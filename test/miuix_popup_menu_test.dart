import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/app_settings.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/services/usage_stats.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/miuix/miuix_keys_page.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';
import 'package:local2api/ui/miuix/miuix_settings_page.dart';
import 'package:local2api/ui/miuix/miuix_token_stats_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// miuix 的下拉菜单默认渲染进**根 popup 注册表**，而根注册表由 `MiuixScaffold`
/// 建立（`MiuixPopupScope` + `MiuixPopupHost`）。项目的 miuix 二级页大多是
/// Material `Scaffold` + `MiuixBlurTopAppBar` 的结构，没有 `MiuixScaffold`：
/// 菜单注册进**进程级 fallback 注册表**，而那个注册表没有任何宿主渲染它
/// —— 表现就是「点下去毫无反应」。修法是页面 body 包一层 `MiuixPagePopupHost`。
///
/// 这组用例钉两件事：
/// 1) 没有 MiuixScaffold 的页面（token 统计 / 对话模拟 / 主题选择），下拉必须
///    真的弹出来；
/// 2) 有 MiuixScaffold 的设置页（界面风格 / 导航栏）本来就正常，别被改坏。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConfigStore configStore;
  late ServerController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    configStore = ConfigStore();
    await configStore.load();
    controller = ServerController(configStore);
  });

  tearDown(() => controller.dispose());

  /// 按 app.dart 的 miuix 分支搭树，外面再套 Material Scaffold（真实外壳
  /// MiuixHomeShell 顶层就是 Material Scaffold）。
  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      MiuixThemeController(
        colorSchemeMode: miuixColorSchemeModeOf(themeMode: ThemeMode.light),
        keyColor: const Color(0xFF386A20),
        child: Builder(
          builder: (context) {
            final miuix = MiuixTheme.of(context);
            return MaterialApp(
              locale: const Locale('zh', 'CN'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: AppTheme.light().copyWith(
                colorScheme: materialSchemeFromMiuix(
                  miuix.colors,
                  miuix.brightness,
                ),
              ),
              home: Scaffold(body: page),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('token 统计页（无 MiuixScaffold）：模型下拉真的弹得出来', (tester) async {
    await usageStats.load();
    usageStats.clear();
    usageStats.add(
      TokenUsage(
        timeMs: DateTime.now().millisecondsSinceEpoch,
        model: 'zen-free',
        upstream: 'Zen',
        lane: 'space-bunny-free',
        input: 10,
        output: 5,
      ),
    );

    await pumpPage(tester, const MiuixTokenStatsPage());
    await tester.tap(find.text('全部模型').first);
    await tester.pumpAndSettle();

    // 修复前这里找不到任何菜单项（注册进了没人渲染的注册表）
    expect(find.text('zen-free'), findsWidgets, reason: '下拉菜单必须弹出来');

    // 先 clear 再 flush：clear 也会调度一次防抖落盘，顺序反了会留下 pending timer
    usageStats.clear();
    await usageStats.flush();
  });

  testWidgets('设置页（有 MiuixScaffold）：界面风格 / 导航栏下拉本来就正常', (tester) async {
    final settings = SettingsService();
    await settings.load();

    await tester.pumpWidget(
      MiuixThemeController(
        colorSchemeMode: miuixColorSchemeModeOf(themeMode: ThemeMode.light),
        keyColor: const Color(0xFF386A20),
        child: Builder(
          builder: (context) {
            final miuix = MiuixTheme.of(context);
            return MultiProvider(
              providers: [
                ChangeNotifierProvider<SettingsService>.value(value: settings),
              ],
              child: MaterialApp(
                locale: const Locale('zh', 'CN'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
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
                    settings: AppSettings(),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.ancestor(
      of: find.text('界面风格'),
      matching: find.byType(MiuixOverlayDropdownPreference),
    );
    await tester.scrollUntilVisible(
      row,
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getRect(row).center);
    await tester.pumpAndSettle();

    // 选项文案是「小米 HyperOS」/「Material 3 Expressive」，不是 Miuix/Material
    expect(find.text('小米 HyperOS'), findsWidgets);
    expect(find.text('Material 3 Expressive'), findsWidgets);
  });

  testWidgets('密钥管理页：没有下拉也不会因为缺宿主报错', (tester) async {
    configStore.config.apiKeys.add(
      ApiKeyEntry(id: 'k1', name: '手机', key: 'sk-abcdefghijklmnop'),
    );
    await pumpPage(tester, MiuixKeysPage(controller: controller));
    expect(find.text('手机'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
