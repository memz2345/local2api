import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'miuix_finders.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/screens/miuix/miuix_display_scale_page.dart';
import 'package:local2api/screens/miuix/miuix_display_settings_screen.dart';
import 'package:local2api/screens/miuix/miuix_font_weight_screen.dart';
import 'package:local2api/screens/miuix/miuix_theme_selector_screen.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';
import 'package:local2api/widgets/color_palette.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/widgets/miuix/miuix_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsService settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsService();
  });

  tearDown(() {
    settings.dispose();
  });

  /// 按 app.dart 里 miuix 分支的结构搭树：SettingsService → MiuixThemeController
  /// （monet 档）→ 配色桥 → MaterialApp。目标页 push 到一个占位 base 之上，
  /// 这样文字粗细页保存时的 Navigator.pop 不会把路由栈清空。
  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsService>.value(
        value: settings,
        child: MiuixThemeController(
          colorSchemeMode: miuixColorSchemeModeOf(themeMode: ThemeMode.light),
          keyColor: const Color(0xFF386A20),
          child: Builder(
            builder: (context) {
              final miuix = MiuixTheme.of(context);
              final scheme = materialSchemeFromMiuix(
                miuix.colors,
                miuix.brightness,
              );
              return MaterialApp(
                // 不钉 locale 的话测试环境默认 en_US，中文断言全对不上
                locale: const Locale('zh', 'CN'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: AppTheme.light().copyWith(colorScheme: scheme),
                home: const SizedBox.shrink(),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets('miuix 显示缩放页渲染，点预设档位写入 displayScale', (tester) async {
    await pumpScreen(tester, const MiuixDisplayScalePage());

    expect(find.text('显示缩放'), findsOneWidget);
    expect(find.text('精细调节'), findsOneWidget);
    expect(find.text('快捷预设'), findsOneWidget);
    expect(find.byType(MiuixBlurTopBar, skipOffstage: false), findsOneWidget);
    expect(find.byType(MiuixSlider), findsOneWidget);
    expect(settings.displayScale, 1.0);

    await tester.ensureVisible(find.text('125%'));
    await tester.tap(find.text('125%'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(settings.displayScale, 1.25);
  });

  testWidgets('miuix 文字粗细页渲染，选预设后保存写入 fontWeight', (tester) async {
    await pumpScreen(tester, const MiuixFontWeightScreen());

    expect(find.text('文字粗细'), findsOneWidget);
    expect(find.text('精细调节'), findsOneWidget);
    expect(find.text('快捷预设'), findsOneWidget);
    expect(find.byType(MiuixSlider), findsOneWidget);
    expect(settings.fontWeight, 400.0);

    await tester.ensureVisible(find.text('Bold · 700'));
    await tester.tap(find.text('Bold · 700'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // 顶栏保存（对勾）落盘并 pop 回 base。
    // 页面里有两个 check（顶栏保存 + 预设行选中标记），限定在顶栏里找。
    await tester.tap(
      find.descendant(
        of: find.byType(MiuixBlurTopBar),
        matching: miuixIcon(AppIconNames.check),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(settings.fontWeight, 700.0);
  });

  testWidgets('miuix 文字粗细页：改过没保存就返回，弹 miuix 对话框，选「不保存」直接走', (
    tester,
  ) async {
    await pumpScreen(tester, const MiuixFontWeightScreen());

    await tester.ensureVisible(find.text('Bold · 700'));
    await tester.tap(find.text('Bold · 700'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // 顶栏返回：有未保存的改动，先弹对话框
    await tester.tap(
      find.descendant(
        of: find.byType(MiuixBlurTopBar),
        matching: miuixIcon(AppIconNames.back),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('有未保存的调整'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('不保存'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    // 圆角卡片（squircle）而不是 Material AlertDialog
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(find.text('不保存'));
    await tester.pumpAndSettle();

    // 没落盘，页面也退掉了
    expect(settings.fontWeight, 400.0);
    expect(find.text('文字粗细'), findsNothing);
  });

  testWidgets('miuix 主题页渲染，跟随系统开关写入 useDynamicColor', (tester) async {
    await pumpScreen(tester, const MiuixThemeSelectorScreen());

    expect(find.text('主题'), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('配色'), findsOneWidget);
    expect(find.text('选择颜色'), findsOneWidget);
    expect(find.byType(ColorPalette), findsWidgets);
    expect(settings.useDynamicColor, false);

    await tester.ensureVisible(find.text('跟随系统配色'));
    await tester.tap(find.text('跟随系统配色'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(settings.useDynamicColor, true);
  });

  testWidgets('miuix 主题页：新建主题弹 miuix 对话框，「创建」随名称可用性切换', (tester) async {
    await pumpScreen(tester, const MiuixThemeSelectorScreen());

    // FAB 打开「创建自定义主题」表单
    await tester.tap(find.byType(MiuixFloatingActionButton));
    await tester.pumpAndSettle();

    // miuix 对话框（squircle 卡片 + 等宽药丸动作行），不是 Material Dialog
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('创建自定义主题'), findsOneWidget);
    expect(find.byType(MiuixDialogButton), findsNWidgets(2));

    MiuixDialogButton buttonOf(String label) =>
        tester.widget<MiuixDialogButton>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(MiuixDialogButton),
          ),
        );

    // 名称为空 → 「创建」禁用；输入后解禁（动作行在同一个 StatefulBuilder 里）
    expect(buttonOf('创建').onPressed, isNull);
    await tester.enterText(find.byType(TextField).first, '我的主题');
    await tester.pumpAndSettle();
    expect(buttonOf('创建').onPressed, isNotNull);

    // 「取消」关掉对话框，不落盘
    await tester.tap(
      find.ancestor(
        of: find.text('取消'),
        matching: find.byType(MiuixDialogButton),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('创建自定义主题'), findsNothing);
    expect(settings.customThemes, isEmpty);
  });

  testWidgets('miuix 显示设置页渲染，纯黑开关写入 + 跳 miuix 子页', (tester) async {
    await pumpScreen(tester, const MiuixDisplaySettingsScreen());

    expect(find.text('显示'), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('个性化'), findsOneWidget);
    expect(find.text('主题配色'), findsOneWidget);
    expect(find.byType(MiuixBlurTopBar, skipOffstage: false), findsOneWidget);
    expect(settings.isPureBlackMode, false);

    await tester.ensureVisible(find.text('纯黑深色模式'));
    await tester.tap(find.text('纯黑深色模式'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(settings.isPureBlackMode, true);

    // 点「显示缩放」行跳到 miuix 版子页（而不是 Material 版）
    await tester.ensureVisible(find.text('显示缩放'));
    await tester.tap(find.text('显示缩放'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.byType(MiuixDisplayScalePage), findsOneWidget);
  });
}
