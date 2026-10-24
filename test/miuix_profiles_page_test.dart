import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/config_profile.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';
import 'package:local2api/ui/miuix/miuix_profiles_page.dart';
import 'package:local2api/ui/miuix/miuix_upstream_edit_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'miuix_finders.dart';

/// miuix 发现页 = 上游服务列表。每张卡是一个 [Upstream]，
/// 不再是「配置档案」卡。
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

  /// 按 app.dart 里 miuix 分支的结构搭树：MiuixThemeController（monet 档）
  /// → 配色桥 → MaterialApp → 页面。
  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ProfileStore>.value(
        value: profileStore,
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
                localizationsDelegates:
                    AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: AppTheme.light().copyWith(colorScheme: scheme),
                home: Scaffold(
                  body: MiuixProfilesPage(controller: controller),
                ),
              );
            },
          ),
        ),
      ),
    );
    // 配置落盘是 400ms 防抖，不推进时钟会报 timer 未清
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets('没有上游时给出提示，顶栏与下拉刷新都在', (tester) async {
    await pumpPage(tester);

    expect(find.text('发现'), findsWidgets);
    expect(find.text('还没有上游，先添加一个'), findsOneWidget);
    expect(find.byType(MiuixPullToRefresh), findsOneWidget);
    expect(find.byType(MiuixTopAppBar, skipOffstage: false), findsOneWidget);
  });

  testWidgets('每个上游一张卡：名称 / 类型 / 地址 / 备注都在', (tester) async {
    configStore.config.upstreams.add(
      upstream(note: '放客厅的 4060 机器'),
    );
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

    await tester.tap(find.byType(MiuixSwitch).first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(u.enabled, isFalse);
    expect(
      tester.widget<MiuixSwitch>(find.byType(MiuixSwitch).first).value,
      isFalse,
    );
  });

  testWidgets('自建上游的更多菜单：备注 / 查看 JSON / 删除', (tester) async {
    configStore.config.upstreams.add(upstream());
    await pumpPage(tester);

    await tester.tap(miuixIcon(AppIconNames.more).first);
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

    await tester.tap(miuixIcon(AppIconNames.more).first);
    await tester.pumpAndSettle();

    expect(find.text('查看车道'), findsOneWidget);
    expect(find.text('刷新可用模型'), findsOneWidget);
  });

  testWidgets('点卡片进上游编辑页', (tester) async {
    configStore.config.upstreams.add(upstream());
    await pumpPage(tester);

    await tester.tap(find.text('本地 llama'));
    await tester.pumpAndSettle();

    expect(find.byType(MiuixUpstreamEditPage), findsOneWidget);
  });

  testWidgets('内容不满一屏时上拉也会折叠标题（短页越界折叠）', (tester) async {
    await pumpPage(tester);
    // 一个上游都没有：内容不满一屏，pixels 永远钉在 0，
    // 上拉只产生越界量（视觉位移由 MiuixOverscrollIndicator 画）。
    expect(configStore.config.upstreams, isEmpty);
    // 展开态只有大标题一层
    expect(find.text('发现'), findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListView)),
    );
    await gesture.moveBy(const Offset(0, -100));
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    // 小标题的弹簧淡入晚一帧才可见
    await tester.pump(const Duration(milliseconds: 50));

    // 拖动中就应折叠出居中小标题（大标题 + 小标题两层）
    expect(find.text('发现'), findsNWidgets(2), reason: '上拉时标题要跟着折叠');

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // 折叠比例过半：松手后停在折叠态（对应 InstallerX 的短页吸附）
    expect(find.text('发现'), findsNWidgets(2));
  });
}
