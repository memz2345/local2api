// 这一组要真起 HTTP 服务验证「请求体里带没带历史」，所以**不能**初始化
// flutter_test 的 widget binding —— 它会把 HttpClient 换成假的（一律回 400），
// 真请求发不出去。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/chat_simulation.dart';
import 'package:local2api/services/proxy_server.dart';

void main() {
  group('端到端：发出去的请求确实带上了历史', () {
    late HttpServer server;
    final received = <String>[];

    setUp(() async {
      received.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final body = await utf8.decoder.bind(req).join();
        received.add(body);
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'model': 'space-bunny-free',
              'choices': [
                {
                  'index': 0,
                  'message': {'role': 'assistant', 'content': '收到你的第二问'},
                },
              ],
            }),
          );
        await req.response.close();
      });
    });

    tearDown(() async => server.close(force: true));

    test('历史按顺序整串发出去，model 用对外名', () async {
      final config = ProxyConfig()
        ..listenHost = '127.0.0.1'
        ..listenPort = server.port;

      final result = await ChatSimulator.send(
        config: config,
        model: 'zen-free',
        messages: [
          ChatMsg(ChatRole.system, 'You are a helpful assistant.'),
          ChatMsg(ChatRole.user, '第一问'),
          ChatMsg(ChatRole.assistant, '第一答'),
          ChatMsg(ChatRole.user, '第二问'),
        ],
      );

      expect(result.ok, isTrue);
      expect(result.content, '收到你的第二问');
      expect(received, hasLength(1));

      final sent = jsonDecode(received.single) as Map<String, dynamic>;
      expect(sent['model'], 'zen-free');
      expect(sent['stream'], isFalse);
      final messages = sent['messages'] as List;
      expect(messages, hasLength(4), reason: '前面的聊天记录必须一起带出去');
      expect(messages.map((m) => '${(m as Map)['role']}'), [
        'system',
        'user',
        'assistant',
        'user',
      ]);
      expect(messages.map((m) => '${(m as Map)['content']}'), [
        'You are a helpful assistant.',
        '第一问',
        '第一答',
        '第二问',
      ]);
    });

    test('失败提示那条不进请求体（它是本地状态不是历史）', () async {
      final config = ProxyConfig()
        ..listenHost = '127.0.0.1'
        ..listenPort = server.port;

      await ChatSimulator.send(
        config: config,
        model: 'zen-free',
        messages: [
          ChatMsg(ChatRole.user, '在吗'),
          ChatMsg(ChatRole.assistant, 'HTTP 403', error: true),
          ChatMsg(ChatRole.user, '再试一次'),
        ],
      );

      final sent = jsonDecode(received.single) as Map<String, dynamic>;
      expect((sent['messages'] as List), hasLength(2));
      expect(
        (sent['messages'] as List).map((m) => '${(m as Map)['content']}'),
        ['在吗', '再试一次'],
      );
    });

    test('连不上本机代理时给出可读原因（服务没跑）', () async {
      // 先关掉服务器占用的端口：拿一个刚关掉的端口去连
      final port = server.port;
      await server.close(force: true);
      final config = ProxyConfig()
        ..listenHost = '127.0.0.1'
        ..listenPort = port;

      final result = await ChatSimulator.send(
        config: config,
        model: 'zen-free',
        messages: [ChatMsg(ChatRole.user, 'hi')],
      );
      expect(result.ok, isFalse);
      expect(result.content, contains('连不上本机代理'));
    });
  });

  group('端到端：仅发送（不等模型回复）', () {
    late HttpServer server;
    final received = <String>[];
    const replyDelay = Duration(milliseconds: 1500);

    setUp(() async {
      received.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final body = await utf8.decoder.bind(req).join();
        received.add(body);
        // 故意慢回：只发不等的话，这段时间根本不该被等满
        await Future<void>.delayed(replyDelay);
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'model': 'm',
              'choices': [
                {
                  'index': 0,
                  'message': {'role': 'assistant', 'content': '慢答案'},
                },
              ],
            }),
          );
        await req.response.close();
      });
    });

    tearDown(() async => server.close(force: true));

    test('请求发出去就返回，不等那 1.5s 的回复', () async {
      final config = ProxyConfig()
        ..listenHost = '127.0.0.1'
        ..listenPort = server.port;

      final sw = Stopwatch()..start();
      final result = await ChatSimulator.sendOnly(
        config: config,
        model: 'zen-free',
        messages: [
          ChatMsg(ChatRole.system, 'You are a helpful assistant.'),
          ChatMsg(ChatRole.user, '在吗'),
        ],
      );
      sw.stop();

      expect(result.ok, isTrue);
      expect(result.content, isEmpty, reason: '不请求回复，正文就是空的');
      expect(
        sw.elapsedMilliseconds,
        lessThan(replyDelay.inMilliseconds),
        reason: '等回复就不是「仅发送」了',
      );

      // 请求真的到了本机代理，带的还是界面上那串消息
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(received, hasLength(1));
      final sent = jsonDecode(received.single) as Map<String, dynamic>;
      expect(sent['model'], 'zen-free');
      expect(sent['stream'], isFalse);
      expect(
        (sent['messages'] as List).map((m) => '${(m as Map)['role']}'),
        ['system', 'user'],
      );
    });

    test('连不上代理时仍然同步报错（那时确实什么都没发出去）', () async {
      final port = server.port;
      await server.close(force: true);
      final config = ProxyConfig()
        ..listenHost = '127.0.0.1'
        ..listenPort = port;

      final result = await ChatSimulator.sendOnly(
        config: config,
        model: 'm',
        messages: [ChatMsg(ChatRole.user, 'hi')],
      );

      expect(result.ok, isFalse);
      expect(result.content, contains('连不上本机代理'));
    });
  });

  group('端到端：auto 路由把真实车道带回来', () {
    late HttpServer server;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        await utf8.decoder.bind(req).join();
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          // 网关回显对外名 + 响应头带真实车道，就是代理那边的真实行为
          ..headers.set(kServedLaneHeader, 'space-bunny-free')
          ..write(
            jsonEncode({
              'model': 'zen-free',
              'choices': [
                {
                  'index': 0,
                  'message': {'role': 'assistant', 'content': '答完了'},
                },
              ],
            }),
          );
        await req.response.close();
      });
    });

    tearDown(() async => server.close(force: true));

    test('回显模型名与真实车道分开落在结果里', () async {
      final config = ProxyConfig()
        ..listenHost = '127.0.0.1'
        ..listenPort = server.port;

      final result = await ChatSimulator.send(
        config: config,
        model: 'zen-free',
        messages: [ChatMsg(ChatRole.user, '嗨')],
      );

      expect(result.ok, isTrue);
      expect(result.model, 'zen-free');
      expect(result.lane, 'space-bunny-free');
    });

    test('没有车道头时 lane 为空，模型名照旧', () async {
      // 换一个不回头的端点：直接把结果当作非路由响应
      final plain = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      plain.listen((req) async {
        await utf8.decoder.bind(req).join();
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'model': 'lane-s',
              'choices': [
                {
                  'index': 0,
                  'message': {'role': 'assistant', 'content': 'ok'},
                },
              ],
            }),
          );
        await req.response.close();
      });

      final config = ProxyConfig()
        ..listenHost = '127.0.0.1'
        ..listenPort = plain.port;

      final result = await ChatSimulator.send(
        config: config,
        model: 'lane-s',
        messages: [ChatMsg(ChatRole.user, '嗨')],
      );
      await plain.close(force: true);

      expect(result.model, 'lane-s');
      expect(result.lane, isNull);
    });
  });

  // 图片输入的整链路：对话模拟 → 本机代理 → 上游。代理只改写 model 字段、
  // 不动 messages，所以多模态 content 要原样落到上游才算「模型真收到了图」。
  group('端到端：图片随消息发到上游', () {
    late HttpServer mockUpstream;
    late ProxyServer proxy;
    late ProxyConfig config;
    Map<String, dynamic>? upstreamBody;

    // 1×1 JPEG 的字节头，够 data URL 拼出来
    final jpeg = Uint8List.fromList(<int>[
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
      0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9,
    ]);

    setUp(() async {
      upstreamBody = null;
      mockUpstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      mockUpstream.listen((req) async {
        upstreamBody =
            jsonDecode(await utf8.decoder.bind(req).join())
                as Map<String, dynamic>;
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'model': 'vision-alias',
              'choices': [
                {
                  'index': 0,
                  'message': {'role': 'assistant', 'content': '一只猫'},
                },
              ],
              'usage': {'prompt_tokens': 300, 'completion_tokens': 5},
            }),
          );
        await req.response.close();
      });

      config = ProxyConfig(listenHost: '127.0.0.1', listenPort: 19297)
        ..upstreams.add(
          Upstream(
            id: 'u1',
            name: 'mock',
            baseUrl: 'http://127.0.0.1:${mockUpstream.port}/v1',
            models: [ModelEntry(publicName: 'vision-alias', target: 'vision')],
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

    test('带图那条以 content parts 到达上游，data URL 完整', () async {
      final result = await ChatSimulator.send(
        config: config,
        model: 'vision-alias',
        messages: [
          ChatMsg(ChatRole.system, '看图说话'),
          ChatMsg(
            ChatRole.user,
            '这是什么',
            attachments: [
              ChatAttachment(
                name: 'cat.jpg',
                isImage: true,
                sizeBytes: jpeg.length,
                thumbnail: jpeg,
              ),
            ],
          ),
        ],
      );

      expect(result.ok, isTrue);
      expect(result.content, '一只猫');
      expect(result.usageTokens, 305);

      final msgs = upstreamBody!['messages'] as List;
      // 代理把对外名换成上游真名再转发（messages 原样不动）
      expect(upstreamBody!['model'], 'vision');
      expect((msgs[0] as Map)['content'], '看图说话');
      final parts = (msgs[1] as Map)['content'];
      expect(parts, isA<List>(), reason: '带图的那条必须是多模态数组');
      expect((parts as List)[0], {'type': 'text', 'text': '这是什么'});
      expect(
        ((parts[1]) as Map)['image_url'],
        {'url': 'data:image/jpeg;base64,${base64Encode(jpeg)}'},
      );
    });

    test('关掉带图开关后上游只收到文字，图片留在界面上', () async {
      await ChatSimulator.send(
        config: config,
        model: 'vision-alias',
        includeImages: false,
        messages: [
          ChatMsg(
            ChatRole.user,
            '这是什么',
            attachments: [
              ChatAttachment(
                name: 'cat.jpg',
                isImage: true,
                thumbnail: jpeg,
              ),
            ],
          ),
        ],
      );

      final msgs = upstreamBody!['messages'] as List;
      expect((msgs.single as Map)['content'], '这是什么');
    });
  });
}
