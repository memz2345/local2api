import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';
import 'package:local2api/ui/miuix/miuix_upstream_models_page.dart';
import 'package:local2api/widgets/az_index_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'miuix_finders.dart';

/// miuix 版对外模型页的排序菜单 + A-Z 索引条回归。
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

  tearDown(() {
    configStore.dispose();
    controller.dispose();
  });

  Widget tree(Widget home) => MiuixThemeController(
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
          home: home,
        );
      },
    ),
  );

  Future<void> pumpPage(WidgetTester tester, List<ModelEntry> models) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      tree(
        MiuixUpstreamModelsPage(
          controller: controller,
          models: models,
          probe: () =>
              Upstream(id: 'u', name: 'u', baseUrl: 'http://127.0.0.1:1/v1'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets('默认顺序下没有 A-Z 索引条', (tester) async {
    await pumpPage(tester, [
      ModelEntry(publicName: 'zeta'),
      ModelEntry(publicName: 'apple'),
    ]);
    expect(find.byType(AzIndexBar), findsNothing);
  });

  testWidgets('切成首字母正序：出现 A-Z 索引条与字母分组', (tester) async {
    await pumpPage(tester, [
      ModelEntry(publicName: 'zeta'),
      ModelEntry(publicName: 'apple'),
      ModelEntry(publicName: '123'),
    ]);

    await tester.tap(miuixIcon(AppIconNames.sort));
    await tester.pumpAndSettle();
    expect(find.text('排序方式'), findsOneWidget);
    await tester.tap(find.text('首字母正序'));
    await tester.pumpAndSettle();

    expect(find.byType(AzIndexBar), findsOneWidget);
    expect(find.text('A'), findsWidgets);
    expect(find.text('Z'), findsWidgets);
    expect(find.text('#'), findsWidgets);
  });
}
