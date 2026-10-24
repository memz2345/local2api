import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/app_settings.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/miuix/miuix_home_shell.dart';
import 'package:local2api/ui/miuix/miuix_profiles_page.dart';
import 'miuix_finders.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProfileStore profileStore;
  late ConfigStore configStore;
  late ServerController controller;
  late SettingsService displaySettings;
  late AppSettings appSettings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    profileStore = ProfileStore();
    await profileStore.load();
    configStore = ConfigStore();
    await configStore.load();
    controller = ServerController(configStore);
    displaySettings = SettingsService();
    appSettings = AppSettings();
  });

  tearDown(() {
    profileStore.dispose();
    configStore.dispose();
    controller.dispose();
    displaySettings.dispose();
    appSettings.dispose();
  });

  Future<void> pumpShell(WidgetTester tester, {Size size = const Size(420, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ProfileStore>.value(value: profileStore),
          ChangeNotifierProvider<SettingsService>.value(value: displaySettings),
        ],
        child: MiuixThemeController(
          colorSchemeMode: miuixColorSchemeModeOf(themeMode: ThemeMode.light),
          keyColor: const Color(0xFF386A20),
          child: Builder(
            builder: (context) {
              final miuix = MiuixTheme.of(context);
              return MaterialApp(
                locale: const Locale('zh', 'CN'),
                localizationsDelegates:
                    AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: AppTheme.light().copyWith(
                  colorScheme: materialSchemeFromMiuix(
                    miuix.colors,
                    miuix.brightness,
                  ),
                ),
                home: MiuixHomeShell(
                  controller: controller,
                  settings: appSettings,
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets('窄屏外壳：miuix 底栏三个 tab，默认停在仪表盘', (tester) async {
    await pumpShell(tester);

    // 玻璃底栏换成了 miuix 的 MiuixGlassNavigationBar；测试环境没有着色器
    // （naviGlassAdvanced == false），按设计退回普通 MiuixNavigationBar。
    expect(find.byType(MiuixNavigationBar), findsOneWidget);
    expect(find.byType(MiuixGlassNavigationBar), findsNothing);
    expect(find.text('仪表盘'), findsWidgets);
    expect(find.text('发现'), findsWidgets);
    expect(find.text('设置'), findsWidgets);
    // snackbar host 挂着，提示才有地方落
    expect(find.byType(MiuixSnackbarHost), findsOneWidget);
    expect(find.byType(MiuixToastScope), findsOneWidget);
  });

  testWidgets('点「发现」切到 miuix 档案页', (tester) async {
    await pumpShell(tester);
    // PageView + keepAlive 之后三页都在树里（只是离屏），
    // 所以改用「只有仪表盘才有的状态卡文案」判断当前停在哪一页。
    expect(find.text('已停止'), findsOneWidget);

    await tester.tap(find.text('发现').last);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // 点底栏「发现」→ 分页滑到第 1 页（对应 InstallerX 的
    // mainPagerState.animateToPage 同一条 pager 路径）。
    final pager =
        tester.widget<PageView>(find.byType(PageView)).controller!;
    expect(pager.page, 1);
    expect(find.byType(MiuixProfilesPage), findsOneWidget);
    // 发现页现在是「上游服务列表」：这份 config 里没有上游，所以是空态提示
    expect(find.text('还没有上游，先添加一个'), findsOneWidget);
    // 发现页的 FAB 是「添加」，不是旧的「刷新」
    expect(miuixIcon(AppIconNames.add), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsNothing);

    // 手势滑动也能切页：从发现页往右滑回仪表盘。
    await tester.drag(find.byType(PageView), const Offset(420, 0));
    await tester.pumpAndSettle();
    expect(pager.page, 0);
  });

  testWidgets('宽屏走侧栏外壳（MiuixNavigationRail）', (tester) async {
    await pumpShell(tester, size: const Size(1100, 800));

    expect(find.byType(MiuixNavigationRail), findsOneWidget);
    expect(find.byType(MiuixGlassNavigationBar), findsNothing);
    expect(find.text('仪表盘'), findsWidgets);
  });
}
