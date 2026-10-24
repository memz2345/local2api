// integration_test/windows_zen_minimax_test.dart
//
// Windows 真网实测（GitHub Actions windows-latest）：
//   1. 应用启动（miuix 主题）；
//   2. 内置 OpenCode Zen 免费档案刷新实时模型清单；
//   3. 选中 minimax 免费车道并导入 DSH；
//   4. 起本机 Local2API 代理 + DSH，让 minimax 识别这台 Windows 的系统信息；
//   5. 每一步截图（原生整屏 + Flutter 图层）。
//
// 这条测试会真的请求 opencode.ai，失败也要留下截图，所以 workflow 里
// 是 continue-on-error；它同时是 `pwsh → bash` 改名回归的端到端验证：
// 如果响应侧没把 bash 还原成 pwsh，DSH 会报 unknown tool，页面等不到结果。
//
// 跑法（Windows 本机 / CI）：
//   L2A_DSH_DIR=<含 node_modules/@deepseek-ai/dsh 的目录> \
//   DSH_HOME=<临时 home> \
//   flutter test integration_test/windows_zen_minimax_test.dart -d windows

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
import 'package:local2api/models/builtin_profiles.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/browser_controller.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/lab/dsh_service.dart';
import 'package:local2api/services/profile_service.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/zen/zen_discovery.dart';
import 'package:local2api/ui/miuix/miuix_browser_page.dart';
import 'package:local2api/ui/miuix/miuix_dsh_page.dart';

const String _prompt =
    '请识别这台 Windows 的系统信息：Windows 版本、CPU 架构和物理内存大小。'
    '你可以运行 PowerShell 命令（例如 [System.Environment]::OSVersion、'
    r'$env:PROCESSOR_ARCHITECTURE、(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory'
    '）。请用中文给出结果。';

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

String get _shotDir =>
    Platform.environment['L2A_SHOT_DIR'] ?? 'build/windows_shots';

Future<void> _nativeShot(String name) async {
  final dir = _shotDir;
  await Directory(dir).create(recursive: true);
  final path = p.join(dir, '$name.png').replaceAll('\\', '/');
  final script = '''
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
    final result = await Process.run(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-Command', script],
    ).timeout(const Duration(seconds: 30));
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
    await File(
      p.join(dir, '$name.flutter.png'),
    ).writeAsBytes(data.buffer.asUint8List(), flush: true);
    // ignore: avoid_print
    print('SHOT flutter $name');
  } catch (e) {
    // ignore: avoid_print
    print('SHOT flutter $name failed: $e');
  }
}

Future<String> _js(BrowserController? controller, String script,
    {String label = 'js'}) async {
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
    final out = await _js(
      wv,
      r'''
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
      ''',
      label: 'preview',
    );
    if (out.contains('clicked')) return;
    await _pumpFor(tester, const Duration(seconds: 1));
  }
}

Future<void> _newSession(WidgetTester tester, BrowserController wv) async {
  await _js(
    wv,
    r'''
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
    ''',
    label: 'new-session',
  );
  await _pumpFor(tester, const Duration(seconds: 2));
}

Future<void> _enableFullAccess(WidgetTester tester, BrowserController wv) async {
  await _js(
    wv,
    r'''
    (() => {
      const b = [...document.querySelectorAll('button')].find(
        (x) => /访问模式|Access mode/i.test(x.getAttribute('aria-label') || ''),
      );
      if (!b) return 'no-access-button';
      b.click();
      return 'opened';
    })()
    ''',
    label: 'access-open',
  );
  await _pumpFor(tester, const Duration(seconds: 1));
  await _js(
    wv,
    r'''
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
    ''',
    label: 'access-full',
  );
  await _pumpFor(tester, const Duration(seconds: 1));
  await _js(
    wv,
    r'''
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
    ''',
    label: 'access-risk',
  );
  await _pumpFor(tester, const Duration(seconds: 1));
  await _js(
    wv,
    r'''
    (() => {
      const b = [...document.querySelectorAll('button')].find(
        (x) => !x.disabled &&
               /启用完全权限|Enable full/i.test(x.textContent || ''),
      );
      if (!b) return 'no-enable-button';
      b.click();
      return 'enabled';
    })()
    ''',
    label: 'access-enable',
  );
  await _pumpFor(tester, const Duration(seconds: 2));
}

Future<void> _sendPrompt(
  WidgetTester tester,
  BrowserController wv,
  String prompt,
) async {
  // DSH 0.2 的输入框是 Lexical。实测三条常规路全废（详见 smoke 测试同位置
  // 的注释）：execCommand 被 MutationObserver 回滚、合成 beforeinput 无效、
  // 按字符串 dispatchCommand 是 map-miss 空操作（这版 Lexical 的命令 key
  // 是冻结对象 {type: name}）。可靠做法：取 _commands 里的原始 key 派发。
  for (var i = 0; i < 20; i++) {
    final typed = await _js(
      wv,
      '''
      (() => {
        const visible = (e) => e && e.offsetParent !== null;
        const inputs = [...document.querySelectorAll('[data-lexical-editor="true"]'),
                        ...document.querySelectorAll('[contenteditable="true"]')]
          .filter(visible);
        if (!inputs.length) return 'no-input';
        const input = inputs[inputs.length - 1];
        const ed = input.__lexicalEditor;
        if (!ed || typeof ed.dispatchCommand !== 'function') {
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
      ''',
      label: 'type',
    );
    // dispatchCommand 的提交是异步的，等一拍再读回。
    await _pumpFor(tester, const Duration(milliseconds: 600));
    final check = await _js(
      wv,
      r'''
      (() => {
        const input = [...document.querySelectorAll('[data-lexical-editor="true"]'),
                       ...document.querySelectorAll('[contenteditable="true"]')]
          .filter((e) => e.offsetParent !== null).pop();
        if (!input) return 'no-input';
        const text = input.innerText || input.textContent || '';
        return 'typed=' + (text.trim() ? 'yes' : 'no') +
               ' text=' + JSON.stringify(text);
      })()
      ''',
      label: 'type-check',
    );
    if (check.contains('typed=yes')) break;
    if (typed.contains('no-input')) break;
    await _pumpFor(tester, const Duration(seconds: 1));
  }
  await _pumpFor(tester, const Duration(seconds: 1));
  for (var i = 0; i < 20; i++) {
    final sent = await _js(
      wv,
      r'''
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
      ''',
      label: 'send',
    );
    if (sent.contains('sent')) return;
    if (sent.contains('enter-dispatched')) {
      await _pumpFor(tester, const Duration(seconds: 2));
      final check = await _js(
        wv,
        r'''
        (() => {
          const visible = (e) => e && e.offsetParent !== null;
          const buttons = [...document.querySelectorAll('button')].filter(visible);
          const send = buttons.find(
            (b) => /发送消息|Send message/i.test(b.getAttribute('aria-label') || ''),
          );
          return send ? (send.disabled ? 'still-disabled' : 'enabled') : 'gone';
        })()
        ''',
        label: 'send-check',
      );
      if (check.contains('enabled') || check.contains('gone')) return;
    }
    await _pumpFor(tester, const Duration(seconds: 1));
  }
}

Future<String> _powershell(String script) async {
  try {
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      script,
    ]);
    return '${r.stdout}${r.stderr}'.trim();
  } catch (e) {
    return 'error: $e';
  }
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

  testWidgets('Windows miuix: 刷新 Zen 免费模型，用 minimax 识别系统信息',
      (tester) async {
    await app.main();
    await _pumpFor(tester, const Duration(seconds: 2));
    await _nativeShot('00-miuix-home');

    final osVersion = await _powershell(
      '[System.Environment]::OSVersion.VersionString',
    );
    final arch = await _powershell(r'$env:PROCESSOR_ARCHITECTURE');
    final memory = await _powershell(
      '(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory',
    );
    // ignore: avoid_print
    print('HOST version=$osVersion arch=$arch memory=$memory');

    final store = ConfigStore();
    await store.load();
    final profiles = ProfileStore();
    await profiles.load();
    // ignore: avoid_print
    print('profiles=${profiles.profiles.map((e) => e.id).toList()} '
        'upstreams=${store.config.upstreams.map((e) => e.id).toList()}');

    if (ProfileService.upstreamOf(store.config, kZenUpstreamId) == null) {
      await ProfileService.ensureBuiltinDefaultUpstream(
        store: profiles,
        config: store.config,
      );
      store.update(store.config);
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (store.config.apiKeys.isEmpty) {
      store.config.apiKeys.add(
        ApiKeyEntry(id: 'ci-live', name: 'CI', key: 'sk-ci-zen-live'),
      );
      store.update(store.config);
      await Future<void>.delayed(const Duration(seconds: 1));
    }

    final refreshed = await ProfileService.refreshModelLists(
      store: profiles,
      config: store.config,
    );
    // ignore: avoid_print
    print('refresh error=${zenDiscovery.lastError} at=${zenDiscovery.refreshedAt}');
    store.update(store.config);
    await Future<void>.delayed(const Duration(seconds: 1));
    final zen = ProfileService.upstreamOf(store.config, kZenUpstreamId);
    final lanes = zen?.models.map((m) => m.target).toList() ?? const <String>[];
    // ignore: avoid_print
    print('refreshed=$refreshed zen lanes=$lanes');
    final minimaxLanes = [
      for (final lane in lanes)
        if (lane.toLowerCase().contains('minimax')) lane,
    ];
    // ignore: avoid_print
    print('minimax lanes=$minimaxLanes');
    expect(minimaxLanes, isNotEmpty,
        reason: '刷新后没有 minimax 免费车道（看上面的 zen lanes）');
    final lane = minimaxLanes.first;

    await DshService.instance.init();
    await DshService.instance.setGroup(kZenProfileId);
    await DshService.instance.setModels([lane]);
    final applied = await DshService.instance.applyApiConfig(store.config);
    // ignore: avoid_print
    print('DSH apply=${applied.ok} err=${applied.error} lane=$lane');

    final controller = ServerController(store);
    await controller.start();
    addTearDown(() => controller.stop());
    // ignore: avoid_print
    print(
      'proxy running=${controller.isRunning} '
      'port=${store.config.listenPort} error=${controller.server.lastError.value}',
    );
    expect(controller.isRunning, isTrue);
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
    expect(DshService.instance.running, isTrue);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    final dshKey = GlobalKey();
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => RepaintBoundary(
            key: dshKey,
            child: MiuixDshPage(controller: controller),
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
    await _pumpFor(tester, const Duration(seconds: 8));

    await _dismissPreview(tester, wv);
    await _newSession(tester, wv);
    await _enableFullAccess(tester, wv);
    await _pumpFor(tester, const Duration(seconds: 2));
    await _capture(tester, '02-miuix-zen-webui', browserKey);

    await _sendPrompt(tester, wv, _prompt);
    await _pumpFor(tester, const Duration(seconds: 3));

    String pageText = '';
    var lastLog = DateTime.now();
    for (var i = 0; i < 180; i++) {
      // 3 分钟，每 2 秒看一次；遇到权限弹窗顺手点允许。
      await _js(
        wv,
        r'''
        (() => {
          const b = [...document.querySelectorAll('button')].find(
            (x) => !x.disabled &&
                   /^(允许|允许一次|总是允许|Allow|Allow once|Always allow)$/i
                     .test((x.textContent || '').trim()),
          );
          if (b) { b.click(); return 'allowed'; }
          return 'no-allow';
        })()
        ''',
        label: 'allow',
      );
      final text = await _js(wv, 'document.body.innerText', label: 'page');
      if (text.isNotEmpty) pageText = text;
      final done = pageText.contains('Completed') ||
          pageText.contains('已完成') ||
          pageText.contains('Failed') ||
          pageText.contains('失败');
      final hasRealInfo = (arch.isNotEmpty && pageText.contains(arch)) ||
          pageText.contains('Windows') ||
          pageText.contains('AMD64') ||
          pageText.contains('x86_64');
      if (done && hasRealInfo) break;
      if (DateTime.now().difference(lastLog) > const Duration(seconds: 20)) {
        lastLog = DateTime.now();
        // ignore: avoid_print
        print(
          'WAIT i=$i done=$done real=$hasRealInfo '
          'tail=${pageText.length > 600 ? pageText.substring(pageText.length - 600) : pageText}',
        );
      }
      await _pumpFor(tester, const Duration(seconds: 2));
    }
    // ignore: avoid_print
    print('FINAL PAGE:\n$pageText');
    await _capture(tester, '03-miuix-system-info', browserKey);

    // 工具名还原回归：页面里不该出现 unknown tool。
    expect(
      pageText.toLowerCase(),
      isNot(contains('unknown tool')),
      reason: 'bash/pwsh 改名没有还原，DSH 收到 unknown tool',
    );
    final expected = <String>[
      if (osVersion.isNotEmpty) osVersion.split(' ').first,
      if (arch.isNotEmpty) arch,
      'Windows',
      'AMD64',
      'x86_64',
    ].where((s) => s.isNotEmpty).map(RegExp.escape).join('|');
    expect(
      pageText,
      matches(RegExp(expected)),
      reason: '模型没有输出可识别的 Windows 系统信息（看上面的 FINAL PAGE）',
    );
  }, timeout: const Timeout(Duration(minutes: 15)));
}
