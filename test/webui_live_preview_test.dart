// 手动实测用的「常驻预览」：平时跳过，设 L2A_PREVIEW=1 才跑。
//
// 它起两个本机服务：
//   * 一个**假上游 API**（只实现 /v1/models 与 /v1/chat/completions，
//     SSE 流式回，并把收到的最后一条请求体写进 build/_scratch/last_body.json）；
//   * 真正的 [WebUiServer]（就是 App 里那个页面，资源从 assets/webui 读盘）。
// 然后停在 http://127.0.0.1:19300 等浏览器连，直到有人创建
// build/_scratch/preview.done 才收工 —— 这样输入框样式、图片上传、
// 上下文弹层这些都能在真浏览器里点一遍，而不是只看代码。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/webui_server.dart';

void main() {
  test('WebUI 常驻预览（人工实测）', () async {
    if (Platform.environment['L2A_PREVIEW'] != '1') {
      markTestSkipped('设 L2A_PREVIEW=1 才起常驻预览服务');
      return;
    }

    final scratch = Directory('build/_scratch')..createSync(recursive: true);
    final lastBody = File('${scratch.path}/last_body.json');
    if (lastBody.existsSync()) lastBody.deleteSync();

    // ---- 假上游：看见什么就回什么，方便在页面上直接读出结果 ----
    final api = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api.listen((req) async {
      if (req.uri.path == '/v1/models') {
        req.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'object': 'list',
              'data': [
                {
                  'id': 'vision-alias',
                  'context_length': 8192,
                  'max_output_tokens': 1024,
                },
                {'id': 'text-only-lane'},
              ],
            }),
          );
        await req.response.close();
        return;
      }
      if (req.uri.path == '/v1/chat/completions') {
        final raw = await utf8.decoder.bind(req).join();
        lastBody.writeAsStringSync(raw);
        void log(String m) => File(
          'build/_scratch/mock.log',
        ).writeAsStringSync('$m\n', mode: FileMode.append);
        log('body ${raw.length}B');
        try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final msgs = (json['messages'] as List).cast<Map<String, dynamic>>();
        final last = msgs.last;
        final content = last['content'];
        final parts = content is List ? content : <Object>[];
        final images = parts
            .whereType<Map<String, dynamic>>()
            .where((p) => p['type'] == 'image_url')
            .length;
        final text = content is String
            ? content
            : parts
                  .whereType<Map<String, dynamic>>()
                  .where((p) => p['type'] == 'text')
                  .map((p) => '${p['text']}')
                  .join(' ');
        final answer =
            '收到 ${msgs.length} 条消息；最后一条 content 是'
            '${content is String ? '字符串' : '数组'}，'
            '图片 $images 张，文字「$text」。';

        req.response
          ..headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8')
          ..headers.set('x-local2api-lane', 'mock-lane');
        // 按 SSE 一 chunk 一词地吐，顺便验证流式解析
        for (final piece in <String>[answer.substring(0, 6), answer.substring(6)]) {
          req.response.write(
            'data: ${jsonEncode({'choices': [{'delta': {'content': piece}}]})}\n\n',
          );
          await req.response.flush();
          log('flushed piece');
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
        req.response.write(
          'data: ${jsonEncode({'usage': {'prompt_tokens': 321, 'completion_tokens': 40}})}\n\n',
        );
        req.response.write('data: [DONE]\n\n');
        await req.response.close();
        log('closed');
        } catch (e, st) {
          log('EXC $e\n$st');
          try { await req.response.close(); } catch (_) {}
        }
        return;
      }
      req.response.statusCode = 404;
      await req.response.close();
    });

    // ---- 真的 WebUiServer（与 App 里同一个类、同一份 HTML） ----
    final config = ProxyConfig(
      listenHost: '127.0.0.1',
      listenPort: api.port,
      webUiHost: '127.0.0.1',
      webUiPort: 19300,
    )..apiKeys.add(ApiKeyEntry(id: 'k', name: 'preview', key: 'sk-preview'));

    final ui = WebUiServer(
      configProvider: () => config,
      assetLoader: (name) => File('assets/webui/$name').readAsBytes(),
    );
    await ui.start();

    stdout.writeln('PREVIEW-URL ${ui.url}');
    final done = File('${scratch.path}/preview.done');
    while (!done.existsSync()) {
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    done.deleteSync();

    await ui.stop();
    await api.close(force: true);
  }, timeout: const Timeout(Duration(minutes: 30)));
}
