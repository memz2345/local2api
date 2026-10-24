// 「跟随系统配色」在 miuix 下的回归。
//
// 背景：flutter_miuix 在没有 keyColor 时会走 `miuixPlatformDynamicColors`，
// 那个函数调的是 DynamicColorPlugin.getAccentColor() —— 该方法的原生实现只有
// macOS 10.14+ / Windows Vista+ / GTK。**Android 侧的 Kotlin 插件只认
// getCorePalette**，OptionalMethodChannel 对没实现的方法直接回 null，于是
// miuix 永远掉回固定种子 0xFF6750A4（monetSystemColors），用户在设置里开了
// 「跟随系统配色」跟没开一个样。
//
// 修法：AppDynamicColorBuilder 已经拿到系统取色（getCorePalette /
// getAccentColor 两路都有），把它的 primary 直接喂给 MiuixThemeController 的
// keyColor —— 非空时走同步的 HCT 计算，不再碰那条在安卓上必然失效的异步取色。
//
// 这个用例把「Android 现状」原样模拟出来：getCorePalette 有值、
// getAccentColor 回 null。修法被撤掉的话，配色会变成 miuix 的固定种子色，
// 断言立刻红。
import 'dart:typed_data';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/services/app_settings.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/src/enums.dart';
import 'package:local2api/ui/app.dart';
import 'package:local2api/ui/miuix/miuix_home_shell.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 系统动态取色的种子（跟应用里手挑的种子色明显不同，好分辨）。
  const systemSeed = 0xFF0088CC;
  /// 用户在设置里手挑的种子色。
  const userSeed = 0xFFE53935;
  /// miuix 拿不到系统取色时的固定兜底种子（0xFF6750A4）。
  const miuixFallbackSeed = 0xFF6750A4;

  const dynamicColorChannel = 'io.material.plugins/dynamic_color';

  void mockPlatformColors() {
    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // ignore: deprecated_member_use
    final palette = CorePalette.of(systemSeed);
    binaryMessenger.setMockMethodCallHandler(
      const MethodChannel(dynamicColorChannel),
      (call) async {
        switch (call.method) {
          // 安卓上有这一路（wallpaper 取色）。
          case 'getCorePalette':
            // ⚠️ 必须是 Int64List：标准编解码器把普通 List 解回 List<Object?>，
            // 而 dynamic_color 那边写的是 `CorePalette.fromList(result.toList())`
            // —— List<Object?>.toList() 不是 List<int>，会当场抛类型错误。
            // Int64List 本身是 List<int>，过得了那道检查。
            // ignore: deprecated_member_use
            return Int64List.fromList(palette.asList());
          // 安卓上没有这一路 —— 这正是原 bug 的根源。
          case 'getAccentColor':
            return null;
        }
        return null;
      },
    );
    addTearDown(() {
      binaryMessenger.setMockMethodCallHandler(
        const MethodChannel(dynamicColorChannel),
        null,
      );
    });
  }

  Future<SettingsService> setUpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2800);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

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

  testWidgets('开了「跟随系统配色」：miuix 吃系统取色，不是固定种子', (tester) async {
    mockPlatformColors();
    final display = await setUpApp(tester);

    await display.setUseCustomThemeColors(true);
    await display.setThemeSeedColor(const Color(userSeed));
    await display.setUiStyle(UiStyle.miuix);
    await display.setThemeMode(ThemeMode.light);
    // 关着的时候：按用户手挑的种子色生成。
    await display.setUseDynamicColor(false);
    await tester.pumpAndSettle();
    final fromUserSeed = miuixColors(tester).primary;

    // 打开「跟随系统配色」。
    await display.setUseDynamicColor(true);
    await tester.pumpAndSettle();
    final fromSystem = miuixColors(tester).primary;

    // 期望值：拿系统调色板的 primary 当种子、走 miuix 同一套 HCT 计算。
    // ignore: deprecated_member_use
    final systemPalette = CorePalette.of(systemSeed);
    final expected = miuixColorsFromSeed(
      seed: systemPalette.toColorScheme().primary,
      colorSpec: MiuixThemeColorSpec.spec2021,
      paletteStyle: MiuixThemePaletteStyle.tonalSpot,
      dark: false,
    ).primary;
    expect(fromSystem, expected);

    // 两条明确的反例：既不是 miuix 的固定兜底种子色，也不是用户的种子色。
    // ignore: deprecated_member_use
    final fallback = miuixColorsFromSeed(
      seed: const Color(miuixFallbackSeed),
      colorSpec: MiuixThemeColorSpec.spec2021,
      paletteStyle: MiuixThemePaletteStyle.tonalSpot,
      dark: false,
    ).primary;
    expect(
      fromSystem,
      isNot(fallback),
      reason: '不该掉回 miuix 的固定种子（getAccentColor 在安卓上就是没有的）',
    );
    expect(
      fromSystem,
      isNot(fromUserSeed),
      reason: '系统取色开着时手挑的种子色应当让位',
    );
  });
}
