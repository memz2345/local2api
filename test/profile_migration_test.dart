import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/models/builtin_profiles.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/profile_service.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:local2api/services/zen/zen_discovery.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _indexKey = 'local2api.profiles.v1';

/// 广场时代由 PlazaService.apply 装出来的上游长这样。
Upstream _legacyZenUpstream({
  bool enabled = true,
  String baseUrl = kOpenCodeZenBaseUrl,
  List<String>? exposedLanes,
  bool withRoute = true,
  String routeHead = 'space-bunny-free',
}) {
  final lanes = exposedLanes ?? const ['space-bunny-free', 'big-pickle'];
  return Upstream(
    id: kZenUpstreamId,
    name: 'OpenCode Zen',
    baseUrl: baseUrl,
    enabled: enabled,
    models: [
      if (withRoute)
        ModelEntry(
          publicName: kZenRouteName,
          target: routeHead,
          fallbacks: [
            for (final l in kZenFreeLanes)
              if (l != routeHead) l,
          ],
        ),
      for (final l in lanes) ModelEntry(publicName: l, target: l),
    ],
  );
}

Future<ProfileStore> _loadStore({Map<String, Object> seed = const {}}) async {
  SharedPreferences.setMockInitialValues(seed);
  final store = ProfileStore();
  await store.load();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => zenDiscovery.clear());
  tearDown(() => zenDiscovery.clear());

  group('首次启动迁移', () {
    test('全新安装：没旧上游就不装也不激活，但迁移标记照样落', () async {
      final store = await _loadStore();
      addTearDown(store.dispose);
      final config = ProxyConfig();

      expect(ProfileService.migrateIfNeeded(store, config), isTrue);
      expect(config.upstreams, isEmpty);
      expect(store.activeId, isNull);
      expect(store.profileOf(kZenProfileId), isNotNull);
    });

    test('索引键已存在 = 迁移跑过了，直接跳过', () async {
      final store = await _loadStore(
        seed: {
          _indexKey: jsonEncode({
            'activeId': null,
            'order': [],
            'states': [],
          }),
        },
      );
      addTearDown(store.dispose);
      final config = ProxyConfig(upstreams: [_legacyZenUpstream()]);

      expect(ProfileService.migrateIfNeeded(store, config), isFalse);
      expect(
        config.upstreams.single.managedBy,
        isNull,
        reason: '跳过就是什么都不该动',
      );
    });

    test('旧上游被认领，激活标记按旧 isRuleEnabled 的判据回填', () async {
      final store = await _loadStore();
      addTearDown(store.dispose);
      final config = ProxyConfig(upstreams: [_legacyZenUpstream()]);

      ProfileService.migrateIfNeeded(store, config);

      final u = config.upstreams.single;
      expect(u.managedBy, kZenProfileId);
      expect(store.activeId, kZenProfileId);
      expect(store.stateOf(kZenProfileId).active, isTrue);
    });

    test('旧上游是停用的：认领归属但不激活', () async {
      final store = await _loadStore();
      addTearDown(store.dispose);
      final config = ProxyConfig(
        upstreams: [_legacyZenUpstream(enabled: false)],
      );

      ProfileService.migrateIfNeeded(store, config);

      expect(config.upstreams.single.managedBy, kZenProfileId);
      expect(store.activeId, isNull);
      expect(
        config.upstreams.single.enabled,
        isFalse,
        reason: '用户当初关着的上游，迁移不能顺手给他打开',
      );
    });

    test('上游开着但一条模型都没暴露：不算激活', () async {
      final store = await _loadStore();
      addTearDown(store.dispose);
      final legacy = _legacyZenUpstream(withRoute: false, exposedLanes: const []);
      final config = ProxyConfig(upstreams: [legacy]);

      ProfileService.migrateIfNeeded(store, config);

      expect(config.upstreams.single.managedBy, kZenProfileId);
      expect(store.activeId, isNull);
    });

    test('只启用过容灾路由的老用户：补进来的零散车道一律 disabled', () async {
      final store = await _loadStore();
      addTearDown(store.dispose);
      // 当年的「路由策略」预设只写这一条对外模型
      final config = ProxyConfig(
        upstreams: [_legacyZenUpstream(exposedLanes: const [])],
      );

      ProfileService.migrateIfNeeded(store, config);

      final u = config.upstreams.single;
      expect(u.models.first.publicName, kZenRouteName);
      expect(u.models.first.enabled, isTrue, reason: '原有那条不动');
      final added = u.models.skip(1).toList();
      expect(added, isNotEmpty);
      for (final m in added) {
        expect(
          m.enabled,
          isFalse,
          reason: '${m.publicName} 是迁移补的，不该凭空对外暴露',
        );
      }
    });

    test('用户排过的回退顺序与单条开关都活下来', () async {
      final store = await _loadStore();
      addTearDown(store.dispose);
      final legacy = _legacyZenUpstream(
        routeHead: 'space-bunny-free',
        exposedLanes: const ['big-pickle'],
      );
      // 用户手动收起过这条
      legacy.models
          .firstWhere((m) => m.publicName == 'big-pickle')
          .enabled = false;
      final config = ProxyConfig(upstreams: [legacy]);

      ProfileService.migrateIfNeeded(store, config);

      final u = config.upstreams.single;
      expect(
        ProfileService.selectedLaneOf(config, kZenUpstreamId),
        'space-bunny-free',
        reason: '链首是用户选的，迁移不能改',
      );
      expect(u.models.first.attempts.first, 'space-bunny-free');
      // space-bunny-free 已经不在内置目录里了（2026-10-22 上游已下架），
      // 但它是**用户自己排的链首**，迁移必须留着；内置目录那些车道按原顺序
      // 跟在后面。
      expect(
        u.models.first.attempts.toSet(),
        {...kZenFreeLanes, 'space-bunny-free'},
      );
      expect(
        u.models.first.attempts.sublist(1),
        kZenFreeLanes,
        reason: '链首之后的顺序就是内置目录的顺序',
      );
      expect(
        ProfileService.isLaneExposed(config, kZenUpstreamId, 'big-pickle'),
        isFalse,
        reason: '用户收起的车道不该被迁移重新打开',
      );
    });

    test('用户换过 baseUrl：标记 customized 且不覆盖他的地址', () async {
      final store = await _loadStore();
      addTearDown(store.dispose);
      final config = ProxyConfig(
        upstreams: [_legacyZenUpstream(baseUrl: 'https://mirror.example/zen/v1')],
      );

      ProfileService.migrateIfNeeded(store, config);

      expect(config.upstreams.single.baseUrl, 'https://mirror.example/zen/v1');
      expect(store.stateOf(kZenProfileId).customized, isTrue);
    });

    test('用户自建的上游一律不碰', () async {
      final store = await _loadStore();
      addTearDown(store.dispose);
      final mine = Upstream(
        id: 'u-mine',
        name: '我的 llama.cpp',
        baseUrl: 'http://192.168.1.10:8080/v1',
        models: [ModelEntry(publicName: 'local', target: 'local')],
      );
      final config = ProxyConfig(upstreams: [_legacyZenUpstream(), mine]);

      ProfileService.migrateIfNeeded(store, config);

      expect(mine.managedBy, isNull);
      expect(mine.enabled, isTrue);
      expect(mine.models.single.enabled, isTrue);
      expect(config.upstreams.length, 2);
    });

    test('幂等：连着跑两次结果一样，不会把车道重复补进去', () async {
      final store = await _loadStore();
      addTearDown(store.dispose);
      final config = ProxyConfig(
        upstreams: [_legacyZenUpstream(exposedLanes: const [])],
      );

      ProfileService.migrateIfNeeded(store, config);
      final afterFirst = config.upstreams.single.models.length;
      // 第二次因为索引还没落盘，hadPersistedIndex 仍是 false；
      // 但补缺逻辑必须认出条目已存在，不能再加一遍。
      ProfileService.migrateIfNeeded(store, config);

      expect(config.upstreams.single.models.length, afterFirst);
      expect(
        config.upstreams.single.models.map((m) => m.publicName).toSet().length,
        afterFirst,
        reason: '不该出现重复的对外模型名',
      );
    });

    test('迁移只加字段：managedBy 之外的旧数据原样保留', () async {
      final store = await _loadStore();
      addTearDown(store.dispose);
      final legacy = _legacyZenUpstream();
      legacy.apiKey = '用户自己填的 key';
      legacy.name = '我改过的名字';
      final config = ProxyConfig(
        listenPort: 8123,
        listenHost: '127.0.0.1',
        upstreams: [legacy],
        apiKeys: [ApiKeyEntry(id: 'k', name: 'k', key: 'sk-1')],
      );

      ProfileService.migrateIfNeeded(store, config);

      final u = config.upstreams.single;
      expect(u.apiKey, '用户自己填的 key');
      expect(u.name, '我改过的名字');
      expect(u.baseUrl, kOpenCodeZenBaseUrl);
      expect(config.listenPort, 8123);
      expect(config.listenHost, '127.0.0.1');
      expect(config.apiKeys.single.key, 'sk-1');
    });
  });
}
