import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/app_settings.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/nav_bus.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/home_shell_nav.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';
import 'package:local2api/ui/miuix/miuix_side_bar_shell.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// miuix 版常驻侧边栏壳：与 Material 版同一套 PageView 滑动切页。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConfigStore configStore;
  late ProfileStore profileStore;
  late ServerController controller;
  late SettingsService displaySettings;
  late AppSettings appSettings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    HomeShellNav.index = 0;
    HomeShellNav.pagePixels.clear();

    profileStore = ProfileStore();
    await profileStore.load();
    configStore = ConfigStore();
    await configStore.load();
    configStore.update(
      ProxyConfig(
        listenPort: 19295,
        listenHost: '127.0.0.1',
        upstreams: [
          Upstream(
            id: 'a',
            name: '甲组',
            type: UpstreamType.openai,
            baseUrl: 'https://a.example/v1',
            models: [ModelEntry(publicName: 'm1')],
          ),
        ],
      ),
    );
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

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 720);
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
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: AppTheme.light().copyWith(
                  colorScheme: materialSchemeFromMiuix(
                    miuix.colors,
                    miuix.brightness,
                  ),
                ),
                home: MiuixSideBarShell(
                  controller: controller,
                  settings: appSettings,
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  PageView pager(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView));

  testWidgets('miuix 宽屏壳也用 PageView 承载一级页', (tester) async {
    await pumpShell(tester);

    expect(find.byType(PageView), findsOneWidget);
    expect(find.byType(MiuixNavigationRail), findsOneWidget);
    expect(pager(tester).controller?.page?.round(), 0);
  });

  testWidgets('点侧栏「发现」是滑过去，不是瞬切', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('发现').last);
    // DrivenScrollActivity 的位移要下一帧才落到 pixels，泵两次再取。
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));
    final mid = pager(tester).controller?.page;
    expect(mid! > 0 && mid < 1, isTrue, reason: '应该正在滑动');

    await tester.pumpAndSettle();
    expect(pager(tester).controller?.page, 1);
    expect(HomeShellNav.index, 1);
  });

  testWidgets('内容区手滑切页会写回共享 tab 位置', (tester) async {
    await pumpShell(tester);

    await tester.fling(find.byType(PageView), const Offset(-420, 0), 1200);
    await tester.pumpAndSettle();

    expect(HomeShellNav.index, 1);
    expect(pager(tester).controller?.page, 1);
  });

  testWidgets('外部切 tab 请求（Shortcut / 任务动作）在 miuix 宽屏也生效', (
    tester,
  ) async {
    await pumpShell(tester);

    NavBus.requestTab(2);
    await tester.pumpAndSettle();

    expect(HomeShellNav.index, 2);
    expect(pager(tester).controller?.page, 2);
  });
}
