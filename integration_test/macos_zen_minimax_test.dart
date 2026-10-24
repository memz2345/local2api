// integration_test/macos_zen_minimax_test.dart
//
// macOS 真网实测（GitHub Actions macos-14）：
//   1. 用 miuix 主题启动应用；
//   2. 内置 OpenCode Zen 免费档案装进配置，刷新实时模型清单；
//   3. 刷新后选中 minimax 免费车道（minimax-m3.1-flash-free）；
//   4. 起本机 Local2API 代理 + DSH，让 minimax 识别这台 Mac 的系统信息；
//   5. 每一步截图。这个测试会真的请求 opencode.ai，失败也要留下截图，
//      所以 workflow 里是 continue-on-error。
//
// 跑法（macOS 本机 / CI）：
//   L2A_DSH_DIR=<含 node_modules/@deepseek-ai/dsh 的目录> \
//   DSH_HOME=<临时 home> \
//   flutter test integration_test/macos_zen_minimax_test.dart -d macos

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
    '请识别这台 Mac 的系统信息：型号、macOS 版本、CPU 架构和内存大小。'
    '你可以运行 sw_vers、uname -m、sysctl 等命令。请用中文给出结果。';

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> _nativeShot(String name) async {
  final dir = Platform.environment['L2A_SHOT_DIR'] ?? 'build/macos_shots';
  await Directory(dir).create(recursive: true);
  final path = p.join(dir, '$name.png');
  try {
    final result = await Process.run(
      'screencapture',
      ['-x', path],
    ).timeout(const Duration(seconds: 20));
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
  final dir = Platform.environment['L2A_SHOT_DIR'] ?? 'build/macos_shots';
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
  WebViewControllerHolder holder,
  String script, {
  String label = 'js',
}) async {
  try {
    final result = await holder.webview?.runJavaScriptReturningResult(script);
    final text = '$result';
    // ignore: avoid_print
    print('JS $label: ${text.length > 300 ? text.substring(0, 300) : text}');
    return text;
  } catch (e) {
    // ignore: avoid_print
    print('JS $label failed: $e');
    return '';
  }
}

class WebViewControllerHolder {
  WebViewControllerHolder(this.webview);
  final dynamic webview;
}

Future<WebViewControllerHolder> _waitForWebview(
  WidgetTester tester,
  BrowserController? Function() controller,
) async {
  for (var i = 0; i < 40; i++) {
    final c = controller();
    if (c != null && c.isReady && c.mobileController != null) {
      return WebViewControllerHolder(c.mobileController);
    }
    await _pumpFor(tester, const Duration(seconds: 1));
  }
  throw StateError('WKWebView 没有初始化');
}

Future<void> _dismissPreview(WidgetTester tester, WebViewControllerHolder wv) async {
  for (var i = 0; i < 12; i++) {
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

Future<void> _newSession(WidgetTester tester, WebViewControllerHolder wv) async {
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

Future<void> _enableFullAccess(WidgetTester tester, WebViewControllerHolder wv) async {
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
      const nodes = [...document.querySelectorAll('*')];
      const hit = nodes.find(
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

Future<void> _sendPrompt(WidgetTester tester, WebViewControllerHolder wv) async {
  await _js(
    wv,
    r'''
    (() => {
      const input = document.querySelector('[contenteditable="true"]');
      if (!input) return 'no-input';
      input.focus();
      document.execCommand('insertText', false, ''' +
        jsonEncode(_prompt) +
        r''');
      return 'typed';
    })()
    ''',
    label: 'type',
  );
  await _pumpFor(tester, const Duration(seconds: 1));
  await _js(
    wv,
    r'''
    (() => {
      const buttons = [...document.querySelectorAll('button')];
      let send = buttons.find(
        (b) => /发送消息|Send message/i.test(b.getAttribute('aria-label') || ''),
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
    ''',
    label: 'send',
  );
}

Future<void> _clickAllowButtons(WebViewControllerHolder wv) async {
  await _js(
    wv,
    r'''
    (() => {
      const buttons = [...document.querySelectorAll('button')];
      const hit = buttons.find(
        (b) => !b.disabled &&
               /^(允许|允许一次|总是允许|Allow|Allow once|Always allow)$/i
                 .test((b.textContent || '').trim()),
      );
      if (hit) { hit.click(); return 'allowed'; }
      return 'no-allow';
    })()
    ''',
    label: 'allow',
  );
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

  testWidgets('macOS miuix: 刷新 Zen 免费模型，用 minimax 识别系统信息', (tester) async {
    await app.main();
    await _pumpFor(tester, const Duration(seconds: 2));
    await _nativeShot('00-miuix-home');

    // 先记下这台 Mac 的真实信息，用来对照模型输出。
    String hostInfo = '';
    for (final cmd in [
      <String>['sw_vers'],
      <String>['uname', '-m'],
      <String>['sysctl', '-n', 'hw.memsize'],
    ]) {
      try {
        final r = await Process.run(cmd.first, cmd.sublist(1));
        hostInfo += '${cmd.join(' ')} => ${r.stdout}${r.stderr}';
        // ignore: avoid_print
        print('HOST ${cmd.join(' ')} => ${r.stdout}${r.stderr}');
      } catch (e) {
        // ignore: avoid_print
        print('HOST ${cmd.join(' ')} failed: $e');
      }
    }
    final versionMatch = RegExp(r'ProductVersion:\s*(\S+)').firstMatch(hostInfo);
    final hostVersion = versionMatch?.group(1) ?? '';
    final hostArch = Platform.version.contains('arm64') ? 'arm64' : 'x86_64';
    // ignore: avoid_print
    print('HOST summary version=$hostVersion arch=$hostArch');

    // 用应用自己的 store 读取内置 Zen 档案（main 已经默认装进配置）。
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

    // 刷新可用模型：这是用户特别强调的一步。
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
    expect(
      minimaxLanes,
      isNotEmpty,
      reason: '刷新后没有 minimax 免费车道（看上面的 zen lanes）',
    );
    final lane = minimaxLanes.first;

    await DshService.instance.init();
    await DshService.instance.setGroup(kZenProfileId);
    await DshService.instance.setModels([lane]);
    final applied = await DshService.instance.applyApiConfig(store.config);
    // ignore: avoid_print
    print('DSH apply=${applied.ok} err=${applied.error} lane=$lane');

    // 起真实代理：DSH → local2api → Zen。
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
    print('DSH running=${DshService.instance.running} url=${DshService.instance.url}');
    expect(DshService.instance.running, isTrue);

    // miuix 的 DSH 设置页截图。
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

    // miuix 内置浏览器打开 DSH。
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
    final wv = await _waitForWebview(
      tester,
      () => MiuixBrowserPage.debugLastController,
    );
    await _pumpFor(tester, const Duration(seconds: 8));

    await _dismissPreview(tester, wv);
    await _newSession(tester, wv);
    await _enableFullAccess(tester, wv);

    // 先截一张模型选择器，确认是 minimax。
    await _pumpFor(tester, const Duration(seconds: 2));
    await _capture(tester, '02-miuix-zen-webui', browserKey);

    await _sendPrompt(tester, wv);
    await _pumpFor(tester, const Duration(seconds: 3));

    String pageText = '';
    var lastLog = DateTime.now();
    for (var i = 0; i < 180; i++) {
      // 3 分钟，每 2 秒看一次；遇到权限弹窗顺手点允许。
      await _clickAllowButtons(wv);
      final text = await _js(
        wv,
        'document.body.innerText',
        label: 'page',
      );
      if (text.isNotEmpty) pageText = text;
      final done = pageText.contains('Completed') ||
          pageText.contains('已完成') ||
          pageText.contains('Failed') ||
          pageText.contains('失败');
      final hasRealInfo = (hostVersion.isNotEmpty &&
              pageText.contains(hostVersion)) ||
          pageText.contains('arm64') ||
          pageText.contains('Darwin') ||
          pageText.contains('Apple');
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

    final expectedInfo = <String>[
      if (hostVersion.isNotEmpty) hostVersion,
      'arm64',
      'Darwin',
      'Apple',
    ].map(RegExp.escape).join('|');
    expect(
      pageText,
      matches(RegExp(expectedInfo)),
      reason: '模型没有输出可识别的系统信息（看上面的 FINAL PAGE）',
    );
  }, timeout: const Timeout(Duration(minutes: 12)));
}
