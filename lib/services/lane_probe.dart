import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/proxy_config.dart';
import 'proxy_server.dart' show ProxyServer;
import 'zen/zen_plan.dart';
import 'zen/zen_protocol.dart';

/// 一条车道的探测结论。
enum LaneVerdict {
  /// 没探测过。
  unknown,

  /// 200，真的能出字。
  usable,

  /// 上游明说这条不给外部客户端用。代理已会补桌面客户端指纹，
  /// 还落到这一档就说明是真被关在官方客户端内。
  restricted,

  /// 免费额度打到上限（429）。等一会儿会恢复，不是模型坏了。
  throttled,

  /// 被上游按本机出口地区拦掉（403 RegionError）。换出口即可，与车道本身无关。
  regionBlocked,

  /// 上游明说这个模型不可用 —— 只有这一档该把车道从选择器里摘掉。
  unavailable,

  /// 其它失败：4xx/5xx。
  failed,

  /// 设备根本连不上端点（DNS / 超时 / 断网），没拿到任何 HTTP 状态。
  unreachable,
}

class LaneProbe {
  final String model;
  final LaneVerdict verdict;
  final int? status;
  final String? detail;

  /// 请求往返耗时（毫秒）—— 代理节点选择器里那个「延迟」的对应物。
  final int? delayMs;

  const LaneProbe(
    this.model,
    this.verdict, {
    this.status,
    this.detail,
    this.delayMs,
  });
}

/// 探测结果按车道名共享：发现页的档案卡和车道列表页看同一份数据，
/// 进页面再返回不会丢，也不用在两处之间传参。
class LaneProbeResults extends ChangeNotifier {
  final Map<String, LaneProbe> _byLane = {};
  final Set<String> _testing = {};

  LaneProbe? of(String lane) => _byLane[lane];

  /// 按给定车道顺序取结果，没测过的位置留空。
  List<LaneProbe?> forLanes(Iterable<String> lanes) => [
    for (final l in lanes) _byLane[l],
  ];

  /// [key] 是发起方自己的标识（档案 id），只用于让 UI 显示「探测中」。
  bool isTesting(String key) => _testing.contains(key);

  void setTesting(String key, bool on) {
    final changed = on ? _testing.add(key) : _testing.remove(key);
    if (changed) notifyListeners();
  }

  void put(Iterable<LaneProbe> probes) {
    for (final p in probes) {
      _byLane[p.model] = p;
    }
    notifyListeners();
  }

  void clear() {
    _byLane.clear();
    _testing.clear();
    notifyListeners();
  }
}

final LaneProbeResults laneProbeResults = LaneProbeResults();

/// 设备侧的车道探测。
///
/// 可用性必须由真实客户端来判定：同一端点对 curl 放行、对某些脚本 UA 直接 403，
/// 而且 Zen 的免费车道策略会变。写死一份「能用清单」迟早是错的。
class LaneProbeService {
  /// 单条车道探测的超时。整个探测是串行的，避免对上游造成突发压力。
  static const Duration _probeTimeout = Duration(seconds: 25);

  /// 连续几条车道「连响应头都没拿到」就判定设备连不上端点，提前停止。
  static const int _maxConnectFails = 3;

  /// 探一批车道并把结果写进共享存储。
  ///
  /// [key] 用于 `isTesting`，一般传档案 id。
  static Future<void> probe({
    required String key,
    required String baseUrl,
    required List<String> lanes,
    String apiKey = '',
  }) async {
    if (lanes.isEmpty) return;
    laneProbeResults.setTesting(key, true);
    try {
      laneProbeResults.put(
        await probeLanes(baseUrl: baseUrl, lanes: lanes, apiKey: apiKey),
      );
    } finally {
      laneProbeResults.setTesting(key, false);
    }
  }

  static Future<List<LaneProbe>> probeLanes({
    required String baseUrl,
    required List<String> lanes,
    String apiKey = '',
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..autoUncompress = false;
    final out = <LaneProbe>[];
    try {
      for (var i = 0; i < lanes.length; i++) {
        out.add(await _probeOne(client, baseUrl, lanes[i], apiKey));
        // 连响应头都没拿到 = 设备根本连不上端点，后面几条不必再各等一遍超时
        if (out.where((p) => p.status == null).length >= _maxConnectFails) {
          for (final rest in lanes.sublist(i + 1)) {
            out.add(LaneProbe(rest, LaneVerdict.unreachable));
          }
          break;
        }
      }
    } finally {
      client.close(force: true);
    }
    return out;
  }

  static Future<LaneProbe> _probeOne(
    HttpClient client,
    String baseUrl,
    String lane,
    String apiKey,
  ) async {
    // 判定模型不产文本，不用出网就知道它接不了聊天请求。
    final rejection = zenLaneRejection(lane);
    if (rejection != null) {
      return LaneProbe(lane, LaneVerdict.unavailable, detail: rejection);
    }

    final stub = Upstream(
      id: 'probe',
      name: 'probe',
      baseUrl: baseUrl,
      apiKey: apiKey,
    );
    final ping = <String, dynamic>{
      'model': lane,
      'messages': [
        {'role': 'user', 'content': 'ok'},
      ],
      'max_tokens': 8,
    };
    // 探测和真实转发必须走同一套构造：上一版就是因为探测没带指纹，
    // 把「我们没声明客户端身份」误判成了「上游不给这个客户端用」。
    final plan = zenPlan(
      upstream: stub,
      lane: lane,
      publicName: lane,
      requestPath: '/v1/chat/completions',
      clientJson: ping,
    );
    final headers = plan?.headers;

    final sw = Stopwatch()..start();
    try {
      final req = await client
          .postUrl(
            ProxyServer.buildUpstreamUri(
              stub,
              plan?.path ?? '/v1/chat/completions',
              '',
            ),
          )
          .timeout(_probeTimeout);
      req.headers.contentType = ContentType.json;
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final key = apiKey.trim();
      if (headers == null && key.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      }
      headers?.forEach((name, value) => req.headers.set(name, value));
      req.add(plan?.body ?? utf8.encode(jsonEncode(ping)));

      final res = await req.close().timeout(_probeTimeout);
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(_probeTimeout, onTimeout: () => '');
      final code = res.statusCode;
      final delay = sw.elapsedMilliseconds;
      if (code == 200) {
        return LaneProbe(
          lane,
          LaneVerdict.usable,
          status: code,
          delayMs: delay,
        );
      }
      final failure = zenClassify(code, body, retryAfterSec: _retryAfter(res));
      return LaneProbe(
        lane,
        _verdictOf(failure),
        status: code,
        detail: _brief(failure.message.isEmpty ? body : failure.message),
        delayMs: delay,
      );
    } catch (e) {
      return LaneProbe(lane, LaneVerdict.unreachable, detail: _brief('$e'));
    }
  }

  /// 上游拒绝的原因 → 探测结论。额度打满与地区受限都会自行恢复或换出口就好，
  /// 和「这条车道坏了」是三件事，不能在 UI 上糊成同一个红色。
  static LaneVerdict _verdictOf(ZenFailure failure) => switch (failure.code) {
    ZenFailureCode.region => LaneVerdict.regionBlocked,
    ZenFailureCode.throttled => LaneVerdict.throttled,
    ZenFailureCode.restricted => LaneVerdict.restricted,
    ZenFailureCode.unavailable => LaneVerdict.unavailable,
    _ => LaneVerdict.failed,
  };

  static int _retryAfter(HttpClientResponse res) {
    final raw = int.tryParse(res.headers.value('retry-after') ?? '') ?? 0;
    return raw > 0 && raw < 3600 ? raw : 0;
  }

  static String _brief(String s) {
    s = s.replaceAll('\n', ' ').trim();
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }
}
