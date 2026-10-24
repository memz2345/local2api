// lib/services/lab/dsh_web_rpc.dart
//
// 直接给 **dsh web 进程** 回一条提问（`userQuestions/answer` RPC）。
//
// 为什么需要它：web 会话的提问走 dsh 的 ask_user_question 工具，答案只能
// 从 dsh 的客户端通道送回去，没有 stdin 可写。dsh 的浏览器通道是：
//   1. 启动日志里的 `?token=...` 换一个签名 cookie（GET /，303）；
//   2. POST /api/userQuestions/answer，body 是 Connection RPC 信封：
//      {type: client-request, rpcId, method, payload: {args: {...}}}
// 这里用 Dart HttpClient 复刻这两步，通知里输入的回答就能真正回到模型。
//
// 失败一律返回 false，调用方负责提示用户去 web 回答；不能因为 RPC 失败
// 影响 dsh 本身。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'dsh_service.dart';

/// 一条问题答案（dsh 的 AskUserQuestionAnswerItem）。
class DshQuestionAnswer {
  const DshQuestionAnswer({
    required this.id,
    this.selected = const <String>[],
    this.custom,
  });

  final String id;
  final List<String> selected;
  final String? custom;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'selected': selected,
    if (custom != null && custom!.isNotEmpty) 'custom': custom,
  };
}

class DshWebRpc {
  DshWebRpc._();

  static final DshWebRpc instance = DshWebRpc._();

  String? _cookie;
  String? _cookieOrigin;

  static final Random _random = Random.secure();

  static String _rpcId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 从 [DshService.instance.openUrl] 取地址并回答；没跑 dsh 就返回 false。
  Future<bool> answerQuestionFromDsh({
    required String sessionId,
    required String callId,
    required List<DshQuestionAnswer> answers,
  }) {
    final open = DshService.instance.openUrl;
    final uri = Uri.tryParse(open);
    if (uri == null || uri.host.isEmpty) return Future<bool>.value(false);
    return answerQuestion(
      tokenUrl: uri,
      sessionId: sessionId,
      callId: callId,
      answers: answers,
    );
  }

  /// 回答一条 dsh web 会话里的提问。
  ///
  /// [tokenUrl] 是 dsh 启动日志里带 `?token=` 的地址；测试里可以直接传一个
  /// 本地假服务器的地址。
  @visibleForTesting
  Future<bool> answerQuestion({
    required Uri tokenUrl,
    required String sessionId,
    required String callId,
    required List<DshQuestionAnswer> answers,
  }) async {
    final origin = '${tokenUrl.scheme}://${tokenUrl.host}:${tokenUrl.port}';
    try {
      var cookie = await _cookieFor(tokenUrl);
      if (cookie == null) {
        debugPrint('[dsh-rpc] no browser cookie from $origin');
        return false;
      }
      var result = await _postAnswer(
        origin: origin,
        cookie: cookie,
        sessionId: sessionId,
        callId: callId,
        answers: answers,
      );
      if (result == _authExpired) {
        _cookie = null;
        _cookieOrigin = null;
        cookie = await _cookieFor(tokenUrl);
        if (cookie == null) return false;
        result = await _postAnswer(
          origin: origin,
          cookie: cookie,
          sessionId: sessionId,
          callId: callId,
          answers: answers,
        );
      }
      return result == _ok;
    } catch (e) {
      debugPrint('[dsh-rpc] answer failed: $e');
      return false;
    }
  }

  static const int _ok = 1;
  static const int _failed = 0;
  static const int _authExpired = 2;

  Future<String?> _cookieFor(Uri tokenUrl) async {
    if (tokenUrl.queryParameters['token'] == null ||
        tokenUrl.queryParameters['token']!.isEmpty) {
      return null;
    }
    final origin = '${tokenUrl.scheme}://${tokenUrl.host}:${tokenUrl.port}';
    if (_cookie != null && _cookieOrigin == origin) return _cookie;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.getUrl(tokenUrl);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      await response.drain<void>();
      String? cookie;
      response.headers.forEach((name, values) {
        if (name.toLowerCase() != HttpHeaders.setCookieHeader) return;
        for (final value in values) {
          final first = value.split(';').first.trim();
          if (first.startsWith('dsh-auth-') && first.contains('=')) {
            cookie = first;
          }
        }
      });
      if (cookie == null) {
        debugPrint(
          '[dsh-rpc] token exchange HTTP ${response.statusCode}, no cookie',
        );
        return null;
      }
      _cookie = cookie;
      _cookieOrigin = origin;
      debugPrint('[dsh-rpc] browser cookie acquired from $origin');
      return cookie;
    } finally {
      client.close(force: true);
    }
  }

  Future<int> _postAnswer({
    required String origin,
    required String cookie,
    required String sessionId,
    required String callId,
    required List<DshQuestionAnswer> answers,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.postUrl(
        Uri.parse('$origin/api/userQuestions/answer'),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.cookieHeader, cookie);
      request.write(
        jsonEncode(<String, Object?>{
          'type': 'client-request',
          'rpcId': _rpcId(),
          'method': 'userQuestions/answer',
          'payload': <String, Object?>{
            'args': <String, Object?>{
              'agentId': sessionId,
              'callId': callId,
              'answer': <String, Object?>{
                'answers': [for (final answer in answers) answer.toJson()],
              },
            },
          },
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint('[dsh-rpc] auth expired (HTTP ${response.statusCode})');
        return _authExpired;
      }
      if (response.statusCode != 200) {
        debugPrint(
          '[dsh-rpc] HTTP ${response.statusCode}: '
          '${text.length > 300 ? text.substring(0, 300) : text}',
        );
        return _failed;
      }
      final decoded = jsonDecode(text);
      final result = decoded is Map ? decoded['result'] : null;
      if (result is Map && result['ok'] == true) {
        debugPrint('[dsh-rpc] answer delivered for $sessionId/$callId');
        return _ok;
      }
      final error = result is Map ? result['error'] : null;
      debugPrint(
        '[dsh-rpc] answer rejected: '
        '${error is Map ? '${error['code']}: ${error['message']}' : result}',
      );
      return _failed;
    } finally {
      client.close(force: true);
    }
  }
}
