// lib/services/anthropic/anthropic_upstream.dart
//
// Anthropic Messages 上游（DeepSeek 的 `/anthropic` 入口、Claude 官方 API、
// 以及任何说这一套协议的网关）的适配层。
//
// 客户端永远只会说 OpenAI chat.completions，所以这里做两件事：
//   1. 出站：把 chat.completions 请求体重编码成 Anthropic Messages 请求体；
//   2. 入站：由 [ZenTranslator] 把 Messages 的 SSE / 整份 JSON 回译成
//      chat.completion（含 tool_calls、reasoning、usage）。
//
// 出站转换直接复用 Zen 车道的 [zenBuildBody]（wire = messages）——那份映射
// 已经在真实网关上验证过 system / 图片 / tool_use / tool_result 这些块形状，
// 没必要再写第二份。差异只有三处，都在 [buildAnthropicHop] 里补齐：
//   · Zen 把版本号放在 body 的 `anthropic_version`（Bedrock 习惯），
//     Anthropic 官方与 DeepSeek 认的是 `anthropic-version` 请求头；
//   · stream 由客户端决定（Zen 那边为了指纹门必须强制 true）；
//   · 鉴权用 `x-api-key`（DeepSeek 同时认 Bearer，但官方 Anthropic 只认前者）。

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../models/proxy_config.dart';
import '../../models/thinking_level.dart';
import '../zen/zen_convert.dart';
import '../zen/zen_protocol.dart';
import '../zen/zen_stream.dart';

/// Anthropic Messages 协议版本头。DeepSeek 会忽略它，官方 API 必须带。
const String kAnthropicVersion = '2023-06-01';

/// Anthropic 端点在「客户端形状路径」里的写法。真正的 URL 由
/// `ProxyServer.buildUpstreamUri` 拼 baseUrl 时归一化（base 以 /v1 结尾
/// 时会自动去掉这一段，避免出现 /v1/v1/messages）。
const String kAnthropicMessagesPath = '/v1/messages';

final Random _rng = Random.secure();

String _replyId() =>
    'chatcmpl-${List.generate(16, (_) => _rng.nextInt(16)).map((b) => b.toRadixString(16)).join()}';

/// 一条 Anthropic 车道的转发方案。
class AnthropicHop {
  const AnthropicHop({
    required this.path,
    required this.body,
    required this.headers,
    required this.translator,
  });

  final String path;
  final Uint8List body;
  final Map<String, String> headers;

  /// 回译器：Messages → chat.completion。客户端要流式就逐帧写 SSE，
  /// 要整份 JSON 就攒完再回灌。
  final ZenTranslator translator;
}

/// 把一份 OpenAI chat.completions 请求体翻译成 Anthropic Messages 请求体。
///
/// [clientStream] 是**客户端**要不要流式：Anthropic 两端都支持，直接照抄，
/// 不做 Zen 那种「上游强制流式」的处理。
Map<String, dynamic> buildAnthropicBody({
  required String target,
  required Map<String, dynamic> clientJson,
  required bool clientStream,
  ThinkingLevel? level,
  int capacity = 0,
}) {
  final body = zenBuildBody(
    wire: ZenWire.messages,
    lane: target,
    clientJson: clientJson,
    level: level,
    capacity: capacity,
  );
  // Bedrock 习惯的字段：官方 / DeepSeek 都不认（未知字段可能直接 400）。
  body.remove('anthropic_version');
  body['stream'] = clientStream;

  // Zen 那份映射刻意只带「验证过」的字段；对外做通用 Anthropic 网关时，
  // 采样参数与停止词是客户端常用项，得按 Anthropic 的名字补上。
  for (final key in const ['temperature', 'top_p', 'top_k']) {
    final value = clientJson[key];
    if (value is num) body[key] = value;
  }
  final stop = clientJson['stop'];
  if (stop is String && stop.isNotEmpty) {
    body['stop_sequences'] = [stop];
  } else if (stop is List) {
    final seqs = stop.whereType<String>().where((s) => s.isNotEmpty).toList();
    if (seqs.isNotEmpty) body['stop_sequences'] = seqs;
  }

  // OpenAI tool_choice → Anthropic tool_choice：
  //   auto → auto / none → none / required → any
  //   {type:function, function:{name}} → {type:tool, name}
  final toolChoice = clientJson['tool_choice'];
  if (toolChoice is String) {
    switch (toolChoice) {
      case 'auto':
        body['tool_choice'] = {'type': 'auto'};
      case 'none':
        body['tool_choice'] = {'type': 'none'};
      case 'required':
        body['tool_choice'] = {'type': 'any'};
    }
  } else if (toolChoice is Map<String, dynamic>) {
    final fn = toolChoice['function'];
    final name = fn is Map<String, dynamic> ? fn['name'] : null;
    if (name is String && name.isNotEmpty) {
      body['tool_choice'] = {'type': 'tool', 'name': name};
    }
  }
  return body;
}

/// 为一条 Anthropic 车道出转发方案。
AnthropicHop buildAnthropicHop({
  required Upstream upstream,
  required String lane,
  required String publicName,
  required Map<String, dynamic> clientJson,
  ThinkingLevel? level,
  int capacity = 0,
}) {
  final clientStream = clientJson['stream'] == true;
  final key = upstream.apiKey.trim();
  return AnthropicHop(
    path: kAnthropicMessagesPath,
    body: Uint8List.fromList(
      utf8.encode(
        jsonEncode(
          buildAnthropicBody(
            target: lane,
            clientJson: clientJson,
            clientStream: clientStream,
            level: level,
            capacity: capacity,
          ),
        ),
      ),
    ),
    headers: {
      'anthropic-version': kAnthropicVersion,
      if (key.isNotEmpty) 'x-api-key': key,
      // 客户端要流式就让上游直接吐 SSE；要整份 JSON 就等它攒完再回译。
      'accept': clientStream ? 'text/event-stream' : 'application/json',
    },
    translator: ZenTranslator(
      wire: ZenWire.messages,
      rename: const <String, String>{},
      model: publicName,
      stream: clientStream,
      id: _replyId(),
      createdSeconds: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ),
  );
}

/// Anthropic `/v1/models` 的鉴权头。
Map<String, String> anthropicCatalogHeaders(String apiKey) {
  final key = apiKey.trim();
  return {
    'anthropic-version': kAnthropicVersion,
    if (key.isNotEmpty) 'x-api-key': key,
    HttpHeaders.acceptEncodingHeader: 'identity',
  };
}

/// DeepSeek 的 Anthropic base 是 `<origin>/anthropic`，模型清单仍挂在
/// OpenAI 兼容的 `<origin>/v1/models` 上。返回 null 表示这条 base 没有
/// 这种「去掉 /anthropic 再问一次」的退路。
String? anthropicCatalogFallbackBase(String baseUrl) {
  var base = baseUrl.trim();
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  final lower = base.toLowerCase();
  if (!lower.endsWith('/anthropic')) return null;
  return base.substring(0, base.length - '/anthropic'.length);
}
