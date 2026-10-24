// 实验室页（Material / miuix 两套）回归：
//   · 两个本地服务：SillyTavern + DeepSeek Harness（dsh）；
//   · 首页每个服务只有一个开关 + 「更多设置」一个入口（打开 / 日志 / 状态
//     说明都撤了，打开入口在「更多设置」里），版本号不进首页；
//   · miuix 的入口换成设置页同款 MiuixArrowPreference（箭头右对齐）；
//
// 只做渲染断言，不触发下载 / npm（那些要网络与 Node 环境）。
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/lab/silly_tavern_service.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/dsh_page.dart';
import 'package:local2api/ui/lab_page.dart';
import 'package:local2api/ui/lab_sillytavern_page.dart';
import 'package:local2api/ui/miuix/miuix_dsh_page.dart';
import 'package:local2api/ui/miuix/miuix_lab_page.dart';
import 'package:local2api/ui/miuix/miuix_lab_sillytavern_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpPage(
    WidgetTester tester,
    Widget page, {
    bool miuix = false,
  }) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final app = MaterialApp(
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light(),
      home: page,
    );
    await tester.pumpWidget(
      miuix
          ? MiuixThemeController(
              colorSchemeMode: MiuixColorSchemeMode.monetLight,
              keyColor: const Color(0xFF3482FF),
              child: app,
            )
          : app,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Material 实验室页：两个服务 + 开关 + 更多设置入口', (tester) async {
    await pumpPage(tester, const LabPage());

    expect(find.text('SillyTavern'), findsOneWidget);
    expect(find.text('DeepSeek Harness'), findsOneWidget);
    expect(find.text('更多设置'), findsNWidgets(2));
    // 打开 / 日志 / 状态说明都只在「更多设置」页，首页不再出现。
    expect(find.text('日志'), findsNothing);
    expect(find.text('打开'), findsNothing);
    expect(find.textContaining('运行于'), findsNothing);
    // 首页不再摆图标、也没有内置浏览器卡片。
    expect(find.text('内置浏览器'), findsNothing);
    expect(find.byIcon(Icons.theater_comedy_outlined), findsNothing);
    expect(find.byType(Switch), findsNWidgets(2));
    // 版本号从首页撤掉（只在更多设置页看得到）。
    expect(find.textContaining('v1.'), findsNothing);
    // 首页不再直接给「安装」按钮（挪进更多设置）。
    expect(find.text('安装'), findsNothing);
  });

  testWidgets('miuix 实验室页：同一份服务，换一套渲染', (tester) async {
    await pumpPage(tester, const MiuixLabPage(), miuix: true);

    expect(find.text('SillyTavern'), findsOneWidget);
    expect(find.text('DeepSeek Harness'), findsOneWidget);
    // 两个服务各一行「更多设置」，用设置页同款箭头行（右对齐）。
    expect(find.text('更多设置'), findsNWidgets(2));
    expect(find.byType(MiuixArrowPreference), findsNWidgets(2));
    expect(find.text('日志'), findsNothing);
    expect(find.text('打开'), findsNothing);
    expect(find.textContaining('运行于'), findsNothing);
    expect(find.text('内置浏览器'), findsNothing);
    expect(find.byType(MiuixSwitch), findsNWidgets(2));
    expect(find.textContaining('v1.'), findsNothing);
  });

  testWidgets('Material 更多设置页：安装 / 状态 / API 配置都在', (tester) async {
    await pumpPage(tester, const LabSillyTavernPage());

    expect(find.text('运行状态'), findsOneWidget);
    expect(find.text('安装位置'), findsOneWidget);
    expect(find.text('API 配置'), findsOneWidget);
    // 测试里没有 ServerController：API 区给出「先启动服务」提示。
    expect(find.text('没连上本机服务，先在仪表盘启动服务'), findsOneWidget);
  });

  testWidgets('miuix 更多设置页：同构', (tester) async {
    await pumpPage(tester, const MiuixLabSillyTavernPage(), miuix: true);

    expect(find.text('运行状态'), findsOneWidget);
    expect(find.text('安装位置'), findsOneWidget);
    expect(find.text('API 配置'), findsOneWidget);
    // 自动打开浏览器开关（默认关）。
    expect(find.text('启动后自动打开浏览器'), findsOneWidget);
  });

  testWidgets('dsh 更多设置页（两套 UI）都能渲染模型配置', (tester) async {
    await pumpPage(tester, const DshPage());
    expect(find.text('运行状态'), findsOneWidget);
    expect(find.text('安装位置'), findsOneWidget);
    expect(find.text('API 配置'), findsOneWidget);
    expect(find.text('默认模型'), findsOneWidget);
    expect(find.text('配置文件'), findsOneWidget);

    await pumpPage(tester, const MiuixDshPage(), miuix: true);
    expect(find.text('运行状态'), findsOneWidget);
    expect(find.text('安装位置'), findsOneWidget);
    expect(find.text('API 配置'), findsOneWidget);
  });

  testWidgets('未安装时打开开关：弹「先去安装」而不是静默失败', (tester) async {
    final st = SillyTavernService.instance;
    await st.init();
    expect(st.installed, isFalse);

    await pumpPage(tester, const MiuixLabPage(), miuix: true);
    await tester.tap(find.byType(MiuixSwitch).first);
    await tester.pumpAndSettle();

    expect(find.text('还没有安装 SillyTavern'), findsOneWidget);
    expect(find.text('去设置'), findsOneWidget);
  });
}
