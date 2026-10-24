import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/usage_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';

TokenUsage _r({
  required DateTime at,
  String model = 'zen-free',
  int input = 100,
  int output = 50,
  int hit = 0,
  int miss = 0,
  String keyId = '',
  String keyName = '',
  String keyLabel = '',
}) => TokenUsage(
  timeMs: at.millisecondsSinceEpoch,
  model: model,
  upstream: 'OpenCode Zen',
  lane: 'space-bunny-free',
  input: input,
  output: output,
  cacheHit: hit,
  cacheMiss: miss == 0 && input > 0 ? input - hit : miss,
  apiKeyId: keyId,
  apiKeyName: keyName,
  apiKeyLabel: keyLabel,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('按 API Key / 按模型归账', () {
    late UsageStats stats;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      stats = UsageStats();
      await stats.load();
    });

    tearDown(() => stats.dispose());

    test('密钥脱敏：只留头 8 尾 4，短串不还原全文', () {
      expect(UsageStats.maskKey('sk-abcdefgh12345678zzzz'), 'sk-abcde**zzzz');
      expect(UsageStats.maskKey(''), '');
      // 短到打星没意义的：不留能反推出原文的片段
      expect(UsageStats.maskKey('abc123'), 'a**3');
    });

    test('同一把 key 的量能单独算出来', () {
      final now = DateTime.now();
      stats
        ..add(
          _r(
            at: now,
            model: 'zen-free',
            input: 1000,
            output: 200,
            keyId: 'key-a',
            keyName: '主力',
            keyLabel: 'sk-aaaa**1111',
          ),
        )
        ..add(
          _r(
            at: now,
            model: 'local',
            input: 40,
            output: 10,
            keyId: 'key-b',
            keyName: '备用',
            keyLabel: 'sk-bbbb**2222',
          ),
        )
        ..add(_r(at: now, model: 'local', input: 7, output: 3));

      final a = stats.summarize(apiKeyId: 'key-a');
      expect(a.requests, 1);
      expect(a.total, 1200);

      // 空串是「没带密钥的那些调用」，不是「全部」
      final anon = stats.summarize(apiKeyId: '');
      expect(anon.requests, 1);
      expect(anon.total, 10);

      final refs = stats.keysWithin();
      expect(refs.map((r) => r.name), ['主力', '备用', '']);
      expect(refs.last.id, ''); // 未鉴权垫底
    });

    test('各模型用量只列真打过的模型，多的排前面', () {
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      stats
        ..add(_r(at: now, model: 'zen-free', input: 900, output: 100))
        ..add(_r(at: now, model: 'local', input: 10, output: 5))
        ..add(_r(at: yesterday, model: 'mimo-old', input: 5, output: 5));

      final rows = stats.byModel(
        from: DateTime(now.year, now.month, now.day),
      );
      // 昨天的那条被时间范围切掉了：表里只列范围内的「真打过」
      expect(rows.map((r) => r.model), ['zen-free', 'local']);
      expect(rows.first.summary.total, 1000);
      expect(rows.last.summary.total, 15);

      // 换个时间维度，昨天的那条就该出现了
      final wider = stats.byModel(from: yesterday);
      expect(wider.map((r) => r.model), ['zen-free', 'local', 'mimo-old']);
    });

    test('老账本（没有 key 字段）读进来按未鉴权归', () {
      final old = jsonDecode('''
        {"records":[{"timeMs":1,"model":"m","upstream":"u","lane":"l",
        "input":5,"output":5,"cacheHit":0,"cacheMiss":5}]}
      ''') as Map<String, dynamic>;
      final r = TokenUsage.fromJson(
        (old['records'] as List).first as Map<String, dynamic>,
      );
      expect(r.hasApiKey, isFalse);
      expect(r.apiKeyId, '');
    });
  });

  group('usage 字段归一', () {
    test('OpenAI 系：prompt_tokens_details.cached_tokens', () {
      final t = UsageTotals.fromUsage({
        'prompt_tokens': 1000,
        'completion_tokens': 200,
        'prompt_tokens_details': {'cached_tokens': 768},
        'completion_tokens_details': {'reasoning_tokens': 64},
      });
      expect(t.input, 1000);
      expect(t.output, 200);
      expect(t.cacheHit, 768);
      // 上游没给 miss，按 input - hit 推
      expect(t.cacheMiss, 232);
      expect(t.reasoning, 64);
    });

    test('DeepSeek 系：prompt_cache_hit_tokens / miss', () {
      final t = UsageTotals.fromUsage({
        'prompt_tokens': 500,
        'completion_tokens': 30,
        'prompt_cache_hit_tokens': 400,
        'prompt_cache_miss_tokens': 100,
      });
      expect(t.cacheHit, 400);
      expect(t.cacheMiss, 100);
    });

    test('input_tokens / output_tokens 别名也认（Anthropic 归一形状）', () {
      final t = UsageTotals.fromUsage({
        'input_tokens': 10,
        'output_tokens': 5,
      });
      expect(t.input, 10);
      expect(t.output, 5);
    });
  });

  group('响应里抠 usage', () {
    test('非流式：顶层对象的 usage', () {
      final ex = UsageExtractor();
      ex.addText(
        jsonEncode({
          'id': 'x',
          'choices': [
            {
              'message': {'content': 'hi', 'role': 'assistant'},
            },
          ],
          'usage': {'prompt_tokens': 12, 'completion_tokens': 3},
        }),
      );
      final t = ex.extract();
      expect(t, isNotNull);
      expect(t!.input, 12);
      expect(t.output, 3);
    });

    test('流式：只认最后一帧那份 usage', () {
      final ex = UsageExtractor();
      ex.addBytes(
        utf8.encode(
          'data: {"choices":[{"delta":{"content":"你"}}]}\n\n'
          'data: {"choices":[{"delta":{"content":"好"}}]}\n\n'
          'data: {"choices":[],"usage":{"prompt_tokens":7,"completion_tokens":2}}\n\n'
          'data: [DONE]\n\n',
        ),
      );
      final t = ex.extract();
      expect(t, isNotNull);
      expect(t!.input, 7);
      expect(t.output, 2);
    });

    test('没有 usage 时给 null', () {
      final ex = UsageExtractor();
      ex.addText('data: {"choices":[{"delta":{"content":"hi"}}]}\n\n');
      expect(ex.extract(), isNull);
    });

    test('分片到达（一帧被拆成几块）也能抠出来', () {
      final ex = UsageExtractor();
      ex.addText('data: {"choices":[],"usa');
      ex.addText('ge":{"prompt_tokens":9,"comple');
      ex.addText('tion_tokens":4}}\n\n');
      final t = ex.extract();
      expect(t, isNotNull);
      expect(t!.input, 9);
      expect(t.output, 4);
    });
  });

  group('记账与聚合', () {
    late UsageStats stats;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      stats = UsageStats();
      await stats.load();
    });

    tearDown(() => stats.dispose());

    test('按模型与时间过滤，汇总输入/输出/命中', () {
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      stats.add(_r(at: today, model: 'zen-free', input: 100, output: 20, hit: 80));
      stats.add(_r(at: today, model: 'local', input: 10, output: 5));
      stats.add(_r(at: yesterday, model: 'zen-free', input: 50, output: 10));

      final all = stats.summarize();
      expect(all.requests, 3);
      expect(all.input, 160);
      expect(all.output, 35);
      expect(all.cacheHit, 80);
      expect(all.cacheMiss, 80); // 160 - 80

      final zenOnly = stats.summarize(model: 'zen-free');
      expect(zenOnly.requests, 2);
      expect(zenOnly.input, 150);

      final todayOnly = stats.summarize(
        from: DateTime(today.year, today.month, today.day),
      );
      expect(todayOnly.requests, 2);
      expect(todayOnly.output, 25);
    });

    test('模型列表去重并排序', () {
      stats.add(_r(at: DateTime.now(), model: 'zzz'));
      stats.add(_r(at: DateTime.now(), model: 'aaa'));
      stats.add(_r(at: DateTime.now(), model: 'aaa'));
      expect(stats.models, ['aaa', 'zzz']);
    });

    test('按天分桶', () {
      final now = DateTime.now();
      final d0 = DateTime(now.year, now.month, now.day);
      final d1 = d0.subtract(const Duration(days: 1));
      stats.add(_r(at: d1.add(const Duration(hours: 10)), input: 5, output: 5));
      // 「今天」这两条直接落在当前时刻：写死 d0+2h / d0+3h 的话，凌晨跑测试
      // 它们就是未来时间，而 byDay 默认 to=now，会被整桶滤掉。
      stats.add(_r(at: now, input: 100, output: 0));
      stats.add(_r(at: now, input: 100, output: 0));

      final days = stats.byDay(from: d1);
      expect(days, hasLength(2));
      expect(days.first.day, d1);
      expect(days.first.summary.total, 10);
      expect(days.last.day, d0);
      expect(days.last.summary.total, 200);
    });

    test('命中率算得对，输入为 0 时给 0 不除零', () {
      expect(const UsageSummary(input: 100, cacheHit: 25).hitRate, 0.25);
      expect(const UsageSummary().hitRate, 0);
    });

    test('超过上限时丢最旧的', () {
      final base = DateTime(2026, 1, 1).millisecondsSinceEpoch;
      for (var i = 0; i < UsageStats.maxRecords + 50; i++) {
        stats.add(
          TokenUsage(
            timeMs: base + i * 1000,
            model: 'm',
            upstream: 'u',
            lane: 'l',
            input: 1,
            output: 1,
          ),
        );
      }
      expect(stats.records, hasLength(UsageStats.maxRecords));
      // 最新的在最前
      expect(
        stats.records.first.timeMs,
        base + (UsageStats.maxRecords + 49) * 1000,
      );
    });
  });
}
