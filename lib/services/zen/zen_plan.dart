import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../models/proxy_config.dart';
import '../../models/thinking_level.dart';
import 'zen_convert.dart';
import 'zen_fingerprint.dart';
import 'zen_ids.dart';
import 'zen_protocol.dart';
import 'zen_stream.dart';

/// 一条车道实际该怎么发出去、回来了怎么译回来。
class ZenHop {
  ZenHop({
    required this.path,
    required this.body,
    required this.headers,
    required this.wire,
    this.translator,
  });

  /// 转发用的「客户端形状」路径，交给 ProxyServer.buildUpstreamUri 拼真实端点。
  final String path;
  final Uint8List body;
  final Map<String, String> headers;
  final ZenWire wire;

  /// 只有非 chat 线需要回译；chat 线留 null，代理走原样透传。
  final ZenTranslator? translator;
}

/// System One 那类判定模型不产文本，拿聊天请求打过去只会收到莫名的状态码。
/// 目录已经把它滤掉了，这里给手填模型名撞上来的用户一句人话。
String? zenLaneRejection(String lane) {
  if (zenWireFor(lane) != ZenWire.systemone) return null;
  return '$lane 是判定模型（System One）：只在自己的端点上回答结构化决策，'
      '不能接聊天请求。请改用有文本输出的车道。';
}

final String _nul = String.fromCharCode(0);

/// 会话种子。同一个会话的每一轮都要拿到同一个 ses_ —— 免费额度按 session 计，
/// 一次请求一个新 id 会撞 429 且 retry-after 递增。
///
/// OpenAI 客户端不会告诉代理「这是第几号会话」，所以用首条 user 消息加对外模型名
/// 当种子：后续每一轮客户端都会重放开场白，种子自然稳定。代价是两种情况会并到
/// 同一个会话 —— 用户改了开场白（其实是新会话）、局域网里两人发了同一句第一句话
/// （合用一份额度）。比起每请求新铸 id 直接撞墙，这个取舍划算。
String zenConversationSeed(String publicName, Map<String, dynamic> clientJson) {
  final opener = _firstUserText(clientJson['messages']);
  return [publicName, opener].join(_nul);
}

/// 同一回合的重试共用一个 msg_：种子取整个 messages 数组。
/// 不预先摘要 —— zenRequestIdFor 内部就要对它做 sha256，长一点无所谓。
String zenTurnSeed(Map<String, dynamic> clientJson) =>
    jsonEncode(clientJson['messages'] ?? const <Object?>[]);

String _firstUserText(Object? messages) {
  if (messages is! List) return '';
  for (final m in messages.whereType<Map<String, dynamic>>()) {
    if (m['role'] != 'user') continue;
    return _contentText(m['content']);
  }
  return '';
}

String _contentText(Object? content) {
  if (content == null) return '';
  if (content is String) return content;
  if (content is List) {
    return content
        .whereType<Map<String, dynamic>>()
        .where((p) => p['text'] is String)
        .map((p) => p['text'] as String)
        .join();
  }
  return '$content';
}

final Random _rng = Random.secure();

String _replyId() =>
    'chatcmpl-${List.generate(16, (_) => _rng.nextInt(16)).map((b) => b.toRadixString(16)).join()}';

/// 为一条车道出转发方案。返回 null 表示「这条不用适配」，代理走原样透传：
/// 不是 Zen 网关、不是 chat 形状入口、body 不是 JSON、或者根本没有 messages。
///
/// 只适配 /v1/chat/completions 入口是刻意的：/embeddings、/v1/responses 之类
/// 反向适配没在上游验证过，半生不熟的转换比不透传更容易骗人。
ZenHop? zenPlan({
  required Upstream upstream,
  required String lane,
  required String publicName,
  required String requestPath,
  required Map<String, dynamic>? clientJson,
  String? inboundSession,
  int outputCapacity = 0,
  ThinkingLevel? level,
}) {
  if (!upstream.isZenGateway) return null;
  if (requestPath != '/v1/chat/completions') return null;
  final json = clientJson;
  if (json == null || json['messages'] is! List) return null;
  if (zenLaneRejection(lane) != null) return null;

  final wire = zenWireFor(lane);
  // 客户端要不要流式，与上游必须怎么发是两件事：免费档指纹门只放行
  // stream:true（见 zen_convert.dart 的 [kZenUpstreamAlwaysStreams]），
  // 所以上游一律流式，客户端要非流式时再攒成整份 JSON 回灌。
  final clientStream = json['stream'] == true;
  final session = zenSessionFor(
    // 透传要过公式校验：形状对但前缀不是「取反时间戳」的 id（旧版本铸的、
    // 别的代理伪造的）打上去就是 403，不如就地换一个合公式的。
    zenSessionIdUsable(inboundSession)
        ? inboundSession!
        : zenConversationSeed(publicName, json),
  );
  final requestId = zenRequestIdFor(session, zenTurnSeed(json));

  final body = zenBuildBody(
    wire: wire,
    lane: lane,
    clientJson: json,
    // 生效档位：调用方（代理）算好传进来 —— 里面已经含「客户端没发时按上游
    // 配置补的默认档」。没传就自己从请求体里读（reasoning_effort / thinking /
    // 模型名后缀都认，后缀长在客户端发的 model = 对外名上）。
    level: level ?? thinkingLevelOf(json),
    capacity: outputCapacity,
  );
  final rename = zenApplyFingerprint(body, zenStyleFor(wire));

  final headers = zenHeaders(
    session: session,
    requestId: requestId,
    // 上游就是流式，accept 跟着走。
    stream: true,
  );
  // 用户在这条上游上填了自己的 Key 就用他的：付费 Zen 账号不该被降级成公共额度。
  final key = upstream.apiKey.trim();
  if (key.isNotEmpty) headers[HttpHeaders.authorizationHeader] = 'Bearer $key';

  return ZenHop(
    path: zenClientPathFor(wire),
    body: Uint8List.fromList(utf8.encode(jsonEncode(body))),
    headers: headers,
    wire: wire,
    // chat 线且客户端自己也要流式：上游字节原样透传，不多一道转译。
    // 但**有工具改名时必须过转译器**：指纹门会把客户端的 `pwsh` 提升成
    // `bash` 再发给上游，模型回来的 tool_calls 名字也是 `bash`；透传路径
    // 不做还原，调用方按自己的注册表查 `bash` 就是 unknown tool（DSH 在
    // Windows 上实测踩到）。其余（非 chat 线，或 chat 线但客户端要整份
    // JSON）本来就要转译器。
    translator: wire == ZenWire.chat && clientStream && rename.isEmpty
        ? null
        : ZenTranslator(
            wire: wire,
            rename: rename,
            model: publicName,
            stream: clientStream,
            id: _replyId(),
            createdSeconds: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          ),
  );
}
