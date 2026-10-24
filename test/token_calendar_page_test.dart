import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/screens/font_weight_screen.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/services/usage_stats.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/miuix/miuix_token_calendar_page.dart';
import 'package:local2api/ui/token_calendar_page.dart';
import 'package:local2api/ui/token_stats_page.dart';
import 'package:local2api/ui/widgets/common.dart' show pushPage;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

TokenUsage _rec({
  required DateTime at,
  required String model,
  required int input,
  required int output,
  int hit = 0,
}) => TokenUsage(
  timeMs: at.millisecondsSinceEpoch,
  model: model,
  upstream: 'OpenCode Zen',
  lane: 'space-bunny-free',
  input: input,
  output: output,
  cacheHit: hit,
  cacheMiss: input - hit,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await usageStats.load();
    usageStats.clear();
  });

  tearDown(() => usageStats.clear());

  void seed() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    usageStats
      ..add(
        _rec(at: today, model: 'zen-free', input: 1000, output: 200, hit: 800),
      )
      ..add(_rec(at: today, model: 'local', input: 40, output: 10))
      ..add(
        _rec(
          at: today.subtract(const Duration(days: 1)),
          model: 'zen-free',
          input: 500,
          output: 100,
        ),
      );
  }

  /// 把日历页 push 到一个占位 base 上，pop 回来的焦点交给 [onResult]。
  Future<void> pumpCalendar(
    WidgetTester tester,
    Widget page,
    ValueChanged<TokenStatsFocus?> onResult,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              final focus = await Navigator.of(ctx).push<TokenStatsFocus>(
                MaterialPageRoute<TokenStatsFocus>(builder: (_) => page),
              );
              onResult(focus);
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('Material 版：月历渲染 + 点日期弹当天活动 + 点卡片带回焦点', (
    tester,
  ) async {
    seed();
    TokenStatsFocus? got;
    await pumpCalendar(tester, const TokenCalendarPage(), (f) => got = f);

    expect(find.text('用量日历'), findsOneWidget);
    // 内联的「当天活动」在日历下方，先滚过去
    await tester.scrollUntilVisible(
      find.text('zen-free'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('zen-free'), findsWidgets);

    // 点今天的格子 → 底部弹出那天的活动
    final todayCell = find.descendant(
      of: find.byType(GridView),
      matching: find.text('${DateTime.now().day}'),
    );
    expect(todayCell, findsWidgets);
    await tester.tap(todayCell.first);
    await tester.pumpAndSettle();
    expect(find.textContaining('的活动'), findsWidgets);

    // 点弹窗里那张模型卡片 → 带着「那天 + 这个模型」回统计页
    await tester.tap(find.text('zen-free').last);
    await tester.pumpAndSettle();
    // 回到占位页说明页面已 pop
    expect(find.text('go'), findsOneWidget);
    await tester.pump();
    expect(got, isNotNull);
    expect(got!.model, 'zen-free');
    final today = DateTime.now();
    expect(got!.day.year, today.year);
    expect(got!.day.month, today.month);
    expect(got!.day.day, today.day);
  });

  testWidgets('miuix 版：同样能从月历挑到模型并带回焦点', (tester) async {
    seed();
    await pumpCalendar(tester, const MiuixTokenCalendarPage(), (_) {});

    expect(find.text('用量日历'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('zen-free'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('zen-free'), findsWidgets);

    final todayCell = find.descendant(
      of: find.byType(GridView),
      matching: find.text('${DateTime.now().day}'),
    );
    await tester.tap(todayCell.first);
    await tester.pumpAndSettle();
    expect(find.textContaining('的活动'), findsWidgets);

    await tester.tap(find.text('zen-free').last);
    await tester.pumpAndSettle();
    expect(find.text('go'), findsOneWidget);
  });

  testWidgets('星期表头是日-六开头，且翻月时固定不动（只有格子平移）', (tester) async {
    seed();
    await pumpCalendar(tester, const MiuixTokenCalendarPage(), (_) {});

    // 表头：日 在最前、一 在其后（周日开头）
    final sun = find.text('日');
    final mon = find.text('一');
    expect(sun, findsOneWidget);
    expect(mon, findsOneWidget);
    final sunX = tester.getTopLeft(sun).dx;
    final monX = tester.getTopLeft(mon).dx;
    expect(sunX, lessThan(monX), reason: '周日应排在最左（日-六）');
    final sunY = tester.getTopLeft(sun).dy;

    // 翻月：网格换成新的，但表头原地不动
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(find.text('日'), findsOneWidget);
    expect(tester.getTopLeft(find.text('日')).dx, sunX);
    expect(tester.getTopLeft(find.text('日')).dy, sunY);
  });

  testWidgets('统计页 → 日历 → 点卡片：回到统计页并切到那天的那个模型', (tester) async {
    seed();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: const TokenStatsPage(),
      ),
    );
    await tester.pumpAndSettle();

    // 顶栏的日历入口
    await tester.tap(find.byTooltip('日历'));
    await tester.pumpAndSettle();
    expect(find.text('用量日历'), findsOneWidget);

    final todayCell = find.descendant(
      of: find.byType(GridView),
      matching: find.text('${DateTime.now().day}'),
    );
    await tester.tap(todayCell.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('zen-free').last);
    await tester.pumpAndSettle();

    // 回到统计页：模型切到 zen-free，时间范围多出「那一天」这一片
    expect(find.text('Token 统计'), findsWidgets);
    expect(find.text('zen-free'), findsWidgets);
    final now = DateTime.now();
    expect(find.text('${now.month}/${now.day}'), findsWidgets);
  });

  // ------------------------------------------------------------ 未保存提示

  /// 读页面上那个 PopScope 的 canPop：false 就说明退出会被拦下来问一句。
  bool canPopOf(WidgetTester tester) {
    final found = find.byWidgetPredicate((w) => w is PopScope<Object>);
    expect(found, findsOneWidget);
    return (found.evaluate().single.widget as PopScope<Object>).canPop;
  }

  testWidgets('文字粗细页：改了没保存 → 退出被拦下；点了保存 → 放行并落盘', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    // 毛玻璃碎片渲染在测试里画不出子内容，走传统 BackdropFilter 分支
    SettingsService.fragmentRenderingEnabled = false;
    addTearDown(() => SettingsService.fragmentRenderingEnabled = true);
    final settings = SettingsService();
    addTearDown(settings.dispose);
    final before = settings.fontWeight;

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsService>.value(
        value: settings,
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => pushPage(ctx, const FontWeightScreen()),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // 没动过：退出直接放行
    expect(canPopOf(tester), isTrue);

    // 把滑块拖到最右：900（默认 400），页面里就是「改了还没确认」
    await tester.drag(find.byType(Slider), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(find.text('900'), findsWidgets);
    // 改了没确认 → 退出会被 PopScope 拦下来问一句
    expect(canPopOf(tester), isFalse);

    // 点「保存并应用」：值落盘（settings clamp 到 800），而且放行退出
    await tester.scrollUntilVisible(
      find.text('保存并应用'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('保存并应用'));
    await tester.pumpAndSettle();
    expect(settings.fontWeight, isNot(before));
    expect(settings.fontWeight, 800);
    // 保存完不会再被多问一句，页面已经退回占位页
    expect(find.byType(FontWeightScreen), findsNothing);
  });

  testWidgets('文字粗细页：没改动就直接退出，不该多问一句', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsService>.value(
        value: settings,
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => pushPage(ctx, const FontWeightScreen()),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.byType(FontWeightScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.text('有未保存的调整'), findsNothing);
    expect(find.text('go'), findsOneWidget);
  });
}
