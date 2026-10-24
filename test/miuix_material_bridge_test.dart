import 'package:flex_seed_scheme/flex_seed_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';

/// 按 app.dart 里 miuix 分支的结构搭一棵最小树：
/// MiuixThemeController → 桥出 ColorScheme → 喂给 AppTheme。
Widget _harness({
  required Color seed,
  bool? isDark,
  MiuixThemePaletteStyle palette = MiuixThemePaletteStyle.tonalSpot,
  required void Function(ColorScheme scheme, MiuixThemeData miuix) onBuild,
  Widget? child,
}) => MiuixThemeController(
  // 必须走 monet* 档：静态 system/light/dark 不吃 keyColor 与 paletteStyle
  colorSchemeMode: miuixColorSchemeModeOf(
    themeMode: switch (isDark) {
      true => ThemeMode.dark,
      false => ThemeMode.light,
      null => ThemeMode.system,
    },
  ),
  keyColor: seed,
  paletteStyle: palette,
  isDark: isDark,
  child: Builder(
    builder: (context) {
      final miuix = MiuixTheme.of(context);
      final scheme = materialSchemeFromMiuix(miuix.colors, miuix.brightness);
      onBuild(scheme, miuix);
      // 与 `_buildMiuixApp` 保持一致：输入装饰要归零，否则 Material 主题那套
      // filled/fillColor 会漏进 MiuixTextField 内层的 TextField。
      final theme = AppTheme.light()
          .copyWith(colorScheme: scheme)
          .copyWith(inputDecorationTheme: kMiuixNeutralInputDecoration);
      return MaterialApp(
        theme: theme,
        darkTheme: theme,
        themeMode: miuix.brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        home: Scaffold(
          body: Center(child: child ?? const _Probe()),
        ),
      );
    },
  ),
  );

class _Probe extends StatelessWidget {
  const _Probe();

  @override
  Widget build(BuildContext context) => Card(
    child: Text('探针', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
  );
}

void main() {
  group('配色桥', () {
    testWidgets('miuix 主色原样映到 ColorScheme，Material 组件能渲染', (tester) async {
      ColorScheme? scheme;
      MiuixThemeData? miuix;
      await tester.pumpWidget(
        _harness(
          seed: const Color(0xFF386A20),
          onBuild: (s, m) {
            scheme = s;
            miuix = m;
          },
        ),
      );
      await tester.pump();

      expect(scheme, isNotNull);
      expect(scheme!.primary, miuix!.colors.primary);
      expect(scheme!.onPrimary, miuix!.colors.onPrimary);
      expect(scheme!.primaryContainer, miuix!.colors.primaryContainer);
      expect(scheme!.secondary, miuix!.colors.secondary);
      expect(scheme!.error, miuix!.colors.error);
      expect(scheme!.surface, miuix!.colors.surface);
      expect(scheme!.onSurface, miuix!.colors.onSurface);
      expect(scheme!.outline, miuix!.colors.outline);
      expect(scheme!.outlineVariant, miuix!.colors.dividerLine);
      expect(scheme!.surfaceTint, Colors.transparent);

      // 桥的用途就是让还没迁走的 Material 页面能正常上色，所以得真渲染出来
      expect(find.text('探针'), findsOneWidget);
      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('深色下亮度跟着 miuix 走', (tester) async {
      ColorScheme? scheme;
      MiuixThemeData? miuix;
      await tester.pumpWidget(
        _harness(
          seed: Colors.blue,
          isDark: true,
          onBuild: (s, m) {
            scheme = s;
            miuix = m;
          },
        ),
      );
      await tester.pump();

      expect(miuix!.brightness, Brightness.dark);
      expect(scheme!.brightness, Brightness.dark);
      expect(scheme!.primary, miuix!.colors.primary);
      expect(find.text('探针'), findsOneWidget);
    });

    testWidgets('miuix 没有 plain tertiary，用 primaryVariant 顶上', (tester) async {
      ColorScheme? scheme;
      MiuixThemeData? miuix;
      await tester.pumpWidget(
        _harness(
          seed: Colors.blue,
          onBuild: (s, m) {
            scheme = s;
            miuix = m;
          },
        ),
      );
      await tester.pump();

      expect(scheme!.tertiary, miuix!.colors.primaryVariant);
      expect(scheme!.onTertiary, miuix!.colors.onPrimaryVariant);
      expect(scheme!.tertiaryContainer, miuix!.colors.tertiaryContainer);
    });

    testWidgets('不同 palette 出来的配色确实不一样', (tester) async {
      final primaries = <MiuixThemePaletteStyle, Color>{};
      for (final palette in [
        MiuixThemePaletteStyle.monochrome,
        MiuixThemePaletteStyle.vibrant,
        MiuixThemePaletteStyle.fruitSalad,
      ]) {
        await tester.pumpWidget(
          _harness(
            seed: const Color(0xFF386A20),
            palette: palette,
            onBuild: (_, m) => primaries[palette] = m.colors.primary,
          ),
        );
        await tester.pump();
      }
      expect(primaries.length, 3);
      expect(primaries.values.toSet().length, greaterThan(1));
    });
  });

  group('miuix 输入框不该被 Material 输入装饰污染', () {
    test('AppTheme 自己那份还是填充的（别顺手把 Material 侧也改了）', () {
      expect(AppTheme.light().inputDecorationTheme.filled, isTrue);
      expect(AppTheme.dark().inputDecorationTheme.filled, isTrue);
    });

    test('归零后的这份不填充、不描边', () {
      expect(kMiuixNeutralInputDecoration.filled, isFalse);
      expect(kMiuixNeutralInputDecoration.border, InputBorder.none);
      expect(kMiuixNeutralInputDecoration.focusedBorder, InputBorder.none);
      expect(kMiuixNeutralInputDecoration.enabledBorder, InputBorder.none);
    });

    testWidgets('MiuixTextField 内层的 Material TextField 解析出来是「不填充」', (tester) async {
      // MiuixTextField 的 InputDecoration 没写 filled，applyDefaults 会把主题
      // 那份补进去 —— 主题没归零时这里解析成 true，miuix 输入框就会在
      // secondaryContainer 底色上再叠一层灰，看着像「一圈神秘包边」。
      await tester.pumpWidget(
        _harness(
          seed: const Color(0xFF386A20),
          onBuild: (_, _) {},
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: MiuixTextField(label: '名称'),
          ),
        ),
      );
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      final resolved = field.decoration!.applyDefaults(
        kMiuixNeutralInputDecoration,
      );
      expect(resolved.filled, isFalse);
      expect(resolved.fillColor, Colors.transparent);
    });
  });

  group('设置映射', () {
    test('paletteStyle 映射对得上的九个 Flex 变体', () {
      expect(
        miuixPaletteStyleOf(FlexSchemeVariant.tonalSpot),
        MiuixThemePaletteStyle.tonalSpot,
      );
      expect(
        miuixPaletteStyleOf(FlexSchemeVariant.fidelity),
        MiuixThemePaletteStyle.fidelity,
      );
      expect(
        miuixPaletteStyleOf(FlexSchemeVariant.monochrome),
        MiuixThemePaletteStyle.monochrome,
      );
      expect(
        miuixPaletteStyleOf(FlexSchemeVariant.neutral),
        MiuixThemePaletteStyle.neutral,
      );
      expect(
        miuixPaletteStyleOf(FlexSchemeVariant.vibrant),
        MiuixThemePaletteStyle.vibrant,
      );
      expect(
        miuixPaletteStyleOf(FlexSchemeVariant.expressive),
        MiuixThemePaletteStyle.expressive,
      );
      expect(
        miuixPaletteStyleOf(FlexSchemeVariant.content),
        MiuixThemePaletteStyle.content,
      );
      expect(
        miuixPaletteStyleOf(FlexSchemeVariant.rainbow),
        MiuixThemePaletteStyle.rainbow,
      );
      expect(
        miuixPaletteStyleOf(FlexSchemeVariant.fruitSalad),
        MiuixThemePaletteStyle.fruitSalad,
      );
    });

    test('Flex 独有的变体有兜底，不会落到同一档', () {
      // switch 是穷尽的（编译器保证），这里只钉住几个兜底选择本身
      expect(
        miuixPaletteStyleOf(FlexSchemeVariant.material),
        MiuixThemePaletteStyle.tonalSpot,
      );
      expect(
        miuixPaletteStyleOf(FlexSchemeVariant.vivid),
        MiuixThemePaletteStyle.vibrant,
      );
      expect(
        miuixPaletteStyleOf(FlexSchemeVariant.oneHue),
        MiuixThemePaletteStyle.monochrome,
      );
      expect(
        miuixPaletteStyleOf(FlexSchemeVariant.candyPop),
        MiuixThemePaletteStyle.fruitSalad,
      );
    });

    test('一律走 monet 档：静态模式会忽略种子色与 palette', () {
      expect(
        miuixColorSchemeModeOf(themeMode: ThemeMode.system),
        MiuixColorSchemeMode.monetSystem,
      );
      expect(
        miuixColorSchemeModeOf(themeMode: ThemeMode.light),
        MiuixColorSchemeMode.monetLight,
      );
      expect(
        miuixColorSchemeModeOf(themeMode: ThemeMode.dark),
        MiuixColorSchemeMode.monetDark,
      );
    });

    test('字重偏移以 400 为基准、100 一档，并夹在 miuix 能吃的范围内', () {
      expect(miuixFontWeightAdjustmentOf(400), 0);
      expect(miuixFontWeightAdjustmentOf(500), 100);
      expect(miuixFontWeightAdjustmentOf(700), 300);
      expect(miuixFontWeightAdjustmentOf(300), -100);
      // SettingsService 把字重夹在 300..800，超出也不该给出离谱的偏移
      expect(miuixFontWeightAdjustmentOf(800), 400);
      expect(miuixFontWeightAdjustmentOf(100), -100);
      expect(miuixFontWeightAdjustmentOf(900), 400);
    });
  });
}
