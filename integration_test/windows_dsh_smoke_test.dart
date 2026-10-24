// integration_test/windows_dsh_smoke_test.dart
//
// Windows 端到端冒烟（GitHub Actions windows-latest）：
//   1. 用 workflow 预先 npm 装好的 DSH（L2A_DSH_DIR）启动；
//   2. 安装并启用两个 dsh 插件：编辑消息 / 电脑操作模式；
//   3. 应用自己写 cordis.patch.yml，把本地代理的 ci-model 挂给 DSH；
//   4. 在内置浏览器（BrowserPage → WebView2）里打开 DSH，发任务；
//   5. 假上游流式回复，确认 UI 走到回复；
//   6. 验证编辑消息按钮真的出现在用户消息旁；
//   7. 验证 Windows Toast 的静默更新（Update）真的被用上。
//
// 截图：原生整屏（PowerShell CopyFromScreen）+ Flutter 图层各一张。
//
// 跑法（Windows 本机 / CI）：
//   L2A_DSH_DIR=<含 node_modules/@deepseek-ai/dsh 的目录> \
//   DSH_HOME=<临时 home> \
//   flutter test integration_test/windows_dsh_smoke_test.dart -d windows

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
import 'package:local2api/services/lab/dsh_plugins.dart';
import 'package:local2api/services/lab/dsh_service.dart';
import 'package:local2api/services/lab/dsh_question.dart';
import 'package:local2api/services/lab/dsh_session_watcher.dart';
import 'package:local2api/services/lab/dsh_task_center.dart';
import 'package:local2api/services/lab/dsh_windows_toast.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:local2api/ui/miuix/miuix_browser_page.dart';
import 'package:local2api/ui/miuix/miuix_dsh_page.dart';

const String _taskPrompt = '帮我看一下当前工作区，然后告诉我结果';
const String _askPrompt = 'NOTIFY_ASK 请向我提一个问题，然后停下来等我回答，不要自己回答。';
const String _fakeReply = 'Windows DSH 离线任务完成：本地假上游回复正常。';

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

String get _shotDir =>
    Platform.environment['L2A_SHOT_DIR'] ?? 'build/windows_shots';

/// 原生整屏截图：WebView2 是原生子窗口，Flutter 图层截不到它。
Future<void> _nativeShot(String name) async {
  final dir = _shotDir;
  await Directory(dir).create(recursive: true);
  final path = p.join(dir, '$name.png').replaceAll('\\', '/');
  final script =
      '''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
\$bmp = New-Object System.Drawing.Bitmap \$b.Width, \$b.Height
\$g = [System.Drawing.Graphics]::FromImage(\$bmp)
\$g.CopyFromScreen(\$b.Location, [System.Drawing.Point]::Empty, \$b.Size)
\$bmp.Save('$path', [System.Drawing.Imaging.ImageFormat]::Png)
\$g.Dispose()
\$bmp.Dispose()
''';
  try {
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      script,
    ]).timeout(const Duration(seconds: 30));
    // ignore: avoid_print
    print('SHOT native $name exit=${result.exitCode} ${result.stderr}');
  } catch (e) {
    // ignore: avoid_print
    print('SHOT native $name failed: $e');
  }
}

Future<void> _capture(
  WidgetTester tester,
  String name,
  GlobalKey boundaryKey,
) async {
  await _nativeShot(name);
  final dir = _shotDir;
  await Directory(dir).create(recursive: true);
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

Future<String> _js(
  BrowserController? controller,
  String script, {
  String label = 'js',
}) async {
  final webview = controller?.windowsController;
  if (webview == null) return '';
  try {
    final result = await webview.executeScript(script);
    final text = '$result';
    // ignore: avoid_print
    print('JS $label: ${text.length > 400 ? text.substring(0, 400) : text}');
    return text;
  } catch (e) {
    // ignore: avoid_print
    print('JS $label failed: $e');
    return '';
  }
}

Future<BrowserController> _waitForWebview(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    final c = MiuixBrowserPage.debugLastController;
    if (c != null && c.isReady && c.windowsController != null) return c;
    await _pumpFor(tester, const Duration(seconds: 1));
  }
  throw StateError('WebView2 没有初始化');
}

Future<void> _dismissPreview(WidgetTester tester, BrowserController wv) async {
  for (var i = 0; i < 20; i++) {
    final out = await _js(wv, r'''
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
      ''', label: 'preview');
    if (out.contains('clicked')) return;
    await _pumpFor(tester, const Duration(seconds: 1));
  }
}

Future<void> _newSession(WidgetTester tester, BrowserController wv) async {
  await _js(wv, r'''
    (() => {
      const b = [...document.querySelectorAll('button')].find((x) => {
        const text = (x.textContent || '').trim();
        const aria = x.getAttribute('aria-label') || '';
        return /^(New Session|New session|新建会话)$/i.test(text) ||
               /新建会话|New session/i.test(aria);
      });
      if (!b) return 'no-new-session';
      b.click();
      return 'new-session-clicked';
    })()
    ''', label: 'new-session');
  await _pumpFor(tester, const Duration(seconds: 2));
}

Future<void> _enableFullAccess(
  WidgetTester tester,
  BrowserController wv,
) async {
  await _js(wv, r'''
    (() => {
      const b = [...document.querySelectorAll('button')].find(
        (x) => /访问模式|Access mode/i.test(x.getAttribute('aria-label') || ''),
      );
      if (!b) return 'no-access-button';
      b.click();
      return 'opened';
    })()
    ''', label: 'access-open');
  await _pumpFor(tester, const Duration(seconds: 1));
  await _js(wv, r'''
    (() => {
      const hit = [...document.querySelectorAll('*')].find(
        (e) => e.offsetParent !== null &&
               e.children.length === 0 &&
               /^(完全权限|Full (access|permission))$/i.test(e.textContent.trim()),
      );
      if (!hit) return 'no-full-option';
      (hit.closest('[role="menuitem"]') || hit).click();
      return 'full-option-clicked';
    })()
    ''', label: 'access-full');
  await _pumpFor(tester, const Duration(seconds: 1));
  await _js(wv, r'''
    (() => {
      const cb = document.querySelector('input[type="checkbox"]') ||
                 document.querySelector('[role="checkbox"]');
      if (cb) { cb.click(); return 'checkbox-clicked'; }
      const label = [...document.querySelectorAll('*')].find(
        (e) => e.offsetParent !== null &&
               e.children.length === 0 &&
               /我已了解风险|I understand/i.test(e.textContent || ''),
      );
      if (label) { label.click(); return 'label-clicked'; }
      return 'no-checkbox';
    })()
    ''', label: 'access-risk');
  await _pumpFor(tester, const Duration(seconds: 1));
  await _js(wv, r'''
    (() => {
      const b = [...document.querySelectorAll('button')].find(
        (x) => !x.disabled &&
               /启用完全权限|Enable full/i.test(x.textContent || ''),
      );
      if (!b) return 'no-enable-button';
      b.click();
      return 'enabled';
    })()
    ''', label: 'access-enable');
  await _pumpFor(tester, const Duration(seconds: 2));
}

Future<void> _sendPrompt(
  WidgetTester tester,
  BrowserController wv,
  String prompt,
) async {
  // DSH 0.2 的输入框是 Lexical（contenteditable + data-lexical-editor）。
  // 实测（headless Chrome + DSH 0.2.1）三条常规路全废：
  //   · execCommand('insertText') 会被 Lexical 的 MutationObserver 回滚；
  //   · 合成 beforeinput 事件无效；
  //   · dispatchCommand('insertText', ...) 是空操作 —— 这版 Lexical 的
  //     createCommand 返回冻结对象 {type: name} 而非字符串，按字符串派发
  //     在 _commands Map 里查不中（注册表里根本没有 INSERT_TEXT_COMMAND，
  //     只有 CONTROLLED_TEXT_INSERTION_COMMAND）。
  // 可靠做法：从 editor._commands 取出命令的原始 key 对象来派发；
  // 旧版 Lexical 的命令是字符串，保留兜底。
  for (var i = 0; i < 20; i++) {
    final typed = await _js(wv, '''
      (() => {
        const visible = (e) => e && e.offsetParent !== null;
        const inputs = [...document.querySelectorAll('[data-lexical-editor="true"]'),
                        ...document.querySelectorAll('[contenteditable="true"]')]
          .filter(visible);
        if (!inputs.length) return 'no-input';
        const input = inputs[inputs.length - 1];
        const ed = input.__lexicalEditor;
        if (!ed || typeof ed.dispatchCommand !== 'function') {
          // 非 Lexical 的普通 contenteditable：老办法还能用。
          input.focus();
          const exec = document.execCommand('insertText', false, ${jsonEncode(prompt)});
          const text = input.innerText || input.textContent || '';
          return 'typed=' + (text.trim() ? 'yes' : 'no') + ' exec=' + exec;
        }
        let key = null;
        for (const name of ['CONTROLLED_TEXT_INSERTION_COMMAND', 'INSERT_TEXT_COMMAND']) {
          key = [...ed._commands.keys()].find(
            (k) => (typeof k === 'string' ? k : (k && k.type)) === name,
          );
          if (key) break;
        }
        if (!key) key = 'insertText';
        input.focus();
        const sel = window.getSelection();
        const range = document.createRange();
        range.selectNodeContents(input);
        range.collapse(true);
        sel.removeAllRanges();
        sel.addRange(range);
        try {
          ed.dispatchCommand(key, ${jsonEncode(prompt)});
        } catch (e) {
          return 'dispatch-error:' + e.message;
        }
        return 'dispatched key=' + (typeof key === 'string' ? key : key.type);
      })()
      ''', label: 'type');
    // dispatchCommand 的提交是异步的，等一拍再读回。
    await _pumpFor(tester, const Duration(milliseconds: 600));
    final check = await _js(wv, r'''
      (() => {
        const input = [...document.querySelectorAll('[data-lexical-editor="true"]'),
                       ...document.querySelectorAll('[contenteditable="true"]')]
          .filter((e) => e.offsetParent !== null).pop();
        if (!input) return 'no-input';
        const text = input.innerText || input.textContent || '';
        return 'typed=' + (text.trim() ? 'yes' : 'no') +
               ' text=' + JSON.stringify(text);
      })()
      ''', label: 'type-check');
    if (check.contains('typed=yes')) break;
    if (typed.contains('no-input')) break;
    await _pumpFor(tester, const Duration(seconds: 1));
  }
  await _pumpFor(tester, const Duration(seconds: 1));
  for (var i = 0; i < 20; i++) {
    final sent = await _js(wv, r'''
      (() => {
        const visible = (e) => e && e.offsetParent !== null;
        const buttons = [...document.querySelectorAll('button')].filter(visible);
        let send = buttons.find(
          (b) => /发送消息|Send message/i.test(b.getAttribute('aria-label') || ''),
        );
        if (!send) {
          send = buttons.find(
            (b) => /^(发送|Send)$/i.test((b.textContent || '').trim()),
          );
        }
        if (!send) return 'no-send';
        if (send.disabled) {
          const inputs = [...document.querySelectorAll('[contenteditable="true"]')]
            .filter(visible);
          const input = inputs[inputs.length - 1];
          if (input) {
            input.dispatchEvent(new KeyboardEvent('keydown', {
              key: 'Enter', code: 'Enter', keyCode: 13, which: 13,
              bubbles: true, cancelable: true,
            }));
            return 'enter-dispatched';
          }
          return 'send-disabled';
        }
        send.click();
        return 'sent';
      })()
      ''', label: 'send');
    if (sent.contains('sent')) return;
    if (sent.contains('enter-dispatched')) {
      await _pumpFor(tester, const Duration(seconds: 2));
      final check = await _js(wv, r'''
        (() => {
          const visible = (e) => e && e.offsetParent !== null;
          const buttons = [...document.querySelectorAll('button')].filter(visible);
          const send = buttons.find(
            (b) => /发送消息|Send message/i.test(b.getAttribute('aria-label') || ''),
          );
          return send ? (send.disabled ? 'still-disabled' : 'enabled') : 'gone';
        })()
        ''', label: 'send-check');
      if (check.contains('enabled') || check.contains('gone')) return;
    }
    await _pumpFor(tester, const Duration(seconds: 1));
  }
}

Future<HttpServer> _startFakeUpstream() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    try {
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
              {'id': 'ci-model', 'object': 'model', 'created': 0},
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
      final stream = body['stream'] == true;
      final model = '${body['model'] ?? 'ci-model'}';
      final base = <String, Object?>{
        'id': 'chatcmpl-windows-ci',
        'created': 0,
        'model': model,
      };
      final tools = body['tools'];
      final hasAskTool =
          tools is List &&
          tools.any((t) {
            final fn = t is Map ? t['function'] : null;
            return fn is Map && fn['name'] == 'ask_user_question';
          });
      final answered = raw.contains('L2A-REPLY-OK');
      final wantAsk = raw.contains('NOTIFY_ASK') && hasAskTool && !answered;
      final replyText = answered ? '收到回答：L2A-REPLY-OK' : _fakeReply;
      final askArguments = jsonEncode(<String, Object?>{
        'questions': [
          <String, Object?>{
            'id': 'q1',
            'header': '代号',
            'question': '你的代号是什么？',
            'options': [
              <String, Object?>{'label': '老铁'},
              <String, Object?>{'label': '大佬'},
            ],
            'multiSelect': false,
          },
        ],
      });
      if (wantAsk) {
        if (!stream) {
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
                  'message': {
                    'role': 'assistant',
                    'content': null,
                    'tool_calls': [
                      {
                        'id': 'call_ci_ask',
                        'type': 'function',
                        'function': {
                          'name': 'ask_user_question',
                          'arguments': askArguments,
                        },
                      },
                    ],
                  },
                  'finish_reason': 'tool_calls',
                },
              ],
              'usage': {
                'prompt_tokens': 10,
                'completion_tokens': 20,
                'total_tokens': 30,
              },
            }),
          );
          await req.response.close();
          return;
        }
        req.response.statusCode = 200;
        req.response.headers.set(
          'content-type',
          'text/event-stream; charset=utf-8',
        );
        req.response.headers.set('cache-control', 'no-cache');
        void sendAsk(Map<String, Object?> chunk) {
          req.response.write('data: ${jsonEncode(chunk)}\n\n');
        }

        sendAsk({
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
        sendAsk({
          ...base,
          'object': 'chat.completion.chunk',
          'choices': [
            {
              'index': 0,
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'call_ci_ask',
                    'type': 'function',
                    'function': {
                      'name': 'ask_user_question',
                      'arguments': askArguments,
                    },
                  },
                ],
              },
              'finish_reason': null,
            },
          ],
        });
        sendAsk({
          ...base,
          'object': 'chat.completion.chunk',
          'choices': [
            {
              'index': 0,
              'delta': <String, Object?>{},
              'finish_reason': 'tool_calls',
            },
          ],
          'usage': {
            'prompt_tokens': 10,
            'completion_tokens': 20,
            'total_tokens': 30,
          },
        });
        req.response.write('data: [DONE]\n\n');
        await req.response.close();
        return;
      }
      if (!stream) {
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
                'message': {'role': 'assistant', 'content': replyText},
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
        await req.response.close();
        return;
      }
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
      for (var i = 0; i < replyText.length; i += 6) {
        final end = i + 6 < replyText.length ? i + 6 : replyText.length;
        send({
          ...base,
          'object': 'chat.completion.chunk',
          'choices': [
            {
              'index': 0,
              'delta': {'content': replyText.substring(i, end)},
              'finish_reason': null,
            },
          ],
        });
      }
      send({
        ...base,
        'object': 'chat.completion.chunk',
        'choices': [
          {'index': 0, 'delta': <String, Object?>{}, 'finish_reason': 'stop'},
        ],
        'usage': {
          'prompt_tokens': 10,
          'completion_tokens': 20,
          'total_tokens': 30,
        },
      });
      req.response.write('data: [DONE]\n\n');
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
      'local2api.localeCode': 'zh-CN',
      'local2api.uiStyle': 'miuix',
    });
    DshService.instance.debugForceNodeAvailable = true;
  });

  testWidgets(
    'Windows: DSH 插件、Toast 静默更新与一次离线任务',
    (tester) async {
      await app.main();
      await _pumpFor(tester, const Duration(seconds: 2));

      await DshService.instance.init();
      // ignore: avoid_print
      print(
        'DSH init: installed=${DshService.instance.installed} '
        'node=${DshService.instance.nodeAvailable} '
        'dir=${DshService.instance.installDir} home=${DshService.instance.dshHome}',
      );
      expect(
        DshService.instance.installed,
        isTrue,
        reason: 'CI 必须先把 L2A_DSH_DIR 指到已 npm install 的 DSH 目录',
      );

      // 先单独验证 Toast：第一次 Show 之后，两次 silent 更新必须走 Update。
      final toast = DshWindowsToast.instance;
      await toast.init();
      final firstShown = await toast.showProgress(
        tag: 'l2a-ci-toast',
        title: 'Toast 更新测试',
        body: '第一次',
        progress: 0.1,
        silent: false,
      );
      // ignore: avoid_print
      print('toast firstShown=$firstShown available=${toast.available}');
      if (firstShown) {
        final before = await toast.stats();
        await toast.showProgress(
          tag: 'l2a-ci-toast',
          title: 'Toast 更新测试',
          body: '第二次',
          progress: 0.4,
          silent: true,
        );
        await toast.showProgress(
          tag: 'l2a-ci-toast',
          title: 'Toast 更新测试',
          body: '第三次',
          progress: 0.7,
          silent: true,
        );
        final after = await toast.stats();
        // ignore: avoid_print
        print('toast stats before=$before after=$after');
        expect(
          (after['update'] ?? 0) - (before['update'] ?? 0),
          greaterThanOrEqualTo(2),
          reason: 'silent 更新没有走 ToastNotifier.Update',
        );
        expect(
          (after['show'] ?? 0) - (before['show'] ?? 0),
          0,
          reason: 'silent 更新不应该重新 Show（会弹横幅）',
        );
        await toast.cancel(tag: 'l2a-ci-toast');
      }

      // 插件：编辑消息 + 电脑操作模式（Windows）。安装失败也继续，后面用
      // 页面上的按钮与配置做断言，并留下日志。
      final plugins = DshPluginsService.instance;
      await plugins.init(DshService.instance);
      final messageEdit = await plugins.setEnabled(
        DshPluginId.messageEdit,
        true,
      );
      final computerUse = await plugins.setEnabled(
        DshPluginId.computerUse,
        true,
      );
      // ignore: avoid_print
      print(
        'plugins messageEdit=$messageEdit '
        'state=${plugins.stateOf(DshPluginId.messageEdit).error} '
        'computerUse=$computerUse '
        'state=${plugins.stateOf(DshPluginId.computerUse).error}',
      );

      // 假上游 + 本地 local2api 代理。
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
      print('DSH config applied=${applied.ok} err=${applied.error}');
      expect(applied.ok, isTrue);

      await DshService.instance.start();
      await _pumpFor(tester, const Duration(seconds: 3));
      // ignore: avoid_print
      print(
        'DSH running=${DshService.instance.running} '
        'url=${DshService.instance.url}',
      );
      // ignore: avoid_print
      print('DSH logs:\n${DshService.instance.logs.join('\n')}');
      expect(DshService.instance.running, isTrue, reason: 'DSH 进程没有起来（看上面的日志）');

      // 配置层里必须能看到两个插件 bundle。
      final dump = await Process.run(
        'node',
        [
          '--expose-internals',
          DshService.instance.binPath,
          '--profile',
          'web',
          '--dump-config',
        ],
        workingDirectory: DshService.instance.installDir,
        environment: await DshService.instance.buildProcessEnv(),
        runInShell: true,
      ).timeout(const Duration(seconds: 60));
      final dumpText = '${dump.stdout}\n${dump.stderr}';
      // ignore: avoid_print
      print(
        'DSH dump exit=${dump.exitCode} hasMessageEdit=${dumpText.contains('message-edit')} '
        'hasComputerUse=${dumpText.contains('preset-computer')}',
      );
      if (dump.exitCode == 0) {
        expect(dumpText, contains('message-edit'));
        expect(dumpText, contains('preset-computer'));
      }

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      final dshKey = GlobalKey();
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => RepaintBoundary(
              key: dshKey,
              child: MiuixDshPage(controller: null),
            ),
          ),
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 3));
      await _capture(tester, '01-miuix-dsh', dshKey);

      final browserKey = GlobalKey();
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => RepaintBoundary(
              key: browserKey,
              child: MiuixBrowserPage(
                initialUrl: DshService.instance.openUrl,
                title: 'DeepSeek Harness',
              ),
            ),
          ),
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 6));
      final wv = await _waitForWebview(tester);
      await _pumpFor(tester, const Duration(seconds: 6));

      await _dismissPreview(tester, wv);
      await _newSession(tester, wv);
      await _enableFullAccess(tester, wv);
      await _pumpFor(tester, const Duration(seconds: 2));
      await _capture(tester, '02-miuix-dsh-webui', browserKey);

      await _sendPrompt(tester, wv, _taskPrompt);

      String pageText = '';
      for (var i = 0; i < 60; i++) {
        final text = await _js(wv, 'document.body.innerText', label: 'page');
        if (text.isNotEmpty) pageText = text;
        if (pageText.contains('离线任务完成')) break;
        await _pumpFor(tester, const Duration(seconds: 1));
      }
      // ignore: avoid_print
      print('FINAL PAGE:\n$pageText');
      expect(
        pageText,
        contains('离线任务完成'),
        reason: 'DSH 没有把假上游的回复渲染出来（看上面的 send/type 日志）',
      );

      // 编辑消息插件：用户消息旁必须出现铅笔按钮。
      final editButton = await _js(
        wv,
        'document.querySelector(\'[data-testid="dsh-message-edit-trigger"]\') '
        '? "found" : "missing"',
        label: 'message-edit',
      );
      expect(
        editButton,
        contains('found'),
        reason: 'dsh-message-edit 没有加载（按钮不存在）',
      );
      await _capture(tester, '03-miuix-dsh-task', browserKey);

      // 让 session watcher 把最后一轮事件推完，再读 Toast 计数。
      await _pumpFor(tester, const Duration(seconds: 4));
      // ignore: avoid_print
      print('toast stats final=${await toast.stats()}');

      // ---- 通知节流 + 通知输入框直接回答 ask_user_question ----
      for (var i = 0; i < 30; i++) {
        if (!DshTaskCenter.instance.hasTask) break;
        await _pumpFor(tester, const Duration(seconds: 1));
      }
      final statsBefore = await toast.stats();
      // ignore: avoid_print
      print('NOTIFY stats before=$statsBefore');

      await _newSession(tester, wv);
      await _enableFullAccess(tester, wv);
      await _sendPrompt(tester, wv, _askPrompt);
      await _pumpFor(tester, const Duration(seconds: 2));

      var firstAlerted = false;
      for (var i = 0; i < 40; i++) {
        if (DshTaskCenter.instance.hasTask) {
          firstAlerted = true;
          break;
        }
        await _pumpFor(tester, const Duration(milliseconds: 500));
      }
      await _pumpFor(tester, const Duration(seconds: 1));
      final statsStart = await toast.stats();
      // ignore: avoid_print
      print(
        'NOTIFY start hasTask=$firstAlerted stats=$statsStart '
        'waiting=${DshTaskCenter.instance.waitingForReply}',
      );
      expect(firstAlerted, isTrue, reason: 'web 会话开跑后没有常驻通知');
      if (!DshTaskCenter.instance.waitingForReply) {
        expect(
          statsStart['show']! - statsBefore['show']!,
          1,
          reason: '第一次思考应只弹一次（实际 $statsStart）',
        );
        expect(
          statsStart['update']! - statsBefore['update']!,
          0,
          reason: '思考/工具调用中途不应更新通知（实际 $statsStart）',
        );
      }

      DshQuestion? question;
      for (var i = 0; i < 60; i++) {
        final q = DshSessionWatcher.instance.state?.question;
        if (q != null && q.text.isNotEmpty) {
          question = q;
          break;
        }
        await _pumpFor(tester, const Duration(seconds: 1));
      }
      // ignore: avoid_print
      print(
        'NOTIFY question=$question '
        'waiting=${DshTaskCenter.instance.waitingForReply}',
      );
      expect(
        question,
        isNotNull,
        reason: '假上游的 ask_user_question 没有出现在 watcher',
      );
      expect(question!.answerable, isTrue, reason: '问题没有 callId，通知里回复不了');
      expect(
        DshTaskCenter.instance.waitingForReply,
        isTrue,
        reason: '通知没有进入等待回复状态',
      );
      final statsAsk = await toast.stats();
      // ignore: avoid_print
      print('NOTIFY ask stats=$statsAsk');
      await _capture(tester, '04-notify-ask', browserKey);

      final submitted = DshTaskCenter.instance.debugSubmitReply('L2A-REPLY-OK');
      expect(submitted, isTrue, reason: '模拟通知输入失败');

      var answered = false;
      var notifyPage = '';
      for (var i = 0; i < 60; i++) {
        final text = await _js(wv, 'document.body.innerText', label: 'page');
        if (text.isNotEmpty) notifyPage = text;
        if (notifyPage.contains('收到回答') ||
            notifyPage.contains('L2A-REPLY-OK')) {
          answered = true;
          break;
        }
        await _pumpFor(tester, const Duration(seconds: 1));
      }
      for (var i = 0; i < 30; i++) {
        if (DshTaskCenter.instance.outcome == DshTaskOutcome.succeeded) break;
        await _pumpFor(tester, const Duration(seconds: 1));
      }
      final statsDone = await toast.stats();
      // ignore: avoid_print
      print(
        'NOTIFY done stats=$statsDone answered=$answered '
        'outcome=${DshTaskCenter.instance.outcome} '
        'tail=${notifyPage.length > 800 ? notifyPage.substring(notifyPage.length - 800) : notifyPage}',
      );
      await _capture(tester, '05-notify-done', browserKey);
      expect(
        answered,
        isTrue,
        reason: '通知里的回答没有回到 dsh 页面（看 dsh-answer/dsh-rpc 日志）',
      );
      expect(
        statsDone['show']! - statsBefore['show']!,
        inInclusiveRange(2, 3),
        reason: '整轮只该有 第一次思考 + (提问) + 结果 这几条横幅（实际 $statsDone）',
      );
      expect(
        statsDone['update']! - statsBefore['update']!,
        0,
        reason: '中途不该有静默更新（实际 $statsDone）',
      );
      expect(DshTaskCenter.instance.outcome, DshTaskOutcome.succeeded);

      // 直接探一次服务端口，确认不是只开了个空窗口。
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      try {
        final req = await client.getUrl(Uri.parse(DshService.instance.url));
        final res = await req.close();
        await res.drain<void>();
        // ignore: avoid_print
        print('DSH HTTP ${res.statusCode} ${DshService.instance.url}');
        expect(res.statusCode, lessThan(500));
      } finally {
        client.close(force: true);
      }

      await DshService.instance.stop();
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
