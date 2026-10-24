// agent 实测常驻服务（设 L2A_AGENT=1 才跑）：
//   * mock Zen 上游：把收到的最后一份请求体写进 build/_scratch/agent_upstream_body.json
//   * 真正的 ProxyServer：Zen 车道（回环 mock，过指纹门），端口 19292
// 然后 opencode CLI 用独立配置打进来，验证「agent 选的思考档位」一路落到上游。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:local2api/services/zen/zen_protocol.dart';

void main() {
  test('agent 实测常驻（人工）', () async {
    if (Platform.environment['L2A_AGENT'] != '1') {
      markTestSkipped('设 L2A_AGENT=1 才起 agent 实测服务');
      return;
    }

    final scratch = Directory('build/_scratch')..createSync(recursive: true);
    final upstreamBody = File('${scratch.path}/agent_upstream_body.json');
    if (upstreamBody.existsSync()) upstreamBody.deleteSync();

    // 回环 mock 要进 zen 网关白名单才能过指纹门（同 zen_lane_test 的做法）。
    zenGatewayHosts.add('127.0.0.1');
    addTearDown(() => zenGatewayHosts.remove('127.0.0.1'));

    final mock = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    mock.listen((req) async {
      if (req.uri.path.endsWith('/chat/completions')) {
        final raw = await utf8.decoder.bind(req).join();
        upstreamBody.writeAsStringSync(raw);
        req.response.headers.contentType =
            ContentType('text', 'event-stream', charset: 'utf-8');
        req.response.bufferOutput = false;
        final body = <String>[
          '档位已收到。上游实际拿到的 max_tokens 在日志里。',
          '（本条由 mock 上游回给 agent）',
        ];
        for (final piece in body) {
          req.response.write(
            'data: ${jsonEncode({
              'choices': [
                {'delta': {'content': piece}},
              ],
            })}\n\n',
          );
          await req.response.flush();
        }
        req.response.write(
          'data: ${jsonEncode({
            'choices': [
              {'delta': {}, 'finish_reason': 'stop'},
            ],
          })}\n\n',
        );
        await req.response.flush();
        req.response.write(
          'data: ${jsonEncode({
            'choices': <Object>[],
            'usage': {'prompt_tokens': 12, 'completion_tokens': 34},
          })}\n\n',
        );
        req.response.write('data: [DONE]\n\n');
        await req.response.close();
        return;
      }
      if (req.uri.path.endsWith('/models')) {
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          jsonEncode({
            'object': 'list',
            'data': [
              {'id': 'step-5-preview-free'},
            ],
          }),
        );
        await req.response.close();
        return;
      }
      req.response.statusCode = 404;
      await req.response.close();
    });

    final config = ProxyConfig(listenHost: '127.0.0.1', listenPort: 19292)
      ..upstreams.add(
        Upstream(
          id: 'zen',
          name: 'Zen',
          type: UpstreamType.openai,
          // isZenGateway 要求路径第一段是 zen：mock 伪装成 /zen/v1。
          baseUrl: 'http://127.0.0.1:${mock.port}/zen/v1',
          models: [
            ModelEntry(
              publicName: 'zen-free',
              target: 'step-5-preview-free',
              maxOutputTokens: 64000,
            ),
          ],
        ),
      )
      ..apiKeys.add(ApiKeyEntry(id: 'k', name: 'agent', key: 'sk-agent'));
    // isZenGateway 看 baseUrl 的 host + 路径；mock 的 /v1 路径要长得像 zen。
    // （host 已进白名单；isZenGateway 的判定见 proxy_config。）
    final proxy = ProxyServer(configProvider: () => config);
    await proxy.start();

    stdout.writeln('AGENT-URL http://127.0.0.1:19292/v1  key=sk-agent');
    final done = File('${scratch.path}/agent_preview.done');
    while (!done.existsSync()) {
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    done.deleteSync();
    await proxy.stop();
    await mock.close(force: true);
  }, timeout: const Timeout(Duration(minutes: 30)));
}
