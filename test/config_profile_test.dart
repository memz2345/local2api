import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/models/builtin_profiles.dart';
import 'package:local2api/models/config_profile.dart';
import 'package:local2api/models/proxy_config.dart';

const _inline = ProfileSource(ProfileSourceKind.inline);

/// 一份最小可用档案。
String _doc({
  String id = 'demo',
  String name = 'Demo',
  int? schema = 1,
  List<Map<String, dynamic>>? upstreams,
  Map<String, dynamic>? extra,
}) => jsonEncode({
  'schema': ?schema,
  'id': id,
  'name': name,
  ...?extra,
  'upstreams':
      upstreams ??
      [
        {
          'id': 'u1',
          'name': 'U1',
          'baseUrl': 'https://a.example/v1',
          'models': [
            {'publicName': 'm1', 'target': 'm1'},
          ],
        },
      ],
});

void main() {
  group('档案解析', () {
    test('最小档案能解析，来源由调用方给定而不是文档自报', () {
      final p = parseConfigProfile(
        _doc(),
        source: const ProfileSource(ProfileSourceKind.url, url: 'https://s/x'),
      );
      expect(p.id, 'demo');
      expect(p.name, 'Demo');
      expect(p.schema, kProfileSchema);
      expect(p.source.kind, ProfileSourceKind.url);
      expect(p.source.url, 'https://s/x');
      expect(p.upstreams.single.id, 'u1');
    });

    test('没写 schema 当 1，写了别的版本直接拒', () {
      expect(
        parseConfigProfile(_doc(schema: null), source: _inline).schema,
        kProfileSchema,
      );
      expect(
        () => parseConfigProfile(_doc(schema: 2), source: _inline),
        throwsA(
          isA<ProfileFormatException>().having(
            (e) => e.code,
            'code',
            ProfileFormatError.unsupportedSchema,
          ),
        ),
      );
    });

    test('id 缺失时用 name 推，两者都没有才报错', () {
      final raw = jsonEncode({
        'name': 'My Cool Profile!',
        'upstreams': jsonDecode(_doc())['upstreams'],
      });
      expect(
        parseConfigProfile(raw, source: _inline).id,
        'my-cool-profile',
      );

      final noId = jsonEncode({
        'upstreams': jsonDecode(_doc())['upstreams'],
      });
      expect(
        () => parseConfigProfile(noId, source: _inline),
        throwsA(
          isA<ProfileFormatException>().having(
            (e) => e.code,
            'code',
            ProfileFormatError.missingId,
          ),
        ),
      );
    });

    test('id 只留安全字符：它要当持久化键的一部分用', () {
      final raw = jsonEncode({
        'id': '../../etc/passwd 你好',
        'upstreams': jsonDecode(_doc())['upstreams'],
      });
      final id = parseConfigProfile(raw, source: _inline).id;
      // id 只进 SharedPreferences 的键、不落文件路径，所以点号本身无害
      //（com.example.profile 这类 id 还要靠它）；要保证的是分隔符进不来、
      // 首尾不留连字符、长度有上限。
      expect(id.contains('/'), isFalse);
      expect(id.contains(r'\'), isFalse);
      expect(id.contains(' '), isFalse);
      expect(id.startsWith('-') || id.endsWith('-'), isFalse);
      expect(id, isNotEmpty);
      expect(id.length, lessThanOrEqualTo(64));
    });

    test('name 缺失时退回 id', () {
      final raw = jsonEncode({
        'id': 'onlyid',
        'upstreams': jsonDecode(_doc())['upstreams'],
      });
      expect(parseConfigProfile(raw, source: _inline).name, 'onlyid');
    });

    test('监听端口 / 密钥 / 访问规则这些顶层键一律忽略', () {
      // 档案只描述「模型从哪来」。让一份粘贴进来的 JSON 能改监听地址、
      // 能塞自己的 API Key、能删 CIDR 拒绝规则，等于给订阅源开了个静默口子。
      final p = parseConfigProfile(
        _doc(
          extra: {
            'listenPort': 1,
            'listenHost': '0.0.0.0',
            'corsEnabled': false,
            'autoStart': true,
            'apiKeys': [
              {'id': 'k', 'name': 'k', 'key': 'sk-evil', 'enabled': true},
            ],
            'cidrRules': [
              {'id': 'c', 'cidr': '0.0.0.0/0', 'allow': true, 'enabled': true},
            ],
          },
        ),
        source: _inline,
      );
      // 解析结果里根本没有承载这些字段的地方，忽略即生效
      expect(p.upstreams.single.apiKey, isEmpty);
      expect(p.toJson().containsKey('listenPort'), isFalse);
      expect(p.toJson().containsKey('apiKeys'), isFalse);
      expect(p.toJson().containsKey('cidrRules'), isFalse);
    });

    test('上游模板里的 apiKey 在解析时就被剥掉', () {
      final p = parseConfigProfile(
        _doc(
          upstreams: [
            {
              'id': 'u1',
              'name': 'U1',
              'baseUrl': 'https://a.example/v1',
              'apiKey': 'sk-secret',
              'models': [
                {'publicName': 'm1', 'target': 'm1'},
              ],
            },
          ],
        ),
        source: _inline,
      );
      expect(p.upstreams.single.apiKey, isEmpty);
    });

    test('缺 id 或 baseUrl 的上游条目被丢掉，全丢光则拒收', () {
      final p = parseConfigProfile(
        _doc(
          upstreams: [
            {'id': '', 'baseUrl': 'https://a/v1'},
            {'id': 'u2', 'baseUrl': ''},
            {
              'id': 'u3',
              'baseUrl': 'https://c/v1',
              'models': [
                {'publicName': 'm', 'target': 'm'},
              ],
            },
          ],
        ),
        source: _inline,
      );
      expect(p.upstreams.map((u) => u.id), ['u3']);

      expect(
        () => parseConfigProfile(
          _doc(upstreams: [
            {'id': '', 'baseUrl': ''},
          ]),
          source: _inline,
        ),
        throwsA(
          isA<ProfileFormatException>().having(
            (e) => e.code,
            'code',
            ProfileFormatError.noUpstreams,
          ),
        ),
      );
    });

    test('坏输入分档报因：空 / 不是 JSON / 顶层不是对象 / 没上游', () {
      expect(
        () => parseConfigProfile('   ', source: _inline),
        throwsA(
          isA<ProfileFormatException>().having(
            (e) => e.code,
            'code',
            ProfileFormatError.empty,
          ),
        ),
      );
      // 用户填了个 Clash YAML 订阅地址时最常撞这条，得给得懂的提示
      expect(
        () => parseConfigProfile(
          'proxies:\n  - name: x\n    type: ss\n',
          source: _inline,
        ),
        throwsA(
          isA<ProfileFormatException>().having(
            (e) => e.code,
            'code',
            ProfileFormatError.notJson,
          ),
        ),
      );
      expect(
        () => parseConfigProfile('[1,2,3]', source: _inline),
        throwsA(
          isA<ProfileFormatException>().having(
            (e) => e.code,
            'code',
            ProfileFormatError.notObject,
          ),
        ),
      );
      expect(
        () => parseConfigProfile(
          jsonEncode({'id': 'x', 'upstreams': []}),
          source: _inline,
        ),
        throwsA(
          isA<ProfileFormatException>().having(
            (e) => e.code,
            'code',
            ProfileFormatError.noUpstreams,
          ),
        ),
      );
    });
  });

  group('车道汇总', () {
    test('取的是上游真实模型名，不是对外暴露名', () {
      // 路由条目的 publicName 是 zen-free，真正的车道在 target + fallbacks 里。
      // 拿 publicName 去探测等于去问上游「你有 zen-free 这个模型吗」，必然白跑。
      final p = builtinZenProfile();
      final lanes = p.lanes;
      expect(lanes, isNot(contains(kZenRouteName)));
      expect(lanes, containsAll(kZenFreeLanes));
      expect(lanes.length, kZenFreeLanes.length);
    });

    test('跨上游去重', () {
      final p = parseConfigProfile(
        _doc(
          upstreams: [
            {
              'id': 'a',
              'baseUrl': 'https://a/v1',
              'models': [
                {'publicName': 'shared', 'target': 'shared'},
                {'publicName': 'only-a', 'target': 'only-a'},
              ],
            },
            {
              'id': 'b',
              'baseUrl': 'https://b/v1',
              'models': [
                {'publicName': 'shared', 'target': 'shared'},
              ],
            },
          ],
        ),
        source: _inline,
      );
      expect(p.lanes, ['shared', 'only-a']);
    });
  });

  group('内置档案', () {
    test('id / 上游 id 沿用广场时代的旧值，迁移才认得出归属', () {
      final p = builtinZenProfile();
      expect(p.id, kZenProfileId);
      expect(p.id, 'opencodezen');
      expect(p.upstreams.single.id, 'plaza-opencode-zen');
      expect(p.upstreams.single.baseUrl, kOpenCodeZenBaseUrl);
      expect(p.source.kind, ProfileSourceKind.builtin);
    });

    test('同时声明容灾路由和零散车道', () {
      final models = builtinZenProfile().upstreams.single.models;
      final route = models.firstWhere((m) => m.publicName == kZenRouteName);
      expect(route.target, kZenFreeLanes.first);
      expect(route.fallbacks, kZenFreeLanes.skip(1).toList());
      expect(
        models.where((m) => m.publicName != kZenRouteName).length,
        kZenFreeLanes.length,
      );
    });

    test('兜底车道表 = 2026-10-22 上游 /zen/v1/models 的可用 free 清单', () {
      // 上游每次上下架都会变；这份 const 只当冷启动/断网兜底，
      // 真正的集合由发现页刷新（applyLiveLanes）对账。
      // jev-1.13-free 也是 free，但它是 systemone 判定模型，不能接聊天，
      // 由 zenFilterUsableLanes 滤掉，所以不在这张聊天车道表里。
      expect(kZenFreeLanes, [
        'nemotron-3.5-super-vl-free',
        'minimax-m3.1-flash-free',
        'mimo-v2.6-flash-free',
        'nemotron-3.5-lightning-free',
        'deepseek-v4.1-flash-free',
        'glm-5.3-flash-free',
        'flint-40b-free',
        'beam-free',
        'big-pickle',
      ]);
      // 已下架的旧车道一律摘掉：留在兜底表里只会让冷启动去探测
      // 一批不存在或已下架的车道。
      for (final dropped in [
        'space-bunny-free',
        'mimo-v2.5-free',
        'ling-3.0-flash-fin-free',
        'nemotron-3-ultra-free',
        'muse-spark-1.3-contributor-free',
        'muse-spark-1.2-contributor-free',
        'jev-1.13-free',
      ]) {
        expect(kZenFreeLanes, isNot(contains(dropped)), reason: dropped);
      }
      // 路由链跟着换，但**上游 id 必须不动**：那是迁移认领归属用的键，
      // 改了会丢用户已经手调过的车道开关与回退顺序。
      expect(kZenUpstreamId, 'plaza-opencode-zen');
      final models = builtinZenProfile().upstreams.single.models;
      expect(models.firstWhere((m) => m.publicName == kZenRouteName).target,
          'nemotron-3.5-super-vl-free');
      expect(builtinZenProfile().upstreams.single.id, kZenUpstreamId);
    });

    test('每次调用都给新对象：模板被装进配置后改动不能污染下次', () {
      final a = builtinZenProfile();
      a.upstreams.single.models.first.target = '被改坏了';
      a.upstreams.single.name = '被改名了';
      final b = builtinZenProfile();
      expect(b.upstreams.single.models.first.target, kZenFreeLanes.first);
      expect(b.upstreams.single.name, 'OpenCode Zen');
    });
  });

  group('状态序列化', () {
    test('ProfileState 往返一致', () {
      final s = ProfileState(
        profileId: 'demo',
        active: true,
        lastUpdateMs: 1234,
        lastError: 'HTTP 500',
        etag: 'W/"abc"',
        customized: true,
        updateIntervalHours: 12,
        updateAvailable: true,
      );
      final back = ProfileState.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(back.profileId, 'demo');
      expect(back.active, isTrue);
      expect(back.lastUpdateMs, 1234);
      expect(back.lastError, 'HTTP 500');
      expect(back.etag, 'W/"abc"');
      expect(back.customized, isTrue);
      expect(back.updateIntervalHours, 12);
      expect(back.updateAvailable, isTrue);
    });

    test('缺字段的状态给安全默认值', () {
      final s = ProfileState.fromJson(const {'profileId': 'x'});
      expect(s.active, isFalse);
      expect(s.customized, isFalse);
      expect(s.updateAvailable, isFalse);
      expect(s.lastUpdateMs, isNull);
    });

    test('ProxyConfig 带上 managedBy 往返，旧配置读出来是 null', () {
      final config = ProxyConfig(
        upstreams: [
          Upstream(
            id: 'u',
            name: 'U',
            baseUrl: 'https://a/v1',
            managedBy: 'demo',
          ),
          Upstream(id: 'v', name: 'V', baseUrl: 'https://b/v1'),
        ],
      );
      final back = ProxyConfig.fromJson(
        jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>,
      );
      expect(back.upstreams[0].managedBy, 'demo');
      expect(back.upstreams[1].managedBy, isNull);

      // 升级前的老配置没有这个键
      final legacy = ProxyConfig.fromJson({
        'upstreams': [
          {'id': 'old', 'name': 'Old', 'baseUrl': 'https://c/v1'},
        ],
      });
      expect(legacy.upstreams.single.managedBy, isNull);
    });
  });
}
