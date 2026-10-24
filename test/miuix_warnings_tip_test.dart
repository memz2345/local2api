import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/miuix/miuix_dashboard_page.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 仪表盘风险提示（图2 样式：一个 info 一张卡 + 各自可关）：
///   1. 显示在「仪表盘」标题与出血状态大卡之间，两条提示是两张独立的卡；
///   2. 每张卡的 X 只关自己那条，且按「警告组合签名」持久化（重启/重建后不再弹）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConfigStore configStore;
  late ServerController controller;
  late SettingsService displaySettings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    configStore = ConfigStore();
    await configStore.load();
    controller = ServerController(configStore);
    displaySettings = SettingsService();
  });

  tearDown(() {
    configStore.dispose();
    controller.dispose();
    displaySettings.dispose();
  });

  Future<void> pumpDashboard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: displaySettings),
        ],
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
                locale: const Locale('zh', 'CN'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: AppTheme.light().copyWith(colorScheme: scheme),
                home: Scaffold(body: MiuixDashboardPage(controller: controller)),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets('风险提示显示在标题与出血大卡之间，一个 info 一张卡', (tester) async {
    await pumpDashboard(tester);

    final tip = find.text('未配置密钥');
    expect(tip, findsOneWidget);
    expect(find.text('对所有来源开放'), findsOneWidget);

    // 两张提示是两张独立的卡（一个 info 一张卡，一卡不装两条）
    final keysCard = find.ancestor(
      of: find.text('未配置密钥'),
      matching: find.byType(MiuixGroupCard),
    );
    final rulesCard = find.ancestor(
      of: find.text('对所有来源开放'),
      matching: find.byType(MiuixGroupCard),
    );
    expect(keysCard, findsOneWidget);
    expect(rulesCard, findsOneWidget);
    expect(
      identical(tester.widget(keysCard), tester.widget(rulesCard)),
      isFalse,
      reason: '一个 info 一张卡，两条提示不能挤在同一张卡里',
    );

    // 出血大卡（状态卡）的「已停止」状态标题在提示条下方
    final tipDy = tester.getTopLeft(tip).dy;
    final cardDy = tester.getTopLeft(find.text('已停止')).dy;
    expect(tipDy, lessThan(cardDy), reason: '提示条应在出血大卡上方');
  });

  testWidgets('每张卡的 X 只关自己那条，重建后仍不显示（签名持久化）', (tester) async {
    await pumpDashboard(tester);
    expect(find.text('未配置密钥'), findsOneWidget);
    expect(find.text('对所有来源开放'), findsOneWidget);

    // 先关「未配置密钥」：另一条不受影响
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('未配置密钥'), findsNothing);
    expect(find.text('对所有来源开放'), findsOneWidget);

    // 再关「对所有来源开放」
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('未配置密钥'), findsNothing);
    expect(find.text('对所有来源开放'), findsNothing);

    // 新建一份 SettingsService 从持久化里读回来：签名还在 → 仍不显示
    displaySettings.dispose();
    displaySettings = SettingsService();
    await displaySettings.load();
    await pumpDashboard(tester);
    expect(find.text('未配置密钥'), findsNothing);
    expect(find.text('对所有来源开放'), findsNothing);
    expect(displaySettings.warningsTipDismissedSigOf('keys'), 'keys+rules');
    expect(displaySettings.warningsTipDismissedSigOf('rules'), 'keys+rules');
  });

  testWidgets('只关一条时另一条重建后还会显示', (tester) async {
    await pumpDashboard(tester);

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('未配置密钥'), findsNothing);
    expect(find.text('对所有来源开放'), findsOneWidget);

    displaySettings.dispose();
    displaySettings = SettingsService();
    await displaySettings.load();
    await pumpDashboard(tester);
    expect(find.text('未配置密钥'), findsNothing);
    expect(find.text('对所有来源开放'), findsOneWidget);
  });
}
