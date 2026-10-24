import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'miuix_finders.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/screens/miuix/miuix_display_settings_screen.dart';
import 'package:local2api/services/app_settings.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/services/tts/tts_settings.dart';
import 'package:local2api/src/enums.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/miuix/miuix_chat_settings_page.dart';
import 'package:local2api/ui/miuix/miuix_ip_rules_page.dart';
import 'package:local2api/ui/miuix/miuix_logs_page.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';
import 'package:local2api/ui/miuix/miuix_network_settings_page.dart';
import 'package:local2api/ui/miuix/miuix_settings_page.dart';
import 'package:local2api/ui/miuix/miuix_theme_quick_sheet.dart';
import 'package:local2api/ui/miuix/miuix_upstream_edit_page.dart';
import 'package:local2api/ui/miuix/miuix_upstream_models_page.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConfigStore configStore;
  late ServerController controller;
  late SettingsService displaySettings;
  late AppSettings appSettings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    configStore = ConfigStore();
    await configStore.load();
    controller = ServerController(configStore);
    displaySettings = SettingsService();
    appSettings = AppSettings();
  });

  tearDown(() {
    configStore.dispose();
    controller.dispose();
    displaySettings.dispose();
    appSettings.dispose();
  });

  Widget miuixTree(Widget body) => MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsService>.value(value: displaySettings),
    ],
    child: MiuixThemeController(
      colorSchemeMode: miuixColorSchemeModeOf(themeMode: ThemeMode.light),
      keyColor: const Color(0xFF386A20),
      child: Builder(
        builder: (context) {
          final miuix = MiuixTheme.of(context);
          return MaterialApp(
            // 不钉 locale 的话测试环境默认 en_US，中文断言全对不上
            locale: const Locale('zh', 'CN'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light().copyWith(
              colorScheme: materialSchemeFromMiuix(miuix.colors, miuix.brightness),
            ),
            home: Scaffold(body: body),
          );
        },
      ),
    ),
  );

  void useTallView(WidgetTester tester) {
    // 这些页面很长，默认 800x600 会溢出
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// 直接把页面挂在根路由上（适用于没有出栈动作的页面）。
  Future<void> pumpBody(WidgetTester tester, Widget body) async {
    useTallView(tester);
    await tester.pumpWidget(miuixTree(body));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  /// push 到占位 base 之上：上游编辑页保存时会 Navigator.pop，
  /// 挂在根路由上会把整个路由栈清空。
  Future<void> pumpPushed(WidgetTester tester, Widget page) async {
    useTallView(tester);
    await tester.pumpWidget(miuixTree(const SizedBox.shrink()));
    await tester.pumpAndSettle();
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(MaterialPageRoute<void>(builder: (_) => page));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  /// 触发 toast 之后要推进时钟：提示是一条 2s（miuix 侧 4s）的浮动条，
  /// 不等它跑完会在 teardown 时留下未清的 Timer。
  Future<void> settleAfterToast(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  group('miuix 设置页', () {
    /// 设置页后来又加了「临时 WebUI / 峰谷时段」两个分区，整体高度超过
    /// 公共的 1400 —— 视口不够高时 ListView 只构建可见范围，靠下的行
    /// （语言 / 关于）压根不会进树。所以设置页单独再拔高一档。
    Future<void> pumpSettings(WidgetTester tester) async {
      await pumpBody(
        tester,
        MiuixSettingsPage(controller: controller, settings: appSettings),
      );
      // 必须在 pumpBody 之后改：它内部会自己钉一遍视口，先改会被覆盖。
      tester.view.physicalSize = const Size(420, 2600);
      tester.view.devicePixelRatio = 1.0;
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
    }

    testWidgets('分区与二级页入口齐全', (tester) async {
      await pumpSettings(tester);

      expect(find.text('设置'), findsOneWidget);
      expect(find.byType(MiuixTopAppBar, skipOffstage: false), findsOneWidget);
      // 服务与功能：两个二级页入口（带副标题说明），具体配置都搬进去了
      expect(find.text('服务与功能'), findsOneWidget);
      expect(find.text('网络设置'), findsOneWidget);
      expect(find.text('端口与监听、临时 WebUI、IP 访问规则'), findsOneWidget);
      expect(find.text('对话设置'), findsOneWidget);
      expect(find.text('TTS 设置、自动播放与角色卡'), findsOneWidget);
      // 端口 / IP 规则这些行不再平铺在设置页上
      expect(find.text('监听地址'), findsNothing);
      expect(find.text('监听端口'), findsNothing);
      expect(find.text('外观'), findsWidgets);
      // 图1 / InstallerX 主题设置三项：主题模式 / 启用模糊 / 自定义颜色
      expect(find.text('主题模式'), findsOneWidget);
      expect(find.text('启用模糊'), findsOneWidget);
      // 渐变模糊顶栏开关跟在「启用模糊」后面（模糊默认开 → 可见）
      expect(find.text('渐变模糊顶栏'), findsOneWidget);
      expect(find.text('自定义颜色'), findsOneWidget);
      expect(find.text('显示设置'), findsOneWidget);
      expect(find.text('界面风格'), findsOneWidget);
      // 这行显示的是**当前选中**的那套风格（出厂默认 miuix）；下拉里的另一项
      // 要点开才进树，所以这里断言它不在，另两项的覆盖在「界面风格写进
      // SettingsService」那条用例里做。
      expect(find.text('小米 HyperOS'), findsOneWidget);
      expect(find.text('Material 3 Expressive'), findsNothing);
      expect(find.text('语言'), findsOneWidget);
      // 关于改成了入口行（分区小标题 + 行标题，同名两处），版本挪进了关于页
      expect(find.text('关于'), findsNWidgets(2));
      expect(find.text('版本、组件与效果背景'), findsOneWidget);
    });

    testWidgets('渐变模糊顶栏开关只在「启用模糊」开着时显示', (tester) async {
      await pumpSettings(tester);
      expect(find.text('渐变模糊顶栏'), findsOneWidget);

      // 关掉模糊总开关 → 开关整体消失（它是模糊的一种形态）。
      await displaySettings.setUseBlur(false);
      await tester.pumpAndSettle();
      expect(find.text('渐变模糊顶栏'), findsNothing);

      // 重新打开 → 回来。
      await displaySettings.setUseBlur(true);
      await tester.pumpAndSettle();
      expect(find.text('渐变模糊顶栏'), findsOneWidget);
    });

    testWidgets('界面风格写进 SettingsService', (tester) async {
      // 出厂默认就是 miuix：这行一开始显示「小米 HyperOS」
      await pumpSettings(tester);
      expect(displaySettings.uiStyle, UiStyle.miuix);

      await tester.tap(find.text('界面风格'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Material 3 Expressive'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(displaySettings.uiStyle, UiStyle.materialExpressive);
      expect(find.text('Material 3 Expressive'), findsOneWidget);

      // 再切回 miuix（用户选过的两个值都要能落盘）
      await tester.tap(find.text('界面风格'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.tap(find.text('小米 HyperOS'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(displaySettings.uiStyle, UiStyle.miuix);
      expect(find.text('小米 HyperOS'), findsOneWidget);
    });

    testWidgets('对话设置：TTS 拆成独立页 + 自动播放开关落盘', (tester) async {
      await pumpPushed(tester, MiuixChatSettingsPage(controller: controller));

      // 入口行与开关都在，具体 TTS 配置不再平铺在对话设置上
      expect(find.text('TTS 设置'), findsOneWidget);
      expect(find.text('本地模型、服务商与试听'), findsOneWidget);
      expect(find.text('自动播放 TTS'), findsOneWidget);
      expect(find.text('本地 TTS（Qwen3-TTS）'), findsNothing);
      // 那段长说明按需求删掉了（本地 TTS 卡片自己也不再挂说明）
      expect(find.textContaining('下载 Qwen3-TTS 1.7B 模型后'), findsNothing);

      final tts = TtsSettings.instance;
      await tts.load();
      await tts.setAutoPlay(false);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.byType(MiuixSwitch), findsOneWidget);

      await tester.tap(find.byType(MiuixSwitch).first);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(tts.autoPlay, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('tts.autoPlay'), isTrue);

      // 再点一次关掉：关是把键删掉（保持 prefs 干净）
      await tester.tap(find.byType(MiuixSwitch).first);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(tts.autoPlay, isFalse);
      expect(prefs.containsKey('tts.autoPlay'), isFalse);
    });

    testWidgets('语言写进 AppSettings', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.text('语言'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      await tester.tap(find.text('English'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(appSettings.localeCode, 'en-US');
    });

    testWidgets('显示设置跳 miuix 版子页', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.text('显示设置'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.byType(MiuixDisplaySettingsScreen), findsOneWidget);
      expect(find.text('个性化'), findsOneWidget);
    });
  });

  group('miuix 网络设置页', () {
    Future<void> pumpNetwork(WidgetTester tester) async {
      await pumpBody(
        tester,
        MiuixNetworkSettingsPage(controller: controller),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }

    testWidgets('端口与监听等配置行齐全', (tester) async {
      await pumpNetwork(tester);

      expect(find.text('网络设置'), findsOneWidget);
      expect(find.text('网络'), findsOneWidget);
      expect(find.text('Cloudflare Tunnel / Tailscale'), findsOneWidget);
      expect(find.text('监听地址'), findsOneWidget);
      expect(find.text('所有网卡 (0.0.0.0)'), findsOneWidget);
      expect(find.text('监听端口'), findsOneWidget);
      expect(find.text('启动时自动运行服务'), findsOneWidget);
      expect(find.text('允许跨域（CORS）'), findsOneWidget);
      expect(find.text('临时 WebUI'), findsWidgets);
      // IP 访问规则变成入口行：空配置显示默认放行说明
      expect(find.text('IP 访问规则'), findsOneWidget);
      expect(find.text('暂无规则，默认放行所有来源'), findsOneWidget);
    });

    testWidgets('开关写回 ProxyConfig（cors 与自启动）', (tester) async {
      await pumpNetwork(tester);
      expect(configStore.config.corsEnabled, isTrue);
      expect(configStore.config.autoStart, isFalse);

      await tester.tap(find.text('允许跨域（CORS）'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(configStore.config.corsEnabled, isFalse);

      await tester.tap(find.text('启动时自动运行服务'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(configStore.config.autoStart, isTrue);
    });

    testWidgets('端口输入写回 ProxyConfig', (tester) async {
      await pumpNetwork(tester);
      final portField = find.byType(TextField);
      expect(portField, findsOneWidget);

      await tester.enterText(portField, '9399');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(configStore.config.listenPort, 9399);

      // 越界值不写回
      await tester.enterText(portField, '80');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(configStore.config.listenPort, 9399);
    });

    testWidgets('监听地址走 miuix 单选抽屉', (tester) async {
      await pumpNetwork(tester);
      await tester.tap(find.text('监听地址'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('仅本机 (127.0.0.1)'), findsOneWidget);
      await tester.tap(find.text('仅本机 (127.0.0.1)'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(configStore.config.listenHost, '127.0.0.1');
      expect(find.text('仅本机 (127.0.0.1)'), findsOneWidget);
    });
  });

  group('miuix IP 规则页', () {
    Future<void> pumpRules(WidgetTester tester) async {
      await pumpBody(tester, MiuixIpRulesPage(controller: controller));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }

    testWidgets('添加 IP 规则：合法 CIDR 落进配置', (tester) async {
      await pumpRules(tester);

      expect(find.text('IP 访问规则'), findsOneWidget);
      expect(find.text('暂无规则，默认放行所有来源'), findsOneWidget);

      // 右下角 FAB 添加
      await tester.tap(miuixIcon(AppIconNames.add));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('添加规则'), findsWidgets);
      await tester.enterText(find.byType(TextField), '192.168.0.0/16');
      await tester.pump();
      await tester.tap(find.text('拒绝'));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      final rules = configStore.config.cidrRules;
      expect(rules, hasLength(1));
      expect(rules.single.cidr, '192.168.0.0/16');
      expect(rules.single.allow, isFalse);
      expect(find.text('192.168.0.0/16'), findsOneWidget);
      expect(find.text('暂无规则，默认放行所有来源'), findsNothing);
    });

    testWidgets('左滑删除规则并可通过 snackbar 恢复', (tester) async {
      configStore.config.cidrRules.add(
        CidrRule(id: 'r1', cidr: '10.0.0.0/8', allow: true),
      );
      await pumpRules(tester);
      expect(find.text('10.0.0.0/8'), findsOneWidget);

      // 左滑越过行宽 35% 松手即删（不弹确认框）
      await tester.drag(find.text('10.0.0.0/8'), const Offset(-300, 0));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(configStore.config.cidrRules, isEmpty);

      // snackbar 带「恢复」，点了放回去
      await tester.tap(find.text('恢复'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(configStore.config.cidrRules, hasLength(1));
      expect(find.text('10.0.0.0/8'), findsOneWidget);
    });
  });

  group('miuix 日志页', () {
    testWidgets('空态显示暂无请求日志', (tester) async {
      await pumpBody(tester, MiuixLogsPage(controller: controller));
      expect(find.text('请求日志'), findsOneWidget);
      expect(find.text('暂无请求日志'), findsOneWidget);
      expect(find.byType(MiuixBlurTopBar, skipOffstage: false), findsOneWidget);
      expect(miuixIcon(AppIconNames.back), findsOneWidget);
    });

    testWidgets('列出请求并可一键清空', (tester) async {
      controller.server.logs.value = [
        RequestLogEntry(
          time: DateTime(2026, 10, 7, 9, 8, 7),
          method: 'POST',
          path: '/v1/chat/completions',
          model: 'qwen',
          upstream: '本机 llama',
          status: 502,
          durationMs: 37,
          client: '192.168.1.20',
          error: '上游返回 502',
        ),
      ];
      await pumpBody(tester, MiuixLogsPage(controller: controller));

      expect(find.text('POST /v1/chat/completions'), findsOneWidget);
      expect(find.text('502'), findsOneWidget);
      expect(find.text('37ms'), findsOneWidget);
      expect(find.text('上游返回 502'), findsOneWidget);

      await tester.tap(miuixIcon(AppIconNames.delete));
      await settleAfterToast(tester);

      expect(controller.server.logs.value, isEmpty);
      expect(find.text('暂无请求日志'), findsOneWidget);
    });
  });

  group('miuix 上游编辑页（CMFA 式一行一字段）', () {
    testWidgets('新建：点行改名称与模式，顶栏 ✔ 写盘', (tester) async {
      await pumpPushed(tester, MiuixUpstreamEditPage(controller: controller));

      expect(find.text('新建上游'), findsOneWidget);
      // 一行一字段，没填的行显示灰占位「未填写」：名称 / 密钥 / 备注 / 峰谷时段
      expect(find.text('名称'), findsOneWidget);
      expect(find.text('URL'), findsOneWidget);
      expect(find.text('模式'), findsOneWidget);
      expect(find.text('未填写'), findsNWidgets(4));
      // 模型不在这一页铺开，只显示数量
      expect(find.text('对外模型'), findsOneWidget);
      expect(find.text('没有对外暴露的模型'), findsOneWidget);
      // 保存不再是页面底部的大按钮
      expect(find.text('保存'), findsNothing);

      // 「模式」行 → 选择面板 → Ollama，新建时地址跟着换成该类型默认值
      await tester.tap(find.text('模式'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('选择模式'), findsOneWidget);
      await tester.tap(find.text('Ollama'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('http://192.168.1.10:11434/v1'), findsOneWidget);

      // 「名称」行 → 编辑器抽屉 → 确定
      await tester.tap(find.text('名称'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '我的 Ollama');
      await tester.pump();
      await tester.tap(find.text('确定'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('我的 Ollama'), findsOneWidget);

      await tester.tap(miuixIcon(AppIconNames.check));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      final saved = configStore.config.upstreams;
      expect(saved, hasLength(1));
      expect(saved.single.name, '我的 Ollama');
      expect(saved.single.type, UpstreamType.ollama);
      expect(saved.single.baseUrl, 'http://192.168.1.10:11434/v1');
      expect(find.byType(MiuixUpstreamEditPage), findsNothing);
    });

    testWidgets('必填校验：空名称与非法地址都不写盘', (tester) async {
      await pumpPushed(tester, MiuixUpstreamEditPage(controller: controller));

      await tester.tap(miuixIcon(AppIconNames.check));
      await settleAfterToast(tester);
      expect(configStore.config.upstreams, isEmpty);

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

      await tester.tap(miuixIcon(AppIconNames.check));
      await settleAfterToast(tester);

      expect(configStore.config.upstreams, isEmpty);
      expect(find.byType(MiuixUpstreamEditPage), findsOneWidget);
    });

    testWidgets('编辑：改掉 baseUrl 保存回原上游，模型行进独立模型页', (tester) async {
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
        MiuixUpstreamEditPage(controller: controller, upstream: upstream),
      );

      expect(find.text('编辑上游'), findsOneWidget);
      expect(find.text('本机 llama'), findsOneWidget);
      // 模型不铺开，只显示「1 个模型」
      expect(find.text('qwen'), findsNothing);
      expect(find.text('1 个模型'), findsOneWidget);

      await tester.tap(find.text('对外模型'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.byType(MiuixUpstreamModelsPage), findsOneWidget);
      expect(find.text('qwen'), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.byType(MiuixUpstreamEditPage), findsOneWidget);

      await tester.tap(find.text('URL'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'http://10.0.0.5:9999/v1');
      await tester.tap(find.text('确定'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      await tester.tap(miuixIcon(AppIconNames.check));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(upstream.baseUrl, 'http://10.0.0.5:9999/v1');
      expect(configStore.config.upstreams, hasLength(1));
    });

    testWidgets('顶栏删除动作弹出 miuix 确认对话框并摘掉上游', (tester) async {
      final upstream = Upstream(
        id: 'u1',
        name: '本机 llama',
        baseUrl: 'http://127.0.0.1:8080/v1',
      );
      configStore.update(ProxyConfig(upstreams: [upstream]));
      await pumpPushed(
        tester,
        MiuixUpstreamEditPage(controller: controller, upstream: upstream),
      );

      await tester.tap(miuixIcon(AppIconNames.delete));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('删除上游「本机 llama」？'), findsOneWidget);

      await tester.tap(find.text('删除'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(configStore.config.upstreams, isEmpty);
      expect(find.byType(MiuixUpstreamEditPage), findsNothing);
    });
  });

  group('miuix 外观快速面板', () {
    Future<void> pumpSheet(WidgetTester tester) => pumpBody(
      tester,
      Builder(
        builder: (context) => Center(
          child: MiuixButton(
            onPressed: () => showMiuixThemeQuickSheet(context),
            child: const MiuixText('打开外观面板'),
          ),
        ),
      ),
    );

    testWidgets('主题模式三档写进 SettingsService', (tester) async {
      await pumpSheet(tester);
      await tester.tap(find.text('打开外观面板'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('外观快速设置'), findsOneWidget);
      expect(find.byType(MiuixTabRow), findsOneWidget);
      expect(displaySettings.themeMode, ThemeMode.system);

      await tester.tap(find.text('深色'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(displaySettings.themeMode, ThemeMode.dark);
    });

    testWidgets('纯黑与跟随系统配色两个开关都生效', (tester) async {
      await pumpSheet(tester);
      await tester.tap(find.text('打开外观面板'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.byType(MiuixSwitch), findsNWidgets(2));
      await tester.tap(find.byType(MiuixSwitch).first);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(displaySettings.isPureBlackMode, isTrue);

      await tester.tap(find.byType(MiuixSwitch).last);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(displaySettings.useDynamicColor, isTrue);
    });
  });
}
