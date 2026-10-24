import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/models/builtin_profiles.dart';
import 'package:local2api/models/config_profile.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/profile_service.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:local2api/services/zen/zen_discovery.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 造一份测试档案：一个上游，一条容灾路由 + 每条车道各一个条目。
///
/// baseUrl 刻意不用 Zen 的地址 —— `activate` 会去刷实时清单，
/// 那是真网络请求，单测里不能碰。
String _doc({
  String id = 'demo',
  String upstreamId = 'u-demo',
  String baseUrl = 'https://a.example/v1',
  List<String> lanes = const ['m1', 'm2', 'm3'],
  String route = 'auto',
}) => jsonEncode({
  'id': id,
  'name': id.toUpperCase(),
  'upstreams': [
    {
      'id': upstreamId,
      'name': 'Demo',
      'baseUrl': baseUrl,
      'models': [
        {
          'publicName': route,
          'target': lanes.first,
          'fallbacks': lanes.skip(1).toList(),
        },
        for (final l in lanes)
          {'publicName': l, 'target': l},
      ],
    },
  ],
});

ConfigProfile _profile({
  String id = 'demo',
  String upstreamId = 'u-demo',
  String baseUrl = 'https://a.example/v1',
  List<String> lanes = const ['m1', 'm2', 'm3'],
}) => parseConfigProfile(
  _doc(id: id, upstreamId: upstreamId, baseUrl: baseUrl, lanes: lanes),
  source: const ProfileSource(ProfileSourceKind.inline),
);

Upstream _userUpstream({String id = 'u-mine'}) => Upstream(
  id: id,
  name: '我的 llama.cpp',
  baseUrl: 'http://192.168.1.10:8080/v1',
  models: [ModelEntry(publicName: 'local', target: 'local')],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProfileStore store;
  late ProxyConfig config;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = ProfileStore();
    await store.load();
    config = ProxyConfig();
    // zenDiscovery 是全局单例，上一个用例留下的清单会串味
    zenDiscovery.clear();
  });

  tearDown(() {
    zenDiscovery.clear();
    store.dispose();
  });

  group('装配', () {
    test('首次安装：建上游、打归属标记、路由链按车道顺序铺开', () {
      final p = _profile();
      final outcomes = ProfileService.installProfile(
        config,
        p,
        addedEnabled: true,
      );

      expect(outcomes, [MergeOutcome.installed]);
      final u = config.upstreams.single;
      expect(u.id, 'u-demo');
      expect(u.managedBy, 'demo');
      expect(u.enabled, isTrue);
      expect(u.models.map((m) => m.publicName), ['auto', 'm1', 'm2', 'm3']);
      final route = u.models.first;
      expect(route.target, 'm1');
      expect(route.fallbacks, ['m2', 'm3']);
      expect(route.attempts, ['m1', 'm2', 'm3']);
    });

    test('增量合并只补缺：用户关掉的单条车道不会被重新打开', () {
      final p = _profile();
      ProfileService.installProfile(config, p, addedEnabled: true);

      // 用户把 m2 收起来了
      ProfileService.setLaneExposed(config, 'u-demo', 'm2', false);
      expect(ProfileService.isLaneExposed(config, 'u-demo', 'm2'), isFalse);

      final outcomes = ProfileService.installProfile(
        config,
        p,
        addedEnabled: true,
      );
      expect(outcomes, [MergeOutcome.merged]);
      expect(
        ProfileService.isLaneExposed(config, 'u-demo', 'm2'),
        isFalse,
        reason: '重装档案不该把用户手动收起的车道又打开',
      );
      expect(config.upstreams.single.models.length, 4);
    });

    test('增量合并保住用户排好的回退顺序', () {
      final p = _profile();
      ProfileService.installProfile(config, p, addedEnabled: true);

      // 用户把 m3 提到链首
      ProfileService.selectLane(config, 'u-demo', 'm3');
      expect(ProfileService.selectedLaneOf(config, 'u-demo'), 'm3');

      ProfileService.installProfile(config, p, addedEnabled: true);
      expect(
        ProfileService.selectedLaneOf(config, 'u-demo'),
        'm3',
        reason: '合并不能把用户点选的链首冲掉',
      );
      expect(
        ProfileService.primaryRouteOf(config, 'u-demo')!.attempts,
        ['m3', 'm1', 'm2'],
      );
    });

    test('上游清单多出来的车道追加到链尾，不动已有顺序', () {
      // 用真的 Zen 地址 + 预置发现结果：lanesFor 是纯查表，不出网。
      // installProfile 不会去刷清单（那是 activate 的事），所以这里安全。
      zenDiscovery.lanes = [...kZenFreeLanes, '刚上线的新车道'];
      final builtin = builtinZenProfile();

      ProfileService.installProfile(config, builtin, addedEnabled: true);
      final route = ProfileService.primaryRouteOf(config, kZenUpstreamId)!;
      expect(route.attempts.last, '刚上线的新车道');
      expect(route.attempts.first, kZenFreeLanes.first);
      expect(
        ProfileService.isLaneExposed(config, kZenUpstreamId, '刚上线的新车道'),
        isTrue,
      );
    });

    test('迁移路径：补进来的条目按 disabled 落，老用户的对外面不变', () {
      // 老用户当年只启用了容灾路由，零散车道一条都没暴露
      config.upstreams.add(
        Upstream(
          id: 'u-demo',
          name: 'Demo',
          baseUrl: 'https://a.example/v1',
          managedBy: 'demo',
          models: [
            ModelEntry(
              publicName: 'auto',
              target: 'm1',
              fallbacks: const ['m2', 'm3'],
            ),
          ],
        ),
      );

      ProfileService.installProfile(
        config,
        _profile(),
        addedEnabled: false,
      );

      final u = config.upstreams.single;
      expect(u.models.length, 4);
      expect(u.models.first.publicName, 'auto');
      expect(u.models.first.enabled, isTrue, reason: '已有条目不动');
      for (final lane in ['m1', 'm2', 'm3']) {
        expect(
          ProfileService.isLaneExposed(config, 'u-demo', lane),
          isFalse,
          reason: '$lane 是迁移补进来的，不该凭空对外暴露',
        );
      }
    });
  });

  group('归属隔离', () {
    test('id 被用户自建上游占了：不认领也不改', () {
      config.upstreams.add(_userUpstream(id: 'u-demo'));

      final outcomes = ProfileService.installProfile(
        config,
        _profile(),
        addedEnabled: true,
      );

      expect(outcomes, [MergeOutcome.conflict]);
      expect(config.upstreams.single.managedBy, isNull);
      expect(config.upstreams.single.name, '我的 llama.cpp');
      expect(config.upstreams.single.models.map((m) => m.publicName), ['local']);
    });

    test('id 被别的档案占了：同样不动', () {
      config.upstreams.add(
        Upstream(
          id: 'u-demo',
          name: '别的档案',
          baseUrl: 'https://other.example/v1',
          managedBy: 'other-profile',
        ),
      );

      final outcomes = ProfileService.installProfile(
        config,
        _profile(),
        addedEnabled: true,
      );

      expect(outcomes, [MergeOutcome.conflict]);
      expect(config.upstreams.single.managedBy, 'other-profile');
      expect(config.upstreams.single.baseUrl, 'https://other.example/v1');
    });

    test('激活 B 只停 A 的上游，用户自建的一律不碰', () async {
      store.importDocument(_doc(id: 'pa'), const ProfileSource(ProfileSourceKind.inline));
      store.importDocument(
        _doc(id: 'pb', upstreamId: 'u-b', baseUrl: 'https://b.example/v1'),
        const ProfileSource(ProfileSourceKind.inline),
      );
      config.upstreams.add(_userUpstream());

      await ProfileService.activate(store: store, config: config, profileId: 'pa');
      expect(ProfileService.upstreamOf(config, 'u-demo')!.enabled, isTrue);

      await ProfileService.activate(store: store, config: config, profileId: 'pb');
      expect(store.activeId, 'pb');
      expect(
        ProfileService.upstreamOf(config, 'u-demo')!.enabled,
        isFalse,
        reason: 'A 装的上游该停用',
      );
      expect(
        ProfileService.upstreamOf(config, 'u-b')!.enabled,
        isTrue,
      );
      expect(
        ProfileService.upstreamOf(config, 'u-mine')!.enabled,
        isTrue,
        reason: '用户手加的上游绝不能被档案切换关掉',
      );
      expect(ProfileService.upstreamOf(config, 'u-mine')!.managedBy, isNull);
    });

    test('停用只翻 enabled：车道级开关留着，重新激活就回来了', () async {
      store.importDocument(_doc(), const ProfileSource(ProfileSourceKind.inline));
      await ProfileService.activate(store: store, config: config, profileId: 'demo');
      ProfileService.setLaneExposed(config, 'u-demo', 'm2', false);

      ProfileService.deactivate(store: store, config: config, profileId: 'demo');
      expect(ProfileService.upstreamOf(config, 'u-demo')!.enabled, isFalse);
      expect(store.activeId, isNull);
      // 车道级处置还在（上游停用只是不转发，不该把用户的选择抹掉）
      expect(
        ProfileService.upstreamOf(config, 'u-demo')!.models
            .firstWhere((m) => m.publicName == 'm2')
            .enabled,
        isFalse,
      );

      await ProfileService.activate(store: store, config: config, profileId: 'demo');
      expect(ProfileService.upstreamOf(config, 'u-demo')!.enabled, isTrue);
      expect(
        ProfileService.isLaneExposed(config, 'u-demo', 'm2'),
        isFalse,
        reason: '重新激活要还原用户之前的处置',
      );
    });

    test('删档案只摘掉归属自己的上游', () {
      store.importDocument(_doc(), const ProfileSource(ProfileSourceKind.inline));
      ProfileService.installProfile(config, _profile(), addedEnabled: true);
      config.upstreams.add(_userUpstream());
      store.setActive('demo');

      ProfileService.removeProfile(store: store, config: config, profileId: 'demo');

      expect(config.upstreams.map((u) => u.id), ['u-mine']);
      expect(store.activeId, isNull);
      expect(store.profileOf('demo'), isNull);
      expect(store.profileOf(kZenProfileId), isNotNull, reason: '内置的还在');
    });

    test('内置档案删不掉', () {
      ProfileService.removeProfile(
        store: store,
        config: config,
        profileId: kZenProfileId,
      );
      expect(store.profileOf(kZenProfileId), isNotNull);
    });
  });

  group('手改检测', () {
    test('用户换过 baseUrl 就标记 customized，且不覆盖他的地址', () {
      final p = _profile();
      ProfileService.installProfile(config, p, addedEnabled: true);
      expect(ProfileService.isCustomized(config, p), isFalse);

      config.upstreams.single.baseUrl = 'https://mirror.example/v1';
      expect(ProfileService.isCustomized(config, p), isTrue);

      ProfileService.installProfile(config, p, addedEnabled: true);
      expect(
        config.upstreams.single.baseUrl,
        'https://mirror.example/v1',
        reason: '合并只补缺，不覆盖用户改过的地址',
      );
    });
  });

  group('车道级处置', () {
    test('selectLane 提到链首，其余保持原顺序', () {
      ProfileService.installProfile(config, _profile(), addedEnabled: true);
      ProfileService.selectLane(config, 'u-demo', 'm2');
      expect(
        ProfileService.primaryRouteOf(config, 'u-demo')!.attempts,
        ['m2', 'm1', 'm3'],
      );
      // 再选一次同一个，顺序不该抖
      ProfileService.selectLane(config, 'u-demo', 'm2');
      expect(
        ProfileService.primaryRouteOf(config, 'u-demo')!.attempts,
        ['m2', 'm1', 'm3'],
      );
    });

    test('没有路由条目时 selectedLaneOf 是 null，selectLane 不炸', () {
      config.upstreams.add(
        Upstream(
          id: 'plain',
          name: 'Plain',
          baseUrl: 'https://p.example/v1',
          models: [ModelEntry(publicName: 'x', target: 'x')],
        ),
      );
      expect(ProfileService.selectedLaneOf(config, 'plain'), isNull);
      expect(ProfileService.primaryRouteOf(config, 'plain'), isNull);
      ProfileService.selectLane(config, 'plain', 'x'); // 不该抛
      expect(ProfileService.upstreamOf(config, 'plain')!.models.single.target, 'x');
    });

    test('上游不存在时各操作都安静返回', () {
      expect(ProfileService.isLaneExposed(config, 'ghost', 'x'), isFalse);
      ProfileService.setLaneExposed(config, 'ghost', 'x', true);
      expect(ProfileService.selectedLaneOf(config, 'ghost'), isNull);
    });
  });

  group('车道汇总', () {
    test('非 Zen 端点直接用文档里那份', () {
      final lanes = ProfileService.effectiveLanes(_profile().upstreams.single);
      expect(lanes, ['m1', 'm2', 'm3']);
    });

    test('Zen 端点拉到过实时清单就以上游为准', () {
      final template = builtinZenProfile().upstreams.single;
      expect(
        ProfileService.effectiveLanes(template),
        kZenFreeLanes,
        reason: '还没拉过，用文档兜底',
      );

      zenDiscovery.lanes = const ['only-one-left'];
      expect(ProfileService.effectiveLanes(template), ['only-one-left']);
    });
  });

  group('刷新可用模型列表（applyLiveLanes 对账）', () {
    Upstream installedFixture() => Upstream(
      id: 'u-demo',
      name: 'Demo',
      baseUrl: 'https://a.example/v1',
      managedBy: 'demo',
      models: [
        // 路由：链首 m2（用户挑过），链里 m3 已下架、m9 是新上的
        ModelEntry(
          publicName: 'auto',
          target: 'm2',
          fallbacks: ['m1', 'm3'],
        ),
        ModelEntry(publicName: 'm1', target: 'm1'),
        ModelEntry(publicName: 'm2', target: 'm2', enabled: false),
        ModelEntry(publicName: 'm3', target: 'm3'),
      ],
    );

    test('摘掉下架车道、保住用户开关与顺序、新车道补到链尾', () {
      final u = installedFixture();
      ProfileService.applyLiveLanes(u, ['m1', 'm2', 'm9']);

      // m3 的条目没了
      expect(u.models.any((m) => m.publicName == 'm3'), isFalse);
      // 用户关掉的 m2 还是关着
      expect(u.models.firstWhere((m) => m.publicName == 'm2').enabled, isFalse);
      // 新车道 m9 补进来了，且默认开着
      final m9 = u.models.firstWhere((m) => m.publicName == 'm9');
      expect(m9.enabled, isTrue);
      // 路由链：m2 还在链首，m3 被摘，m9 顶到链尾
      final route = u.models.firstWhere((m) => m.publicName == 'auto');
      expect(route.attempts, ['m2', 'm1', 'm9']);
    });

    test('整条链都下架时直接采纳实时清单', () {
      final u = installedFixture();
      ProfileService.applyLiveLanes(u, ['fresh-1', 'fresh-2']);

      final route = u.models.firstWhere((m) => m.publicName == 'auto');
      expect(route.attempts, ['fresh-1', 'fresh-2']);
      // 旧车道条目清光，新车道条目补上
      expect(u.models.any((m) => m.publicName == 'm1'), isFalse);
      expect(u.models.any((m) => m.publicName == 'fresh-1'), isTrue);
    });
  });
}
