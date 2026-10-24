import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/usage_stats.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/token_calendar_page.dart';
import 'package:local2api/ui/miuix/miuix_token_calendar_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归：用量日历的「左右滑动切月」与「回今天」悬浮按钮。
///
/// 两条判据（两份 UI 共用）：
/// 1. 在月历上横扫 ≥ 阈值速度 → 月份跟着走（向左 = 下个月）；
/// 2. 「回今天」只在**不看当月**时出现，中文界面写「今」、其余语言用图标。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await usageStats.load();
    usageStats.clear();
  });

  tearDown(() => usageStats.clear());

  Future<void> pumpCalendar(
    WidgetTester tester,
    Widget page, {
    Locale locale = const Locale('zh', 'CN'),
  }) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: page,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  String monthLabel(WidgetTester tester, DateTime month) =>
      MaterialLocalizations.of(
        tester.element(find.byType(Navigator)),
      ).formatMonthYear(month);

  /// 在月历网格上横扫：dx < 0 = 手指向左（看下个月）。
  Future<void> swipeMonth(WidgetTester tester, double dx) async {
    final grid = find.byType(GridView).first;
    final center = tester.getCenter(grid);
    // 用 fling 而不是 drag：`dragFrom` 的每步 16ms 会把速度摊平，
    // 达不到手势里的速度阈值；fling 能显式给速度。
    await tester.flingFrom(center, Offset(dx, 0), 900);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  testWidgets('手指向左滑 → 下个月；向右滑 → 上个月', (tester) async {
    await pumpCalendar(tester, const TokenCalendarPage());

    final now = DateTime.now();
    expect(find.text(monthLabel(tester, DateTime(now.year, now.month))),
        findsOneWidget);

    // 向左滑：下个月
    await swipeMonth(tester, -260);
    expect(
      find.text(monthLabel(tester, DateTime(now.year, now.month + 1))),
      findsOneWidget,
    );

    // 再向右滑两次：上个月 → 上上个月
    await swipeMonth(tester, 260);
    expect(find.text(monthLabel(tester, DateTime(now.year, now.month))),
        findsOneWidget);
    await swipeMonth(tester, 260);
    expect(
      find.text(monthLabel(tester, DateTime(now.year, now.month - 1))),
      findsOneWidget,
    );
  });

  testWidgets('慢速长拖也翻月（不只看速度）', (tester) async {
    await pumpCalendar(tester, const TokenCalendarPage());

    final now = DateTime.now();
    final grid = find.byType(GridView).first;
    final center = tester.getCenter(grid);
    // 慢拖：dragFrom 每步 16ms，速度被摊得很平，只能靠位移判据。
    await tester.dragFrom(center, const Offset(-120, 0));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(
      find.text(monthLabel(tester, DateTime(now.year, now.month + 1))),
      findsOneWidget,
    );
  });

  testWidgets('当前月不显示「回今天」，翻走之后才出现', (tester) async {
    await pumpCalendar(tester, const TokenCalendarPage());

    expect(find.byType(FloatingActionButton), findsNothing);
    // 顶栏那颗「今天」文字按钮一直在（浮动的是右下角那颗）
    expect(find.text('今天'), findsOneWidget);

    await swipeMonth(tester, -260);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    // 中文界面写「今」而不是图标
    expect(find.text('今'), findsOneWidget);
    expect(find.byIcon(Icons.today), findsNothing);
  });

  testWidgets('点「回今天」回到当月，按钮随之收起', (tester) async {
    await pumpCalendar(tester, const TokenCalendarPage());

    await swipeMonth(tester, -260);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    final now = DateTime.now();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text(monthLabel(tester, DateTime(now.year, now.month))),
        findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('英文界面用图标而不是「今」', (tester) async {
    await pumpCalendar(
      tester,
      const TokenCalendarPage(),
      locale: const Locale('en'),
    );

    await swipeMonth(tester, -260);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byIcon(Icons.today), findsOneWidget);
    expect(find.text('今'), findsNothing);
  });

  testWidgets('miuix 版同样能横扫切月并给出「回今天」', (tester) async {
    await pumpCalendar(tester, const MiuixTokenCalendarPage());

    final now = DateTime.now();
    expect(find.byType(FloatingActionButton), findsNothing);

    await swipeMonth(tester, -260);
    expect(
      find.text(monthLabel(tester, DateTime(now.year, now.month + 1))),
      findsOneWidget,
    );

    // miuix 的 FAB 是自己那一套（不是 Material 的 FloatingActionButton）
    expect(find.text('今'), findsOneWidget);

    await tester.tap(find.text('今'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text(monthLabel(tester, DateTime(now.year, now.month))),
        findsOneWidget);
    expect(find.text('今'), findsNothing);
  });
}
