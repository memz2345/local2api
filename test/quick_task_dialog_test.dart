import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/nav_bus.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/services/windows_task_dialog.dart';
import 'package:local2api/src/enums.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';
import 'package:local2api/ui/quick_task_actions.dart';
import 'package:local2api/ui/upstream_edit_page.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「任务」对话框：Windows 走原生 TaskDialog，其它平台（以及测试里强制关掉
/// 原生那档）走 Flutter 同构弹窗 —— Material / miuix 各一套。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConfigStore configStore;
  late ServerController controller;
  late SettingsService displaySettings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // 开发机就是 Windows：不放回退开关的话，showQuickTaskDialog 会去撞
    // 不存在的原生通道，Flutter UI 一行都跑不到。
    WindowsTaskDialog.debugForceUnsupported = true;
    // 与 logs_filter_test 同款：ServerController 的真实异步 IO 必须在
    // testWidgets 体外建好，否则假时钟里整个用例吊死。
    configStore = ConfigStore();
    await configStore.load();
    configStore.update(
      ProxyConfig(
        listenHost: '0.0.0.0',
        listenPort: 8080,
        upstreams: [
          Upstream(
            id: 'home',
            name: '家里那组',
            type: UpstreamType.openai,
            baseUrl: 'https://home.example/v1',
            models: [
              ModelEntry(publicName: 'm1'),
              ModelEntry(publicName: 'm2'),
            ],
          ),
        ],
      ),
    );
    controller = ServerController(configStore)..webUiAutoStart = false;
    displaySettings = SettingsService();
  });

  tearDown(() {
    WindowsTaskDialog.debugForceUnsupported = false;
    controller.dispose();
    configStore.dispose();
    displaySettings.dispose();
  });

  Future<void> pumpHost(WidgetTester tester, {required bool miuix}) async {
    await displaySettings.setUiStyle(
      miuix ? UiStyle.miuix : UiStyle.materialExpressive,
    );

    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsService>.value(
        value: displaySettings,
        child: MiuixThemeController(
          colorSchemeMode: miuixColorSchemeModeOf(themeMode: ThemeMode.light),
          keyColor: const Color(0xFF386A20),
          child: Builder(
            builder: (context) {
              final colors = MiuixTheme.of(context).colors;
              return MaterialApp(
                locale: const Locale('zh', 'CN'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: AppTheme.light().copyWith(
                  colorScheme: materialSchemeFromMiuix(
                    colors,
                    MiuixTheme.of(context).brightness,
                  ),
                ),
                home: Builder(
                  builder: (context) => Scaffold(
                    body: Center(
                      child: ElevatedButton(
                        onPressed: () => showQuickTaskDialog(
                          context,
                          controller,
                        ),
                        child: const Text('open'),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Material：任务三项 + 最近的上游组都在', (tester) async {
    await pumpHost(tester, miuix: false);
    await openDialog(tester);

    expect(find.text('任务'), findsOneWidget);
    expect(find.text('启动服务'), findsOneWidget);
    expect(find.text('暂停服务'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('最近'), findsOneWidget);
    expect(find.text('家里那组'), findsOneWidget);
    expect(find.text('2 个模型'), findsOneWidget);
    // 副标题带着监听地址，用户不用先回仪表盘确认端口。
    expect(find.textContaining('0.0.0.0:8080'), findsOneWidget);
  });

  testWidgets('Material：点「设置」关闭弹窗并请求切到设置 tab', (tester) async {
    await pumpHost(tester, miuix: false);
    await openDialog(tester);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.text('启动服务'), findsNothing);
    expect(NavBus.tabRequest.value.index, 2);
  });

  testWidgets('Material：点「最近」里的上游组直接进它的编辑页', (tester) async {
    await pumpHost(tester, miuix: false);
    await openDialog(tester);

    await tester.tap(find.text('家里那组'));
    await tester.pumpAndSettle();

    expect(find.byType(UpstreamEditPage), findsOneWidget);
  });

  testWidgets('miuix：同一份内容换成 HyperOS 卡片皮肤', (tester) async {
    await pumpHost(tester, miuix: true);
    await openDialog(tester);

    expect(find.text('任务'), findsOneWidget);
    expect(find.text('启动服务'), findsOneWidget);
    expect(find.text('暂停服务'), findsOneWidget);
    expect(find.text('家里那组'), findsOneWidget);
    // miuix 档走 MiuixGroupCard 行，不是 Material 的 ListTile。
    expect(find.byType(MiuixGroupCard), findsWidgets);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('miuix：点「启动服务」会把服务起起来', (tester) async {
    await pumpHost(tester, miuix: true);
    await openDialog(tester);

    expect(controller.isRunning, isFalse);
    await tester.tap(find.text('启动服务'));
    await tester.pumpAndSettle();

    expect(controller.isRunning, isTrue);
    controller.stop();
  });
}
