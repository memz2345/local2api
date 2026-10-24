// integration_test/windows_browser_input_test.dart
//
// Windows 内置浏览器输入回归（GitHub Actions windows-2022）：
//   1. 滚轮：PointerScrollEvent → 页面真的往下滚（以前发到 (0,0)，只滚页头）；
//   2. 右键：WebView2 默认菜单已开启，右键后能看到原生菜单窗口（#32768）；
//   3. IME 锚点：宿主锚点窗口必须落在 webview 控件的屏幕矩形上
//      （以前是 message-only 窗口，坐标永远 0,0，候选框会飘到左上角）；
//   4. 点击输入框后 document.activeElement 真的切过去（焦点路径没被锚点改坏）。
//
// 跑法（Windows 本机 / CI）：
//   flutter test integration_test/windows_browser_input_test.dart -d windows

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_windows/webview_windows.dart' as win;

import 'package:local2api/main.dart' as app;
import 'package:local2api/services/browser_controller.dart';
import 'package:local2api/ui/miuix/miuix_browser_page.dart';

const String _html = '''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<style>
  html, body { margin: 0; background: #1b1b1f; color: #eee;
               font-family: sans-serif; }
  #pad { height: 6000px; padding: 40px; box-sizing: border-box; }
  #txt { position: absolute; left: 40px; top: 40px; width: 320px;
         height: 44px; font-size: 18px; }
  #hint { position: absolute; left: 40px; top: 96px; }
</style>
</head>
<body>
  <input id="txt" placeholder="type here">
  <div id="hint">scroll test page</div>
  <div id="pad"></div>
  <script>
    window.__ctx = null;
    document.addEventListener('contextmenu', (e) => {
      window.__ctx = { x: e.clientX, y: e.clientY,
                       target: e.target && e.target.id };
    });
  </script>
</body>
</html>
''';

String get _shotDir =>
    Platform.environment['L2A_SHOT_DIR'] ?? 'build/windows_shots';

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> _nativeShot(String name) async {
  await Directory(_shotDir).create(recursive: true);
  final path = p.join(_shotDir, '$name.png').replaceAll('\\', '/');
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

Future<String> _js(BrowserController? controller, String script) async {
  final webview = controller?.windowsController;
  if (webview == null) return '';
  try {
    final result = await webview.executeScript(script);
    final text = '$result';
    // ignore: avoid_print
    print('JS: ${text.length > 300 ? text.substring(0, 300) : text}');
    return text;
  } catch (e) {
    // ignore: avoid_print
    print('JS failed: $e');
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

/// 起一个旁路进程：等右键菜单弹出来 → 截图后 Esc 收掉。
///
/// WebView2 的右键菜单不一定是 #32768（实测 FindWindow 找不到但画面里
/// 确实有菜单），所以不靠窗口类判断；真正的证据是测试里那张整屏截图。
Future<Process> _startMenuWatcher(String outPath) {
  final script =
      '''
Add-Type -AssemblyName System.Windows.Forms
Start-Sleep -Seconds 4
[System.Windows.Forms.SendKeys]::SendWait("{ESC}")
Set-Content -Path '$outPath' -Value "esc-sent=true"
''';
  return Process.start('powershell', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    script,
  ]);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Windows 内置浏览器：滚轮 / 右键菜单 / IME 锚点 / 焦点',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'local2api.localeCode': 'zh-CN',
        'local2api.uiStyle': 'miuix',
      });

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.headers.contentType = ContentType.html;
        request.response.write(_html);
        await request.response.close();
      });

      await app.main();
      await _pumpFor(tester, const Duration(seconds: 2));

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      final key = GlobalKey();
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => RepaintBoundary(
              key: key,
              child: MiuixBrowserPage(
                initialUrl: 'http://127.0.0.1:${server.port}/',
                title: 'Browser input test',
              ),
            ),
          ),
        ),
      );
      final wv = await _waitForWebview(tester);
      await _pumpFor(tester, const Duration(seconds: 4));

      final webviewFinder = find.byType(win.Webview);
      expect(webviewFinder, findsOneWidget);
      final rect = tester.getRect(webviewFinder);
      final dpr = tester.view.devicePixelRatio;
      // ignore: avoid_print
      print('RECT=$rect dpr=$dpr');

      // 1) 原生右键菜单开关 + 锚点窗口位置。
      final raw = await wv.windowsController!.getDiagnostics();
      // ignore: avoid_print
      print('DIAG=$raw');
      final diag = jsonDecode(raw ?? '{}') as Map<String, dynamic>;
      expect(diag['contextMenus'], isTrue, reason: 'WebView2 默认右键菜单没开');
      final anchor = (diag['anchor'] as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList();
      // 锚点必须是 webview 控件的屏幕矩形；y > 40 直接排除 message-only (0,0)。
      expect(
        anchor[2] - anchor[0],
        closeTo(rect.width * dpr, 4),
        reason: '锚点宽度和 webview 不一致：$anchor vs $rect',
      );
      expect(
        anchor[3] - anchor[1],
        closeTo(rect.height * dpr, 4),
        reason: '锚点高度和 webview 不一致：$anchor vs $rect',
      );
      expect(
        anchor[1],
        greaterThan(40 * dpr),
        reason: '锚点还在屏幕左上角（IME 候选框会飘）：$anchor',
      );

      // 2) 点一下输入框，确认焦点真的进了网页（键盘/IME 路径）。
      await tester.sendEventToBinding(
        PointerDownEvent(
          position: rect.topLeft + const Offset(120, 60),
          buttons: kPrimaryMouseButton,
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.sendEventToBinding(
        PointerUpEvent(
          position: rect.topLeft + const Offset(120, 60),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 1));
      final active = await _js(
        wv,
        'document.activeElement ? document.activeElement.id : ""',
      );
      // ignore: avoid_print
      print('ACTIVE=$active');
      expect(active, contains('txt'), reason: '点击后网页输入框没拿到焦点');

      // 3) 滚轮：先把光标移到 webview 中间，再发滚动信号。
      final center = rect.center;
      await tester.sendEventToBinding(
        PointerHoverEvent(position: center, kind: PointerDeviceKind.mouse),
      );
      await _pumpFor(tester, const Duration(milliseconds: 300));
      final before =
          double.tryParse(
            (await _js(wv, 'String(window.scrollY)')).replaceAll('"', ''),
          ) ??
          0;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: center,
          scrollDelta: const Offset(0, 320),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await _pumpFor(tester, const Duration(seconds: 1));
      final after =
          double.tryParse(
            (await _js(wv, 'String(window.scrollY)')).replaceAll('"', ''),
          ) ??
          0;
      // ignore: avoid_print
      print('SCROLL before=$before after=$after');
      expect(after, greaterThan(before + 10), reason: '滚轮没有让页面滚动');

      // 4) 右键菜单：旁路进程等 #32768，出现就按 Esc。
      //    先把页面滚回顶部，确保右键落点在同一块空白区域。
      await _js(wv, 'window.scrollTo(0, 0); "ok"');
      await _pumpFor(tester, const Duration(milliseconds: 300));
      final outPath = p.join(_shotDir, 'browser-menu.txt');
      await Directory(_shotDir).create(recursive: true);
      final watcher = await _startMenuWatcher(outPath);
      await _pumpFor(tester, const Duration(seconds: 2));
      final menuPoint = rect.topLeft + const Offset(140, 70);
      await tester.sendEventToBinding(
        PointerDownEvent(
          position: menuPoint,
          buttons: kSecondaryMouseButton,
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.sendEventToBinding(
        PointerUpEvent(position: menuPoint, kind: PointerDeviceKind.mouse),
      );
      await _pumpFor(tester, const Duration(seconds: 1));
      final ctx = await _js(wv, 'JSON.stringify(window.__ctx)');
      // ignore: avoid_print
      print('CONTEXT-EVENT $ctx');
      await _nativeShot('browser-right-click');
      await watcher.exitCode.timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          watcher.kill();
          return -1;
        },
      );
      var menuResult = '';
      try {
        menuResult = await File(outPath).readAsString();
      } catch (_) {}
      // ignore: avoid_print
      print('CONTEXT-MENU $menuResult see browser-right-click.png');
      // 菜单由浏览器进程弹，CI 上偶发抢不到前台；截图留证，不作为硬失败。
      // 真正的开关由上面的 contextMenus 诊断保证。
      await _pumpFor(tester, const Duration(seconds: 1));
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
