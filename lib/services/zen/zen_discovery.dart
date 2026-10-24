import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/proxy_config.dart';
import '../proxy_server.dart' show ProxyServer;
import 'zen_protocol.dart';

/// 上游 `/v1/models`（Ollama 走 `/api/tags`）是「现在到底有哪些模型可用」的
/// 权威来源，本地那份 const 目录只当冷启动与断网时的底。
///
/// 写成「发现结果 + 本地兜底」而不是纯动态：上游上新一条车道不用改代码发版，
/// 上游抖动时也不会把已知车道清空 —— OpenCode Zen 那份免密清单本来就
/// 会随上游上下架变动，写死必然过期（这正是 zen-gate 那类网关要动态拉清单
/// 的原因）。
///
/// 缓存按端点地址分开存：[byBaseUrl] 记每个上游拉到的实时清单，
/// [lanes] 只是 Zen 免密网关那一份的快捷视图（老代码路径还在用它）。
class ZenDiscovery extends ChangeNotifier {
  /// 上一次成功发现的 Zen 免密集合；失败或还没拉过时为空。
  List<String> lanes = const [];

  /// 端点地址 -> 该端点最近一次拉到的可用模型清单。
  final Map<String, List<String>> byBaseUrl = {};

  /// 端点地址 -> 最近一次失败原因。
  final Map<String, String> errorsByBaseUrl = {};

  DateTime? refreshedAt;

  /// 最近一次失败的原因（给 UI 如实说明「这次拉到的还是上一次的」）。
  String? lastError;

  bool get hasLanes => lanes.isNotEmpty;

  /// 某个端点拉到过的实时清单；没拉到过返回 null。
  List<String>? lanesOf(String baseUrl) => byBaseUrl[keyFor(baseUrl)];

  /// 某个端点最近一次没拉到的原因；没失败过返回 null。
  String? errorOf(String baseUrl) => errorsByBaseUrl[keyFor(baseUrl)];

  /// 缓存键：同一个端点地址尾部的斜杠不该分成两份。
  static String keyFor(String baseUrl) =>
      baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  /// 拉一个上游的实时模型清单并缓存。
  ///
  /// 走 [ProxyServer.fetchModelCatalog]：OpenAI 兼容 / Ollama / Zen 免密三种
  /// 端点的差异都在那边处理完。失败保留上一次结果 —— 网络抖动不该让车道目录
  /// 忽然变空，返回 null 让调用方知道这次没拉到（**没拉到就不能摘车道**）。
  Future<List<String>?> refreshFor(
    Upstream upstream, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final baseUrl = upstream.baseUrl.trim();
    if (baseUrl.isEmpty) return null;
    final key = keyFor(baseUrl);
    try {
      final catalog = await ProxyServer.fetchModelCatalog(
        upstream,
      ).timeout(timeout);
      final ids = catalog.ids;
      if (ids.isEmpty) {
        errorsByBaseUrl[key] = '清单是空的';
        lastError = errorsByBaseUrl[key];
        notifyListeners();
        return null;
      }
      byBaseUrl[key] = ids;
      errorsByBaseUrl.remove(key);
      if (upstream.isZenGateway) lanes = ids;
      refreshedAt = DateTime.now();
      lastError = null;
      notifyListeners();
      return ids;
    } catch (e) {
      errorsByBaseUrl[key] = _brief('$e');
      lastError = errorsByBaseUrl[key];
      notifyListeners();
      return null;
    }
  }

  static String _brief(String s) {
    s = s.replaceAll('\n', ' ').trim();
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }

  /// 拉一次 Zen 清单（老接口，保留给只关心免密车道的调用方）。
  /// 失败保留上一次结果。
  Future<List<String>> refresh(
    String baseUrl, {
    String apiKey = '',
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final upstream = Upstream(
      id: 'zen-catalog',
      name: 'zen-catalog',
      baseUrl: baseUrl,
      apiKey: apiKey,
    );
    // 非免密网关的规则不该来刷这份清单：拉了也不是它的集合。
    if (!upstream.isZenGateway) return lanes;
    await refreshFor(upstream, timeout: timeout);
    return lanes;
  }

  /// 装一个档案 / 刷新一次时实际要用的车道清单。
  ///
  /// 拉到过这个端点的实时清单就用实时的（任何类型的端点都算，不只是 Zen），
  /// 否则退回调用方给的 [fallback]（档案文档里那份）。
  List<String> lanesFor(String baseUrl, {required List<String> fallback}) {
    final live = lanesOf(baseUrl);
    if (live != null && live.isNotEmpty) return live;
    if (!hasLanes) return fallback;
    final probe = Upstream(
      id: 'zen-lanes',
      name: 'zen-lanes',
      baseUrl: baseUrl,
    );
    return probe.isZenGateway ? lanes : fallback;
  }

  void clear() {
    lanes = const [];
    byBaseUrl.clear();
    errorsByBaseUrl.clear();
    refreshedAt = null;
    lastError = null;
    notifyListeners();
  }
}

final ZenDiscovery zenDiscovery = ZenDiscovery();
