/// OpenCode Zen 免密车道的线协议事实：哪些模型走哪个端点、请求要长什么样、
/// 上游的拒绝该怎么分类。
///
/// 每一条都对照两份上游实现核对过（dsh-our-free-model 的 src/upstream.js、
/// 它的 Go 移植 zen-gate 的 internal/lane/*）。这个网关靠客户端指纹放行，
/// 裸 OpenAI 请求一律 403 FreeTierError，只有 space-bunny-free 例外。
///
/// 2026-10 起指纹门多了一道：`ses_` 会话 id 的前缀必须是「取反时间戳」
/// 公式铸出来的（纯哈希前缀直接 403「需要官方客户端」）。铸造与校验在
/// zen_ids.dart，修复依据是 9router PR #4782 与 opencode2api#68 的同一发现，
/// 并经真网 curl 矩阵验证：前缀合公式 → 200（24h 前的时间戳也放行），
/// 纯哈希前缀 → 403，`msg_` 前缀则完全不校验。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/proxy_config.dart';

/// 一条车道说哪种线协议。systemone 是判定模型，不产文本，不能接聊天请求。
enum ZenWire { chat, responses, messages, systemone }

/// 网关的 User-Agent 下限是 1.17；Dart 的默认 UA 过不了这道检查。
const String kZenClientUa = 'opencode/1.18.31';

/// 免费档指纹门要求 body.tools 必须声明的小写四件套。
const List<String> kZenFingerprintTools = ['bash', 'glob', 'grep', 'read'];

/// 免密网关的 host 白名单。测试里把回环 mock 的 host 加进来，
/// 才能不碰外网就验证整条转发路径（参考实现同样用可覆盖的 base 地址留这个缝）。
@visibleForTesting
final Set<String> zenGatewayHosts = {'opencode.ai'};

/// 不带 `-free` 后缀但同样免密的车道。
///
/// `space-bunny-free` 名字里本来就有 free（列进来只是为了跟参考实现保持一致，
/// 后缀正则本来也能命中它）；`union-alpha` 是 Messages 线那条免密档；
/// `big-pickle` 是 2026-10-22 从上游 `/zen/v1/models` 实时清单确认的免密
/// 车道（我们自己的实测与上游目录都还在，之前因 zen-gate 目录缺它被误摘）。
const Set<String> _alwaysFree = {
  'union-alpha',
  'space-bunny-free',
  'big-pickle',
};

const Set<String> _responsesModels = {
  'muse-spark-1.2-contributor-free',
  'muse-spark-1.3-contributor-free',
};

const Set<String> _messagesModels = {'union-alpha'};

final RegExp _freeLaneRe = RegExp(r'(?:^|[-_])free(?:$|[-_.])');
final RegExp _museSparkRe = RegExp(
  r'^muse[-_]?spark(?:$|[-_:.\s])',
  caseSensitive: false,
);
final RegExp _systemOneRe = RegExp(r'^jev');
final RegExp _effortSuffixRe = RegExp(r'\([^()]+\)\s*$');

/// 剥掉尾部的 `(档位)` 思考后缀，让查表命中基础 id。
String zenBaseId(String model) =>
    model.trim().replaceFirst(_effortSuffixRe, '').trim();

String _lastSegment(String id) {
  final i = id.lastIndexOf('/');
  return i < 0 ? id : id.substring(i + 1);
}

/// 这条车道由哪个线协议服务。
ZenWire zenWireFor(String model) {
  final base = zenBaseId(model);
  if (_responsesModels.contains(base) ||
      _museSparkRe.hasMatch(_lastSegment(base))) {
    return ZenWire.responses;
  }
  if (_messagesModels.contains(base)) return ZenWire.messages;
  if (_systemOneRe.hasMatch(base)) return ZenWire.systemone;
  return ZenWire.chat;
}

/// 转发时用的「客户端形状」路径：交给 ProxyServer.buildUpstreamUri 拼成真实
/// 端点（baseUrl 末尾带 /v1 时它会把 /v1 摘掉），所以这里不自己造 URI。
String zenClientPathFor(ZenWire wire) => switch (wire) {
  ZenWire.chat => '/v1/chat/completions',
  ZenWire.responses => '/v1/responses',
  ZenWire.messages => '/v1/messages',
  ZenWire.systemone => '/v1/systemone',
};

ZenWire zenWireForClientPath(String path) {
  if (path.endsWith('/responses')) return ZenWire.responses;
  if (path.endsWith('/messages')) return ZenWire.messages;
  return ZenWire.chat;
}

/// 这条 id 是不是免密车道：上游清单混着付费 id，只有这些不用个人 Key 就答。
bool zenIsFreeLane(String model) {
  final base = zenBaseId(model);
  return _alwaysFree.contains(base) || _freeLaneRe.hasMatch(base);
}

/// 清单 → 能被普通客户端当聊天模型用的车道：滤掉付费 id 与判定模型，按基础 id 去重。
List<String> zenFilterUsableLanes(Iterable<String> ids) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in ids) {
    final id = raw.trim();
    if (id.isEmpty || !zenIsFreeLane(id)) continue;
    final base = zenBaseId(id);
    if (zenWireFor(base) == ZenWire.systemone) continue;
    if (seen.add(base)) out.add(base);
  }
  return out;
}

/// 网关靠这组头认出「这是真的桌面客户端」。`Bearer public` 是这条车道本身的
/// 公开免密额度，不是任何人的私人密钥。
Map<String, String> zenHeaders({
  required String session,
  required String requestId,
  required bool stream,
  String? accept,
}) => {
  HttpHeaders.contentTypeHeader: 'application/json',
  HttpHeaders.authorizationHeader: 'Bearer public',
  HttpHeaders.userAgentHeader: kZenClientUa,
  'x-opencode-client': 'desktop',
  'x-opencode-session': session,
  'x-opencode-request': requestId,
  'x-opencode-project': 'global',
  HttpHeaders.acceptHeader: accept ?? (stream ? 'text/event-stream' : '*/*'),
};

/// 上游拒绝的归类。判定顺序照参考实现：先看 payload 里的错误名，再看状态码——
/// 前置代理那句通用的 503 "Service Unavailable" 不该被读成「这个模型没了」，
/// 它吐回来的一整张 HTML 错误页同样不该被读成「凭据失效」（见 [zenClassify]）。
enum ZenFailureCode {
  none,

  /// 出口地区被拦（403 RegionError）。不是模型的问题，换出口就好。
  region,

  /// 免费额度打到上限（429 FreeUsageLimitError）。同一 session 下换模型也是白换。
  throttled,

  /// 仍然被当伪造客户端（403 FreeTierError）：指纹没凑齐。
  restricted,

  /// 鉴权类失败。
  credential,

  /// 上游明说这个模型不可用 —— 只有这一类有资格把车道从选择器里摘掉。
  unavailable,

  /// 请求自己的问题（4xx，除 408/425）：重放同一份 body 必然得到同一句拒绝。
  /// 与 [server] 分开就是为了不让路由在整条回退链上连环重试把车道烧穿。
  client,

  server,
  transport,
  empty,
}

class ZenFailure {
  final ZenFailureCode code;
  final int? status;
  final String message;
  final int retryAfterSec;

  const ZenFailure(
    this.code, {
    this.status,
    this.message = '',
    this.retryAfterSec = 0,
  });

  bool get isThrottled => code == ZenFailureCode.throttled;
}

final RegExp _regionRe = RegExp(
  r'RegionError|not available in your country|region.?block',
  caseSensitive: false,
);
final RegExp _quotaRe = RegExp(
  r'FreeUsageLimitError|usage limit|rate limit',
  caseSensitive: false,
);
final RegExp _restrictedRe = RegExp(
  r'FreeTierError|within OpenCode|free tier',
  caseSensitive: false,
);
final RegExp _modelErrRe = RegExp(
  r'ModelError|ModelDeprecated|model is unavailable|model is not supported|'
  r'not supported|has been deprecated|is deprecated|Endpoint is unavailable',
  caseSensitive: false,
);

/// 前置代理吐回来的 HTML 错误页。状态码本身会把它归错档：WAF 的 403 不是
/// 凭据坏了，它的 413 也不是调用方重发一次就能修好的 —— 而整页 markup 里
/// 唯一有用的事实（说话的是哪一跳）反而被埋住了。所以先认页面，再谈状态码。
final RegExp _htmlPageRe = RegExp(
  r'^\s*<(!doctype|html[\s>])',
  caseSensitive: false,
);

bool _isHtmlPage(String payload) =>
    _htmlPageRe.hasMatch(payload) ||
    payload.contains('with an HTML error page');

/// HTML 错误页的专用提示：不引用页面本身（那是噪音），只点名是哪一跳、
/// 以及为什么不该换道重试。
const String kZenHtmlPageHint =
    '网关的前置代理回了一张 HTML 错误页 —— 通常是网关前面的 WAF 或请求体大小'
    '限制，不是凭据问题；请求根本没被送到任何模型面前，重放同一份 body 只会'
    '得到同一张页，所以换道重试没有意义。如果这发生在一段很长的对话上，'
    '触发点很可能就是请求体大小。';

/// 429 没带 `Retry-After` 时的默认冷却秒数。刻意**短**。
///
/// 理由照 zen-gate `internal/lane/throttle.go:29-46` 的原文注释：
/// 这条车道的免费池是**一份全球共享的凭据**（`Bearer public`），所以一个 429
/// 报的是「此刻拥挤」，不是这个模型的持久属性。2026-10-11 实测：
/// space-bunny-free 与 longcat-2.5-preview-free 都回过 429，也都在两分钟内
/// 重新回 200；92 次记录在案的 throttle 事件里最短的一次 0.6 秒就恢复了。
/// 冷却 60 秒等于为一个通常几秒就散的状况去惩罚模型 —— 而候选选择器会跳过
/// 被标记节流的车道，于是客户端看到整条 `zen-free` 一分钟不可用，这就是用户
/// 体感的「又失效了」。重试不消耗额度（被拒的请求不计量），所以便宜的方向
/// 是短冷却。
const int kZenThrottleDefaultSec = 10;

ZenFailure zenClassify(int? status, String payload, {int retryAfterSec = 0}) {
  final brief = payload.replaceAll('\n', ' ').trim();
  final msg = brief.length > 200 ? '${brief.substring(0, 200)}…' : brief;
  ZenFailure make(
    ZenFailureCode code, {
    int? retry,
    String? message,
  }) => ZenFailure(
    code,
    status: status,
    message: message ?? msg,
    retryAfterSec: retry ?? 0,
  );

  // 判定顺序照 zen-gate `internal/lane/http.go:25-88` 的 ClassifyFailure：
  // payload 模式先于状态码。
  if (_regionRe.hasMatch(payload)) return make(ZenFailureCode.region);
  if (status == 429 || _quotaRe.hasMatch(payload)) {
    return make(
      ZenFailureCode.throttled,
      retry: retryAfterSec == 0 ? kZenThrottleDefaultSec : retryAfterSec,
    );
  }
  // 必须排在 401/403 之前：WAF 的 HTML 403 会被误读成凭据失效，进而把整条
  // 车道标红；而前置代理是在任何模型被问之前就把请求挡掉的，换道只会再收
  // 一张同样的页。
  if (_isHtmlPage(payload)) {
    return make(
      ZenFailureCode.client,
      message: status == null
          ? kZenHtmlPageHint
          : '$kZenHtmlPageHint（HTTP $status）',
    );
  }
  if (status == 403 && _restrictedRe.hasMatch(payload)) {
    return make(ZenFailureCode.restricted);
  }
  if (status != null && status >= 500) return make(ZenFailureCode.server);
  // 上游点名说这个 id 没了：`Model X is not supported`（401）、
  // `Model X has been deprecated`（410）。这是**车道下架**，不是凭据问题 ——
  // 归到 unavailable 才能被探测摘掉、被路由跳过去。免密车道上下架很频繁，
  // 这一步之前 401 一律当 credential，于是下架的车道在 UI 上永远红着。
  // 我方有真网实测注释，这一条比 zen-gate 把它归 credential 更准，保留。
  if (_modelErrRe.hasMatch(payload)) return make(ZenFailureCode.unavailable);
  if (status == 401 || status == 403) return make(ZenFailureCode.credential);
  if (status == 404 || status == 400 || status == 422) {
    return make(ZenFailureCode.unavailable);
  }
  // 其余 4xx 是请求自己的问题：重放同一份 body 必然得到同一句拒绝。归到
  // server 会让路由把它当「上游一时抽风」，在整条回退链上连环重试烧穿车道。
  // 408 / 425 是例外 —— 它们说的是网关自己的时序问题，重发可能给出不同结果。
  if (status != null && status >= 400 && status != 408 && status != 425) {
    return make(ZenFailureCode.client);
  }
  return make(ZenFailureCode.server);
}

/// 这个上游是不是 Zen 免密网关。用推断而不是持久字段：手填这个地址的用户
/// 直接就该能用，配置结构也不用跟着加一次迁移。
extension ZenUpstreamX on Upstream {
  bool get isZenGateway {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null) return false;
    return zenGatewayHosts.contains(uri.host.toLowerCase()) &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.first == 'zen';
  }
}
