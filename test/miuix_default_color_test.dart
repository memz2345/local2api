// 「自定义颜色」开关的配色回归（miuix 侧）：
// 关掉后走 InstallerX 的 Default Miuix Theme Path —— 静态出厂配色
// （HyperOS 蓝 0xFF3482FF / 深色 0xFF277AF7），而不是种子色经 monet
// 生成的 Material 蓝；Material 引擎不读这个开关，不受影响。
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/app_settings.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/src/enums.dart';
import 'package:local2api/ui/app.dart';
import 'package:local2api/ui/home_shell.dart';
import 'package:local2api/ui/miuix/miuix_home_shell.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_miuix lightColorScheme / darkColorScheme 的主色
  const miuixFactoryBlue = Color(0xFF3482FF);
  const miuixFactoryBlueDark = Color(0xFF277AF7);
  // 用来跟出厂蓝区分的种子色
  const redSeed = Color(0xFFE53935);

  Future<SettingsService> setUpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2800);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    // 与配色断言无关的既有伪溢出（Material 侧 700 逻辑宽下就有），放过它
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
        return;
      }
      prevOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = prevOnError);

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
    return display;
  }

  MiuixColors miuixColors(WidgetTester tester) => MiuixTheme.of(
    tester.element(find.byType(MiuixHomeShell, skipOffstage: false)),
  ).colors;

  Color materialPrimary(WidgetTester tester) => Theme.of(
    tester.element(find.byType(HomeShell, skipOffstage: false)),
  ).colorScheme.primary;

  testWidgets('miuix：跟随系统时明暗跟着系统亮度走（两边同一步调）', (tester) async {
    final display = await setUpApp(tester);

    // 系统亮度是**同一份 TestPlatformDispatcher 上的全局测试值**，不自己收回去
    // 会漏给后面的用例（它们默认按浅色断言）。
    addTearDown(
      () =>
          tester.platformDispatcher.platformBrightnessTestValue =
              Brightness.light,
    );

    // Material 那层主题的明暗：miuix 模式下 HomeShell 并不上树（首页是
    // MiuixHomeShell），所以直接拿 MaterialApp 自己的 Navigator 当锚点。
    Brightness materialBrightness(WidgetTester t) =>
        Theme.of(t.element(find.byType(Navigator).first)).brightness;

    // 走静态出厂配色（0xFF3482FF / 0xFF277AF7）当判据：跟 monet 无关，
    // 这样断言只反映「明暗档位有没有被系统亮度带着走」。
    await display.setUseCustomThemeColors(false);
    await display.setUiStyle(UiStyle.miuix);
    await display.setThemeMode(ThemeMode.system);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(miuixColors(tester).primary, miuixFactoryBlue);
    expect(materialBrightness(tester), Brightness.light);

    // 系统切成深色：miuix 配色与 Material 那层主题**同时**翻过去。
    // 回归点：以前 MiuixThemeController 与 MaterialApp.themeMode 各判一次
    // 明暗，系统亮度变了只翻一半（配色变了、没迁页的主题还停在老的那份）。
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(miuixColors(tester).primary, miuixFactoryBlueDark);
    expect(materialBrightness(tester), Brightness.dark);
  });

  testWidgets('miuix：关掉自定义颜色回出厂蓝，Material 分支不受影响', (tester) async {
    final display = await setUpApp(tester);

    await display.setThemeSeedColor(redSeed);
    await display.setUiStyle(UiStyle.miuix);
    await tester.pumpAndSettle();

    // 自定义颜色开着：种子色生效（monet 生成的偏红主色），不是出厂蓝
    final monetPrimary = miuixColors(tester).primary;
    expect(monetPrimary, isNot(miuixFactoryBlue));
    expect(
      monetPrimary.r,
      greaterThan(monetPrimary.b),
      reason: '红色种子应生成偏红主色',
    );

    // 关掉自定义颜色：种子色不再生效，回 HyperOS 出厂蓝
    await display.setUseCustomThemeColors(false);
    await tester.pumpAndSettle();
    expect(miuixColors(tester).primary, miuixFactoryBlue);
    expect(miuixColors(tester).background, const Color(0xFFFFFFFF));

    // 深色走 darkColorScheme 的出厂蓝
    await display.setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(miuixColors(tester).primary, miuixFactoryBlueDark);

    // 换回 Material：同一个开关在 Material 分支不参与配色
    await display.setThemeMode(ThemeMode.light);
    await display.setUiStyle(UiStyle.materialExpressive);
    await tester.pumpAndSettle();
    expect(display.useCustomThemeColors, isFalse);
    final materialColor = materialPrimary(tester);
    expect(materialColor, isNot(miuixFactoryBlue));
    expect(
      materialColor.r,
      greaterThan(materialColor.b),
      reason: 'Material 仍按种子色（红）生成主色',
    );
  });
}