// integration_test/macos_dsh_smoke_test.dart
//
// macOS 端到端冒烟（GitHub Actions 的 macos-14 runner 上跑）：
//   1. 用 workflow 预先 npm 装好的 DSH（环境变量 L2A_DSH_DIR）启动；
//   2. 应用自己写 cordis.patch.yml，把本地代理的 ci-model 挂给 DSH；
//   3. 在应用真实的内置浏览器（BrowserPage → WKWebView）里打开 DSH；
//   4. 在 DSH 输入框里发一条任务，假上游流式回复，确认 UI 走到「已完成」；
//   5. 每一步都截图（原生 screencapture + Flutter 图层各一张）。
//
// 这不是 Android 那种「装 Node 运行时」测试：macOS 桌面直接用系统 node/npm，
// DSH 的安装由 CI 提前完成。假上游只验证 DSH → local2api → 上游这条链路，
// 真实模型能力仍由用户在自己的 Mac 上接真上游验证。
//
// 跑法（macOS 本机 / CI）：
//   L2A_DSH_DIR=<含 node_modules/@deepseek-ai/dsh 的目录> \
//   DSH_HOME=<临时 home> \
//   flutter test integration_test/macos_dsh_smoke_test.dart -d macos

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:local2api/main.dart' as app;
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/browser_controller.dart';
import 'package:local2api/services/lab/dsh_service.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:local2api/ui/browser_page.dart';
import 'package:local2api/ui/dsh_page.dart';

const String _taskPrompt = '帮我看一下当前工作区，然后告诉我结果';
const String _fakeReply = 'macOS DSH 离线任务完成：本地假上游回复正常。';

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> _capture(
  WidgetTester tester,
  String name,
  GlobalKey boundaryKey,
) async {
  final dir = Platform.environment['L2A_SHOT_DIR'] ?? 'build/macos_shots';
  await Directory(dir).create(recursive: true);

  // 1) 原生整屏截图：能拍到 WKWebView 的真实内容。
  final nativePath = p.join(dir, '$name.png');
  try {
    final result = await Process.run(
      'screencapture',
      ['-x', nativePath],
    ).timeout(const Duration(seconds: 20));
    // ignore: avoid_print
    print('SHOT native $name exit=${result.exitCode} ${result.stderr}');
  } catch (e) {
    // ignore: avoid_print
    print('SHOT native $name failed: $e');
  }

  // 2) Flutter 页面截图：不依赖屏幕录制权限，至少能留下应用界面。
  //    页面外面套了 RepaintBoundary（见下），平台视图（WKWebView）不会进
  //    这张图，网页内容靠上面那张原生截图。
  try {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundaryKey),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return;
    final flutterPath = p.join(dir, '$name.flutter.png');
    await File(
      flutterPath,
    ).writeAsBytes(data.buffer.asUint8List(), flush: true);
    // ignore: avoid_print
    print('SHOT flutter $name -> $flutterPath');
  } catch (e) {
    // ignore: avoid_print
    print('SHOT flutter $name failed: $e');
  }
}

/// 离线假 OpenAI 上游：/v1/models + 流式 /v1/chat/completions。
///
/// 返回一句固定中文，DSH 收到后会把它渲染成助手消息。这样 macOS CI 不需要
/// 任何真实模型或密钥，也能验证「DSH → local2api → 上游」整条链路。
Future<HttpServer> _startFakeUpstream() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    try {
      // HttpResponse.write 默认按 Content-Type 的 charset 编码；SSE 这里
      // 没写 charset 时会退回 latin1，中文回复直接抛 "Contains invalid
      // characters"。HttpResponse.encoding 本身不可改，只能在 Content-Type
      // 上显式带 charset=utf-8。
      if (req.method == 'GET' && req.uri.path.endsWith('/models')) {
        req.response.headers.contentType = ContentType(
          'application',
          'json',
          charset: 'utf-8',
        );
        req.response.write(
          jsonEncode({
            'object': 'list',
            'data': [
              {
                'id': 'ci-model',
                'object': 'model',
                'created': 0,
                'owned_by': 'mock',
              },
            ],
          }),
        );
        await req.response.close();
        return;
      }

      final raw = await utf8.decoder.bind(req).join();
      Map<String, dynamic> body = <String, dynamic>{};
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) body = decoded.cast<String, dynamic>();
      } catch (_) {}
      final isStream = body['stream'] == true;
      final model = '${body['model'] ?? 'ci-model'}';
      final base = <String, Object?>{
        'id': 'chatcmpl-macos-ci',
        'created': 0,
        'model': model,
      };

      if (isStream) {
        req.response.statusCode = 200;
        req.response.headers.set(
          'content-type',
          'text/event-stream; charset=utf-8',
        );
        req.response.headers.set('cache-control', 'no-cache');
        void send(Map<String, Object?> chunk) {
          req.response.write('data: ${jsonEncode(chunk)}\n\n');
        }

        send({
          ...base,
          'object': 'chat.completion.chunk',
          'choices': [
            {
              'index': 0,
              'delta': {'role': 'assistant'},
              'finish_reason': null,
            },
          ],
        });
        for (var i = 0; i < _fakeReply.length; i += 6) {
          final end = i + 6 < _fakeReply.length ? i + 6 : _fakeReply.length;
          send({
            ...base,
            'object': 'chat.completion.chunk',
            'choices': [
              {
                'index': 0,
                'delta': {'content': _fakeReply.substring(i, end)},
                'finish_reason': null,
              },
            ],
          });
        }
        send({
          ...base,
          'object': 'chat.completion.chunk',
          'choices': [
            {
              'index': 0,
              'delta': <String, Object?>{},
              'finish_reason': 'stop',
            },
          ],
          'usage': {
            'prompt_tokens': 10,
            'completion_tokens': 20,
            'total_tokens': 30,
          },
        });
        req.response.write('data: [DONE]\n\n');
      } else {
        req.response.headers.contentType = ContentType(
          'application',
          'json',
          charset: 'utf-8',
        );
        req.response.write(
          jsonEncode({
            ...base,
            'object': 'chat.completion',
            'choices': [
              {
                'index': 0,
                'message': {'role': 'assistant', 'content': _fakeReply},
                'finish_reason': 'stop',
              },
            ],
            'usage': {
              'prompt_tokens': 10,
              'completion_tokens': 20,
              'total_tokens': 30,
            },
          }),
        );
      }
      await req.response.close();
    } catch (e) {
      // ignore: avoid_print
      print('fake upstream error: $e');
      try {
        await req.response.close();
      } catch (_) {}
    }
  });
  return server;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final dshDir = Platform.environment['L2A_DSH_DIR'] ?? '';

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      if (dshDir.isNotEmpty) 'lab.dsh.dir': dshDir,
      if (dshDir.isNotEmpty) 'lab.dsh.root': p.dirname(dshDir),
      'lab.visible': true,
      'lab.dsh.enabled': false,
      // CI runner 的系统语言是 en-US；应用内钉成简体中文，截图跟用户实际
      // 使用时的文案一致。
      'local2api.localeCode': 'zh-CN',
    });
    // integration_test 的宿主环境里 FLUTTER_TEST=true，DshService 会主动
    // 把系统 node 判成不可用；这个闸门就是给这种真跑 DSH 的测试开的。
    DshService.instance.debugForceNodeAvailable = true;
  });

  testWidgets('macOS: DSH 启动、打开、并完成一次任务', (tester) async {
    await app.main();
    await _pumpFor(tester, const Duration(seconds: 2));

    await DshService.instance.init();
    // ignore: avoid_print
    print(
      'DSH init: installed=${DshService.instance.installed} '
      'node=${DshService.instance.nodeAvailable} '
      'dir=${DshService.instance.installDir} '
      'home=${DshService.instance.dshHome}',
    );
    expect(
      DshService.instance.installed,
      isTrue,
      reason: 'CI 必须先把 L2A_DSH_DIR 指到已 npm install 的 DSH 目录',
    );

    // 假上游 + 本地 local2api 代理：DSH 的 provider 指向代理，代理再转发。
    final fake = await _startFakeUpstream();
    addTearDown(() => fake.close(force: true));
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final proxyPort = probe.port;
    await probe.close();
    final config = ProxyConfig(
      listenPort: proxyPort,
      listenHost: '127.0.0.1',
      upstreams: [
        Upstream(
          id: 'ci-fake',
          name: 'CI Fake',
          baseUrl: 'http://127.0.0.1:${fake.port}/v1',
          models: [ModelEntry(publicName: 'ci-model')],
        ),
      ],
      apiKeys: [ApiKeyEntry(id: 'ci-key', name: 'CI', key: 'sk-ci-test')],
    );
    final proxy = ProxyServer(configProvider: () => config);
    await proxy.start();
    expect(proxy.isRunning, isTrue, reason: '${proxy.lastError.value}');
    addTearDown(() => proxy.stop());

    await DshService.instance.setModels(['ci-model']);
    final applied = await DshService.instance.applyApiConfig(config);
    // ignore: avoid_print
    print(
      'DSH config applied=${applied.ok} err=${applied.error} '
      'path=${DshService.instance.configPath}',
    );
    if (File(DshService.instance.configPath).existsSync()) {
      // ignore: avoid_print
      print(await File(DshService.instance.configPath).readAsString());
    }

    await DshService.instance.start();
    await _pumpFor(tester, const Duration(seconds: 3));
    // ignore: avoid_print
    print(
      'DSH running=${DshService.instance.running} '
      'url=${DshService.instance.url}',
    );
    // ignore: avoid_print
    print('DSH logs:\n${DshService.instance.logs.join('\n')}');
    expect(
      DshService.instance.running,
      isTrue,
      reason: 'DSH 进程没有起来（看上面的日志）',
    );

    // 点开 DSH 设置页（Material 版；miuix 那套是同一份 service）。
    final settingsKey = GlobalKey();
    final browserKey = GlobalKey();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => RepaintBoundary(
            key: settingsKey,
            child: const DshPage(),
          ),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(seconds: 3));
    expect(find.text('DeepSeek Harness'), findsWidgets);
    await _capture(tester, '01-dsh-settings', settingsKey);

    // 用应用真实的内置浏览器页打开 DSH（BrowserPage → WKWebView）。
    final url = DshService.instance.openUrl;
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => RepaintBoundary(
            key: browserKey,
            child: BrowserPage(
              initialUrl: url,
              title: 'DeepSeek Harness',
            ),
          ),
        ),
      ),
    );
    await _pumpFor(tester, const Duration(seconds: 6));

    BrowserController? browser;
    for (var i = 0; i < 30; i++) {
      browser = BrowserPage.debugLastController;
      if (browser != null &&
          browser.isReady &&
          browser.mobileController != null) {
        break;
      }
      await _pumpFor(tester, const Duration(seconds: 1));
    }
    expect(browser, isNotNull, reason: 'BrowserPage 没有创建 controller');
    expect(browser!.initError, isNull, reason: browser.initError);
    final webview = browser.mobileController;
    expect(webview, isNotNull, reason: 'WKWebView 没有初始化');
    await _pumpFor(tester, const Duration(seconds: 6));

    // DSH 首次打开会盖一层「预览版说明」；点「继续 / Continue」。
    for (var i = 0; i < 30; i++) {
      try {
        final result = await webview!.runJavaScriptReturningResult('''
          (() => {
            const visible = (e) => e && e.offsetParent !== null;
            const labels = new Set(['继续', 'Continue', 'CONTINUE']);
            let hit = [...document.querySelectorAll('button')].find(
              (e) => visible(e) && labels.has(e.textContent.trim()),
            );
            if (!hit) {
              hit = [...document.querySelectorAll('*')].find(
                (e) => visible(e) &&
                       e.children.length === 0 &&
                       labels.has(e.textContent.trim()),
              );
            }
            if (!hit) return 'not-found';
            (hit.closest('button') || hit).click();
            return 'clicked';
          })()
        ''');
        // ignore: avoid_print
        print('DSH continue: $result');
        if ('$result'.contains('clicked')) break;
      } catch (e) {
        // ignore: avoid_print
        print('DSH continue attempt $i failed: $e');
      }
      await _pumpFor(tester, const Duration(seconds: 1));
    }
    await _pumpFor(tester, const Duration(seconds: 4));

    try {
      final body = await webview!.runJavaScriptReturningResult(
        'document.body.innerText',
      );
      // ignore: avoid_print
      print('DSH page text: $body');
    } catch (e) {
      // ignore: avoid_print
      print('DSH page text failed: $e');
    }
    await _capture(tester, '02-dsh-webui', browserKey);

    // 在 DSH 输入框里发一条任务，等假上游的流式回复出现在页面上。
    for (var i = 0; i < 20; i++) {
      try {
        final typed = await webview!.runJavaScriptReturningResult('''
          (() => {
            const input = document.querySelector('[contenteditable="true"]');
            if (!input) return 'no-input';
            input.focus();
            document.execCommand('insertText', false, '$_taskPrompt');
            return 'typed';
          })()
        ''');
        // ignore: avoid_print
        print('DSH type: $typed');
        if ('$typed'.contains('typed')) break;
      } catch (e) {
        // ignore: avoid_print
        print('DSH type attempt $i failed: $e');
      }
      await _pumpFor(tester, const Duration(seconds: 1));
    }
    await _pumpFor(tester, const Duration(seconds: 1));

    for (var i = 0; i < 20; i++) {
      try {
        final sent = await webview!.runJavaScriptReturningResult('''
          (() => {
            const buttons = [...document.querySelectorAll('button')];
            let send = buttons.find(
              (b) => /发送消息|Send message/i.test(
                b.getAttribute('aria-label') || '',
              ),
            );
            if (!send) {
              send = buttons.find(
                (b) => (b.className || '').includes('uV2eYG_primary'),
              );
            }
            if (!send) return 'no-send';
            if (send.disabled) return 'send-disabled';
            send.click();
            return 'sent';
          })()
        ''');
        // ignore: avoid_print
        print('DSH send: $sent');
        if ('$sent'.contains('sent')) break;
      } catch (e) {
        // ignore: avoid_print
        print('DSH send attempt $i failed: $e');
      }
      await _pumpFor(tester, const Duration(seconds: 1));
    }

    String pageText = '';
    for (var i = 0; i < 45; i++) {
      try {
        final body = await webview!.runJavaScriptReturningResult(
          'document.body.innerText',
        );
        pageText = '$body';
        if (pageText.contains('DSH 离线任务完成')) break;
      } catch (_) {}
      await _pumpFor(tester, const Duration(seconds: 1));
    }
    // ignore: avoid_print
    print('DSH task text: $pageText');
    expect(
      pageText,
      contains('DSH 离线任务完成'),
      reason: 'DSH 没有把假上游的回复渲染出来（看上面的 send/type 日志）',
    );
    await _capture(tester, '03-dsh-task', browserKey);

    // 直接探一次服务端口，确认不是只开了个空窗口。
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      await res.drain<void>();
      // ignore: avoid_print
      print('DSH HTTP ${res.statusCode} $url');
      expect(res.statusCode, lessThan(500));
    } finally {
      client.close(force: true);
    }

    await DshService.instance.stop();
  });
}
