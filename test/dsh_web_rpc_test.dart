// test/dsh_web_rpc_test.dart
//
// 验证通知回复真正能送回 dsh web：
//   1. 带 ?token= 的 GET 换 dsh-auth-* cookie；
//   2. POST /api/userQuestions/answer 的信封是
//      {type: client-request, rpcId, method, payload:{args:{agentId,callId,answer}}};
//   3. cookie 过期（401）会重新换一次 token 再试。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/lab/dsh_web_rpc.dart';

void main() {
  late HttpServer server;
  late int tokenExchanges;
  late int posts;
  late Map<String, dynamic> lastPost;
  late String? lastCookie;
  var rejectOnce = false;
  var rejectResult = false;

  setUp(() async {
    tokenExchanges = 0;
    posts = 0;
    lastPost = <String, dynamic>{};
    lastCookie = null;
    rejectOnce = false;
    rejectResult = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.method == 'GET' && request.uri.path == '/') {
        tokenExchanges++;
        request.response.statusCode = HttpStatus.seeOther;
        request.response.headers.set(
          HttpHeaders.setCookieHeader,
          'dsh-auth-test=abc123; Path=/; HttpOnly',
        );
        request.response.headers.set(HttpHeaders.locationHeader, './');
        await request.response.close();
        return;
      }
      if (request.method == 'POST' &&
          request.uri.path == '/api/userQuestions/answer') {
        posts++;
        lastCookie = request.headers.value(HttpHeaders.cookieHeader);
        final raw = await utf8.decoder.bind(request).join();
        lastPost = jsonDecode(raw) as Map<String, dynamic>;
        if (rejectOnce) {
          rejectOnce = false;
          request.response.statusCode = HttpStatus.unauthorized;
          await request.response.close();
          return;
        }
        final rpcId = lastPost['rpcId'];
        request.response.headers.contentType = ContentType.json;
        if (rejectResult) {
          request.response.write(
            jsonEncode(<String, Object?>{
              'type': 'server-response',
              'rpcId': rpcId,
              'result': <String, Object?>{
                'ok': false,
                'error': <String, Object?>{
                  'code': 'session/not-found',
                  'message': 'session gone',
                  'details': <String, Object?>{},
                },
              },
            }),
          );
        } else {
          request.response.write(
            jsonEncode(<String, Object?>{
              'type': 'server-response',
              'rpcId': rpcId,
              'result': <String, Object?>{'ok': true, 'value': true},
            }),
          );
        }
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  Uri tokenUrl() =>
      Uri.parse('http://127.0.0.1:${server.port}/?token=test-token');

  test('换 cookie 并把回答按 dsh RPC 信封送出去', () async {
    final ok = await DshWebRpc.instance.answerQuestion(
      tokenUrl: tokenUrl(),
      sessionId: 'session-abc',
      callId: 'call-1',
      answers: const [
        DshQuestionAnswer(id: 'q1', custom: '老铁的回答'),
        DshQuestionAnswer(id: 'q2'),
      ],
    );

    expect(ok, isTrue);
    expect(tokenExchanges, 1);
    expect(posts, 1);
    expect(lastCookie, contains('dsh-auth-test=abc123'));
    expect(lastPost['type'], 'client-request');
    expect(lastPost['method'], 'userQuestions/answer');
    final payload = lastPost['payload'] as Map<String, dynamic>;
    final args = payload['args'] as Map<String, dynamic>;
    expect(args['agentId'], 'session-abc');
    expect(args['callId'], 'call-1');
    final answer = args['answer'] as Map<String, dynamic>;
    final answers = answer['answers'] as List<dynamic>;
    expect(answers, hasLength(2));
    expect(answers.first, <String, Object?>{
      'id': 'q1',
      'selected': <String>[],
      'custom': '老铁的回答',
    });
    expect(answers.last, <String, Object?>{'id': 'q2', 'selected': <String>[]});
  });

  test('401 时重新换 token 再重试一次', () async {
    rejectOnce = true;
    final ok = await DshWebRpc.instance.answerQuestion(
      tokenUrl: tokenUrl(),
      sessionId: 'session-abc',
      callId: 'call-2',
      answers: const [DshQuestionAnswer(id: 'q1', custom: 'retry')],
    );

    expect(ok, isTrue);
    expect(tokenExchanges, 2);
    expect(posts, 2);
  });

  test('Host 返回 result.ok=false 时返回 false', () async {
    rejectResult = true;
    final ok = await DshWebRpc.instance.answerQuestion(
      tokenUrl: tokenUrl(),
      sessionId: 'session-abc',
      callId: 'call-3',
      answers: const [DshQuestionAnswer(id: 'q1', custom: 'nope')],
    );

    expect(ok, isFalse);
    expect(posts, 1);
  });
}
