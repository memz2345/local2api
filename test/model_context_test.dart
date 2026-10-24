import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/ui/upstream_models_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 模型「上下文长度」：JSON 往返、默认值回退 1M、模型编辑弹窗的回写。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ModelEntry.contextLength', () {
    test('未设置：不落盘、读回仍是 0、对外回退 1M', () {
      final m = ModelEntry(publicName: 'a');
      expect(m.contextLength, 0);
      expect(m.effectiveContextLength, kDefaultContextLength);
      expect(m.toJson().containsKey('contextLength'), isFalse);
      final back = ModelEntry.fromJson(m.toJson());
      expect(back.contextLength, 0);
      expect(back.effectiveContextLength, kDefaultContextLength);
    });

    test('配了值随 JSON 往返', () {
      final m = ModelEntry(publicName: 'a', contextLength: 200000);
      expect(m.toJson()['contextLength'], 200000);
      expect(ModelEntry.fromJson(m.toJson()).contextLength, 200000);
      expect(m.effectiveContextLength, 200000);
    });

    test('maxOutputTokens 随 JSON 往返（0 不落盘）', () {
      final m = ModelEntry(publicName: 'a');
      expect(m.maxOutputTokens, 0);
      expect(m.toJson().containsKey('maxOutputTokens'), isFalse);
      final m2 = ModelEntry(publicName: 'a', maxOutputTokens: 32000);
      expect(m2.toJson()['maxOutputTokens'], 32000);
      expect(ModelEntry.fromJson(m2.toJson()).maxOutputTokens, 32000);
    });

    test('contextLabel 紧凑显示（没配为空串）', () {
      expect(ModelEntry(publicName: 'a').contextLabel, '');
      expect(
        ModelEntry(publicName: 'a', contextLength: 1000000).contextLabel,
        '1M',
      );
      expect(
        ModelEntry(publicName: 'a', contextLength: 128000).contextLabel,
        '128K',
      );
      expect(ModelEntry(publicName: 'a', contextLength: 8000).contextLabel, '8K');
      expect(ModelEntry(publicName: 'a', contextLength: 512).contextLabel, '512');
    });
  });

  group('模型编辑弹窗', () {
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

    Future<void> pumpPage(WidgetTester tester, List<ModelEntry> models) async {
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: UpstreamModelsPage(
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

    testWidgets('编辑里能填上下文长度并回写（行尾出徽标）', (tester) async {
      final models = [ModelEntry(publicName: 'alpha', target: 'alpha')];
      await pumpPage(tester, models);

      await tester.tap(find.byIcon(Icons.drive_file_rename_outline).first);
      await tester.pumpAndSettle();
      expect(find.text('最大上下文数'), findsOneWidget);
      expect(find.text('最大输出数'), findsOneWidget);

      // 四个输入框：对外名称 / 上游模型 / 最大上下文 / 最大输出
      await tester.enterText(find.byType(TextField).at(2), '128000');
      await tester.enterText(find.byType(TextField).at(3), '32000');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(models.first.contextLength, 128000);
      expect(models.first.maxOutputTokens, 32000);
      // 行尾徽标也出来了（l10n「上下文 {value}」）
      expect(find.text('上下文 128K'), findsOneWidget);
    });

    testWidgets('已有值进弹窗时预填，清空即恢复默认', (tester) async {
      final models = [
        ModelEntry(publicName: 'alpha', contextLength: 65536),
      ];
      await pumpPage(tester, models);

      await tester.tap(find.byIcon(Icons.drive_file_rename_outline).first);
      await tester.pumpAndSettle();
      expect(find.text('65536'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(2), '');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(models.first.contextLength, 0);
    });
  });
}
