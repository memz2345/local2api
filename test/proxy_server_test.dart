import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/network_utils.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:local2api/services/tts/tts_settings.dart';

void main() {
  // 注意：不要调用 TestWidgetsFlutterBinding.ensureInitialized()，
  // 它会把测试里所有 HttpClient 请求劫持成 400。
  group('NetworkUtils CIDR', () {
    test('IPv4 前缀匹配', () {
      expect(
        NetworkUtils.cidrMatches(
          '192.168.0.0/16',
          InternetAddress('192.168.1.10'),
        ),
        isTrue,
      );
      expect(
        NetworkUtils.cidrMatches(
          '192.168.0.0/16',
          InternetAddress('192.169.1.10'),
        ),
        isFalse,
      );
      expect(
        NetworkUtils.cidrMatches('10.0.0.0/8', InternetAddress('10.255.0.1')),
        isTrue,
      );
      expect(
        NetworkUtils.cidrMatches('0.0.0.0/0', InternetAddress('8.8.8.8')),
        isTrue,
      );
      expect(
        NetworkUtils.cidrMatches('127.0.0.0/8', InternetAddress('127.0.0.1')),
        isTrue,
      );
    });

    test('单地址无前缀', () {
      expect(
        NetworkUtils.cidrMatches('192.168.1.5', InternetAddress('192.168.1.5')),
        isTrue,
      );
      expect(
        NetworkUtils.cidrMatches('192.168.1.5', InternetAddress('192.168.1.6')),
        isFalse,
      );
    });

    test('IPv6 前缀匹配', () {
      expect(
        NetworkUtils.cidrMatches('fc00::/7', InternetAddress('fc00::1')),
        isTrue,
      );
      expect(
        NetworkUtils.cidrMatches('fc00::/7', InternetAddress('fe80::1')),
        isFalse,
      );
      expect(
        NetworkUtils.cidrMatches('::/0', InternetAddress('2001:db8::1')),
        isTrue,
      );
    });

    test('IPv4-mapped IPv6 客户端按 IPv4 匹配', () {
      final mapped = InternetAddress('::ffff:192.168.1.10');
      expect(NetworkUtils.cidrMatches('192.168.0.0/16', mapped), isTrue);
      expect(NetworkUtils.cidrMatches('10.0.0.0/8', mapped), isFalse);
    });

    test('非法 CIDR', () {
      expect(NetworkUtils.parseCidr('abc'), isNull);
      expect(NetworkUtils.parseCidr('1.2.3.4/40'), isNull);
      expect(NetworkUtils.parseCidr(''), isNull);
    });
  });

  group('buildUpstreamUri /v1 归一化', () {
    test('baseUrl 以 /v1 结尾时拼接去掉 /v1 的请求路径（OpenAI SDK 约定）', () {
      final u = Upstream(id: '1', name: 'a', baseUrl: 'http://h:8080/v1');
      final uri = ProxyServer.buildUpstreamUri(u, '/v1/chat/completions', '');
      expect(uri.toString(), 'http://h:8080/v1/chat/completions');
    });

    test('baseUrl 不带 /v1 时保留完整路径', () {
      final u = Upstream(id: '1', name: 'a', baseUrl: 'http://h:8080');
      final uri = ProxyServer.buildUpstreamUri(u, '/v1/chat/completions', '');
      expect(uri.toString(), 'http://h:8080/v1/chat/completions');
    });

    test('保留查询参数', () {
      final u = Upstream(id: '1', name: 'a', baseUrl: 'http://h:8080/v1/');
      final uri = ProxyServer.buildUpstreamUri(u, '/v1/models', 'a=1&b=2');
      expect(uri.toString(), 'http://h:8080/v1/models?a=1&b=2');
    });
  });

  group('ProxyConfig 序列化', () {
    test('round-trip 保留全部字段', () {
      final config =
          ProxyConfig(
              listenPort: 1234,
              listenHost: '127.0.0.1',
              corsEnabled: false,
              autoStart: true,
            )
            ..upstreams.add(
              Upstream(
                id: 'u1',
                name: '本地 llama',
                type: UpstreamType.llamacpp,
                baseUrl: 'http://127.0.0.1:8080/v1',
                apiKey: 'sk-up',
                models: [ModelEntry(publicName: 'gpt-x', target: 'qwen2.5')],
              ),
            )
            ..apiKeys.add(ApiKeyEntry(id: 'k1', name: '手机', key: 'sk-abc'))
            ..cidrRules.add(
              CidrRule(id: 'r1', cidr: '192.168.0.0/16', allow: false),
            );

      final restored = ProxyConfig.fromJson(
        (jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>),
      );
      expect(restored.listenPort, 1234);
      expect(restored.listenHost, '127.0.0.1');
      expect(restored.corsEnabled, isFalse);
      expect(restored.autoStart, isTrue);
      expect(restored.upstreams.first.type, UpstreamType.llamacpp);
      expect(restored.upstreams.first.models.first.target, 'qwen2.5');
      expect(restored.apiKeys.first.key, 'sk-abc');
      expect(restored.cidrRules.first.allow, isFalse);
    });
  });

  group('ProxyServer 集成', () {
    late HttpServer mockUpstream;
    late ProxyServer proxy;
    late ProxyConfig config;

    String? upstreamAuth;
    String? receivedModel;

    setUp(() async {
      receivedModel = null;
      // 模拟上游：OpenAI 兼容
      mockUpstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      mockUpstream.listen((req) async {
        upstreamAuth = req.headers.value('authorization');
        if (req.uri.path == '/v1/models') {
          req.response.headers.contentType = ContentType.json;
          req.response.write(
            jsonEncode({
              'object': 'list',
              'data': [
                {
                  'id': 'qwen2.5-7b',
                  'object': 'model',
                  'context_length': 131072,
                },
                {
                  'id': 'llama3',
                  'object': 'model',
                  'max_model_len': 4096,
                  'max_completion_tokens': 8192,
                },
              ],
            }),
          );
          await req.response.close();
          return;
        }
        if (req.uri.path == '/chat/completions' ||
            req.uri.path == '/v1/chat/completions') {
          final body =
              jsonDecode(await utf8.decoder.bind(req).join())
                  as Map<String, dynamic>;
          receivedModel = body['model'] as String?;
          final stream = body['stream'] == true;
          if (stream) {
            req.response.headers.contentType = ContentType(
              'text',
              'event-stream',
            );
            req.response.bufferOutput = false;
            for (var i = 0; i < 3; i++) {
              req.response.write(
                'data: {"choices":[{"delta":{"content":"chunk$i"}}]}\n\n',
              );
              await req.response.flush();
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
            req.response.write('data: [DONE]\n\n');
            await req.response.close();
          } else {
            req.response.headers.contentType = ContentType.json;
            req.response.write(
              jsonEncode({
                'id': 'cmpl-1',
                'object': 'chat.completion',
                'model': receivedModel,
                'choices': [
                  {
                    'index': 0,
                    'message': {'role': 'assistant', 'content': 'hi'},
                  },
                ],
              }),
            );
            await req.response.close();
          }
          return;
        }
        req.response.statusCode = 404;
        await req.response.close();
      });

      config = ProxyConfig(listenHost: '127.0.0.1', listenPort: 19283)
        ..upstreams.add(
          Upstream(
            id: 'u1',
            name: 'mock',
            type: UpstreamType.openai,
            baseUrl: 'http://127.0.0.1:${mockUpstream.port}/v1',
            apiKey: 'sk-upstream',
            models: [
              ModelEntry(publicName: 'gpt-alias', target: 'qwen2.5-7b'),
              ModelEntry(publicName: 'direct-model', enabled: false),
            ],
          ),
        )
        ..apiKeys.add(ApiKeyEntry(id: 'k1', name: 'test', key: 'sk-client'));

      proxy = ProxyServer(configProvider: () => config);
      await proxy.start();
    });

    tearDown(() async {
      await proxy.stop();
      await mockUpstream.close(force: true);
    });

    Future<(int, String)> request(
      String path, {
      String? auth,
      Map<String, dynamic>? body,
      String? method,
    }) async {
      final client = HttpClient();
      final req = await client.openUrl(
        method ?? (body != null ? 'POST' : 'GET'),
        Uri.parse('http://127.0.0.1:19283$path'),
      );
      if (auth != null) {
        req.headers.set('authorization', 'Bearer $auth');
      }
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      client.close();
      return (res.statusCode, text);
    }

    test('/health 免鉴权', () async {
      final (status, body) = await request('/health');
      expect(status, 200);
      expect(body, contains('ok'));
    });

    test('无密钥返回 401', () async {
      final (status, _) = await request('/v1/models');
      expect(status, 401);
    });

    test('错误密钥返回 401', () async {
      final (status, _) = await request('/v1/models', auth: 'sk-wrong');
      expect(status, 401);
    });

    test('模型列表只含暴露且启用的模型（别名）', () async {
      final (status, body) = await request('/v1/models', auth: 'sk-client');
      expect(status, 200);
      final json = jsonDecode(body) as Map<String, dynamic>;
      final ids = (json['data'] as List)
          .map((e) => (e as Map<String, dynamic>)['id'])
          .toList();
      expect(ids, ['gpt-alias']);
    });

    test('模型列表带上下文长度：配了用配置值，没配回退 1M', () async {
      final list = config.upstreams.first.models;
      list[0].contextLength = 200000;
      list[0].maxOutputTokens = 32000;
      list[1].enabled = true;
      addTearDown(() {
        list[0].contextLength = 0;
        list[0].maxOutputTokens = 0;
        list[1].enabled = false;
      });
      final (status, body) = await request('/v1/models', auth: 'sk-client');
      expect(status, 200);
      final data = (jsonDecode(body) as Map<String, dynamic>)['data'] as List;
      final byId = {
        for (final m in data)
          (m as Map<String, dynamic>)['id'] as String: m,
      };
      expect(byId['gpt-alias']!['context_length'], 200000);
      expect(byId['gpt-alias']!['max_output_tokens'], 32000);
      // 没配输出上限的模型不带这个字段（不替它编数字）
      expect(byId['direct-model']!.containsKey('max_output_tokens'), isFalse);
      expect(byId['direct-model']!['context_length'], 1000000);
    });

    test('拉清单顺带收上游声明的上下文长度', () async {
      final catalog = await ProxyServer.fetchModelCatalog(
        config.upstreams.first,
      );
      expect(catalog.ids, containsAll(['qwen2.5-7b', 'llama3']));
      expect(catalog.contexts['qwen2.5-7b'], 131072);
      // vLLM 风格字段也认
      expect(catalog.contexts['llama3'], 4096);
      // 输出上限（OpenAI 的 max_completion_tokens）也收
      expect(catalog.outputs['llama3'], 8192);
    });

    test('别名模型转发并改写为上游真实名称', () async {
      final (status, body) = await request(
        '/v1/chat/completions',
        auth: 'sk-client',
        body: {'model': 'gpt-alias', 'messages': []},
      );
      expect(status, 200);
      expect(receivedModel, 'qwen2.5-7b');
      expect(upstreamAuth, 'Bearer sk-upstream');
      expect(body, contains('"content":"hi"'));
    });

    test('未暴露的模型返回 404', () async {
      final (status, body) = await request(
        '/v1/chat/completions',
        auth: 'sk-client',
        body: {'model': 'unknown', 'messages': []},
      );
      expect(status, 404);
      expect(body, contains('not exposed'));
    });

    test('流式响应逐块透传', () async {
      final client = HttpClient();
      final req = await client.postUrl(
        Uri.parse('http://127.0.0.1:19283/v1/chat/completions'),
      );
      req.headers.set('authorization', 'Bearer sk-client');
      req.headers.contentType = ContentType.json;
      req.write(
        jsonEncode({'model': 'gpt-alias', 'stream': true, 'messages': []}),
      );
      final res = await req.close();
      expect(res.statusCode, 200);
      expect(res.headers.contentType.toString(), contains('event-stream'));

      final chunks = <String>[];
      await for (final chunk in res.transform(utf8.decoder)) {
        chunks.add(chunk);
      }
      client.close();
      final all = chunks.join();
      expect(all, contains('chunk0'));
      expect(all, contains('chunk2'));
      expect(all, contains('[DONE]'));
    });

    test('IP 规则：拒绝规则命中返回 403', () async {
      config.cidrRules.add(
        CidrRule(id: 'r1', cidr: '127.0.0.0/8', allow: false),
      );
      final (status, body) = await request('/v1/models', auth: 'sk-client');
      expect(status, 403);
      expect(body, contains('denied'));
      config.cidrRules.clear();
    });

    test('IP 规则：先命中先生效（先 allow 后 deny 全网段）', () async {
      config.cidrRules
        ..add(CidrRule(id: 'r1', cidr: '127.0.0.1/32', allow: true))
        ..add(CidrRule(id: 'r2', cidr: '0.0.0.0/0', allow: false));
      final (status, _) = await request('/v1/models', auth: 'sk-client');
      expect(status, 200);
      config.cidrRules.clear();
    });

    test('密钥列表为空时不鉴权', () async {
      config.apiKeys.clear();
      final (status, _) = await request('/v1/models');
      expect(status, 200);
    });
  });

  group('免费车道有序回退', () {
    late HttpServer upstream;
    late ProxyServer proxy;
    late ProxyConfig config;
    final asked = <String>[];
    final blocked = <String>{};

    setUp(() async {
      asked.clear();
      blocked.clear();
      upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((req) async {
        if (req.uri.path != '/v1/chat/completions') {
          req.response.statusCode = 404;
          await req.response.close();
          return;
        }
        final body =
            jsonDecode(await utf8.decoder.bind(req).join())
                as Map<String, dynamic>;
        final model = body['model'] as String;
        asked.add(model);
        req.response.headers.contentType = ContentType.json;
        if (blocked.contains(model)) {
          req.response.statusCode = 403;
          req.response.write('{"error":{"message":"lane refused"}}');
          await req.response.close();
          return;
        }
        req.response.write(
          jsonEncode({
            'id': 'cmpl-1',
            'model': model,
            'choices': [
              {
                'index': 0,
                'message': {'role': 'assistant', 'content': 'from-$model'},
              },
            ],
          }),
        );
        await req.response.close();
      });

      config = ProxyConfig(listenHost: '127.0.0.1', listenPort: 19284)
        ..upstreams.add(
          Upstream(
            id: 'u1',
            name: 'zen',
            type: UpstreamType.openai,
            baseUrl: 'http://127.0.0.1:${upstream.port}/v1',
            models: [
              ModelEntry(
                publicName: 'free',
                target: 'lane-a',
                fallbacks: ['lane-b', 'lane-c'],
              ),
              ModelEntry(publicName: 'single', target: 'lane-s'),
              // 对外名就是车道本名（不重命名）：这种不该补车道头
              ModelEntry(publicName: 'lane-s', target: 'lane-s'),
            ],
          ),
        )
        ..apiKeys.add(ApiKeyEntry(id: 'k1', name: 't', key: 'sk-c'));

      proxy = ProxyServer(configProvider: () => config);
      await proxy.start();
    });

    tearDown(() async {
      await proxy.stop();
      await upstream.close(force: true);
    });

    Future<(int, String)> chat(String model) async {
      final client = HttpClient();
      final req = await client.openUrl(
        'POST',
        Uri.parse('http://127.0.0.1:19284/v1/chat/completions'),
      );
      req.headers.set('authorization', 'Bearer sk-c');
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'model': model, 'messages': []}));
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      client.close();
      return (res.statusCode, text);
    }

    test('首条车道被拒时自动换下一条，客户端只看到成功', () async {
      blocked.addAll({'lane-a', 'lane-b'});
      final (status, text) = await chat('free');
      expect(status, 200);
      expect(text, contains('from-lane-c'));
      expect(asked, ['lane-a', 'lane-b', 'lane-c']);
    });

    test('响应头带出真正接住请求的车道（对外名 ≠ 车道时）', () async {
      blocked.addAll({'lane-a', 'lane-b'});
      final client = HttpClient();
      final req = await client.openUrl(
        'POST',
        Uri.parse('http://127.0.0.1:19284/v1/chat/completions'),
      );
      req.headers.set('authorization', 'Bearer sk-c');
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'model': 'free', 'messages': []}));
      final res = await req.close();
      final lane = res.headers.value(kServedLaneHeader);
      await res.drain<void>();
      client.close();

      expect(lane, 'lane-c', reason: '回退到第三条，头里得说第三条');
    });

    test('对外名就是车道名时不补车道头（响应体已经说清楚了）', () async {
      final client = HttpClient();
      final req = await client.openUrl(
        'POST',
        Uri.parse('http://127.0.0.1:19284/v1/chat/completions'),
      );
      req.headers.set('authorization', 'Bearer sk-c');
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'model': 'lane-s', 'messages': []}));
      final res = await req.close();
      final lane = res.headers.value(kServedLaneHeader);
      await res.drain<void>();
      client.close();

      expect(lane, isNull);
    });

    test('全部车道被拒时把最后一次的真实状态与响应体回传', () async {
      blocked.addAll({'lane-a', 'lane-b', 'lane-c'});
      final (status, text) = await chat('free');
      expect(status, 403);
      expect(text, contains('lane refused'));
      expect(asked.length, 3);
    });

    test('未配回退的模型只打一次上游', () async {
      blocked.add('lane-s');
      final (status, _) = await chat('single');
      expect(status, 403);
      expect(asked, ['lane-s']);
    });

    test('attempts 以 target 打头并去重去空', () {
      final m = ModelEntry(
        publicName: 'p',
        target: ' a ',
        fallbacks: ['a', '', 'b', 'a'],
      );
      expect(m.attempts, ['a', 'b']);
    });

    test('回退链随配置一起持久化', () {
      final m = ModelEntry(publicName: 'free', target: 'a', fallbacks: ['b']);
      final restored = ModelEntry.fromJson(
        jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>,
      );
      expect(restored.fallbacks, ['b']);
      expect(restored.attempts, ['a', 'b']);
    });
  });

  group('/v1/audio/speech 转发', () {
    late HttpServer mockUpstream;
    late ProxyServer proxy;
    late ProxyConfig config;

    // 模拟上游收到的那份请求体（翻译产物）
    Map<String, dynamic>? upstreamBody;
    String? upstreamPath;

    setUp(() async {
      upstreamBody = null;
      upstreamPath = null;
      mockUpstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      mockUpstream.listen((req) async {
        upstreamPath = req.uri.path;
        if (req.uri.path == '/chat/completions' ||
            req.uri.path == '/v1/chat/completions') {
          upstreamBody =
              jsonDecode(await utf8.decoder.bind(req).join())
                  as Map<String, dynamic>;
          // MiMo 风格回包：base64 音频挂在 message.audio.data
          req.response.headers.contentType = ContentType.json;
          req.response.write(
            jsonEncode({
              'id': 'tts-1',
              'choices': [
                {
                  'index': 0,
                  'finish_reason': 'stop',
                  'message': {
                    'role': 'assistant',
                    'content': '',
                    'audio': {
                      'id': 'a1',
                      // "FAKEWAVDATA" 的 base64
                      'data': base64Encode(utf8.encode('FAKEWAVDATA')),
                    },
                  },
                },
              ],
            }),
          );
          await req.response.close();
          return;
        }
        req.response.statusCode = 404;
        await req.response.close();
      });

      config = ProxyConfig(listenHost: '127.0.0.1', listenPort: 19285)
        ..upstreams.add(
          Upstream(
            id: 'u1',
            name: 'mimo',
            type: UpstreamType.openai,
            modality: UpstreamModality.audio,
            baseUrl: 'http://127.0.0.1:${mockUpstream.port}/v1',
            apiKey: 'sk-upstream',
            models: [ModelEntry(publicName: 'my-tts', target: 'mimo-v2.5-tts')],
          ),
        )
        ..apiKeys.add(ApiKeyEntry(id: 'k1', name: 'test', key: 'sk-client'));

      proxy = ProxyServer(configProvider: () => config);
      await proxy.start();
    });

    tearDown(() async {
      await proxy.stop();
      await mockUpstream.close(force: true);
    });

    Future<(int, String)> postJson(
      String path,
      Map<String, dynamic> body,
    ) async {
      final client = HttpClient();
      final req = await client.postUrl(
        Uri.parse('http://127.0.0.1:19285$path'),
      );
      req.headers.set('authorization', 'Bearer sk-client');
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      client.close();
      return (res.statusCode, text);
    }

    test('OpenAI TTS 请求被翻译成 chat.completions，回包解成原始音频字节', () async {
      final client = HttpClient();
      final req = await client.postUrl(
        Uri.parse('http://127.0.0.1:19285/v1/audio/speech'),
      );
      req.headers.set('authorization', 'Bearer sk-client');
      req.headers.contentType = ContentType.json;
      req.write(
        jsonEncode({
          'model': 'my-tts',
          'input': '你好世界',
          'voice': 'Chloe',
          'response_format': 'wav',
        }),
      );
      final res = await req.close();
      final bytes = <int>[];
      await for (final chunk in res) {
        bytes.addAll(chunk);
      }
      client.close();

      expect(res.statusCode, 200);
      expect(utf8.decode(bytes), 'FAKEWAVDATA');
      expect(res.headers.contentType?.mimeType, 'audio/wav');

      // 上游收到的是翻译后的 chat.completions 请求
      // （baseUrl 以 /v1 结尾 → 完整路径 /v1/chat/completions）
      expect(upstreamPath, '/v1/chat/completions');
      expect(upstreamBody, isNotNull);
      expect(upstreamBody!['model'], 'mimo-v2.5-tts');
      expect(upstreamBody!['stream'], false);
      final messages = upstreamBody!['messages'] as List;
      expect(messages, hasLength(1));
      expect((messages.first as Map)['role'], 'assistant');
      expect((messages.first as Map)['content'], '你好世界');
      expect((upstreamBody!['audio'] as Map)['format'], 'wav');
      expect((upstreamBody!['audio'] as Map)['voice'], 'Chloe');
    });

    test('instructions 翻译成 user 消息，pcm 格式映射为 pcm16', () async {
      final client = HttpClient();
      final req = await client.postUrl(
        Uri.parse('http://127.0.0.1:19285/v1/audio/speech'),
      );
      req.headers.set('authorization', 'Bearer sk-client');
      req.headers.contentType = ContentType.json;
      req.write(
        jsonEncode({
          'model': 'my-tts',
          'input': '嗨',
          'instructions': '开心一点',
          'response_format': 'pcm',
        }),
      );
      final res = await req.close();
      await res.drain<void>();
      client.close();

      expect(res.statusCode, 200);
      final messages = upstreamBody!['messages'] as List;
      expect(messages, hasLength(2));
      expect((messages.first as Map)['role'], 'user');
      expect((messages.first as Map)['content'], '开心一点');
      expect((upstreamBody!['audio'] as Map)['format'], 'pcm16');
    });

    test('缺 input 返回 400', () async {
      final (status, body) = await postJson(
        '/v1/audio/speech',
        {'model': 'my-tts'},
      );
      expect(status, 400);
      expect(body, contains('input'));
    });

    test('voice_sample（data URI）顶掉 voice 字段：音色克隆样本随请求带上去', () async {
      final (status, _) = await postJson('/v1/audio/speech', {
        'model': 'my-tts',
        'input': '克隆音色测试',
        'voice': 'Chloe',
        'voice_sample': 'data:audio/wav;base64,UklGRg==',
      });
      expect(status, 200);
      expect((upstreamBody!['audio'] as Map)['voice'], 'data:audio/wav;base64,UklGRg==');
    });

    test('voicedesign 缺 instructions 时兜底默认音色描述（user 消息不能空）', () async {
      config.upstreams.first.models
        ..clear()
        ..add(
          ModelEntry(
            publicName: 'vd',
            target: 'mimo-v2.5-tts-voicedesign',
          ),
        );
      final (status, _) = await postJson('/v1/audio/speech', {
        'model': 'vd',
        'input': '设计音色测试',
      });
      expect(status, 200);
      final messages = upstreamBody!['messages'] as List;
      expect(messages, hasLength(2));
      expect((messages.first as Map)['role'], 'user');
      // user 消息就是音色描述：没给就用默认文案顶上，绝不空（空 = 上游 400）。
      expect(
        (messages.first as Map)['content'],
        TtsSettings.defaultDesignPrompt,
      );
      // voicedesign 不认预置音色 / 样本，audio.voice 剥掉。
      expect((upstreamBody!['audio'] as Map).containsKey('voice'), isFalse);
    });

    test('voicedesign 带 instructions 时用指令顶替默认音色描述', () async {
      config.upstreams.first.models
        ..clear()
        ..add(
          ModelEntry(
            publicName: 'vd',
            target: 'mimo-v2.5-tts-voicedesign',
          ),
        );
      final (status, _) = await postJson('/v1/audio/speech', {
        'model': 'vd',
        'input': '设计音色测试',
        'instructions': '低沉沙哑的中年男声',
      });
      expect(status, 200);
      final messages = upstreamBody!['messages'] as List;
      expect((messages.first as Map)['content'], '低沉沙哑的中年男声');
    });

    test('voiceclone 无 instructions 时也带一条空 user 消息（官方示例形态）', () async {
      config.upstreams.first.models
        ..clear()
        ..add(
          ModelEntry(
            publicName: 'vc',
            target: 'mimo-v2.5-tts-voiceclone',
          ),
        );
      final (status, _) = await postJson('/v1/audio/speech', {
        'model': 'vc',
        'input': '克隆音色测试',
        'voice_sample': 'data:audio/mpeg;base64,AAAA',
      });
      expect(status, 200);
      final messages = upstreamBody!['messages'] as List;
      // user 消息要存在（可为空串），assistant 是要合成的文本。
      expect((messages.first as Map), {'role': 'user', 'content': ''});
      expect((messages.last as Map)['role'], 'assistant');
      expect((messages.last as Map)['content'], '克隆音色测试');
      expect((upstreamBody!['audio'] as Map)['voice'], 'data:audio/mpeg;base64,AAAA');
    });

    test('旧配置 JSON 没有 modality 字段时按 chat 处理', () {
      final restored = Upstream.fromJson({
        'id': 'u9',
        'name': 'legacy',
        'type': 'openai',
        'baseUrl': 'http://x/v1',
        'apiKey': '',
        'enabled': true,
        'models': [],
      });
      expect(restored.modality, UpstreamModality.chat);
      // 序列化回 JSON 也不带 modality 键（文件保持干净）
      expect(restored.toJson().containsKey('modality'), isFalse);
    });

    test('audio 模态随配置持久化', () {
      final restored = Upstream.fromJson({
        'id': 'u9',
        'name': 'mimo',
        'type': 'openai',
        'modality': 'audio',
        'baseUrl': 'http://x/v1',
        'apiKey': '',
        'enabled': true,
        'models': [],
      });
      expect(restored.modality, UpstreamModality.audio);
    });

    test('localTts 类型上游拒绝聊天请求', () async {
      config.upstreams
        ..clear()
        ..add(
          Upstream(
            id: 'local',
            name: 'local-tts',
            type: UpstreamType.localTts,
            baseUrl: '',
            models: [ModelEntry(publicName: 'qwen3-tts')],
          ),
        );
      final (status, body) = await postJson('/v1/chat/completions', {
        'model': 'qwen3-tts',
        'messages': [],
      });
      expect(status, 400);
      expect(body, contains('/v1/audio/speech'));
    });

    test('localTts 类型上游缺 input 返回 400（不触碰本地引擎）', () async {
      config.upstreams
        ..clear()
        ..add(
          Upstream(
            id: 'local',
            name: 'local-tts',
            type: UpstreamType.localTts,
            baseUrl: '',
            models: [ModelEntry(publicName: 'qwen3-tts')],
          ),
        );
      final (status, body) = await postJson('/v1/audio/speech', {
        'model': 'qwen3-tts',
      });
      expect(status, 400);
      expect(body, contains('input'));
    });
  });
}
