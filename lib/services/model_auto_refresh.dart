// lib/services/model_auto_refresh.dart
//
// 上游模型列表的自动更新。
//
// 规则很简单：每个上游带两个字段 —— `autoRefreshHours`（间隔，0 = 关）和
// `modelsRefreshedAtMs`（上次刷新时间）。进程起来时跑一次 [runDue]，把
// 「距上次刷新已超过间隔」的上游挨个拉一遍 `/models`。
//
//   · 内置的 Zen / MiMo：`autoRefreshHours` 默认 7 天、`modelsRefreshedAtMs`
//     是 0 → **首次进入应用就会刷一次**（之后再按 7 天的节奏走）。
//   · 用户在「编辑上游」页里改成别的档位或关掉，照用户的来。
//
// 合并策略：**跟随上游清单，但保住路由条目** ——
//   · 上游有的、我们没的 → 补进来（和发现页「刷新可用模型列表」同一套口径，
//     走 [ProfileService.applyLiveLanes]）；
//   · 我们有的、上游没有的 → 删掉；
//   · 路由条目（Zen 的 `zen-free` 这种「一个名字挂一串回退链」）**永远保留**：
//     它本来就不是上游的模型，只把链里下架的车道摘掉、新车道补到链尾。
//   · 兜底：本地一条都对不上时（典型是 MiMo TTS 的 `/models` 给的是另一
//     维度的东西）**整次跳过**，绝不把用户正在用的模型删光。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/builtin_profiles.dart';
import '../models/proxy_config.dart';
import 'config_store.dart';
import 'profile_service.dart';
import 'proxy_server.dart';

/// 一次自动更新的战果（给 UI 打 toast / 日志用）。
class ModelRefreshResult {
  const ModelRefreshResult({
    required this.upstreamName,
    required this.added,
    required this.removed,
    this.error,
  });

  final String upstreamName;
  final List<String> added;
  final List<String> removed;
  final String? error;

  bool get ok => error == null;

  bool get changed => added.isNotEmpty || removed.isNotEmpty;
}

class ModelAutoRefresh {
  ModelAutoRefresh(this._store);

  final ConfigStore _store;

  bool _running = false;

  Timer? _timer;

  /// 「老配置回填」的一次性门闩。
  static const String _backfillKey = 'local2api.autoRefresh.builtinBackfill.v1';

  /// 起一个轻量巡检：每 [interval] 看一眼有没有到点的上游。
  ///
  /// 桌面端进程常开好几天，只在启动时刷一次的话「7 天一次」根本等不到
  /// 第二次触发。巡检本身不碰网络（[runDue] 会先过 [isDue]）。
  void startWatching({Duration interval = const Duration(minutes: 30)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(runDue()));
  }

  void stopWatching() {
    _timer?.cancel();
    _timer = null;
  }

  /// 给「这个功能上线前就装过内置上游」的老配置补默认间隔。
  ///
  /// 老配置里根本没有 `autoRefreshHours` 这个键，读出来是 0 —— 和「用户主动
  /// 关掉」长得一模一样。这个字段是本次新增的，上线前不可能有人主动设 0，
  /// 所以一次性全补成 [kAutoRefreshHoursBuiltin]；门闩落地后用户再关就关了。
  ///
  /// 返回是否真的改过（调用方据此决定要不要落盘）。
  static Future<bool> backfillBuiltinDefaults(ProxyConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_backfillKey) ?? false) return false;
    await prefs.setBool(_backfillKey, true);
    var changed = false;
    for (final u in config.upstreams) {
      final builtin = u.id == kZenUpstreamId || u.id == kMimoTtsUpstreamId;
      if (!builtin || u.autoRefreshHours != 0) continue;
      u.autoRefreshHours = kAutoRefreshHoursBuiltin;
      changed = true;
    }
    return changed;
  }

  /// 这个上游现在该不该刷新。
  ///
  /// `autoRefreshHours <= 0` 直接否；`modelsRefreshedAtMs == 0`（从没刷过）
  /// 一律当成「该刷」—— 这正是「首次进入应用刷一次」的实现。
  static bool isDue(Upstream u, {DateTime? now}) {
    if (u.autoRefreshHours <= 0) return false;
    if (u.modelsRefreshedAtMs <= 0) return true;
    final t = now ?? DateTime.now();
    final elapsed = t.millisecondsSinceEpoch - u.modelsRefreshedAtMs;
    return elapsed >= u.autoRefreshHours * 3600 * 1000;
  }

  /// 距下次自动更新还有多久；不自动更新返回 null。
  static Duration? untilNext(Upstream u, {DateTime? now}) {
    if (u.autoRefreshHours <= 0) return null;
    if (u.modelsRefreshedAtMs <= 0) return Duration.zero;
    final t = now ?? DateTime.now();
    final due =
        u.modelsRefreshedAtMs + u.autoRefreshHours * 3600 * 1000;
    final left = due - t.millisecondsSinceEpoch;
    return left <= 0 ? Duration.zero : Duration(milliseconds: left);
  }

  /// 把该刷的上游都刷一遍，返回每个上游的战果。
  ///
  /// 静默失败：拉不到（断网 / 密钥过期 / 上游没这个端点）只记进结果，
  /// 不重试、不弹错、**也不更新 `modelsRefreshedAtMs`** —— 下次进应用再试。
  Future<List<ModelRefreshResult>> runDue() async {
    if (_running) return const [];
    _running = true;
    final out = <ModelRefreshResult>[];
    try {
      final config = _store.config;
      // 先快照一遍：刷新过程中用户可能改配置，边遍历边改列表会炸。
      final targets = [
        for (final u in config.upstreams)
          if (isDue(u) && !u.type.isLocal && u.baseUrl.trim().isNotEmpty) u,
      ];
      for (final u in targets) {
        final result = await refreshOne(u, config: config, save: false);
        if (!result.ok) continue;
        out.add(result);
      }
      if (out.isNotEmpty) _store.update(config);
    } finally {
      _running = false;
    }
    return out;
  }

  /// 刷新单个上游并（可选）落盘。[config] 给定时就地改它，不给就用当前配置。
  Future<ModelRefreshResult> refreshOne(
    Upstream u, {
    ProxyConfig? config,
    bool save = true,
  }) async {
    final target = config ?? _store.config;
    try {
      final catalog = await ProxyServer.fetchModelCatalog(u);
      final result = mergeCatalog(u, catalog);
      if (!result.ok) return result;
      u.modelsRefreshedAtMs = DateTime.now().millisecondsSinceEpoch;
      if (save) _store.update(target);
      return result;
    } catch (e) {
      debugPrint('model auto refresh failed for ${u.name}: $e');
      return ModelRefreshResult(
        upstreamName: u.name,
        added: const [],
        removed: const [],
        error: '$e',
      );
    }
  }

  /// 把一次上游清单对账进 [u] 的模型表（**就地改，不落盘**）。
  ///
  /// 「编辑上游」页的「立即刷新」也走这里：页面上还没保存的草稿不能被一次
  /// 刷新偷偷写进配置，但合并口径必须和后台自动更新完全一致。
  static ModelRefreshResult mergeCatalog(Upstream u, ModelCatalog catalog) {
    final before = {for (final m in u.models) m.publicName};
    if (catalog.ids.isEmpty) {
      return ModelRefreshResult(
        upstreamName: u.name,
        added: const [],
        removed: const [],
        error: '上游返回空清单',
      );
    }

    // 安全阀：本地一条都对不上就别照着清单清空。
    //
    // 典型是「`/models` 给的是聊天模型、本地装的是 TTS 音色」这类**压根不是
    // 同一维度**的情况（MiMo TTS 就是这个形状）。宁可这次跳过，也不把用户
    // 正在用的模型删光 —— 真要换成另一套清单，走「编辑上游」手动换。
    final live = catalog.ids.toSet();
    final existingTargets = {
      for (final m in u.models)
        if (!ProfileService.isRoute(m)) m.target,
    };
    if (existingTargets.isNotEmpty && !existingTargets.any(live.contains)) {
      return ModelRefreshResult(
        upstreamName: u.name,
        added: const [],
        removed: const [],
        error: '上游清单与本地模型没有交集（上游 ${catalog.ids.length} 条），已跳过',
      );
    }

    // 合并交给发现页那套对账逻辑（[ProfileService.applyLiveLanes]）：
    // 路由条目（Zen 的 `zen-free`）**永远保留**，只把链里下架的车道摘掉、
    // 新出现的车道补到链尾。自己再写一份必然把路由当「上游没有的模型」删掉。
    ProfileService.applyLiveLanes(u, catalog.ids);

    // 对账只补名字，上下文 / 输出上限还得从这次清单里回填（只填空位，
    // 用户手调过的一律不碰）。
    for (final m in u.models) {
      if (m.contextLength <= 0) {
        final ctx = catalog.contexts[m.target] ?? 0;
        if (ctx > 0) m.contextLength = ctx;
      }
      if (m.maxOutputTokens <= 0) {
        final out = catalog.outputs[m.target] ?? 0;
        if (out > 0) m.maxOutputTokens = out;
      }
    }

    final after = {for (final m in u.models) m.publicName};
    return ModelRefreshResult(
      upstreamName: u.name,
      added: [
        for (final n in after)
          if (!before.contains(n)) n,
      ],
      removed: [
        for (final n in before)
          if (!after.contains(n)) n,
      ],
    );
  }
}
