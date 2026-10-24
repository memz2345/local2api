import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/app_settings.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/src/enums.dart';
import 'package:local2api/ui/app.dart';
import 'package:local2api/ui/home_shell.dart';
import 'package:local2api/ui/miuix/miuix_dashboard_page.dart';
import 'package:local2api/ui/miuix/miuix_home_shell.dart';
import 'package:local2api/ui/miuix/miuix_settings_page.dart';
import 'package:local2api/ui/miuix/miuix_side_bar_shell.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归：切换 UI 引擎要把**当前页面**留住，而不是每次都从仪表盘页开始。
///
/// 两个根因（都在 app 级，只 pump 单页碰不到）：
///  1. `MiuixThemeController` 原来只在 miuix 模式才包住 MaterialApp ——
///     返回类型一变，MaterialApp 整棵卸载重建，Navigator 的路由栈当场清空；
///  2. HomeShell / MiuixHomeShell 的 tab 位置是各自的本地 State
///     （`_index = 0`），换引擎时整棵 shell 换掉，位置归零 = 回到仪表盘页。
/// 现在前者两支同形、后者提进 [HomeShellNav] 跨引擎共享（照 InstallerX
/// `SettingsSharedViewModel.lastMainPageIndex` 的做法）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<
    ({
      AppSettings settings,
      SettingsService display,
      ServerController controller,
    })
  >
  setUpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2800);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    // 测试字体比真机宽，某些 Row 会出「伪溢出」（Material 侧 700 逻辑宽下
    // 是既有的），跟本用例要测的导航/引擎切换毫无关系，却会把 pumpAndSettle
    // 刷成异常。这里只放过 RenderFlex overflow，其余照常让用例红。
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
        return;
      }
      prevOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = prevOnError);

    // 起步就停在设置 tab —— 界面风格的切换入口就在那，也正是用户「换完
    // 引擎发现自己被弹回仪表盘」时所处的位置。
    HomeShellNav.index = 2;
    addTearDown(() {
      HomeShellNav.index = 0;
      HomeShellNav.pagePixels.clear();
    });

    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings();
    final display = SettingsService();
    final store = ConfigStore();
    final profileStore = ProfileStore();
    await Future.wait([
      settings.load(),
      display.load(),
      store.load(),
      profileStore.load(),
    ]);
    final controller = ServerController(store);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: display),
          ChangeNotifierProvider<ProfileStore>.value(value: profileStore),
        ],
        child: Local2ApiApp(settings: settings, controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    return (settings: settings, display: display, controller: controller);
  }

  testWidgets('切到 miuix：路由栈不清空，子页还在', (tester) async {
    final app = await setUpApp(tester);
    // 出厂默认已经是 miuix，这条用例要的是「Material → miuix」那一跳，
    // 所以先把引擎显式按回 Material 起步。
    await app.display.setUiStyle(UiStyle.materialExpressive);
    await tester.pumpAndSettle();
    expect(app.display.uiStyle, UiStyle.materialExpressive);

    // 推一个子页进去
    final NavigatorState nav = tester.state(find.byType(Navigator).first);
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('SUB_PAGE')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('SUB_PAGE'), findsOneWidget);
    expect(nav.canPop(), isTrue);

    // 换 UI 引擎
    await app.display.setUiStyle(UiStyle.miuix);
    await tester.pumpAndSettle();

    // 路由栈没有被清空：子页还压在上面（这正是「回到仪表盘页」的根因之一）
    expect(find.text('SUB_PAGE'), findsOneWidget);
    expect(nav.canPop(), isTrue);
    // 首页确实换成了 miuix 那套 shell。
    // skipOffstage: false —— 上面压着子页时首页是 offstage 的，
    // 默认会跳过、误报「找不到」。
    expect(
      find.byType(MiuixHomeShell, skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byType(HomeShell, skipOffstage: false), findsNothing);
  });

  testWidgets('切引擎来回：首页 tab 位置不归零（不跳回仪表盘页）', (tester) async {
    final app = await setUpApp(tester);
    // 起步就在设置 tab
    expect(HomeShellNav.index, 2);

    // 换到 miuix
    await app.display.setUiStyle(UiStyle.miuix);
    await tester.pumpAndSettle();
    expect(HomeShellNav.index, 2, reason: '换引擎后不该归零回仪表盘');
    expect(find.byType(MiuixHomeShell, skipOffstage: false), findsOneWidget);

    // 再换回 Material
    await app.display.setUiStyle(UiStyle.materialExpressive);
    await tester.pumpAndSettle();
    expect(HomeShellNav.index, 2, reason: '再换回来也该还在设置 tab');
    expect(find.byType(HomeShell, skipOffstage: false), findsOneWidget);
    expect(find.byType(MiuixHomeShell, skipOffstage: false), findsNothing);
  });

  testWidgets('横竖屏切换：宽屏侧栏壳接着当前 tab，不跳回仪表盘', (tester) async {
    // 起步在设置 tab（setUpApp 已经把 HomeShellNav.index 设成 2），
    // 尺寸是 1400x2800 @2.0 = 700x1400 逻辑像素 —— 窄屏。
    final app = await setUpApp(tester);
    await app.display.setUiStyle(UiStyle.miuix);
    await tester.pumpAndSettle();

    // 窄屏：走底栏壳，设置页真的建出来了
    expect(find.byType(MiuixHomeShell, skipOffstage: false), findsOneWidget);
    expect(find.byType(MiuixSideBarShell, skipOffstage: false), findsNothing);
    expect(
      find.byType(MiuixSettingsPage, skipOffstage: false),
      findsOneWidget,
    );

    // 「转横屏」：逻辑宽 900 ≥ 768 → 换成常驻侧栏壳（另一棵 State）
    tester.view.physicalSize = const Size(1800, 2800);
    await tester.pumpAndSettle();

    expect(
      find.byType(MiuixSideBarShell, skipOffstage: false),
      findsOneWidget,
    );
    // 侧栏壳的 _index / _visited 必须接住共享的 HomeShellNav.index（2 = 设置），
    // 而不是从 0 重来 —— 后者就是「一转横屏跳回仪表盘」的根因。
    // 断言用类型而不是文案：这棵测试树没钉 locale，文案会随系统变。
    expect(HomeShellNav.index, 2, reason: '转横屏不该归零');
    expect(
      find.byType(MiuixSettingsPage, skipOffstage: false),
      findsOneWidget,
      reason: '侧栏壳要停在设置页',
    );
    expect(
      find.byType(MiuixDashboardPage, skipOffstage: false),
      findsNothing,
      reason: '不该把仪表盘重新建出来',
    );
  });
}
