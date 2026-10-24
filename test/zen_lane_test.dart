import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:local2api/services/zen/zen_convert.dart';
import 'package:local2api/services/zen/zen_ids.dart';
import 'package:local2api/services/zen/zen_protocol.dart';

/// 上游收到的一次请求。
class _Seen {
  _Seen(this.path, this.headers, this.body);

  final String path;
  final Map<String, String> headers;
  final Map<String, dynamic> body;

  List<String> get toolNames => [
    for (final t in (body['tools'] as List? ?? const []))
      if (t is Map<String, dynamic>)
        '${(t['function'] as Map<String, dynamic>?)?['name'] ?? t['name']}',
  ];
}

Map<String, dynamic> _firstChoiceMessage(String body) =>
    ((_firstChoiceRaw(body)['message']) as Map<String, dynamic>);

Map<String, dynamic> _firstChoiceRaw(String body) =>
    ((jsonDecode(body)['choices'] as List).first as Map<String, dynamic>);

List<Map<String, dynamic>> _chunks(String body) => [
  for (final line in const LineSplitter().convert(body))
    if (line.startsWith('data:') && !line.contains('[DONE]'))
      jsonDecode(line.substring(5).trim()) as Map<String, dynamic>,
];

Map<String, dynamic> _deltaOf(Map<String, dynamic> chunk) =>
    ((chunk['choices'] as List).first as Map<String, dynamic>)['delta']
        as Map<String, dynamic>;

String _deltaText(List<Map<String, dynamic>> chunks) =>
    chunks.map((c) => '${_deltaOf(c)['content'] ?? ''}').join();

String _deltaReasoning(List<Map<String, dynamic>> chunks) =>
    chunks.map((c) => '${_deltaOf(c)['reasoning_content'] ?? ''}').join();

String? _lastFinish(List<Map<String, dynamic>> chunks) =>
    ((chunks.last['choices'] as List).first as Map<String, dynamic>)['finish_reason']
        as String?;

/// 各帧里的工具参数增量按顺序拼回来。
String _toolArgs(List<Map<String, dynamic>> chunks) {
  final out = StringBuffer();
  for (final chunk in chunks) {
    final calls = _deltaOf(chunk)['tool_calls'];
    if (calls is! List || calls.isEmpty) continue;
    final fn = (calls.first as Map)['function'];
    if (fn is Map) out.write('${fn['arguments'] ?? ''}');
  }
  return out.toString();
}

void main() {
  // 不要调用 TestWidgetsFlutterBinding.ensureInitialized()，
  // 它会把测试里所有 HttpClient 请求劫持成 400。

  const port = 19285;
  late HttpServer upstream;
  late ProxyServer proxy;
  late ProxyConfig config;
  final seen = <_Seen>[];
  late Future<void> Function(HttpRequest req) respond;

  Future<void> refuseWith500(HttpRequest req) async {
    req.response.statusCode = 500;
    await req.response.close();
  }

  setUp(() async {
    seen.clear();
    respond = refuseWith500;
    zenGatewayHosts.add('127.0.0.1');
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((req) async {
      final raw = await utf8.decoder.bind(req).join();
      Map<String, dynamic> json;
      try {
        json = raw.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(raw) as Map<String, dynamic>;
      } on FormatException {
        json = <String, dynamic>{};
      }
      seen.add(
        _Seen(
          req.uri.path,
          {
            for (final name in const [
              'authorization',
              'user-agent',
              'x-opencode-client',
              'x-opencode-session',
              'x-opencode-request',
              'x-opencode-project',
            ])
              name: req.headers.value(name) ?? '',
          },
          json,
        ),
      );
      await respond(req);
    });

    config = ProxyConfig(listenHost: '127.0.0.1', listenPort: port)
      ..upstreams.add(
        Upstream(
          id: 'zen',
          name: 'OpenCode Zen',
          baseUrl: 'http://127.0.0.1:${upstream.port}/zen/v1',
          models: [
            ModelEntry(publicName: 'space-bunny-free'),
            ModelEntry(publicName: 'union-alpha'),
            ModelEntry(
              publicName: 'muse',
              target: 'muse-spark-1.3-contributor-free',
            ),
            ModelEntry(
              publicName: 'zen-free',
              target: 'muse-spark-1.3-contributor-free',
              fallbacks: ['union-alpha'],
            ),
            ModelEntry(publicName: 'decide', target: 'jev-1.13-free'),
          ],
        ),
      )
      ..apiKeys.add(ApiKeyEntry(id: 'k', name: 't', key: 'sk-c'));

    proxy = ProxyServer(configProvider: () => config);
    await proxy.start();
  });

  tearDown(() async {
    zenGatewayHosts.remove('127.0.0.1');
    await proxy.stop();
    await upstream.close(force: true);
  });

  Future<(int, String)> send(Map<String, dynamic> payload) async {
    final client = HttpClient();
    final req = await client.openUrl(
      'POST',
      Uri.parse('http://127.0.0.1:$port/v1/chat/completions'),
    );
    req.headers.set('authorization', 'Bearer sk-c');
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(payload));
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    client.close();
    return (res.statusCode, text);
  }

  Future<(int, String)> chat(
    String model, {
    bool stream = false,
    List<Map<String, dynamic>>? tools,
    Map<String, String>? extraHeaders,
  }) async {
    final client = HttpClient();
    final req = await client.openUrl(
      'POST',
      Uri.parse('http://127.0.0.1:$port/v1/chat/completions'),
    );
    req.headers.set('authorization', 'Bearer sk-c');
    req.headers.contentType = ContentType.json;
    extraHeaders?.forEach((k, v) => req.headers.set(k, v));
    req.write(
      jsonEncode({
        'model': model,
        'messages': [
          {'role': 'user', 'content': '你好'},
        ],
        'stream': stream,
        'tools': ?tools,
      }),
    );
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    client.close();
    return (res.statusCode, text);
  }

  void replyJson(
    HttpRequest req,
    Map<String, dynamic> doc, {
    int status = 200,
  }) {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(doc));
  }

  void replySse(HttpRequest req, List<String> payloads) {
    req.response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    req.response.bufferOutput = false;
    for (final p in payloads) {
      req.response.write('data: $p\n\n');
    }
  }

  group('chat 线车道：补齐桌面客户端指纹', () {
    setUp(() {
      respond = (req) async {
        replyJson(
          req,
          {
            'id': 'cmpl-1',
            'object': 'chat.completion',
            'choices': [
              {
                'index': 0,
                'message': {'role': 'assistant', 'content': 'from-lane'},
              },
            ],
          },
        );
        await req.response.close();
      };
    });

    test('六个指纹头都带上，model 改写成上游车道名', () async {
      final (status, body) = await chat('space-bunny-free');
      expect(status, 200);
      expect(body, contains('from-lane'));

      final hop = seen.single;
      expect(hop.path, '/zen/v1/chat/completions');
      expect(hop.headers['authorization'], 'Bearer public');
      expect(hop.headers['user-agent'], kZenClientUa);
      expect(hop.headers['x-opencode-client'], 'desktop');
      expect(hop.headers['x-opencode-project'], 'global');
      expect(
        kZenSessionRe.hasMatch(hop.headers['x-opencode-session']!),
        isTrue,
      );
      expect(
        kZenRequestRe.hasMatch(hop.headers['x-opencode-request']!),
        isTrue,
      );
      expect(hop.body['model'], 'space-bunny-free');
    });

    test('body.tools 补齐四件套 —— 缺一个整条车道就 403', () async {
      await chat('space-bunny-free');
      expect(seen.single.toolNames, containsAll(kZenFingerprintTools));
    });

    test('同一会话的连续两轮共用一个 session，换会话才换', () async {
      await chat('space-bunny-free');
      final first = seen.single.headers['x-opencode-session'];
      // 第二轮客户端会带上开场白，种子不变。
      await send({
        'model': 'space-bunny-free',
        'messages': [
          {'role': 'user', 'content': '你好'},
          {'role': 'assistant', 'content': 'from-lane'},
          {'role': 'user', 'content': '再说一遍'},
        ],
      });
      expect(seen.last.headers['x-opencode-session'], first);

      // 换了开场白就是新会话。
      await send({
        'model': 'space-bunny-free',
        'messages': [
          {'role': 'user', 'content': '完全不同的开头'},
        ],
      });
      expect(seen.last.headers['x-opencode-session'], isNot(first));
    });

    test('客户端自带合法 x-opencode-session 时沿用，不另起一份额度', () async {
      final fromHost = zenSessionFor('host-session');
      await chat('space-bunny-free', extraHeaders: {
        'x-opencode-session': fromHost,
      });
      expect(seen.single.headers['x-opencode-session'], fromHost);
    });

    test('最后一条车道的 403 照原样回传，不替客户端编一个状态', () async {
      respond = (req) async {
        replyJson(
          req,
          {'error': {'message': 'FreeTierError: usage within OpenCode only'}},
          status: 403,
        );
        await req.response.close();
      };
      final (status, body) = await chat('space-bunny-free');
      expect(status, 403);
      expect(body, contains('FreeTierError'));
    });

    test('WAF 的 HTML 403 不被读成凭据失效：回一句点名的提示', () async {
      // 前置代理在任何模型被问之前就挡下了请求，状态码与凭据无关；
      // 整页 markup 是噪音，客户端只该看到「是哪一跳、为什么不该换道重试」。
      respond = (req) async {
        req.response.statusCode = 403;
        req.response.headers.contentType = ContentType.html;
        req.response.write(
          '<!doctype html>\n<html><head><title>403 Forbidden</title></head>'
          '<body>nginx: request blocked by WAF rule 942100</body></html>',
        );
        await req.response.close();
      };
      final (status, body) = await chat('space-bunny-free');
      expect(status, 403);
      final json = jsonDecode(body) as Map<String, dynamic>;
      final error = json['error'] as Map<String, dynamic>;
      expect(error['type'], 'invalid_request_error');
      expect(error['message'], contains('HTML'));
      expect(error['message'], contains('凭据'));
      expect(error['message'], isNot(contains('nginx')), reason: '页面本身不许回灌');
      expect(error['message'], isNot(contains('942100')));
    });
  });

  group('chat 线车道：客户端要非流式', () {
    // 免费档指纹门只放行 stream:true 的请求（2026-10 实测：stream:false 时
    // 除 space-bunny-free 外条条 403 FreeTierError）。所以上游一律流式，
    // 客户端要整份 JSON 时由转译器攒完回灌 —— 这一组就是守这条链路。
    test('上游被强制成流式，客户端拿到的仍是一份 chat.completion', () async {
      respond = (req) async {
        replySse(req, [
          '{"id":"c1","object":"chat.completion.chunk","choices":[{"index":0,'
              '"delta":{"role":"assistant","content":"你"},"finish_reason":null}]}',
          '{"id":"c1","object":"chat.completion.chunk","choices":[{"index":0,'
              '"delta":{"content":"好"},"finish_reason":null}]}',
          '{"id":"c1","object":"chat.completion.chunk","choices":[{"index":0,'
              '"delta":{},"finish_reason":"stop"}],'
              '"usage":{"prompt_tokens":7,"completion_tokens":2,"total_tokens":9}}',
          '[DONE]',
        ]);
        await req.response.close();
      };

      final (status, body) = await chat('space-bunny-free', stream: false);
      expect(status, 200);
      // 出站：客户端说不要流式，上游那边必须还是流式。
      expect(seen.single.body['stream'], isTrue);
      // 但**绝不带 stream_options**：官方 opencode 客户端不发这个字段
      // （zen-gate 的 zen 车道 body 只有 {"model","stream":true,…}，只有
      // 带账号凭据的 WorkBuddy 渠道才写它），多带一个就是给指纹门递把柄。
      expect(seen.single.body.containsKey('stream_options'), isFalse);
      // 回站：一份整的 JSON，不是 SSE。
      expect(body, isNot(contains('data:')));
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['object'], 'chat.completion');
      expect(_firstChoiceMessage(body)['content'], '你好');
      expect(_firstChoiceMessage(body)['role'], 'assistant');
      expect(_firstChoiceRaw(body)['finish_reason'], 'stop');
      expect(json['usage']['total_tokens'], 9);
    });

    test('上游一帧 usage 都不回时优雅降级：不带 usage 键、不抛异常', () async {
      // 删掉 stream_options:{include_usage:true} 的直接后果就是上游可能不再
      // 补 usage 帧。token 统计因此只能缺省 —— 但整条链路必须照常出字，
      // 不许因为「usage 没了」而 500。
      respond = (req) async {
        replySse(req, [
          '{"id":"c9","object":"chat.completion.chunk","choices":[{"index":0,'
              '"delta":{"role":"assistant","content":"没有用量"},"finish_reason":null}]}',
          '{"id":"c9","object":"chat.completion.chunk","choices":[{"index":0,'
              '"delta":{},"finish_reason":"stop"}]}',
          '[DONE]',
        ]);
        await req.response.close();
      };

      final (status, body) = await chat('space-bunny-free', stream: false);
      expect(status, 200);
      expect(seen.single.body.containsKey('stream_options'), isFalse);
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(_firstChoiceMessage(body)['content'], '没有用量');
      expect(
        json.containsKey('usage'),
        isFalse,
        reason: '上游没给就不许自己编一个 usage 出来',
      );
    });

    test('客户端要流式时上游的 SSE 原样透传，出站体同样不带 stream_options', () async {
      respond = (req) async {
        replySse(req, [
          '{"id":"c10","object":"chat.completion.chunk","choices":[{"index":0,'
              '"delta":{"role":"assistant","content":"直通的"},"finish_reason":null}]}',
          '{"id":"c10","object":"chat.completion.chunk","choices":[{"index":0,'
              '"delta":{},"finish_reason":"stop"}]}',
          '[DONE]',
        ]);
        await req.response.close();
      };
      final (status, body) = await chat('space-bunny-free', stream: true);
      expect(status, 200);
      expect(seen.single.body.containsKey('stream_options'), isFalse);
      expect(_deltaText(_chunks(body)), '直通的');
    });

    test('上游用一整份 JSON 回答流式请求时照样拼得出正文', () async {
      respond = (req) async {
        replyJson(req, {
          'id': 'c2',
          'object': 'chat.completion',
          'choices': [
            {
              'index': 0,
              'message': {'role': 'assistant', 'content': '整份的答案'},
              'finish_reason': 'stop',
            },
          ],
        });
        await req.response.close();
      };
      final (status, body) = await chat('space-bunny-free');
      expect(status, 200);
      expect(_firstChoiceMessage(body)['content'], '整份的答案');
    });

    test('工具调用的增量在整份 JSON 里拼成完整的 tool_calls', () async {
      respond = (req) async {
        replySse(req, [
          '{"id":"c3","object":"chat.completion.chunk","choices":[{"index":0,'
              '"delta":{"tool_calls":[{"index":0,"id":"call_9","type":"function",'
              '"function":{"name":"read","arguments":""}}]}}]}',
          '{"id":"c3","object":"chat.completion.chunk","choices":[{"index":0,'
              '"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"a\\": "}}]}}]}',
          '{"id":"c3","object":"chat.completion.chunk","choices":[{"index":0,'
              '"delta":{"tool_calls":[{"index":0,"function":{"arguments":"1}"}}]}}]}',
          '{"id":"c3","object":"chat.completion.chunk","choices":[{"index":0,'
              '"delta":{},"finish_reason":"tool_calls"}]}',
          '[DONE]',
        ]);
        await req.response.close();
      };
      final (status, body) = await chat('space-bunny-free');
      expect(status, 200);
      final calls = _firstChoiceMessage(body)['tool_calls'] as List;
      expect(calls.length, 1);
      expect((calls.first as Map)['id'], 'call_9');
      expect((calls.first as Map)['function']['name'], 'read');
      expect(jsonDecode((calls.first as Map)['function']['arguments']), {'a': 1});
      expect(_firstChoiceRaw(body)['finish_reason'], 'tool_calls');
    });
  });

  group('messages 线车道（union-alpha）', () {
    test('打到 /zen/v1/messages，Anthropic SSE 回译成 OpenAI chunk', () async {
      respond = (req) async {
        replySse(req, [
          '{"type":"message_start","message":{"usage":{"input_tokens":11}}}',
          '{"type":"content_block_start","index":0,"content_block":{"type":"thinking"}}',
          '{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"让我"}}',
          '{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"想想"}}',
          '{"type":"content_block_start","index":1,"content_block":{"type":"text"}}',
          '{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"你"}}',
          '{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"好"}}',
          '{"type":"content_block_stop","index":1}',
          '{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":5}}',
          '{"type":"message_stop"}',
        ]);
        await req.response.close();
      };

      final (status, body) = await chat('union-alpha', stream: true);
      final chunks = _chunks(body);

      expect(status, 200);
      expect(seen.single.path, '/zen/v1/messages');
      expect(seen.single.body['anthropic_version'], '2023-06-01');
      expect(seen.single.body.containsKey('system'), isFalse);
      expect(seen.single.toolNames, containsAll(kZenFingerprintTools));
      expect(_deltaText(chunks), '你好');
      expect(_deltaReasoning(chunks), '让我想想');
      expect(_lastFinish(chunks), 'stop');
      expect(body, contains('[DONE]'));
      // 首帧要带 role，OpenAI 的增量形状就是这样。
      expect(_deltaOf(chunks.first)['role'], 'assistant');
      expect(chunks.first['object'], 'chat.completion.chunk');
      expect(chunks.first['model'], 'union-alpha');
    });

    test('客户端要非流式：整份文档拼成一份 chat.completion，usage 换算成 OpenAI 字段', () async {
      respond = (req) async {
        replyJson(
          req,
          {
            'type': 'message',
            'role': 'assistant',
            'content': [
              {'type': 'thinking', 'thinking': '想了一下'},
              {'type': 'text', 'text': '答案在这里'},
            ],
            'stop_reason': 'end_turn',
            'usage': {'input_tokens': 11, 'output_tokens': 5},
          },
        );
        await req.response.close();
      };

      final (status, body) = await chat('union-alpha');
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(status, 200);
      // 客户端要非流式 ≠ 上游能发非流式：免费档指纹门只放行 stream:true，
      // 所以上游永远是流式，攒成整份 JSON 是我们对客户端的呈现。
      expect(seen.single.body['stream'], isTrue);
      expect(_firstChoiceMessage(body)['content'], '答案在这里');
      expect(_firstChoiceMessage(body)['reasoning_content'], '想了一下');
      expect(json['object'], 'chat.completion');
      expect(json['usage'], {
        'prompt_tokens': 11,
        'completion_tokens': 5,
        'total_tokens': 16,
      });
      expect(body, isNot(contains('data:')));
    });

    test('调用方的 pwsh 被提升成 bash 过门，回来的工具名还原成 pwsh', () async {
      respond = (req) async {
        replySse(req, [
          '{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"tu1","name":"bash"}}',
          '{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"p\\":1}"}}',
          '{"type":"content_block_stop","index":0}',
          '{"type":"message_delta","delta":{"stop_reason":"tool_use"}}',
        ]);
        await req.response.close();
      };

      final (status, body) = await chat(
        'union-alpha',
        stream: true,
        tools: [
          {
            'type': 'function',
            'function': {
              'name': 'pwsh',
              'parameters': {'type': 'object'},
            },
          },
        ],
      );
      expect(status, 200);
      // 出站：pwsh 顶替了 bash 槽位，所以四件套齐且不再有 pwsh 这个名字。
      expect(seen.single.toolNames, containsAll(kZenFingerprintTools));
      expect(seen.single.toolNames, isNot(contains('pwsh')));
      // 回站：模型说的是 bash，客户端注册的是 pwsh，必须还原回去才能执行。
      final chunks = _chunks(body);
      final call = (_deltaOf(chunks.first)['tool_calls'] as List).first
          as Map<String, dynamic>;
      expect(call['function']['name'], 'pwsh');
      expect(call['id'], 'tu1');
      expect(_deltaText(chunks), isEmpty);

      // 参数增量拼完是调用方能直接 parse 的 JSON。
      expect(jsonDecode(_toolArgs(chunks)), {'p': 1});
    });

    test('上游的错误体换成 OpenAI 的形状再回给客户端', () async {
      respond = (req) async {
        replyJson(
          req,
          {
            'type': 'error',
            'error': {'type': 'overloaded_error', 'message': 'RegionError'},
          },
          status: 403,
        );
        await req.response.close();
      };
      final (status, body) = await chat('union-alpha');
      expect(status, 403);
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['error'], isA<Map<String, dynamic>>());
      expect((json['error'] as Map)['type'], isNotNull);
      expect((json['error'] as Map)['message'], contains('地区'));
    });
  });

  group('responses 线车道（muse-spark）', () {
    test('打到 /zen/v1/responses，Responses SSE 回译', () async {
      respond = (req) async {
        replySse(req, [
          '{"type":"response.output_item.added","output_index":0,"item":{"type":"reasoning"}}',
          '{"type":"response.reasoning_summary_text.delta","output_index":0,"delta":"思考"}',
          '{"type":"response.output_item.added","output_index":1,"item":{"type":"message"}}',
          '{"type":"response.output_text.delta","output_index":1,"delta":"Hel"}',
          '{"type":"response.output_text.delta","output_index":1,"delta":"lo"}',
          '{"type":"response.output_item.done","output_index":1}',
          '{"type":"response.completed","response":{"usage":{"input_tokens":3,"output_tokens":2,"total_tokens":5}}}',
        ]);
        await req.response.close();
      };

      final (status, body) = await chat('muse', stream: true);
      final chunks = _chunks(body);
      expect(status, 200);
      expect(seen.single.path, '/zen/v1/responses');
      expect(seen.single.body['store'], isFalse);
      expect(seen.single.body['max_output_tokens'], kZenDefaultMaxTokens);
      expect(seen.single.body['input'], isA<List>());
      expect(seen.single.toolNames, containsAll(kZenFingerprintTools));
      expect(_deltaText(chunks), 'Hello');
      expect(_deltaReasoning(chunks), '思考');
      expect(_lastFinish(chunks), 'stop');
    });

    test('上游用一整份 JSON 回答了流式请求：仍然回灌成 SSE', () async {
      respond = (req) async {
        replyJson(
          req,
          {
            'id': 'resp_1',
            'object': 'response',
            'status': 'completed',
            'output': [
              {
                'type': 'message',
                'content': [
                  {'type': 'output_text', 'text': '整份文档的答案'},
                ],
              },
            ],
            'usage': {'input_tokens': 2, 'output_tokens': 4},
          },
        );
        await req.response.close();
      };

      final (status, body) = await chat('muse', stream: true);
      expect(status, 200);
      expect(body, contains('chat.completion.chunk'));
      expect(_deltaText(_chunks(body)), '整份文档的答案');
      expect(body, contains('[DONE]'));
    });

    test('输出被 max_tokens 截断时回 length 而不是 stop', () async {
      respond = (req) async {
        replySse(req, [
          '{"type":"response.output_item.added","output_index":0,"item":{"type":"message"}}',
          '{"type":"response.output_text.delta","output_index":0,"delta":"半截"}',
          '{"type":"response.incomplete","response":{"incomplete_details":{"reason":"max_output_tokens"}}}',
        ]);
        await req.response.close();
      };
      final (_, body) = await chat('muse', stream: true);
      expect(_lastFinish(_chunks(body)), 'length');
    });
  });

  group('跨线回退与提前止损', () {
    test('第一条车道被拒时第二条换了线协议照样出字，客户端只看到一个响应', () async {
      respond = (req) async {
        if (req.uri.path == '/zen/v1/responses') {
          replyJson(
            req,
            {
              'error': {'message': 'RegionError: not available in your country'},
            },
            status: 403,
          );
        } else {
          replyJson(
            req,
            {
              'type': 'message',
              'content': [
                {'type': 'text', 'text': '换线接住了'},
              ],
              'stop_reason': 'end_turn',
            },
          );
        }
        await req.response.close();
      };

      final (status, body) = await chat('zen-free');
      expect(status, 200);
      expect(_firstChoiceMessage(body)['content'], '换线接住了');
      // 先试 responses，再落到 messages —— 两条车道的端点确实不一样。
      expect(seen.map((s) => s.path), ['/zen/v1/responses', '/zen/v1/messages']);
    });

    test('额度打满（429）时不再往下试：同一 session 每条都会 429', () async {
      respond = (req) async {
        replyJson(
          req,
          {'error': {'message': 'FreeUsageLimitError'}},
          status: 429,
        );
        await req.response.close();
      };
      final (status, _) = await chat('zen-free');
      expect(status, 429);
      expect(seen.length, 1);
    });

    test('判定模型不产文本：直接拒绝，一个请求都不发往上游', () async {
      final (status, body) = await chat('decide');
      expect(status, 400);
      expect(body, contains('System One'));
      expect(seen, isEmpty);
    });
  });

  group('不是 Zen 网关的上游不受影响', () {
    test('本机普通上游保持原样透传：不带指纹头、只改写 model', () async {
      zenGatewayHosts.remove('127.0.0.1');
      config.upstreams
        ..clear()
        ..add(
          Upstream(
            id: 'plain',
            name: 'plain',
            baseUrl: 'http://127.0.0.1:${upstream.port}/v1',
            models: [ModelEntry(publicName: 'local-model')],
          ),
        );
      respond = (req) async {
        replyJson(
          req,
          {
            'id': 'cmpl-2',
            'choices': [
              {
                'index': 0,
                'message': {'role': 'assistant', 'content': 'plain'},
              },
            ],
          },
        );
        await req.response.close();
      };

      final (status, body) = await chat('local-model');
      expect(status, 200);
      expect(body, contains('plain'));
      expect(seen.single.path, '/v1/chat/completions');
      expect(seen.single.headers['x-opencode-session'], isEmpty);
      expect(seen.single.toolNames, isEmpty);
      expect(seen.single.body['model'], 'local-model');
    });
  });
}
