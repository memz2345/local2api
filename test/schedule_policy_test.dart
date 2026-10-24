import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/model_schedule.dart';
import 'package:local2api/services/proxy_server.dart';

void main() {
  // 注意：不要调用 TestWidgetsFlutterBinding.ensureInitialized()，
  // 它会把测试里所有 HttpClient 请求劫持成 400（见 proxy_server_test.dart）。

  group('ScheduleRule 窗口匹配', () {
    test('同天内 [start, end) 含头不含尾', () {
      final rule = ScheduleRule(
        id: 'r',
        targets: ['m'],
        startHour: 9,
        endHour: 18,
      );
      expect(rule.matches(DateTime(2026, 10, 12, 8)), isFalse);
      expect(rule.matches(DateTime(2026, 10, 12, 9)), isTrue);
      expect(rule.matches(DateTime(2026, 10, 12, 17)), isTrue);
      expect(rule.matches(DateTime(2026, 10, 12, 18)), isFalse);
    });

    test('跨天窗口（22-6）', () {
      final rule = ScheduleRule(
        id: 'r',
        targets: ['m'],
        startHour: 22,
        endHour: 6,
      );
      expect(rule.matches(DateTime(2026, 10, 12, 23)), isTrue);
      expect(rule.matches(DateTime(2026, 10, 12, 3)), isTrue);
      expect(rule.matches(DateTime(2026, 10, 12, 12)), isFalse);
    });

    test('星期不匹配时不命中', () {
      // 2026-10-12 是周一
      final monday = DateTime(2026, 10, 12, 10);
      expect(monday.weekday, DateTime.monday);
      final onlyWeekend = ScheduleRule(
        id: 'r',
        targets: ['m'],
        weekdays: const [6, 7],
        startHour: 0,
        endHour: 24,
      );
      expect(onlyWeekend.matches(monday), isFalse);
      expect(
        onlyWeekend.matches(DateTime(2026, 10, 17, 10)), // 周六
        isTrue,
      );
    });

    test('endHour=24 覆盖到当天最后一小时', () {
      final rule = ScheduleRule(
        id: 'r',
        targets: ['m'],
        startHour: 0,
        endHour: 24,
      );
      expect(rule.matches(DateTime(2026, 10, 12, 23)), isTrue);
    });

    test('序列化 round-trip 保留方向与范围', () {
      final rule = ScheduleRule(
        id: 'r1',
        targets: ['grp'],
        mode: ScheduleMode.deny,
        weekdays: const [1, 2],
        startHour: 22,
        endHour: 6,
        enabled: false,
      );
      final back = ScheduleRule.fromJson(
        (jsonDecode(jsonEncode(rule.toJson())) as Map<String, dynamic>),
      );
      expect(back.targets, ['grp']);
      expect(back.mode, ScheduleMode.deny);
      expect(back.weekdays, [1, 2]);
      expect(back.startHour, 22);
      expect(back.endHour, 6);
      expect(back.enabled, isFalse);
    });

    test('多目标：一条规则管好几个模型', () {
      final rules = [
        ScheduleRule(
          id: 'r',
          targets: ['a', 'b'],
          mode: ScheduleMode.deny,
          startHour: 0,
          endHour: 24,
        ),
      ];
      final now = DateTime(2026, 10, 12, 12);
      expect(scheduleAllows(rules: rules, model: 'a', now: now).allowed, isFalse);
      expect(scheduleAllows(rules: rules, model: 'b', now: now).allowed, isFalse);
      expect(scheduleAllows(rules: rules, model: 'c', now: now).allowed, isTrue);
    });

    test('老格式（单 target + scope）照样读得进来', () {
      final back = ScheduleRule.fromJson({
        'id': 'old',
        'target': 'zen',
        'scope': 'group',
        'mode': 'deny',
        'startHour': 9,
        'endHour': 18,
        'enabled': true,
      });
      expect(back.targets, ['zen']);
      // 以前「组级」的语义还在：groupId 命中同一条规则
      expect(
        scheduleAllows(
          rules: [back],
          model: 'other',
          groupId: 'zen',
          now: DateTime(2026, 10, 12, 12),
        ).allowed,
        isFalse,
      );
    });

    test('非法小时被夹回合法区间', () {
      final back = ScheduleRule.fromJson({
        'id': 'x',
        'target': 'm',
        'startHour': 99,
        'endHour': -3,
      });
      expect(back.startHour, inInclusiveRange(0, 23));
      expect(back.endHour, inInclusiveRange(0, 24));
    });
  });

  group('scheduleAllows 判定', () {
    final mondayMorning = DateTime(2026, 10, 12, 10); // 周一 10 点

    test('没有配规则 = 全天放行', () {
      expect(
        scheduleAllows(
          rules: const [],
          model: 'm',
          now: mondayMorning,
        ).allowed,
        isTrue,
      );
    });

    test('正向：窗口内放行、窗口外拒绝', () {
      final rules = [
        ScheduleRule(
          id: 'r',
          targets: ['m'],
          mode: ScheduleMode.allow,
          weekdays: const [1, 2, 3, 4, 5, 6],
          startHour: 9,
          endHour: 18,
        ),
      ];
      expect(
        scheduleAllows(
          rules: rules,
          model: 'm',
          now: mondayMorning,
        ).allowed,
        isTrue,
      );
      final blocked = scheduleAllows(
        rules: rules,
        model: 'm',
        now: DateTime(2026, 10, 12, 20),
      );
      expect(blocked.allowed, isFalse);
      expect(blocked.reason, contains('m'));
    });

    test('反向：窗口内拒绝、窗口外放行', () {
      final rules = [
        ScheduleRule(
          id: 'r',
          targets: ['m'],
          mode: ScheduleMode.deny,
          startHour: 9,
          endHour: 18,
        ),
      ];
      expect(
        scheduleAllows(rules: rules, model: 'm', now: mondayMorning).allowed,
        isFalse,
      );
      expect(
        scheduleAllows(
          rules: rules,
          model: 'm',
          now: DateTime(2026, 10, 12, 20),
        ).allowed,
        isTrue,
      );
    });

    test('先命中先生效：deny 压住后面的 allow', () {
      final rules = [
        ScheduleRule(
          id: 'deny',
          targets: ['m'],
          mode: ScheduleMode.deny,
          startHour: 0,
          endHour: 24,
        ),
        ScheduleRule(
          id: 'allow',
          targets: ['m'],
          mode: ScheduleMode.allow,
          startHour: 0,
          endHour: 24,
        ),
      ];
      expect(
        scheduleAllows(rules: rules, model: 'm', now: mondayMorning).allowed,
        isFalse,
      );
    });

    test('模型组级规则按 managedBy 匹配', () {
      final rules = [
        ScheduleRule(
          id: 'r',
          targets: ['zen'],
          mode: ScheduleMode.deny,
          startHour: 0,
          endHour: 24,
        ),
      ];
      expect(
        scheduleAllows(
          rules: rules,
          model: 'm',
          groupId: 'zen',
          now: mondayMorning,
        ).allowed,
        isFalse,
      );
      // 别组不受影响
      expect(
        scheduleAllows(
          rules: rules,
          model: 'm',
          groupId: 'other',
          now: mondayMorning,
        ).allowed,
        isTrue,
      );
      // 组 id 为空（用户手加的上游）也匹配不上
      expect(
        scheduleAllows(rules: rules, model: 'm', now: mondayMorning).allowed,
        isTrue,
      );
    });

    test('停用的规则不参与判定', () {
      final rules = [
        ScheduleRule(
          id: 'r',
          targets: ['m'],
          mode: ScheduleMode.deny,
          enabled: false,
          startHour: 0,
          endHour: 24,
        ),
      ];
      expect(
        scheduleAllows(rules: rules, model: 'm', now: mondayMorning).allowed,
        isTrue,
      );
    });
  });

  group('峰谷策略在代理链路上生效', () {
    late HttpServer mockUpstream;
    late ProxyServer proxy;
    late ProxyConfig config;

    setUp(() async {
      mockUpstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      mockUpstream.listen((req) async {
        req.response.headers.contentType = ContentType.json;
        req.response.write('{"choices":[{"message":{"content":"hi"}}]}');
        await req.response.close();
      });
      config = ProxyConfig(listenHost: '127.0.0.1', listenPort: 19295)
        ..upstreams.add(
          Upstream(
            id: 'u1',
            name: 'mock',
            baseUrl: 'http://127.0.0.1:${mockUpstream.port}/v1',
            managedBy: 'zen',
            models: [ModelEntry(publicName: 'peak-model')],
          ),
        );
      proxy = ProxyServer(configProvider: () => config);
      await proxy.start();
    });

    tearDown(() async {
      await proxy.stop();
      await mockUpstream.close(force: true);
    });

    Future<(int, String)> send(
      Map<String, dynamic> body, {
      bool sim = false,
    }) async {
      final client = HttpClient();
      final req = await client.postUrl(
        Uri.parse('http://127.0.0.1:19295/v1/chat/completions'),
      );
      req.headers.contentType = ContentType.json;
      if (sim) req.headers.set(kSimRequestHeader, '1');
      req.write(jsonEncode(body));
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      client.close();
      return (res.statusCode, text);
    }

    test('窗口外：正向策略让请求吃 403', () async {
      // 周一 20 点，策略只放行周一至周六 9-18 点
      final mondayEvening = DateTime(2026, 10, 12, 20);
      config.scheduleRules.add(
        ScheduleRule(
          id: 'r1',
          targets: ['peak-model'],
          mode: ScheduleMode.allow,
          weekdays: const [1, 2, 3, 4, 5, 6],
          startHour: 9,
          endHour: 18,
        ),
      );
      proxy.nowProvider = () => mondayEvening;
      final (status, text) = await send({'model': 'peak-model'});
      expect(status, 403);
      expect(text, contains('permission_error'));

      // 窗口内放行
      proxy.nowProvider = () => DateTime(2026, 10, 12, 10);
      final (ok, _) = await send({'model': 'peak-model'});
      expect(ok, 200);
    });

    test('反向策略在选中时段拦截', () async {
      config.scheduleRules.add(
        ScheduleRule(
          id: 'r1',
          targets: ['peak-model'],
          mode: ScheduleMode.deny,
          startHour: 9,
          endHour: 18,
        ),
      );
      proxy.nowProvider = () => DateTime(2026, 10, 12, 10);
      final (status, _) = await send({'model': 'peak-model'});
      expect(status, 403);

      proxy.nowProvider = () => DateTime(2026, 10, 12, 20);
      final (ok, _) = await send({'model': 'peak-model'});
      expect(ok, 200);
    });

    test('组级策略整组拦截', () async {
      config.scheduleRules.add(
        ScheduleRule(
          id: 'r1',
          targets: ['zen'],
          mode: ScheduleMode.deny,
          startHour: 0,
          endHour: 24,
        ),
      );
      proxy.nowProvider = () => DateTime(2026, 10, 12, 10);
      final (status, _) = await send({'model': 'peak-model'});
      expect(status, 403);
    });

    test('模拟对话带标记：策略一律放行', () async {
      config.scheduleRules.add(
        ScheduleRule(
          id: 'r1',
          targets: ['peak-model'],
          mode: ScheduleMode.deny,
          startHour: 0,
          endHour: 24,
        ),
      );
      proxy.nowProvider = () => DateTime(2026, 10, 12, 10);
      final (status, _) = await send({'model': 'peak-model'}, sim: true);
      expect(status, 200);
    });

    test('/v1/models 与转发同一口径：窗口外看不到这个模型', () async {
      config.scheduleRules.add(
        ScheduleRule(
          id: 'r1',
          targets: ['peak-model'],
          mode: ScheduleMode.deny,
          startHour: 0,
          endHour: 24,
        ),
      );
      proxy.nowProvider = () => DateTime(2026, 10, 12, 10);
      final client = HttpClient();
      final req = await client.getUrl(
        Uri.parse('http://127.0.0.1:19295/v1/models'),
      );
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      client.close();
      expect(res.statusCode, 200);
      expect(text, isNot(contains('peak-model')));

      // 关掉策略后立刻回来
      config.scheduleRules.clear();
      final c2 = HttpClient();
      final r2 = await c2.getUrl(
        Uri.parse('http://127.0.0.1:19295/v1/models'),
      );
      final res2 = await r2.close();
      final text2 = await res2.transform(utf8.decoder).join();
      c2.close();
      expect(text2, contains('peak-model'));
    });
  });

  group('ProxyConfig 新增字段向后兼容', () {
    test('老配置没有 webUi / scheduleRules 键时落到默认值', () {
      final old = ProxyConfig.fromJson({'listenPort': 9999});
      expect(old.webUiEnabled, isFalse);
      expect(old.webUiPort, 9293);
      expect(old.webUiHost, '127.0.0.1');
      expect(old.scheduleRules, isEmpty);
    });

    test('新字段 round-trip 不丢', () {
      final config = ProxyConfig(
        listenPort: 1234,
        webUiEnabled: true,
        webUiPort: 9393,
        webUiHost: '0.0.0.0',
      )..scheduleRules.add(
          ScheduleRule(
            id: 'r1',
            targets: ['m'],
            mode: ScheduleMode.deny,
            weekdays: const [1, 3],
            startHour: 1,
            endHour: 5,
          ),
        );
      final back = ProxyConfig.fromJson(
        (jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>),
      );
      expect(back.webUiEnabled, isTrue);
      expect(back.webUiPort, 9393);
      expect(back.webUiHost, '0.0.0.0');
      expect(back.scheduleRules.length, 1);
      expect(back.scheduleRules.first.mode, ScheduleMode.deny);
      expect(back.scheduleRules.first.weekdays, [1, 3]);
    });

    test('策略为空时不写 scheduleRules 键', () {
      final json = ProxyConfig().toJson();
      expect(json.containsKey('scheduleRules'), isFalse);
    });
  });
}
