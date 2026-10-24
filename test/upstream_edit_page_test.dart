import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/ui/create_config_page.dart';
import 'package:local2api/ui/upstream_edit_page.dart';
import 'package:local2api/ui/upstream_models_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「这一行的墨迹落在哪块 Material 上」的回归断言。
///
/// `FrostedBarPage` 把 [PageBackground] 画在 body 里，而 `Scaffold` 自带的
/// `Material` 在整块 body **之下** —— 行不自己带一层透明 Material 时，
/// `InkWell` 的墨迹就画在背景底下，点了什么反馈都看不见（用户报的
/// 「两行没有 ripple」正是这个）。所以要求：最近的 Material 祖先必须是
/// 行自带的那层 `MaterialType.transparency`。
void expectRowHasOwnMaterial(WidgetTester tester, Finder row) {
  final ink = find.ancestor(of: row, matching: find.byType(InkWell)).last;
  // findAncestorWidgetOfExactType 走的是「最近的那一个」，不依赖 finder 的
  // 祖先排序（它的顺序在不同版本里靠不住）。
  final nearest =
      tester
          .element(ink)
          .findAncestorWidgetOfExactType<Material>();
  expect(nearest, isNotNull, reason: '$row 里没找到 InkWell 的 Material 宿主');
  expect(
    nearest!.type,
    MaterialType.transparency,
    reason: '墨迹要落在行自己的透明 Material 上，而不是 Scaffold 那块（被页面背景盖住）',
  );
  expect(nearest.borderRadius, isNotNull);
}

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

  Widget tree(Widget home) => ChangeNotifierProvider<ConfigStore>.value(
    value: configStore,
    child: MaterialApp(
      // 不钉 locale 的话测试环境默认 en_US，中文断言全对不上
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );

  void useTallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 1500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpBody(WidgetTester tester, Widget body) async {
    useTallView(tester);
    await tester.pumpWidget(tree(body));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  /// push 到占位 base 之上：这些页面会 Navigator.pop，挂根路由会清空路由栈。
  Future<void> pumpPushed(WidgetTester tester, Widget page) async {
    useTallView(tester);
    await tester.pumpWidget(tree(const SizedBox.shrink()));
    await tester.pumpAndSettle();
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(MaterialPageRoute<void>(builder: (_) => page));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  /// toast 是条有存活时长的浮动条，收尾要把它推完，否则 teardown 留 Timer。
  Future<void> settleAfterToast(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  group('ripple 宿主', () {
    testWidgets('创建配置页两行：墨迹落在行自带的透明 Material 上', (tester) async {
      await pumpBody(tester, CreateConfigPage(controller: controller));

      expectRowHasOwnMaterial(tester, find.text('添加配置文件'));
      expectRowHasOwnMaterial(tester, find.text('新建上游'));
    });

    testWidgets('上游编辑页每一行都自带 Material 宿主', (tester) async {
      await pumpPushed(tester, UpstreamEditPage(controller: controller));

      for (final label in ['名称', 'URL', '模式', '对外模型', '测试连接']) {
        expectRowHasOwnMaterial(tester, find.text(label));
      }
    });
  });

  group('Material 上游编辑页（CMFA 式一行一字段）', () {
    testWidgets('新建：行渲染齐全，保存动作在右上角而不是页面底部', (tester) async {
      await pumpPushed(tester, UpstreamEditPage(controller: controller));

      expect(find.text('新建上游'), findsOneWidget);
      expect(find.text('名称'), findsOneWidget);
      expect(find.text('URL'), findsOneWidget);
      expect(find.text('模式'), findsOneWidget);
      expect(find.text('启用'), findsOneWidget);
      expect(find.text('对外模型'), findsOneWidget);
      expect(find.text('测试连接'), findsOneWidget);
      // 没填的行显示灰占位（对应设计图里那行灰字）：名称 / 密钥 / 备注 / 峰谷时段
      expect(find.text('未填写'), findsNWidgets(4));
      // 保存 = 右上角图标；页面底部那个大按钮已经不要了
      expect(find.byIcon(Icons.save_outlined), findsOneWidget);
      expect(find.text('保存'), findsNothing);
      // 模型不在这页铺开
      expect(find.text('没有对外暴露的模型'), findsOneWidget);
    });

    testWidgets('点「模式」行选 Ollama：新建时地址换成该类型默认值', (tester) async {
      await pumpPushed(tester, UpstreamEditPage(controller: controller));

      expect(find.text('http://192.168.1.10:8080/v1'), findsOneWidget);
      await tester.tap(find.text('模式'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('选择模式'), findsOneWidget);

      await tester.tap(find.text('Ollama'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('Ollama'), findsOneWidget);
      expect(find.text('http://192.168.1.10:11434/v1'), findsOneWidget);
    });

    testWidgets('点「名称」行填名字 → 右上角保存写进 config.upstreams', (tester) async {
      await pumpPushed(tester, UpstreamEditPage(controller: controller));

      // 名称为空时点保存只弹提示，不落盘
      await tester.tap(find.byIcon(Icons.save_outlined));
      await settleAfterToast(tester);
      expect(configStore.config.upstreams, isEmpty);

      await tester.tap(find.text('名称'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '本机 llama');
      await tester.tap(find.text('确定'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('本机 llama'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.save_outlined));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      final saved = configStore.config.upstreams;
      expect(saved, hasLength(1));
      expect(saved.single.name, '本机 llama');
      expect(saved.single.baseUrl, 'http://192.168.1.10:8080/v1');
      expect(find.byType(UpstreamEditPage), findsNothing);
    });

    testWidgets('点「URL」行填非法地址：保存被拦下，页面还在', (tester) async {
      await pumpPushed(tester, UpstreamEditPage(controller: controller));

      await tester.tap(find.text('名称'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'demo');
      await tester.tap(find.text('确定'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      await tester.tap(find.text('URL'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ftp://bad');
      await tester.tap(find.text('确定'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.save_outlined));
      await settleAfterToast(tester);

      expect(configStore.config.upstreams, isEmpty);
      expect(find.byType(UpstreamEditPage), findsOneWidget);
    });

    testWidgets('备注下面挂「峰谷时段」行：点进去配这个上游的窗口', (tester) async {
      final upstream = Upstream(
        id: 'u1',
        name: '本机 llama',
        baseUrl: 'http://127.0.0.1:8080/v1',
        models: [ModelEntry(publicName: 'peak-model')],
      );
      configStore.update(ProxyConfig(upstreams: [upstream]));
      await pumpPushed(
        tester,
        UpstreamEditPage(controller: controller, upstream: upstream),
      );

      // 跟其它字段同一套行外观：就一行「峰谷时段」（值是条数，0 条时是灰占位）
      expect(find.text('峰谷时段'), findsOneWidget);

      // 点进去是限定在这个上游的策略页（空态那句只在那页有）
      await tester.tap(find.text('峰谷时段'));
      await tester.pumpAndSettle();
      expect(find.text('还没有策略：不加就是全天可用'), findsOneWidget);

      // 加一条：候选模型就是这一页的模型
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text('peak-model'), findsWidgets);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      await settleAfterToast(tester);

      final rules = configStore.config.scheduleRules;
      expect(rules, hasLength(1));
      expect(rules.first.targets, ['peak-model']);
    });

    testWidgets('点「对外模型」行进独立模型页，改动回显到这一行', (tester) async {
      final upstream = Upstream(
        id: 'u1',
        name: '本机 llama',
        type: UpstreamType.llamacpp,
        baseUrl: 'http://127.0.0.1:8080/v1',
        models: [ModelEntry(publicName: 'qwen', target: 'qwen')],
      );
      configStore.update(ProxyConfig(upstreams: [upstream]));
      await pumpPushed(
        tester,
        UpstreamEditPage(controller: controller, upstream: upstream),
      );

      expect(find.text('编辑上游'), findsOneWidget);
      // 模型不铺开，只显示数量
      expect(find.text('qwen'), findsNothing);
      expect(find.text('1 个模型'), findsOneWidget);

      await tester.tap(find.text('对外模型'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.byType(UpstreamModelsPage), findsOneWidget);
      expect(find.text('qwen'), findsOneWidget);

      // 删掉唯一的模型，回上游编辑页时那一行要跟着变
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('没有对外暴露的模型'), findsOneWidget);

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.byType(UpstreamEditPage), findsOneWidget);
      expect(find.text('没有对外暴露的模型'), findsOneWidget);
    });
  });
}
