import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/ui/upstream_models_page.dart';
import 'package:local2api/widgets/az_index_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 对外模型页的排序菜单 + A-Z 索引条回归。
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

  Widget tree(Widget home) => MaterialApp(
    locale: const Locale('zh', 'CN'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  Future<void> pumpPage(WidgetTester tester, List<ModelEntry> models) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      tree(
        UpstreamModelsPage(
          controller: controller,
          models: models,
          probe: () =>
              Upstream(id: 'u', name: 'u', baseUrl: 'http://127.0.0.1:1/v1'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
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

    // 顶栏排序按钮 → 底部菜单里选「首字母正序」
    await tester.tap(find.byIcon(Icons.sort_by_alpha));
    await tester.pumpAndSettle();
    expect(find.text('排序方式'), findsOneWidget);
    await tester.tap(find.text('首字母正序'));
    await tester.pumpAndSettle();

    expect(find.byType(AzIndexBar), findsOneWidget);
    // 三个分组字母都在（A / Z / #），索引条里也各有一份
    expect(find.text('A'), findsWidgets);
    expect(find.text('Z'), findsWidgets);
    expect(find.text('#'), findsWidgets);
  });

  testWidgets('排序方式会记住（切回来仍是首字母正序）', (tester) async {
    await pumpPage(tester, [ModelEntry(publicName: 'zeta')]);
    await tester.tap(find.byIcon(Icons.sort_by_alpha));
    await tester.pumpAndSettle();
    await tester.tap(find.text('首字母正序'));
    await tester.pumpAndSettle();
    expect(find.byType(AzIndexBar), findsOneWidget);

    // 重新 pump 一个新页面实例：应当从持久化里读回首字母正序
    await tester.pumpWidget(const SizedBox());
    await pumpPage(tester, [ModelEntry(publicName: 'zeta')]);
    expect(find.byType(AzIndexBar), findsOneWidget);
  });
}
