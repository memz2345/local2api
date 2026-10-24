// 「文字粗细」页退出确认弹窗：Material 走居中 AlertDialog、Miuix 走
// showMiuixDialog（贴底卡片）。miuix 那一半在 miuix_screens_test.dart 里，
// 那份基础设施（MiuixThemeController 搭树）已经现成。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/screens/font_weight_screen.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/ui/app_theme.dart';
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

  /// 把页面 push 到一个空 base 之上：保存后的 pop 不会把路由栈清空。
  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsService>.value(
        value: settings,
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(MaterialPageRoute<void>(builder: (_) => const FontWeightScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets('改过没保存就返回：弹居中 AlertDialog，点「保存」落盘并退出', (tester) async {
    await pumpScreen(tester);

    await tester.ensureVisible(find.text('Bold · 700'));
    await tester.tap(find.text('Bold · 700'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('有未保存的调整'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('不保存'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(settings.fontWeight, 700.0);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('文字粗细'), findsNothing, reason: '保存完应当退出页面');
  });

  testWidgets('点「取消」留在页面上继续改（不落盘也不退出）', (tester) async {
    await pumpScreen(tester);

    await tester.ensureVisible(find.text('Bold · 700'));
    await tester.tap(find.text('Bold · 700'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('文字粗细'), findsWidgets, reason: '取消 = 接着调，不能退出');
    expect(settings.fontWeight, 400.0);
  });
}
