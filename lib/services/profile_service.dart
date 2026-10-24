import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/builtin_profiles.dart';
import '../models/config_profile.dart';
import '../models/proxy_config.dart';
import 'lane_probe.dart';
import 'profile_store.dart';
import 'zen/zen_discovery.dart';
import 'zen/zen_protocol.dart';

/// 一个上游模板装进配置时的结果。
enum MergeOutcome {
  /// 配置里原本没有，新建并认领。
  installed,

  /// 已存在且归属本档案，做了增量合并。
  merged,

  /// id 被别的档案或用户自建的上游占了，没动它。
  conflict,
}

/// 远程订阅更新失败。消息已收敛成用户可读的一行，不是堆栈。
class ProfileUpdateException implements Exception {
  const ProfileUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 配置档案与 ProxyConfig 之间的装配关系。
///
/// 方法一律只改传入的 [ProxyConfig]，落盘由调用方走 ConfigStore.update ——
/// 和原来 PlazaService 的用法一致，免得两处各自写盘互相踩。
class ProfileService {
  /// 远程订阅拉取的超时。
  static const Duration _fetchTimeout = Duration(seconds: 20);

  static Upstream? upstreamOf(ProxyConfig config, String upstreamId) {
    for (final u in config.upstreams) {
      if (u.id == upstreamId) return u;
    }
    return null;
  }

  /// 模板里声明的车道（上游真实模型名，跨条目去重、保序）。
  static List<String> templateLanes(Upstream template) =>
      <String>{for (final m in template.models) ...m.attempts}.toList();

  /// 本次实际要用的车道：上游 `/v1/models` 拉到过就用实时的，否则退回文档那份。
  static List<String> effectiveLanes(Upstream template) => zenDiscovery
      .lanesFor(template.baseUrl, fallback: templateLanes(template));

  /// 模板条目里哪条是「路由」：对外暴露一个名字、内部一条有序回退链。
  /// 车道条目是 publicName == target，路由不是。
  static bool isRoute(ModelEntry m) => m.publicName != m.target;

  // ---- 装配 ----

  /// 把一个上游模板装进配置。
  ///
  /// 增量合并只补缺、不覆盖：用户在车道页做的单条开关与回退链重排必须活下来。
  /// [addedEnabled] 控制新补进来的条目是否直接暴露 —— 正常激活传 true，
  /// 迁移老用户传 false（否则只启用过容灾路由的人升级后会凭空多出十几个对外模型）。
  /// [enableUpstream] 为 false 时完全不碰上游自己的开关 —— 迁移要用：
  /// 用户当初特意关掉的档案，不该因为升级又被打开。
  static MergeOutcome mergeUpstream({
    required ProxyConfig config,
    required Upstream template,
    required String profileId,
    required List<String> lanes,
    required bool addedEnabled,
    bool enableUpstream = true,
  }) {
    final existing = upstreamOf(config, template.id);

    if (existing == null) {
      final fresh = Upstream(
        id: template.id,
        name: template.name,
        type: template.type,
        baseUrl: template.baseUrl,
        note: template.note,
        managedBy: profileId,
        enabled: enableUpstream,
        // 自动更新策略也跟着模板走：丢了这两行，内置 Zen 装进来就是
        // `autoRefreshHours = 0`（永不自动更新），「自带 7 天一次」直接失效。
        autoRefreshHours: template.autoRefreshHours,
        modelsRefreshedAtMs: template.modelsRefreshedAtMs,
        models: [
          for (final m in template.models)
            isRoute(m)
                ? ModelEntry(
                    publicName: m.publicName,
                    target: lanes.isEmpty ? m.target : lanes.first,
                    enabled: m.enabled,
                    fallbacks: lanes.length > 1 ? lanes.skip(1).toList() : [],
                    contextLength: m.contextLength,
                    maxOutputTokens: m.maxOutputTokens,
                  )
                : ModelEntry(
                    publicName: m.publicName,
                    target: m.target,
                    enabled: m.enabled,
                    contextLength: m.contextLength,
                    maxOutputTokens: m.maxOutputTokens,
                  ),
        ],
      );
      config.upstreams.add(fresh);
      // 实时清单可能带出模板里没声明的车道，新建这条也要补一遍，
      // 否则那些车道只在回退链里能用，车道页看不见也没法单独暴露。
      _appendMissing(fresh, template, lanes, addedEnabled: true);
      return MergeOutcome.installed;
    }

    // 归属别的档案、或是用户自建的：不认领也不改，让 UI 去提示 id 冲突。
    if (existing.managedBy != profileId) return MergeOutcome.conflict;

    if (enableUpstream) existing.enabled = true;
    _appendMissing(existing, template, lanes, addedEnabled: addedEnabled);
    return MergeOutcome.merged;
  }

  /// 补缺：模板或实时清单里有、配置里还没有的车道条目与路由条目。
  ///
  /// 只加不改 —— 用户已有的单条开关与回退链顺序必须活下来。
  static void _appendMissing(
    Upstream target,
    Upstream template,
    List<String> lanes, {
    required bool addedEnabled,
  }) {
    final present = <String>{for (final m in target.models) m.publicName};
    for (final lane in lanes) {
      if (present.contains(lane)) continue;
      target.models.add(
        ModelEntry(publicName: lane, target: lane, enabled: addedEnabled),
      );
    }

    // 路由条目：已存在就把新发现的车道追加到链尾（保住用户排好的顺序），
    // 不存在才按模板新建。
    for (final templateRoute in template.models.where(isRoute)) {
      ModelEntry? route;
      for (final m in target.models) {
        if (m.publicName == templateRoute.publicName) route = m;
      }
      if (route == null) {
        if (lanes.isEmpty) continue;
        target.models.add(
          ModelEntry(
            publicName: templateRoute.publicName,
            target: lanes.first,
            enabled: addedEnabled,
            fallbacks: lanes.skip(1).toList(),
          ),
        );
        continue;
      }
      final known = route.attempts.toSet();
      final fresh = [
        for (final l in lanes)
          if (!known.contains(l)) l,
      ];
      // 整体替换而不是 addAll：fallbacks 可能是不可变列表，原地加会抛。
      if (fresh.isNotEmpty) {
        route.fallbacks = [...route.fallbacks, ...fresh];
      }
    }
  }

  /// 用户是否手改过归属上游的地址（改过就别在更新时覆盖他的改动）。
  static bool isCustomized(ProxyConfig config, ConfigProfile profile) {
    for (final template in profile.upstreams) {
      final installed = upstreamOf(config, template.id);
      if (installed == null) continue;
      if (installed.managedBy != profile.id) continue;
      if (installed.baseUrl != template.baseUrl) return true;
    }
    return false;
  }

  /// 装一整个档案（不动激活标记）。
  static List<MergeOutcome> installProfile(
    ProxyConfig config,
    ConfigProfile profile, {
    required bool addedEnabled,
    bool enableUpstream = true,
  }) => [
    for (final template in profile.upstreams)
      mergeUpstream(
        config: config,
        template: template,
        profileId: profile.id,
        lanes: effectiveLanes(template),
        addedEnabled: addedEnabled,
        enableUpstream: enableUpstream,
      ),
  ];

  /// 激活一个档案（单选）。
  ///
  /// 只动归属自己的上游：别的档案装的上游停用，用户在「模型」页手加的
  /// （managedBy == null）一律不碰 —— 否则选个免费订阅就会把人家局域网里的
  /// llama.cpp 一起关掉。
  static Future<List<MergeOutcome>> activate({
    required ProfileStore store,
    required ProxyConfig config,
    required String profileId,
  }) async {
    final profile = store.profileOf(profileId);
    if (profile == null) return const [MergeOutcome.conflict];

    await refreshDiscovery(config, profile);
    final outcomes = installProfile(config, profile, addedEnabled: true);

    for (final u in config.upstreams) {
      final ownedByOther = u.managedBy != null && u.managedBy != profileId;
      if (ownedByOther) u.enabled = false;
    }

    store.setActive(profileId);
    store.mutateState(profileId, (s) {
      s.lastError = null;
      s.lastUpdateMs = DateTime.now().millisecondsSinceEpoch;
      s.updateAvailable = false;
      s.customized = isCustomized(config, profile);
    });
    return outcomes;
  }

  /// 停用档案：只翻上游的 enabled，不删也不动车道级开关，
  /// 这样重新激活时用户之前的处置还在。
  static void deactivate({
    required ProfileStore store,
    required ProxyConfig config,
    required String profileId,
  }) {
    for (final u in config.upstreams) {
      if (u.managedBy == profileId) u.enabled = false;
    }
    if (store.activeId == profileId) store.setActive(null);
  }

  /// 删档案：连带摘掉它装进来的上游。内置的不给删。
  static void removeProfile({
    required ProfileStore store,
    required ProxyConfig config,
    required String profileId,
  }) {
    if (store.isBuiltin(profileId)) return;
    config.upstreams.removeWhere((u) => u.managedBy == profileId);
    if (store.activeId == profileId) store.setActive(null);
    store.remove(profileId);
  }

  // ---- 车道级处置（车道列表页用） ----

  /// 这个上游的主路由条目（对外一个名字、内部一条回退链）。没有就返回 null。
  static ModelEntry? primaryRouteOf(ProxyConfig config, String upstreamId) {
    final u = upstreamOf(config, upstreamId);
    if (u == null) return null;
    for (final m in u.models) {
      if (isRoute(m)) return m;
    }
    return null;
  }

  /// 当前选中（链首）的车道。
  static String? selectedLaneOf(ProxyConfig config, String upstreamId) {
    final t = primaryRouteOf(config, upstreamId)?.target.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  /// 把某条车道提到回退链链首，其余保持原顺序跟在后面（对应代理组里点选节点）。
  static void selectLane(ProxyConfig config, String upstreamId, String lane) {
    final route = primaryRouteOf(config, upstreamId);
    if (route == null) return;
    // 必须先算 rest 再赋值：attempts 是 [target, ...fallbacks] 去重来的，
    // 先改 target 会让旧链首在去重时被吞掉，每选一次就丢一条车道。
    final rest = [
      for (final l in route.attempts)
        if (l != lane) l,
    ];
    route
      ..target = lane
      ..fallbacks = rest;
  }

  static bool isLaneExposed(
    ProxyConfig config,
    String upstreamId,
    String lane,
  ) {
    final u = upstreamOf(config, upstreamId);
    if (u == null) return false;
    for (final m in u.models) {
      if (m.publicName == lane) return m.enabled;
    }
    return false;
  }

  static void setLaneExposed(
    ProxyConfig config,
    String upstreamId,
    String lane,
    bool on,
  ) {
    final u = upstreamOf(config, upstreamId);
    if (u == null) return;
    for (final m in u.models) {
      if (m.publicName == lane) m.enabled = on;
    }
  }

  // ---- 导入 ----

  /// 从订阅地址导入一份新档案。
  ///
  /// 档案 id 写在文档里，所以必须先拉一次才知道它叫什么 —— 这一步没法省。
  /// 拉完顺手把 etag 记进状态，之后更新就能走条件请求。
  static Future<ConfigProfile> importFromUrl(
    ProfileStore store,
    String url,
  ) async {
    final fetched = await _fetch(url);
    // 没带 etag 却回了 304：订阅端行为不受我们控制，此时没有内容可存，
    // 当成一次失败明确报出来，别让调用方拿到半份档案。
    if (fetched == null) {
      throw const ProfileUpdateException('订阅没有返回内容');
    }
    final profile = store.importDocument(
      fetched.body,
      ProfileSource(ProfileSourceKind.url, url: url),
    );
    final etag = fetched.etag;
    store.mutateState(profile.id, (s) {
      s.etag = etag;
      s.lastUpdateMs = DateTime.now().millisecondsSinceEpoch;
    });
    return profile;
  }

  // ---- 更新与探测 ----

  /// 刷一遍档案里那些 Zen 免密端点的实时车道清单。
  /// 失败不抛：`zenDiscovery` 会保留上一次结果，装配时自然退回文档兜底。
  static Future<void> refreshDiscovery(
    ProxyConfig config,
    ConfigProfile profile,
  ) async {
    for (final template in profile.upstreams) {
      if (!template.isZenGateway) continue;
      final apiKey = upstreamOf(config, template.id)?.apiKey ?? '';
      await zenDiscovery.refresh(template.baseUrl, apiKey: apiKey);
    }
  }

  /// 刷新「现在还有哪些模型可用」（发现页下拉刷新走这条）。
  ///
  /// 和 [updateOne] 是两件事：这里只跟上游 `/v1/models` 对账——拉到实时清单
  /// 就把新出现的车道补进已装上游、把上游已经下架的摘掉（Zen 那类免密清单
  /// 会随上游上下架变动，写死在包里的目录迟早过期）。订阅文档的重新拉取
  /// 不在这里做，仍归「更多 → 更新」。
  ///
  /// 只有**装进了配置且归本档案管**的上游会被改写：用户在「模型」页手建的
  /// （managedBy == null）与别的档案装的一律不碰。
  /// 某个端点这次没拉到（超时 / 报错）就整条跳过 —— 拿不到清单时摘车道
  /// 等于凭空把还能用的模型删掉。
  ///
  /// 返回本次真正刷新成功的档案数，UI 拿它提示「刷新了几个」。
  static Future<int> refreshModelLists({
    required ProfileStore store,
    required ProxyConfig config,
  }) async {
    var refreshed = 0;
    for (final profile in store.profiles) {
      final ok = await refreshModelListOf(
        store: store,
        config: config,
        profileId: profile.id,
      );
      if (ok) refreshed++;
    }
    return refreshed;
  }

  /// 刷单个档案的可用模型列表。返回是否拉到了至少一份实时清单。
  static Future<bool> refreshModelListOf({
    required ProfileStore store,
    required ProxyConfig config,
    required String profileId,
  }) async {
    final profile = store.profileOf(profileId);
    if (profile == null) return false;

    var gotAny = false;
    final failures = <String>[];

    for (final template in profile.upstreams) {
      // 装进配置的那条才是用户真在用的：地址 / Key 都可能被他改过，
      // 只能拿它去拉，拿模板去拉会拉到另一份集合。
      final installed = upstreamOf(config, template.id);
      final target = installed ?? template;
      if (installed != null && installed.managedBy != profileId) continue;

      final live = await zenDiscovery.refreshFor(target);
      if (live == null || live.isEmpty) {
        final why = zenDiscovery.errorOf(target.baseUrl);
        if (why != null) failures.add(why);
        continue;
      }
      gotAny = true;
      if (installed == null) continue; // 没激活：只更新清单缓存，不碰配置
      applyLiveLanes(installed, live);
    }

    store.mutateState(profileId, (s) {
      if (failures.isNotEmpty && !gotAny) {
        s.lastError = failures.first;
      } else {
        s.lastError = null;
      }
      if (gotAny) s.lastUpdateMs = DateTime.now().millisecondsSinceEpoch;
    });
    return gotAny;
  }

  /// 按实时清单对账一个已装上游：补新、摘失效。
  ///
  /// 只动车道条目与回退链，不动用户手调过的开关（新增的按 enabled 落，
  /// 已有的保留原值）。路由条目（`zen-free` 那种一个名字挂一串回退链的）
  /// 永远保留，只把它链里已经下架的车道摘掉；链首被摘了就把下一条顶上。
  static void applyLiveLanes(Upstream installed, List<String> live) {
    final alive = live.toSet();

    // 1) 摘掉上游已经没有的车道条目。
    installed.models.removeWhere((m) {
      if (isRoute(m)) return false;
      return !alive.contains(m.target);
    });

    // 2) 路由条目：摘掉链里失效的车道，链首没了就顺位顶上。
    for (final m in installed.models) {
      if (!isRoute(m)) continue;
      final kept = [
        for (final lane in m.attempts)
          if (alive.contains(lane)) lane,
      ];
      if (kept.isEmpty) {
        // 整条旧链都下架了（上游换了一茬模型）：直接采纳实时清单，
        // 别留个死链首挂着 —— 调它就是必失败。
        m
          ..target = live.first
          ..fallbacks = live.skip(1).toList();
        continue;
      }
      m
        ..target = kept.first
        ..fallbacks = kept.skip(1).toList();
      // 新出现的车道补到链尾（保住用户排好的优先级）。
      final known = kept.toSet();
      final fresh = [
        for (final l in live)
          if (!known.contains(l)) l,
      ];
      if (fresh.isNotEmpty) m.fallbacks = [...m.fallbacks, ...fresh];
    }

    // 3) 补进清单里有、配置里还没有的车道。
    final present = <String>{for (final m in installed.models) m.publicName};
    for (final lane in live) {
      if (present.contains(lane)) continue;
      installed.models.add(ModelEntry(publicName: lane, target: lane));
    }
  }

  static Future<void> probeProfile({
    required ProfileStore store,
    required ProxyConfig config,
    required String profileId,
  }) async {
    final profile = store.profileOf(profileId);
    if (profile == null) return;
    for (final template in profile.upstreams) {
      final installed = upstreamOf(config, template.id);
      await LaneProbeService.probe(
        key: profileId,
        baseUrl: installed?.baseUrl ?? template.baseUrl,
        apiKey: installed?.apiKey ?? '',
        lanes: effectiveLanes(template),
      );
    }
  }

  /// 下拉刷新：更新全部档案。
  ///
  /// 远程的重拉订阅，本地与内置的重解析实时车道；只有**激活中**的档案会
  /// 重新装配并探测，没激活的拉到了新内容只打个「有更新」角标，
  /// 免得一次下拉把十几个没在用的订阅全装进配置。
  static Future<void> updateAll({
    required ProfileStore store,
    required ProxyConfig config,
  }) async {
    for (final profile in store.profiles) {
      await updateOne(store: store, config: config, profileId: profile.id);
    }
  }

  static Future<void> updateOne({
    required ProfileStore store,
    required ProxyConfig config,
    required String profileId,
  }) async {
    final profile = store.profileOf(profileId);
    if (profile == null) return;
    final isActive = store.activeId == profileId;
    var current = profile;
    var changed = false;

    if (profile.source.isRemote) {
      final _Fetched? fetched;
      try {
        fetched = await _fetch(
          profile.source.url,
          etag: store.stateOf(profileId).etag,
        );
      } on ProfileUpdateException catch (e) {
        store.mutateState(profileId, (s) {
          s.lastError = e.message;
          s.lastUpdateMs = DateTime.now().millisecondsSinceEpoch;
        });
        return;
      } catch (e) {
        store.mutateState(profileId, (s) {
          s.lastError = _brief('$e');
          s.lastUpdateMs = DateTime.now().millisecondsSinceEpoch;
        });
        return;
      }

      // 落到非空局部：闭包捕获的可空变量拿不到外层 if 的类型提升。
      final updated = fetched;
      if (updated != null) {
        final newEtag = updated.etag;
        try {
          current = store.replaceDocument(profileId, updated.body);
          changed = true;
          store.mutateState(profileId, (s) => s.etag = newEtag);
        } on ProfileFormatException catch (e) {
          store.mutateState(profileId, (s) {
            s.lastError = '档案格式不对（${e.code.name}）';
            s.lastUpdateMs = DateTime.now().millisecondsSinceEpoch;
          });
          return;
        }
      }
    }

    await refreshDiscovery(config, current);

    if (!isActive) {
      if (changed) {
        store.mutateState(profileId, (s) => s.updateAvailable = true);
      }
      return;
    }

    installProfile(config, current, addedEnabled: true);
    store.mutateState(profileId, (s) {
      s.lastError = null;
      s.lastUpdateMs = DateTime.now().millisecondsSinceEpoch;
      s.updateAvailable = false;
      s.customized = isCustomized(config, current);
    });
    await probeProfile(store: store, config: config, profileId: profileId);
  }

  static Future<_Fetched?> _fetch(String url, {String? etag}) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const ProfileUpdateException('地址不合法');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..autoUncompress = false;
    try {
      final req = await client.getUrl(uri).timeout(_fetchTimeout);
      if (etag != null && etag.isNotEmpty) {
        req.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
      }
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final res = await req.close().timeout(_fetchTimeout);

      if (res.statusCode == HttpStatus.notModified) {
        await res.drain<void>();
        return null;
      }
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(_fetchTimeout, onTimeout: () => '');
      if (res.statusCode != HttpStatus.ok) {
        throw ProfileUpdateException('HTTP ${res.statusCode}');
      }
      return _Fetched(body, res.headers.value(HttpHeaders.etagHeader));
    } on SocketException catch (e) {
      throw ProfileUpdateException(_brief(e.osError?.message ?? '$e'));
    } on TimeoutException {
      throw const ProfileUpdateException('拉取超时');
    } finally {
      client.close(force: true);
    }
  }

  // ---- 迁移 ----

  /// 从「广场预设」时代升级上来的首次启动迁移。
  ///
  /// 只在索引键缺失时跑一次；跑完调用方要把两个 store 都落盘。
  /// 只加字段、不删东西：老代码忽略 managedBy，所以降级也安全。
  ///
  /// 返回是否真的执行了迁移（用于决定要不要写盘）。
  static bool migrateIfNeeded(ProfileStore store, ProxyConfig config) {
    if (store.hadPersistedIndex) return false;

    final legacy = config.upstreams
        .where((u) => u.id == kZenUpstreamId)
        .toList();
    if (legacy.isEmpty) return true; // 全新安装：内置档案在列表里但不激活

    // 这个 id 是广场时代专属的，用户手建的上游不会撞上来，认领是安全的。
    for (final u in legacy) {
      u.managedBy ??= kZenProfileId;
    }

    // 激活判据必须在装配之前读：装配会动上游开关，之后再判就读不到
    // 用户当初「关着」这个事实了。判据沿用旧的 isRuleEnabled ——
    // 上游开着，且有任一条目开着。
    final wasActive = legacy.any(
      (u) => u.enabled && u.models.any((m) => m.enabled),
    );

    final builtin = builtinZenProfile();
    // enableUpstream: false —— 迁移只补缺失的车道条目，
    // 不能把用户特意关掉的档案又打开。
    installProfile(config, builtin, addedEnabled: false, enableUpstream: false);

    store.mutateState(kZenProfileId, (s) {
      s.customized = isCustomized(config, builtin);
      s.active = wasActive;
    });
    if (wasActive) store.setActive(kZenProfileId);

    return true;
  }

  // ---- 内置档案的默认启用 ----

  /// 「内置 OpenCode Zen 默认启用」的一次性门闩。
  ///
  /// 独立于档案索引键（`local2api.profiles.v1`）：那条只覆盖「广场时代升级
  /// 上来」这一种情况，而我们要补的恰恰是**索引已存在、但配置里没有这个上游**
  /// 的配置（新装也一样）。
  static const String _builtinDefaultKey = 'local2api.builtinZen.default.v1';

  /// 「内置 MiMo TTS 上游默认启用」的一次性门闩键（与上面那条同理，独立成键）。
  static const String _builtinMimoTtsKey = 'local2api.builtinMimoTts.default.v1';

  /// 保证内置的 OpenCode Zen 上游**装进配置并处于启用状态**（默认启用）。
  ///
  /// 为什么需要它：发现页改版后列的是 `config.upstreams` 本身（不再列档案卡），
  /// 而内置档案在此之前只活在 [ProfileStore] 里、从不装配 —— 全新安装、以及
  /// 「装过但没手动激活过」的配置里上游列表都是空的，发现页上那个预制提供商
  /// 就凭空消失了。
  ///
  /// 只补缺、不复活：
  ///   · 门闩跑过一次就不再干预（用户后来删掉 / 关掉都算他的决定）；
  ///   · 配置里已经有这个 id 的上游时（无论开关）原样不碰 —— 免得把用户特意
  ///     关掉的档案又打开，这正是 [migrateIfNeeded] 里 `enableUpstream: false`
  ///     要防的事。
  ///
  /// 返回「本次是否真的装了东西」，调用方据此决定要不要落盘。
  static Future<bool> ensureBuiltinDefaultUpstream({
    required ProfileStore store,
    required ProxyConfig config,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_builtinDefaultKey) ?? false) return false;
    await prefs.setBool(_builtinDefaultKey, true);

    // 已经有了就不碰（可能是用户自己调过的、或广场时代迁移认领的）。
    if (upstreamOf(config, kZenUpstreamId) != null) return false;

    installProfile(
      config,
      builtinZenProfile(),
      // 等价于用户手动激活一次：路由与各条车道都直接对外暴露。
      addedEnabled: true,
      enableUpstream: true,
    );
    // 状态与配置保持一致（档案被当作「已激活」），否则发现页卡片开着、
    // 档案状态却是未激活，后面点「更新」之类的动作会走错分支。
    store.setActive(kZenProfileId);
    return true;
  }

  /// 「内置 MiMo TTS 上游默认启用」的一次性门闩。
  ///
  /// 与 [ensureBuiltinDefaultUpstream] 同一套路：首次运行把 MiMo TTS 语音
  /// 上游装进配置并启用（三个 TTS 模型全勾），API Key 留空由用户自填。
  /// 门闩独立成键：用户后来删了这个上游也不会被下次启动悄悄补回来。
  ///
  /// 返回「本次是否真的装了东西」，调用方据此决定要不要落盘。
  static Future<bool> ensureBuiltinMimoTtsUpstream(ProxyConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_builtinMimoTtsKey) ?? false) return false;
    await prefs.setBool(_builtinMimoTtsKey, true);

    // 已经有了就不碰（可能是用户自己加过、调过的）。
    if (config.upstreams.any((u) => u.id == kMimoTtsUpstreamId)) return false;

    config.upstreams.add(builtinMimoTtsUpstream());
    return true;
  }

  static String _brief(String s) {
    s = s.replaceAll('\n', ' ').trim();
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }
}

class _Fetched {
  const _Fetched(this.body, this.etag);

  final String body;
  final String? etag;
}
