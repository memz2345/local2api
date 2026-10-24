// 回归：miuix 页面底色必须与卡片底色区分开。
//
// 出厂（静态）配色里 `background == surfaceContainer`：
//   - 浅色：both 0xFFFFFFFF
//   - 深色：both 0xFF242424
// 而 `MiuixCard` 的默认底色正是 `surfaceContainer` —— 页面一旦用 `background`
// 当容器色，卡片就跟背景糊成一片、主次不分（用户报的「分不清主体」）。
// `MiuixScaffold` 的出厂默认是 `surface`（浅色 #F7F7F7 / 深色纯黑），
// 也正是 InstallerX 的样子 —— 各 miuix 页面都该用这个。
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/app_settings.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';
import 'package:local2api/ui/miuix/miuix_settings_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConfigStore configStore;
  late ServerController controller;
  late SettingsService displaySettings;
  late AppSettings appSettings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    configStore = ConfigStore();
    await configStore.load();
    controller = ServerController(configStore);
    displaySettings = SettingsService();
    appSettings = AppSettings();
  });

  tearDown(() {
    configStore.dispose();
    controller.dispose();
    displaySettings.dispose();
    appSettings.dispose();
  });

  /// 按 app.dart 的 miuix 分支搭树，走**静态出厂配色**（问题现场那一档）。
  Future<MiuixColors> pumpSettings(
    WidgetTester tester, {
    required ThemeMode mode,
  }) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: displaySettings),
        ],
        child: MiuixThemeController(
          colorSchemeMode: miuixDefaultColorSchemeModeOf(themeMode: mode),
          child: Builder(
            builder: (context) {
              final miuix = MiuixTheme.of(context);
              return MaterialApp(
                // 不钉 locale 的话测试环境默认 en_US，中文断言全对不上
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
                home: Scaffold(
                  body: MiuixSettingsPage(
                    controller: controller,
                    settings: appSettings,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return MiuixTheme.of(tester.element(find.byType(MiuixSettingsPage))).colors;
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('miuix 设置页：页面底色与卡片底色必须能分开（$mode）', (tester) async {
      final colors = await pumpSettings(tester, mode: mode);

      // 出厂配色本身就是分开的（surface 深色纯黑 / 浅色 #F7F7F7）
      expect(
        colors.surface,
        isNot(colors.surfaceContainer),
        reason: 'MiuixScaffold 的 surface 必须与 MiuixCard 的 surfaceContainer 不同色',
      );
      // 而 background 恰好跟卡片同色 —— 这就是当初踩的坑，钉住它别再选错
      expect(
        colors.background,
        colors.surfaceContainer,
        reason: '出厂配色里 background 就是卡片色，所以页面容器不能用它',
      );

      final scaffold = tester.widget<MiuixScaffold>(
        find.byType(MiuixScaffold).first,
      );
      expect(
        scaffold.containerColor,
        colors.surface,
        reason: '页面容器要用 surface，不能用与卡片同色的 background',
      );
    });
  }
}
