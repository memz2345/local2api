// integration_test/windows_computer_use_test.dart
//
// Windows 真网实测：computer use（GitHub Actions windows-2022）：
//   1. 一键装并启用 `dsh-computer-use-mode` 插件（电脑操作模式）；
//   2. 刷新 Zen 免费车道，优先挑带视觉的车道（*-vl-*），否则退回 minimax；
//   3. 起本地代理 + DSH，web UI 里切到「电脑操作模式」；
//   4. 让模型用 `computer` 工具操作真实 GUI：启动记事本 → 聚焦 → 打字 →
//      截图 → 把截图里的字复述出来（闭环：键盘输入 + 截图读取都验到）；
//   5. 每一步截图（原生整屏 + Flutter 图层）。
//
// 会真的请求 opencode.ai、真的动鼠标键盘，所以 workflow 里是
// continue-on-error。
//
// 跑法（Windows 本机 / CI）：
//   L2A_DSH_DIR=<含 node_modules/@deepseek-ai/dsh 的目录> \
//   L2A_SHOT_DIR=<截图目录> \
//   DSH_HOME=<临时 home> DSH_AGENTS_HOME=<临时 agents home> \
//   flutter test integration_test/windows_computer_use_test.dart -d windows

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
import 'package:local2api/services/lab/dsh_plugins.dart';
import 'package:local2api/services/lab/dsh_service.dart';
import 'package:local2api/services/profile_service.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/zen/zen_discovery.dart';
import 'package:local2api/ui/miuix/miuix_browser_page.dart';
import 'package:local2api/ui/miuix/miuix_dsh_page.dart';
import 'package:local2api/ui/miuix/miuix_profiles_page.dart';

// 让模型打进记事本、再另存成文件的暗号。最终断言看的是**磁盘上的文件**，
// 不是页面文字 —— 页面里本来就有这段 prompt（含 "computer"、含暗号），
// 拿页面文字当断言等于自己证明自己，什么都没验到。
const String _secret = 'L2A-CU-A7F3K9';

String _targetFile() =>
    p.join(Directory.systemTemp.path, 'l2a-computer-use.txt');

String _promptOf(String file) =>
    '请用电脑操作模式操作这台电脑的桌面。本模型不支持读图，'
    '**不要调用 screenshot**，直接用 windows / type / shortcut 等动作完成：'
    '(1) 用 PowerShell 命令启动记事本：Start-Process notepad；'
    '(2) 用 computer 工具的 windows 找到记事本窗口并 focus_window 聚焦它；'
    '(3) 用 computer 工具的 type 动作输入这一段文字：$_secret；'
    '(4) 按 Ctrl+S，在另存为对话框的文件名框里输入完整路径 $file 并回车保存；'
    '(5) 关闭记事本，最后用一句话说明你用了哪些 computer 动作。';

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

String get _shotDir =>
    Platform.environment['L2A_SHOT_DIR'] ?? 'build/windows_shots';

Future<void> _writeLog(String name, String content) async {
  final dir = _shotDir;
  await Directory(dir).create(recursive: true);
  await File(p.join(dir, name)).writeAsString(content, flush: true);
  // ignore: avoid_print
  print('LOG $name ${content.length} chars');
}

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

/// 把会话切到插件给的「电脑操作模式」preset（composer 上那一排模式）。
Future<bool> _selectComputerMode(
  WidgetTester tester,
  BrowserController wv,
) async {
  for (var i = 0; i < 10; i++) {
    final opened = await _js(wv, r'''
      (() => {
        const visible = (e) => e && e.offsetParent !== null;
        let btn = [...document.querySelectorAll('button')].find(
          (b) => visible(b) &&
                 /标准模式|Standard mode|PTC 模式|创造模式|极简模式/i
                   .test((b.textContent || '').trim()),
        );
        if (!btn) {
          const label = [...document.querySelectorAll('*')].find(
            (e) => visible(e) && e.children.length === 0 &&
                   /^(标准模式|Standard mode)$/i
                     .test((e.textContent || '').trim()),
          );
          btn = label ? (label.closest('button') || label) : null;
        }
        if (!btn) return 'no-mode-button';
        btn.click();
        return 'opened';
      })()
      ''', label: 'mode-open');
    await _pumpFor(tester, const Duration(milliseconds: 800));
    final picked = await _js(wv, r'''
      (() => {
        const visible = (e) => e && e.offsetParent !== null;
        const hit = [...document.querySelectorAll('*')].find(
          (e) => visible(e) && e.children.length === 0 &&
                 /电脑操作模式|Computer operation|Computer use|Computer mode/i
                   .test((e.textContent || '').trim()),
        );
        if (!hit) return 'no-computer-mode';
        (hit.closest('[role="menuitem"]') || hit.closest('button') || hit).click();
        return 'clicked';
      })()
      ''', label: 'mode-pick');
    await _pumpFor(tester, const Duration(seconds: 1));
    final state = await _js(
      wv,
      'document.body.innerText.includes("电脑操作模式") ? "on" : "off"',
      label: 'mode-state',
    );
    if (state.contains('on')) return true;
    // ignore: avoid_print
    print('mode attempt $i: open=$opened pick=$picked state=$state');
    await _pumpFor(tester, const Duration(seconds: 1));
  }
  return false;
}

/// 切到 DSH 的 Trajectory 视图：思考过程 / 工具调用都在这里，
/// Chat 视图只显示最终正文。截图与轮询日志都基于这个视图。
Future<void> _showTrajectory(WidgetTester tester, BrowserController wv) async {
  for (var i = 0; i < 10; i++) {
    final out = await _js(wv, r'''
      (() => {
        const visible = (e) => e && e.offsetParent !== null;
        const hit = [...document.querySelectorAll('button,[role="tab"],a')]
          .filter(visible)
          .find((e) => /^(Trajectory|轨迹|轨迹视图)$/i
            .test((e.textContent || '').trim()));
        if (hit) {
          hit.click();
          return 'clicked';
        }
        const label = [...document.querySelectorAll('*')].find(
          (e) => visible(e) && e.children.length === 0 &&
                 /^(Trajectory|轨迹|轨迹视图)$/i
                   .test((e.textContent || '').trim()),
        );
        if (!label) return 'no-tab';
        (label.closest('button,[role="tab"],a') || label).click();
        return 'clicked';
      })()
      ''', label: 'trajectory');
    if (out.contains('clicked')) {
      await _pumpFor(tester, const Duration(seconds: 2));
      return;
    }
    await _pumpFor(tester, const Duration(seconds: 1));
  }
}

Future<void> _sendPrompt(
  WidgetTester tester,
  BrowserController wv,
  String prompt,
) async {
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

  testWidgets(
    'Windows miuix: 电脑操作模式实测（记事本 + 截图回读）',
    (tester) async {
      await app.main();
      await _pumpFor(tester, const Duration(seconds: 2));
      await _nativeShot('00-cu-home');

      // 1. 装插件（装完插件服务会自己重启 DSH）。
      await DshService.instance.init();
      final plugins = DshPluginsService.instance;
      await plugins.init(DshService.instance);
      final cuEnabled = await plugins.setEnabled(DshPluginId.computerUse, true);
      // ignore: avoid_print
      print(
        'computer-use plugin enabled=$cuEnabled '
        'state=${plugins.stateOf(DshPluginId.computerUse).error}',
      );
      expect(cuEnabled, isTrue, reason: 'dsh-computer-use-mode 没装上');

      // 2. 刷新 Zen 免费车道，优先带视觉的（computer use 全靠读图）。
      final store = ConfigStore();
      await store.load();
      final profiles = ProfileStore();
      await profiles.load();
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
          ApiKeyEntry(id: 'ci-cu', name: 'CI', key: 'sk-ci-computer-use'),
        );
        store.update(store.config);
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      await ProfileService.refreshModelLists(
        store: profiles,
        config: store.config,
      );
      store.update(store.config);
      await Future<void>.delayed(const Duration(seconds: 1));
      final zen = ProfileService.upstreamOf(store.config, kZenUpstreamId);
      final lanes =
          zen?.models.map((m) => m.target).toList() ?? const <String>[];
      // 发现页「刷新可用模型列表」的同一套对账：补新、摘失效。
      // ignore: avoid_print
      print(
        'DISCOVER refreshError=${zenDiscovery.lastError} '
        'at=${zenDiscovery.refreshedAt} lanes=$lanes',
      );
      await _writeLog(
        'computer-use-discover.log',
        'refreshError=${zenDiscovery.lastError}\n'
            'refreshedAt=${zenDiscovery.refreshedAt}\n'
            'lanes=${lanes.join('\n')}\n',
      );
      expect(
        lanes,
        contains('minimax-m3.1-flash-free'),
        reason: '发现页刷新后没有 minimax 免费车道（看上面的 lanes）',
      );
      final minimax = [
        for (final lane in lanes)
          if (lane.toLowerCase().contains('minimax')) lane,
      ];
      final lane = minimax.first;
      // ignore: avoid_print
      print('CHOSEN lane=$lane minimax=$minimax');
      expect(lane, isNotEmpty, reason: '刷新后没有可用的免费车道');

      await DshService.instance.setGroup(kZenProfileId);
      await DshService.instance.setModels([lane]);
      final applied = await DshService.instance.applyApiConfig(store.config);
      // ignore: avoid_print
      print('DSH apply=${applied.ok} err=${applied.error} lane=$lane');
      expect(applied.ok, isTrue);
      // 证明导入的是 minimax 而不是别的车道。
      final cordis = await File(DshService.instance.configPath).readAsString();
      expect(cordis, contains('minimax'));
      await _writeLog('computer-use-cordis.yml', cordis);

      final controller = ServerController(store);
      await controller.start();
      addTearDown(() => controller.stop());
      await DshService.instance.start();
      await _pumpFor(tester, const Duration(seconds: 3));
      // ignore: avoid_print
      print(
        'DSH running=${DshService.instance.running} '
        'url=${DshService.instance.url}',
      );
      expect(DshService.instance.running, isTrue);

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );

      // 发现页（刷新后的 Zen 免费车道）：截图留档，证明导入 DSH 的
      // minimax 车道来自发现页这次对账。
      final discoverKey = GlobalKey();
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => RepaintBoundary(
              key: discoverKey,
              child: MiuixProfilesPage(controller: controller),
            ),
          ),
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 3));
      await _capture(tester, '00b-cu-discover', discoverKey);
      navigator.pop();
      await _pumpFor(tester, const Duration(seconds: 1));

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
      await _capture(tester, '01-cu-dsh', dshKey);

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
      final onComputerMode = await _selectComputerMode(tester, wv);
      // ignore: avoid_print
      print('computer mode selected=$onComputerMode');
      await _pumpFor(tester, const Duration(seconds: 2));
      await _capture(tester, '02-cu-webui', browserKey);
      final modelShown = await _js(wv, r'''
      (() => {
        const text = document.body.innerText || '';
        const hit = text.match(/minimax[^\s]*/gi) || [];
        return 'minimax=' + JSON.stringify(hit.slice(0, 5));
      })()
      ''', label: 'model-visible');
      // ignore: avoid_print
      print('MODEL selector $modelShown');

      final target = _targetFile();
      await _sendPrompt(tester, wv, _promptOf(target));
      await _pumpFor(tester, const Duration(seconds: 3));
      await _showTrajectory(tester, wv);
      final trajectoryText = await _js(
        wv,
        'document.body.innerText',
        label: 'trajectory-text',
      );
      await _writeLog('computer-use-trajectory-start.log', trajectoryText);
      await _capture(tester, '03-cu-trajectory', browserKey);

      String pageText = '';
      var lastLog = DateTime.now();
      var lastShot = DateTime.now();
      DateTime? savedAt;
      final progressLog = StringBuffer();
      var progressShots = 0;
      for (var i = 0; i < 210; i++) {
        // 最多约 7 分钟，每 2 秒看一次；屏幕录制 / 输入注入的权限弹窗顺手点允许。
        // Trajectory 视图里工具结果本身就会写 "Completed all N action(s)"，
        // 不能拿它当整轮结束的标志；只认目标文件落盘，再留 15 秒让模型收尾。
        await _js(wv, r'''
        (() => {
          const b = [...document.querySelectorAll('button')].find(
            (x) => !x.disabled &&
                   /^(允许|允许一次|总是允许|Allow|Allow once|Always allow)$/i
                     .test((x.textContent || '').trim()),
          );
          if (b) { b.click(); return 'allowed'; }
          return 'no-allow';
        })()
        ''', label: 'allow');
        final text = await _js(wv, 'document.body.innerText', label: 'page');
        if (text.isNotEmpty) pageText = text;
        String disk = '';
        try {
          final f = File(target);
          if (await f.exists()) disk = await f.readAsString();
        } catch (_) {}
        final saved = disk.contains(_secret);
        if (saved) savedAt ??= DateTime.now();
        if (savedAt != null &&
            DateTime.now().difference(savedAt) > const Duration(seconds: 15)) {
          break;
        }
        if (DateTime.now().difference(lastLog) > const Duration(seconds: 20)) {
          lastLog = DateTime.now();
          progressLog.writeAll([
            '\n===== ${DateTime.now().toIso8601String()} i=$i '
                'saved=$saved =====\n',
            pageText,
            '\n',
          ]);
          // ignore: avoid_print
          print(
            'WAIT i=$i saved=$saved '
            'tail=${pageText.length > 600 ? pageText.substring(pageText.length - 600) : pageText}',
          );
        }
        // 每 30 秒整屏截一张，把「思考中 / 工具调用 / 输出」留在 artifact 里。
        if (DateTime.now().difference(lastShot) > const Duration(seconds: 30)) {
          lastShot = DateTime.now();
          progressShots++;
          await _capture(tester, '03-cu-progress-$progressShots', browserKey);
        }
        await _pumpFor(tester, const Duration(seconds: 2));
      }
      // 让模型把收尾那句话 / 关记事本的最后一个动作走完，再截最终图。
      await _pumpFor(tester, const Duration(seconds: 3));
      progressLog.writeAll([
        '\n===== ${DateTime.now().toIso8601String()} FINAL =====\n',
        pageText,
        '\n',
      ]);
      // ignore: avoid_print
      print(
        'FINAL PAGE (tail):\n'
        '${pageText.length > 4000 ? pageText.substring(pageText.length - 4000) : pageText}',
      );
      await _writeLog('computer-use-page.log', progressLog.toString());
      await _capture(tester, '04-cu-final', browserKey);
      await _writeLog(
        'computer-use-dsh.log',
        DshService.instance.logs.join('\n'),
      );

      // 侧效验：真的有个 GUI 应用被拉起来了。
      final notepad = await _powershell(
        '(Get-Process notepad -ErrorAction SilentlyContinue | '
        'Select-Object -First 1 -ExpandProperty Id)',
      );
      final windows = await _powershell(
        '(Get-Process | Where-Object { \$_.MainWindowTitle -ne "" } | '
        'Select-Object -ExpandProperty MainWindowTitle) -join " | "',
      );
      // ignore: avoid_print
      print('notepad pid=$notepad windows=$windows');
      await _writeLog(
        'computer-use-host.log',
        'notepad pid=$notepad\nwindows=$windows\n',
      );

      // 硬证据：记事本里真的被敲进了字，并且真的被保存成了文件。
      final out = File(target);
      final exists = await out.exists();
      final disk = exists ? await out.readAsString() : '';
      // ignore: avoid_print
      print(
        'COMPUTER-USE file=$target exists=$exists content=${jsonEncode(disk)}',
      );

      expect(
        pageText.toLowerCase(),
        isNot(contains('unknown tool')),
        reason: '工具名没还原，DSH 收到 unknown tool',
      );
      expect(
        pageText.toLowerCase(),
        isNot(contains('unknown prompt variable')),
        reason: '插件预设里有 DSH 不认的模板变量（看上面的 FINAL PAGE）',
      );
      expect(
        exists,
        isTrue,
        reason: '记事本没有把文件存出来：computer 工具没真的操作到 GUI（看 FINAL PAGE）',
      );
      expect(
        disk,
        contains(_secret),
        reason: '文件里没有敲进去的暗号：键盘合成没生效（实际内容见上面的 log）',
      );
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
