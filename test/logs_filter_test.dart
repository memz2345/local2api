import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/ui/active_connections_page.dart';
import 'package:local2api/ui/logs_page.dart';
import 'package:local2api/widgets/frosted_page_bar.dart';
import 'package:local2api/widgets/navi_oval_tab_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归：请求日志页的筛选（全部 / 通过 / 失败）与活跃连接页。
///
/// 筛选用的是一条服务层的判定（`logEntryMatches`），两份 UI 共用，
/// 所以这里只钉 Material 版的行为 + 仪表盘带进来的预选。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConfigStore configStore;
  late ServerController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    configStore = ConfigStore();
    await configStore.load();
    configStore.update(ProxyConfig(listenPort: 19293, listenHost: '127.0.0.1'));
    controller = ServerController(configStore)..webUiAutoStart = false;
  });

  tearDown(() {
    controller.dispose();
    configStore.dispose();
  });

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: page,
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  RequestLogEntry entry({
    required int status,
    String? error,
    String model = 'gpt-alias',
    String client = '192.168.1.20',
  }) => RequestLogEntry(
    time: DateTime(2026, 10, 16, 9, 8, 7),
    method: 'POST',
    path: '/v1/chat/completions',
    model: model,
    upstream: 'mock',
    status: status,
    durationMs: 37,
    client: client,
    error: error,
  );

  void seedLogs() {
    controller.server.logs.value = [
      entry(status: 200),
      entry(status: 502, error: '上游返回 502', model: 'other-model'),
    ];
  }

  testWidgets('默认全部：两条都在', (tester) async {
    seedLogs();
    await pumpPage(tester, LogsPage(controller: controller));

    expect(find.text('全部'), findsOneWidget);
    expect(find.text('通过'), findsOneWidget);
    expect(find.text('失败'), findsOneWidget);
    expect(find.textContaining('gpt-alias'), findsWidgets);
    expect(find.textContaining('other-model'), findsWidgets);
  });

  testWidgets('切到「失败」只留失败那条，成功的不再出现', (tester) async {
    seedLogs();
    await pumpPage(tester, LogsPage(controller: controller));

    await tester.tap(find.text('失败'));
    await tester.pumpAndSettle();

    expect(find.textContaining('other-model'), findsWidgets);
    expect(find.textContaining('gpt-alias'), findsNothing);
  });

  testWidgets('仪表盘点「失败」进来就是预选失败', (tester) async {
    seedLogs();
    await pumpPage(
      tester,
      LogsPage(controller: controller, initialFilter: LogStatusFilter.failed),
    );

    // 预选生效：通过的那条不在列表里。
    expect(find.textContaining('gpt-alias'), findsNothing);
    expect(find.textContaining('other-model'), findsWidgets);

    // 点回「全部」两条都回来。
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(find.textContaining('gpt-alias'), findsWidgets);
  });

  testWidgets('筛选后一条都没有：给筛选态的空态文案', (tester) async {
    controller.server.logs.value = [entry(status: 200)];
    await pumpPage(
      tester,
      LogsPage(controller: controller, initialFilter: LogStatusFilter.failed),
    );

    expect(find.text('当前筛选下没有请求'), findsOneWidget);
    // 不是「暂无请求日志」—— 日志其实有，只是被筛掉了。
    expect(find.text('暂无请求日志'), findsNothing);
  });

  testWidgets('一条日志都没有时才是「暂无请求日志」', (tester) async {
    await pumpPage(tester, LogsPage(controller: controller));
    expect(find.text('暂无请求日志'), findsOneWidget);
  });

  testWidgets('清空按钮清的是全部日志，不受筛选影响', (tester) async {
    seedLogs();
    await pumpPage(
      tester,
      LogsPage(controller: controller, initialFilter: LogStatusFilter.failed),
    );

    await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(controller.server.logs.value, isEmpty);
  });

  testWidgets('筛选是顶栏自带的 tab 行，不是内容区悬浮的 FilterChip', (
    WidgetTester tester,
  ) async {
    seedLogs();
    await pumpPage(tester, LogsPage(controller: controller));

    // NaviFlash「分区 / 搜索」那套：tab 行和标题行包在同一块毛玻璃里。
    expect(
      find.descendant(
        of: find.byType(FrostedPageBar),
        matching: find.byType(NaviOvalTabRow),
      ),
      findsOneWidget,
    );
    expect(find.byType(FilterChip), findsNothing);

    // 点 tab 行里的「失败」照旧只留失败那条。
    await tester.tap(find.text('失败'));
    await tester.pumpAndSettle();
    expect(find.textContaining('other-model'), findsWidgets);
    expect(find.textContaining('gpt-alias'), findsNothing);
  });

  group('活跃连接页', () {
    testWidgets('空态', (tester) async {
      await pumpPage(tester, ActiveConnectionsPage(controller: controller));
      expect(find.text('当前没有活跃连接'), findsOneWidget);
    });

    testWidgets('列出客户端 IP 与使用的模型', (tester) async {
      controller.server.activeSessions.value = [
        ActiveConnection(
          clientIp: '192.168.1.20',
          method: 'POST',
          path: '/v1/chat/completions',
          startedAt: DateTime.now().subtract(const Duration(seconds: 65)),
        )..model = 'gpt-alias',
      ];

      await pumpPage(tester, ActiveConnectionsPage(controller: controller));

      expect(find.text('192.168.1.20'), findsOneWidget);
      expect(find.text('gpt-alias'), findsOneWidget);
      expect(find.text('POST /v1/chat/completions'), findsOneWidget);
      // 已持续 1 分 05 秒
      expect(find.text('1:05'), findsWidgets);
      expect(find.text('当前没有活跃连接'), findsNothing);
    });
  });
}
