import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/config_profile.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/src/expressive_loading_indicator.dart';
import 'package:local2api/ui/profiles_page.dart';
import 'package:local2api/ui/upstream_edit_page.dart';
import 'package:local2api/widgets/m3e_pull_to_refresh.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Material 发现页 = 上游服务列表（与 miuix 版同构，业务逻辑共用）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProfileStore profileStore;
  late ConfigStore configStore;
  late ServerController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    profileStore = ProfileStore();
    await profileStore.load();
    configStore = ConfigStore();
    await configStore.load();
    controller = ServerController(configStore);
  });

  tearDown(() {
    profileStore.dispose();
    configStore.dispose();
    controller.dispose();
  });

  Upstream upstream({
    String id = 'u1',
    String name = '本地 llama',
    String note = '',
    String? managedBy,
  }) => Upstream(
    id: id,
    name: name,
    type: UpstreamType.llamacpp,
    baseUrl: 'https://a.example/v1',
    note: note,
    managedBy: managedBy,
    models: [ModelEntry(publicName: 'm1')],
  );

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ProfileStore>.value(
        value: profileStore,
        child: MaterialApp(
          // 不钉 locale 的话测试环境默认 en_US，下面的中文断言全都对不上
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ProfilesPage(controller: controller),
        ),
      ),
    );
    // 配置落盘是 400ms 防抖；pumpAndSettle 在没有帧要画时不推进时钟，
    // 那个定时器会一直挂到测试结束并报「A Timer is still pending」。
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets('没有上游时给出提示，并套着 M3E 下拉刷新', (tester) async {
    await pumpPage(tester);

    expect(find.text('发现'), findsWidgets);
    expect(find.byType(M3EPullToRefresh), findsOneWidget);
    expect(find.text('还没有上游，先添加一个'), findsOneWidget);
  });

  testWidgets('每个上游一张卡：名称 / 类型 / 地址 / 备注都在', (tester) async {
    configStore.config.upstreams.add(upstream(note: '放客厅的 4060 机器'));
    await pumpPage(tester);

    expect(find.text('本地 llama'), findsOneWidget);
    expect(find.text('llama.cpp'), findsOneWidget);
    expect(find.text('https://a.example/v1'), findsOneWidget);
    expect(find.text('放客厅的 4060 机器'), findsOneWidget);
    expect(find.text('1 个模型'), findsOneWidget);
    expect(find.text('尚未测试'), findsOneWidget);
  });

  testWidgets('开关直接改上游的 enabled', (tester) async {
    final u = upstream();
    configStore.config.upstreams.add(u);
    await pumpPage(tester);
    expect(u.enabled, isTrue);

    await tester.tap(find.byType(Switch).first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(u.enabled, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
  });

  testWidgets('自建上游的更多菜单：备注 / 查看 JSON / 删除', (tester) async {
    configStore.config.upstreams.add(upstream());
    await pumpPage(tester);

    await tester.tap(find.byIcon(Icons.more_horiz).first);
    await tester.pumpAndSettle();

    expect(find.text('备注'), findsOneWidget);
    expect(find.text('查看 JSON'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    // 自建上游没有档案归属：既没有回退链也没有可拉取的订阅端
    expect(find.text('查看车道'), findsNothing);
    expect(find.text('刷新可用模型'), findsNothing);
  });

  testWidgets('档案归属的上游，更多菜单多出查看车道 / 刷新可用模型', (tester) async {
    // 「车道」这些档案级动作要靠 ProfileStore 解析归属档案，所以先导入一份
    // id = demo 的档案，再把上游标成它装的。
    profileStore.importDocument(
      '{"id":"demo","name":"DEMO","upstreams":[{"id":"u1","name":"Demo",'
      '"baseUrl":"https://a.example/v1","models":[{"publicName":"m1"}]}]}',
      const ProfileSource(ProfileSourceKind.inline),
    );
    configStore.config.upstreams.add(upstream(managedBy: 'demo'));
    await pumpPage(tester);

    await tester.tap(find.byIcon(Icons.more_horiz).first);
    await tester.pumpAndSettle();

    expect(find.text('查看车道'), findsOneWidget);
    expect(find.text('刷新可用模型'), findsOneWidget);
  });

  testWidgets('点卡片进上游编辑页', (tester) async {
    configStore.config.upstreams.add(upstream());
    await pumpPage(tester);

    await tester.tap(find.text('本地 llama'));
    await tester.pumpAndSettle();

    expect(find.byType(UpstreamEditPage), findsOneWidget);
  });

  testWidgets('只有一两条上游（内容不满一屏）时也能把指示器拉出来', (tester) async {
    // 回归：物理效果只挂裸的 ClampingScrollPhysics 时，内容比视口短 →
    // shouldAcceptUserOffset 直接拒绝拖拽，一个滚动通知都发不出来，
    // 下拉刷新等于死了。
    await pumpPage(tester);
    expect(configStore.config.upstreams, isEmpty);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    // 分两小步拖（一次大跳会被手势竞技场吃掉），跟真实拖动一致
    await gesture.moveBy(const Offset(0, 30));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();

    expect(
      find.byType(ExpressiveLoadingIndicator),
      findsOneWidget,
      reason: '拉得动才说明拖拽被接受了',
    );

    // 松手回弹即可，别过阈值真去发网络请求
    await gesture.up();
    await tester.pump();
    await tester.pumpAndSettle();
  });
}
