import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/model_schedule.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';
import 'package:local2api/ui/miuix/miuix_schedule_policy_page.dart';
import 'package:local2api/ui/miuix/miuix_webui_page.dart';
import 'package:local2api/ui/schedule_policy_page.dart';
import 'package:local2api/ui/webui_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConfigStore configStore;
  late ServerController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    configStore = ConfigStore();
    await configStore.load();
    controller = ServerController(configStore);
    // widget test 的假时钟不允许 HttpServer.bind 留下的空闲计时器活着
    controller.webUiAutoStart = false;
    final cfg = configStore.config;
    cfg.upstreams.add(
      Upstream(
        id: 'u1',
        name: '本地',
        baseUrl: 'http://127.0.0.1:8080/v1',
        managedBy: 'zen',
        models: [ModelEntry(publicName: 'peak-model')],
      ),
    );
    configStore.update(cfg);
  });

  tearDown(() => controller.dispose());

  Future<void> settleAll(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  Future<void> pumpMaterial(WidgetTester tester, {required Widget home}) async {
    await tester.pumpWidget(
      MaterialApp(
        // 不钉 locale 的话测试环境默认 en_US，中文断言全对不上
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );
    await settleAll(tester);
  }

  Future<void> pumpMiuix(WidgetTester tester, {required Widget home}) async {
    await tester.pumpWidget(
      MiuixThemeController(
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
              home: home,
            );
          },
        ),
      ),
    );
    await settleAll(tester);
  }

  group('峰谷策略页（Material）', () {
    testWidgets('空态渲染（说明行已按需求撤下）', (tester) async {
      await pumpMaterial(
        tester,
        home: SchedulePolicyPage(controller: controller),
      );
      expect(find.text('峰谷时段'), findsWidgets);
      expect(find.text('还没有策略：不加就是全天可用'), findsOneWidget);
      expect(find.text('对话模拟永远可用，不受这些策略限制'), findsNothing);
      expect(find.textContaining('正向：只有选中的时间段能用'), findsNothing);
    });

    testWidgets('新增一条策略：落到 ProxyConfig 并渲染成卡片', (tester) async {
      await pumpMaterial(
        tester,
        home: SchedulePolicyPage(controller: controller),
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // 面板里能选到模型（配置里那个对外名）
      expect(find.text('peak-model'), findsWidgets);
      expect(find.text('正向（选中时段才能用）'), findsOneWidget);
      expect(find.text('反向（选中时段禁止用）'), findsOneWidget);

      // 切成反向
      await tester.tap(find.text('反向（选中时段禁止用）'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      await settleAll(tester);

      final rules = configStore.config.scheduleRules;
      expect(rules.length, 1);
      expect(rules.first.mode, ScheduleMode.deny);
      expect(rules.first.targets, ['peak-model']);
      expect(rules.first.weekdays, [1, 2, 3, 4, 5, 6, 7]);
      // 页面上渲染出这条的卡片
      expect(find.text('反向（选中时段禁止用）'), findsWidgets);
    });

    testWidgets('已存在的策略能开关停用', (tester) async {
      final cfg = configStore.config;
      cfg.scheduleRules.add(
        ScheduleRule(
          id: 'r1',
          targets: ['peak-model'],
          mode: ScheduleMode.allow,
          startHour: 9,
          endHour: 18,
        ),
      );
      configStore.update(cfg);

      await pumpMaterial(
        tester,
        home: SchedulePolicyPage(controller: controller),
      );
      expect(find.text('peak-model'), findsWidgets);
      expect(find.byType(Switch), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await settleAll(tester);
      expect(configStore.config.scheduleRules.first.enabled, isFalse);
    });
  });

  group('峰谷策略页（miuix）', () {
    testWidgets('空态渲染（说明行已按需求撤下）', (tester) async {
      await pumpMiuix(
        tester,
        home: MiuixSchedulePolicyPage(controller: controller),
      );
      expect(find.text('峰谷时段'), findsWidgets);
      expect(find.text('还没有策略：不加就是全天可用'), findsOneWidget);
      expect(find.text('对话模拟永远可用，不受这些策略限制'), findsNothing);
      expect(find.textContaining('正向：只有选中的时间段能用'), findsNothing);
    });

    testWidgets('新增一条策略：miuix 面板同样写入配置', (tester) async {
      await pumpMiuix(
        tester,
        home: MiuixSchedulePolicyPage(controller: controller),
      );

      await tester.tap(find.byType(MiuixFloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('peak-model'), findsWidgets);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      // miuix 的 toast 在没有 Material Scaffold 的测试树上会抛一次（见
      // miuix_keys_page 注释）：吞掉框架噪声再断言数据
      while (tester.takeException() != null) {}
      await settleAll(tester);

      final rules = configStore.config.scheduleRules;
      expect(rules.length, 1);
      expect(rules.first.targets, ['peak-model']);
      expect(rules.first.mode, ScheduleMode.allow);
    });
  });

  group('临时 WebUI 页', () {
    testWidgets('Material：开关与端口字段都在', (tester) async {
      await pumpMaterial(tester, home: WebUiPage(controller: controller));
      expect(find.text('启用临时 WebUI'), findsOneWidget);
      expect(find.text('WebUI 端口'), findsOneWidget);
      expect(find.text('网页未启动'), findsOneWidget);
    });

    testWidgets('miuix：开关与端口字段都在', (tester) async {
      await pumpMiuix(tester, home: MiuixWebUiPage(controller: controller));
      expect(find.text('启用临时 WebUI'), findsOneWidget);
      expect(find.text('WebUI 端口'), findsOneWidget);
    });

    testWidgets('Material：打开开关后配置落盘为 true', (tester) async {
      await pumpMaterial(tester, home: WebUiPage(controller: controller));
      expect(configStore.config.webUiEnabled, isFalse);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await settleAll(tester);
      expect(configStore.config.webUiEnabled, isTrue);
    });
  });
}
