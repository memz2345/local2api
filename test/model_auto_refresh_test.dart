import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/models/builtin_profiles.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/model_auto_refresh.dart';
import 'package:local2api/services/profile_service.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

Upstream _upstream({
  String id = 'u1',
  String name = '测试上游',
  int autoRefreshHours = 0,
  int refreshedAt = 0,
  List<ModelEntry> models = const [],
}) => Upstream(
  id: id,
  name: name,
  type: UpstreamType.openai,
  baseUrl: 'https://example.com/v1',
  autoRefreshHours: autoRefreshHours,
  modelsRefreshedAtMs: refreshedAt,
  models: [...models],
);

ModelEntry _m(String name, {String? target, List<String>? fallbacks}) =>
    ModelEntry(
      publicName: name,
      target: target ?? name,
      fallbacks: fallbacks,
    );

/// Zen 那种形状：一条容灾路由 + 一堆零散车道。
Upstream _zenLike() => _upstream(
  id: kZenUpstreamId,
  name: 'OpenCode Zen',
  autoRefreshHours: kAutoRefreshHoursBuiltin,
  models: [
    _m(
      kZenRouteName,
      target: 'lane-a',
      fallbacks: ['lane-b', 'lane-dead'],
    ),
    _m('lane-a'),
    _m('lane-b'),
    _m('lane-dead'),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('该不该刷（isDue / untilNext）', () {
    test('关掉自动更新就永远不该刷', () {
      final u = _upstream(autoRefreshHours: 0, refreshedAt: 12345);
      expect(ModelAutoRefresh.isDue(u), isFalse);
      expect(ModelAutoRefresh.untilNext(u), isNull);
    });

    test('从没刷过 → 立刻该刷（首次进应用刷一次就是这么来的）', () {
      final u = _upstream(autoRefreshHours: 168);
      expect(ModelAutoRefresh.isDue(u), isTrue);
      expect(ModelAutoRefresh.untilNext(u), Duration.zero);
    });

    test('没到点不刷，过了点就刷', () {
      final now = DateTime(2026, 10, 24, 12);
      final nowMs = now.millisecondsSinceEpoch;

      final fresh = _upstream(
        autoRefreshHours: 168,
        refreshedAt: nowMs - const Duration(days: 6).inMilliseconds,
      );
      expect(ModelAutoRefresh.isDue(fresh, now: now), isFalse);
      expect(ModelAutoRefresh.untilNext(fresh, now: now), const Duration(days: 1));

      final stale = _upstream(
        autoRefreshHours: 168,
        refreshedAt: nowMs - const Duration(days: 7).inMilliseconds,
      );
      expect(ModelAutoRefresh.isDue(stale, now: now), isTrue);
      expect(ModelAutoRefresh.untilNext(stale, now: now), Duration.zero);
    });

    test('内置 Zen / MiMo 默认就是 7 天一次', () {
      expect(kAutoRefreshHoursBuiltin, 168);
      final zen = builtinZenProfile().upstreams.first;
      expect(zen.autoRefreshHours, kAutoRefreshHoursBuiltin);
      expect(zen.modelsRefreshedAtMs, 0, reason: '首次进应用要刷一次');
      expect(builtinMimoTtsUpstream().autoRefreshHours, kAutoRefreshHoursBuiltin);
    });
  });

  group('配置存取', () {
    test('间隔与上次刷新时间能落盘、能读回来', () {
      final u = _upstream(autoRefreshHours: 72, refreshedAt: 1700000000000);
      final back = Upstream.fromJson(u.toJson());
      expect(back.autoRefreshHours, 72);
      expect(back.modelsRefreshedAtMs, 1700000000000);
    });

    test('默认值不写进 JSON（老配置不变胖）', () {
      final json = _upstream().toJson();
      expect(json.containsKey('autoRefreshHours'), isFalse);
      expect(json.containsKey('modelsRefreshedAtMs'), isFalse);
      // 老配置里没这两个键也要读得出默认值
      final old = Upstream.fromJson(json);
      expect(old.autoRefreshHours, 0);
      expect(old.modelsRefreshedAtMs, 0);
    });
  });

  group('清单对账（mergeCatalog）', () {
    test('路由条目永远保住，链里下架的车道摘掉', () {
      final u = _zenLike();
      final result = ModelAutoRefresh.mergeCatalog(
        u,
        // lane-a / lane-b 还在，lane-dead 下架，lane-c 是新车道
        const ModelCatalog(['lane-a', 'lane-b', 'lane-c']),
      );

      expect(result.ok, isTrue);
      final route = u.models.firstWhere((m) => m.publicName == kZenRouteName);
      expect(route.target, 'lane-a');
      expect(route.fallbacks, ['lane-b', 'lane-c'], reason: '下架的摘掉，新的补到链尾');
      expect(
        u.models.map((m) => m.publicName),
        isNot(contains('lane-dead')),
      );
      expect(result.removed, ['lane-dead']);
      expect(result.added, ['lane-c']);
    });

    test('链首下架就顺位顶上', () {
      final u = _zenLike();
      ModelAutoRefresh.mergeCatalog(
        u,
        const ModelCatalog(['lane-b', 'lane-c']),
      );
      final route = u.models.firstWhere((m) => m.publicName == kZenRouteName);
      expect(route.target, 'lane-b');
      expect(route.fallbacks, ['lane-c']);
    });

    test('上游换了一整茬（与本地零交集）→ 整次跳过，路由与车道都不动', () {
      final u = _zenLike();
      final before = u.models.map((m) => m.publicName).toList();
      final result = ModelAutoRefresh.mergeCatalog(
        u,
        const ModelCatalog(['x1', 'x2']),
      );
      expect(result.ok, isFalse);
      expect(u.models.map((m) => m.publicName), before);
      expect(
        u.models.firstWhere((m) => m.publicName == kZenRouteName).target,
        'lane-a',
      );
    });

    test('本地一条都对不上就整次跳过（MiMo TTS 那种情况）', () {
      final u = _upstream(
        name: 'MiMo TTS',
        autoRefreshHours: 168,
        models: [
          _m('mimo-v2.5-tts'),
          _m('mimo-v2.5-tts-voicedesign'),
        ],
      );
      final result = ModelAutoRefresh.mergeCatalog(
        u,
        // /models 给的是聊天模型，跟 TTS 音色不是一维度
        const ModelCatalog(['mimo-v2.5-chat', 'mimo-v2.5-pro']),
      );

      expect(result.ok, isFalse);
      expect(result.error, contains('没有交集'));
      expect(
        u.models.map((m) => m.publicName),
        ['mimo-v2.5-tts', 'mimo-v2.5-tts-voicedesign'],
        reason: '失败时绝不能动用户的模型表',
      );
    });

    test('空清单算失败，不删任何东西', () {
      final u = _zenLike();
      final before = u.models.map((m) => m.publicName).toList();
      final result = ModelAutoRefresh.mergeCatalog(u, const ModelCatalog([]));
      expect(result.ok, isFalse);
      expect(u.models.map((m) => m.publicName), before);
    });

    test('上下文 / 输出上限只填空位，用户手填的不覆盖', () {
      final u = _upstream(
        autoRefreshHours: 24,
        models: [
          _m('m-a'), // 全是空位，该被回填
          ModelEntry(
            publicName: 'm-b',
            contextLength: 4096,
            maxOutputTokens: 512,
          ),
        ],
      );
      ModelAutoRefresh.mergeCatalog(
        u,
        const ModelCatalog(
          ['m-a', 'm-b'],
          contexts: {'m-a': 200000, 'm-b': 999999},
          outputs: {'m-a': 8192, 'm-b': 1024},
        ),
      );
      expect(u.models[0].contextLength, 200000);
      expect(u.models[0].maxOutputTokens, 8192);
      expect(u.models[1].contextLength, 4096, reason: '手填的不动');
      expect(u.models[1].maxOutputTokens, 512);
    });

    test('新补进来的模型按启用落（跟发现页刷车道同一口径）', () {
      final u = _upstream(models: [_m('a')]);
      ModelAutoRefresh.mergeCatalog(u, const ModelCatalog(['a', 'b']));
      expect(u.models.firstWhere((m) => m.publicName == 'b').enabled, isTrue);
    });
  });

  group('runDue', () {
    test('没有上游该刷时安静返回，不碰网络', () async {
      SharedPreferences.setMockInitialValues({});
      final store = ConfigStore();
      await store.load();
      final config = store.config;
      config.upstreams
        ..clear()
        ..add(_upstream(autoRefreshHours: 0));
      store.update(config);

      final results = await ModelAutoRefresh(store).runDue();
      expect(results, isEmpty);
    });
  });

  group('内置上游装上后要带着 7 天的策略', () {
    test('installProfile 装配时不会丢 autoRefreshHours', () {
      final config = ProxyConfig();
      ProfileService.mergeUpstream(
        config: config,
        template: builtinZenProfile().upstreams.first,
        profileId: kZenProfileId,
        lanes: const [],
        addedEnabled: true,
      );
      final zen = config.upstreams.firstWhere((u) => u.id == kZenUpstreamId);
      expect(zen.autoRefreshHours, kAutoRefreshHoursBuiltin);
      expect(zen.modelsRefreshedAtMs, 0, reason: '首次进应用要刷一次');
    });

    test('老配置（没有这个键）一次性回填成 7 天，之后不再动', () async {
      SharedPreferences.setMockInitialValues({});
      final config = ProxyConfig();
      config.upstreams
        ..add(_upstream(id: kZenUpstreamId, name: 'OpenCode Zen'))
        ..add(_upstream(id: kMimoTtsUpstreamId, name: 'MiMo TTS'))
        ..add(_upstream(id: 'mine', name: '用户自建'));

      expect(await ModelAutoRefresh.backfillBuiltinDefaults(config), isTrue);
      expect(
        config.upstreams.firstWhere((u) => u.id == kZenUpstreamId).autoRefreshHours,
        kAutoRefreshHoursBuiltin,
      );
      expect(
        config.upstreams
            .firstWhere((u) => u.id == kMimoTtsUpstreamId)
            .autoRefreshHours,
        kAutoRefreshHoursBuiltin,
      );
      expect(
        config.upstreams.firstWhere((u) => u.id == 'mine').autoRefreshHours,
        0,
        reason: '用户自建的上游不替他开自动更新',
      );

      // 门闩已落：用户之后手动关掉（设 0）不会被下次启动偷偷改回来
      config.upstreams.firstWhere((u) => u.id == kZenUpstreamId).autoRefreshHours =
          0;
      expect(await ModelAutoRefresh.backfillBuiltinDefaults(config), isFalse);
      expect(
        config.upstreams.firstWhere((u) => u.id == kZenUpstreamId).autoRefreshHours,
        0,
      );
    });
  });
}
