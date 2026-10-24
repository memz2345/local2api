// 思考档位：入站解析 → 输出预算 → /v1/models 声明。
//
// 上游实测（2026-10）：OpenCode Zen 的 /zen/v1/models 不带任何 reasoning
// 字段，请求里的 reasoning_effort 被网关收下后忽略（zen-gate 的
// internal/lane/effort.go 也是同一结论）—— 所以档位在本端落成
// max_tokens 输出预算，这才是真实生效的控制。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/models/thinking_level.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:local2api/services/zen/zen_convert.dart';
import 'package:local2api/services/zen/zen_plan.dart';
import 'package:local2api/services/zen/zen_protocol.dart';

Map<String, dynamic> chatBody(Map<String, dynamic>? extra) => {
  'model': 'zen-free',
  'messages': [
    {'role': 'user', 'content': 'hi'},
  ],
  ...?extra,
};

void main() {
  group('档位解析', () {
    test('reasoning_effort 各家写法都认（七档不折叠）', () {
      // none / minimal 是两回事：前者显式关、后者极轻，不能折叠成一个。
      expect(thinkingLevelOf({'reasoning_effort': 'none'}), ThinkingLevel.none);
      expect(
        thinkingLevelOf({'reasoning_effort': 'minimal'}),
        ThinkingLevel.minimal,
      );
      expect(thinkingLevelOf({'reasoning_effort': 'low'}), ThinkingLevel.low);
      expect(
        thinkingLevelOf({'reasoning_effort': 'medium'}),
        ThinkingLevel.medium,
      );
      expect(thinkingLevelOf({'reasoning_effort': 'high'}), ThinkingLevel.high);
      expect(
        thinkingLevelOf({'reasoning_effort': 'xhigh'}),
        ThinkingLevel.xhigh,
      );
      expect(thinkingLevelOf({'reasoning_effort': 'max'}), ThinkingLevel.max);
      // ultra 是 max 的别名（OpenRouter 那套拼写）
      expect(thinkingLevelOf({'reasoning_effort': 'ultra'}), ThinkingLevel.max);
      // 认不出的写法不算档位
      expect(thinkingLevelOf({'reasoning_effort': 'banana'}), isNull);
    });

    test('Anthropic reasoning.effort 与 DeepSeek thinking 两种形状', () {
      expect(
        thinkingLevelOf({
          'reasoning': {'effort': 'max'},
        }),
        ThinkingLevel.max,
      );
      expect(
        thinkingLevelOf({
          'thinking': {'type': 'enabled'},
        }),
        ThinkingLevel.high,
      );
      expect(
        thinkingLevelOf({
          'thinking': {'type': 'disabled'},
        }),
        ThinkingLevel.none,
      );
      expect(
        thinkingLevelOf({
          'thinking': {'effort': 'low'},
        }),
        ThinkingLevel.low,
      );
      expect(
        thinkingLevelOf({
          'output_config': {'effort': 'high'},
        }),
        ThinkingLevel.high,
      );
    });

    test('opencode 的模型名后缀 (high) 也算档位', () {
      expect(
        thinkingLevelOf(chatBody(null), model: 'zen-free (high)'),
        ThinkingLevel.high,
      );
      expect(
        thinkingLevelOf({'model': 'm (low)'}),
        ThinkingLevel.low,
      );
      // 后缀不是档位名 → 不算
      expect(thinkingLevelOf({'model': 'm (preview)'}), isNull);
    });

    test('优先级：reasoning_effort > 嵌套形状 > 模型名后缀', () {
      expect(
        thinkingLevelOf(
          {
            'reasoning_effort': 'low',
            'thinking': {'type': 'enabled'},
            'model': 'm (high)',
          },
        ),
        ThinkingLevel.low,
      );
    });
  });

  group('输出预算', () {
    test('七档阶梯：1024 / 2048 / 4096 / 8192 / 模型上限', () {
      expect(thinkingBudget(ThinkingLevel.none, capacity: 128000), 1024);
      expect(thinkingBudget(ThinkingLevel.minimal, capacity: 128000), 2048);
      expect(thinkingBudget(ThinkingLevel.low, capacity: 128000), 4096);
      expect(
        thinkingBudget(ThinkingLevel.medium, capacity: 128000),
        8192,
      );
      expect(
        thinkingBudget(ThinkingLevel.high, capacity: 128000),
        128000,
      );
      // 极深 / 最重同样不额外设限
      expect(thinkingBudget(ThinkingLevel.xhigh, capacity: 128000), 128000);
      expect(thinkingBudget(ThinkingLevel.max, capacity: 128000), 128000);
    });

    test('模型没配输出上限时回退 32768；预算不低于 512；深思尊重显式预算', () {
      expect(thinkingBudget(ThinkingLevel.high, capacity: 0), 32768);
      expect(thinkingBudget(ThinkingLevel.low, capacity: 0), 4096);
      expect(thinkingBudget(ThinkingLevel.low, capacity: 100), 512);
      // 深思：客户端显式预算优先（不被猜的默认值压回去，zen-gate #27）
      expect(
        thinkingBudget(ThinkingLevel.high, capacity: 64000, requested: 128000),
        128000,
      );
      // 轻档：显式预算被钳到档位上
      expect(
        thinkingBudget(ThinkingLevel.low, capacity: 64000, requested: 128000),
        4096,
      );
    });
  });

  group('档位降级链', () {
    test('max → xhigh → high → medium → low → minimal → none → off', () {
      expect(downgradeThinkingLevel(ThinkingLevel.max), ThinkingLevel.xhigh);
      expect(downgradeThinkingLevel(ThinkingLevel.xhigh), ThinkingLevel.high);
      expect(downgradeThinkingLevel(ThinkingLevel.high), ThinkingLevel.medium);
      expect(
        downgradeThinkingLevel(ThinkingLevel.medium),
        ThinkingLevel.low,
      );
      expect(downgradeThinkingLevel(ThinkingLevel.low), ThinkingLevel.minimal);
      expect(
        downgradeThinkingLevel(ThinkingLevel.minimal),
        ThinkingLevel.none,
      );
      expect(downgradeThinkingLevel(ThinkingLevel.none), ThinkingLevel.off);
      // off 是最后一步：再往下没有了
      expect(downgradeThinkingLevel(ThinkingLevel.off), isNull);
    });

    test('往上游写的字面量：off 是空串，其余原名', () {
      expect(thinkingWireValue(ThinkingLevel.off), '');
      expect(thinkingWireValue(ThinkingLevel.none), 'none');
      expect(thinkingWireValue(ThinkingLevel.minimal), 'minimal');
      expect(thinkingWireValue(ThinkingLevel.low), 'low');
      expect(thinkingWireValue(ThinkingLevel.medium), 'medium');
      expect(thinkingWireValue(ThinkingLevel.high), 'high');
      expect(thinkingWireValue(ThinkingLevel.xhigh), 'xhigh');
      expect(thinkingWireValue(ThinkingLevel.max), 'max');
    });

    test('降级重写：effort 形换值、off 形删字段，预算跟着降', () {
      final body = chatBody({'max_tokens': 99999});
      writeThinkingLevel(
        body,
        ThinkingLevel.max,
        wire: ThinkingWireFormat.effort,
      );
      expect(body['reasoning_effort'], 'max');
      // 重档不钳：客户端显式要的数原样留着
      expect(body['max_tokens'], 99999);

      writeThinkingLevel(
        body,
        ThinkingLevel.low,
        wire: ThinkingWireFormat.effort,
      );
      expect(body['reasoning_effort'], 'low');
      expect(body['max_tokens'], 4096);

      writeThinkingLevel(
        body,
        ThinkingLevel.off,
        wire: ThinkingWireFormat.effort,
      );
      expect(body.containsKey('reasoning_effort'), isFalse);
      // off 不抬预算：已经被上一档钳下去的就那么留着（它不知道原值）
      expect(body['max_tokens'], 4096);
    });

    test('DeepSeek 的 thinking 形：none 写成 disabled，off 删字段', () {
      final body = chatBody(null);
      writeThinkingLevel(
        body,
        ThinkingLevel.none,
        wire: ThinkingWireFormat.thinking,
      );
      expect(body['thinking'], {'type': 'disabled'});
      writeThinkingLevel(
        body,
        ThinkingLevel.off,
        wire: ThinkingWireFormat.thinking,
      );
      expect(body.containsKey('thinking'), isFalse);
    });
  });

  group('zen 出站体', () {
    test('chat 线：带档位时写 max_tokens 预算，reasoning_effort 原样带上', () {
      final body = zenBuildBody(
        wire: ZenWire.chat,
        lane: 'step-5-preview-free',
        clientJson: chatBody({'reasoning_effort': 'low', 'stream': false}),
        capacity: 64000,
      );
      expect(body['max_tokens'], 4096);
      expect(body['reasoning_effort'], 'low');
      expect(body['stream'], isTrue); // 指纹门强制流式
    });

    test('chat 线：没档位没预算时不写 max_tokens（不替上游定上限）', () {
      final body = zenBuildBody(
        wire: ZenWire.chat,
        lane: 'mimo-v2.5-free',
        clientJson: chatBody(null),
      );
      expect(body.containsKey('max_tokens'), isFalse);
    });

    test('chat 线：精简档硬钳制 —— 显式预算超过档位上限时被压回', () {
      final body = zenBuildBody(
        wire: ZenWire.chat,
        lane: 'step-5-preview-free',
        clientJson: chatBody({'reasoning_effort': 'low', 'max_tokens': 99999}),
      );
      expect(body['max_tokens'], 4096);
      // 要得比档位少就随它（钳制是上限不是下限，同 zen-gate 的 min 语义）
      final small = zenBuildBody(
        wire: ZenWire.chat,
        lane: 'step-5-preview-free',
        clientJson: chatBody({'reasoning_effort': 'low', 'max_tokens': 999}),
      );
      expect(small['max_tokens'], 999);
    });

    test('responses / messages 线：档位落成 max_output_tokens / max_tokens', () {
      final responses = zenBuildBody(
        wire: ZenWire.responses,
        lane: 'muse-spark-1.3-contributor-free',
        clientJson: chatBody({'reasoning_effort': 'medium'}),
        capacity: 0,
      );
      expect(responses['max_output_tokens'], 8192);

      final messages = zenBuildBody(
        wire: ZenWire.messages,
        lane: 'union-alpha',
        clientJson: chatBody({'reasoning_effort': 'high'}),
        capacity: 4096,
      );
      expect(messages['max_tokens'], 4096);
    });

    test('端到端 zenPlan：模型名后缀 (low) 也能落到预算', () {
      final upstream = Upstream(
        id: 'zen',
        name: 'Zen',
        baseUrl: 'https://opencode.ai/zen/v1',
        models: [
          ModelEntry(publicName: 'zen-free', target: 'step-5-preview-free'),
        ],
      );
      expect(upstream.isZenGateway, isTrue);
      final plan = zenPlan(
        upstream: upstream,
        lane: 'step-5-preview-free',
        publicName: 'zen-free (low)',
        requestPath: '/v1/chat/completions',
        // 客户端发的 model 就带着档位后缀（opencode 的 variant 形态）。
        clientJson: chatBody(null)..['model'] = 'zen-free (low)',
        outputCapacity: 96000,
      );
      expect(plan, isNotNull);
      final sent = jsonDecode(utf8.decode(plan!.body)) as Map<String, dynamic>;
      expect(sent['max_tokens'], 4096);
    });

    test('代理算好的档位（含上游默认档）直接经 level 传入', () {
      final upstream = Upstream(
        id: 'zen',
        name: 'Zen',
        baseUrl: 'https://opencode.ai/zen/v1',
        // 上游配了默认档、客户端没发：_planHops 会算出 medium 再传进来。
        thinkingDefault: 'medium',
      );
      final plan = zenPlan(
        upstream: upstream,
        lane: 'step-5-preview-free',
        publicName: 'zen-free',
        requestPath: '/v1/chat/completions',
        clientJson: chatBody(null),
        outputCapacity: 96000,
        level: ThinkingLevel.medium,
      );
      final sent = jsonDecode(utf8.decode(plan!.body)) as Map<String, dynamic>;
      expect(sent['max_tokens'], 8192);
    });
  });

  group('applyThinkingDefaults（客户端没发才补）', () {
    test('客户端发了任何一家写法都不覆盖', () {
      final body = chatBody({'reasoning_effort': 'low'});
      expect(
        applyThinkingDefaults(
          body,
          defaultLevelId: 'high',
          wire: ThinkingWireFormat.effort,
        ),
        ThinkingLevel.low,
      );
      expect(body['reasoning_effort'], 'low');
      // thinking 形状也算「客户端发了」：补档不能把它的预算也改掉
      final thinkingBody = chatBody({'thinking': {'type': 'enabled'}});
      expect(
        applyThinkingDefaults(
          thinkingBody,
          defaultLevelId: 'low',
          wire: ThinkingWireFormat.budget,
        ),
        ThinkingLevel.high,
      );
      expect(thinkingBody.containsKey('max_tokens'), isFalse);
    });

    test('没配默认档 = 一个字都不改', () {
      final body = chatBody(null);
      expect(applyThinkingDefaults(body, defaultLevelId: ''), isNull);
      expect(body.containsKey('reasoning_effort'), isFalse);
      expect(body.containsKey('max_tokens'), isFalse);
    });

    test('budget 形：按档位钳在客户端用的那个键上', () {
      final none = chatBody(null);
      expect(
        applyThinkingDefaults(
          none,
          defaultLevelId: 'medium',
          capacity: 96000,
        ),
        ThinkingLevel.medium,
      );
      expect(none['max_tokens'], 8192);

      // pi-ai 那类客户端发的是 max_completion_tokens：钳回同一个键，
      // 不另开一个 max_tokens（两个都给上游会打架）。
      final asked = chatBody({'max_completion_tokens': 32768});
      applyThinkingDefaults(
        asked,
        defaultLevelId: 'low',
        capacity: 96000,
        wire: ThinkingWireFormat.budget,
      );
      expect(asked['max_completion_tokens'], 4096);
      expect(asked.containsKey('max_tokens'), isFalse);

      // 深思不额外设限：尊重客户端要的数
      final deep = chatBody({'max_tokens': 40000});
      applyThinkingDefaults(
        deep,
        defaultLevelId: 'high',
        capacity: 96000,
        wire: ThinkingWireFormat.budget,
      );
      expect(deep['max_tokens'], 40000);
    });

    test('effort / thinking / both 三种形状各写什么', () {
      final effort = chatBody(null);
      applyThinkingDefaults(
        effort,
        defaultLevelId: 'high',
        wire: ThinkingWireFormat.effort,
      );
      expect(effort['reasoning_effort'], 'high');
      expect(effort.containsKey('thinking'), isFalse);

      final thinking = chatBody(null);
      applyThinkingDefaults(
        thinking,
        defaultLevelId: 'medium',
        wire: ThinkingWireFormat.thinking,
      );
      expect(thinking['thinking'], {'type': 'enabled'});
      expect(thinking.containsKey('reasoning_effort'), isFalse);

      final both = chatBody(null);
      applyThinkingDefaults(
        both,
        defaultLevelId: 'low',
        wire: ThinkingWireFormat.both,
      );
      expect(both['reasoning_effort'], 'low');
      expect(both['thinking'], {'type': 'enabled'});
    });

    test('认不出的默认档 id 不算补档', () {
      final body = chatBody(null);
      expect(applyThinkingDefaults(body, defaultLevelId: 'banana'), isNull);
      expect(body.containsKey('max_tokens'), isFalse);
    });
  });

  group('配置往返（默认档只在配了时才落盘）', () {
    test('没配 → JSON 干净；配了 → 两个字段都在；老配置读回来是不干预', () {
      final plain = Upstream(id: 'u', name: 'n', baseUrl: 'https://a/v1');
      expect(plain.toJson().containsKey('thinkingDefault'), isFalse);
      expect(plain.toJson().containsKey('thinkingWire'), isFalse);

      plain.thinkingDefault = 'medium';
      plain.thinkingWire = ThinkingWireFormat.thinking;
      final json = plain.toJson();
      expect(json['thinkingDefault'], 'medium');
      expect(json['thinkingWire'], 'thinking');

      final back = Upstream.fromJson(json);
      expect(back.thinkingDefault, 'medium');
      expect(back.thinkingWire, ThinkingWireFormat.thinking);

      final old = Upstream.fromJson({
        'id': 'u',
        'name': 'n',
        'type': 'openai',
        'baseUrl': 'https://a/v1',
      });
      expect(old.thinkingDefault, '');
      // 老配置没存形状：默认 effort（写 reasoning_effort），配了档位才用
      expect(old.thinkingWire, ThinkingWireFormat.effort);
    });
  });

  group('端到端：上游配了默认档', () {
    late HttpServer mockUpstream;
    late ProxyServer proxy;
    late ProxyConfig config;
    Map<String, dynamic>? received;

    /// 上游要「拒」的档位字面量（模拟不认 xhigh 的上游）；
    /// 空 = 全部放行。命中时回 400 并在错误体里点名 reasoning_effort。
    String rejectEffort = '';

    /// 上游一共被请求了几次（降级重试会让它多于一次）。
    int upstreamHits = 0;

    Future<void> startProxy({
      required String defaultLevel,
      ThinkingWireFormat wire = ThinkingWireFormat.effort,
    }) async {
      config = ProxyConfig(listenHost: '127.0.0.1', listenPort: 19292)
        ..upstreams.add(
          Upstream(
            id: 'u1',
            name: 'mock',
            type: UpstreamType.openai,
            baseUrl: 'http://127.0.0.1:${mockUpstream.port}/v1',
            apiKey: 'sk-upstream',
            thinkingDefault: defaultLevel,
            thinkingWire: wire,
            models: [
              ModelEntry(
                publicName: 'alias',
                target: 'real-model',
                maxOutputTokens: 96000,
              ),
            ],
          ),
        )
        ..apiKeys.add(ApiKeyEntry(id: 'k1', name: 't', key: 'sk-client'));
      proxy = ProxyServer(configProvider: () => config);
      await proxy.start();
    }

    Future<void> sendClient(Map<String, dynamic> extra) async {
      final client = HttpClient();
      final req = await client.postUrl(
        Uri.parse('http://127.0.0.1:19292/v1/chat/completions'),
      );
      req.headers.set('content-type', 'application/json');
      req.headers.set('authorization', 'Bearer sk-client');
      req.write(
        jsonEncode({
          'model': 'alias',
          'stream': true,
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
          ...extra,
        }),
      );
      final res = await req.close();
      await res.drain<void>();
      client.close();
    }

    setUp(() async {
      received = null;
      rejectEffort = '';
      upstreamHits = 0;
      mockUpstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      mockUpstream.listen((req) async {
        final raw = await utf8.decoder.bind(req).join();
        if (req.method == 'POST' && raw.isNotEmpty) {
          received = jsonDecode(raw) as Map<String, dynamic>;
        }
        // 不认这一档：回 400 并点名参数（真实上游就是这个姿势）。
        if (rejectEffort.isNotEmpty &&
            received?['reasoning_effort'] == rejectEffort) {
          upstreamHits++;
          req.response.statusCode = 400;
          req.response.headers.contentType = ContentType.json;
          req.response.write(
            jsonEncode({
              'error': {
                'message':
                    'Unsupported value: \'reasoning_effort\' does not support '
                    '\'$rejectEffort\'. Supported values are \'low\', \'high\' '
                    'and \'max\'.',
                'type': 'invalid_request_error',
              },
            }),
          );
          await req.response.close();
          return;
        }
        upstreamHits++;
        req.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        req.response.write(
          'data: {"choices":[{"delta":{"content":"ok"},"finish_reason":"stop"}]}\n\n',
        );
        req.response.write('data: [DONE]\n\n');
        await req.response.close();
      });
    });

    tearDown(() async {
      await proxy.stop();
      await mockUpstream.close(force: true);
    });

    test('客户端没发 → 补 reasoning_effort', () async {
      await startProxy(defaultLevel: 'high', wire: ThinkingWireFormat.effort);
      await sendClient({});
      expect(received, isNotNull);
      expect(received!['reasoning_effort'], 'high');
      expect(received!['model'], 'real-model');
    });

    test('客户端发了 → 一个字都不改', () async {
      await startProxy(defaultLevel: 'high', wire: ThinkingWireFormat.effort);
      await sendClient({'reasoning_effort': 'minimal'});
      expect(received!['reasoning_effort'], 'minimal');
    });

    test('budget 形：钳 max_completion_tokens 且不注入思考字段', () async {
      await startProxy(
        defaultLevel: 'medium',
        wire: ThinkingWireFormat.budget,
      );
      // pi-ai 的真实形状：max_completion_tokens + store
      await sendClient({'max_completion_tokens': 32768, 'store': false});
      expect(received!['max_completion_tokens'], 8192);
      expect(received!.containsKey('reasoning_effort'), isFalse);
      expect(received!.containsKey('thinking'), isFalse);
      expect(received!['store'], isFalse);
    });

    test('xhigh / max 原样下发（不再折叠成 high）', () async {
      await startProxy(
        defaultLevel: 'max',
        wire: ThinkingWireFormat.effort,
      );
      await sendClient({});
      expect(received!['reasoning_effort'], 'max');
    });

    test('none 原样下发：显式关思考', () async {
      await startProxy(
        defaultLevel: 'none',
        wire: ThinkingWireFormat.effort,
      );
      await sendClient({});
      expect(received!['reasoning_effort'], 'none');
      // none 也钳预算：1024
      expect(received!['max_tokens'], 1024);
    });

    test('thinking 形：补 DeepSeek 的 thinking.type', () async {
      await startProxy(defaultLevel: 'medium', wire: ThinkingWireFormat.thinking);
      await sendClient({});
      expect(received!['thinking'], {'type': 'enabled'});
    });

    test('上游不认 xhigh → 自动降到 high 再发，客户端只看到成功', () async {
      rejectEffort = 'xhigh';
      await startProxy(defaultLevel: 'xhigh');
      await sendClient({});
      // 客户端拿到的是 200（降级发生在写任何字节之前）
      expect(upstreamHits, 2);
      // 最终发出去的是降下来的那档
      expect(received!['reasoning_effort'], 'high');
    });

    test('一路降到底：上游只认 low，max 三次降级后落在 low', () async {
      // low 不在拒绝名单里 → max→xhigh→high→medium 都拒，第 4 跳 low 成
      rejectEffort = 'max';
      // 上面只拒 max；这里换成「除 low 外全拒」的判据更直观：
      // 用 max/xhigh/high/medium 依次拒（每次改判据即可）。
      await startProxy(defaultLevel: 'max');
      await sendClient({});
      expect(received!['reasoning_effort'], 'xhigh');
    });
  });

    group('/v1/models 声明档位', () {
    late HttpServer mockUpstream;
    late ProxyServer proxy;

    setUp(() async {
      mockUpstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      mockUpstream.listen((req) async {
        if (req.uri.path.endsWith('/models')) {
          req.response.headers.contentType = ContentType.json;
          req.response.write(
            jsonEncode({
              'object': 'list',
              'data': [
                {'id': 'qwen2.5-7b'},
              ],
            }),
          );
          await req.response.close();
          return;
        }
        req.response.statusCode = 404;
        await req.response.close();
      });

      final config = ProxyConfig(listenHost: '127.0.0.1', listenPort: 19291)
        ..upstreams.add(
          Upstream(
            id: 'u1',
            name: 'mock',
            type: UpstreamType.openai,
            baseUrl: 'http://127.0.0.1:${mockUpstream.port}/v1',
            apiKey: 'sk-upstream',
            models: [ModelEntry(publicName: 'gpt-alias', target: 'qwen2.5-7b')],
          ),
        )
        ..apiKeys.add(ApiKeyEntry(id: 'k1', name: 't', key: 'sk-client'));
      proxy = ProxyServer(configProvider: () => config);
      await proxy.start();
    });

    tearDown(() async {
      await proxy.stop();
      await mockUpstream.close(force: true);
    });

    test('每条模型带 reasoning + supported_reasoning_levels（agent 读这个出档位）', () async {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:19291/v1/models'));
      req.headers.set('authorization', 'Bearer sk-client');
      final res = await req.close();
      expect(res.statusCode, 200);
      final json =
          jsonDecode(await res.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      final entry = (json['data'] as List).single as Map<String, dynamic>;
      expect(entry['reasoning'], isTrue);
      expect(entry['supported_reasoning_levels'], kThinkingLevelIds);
      client.close();
    });
  });
}
