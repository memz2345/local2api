import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'miuix_finders.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/miuix/miuix_active_connections_page.dart';
import 'package:local2api/ui/miuix/miuix_dashboard_page.dart';
import 'package:local2api/ui/miuix/miuix_logs_page.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';
import 'package:local2api/ui/miuix/miuix_keys_page.dart';
import 'package:local2api/ui/miuix/miuix_upstream_edit_page.dart';
import 'package:local2api/widgets/miuix/miuix_tilt_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// 按 app.dart 里 miuix 分支的结构搭树：MiuixThemeController（monet 档）
  /// → 配色桥 → MaterialApp → 页面。这些页面很长，默认 800x600 会溢出。
  Future<void> pumpPage(WidgetTester tester, Widget page) async {
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
                // 不钉 locale 的话测试环境默认 en_US，中文断言全对不上
                locale: const Locale('zh', 'CN'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: AppTheme.light().copyWith(colorScheme: scheme),
                home: Scaffold(body: page),
              );
            },
          ),
        ),
      ),
    );
    // ConfigStore 落盘是 400ms 防抖，不推进时钟会报 timer 未清
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  void seed({List<Upstream> upstreams = const [], List<ApiKeyEntry> keys = const []}) {
    configStore.update(
      ProxyConfig(
        listenPort: 9292,
        listenHost: '0.0.0.0',
        upstreams: [...upstreams],
        apiKeys: [...keys],
      ),
    );
  }

  testWidgets('空配置仪表盘：四个分区与空态文案齐全', (tester) async {
    await pumpPage(
      tester,
      MiuixDashboardPage(controller: controller),
    );

    expect(find.text('仪表盘'), findsOneWidget);
    expect(find.byType(MiuixTopAppBar, skipOffstage: false), findsOneWidget);
    // 服务分区
    expect(find.text('已停止'), findsOneWidget);
    expect(find.text('服务未启动，点一下卡片启动'), findsOneWidget);
    expect(find.text('接入地址'), findsOneWidget);
    expect(find.text('http://0.0.0.0:9292/v1'), findsOneWidget);
    expect(find.text('请求统计'), findsOneWidget);
    // 风险提示：没密钥 + 没规则
    expect(find.text('未配置密钥'), findsOneWidget);
    expect(find.text('对所有来源开放'), findsOneWidget);
    // 模型分区空态
    expect(find.text('对外模型'), findsOneWidget);
    expect(find.text('没有对外暴露的模型'), findsOneWidget);
    // 状态卡的小卡与分区标题各有一处
    expect(find.text('上游服务'), findsWidgets);
    expect(find.text('还没有上游，先添加一个'), findsOneWidget);
    // 密钥分区空态
    expect(find.text('密钥'), findsWidgets);
    expect(find.text('尚无密钥，任何客户端都能直接调用'), findsOneWidget);
    // 最近请求空态
    expect(find.text('最近请求'), findsOneWidget);
    expect(find.text('暂无请求日志'), findsOneWidget);
    // 卡片本体是项目自绘的 MiuixTiltCard（MiuixGroupCard 的实现委托它），
    // 不再是包版 MiuixCard。
    expect(find.byType(MiuixTiltCard), findsWidgets);
  });

  testWidgets('有上游与密钥时列出条目，密钥按掩码显示', (tester) async {
    final key = ApiKeyEntry(id: 'k1', name: '手机', key: 'sk-abcdefghijklmnopqrstuvwxyz');
    seed(
      upstreams: [
        Upstream(
          id: 'u1',
          name: '本机 llama',
          type: UpstreamType.llamacpp,
          baseUrl: 'http://127.0.0.1:8080/v1',
          models: [ModelEntry(publicName: 'qwen', target: 'qwen')],
        ),
      ],
      keys: [key],
    );
    await pumpPage(tester, MiuixDashboardPage(controller: controller));

    expect(find.text('本机 llama'), findsOneWidget);
    expect(find.text('http://127.0.0.1:8080/v1'), findsOneWidget);
    expect(find.text('1 个模型'), findsOneWidget);
    expect(find.text('llama.cpp'), findsWidgets);
    // 对外模型计数从 0 变成 1
    expect(find.text('1'), findsWidgets);
    expect(find.text('没有对外暴露的模型'), findsNothing);
    expect(find.text('还没有上游，先添加一个'), findsNothing);

    // 密钥不再铺在仪表盘上：只给一张概览卡 + 「管理密钥」入口
    expect(find.text('密钥 · 1/1'), findsOneWidget);
    // （密钥名与掩码都在下一页断言 —— 跳过去之后本页会 offstage）
    await tester.tap(find.text('管理密钥'));
    await tester.pumpAndSettle();

    expect(find.byType(MiuixKeysPage), findsOneWidget);
    expect(find.text('手机'), findsOneWidget);
    // sk-abc…wxyz：前 6 后 4 掩码，不整串铺开
    expect(find.text('sk-abc…wxyz'), findsOneWidget);
  });

  testWidgets('上游行的开关只改 enabled，不会误跳编辑页', (tester) async {
    final upstream = Upstream(
      id: 'u1',
      name: '本机 llama',
      baseUrl: 'http://127.0.0.1:8080/v1',
    );
    seed(
      upstreams: [upstream],
      keys: [ApiKeyEntry(id: 'k1', name: '手机', key: 'sk-1')],
    );
    await pumpPage(tester, MiuixDashboardPage(controller: controller));

    // 密钥行的开关已经跟着密钥管理页走了，仪表盘上只剩上游这一个
    expect(find.byType(MiuixSwitch), findsNWidgets(1));
    await tester.tap(find.byType(MiuixSwitch).first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(upstream.enabled, isFalse);
    expect(find.byType(MiuixUpstreamEditPage), findsNothing);
  });

  testWidgets('点上游行进的是 miuix 编辑页', (tester) async {
    seed(
      upstreams: [
        Upstream(id: 'u1', name: '本机 llama', baseUrl: 'http://127.0.0.1:8080/v1'),
      ],
    );
    await pumpPage(tester, MiuixDashboardPage(controller: controller));

    await tester.tap(find.text('本机 llama'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.byType(MiuixUpstreamEditPage), findsOneWidget);
    expect(find.text('编辑上游'), findsOneWidget);
  });

  testWidgets('添加密钥抽屉：保存后写进配置的是一条 sk- 密钥', (tester) async {
    await pumpPage(tester, MiuixDashboardPage(controller: controller));

    // 密钥的加号现在在密钥管理页里（仪表盘那颗只剩上游）
    await tester.tap(find.text('管理密钥'));
    await tester.pumpAndSettle();
    expect(find.byType(MiuixKeysPage), findsOneWidget);
    await tester.tap(miuixIcon(AppIconNames.addCircle).first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('添加密钥'), findsWidgets);
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.first, '我的平板');
    await tester.pump();

    await tester.tap(find.text('保存'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    final saved = configStore.config.apiKeys;
    expect(saved, hasLength(1));
    expect(saved.single.name, '我的平板');
    expect(saved.single.key, startsWith('sk-'));
    expect(find.text('我的平板'), findsOneWidget);
  });

  testWidgets('随机生成按钮换掉密钥文本', (tester) async {
    await pumpPage(tester, MiuixDashboardPage(controller: controller));
    await tester.tap(find.text('管理密钥'));
    await tester.pumpAndSettle();
    await tester.tap(miuixIcon(AppIconNames.addCircle).first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    final keyField = find.byType(TextField).last;
    final before = (keyField.evaluate().single.widget as TextField).controller!.text;
    await tester.tap(find.byIcon(Icons.casino_outlined));
    await tester.pump();
    final after = (keyField.evaluate().single.widget as TextField).controller!.text;

    expect(after, isNot(before));
    expect(after, startsWith('sk-'));
  });

  testWidgets('点「查看全部」进 miuix 日志页（不回 Material 版）', (tester) async {
    controller.server.logs.value = [
      RequestLogEntry(
        time: DateTime(2026, 10, 7, 9, 8, 7),
        method: 'GET',
        path: '/v1/models',
        model: 'qwen',
        upstream: '本机 llama',
        status: 200,
        durationMs: 12,
        client: '192.168.1.20',
      ),
    ];
    await pumpPage(tester, MiuixDashboardPage(controller: controller));

    expect(find.text('GET /v1/models  qwen'), findsOneWidget);
    await tester.ensureVisible(find.text('查看全部'));
    await tester.tap(find.text('查看全部'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  });

  testWidgets('统计三块可点：失败带预选、活跃连接进独立页', (tester) async {
    controller.server.logs.value = [
      RequestLogEntry(
        time: DateTime(2026, 10, 7, 9, 8, 7),
        method: 'GET',
        path: '/v1/models',
        model: 'qwen',
        upstream: '本机 llama',
        status: 200,
        durationMs: 12,
        client: '192.168.1.20',
      ),
      RequestLogEntry(
        time: DateTime(2026, 10, 7, 9, 9, 7),
        method: 'POST',
        path: '/v1/chat/completions',
        model: 'boom',
        upstream: '本机 llama',
        status: 502,
        durationMs: 30,
        client: '192.168.1.20',
        error: '上游返回 502',
      ),
    ];
    await pumpPage(tester, MiuixDashboardPage(controller: controller));

    // 点「失败」：进日志页且预选失败 —— 成功的那条不该出现
    await tester.ensureVisible(find.text('失败'));
    await tester.tap(find.text('失败'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.byType(MiuixLogsPage), findsOneWidget);
    expect(find.textContaining('boom'), findsWidgets);
    expect(find.textContaining('qwen'), findsNothing);
    // miuix 的返回键是自绘的（不是 Cupertino 返回按钮），走 Navigator.pop
    Navigator.of(tester.element(find.byType(MiuixLogsPage))).pop();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // 点「活跃连接」：进活跃连接页（没有连接时是空态）
    await tester.ensureVisible(find.text('活跃连接'));
    await tester.tap(find.text('活跃连接'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.byType(MiuixActiveConnectionsPage), findsOneWidget);
    expect(find.text('当前没有活跃连接'), findsOneWidget);
  });
}
