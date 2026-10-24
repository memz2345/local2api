import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/tailscale_service.dart';
import 'package:local2api/ui/miuix/miuix_network_page.dart';
import 'package:local2api/ui/network_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归：Tailscale 卡片在「已装 / 没装」两种状态下的文案与图标。
///
/// 探测结果用 `TailscaleService.detectOverride` 钉住（真去 fork 进程既慢
/// 又依赖机器装没装），两份 UI 各验一遍。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConfigStore configStore;
  late ServerController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    configStore = ConfigStore();
    await configStore.load();
    configStore.update(ProxyConfig(listenPort: 19293, listenHost: '127.0.0.1'));
    controller = ServerController(configStore)..webUiAutoStart = false;
    TailscaleService.detectOverride = () async => false;
  });

  tearDown(() {
    TailscaleService.detectOverride = null;
    controller.dispose();
    configStore.dispose();
  });

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: page,
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets('Material 版：没装显示下载，装了改成打开', (tester) async {
    await pumpPage(tester, NetworkPage(controller: controller));

    expect(find.text('获取 Tailscale'), findsOneWidget);
    expect(find.byIcon(Icons.link), findsWidgets);
    expect(find.text('打开 Tailscale'), findsNothing);

    // 连续两次 pumpWidget 只会更新同一棵子树（State 不重建），中间的占位
    // 让上一页真的被 dispose，initState 才会带着新结果再跑一遍。
    await tester.pumpWidget(const SizedBox.shrink());
    TailscaleService.detectOverride = () async => true;
    await pumpPage(tester, NetworkPage(controller: controller));

    expect(find.text('打开 Tailscale'), findsOneWidget);
    expect(find.text('已安装 Tailscale，点一下打开客户端'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsWidgets);
    expect(find.text('获取 Tailscale'), findsNothing);
  });

  testWidgets('miuix 版：同样是装了就打开', (tester) async {
    TailscaleService.detectOverride = () async => true;
    await pumpPage(tester, MiuixNetworkPage(controller: controller));

    expect(find.text('打开 Tailscale'), findsOneWidget);
    expect(find.text('已安装 Tailscale，点一下打开客户端'), findsOneWidget);
    expect(find.text('获取 Tailscale'), findsNothing);
  });

  testWidgets('两种状态下都留着下载页入口（装了也要能重装）', (tester) async {
    TailscaleService.detectOverride = () async => true;
    await pumpPage(tester, NetworkPage(controller: controller));

    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
  });
}
