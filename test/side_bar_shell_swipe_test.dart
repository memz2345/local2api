import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/app_settings.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/nav_bus.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/ui/home_shell_nav.dart';
import 'package:local2api/ui/side_bar_shell.dart';
import 'package:local2api/widgets/collapsible_side_bar.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 常驻侧边栏壳的切页方式：与窄屏底栏壳同一套 PageView（可手滑、点侧栏走
/// animateToPage 的滑动动画），不再是瞬切的 IndexedStack。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConfigStore configStore;
  late ProfileStore profileStore;
  late ServerController controller;
  late SettingsService displaySettings;
  late AppSettings appSettings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // 侧栏壳与底栏壳共享同一个静态 tab 位置，逐钉测试前必须归零。
    HomeShellNav.index = 0;
    HomeShellNav.pagePixels.clear();
    CollapsibleSideBar.expanded.value = false;

    profileStore = ProfileStore();
    await profileStore.load();
    configStore = ConfigStore();
    await configStore.load();
    configStore.update(ProxyConfig(listenPort: 19294, listenHost: '127.0.0.1'));
    controller = ServerController(configStore)..webUiAutoStart = false;
    displaySettings = SettingsService();
    appSettings = AppSettings();
  });

  tearDown(() {
    controller.dispose();
    configStore.dispose();
    profileStore.dispose();
    displaySettings.dispose();
    appSettings.dispose();
  });

  Future<void> pumpShell(
    WidgetTester tester, {
    Size size = const Size(1000, 700),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ProfileStore>.value(value: profileStore),
          ChangeNotifierProvider<SettingsService>.value(value: displaySettings),
        ],
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SideBarShell(controller: controller, settings: appSettings),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  PageView pager(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView));

  testWidgets('宽屏壳用 PageView 承载一级页', (tester) async {
    await pumpShell(tester);

    expect(find.byType(PageView), findsOneWidget);
    expect(pager(tester).controller?.page?.round(), 0);
  });

  testWidgets('点侧栏图标是滑过去（中途出现小数页），不是瞬切', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.byIcon(Icons.explore_outlined));
    // 侧栏点击立刻改高亮（nav 先变成 1），分页控制器随后滑过去。
    // ⚠️ DrivenScrollActivity 的位移在启动后的下一帧才落到 pixels 上，所以
    // 要泵两帧再取：只 pump 一次会读到 0.0，看着像「没动画」。
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));
    final mid = pager(tester).controller?.page;
    expect(mid, isNotNull);
    expect(mid! > 0 && mid < 1, isTrue, reason: '应该正在滑动，而不是瞬切');

    await tester.pumpAndSettle();
    expect(pager(tester).controller?.page, 1);
    expect(HomeShellNav.index, 1);
  });

  testWidgets('内容区可以左右手滑切页并写回共享 tab 位置', (tester) async {
    await pumpShell(tester);

    // 用 fling 而不是 drag：视口宽 900，慢速 drag 420px 会被 PageScrollPhysics
    // 判成「没过吸附阈值」弹回原页，测不出切页。
    await tester.fling(find.byType(PageView), const Offset(-420, 0), 1200);
    await tester.pumpAndSettle();

    expect(HomeShellNav.index, 1);
    expect(pager(tester).controller?.page, 1);
    // 侧栏高亮跟着手滑走（选中态换成实心图标）。
    expect(find.byIcon(Icons.explore), findsWidgets);
  });

  testWidgets('反向滑回第 0 页', (tester) async {
    await pumpShell(tester);

    await tester.fling(find.byType(PageView), const Offset(-420, 0), 1200);
    await tester.pumpAndSettle();
    expect(HomeShellNav.index, 1);

    await tester.fling(find.byType(PageView), const Offset(420, 0), 1200);
    await tester.pumpAndSettle();

    expect(HomeShellNav.index, 0);
  });

  testWidgets('宽屏时外部切 tab 请求（安卓 Shortcut / 任务动作）也能生效', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);

    NavBus.requestTab(2);
    await tester.pumpAndSettle();

    expect(HomeShellNav.index, 2);
    expect(pager(tester).controller?.page, 2);
  });
}
