// integration_test/browser_shim_probe_test.dart
//
// 内置浏览器的真机探针（Android）：
//   1. 网页 `<select>` 被拦下 → 弹出 Flutter 的 Material 3 选择器 →
//      选中后回填 selectedIndex + 派发 change（页面把结果显示到 <title>）；
//   2. 滚动条 CSS 装上了（shim 的 <style> 存在）；
//   3. Custom Tabs 通道：能枚举浏览器、能拉起。
//
// 跑法（真机 / 模拟器）：
//   flutter test integration_test/browser_shim_probe_test.dart -d <deviceId>
// 页面由测试自己起一个 127.0.0.1 的 HttpServer 提供，不依赖外网。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/custom_tabs_service.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/ui/browser_page.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

const String _page = '''
<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>TEST</title>
<style>
  body { margin:0; font-family: sans-serif; }
  select { position:relative; display:block; width:100%; height:64px; font-size:22px; }
  .fill { height:1600px; background:linear-gradient(#fff,#eee); }
</style></head>
<body>
  <select id="sel" onchange="document.title='PICKED:'+this.value;location.hash='picked='+this.value;">
    <option value="amazon-bedrock">amazon-bedrock</option>
    <option value="anthropic">anthropic</option>
    <option value="azure" selected>azure</option>
    <option value="deepseek">deepseek</option>
    <option value="fireworks">fireworks</option>
  </select>
  <select id="grouped">
    <optgroup label="本地"><option>ollama</option><option>llama.cpp</option></optgroup>
    <optgroup label="云端"><option>openai</option><option>claude</option></optgroup>
  </select>
  <div class="fill"></div>
</body></html>
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write(_page);
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  testWidgets('网页 select 走 Flutter 选择器，选完回填 change', (tester) async {
    final settings = SettingsService();
    await settings.load();
    final url = 'http://127.0.0.1:${server.port}/';

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsService>.value(
        value: settings,
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BrowserPage(initialUrl: url),
        ),
      ),
    );

    // 等页面加载完（标题 TEST 出现在顶栏）
    var loaded = false;
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.text('TEST').evaluate().isNotEmpty) {
        loaded = true;
        break;
      }
    }
    expect(loaded, isTrue, reason: '测试页没加载出来');

    // 点第一个 <select>（固定在页面顶部，高度 64）
    final origin = tester.getTopLeft(find.byType(WebViewWidget));
    await tester.tapAt(origin + const Offset(160, 32));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 600));

    // 我们的 Material 3 面板（不是系统 Holo 弹窗）应该出来了
    expect(find.text('deepseek'), findsOneWidget, reason: '选择器没弹出来');
    expect(find.text('fireworks'), findsOneWidget);

    await tester.tap(find.text('deepseek'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 800));

    // 页面 onchange 改了 location.hash → 控制器的 onUrlChange → 顶栏地址变化。
    // （标题只在 onPageFinished 读一次，不能用它判定回填。）
    var applied = false;
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.textContaining('picked=deepseek').evaluate().isNotEmpty) {
        applied = true;
        break;
      }
    }
    expect(applied, isTrue, reason: 'change 事件没有回填到页面');
  });

  testWidgets('Custom Tabs 通道：能枚举、能拉起', (tester) async {
    expect(CustomTabsService.isSupported, isTrue);
    final available = await CustomTabsService.isAvailable();
    final browsers = await CustomTabsService.browsers();
    // ignore: avoid_print
    print(
      'CT_PROBE available=$available browsers='
      '${browsers.map((b) => '${b.label}|${b.packageName}|default=${b.isDefault}').join(',')}',
    );
    expect(available, isTrue, reason: '设备上没有 Custom Tabs 提供者');
    expect(browsers, isNotEmpty);

    // 真拉起一次（真机验证会切到 Chrome / Edge）
    final ok = await CustomTabsService.open(
      'https://example.com',
      packageName: browsers.first.packageName,
    );
    // ignore: avoid_print
    print('CT_PROBE open=$ok');
    expect(ok, isTrue);
  });
}
