// miuix 说明卡（InstallerX `ui/page/miuix/widgets/MiuixCards.kt` 的 `TipCard`
// 配方）回归：
//   1. 淡蓝底 = `primaryContainer` **25% 透明** + primary 蓝字 —— 直接拿整块
//      primaryContainer 打底时，全默认（静态 HyperOS）配色下那是中蓝，
//      蓝底蓝字看不清（就是之前那张看着很奇怪的卡）；
//   2. 行尾 X 关掉后按 id 记住：重进页面、重启（重新 load）都不再显示，
//      别的 id 不受影响。
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_info_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // 关闭记录是静态的、跨用例存活：用一次 load() 从（空的）mock prefs 重置
    await SettingsService().load();
  });

  Future<void> pumpCard(WidgetTester tester, Widget card) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MiuixThemeController(
        // 全默认（静态 HyperOS）配色：就是「全默认颜色」那一档
        colorSchemeMode: MiuixColorSchemeMode.light,
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: Scaffold(
            body: Padding(padding: const EdgeInsets.all(16), child: card),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('出厂配色下：淡蓝底 + primary 蓝字，不再是蓝底蓝字', (tester) async {
    await pumpCard(tester, const MiuixInfoCard(text: '说明文字'));

    final colors = MiuixTheme.of(
      tester.element(find.byType(MiuixInfoCard)),
    ).colors;
    final card = tester.widget<MiuixGroupCard>(
      find.descendant(
        of: find.byType(MiuixInfoCard),
        matching: find.byType(MiuixGroupCard),
      ),
    );
    final bg = card.colors!.color;
    expect(bg, colors.primaryContainer.withValues(alpha: 0.25));
    expect(
      bg.a,
      lessThan(0.5),
      reason: '整块 primaryContainer 打底就是之前那个蓝底蓝字的底',
    );

    // 文字是 primary 蓝（find.text 命中的是 MiuixText 里层的 Text）
    final label = tester.widget<MiuixText>(
      find.ancestor(
        of: find.text('说明文字'),
        matching: find.byType(MiuixText),
      ),
    );
    expect(label.color, colors.primary);

    // 底是浅色、字是深色：方向对了才谈得上对比度
    final composited = Color.alphaBlend(bg, Colors.white);
    expect(composited.computeLuminance(), greaterThan(0.6));
    expect(colors.primary.computeLuminance(), lessThan(0.4));
  });

  testWidgets('行尾 X 关掉后按 id 记住：重进页面 / 重启都还是关着的', (tester) async {
    const card = MiuixDismissibleInfoCard(id: 'intro.test', text: '说明文字');
    await pumpCard(tester, card);

    expect(find.text('说明文字'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('说明文字'), findsNothing);

    // 重建整棵树（相当于重进页面）：这条 id 还是关着的
    await pumpCard(tester, card);
    expect(find.text('说明文字'), findsNothing);

    // 落盘了：换一份 SettingsService 从持久化里读回来（相当于重启）
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList('local2api.dismissedInfoCards'),
      contains('intro.test'),
    );
    final restarted = SettingsService();
    addTearDown(restarted.dispose);
    await restarted.load();
    await pumpCard(tester, card);
    expect(find.text('说明文字'), findsNothing);

    // 别的 id 不受影响
    await pumpCard(
      tester,
      const MiuixDismissibleInfoCard(id: 'intro.other', text: '另一条说明'),
    );
    expect(find.text('另一条说明'), findsOneWidget);
  });
}