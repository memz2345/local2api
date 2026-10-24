// dsh 插件管理页（Material / miuix 两套）的渲染回归：
//   · 标题、搜索框、安装入口都在；
//   · dsh 没装齐时给出「先装 dsh」的空态，而不是空白页。
//
// 只做渲染断言，不触发 npm / node 启动。

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/lab/dsh_plugins.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/dsh_plugins_page.dart';
import 'package:local2api/ui/miuix/miuix_dsh_plugins_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // 「除了手机操作，其他插件都启用不了」的回归：平台门控曾经一律要求
  // isDesktop，安卓上把编辑消息也挡掉了。现在按插件自己的宿主判定。
  test('内置插件的宿主限制：编辑消息不限平台，电脑操作仅 Windows，手机操作仅 Android', () {
    expect(dshPluginSpec(DshPluginId.messageEdit).host, DshPluginHost.any);
    expect(dshPluginSpec(DshPluginId.computerUse).host, DshPluginHost.windows);
    expect(dshPluginSpec(DshPluginId.androidControl).host, DshPluginHost.android);

    expect(
      dshPluginHostSupports(
        DshPluginHost.any,
        isWindows: false,
        isAndroid: true,
      ),
      isTrue,
    );
    expect(
      dshPluginHostSupports(
        DshPluginHost.windows,
        isWindows: false,
        isAndroid: true,
      ),
      isFalse,
    );
    expect(
      dshPluginHostSupports(
        DshPluginHost.android,
        isWindows: true,
        isAndroid: false,
      ),
      isFalse,
    );
    expect(dshPluginHostLabel(DshPluginHost.windows), 'Windows');
  });

  test('插件搜索：包名 / 展示名 / 描述都能命中', () {
    const plugin = ManagedDshPlugin(
      package: '@xt765/dsh-message-edit',
      displayName: '编辑消息',
      version: '0.1.1',
      description: '在用户消息气泡旁加铅笔按钮',
      homepage: null,
      installed: true,
      enabled: true,
      busy: false,
      recommended: true,
      supportedOnThisHost: true,
    );
    expect(plugin.matches(''), isTrue);
    expect(plugin.matches('xt765'), isTrue);
    expect(plugin.matches('编辑'), isTrue);
    expect(plugin.matches('铅笔'), isTrue);
    expect(plugin.matches('nope'), isFalse);
  });

  Future<void> pumpPage(
    WidgetTester tester,
    Widget page, {
    Size logicalSize = const Size(600, 1200),
  }) async {
    tester.view.physicalSize = Size(
      logicalSize.width * 2,
      logicalSize.height * 2,
    );
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
      MiuixThemeController(
        colorSchemeMode: MiuixColorSchemeMode.monetLight,
        keyColor: const Color(0xFF3482FF),
        child: app,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('miuix 插件页：标题 / 搜索 / 安装入口齐全', (tester) async {
    late AppLocalizations l10n;
    await pumpPage(
      tester,
      Builder(
        builder: (context) {
          l10n = AppLocalizations.of(context);
          return const MiuixDshPluginsPage();
        },
      ),
    );
    expect(find.text(l10n.pluginManagerTitle), findsWidgets);
    // miuix 版的搜索图标是自绘图标字体，按 TextField 找。
    expect(find.byType(TextField), findsOneWidget);
    // dsh 还没装好时必须给个说法，而不是一张空报表。
    expect(find.text(l10n.pluginManagerNotReady), findsOneWidget);
  });

  testWidgets('Material 插件页：同一份结构与文案', (tester) async {
    late AppLocalizations l10n;
    await pumpPage(
      tester,
      Builder(
        builder: (context) {
          l10n = AppLocalizations.of(context);
          return const DshPluginsPage();
        },
      ),
    );
    expect(find.text(l10n.pluginManagerTitle), findsWidgets);
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.text(l10n.pluginManagerNotReady), findsOneWidget);
  });

  const sample = <ManagedDshPlugin>[
    ManagedDshPlugin(
      package: '@xt765/dsh-message-edit',
      displayName: '编辑消息',
      version: '0.1.1',
      description: '在用户消息气泡旁加铅笔按钮，改完从上一轮分叉重发，'
          '省得把整段对话重贴一遍。这个描述故意写长一点，好让卡片默认只露两行。',
      homepage: 'https://github.com/xt765/dsh-message-edit',
      installed: true,
      enabled: true,
      busy: false,
      recommended: true,
      supportedOnThisHost: true,
    ),
    ManagedDshPlugin(
      package: 'dsh-computer-use-mode',
      displayName: '电脑操作',
      version: '0.1.1',
      description: '截屏 + 鼠标键盘控制，Windows 专用。',
      homepage: 'https://github.com/EvangeliMo/dsh-computer-use-mode',
      installed: false,
      enabled: false,
      busy: false,
      recommended: true,
      supportedOnThisHost: false,
      requiredHost: 'Windows',
    ),
    ManagedDshPlugin(
      package: 'dsh-third-party',
      version: '0.0.2',
      description: '第三方插件示例。',
      homepage: null,
      installed: false,
      enabled: false,
      busy: false,
      recommended: false,
      supportedOnThisHost: true,
    ),
  ];

  testWidgets('miuix 插件页：分组 / 折叠 / 搜索（360dp 窄屏不溢出）', (tester) async {
    late AppLocalizations l10n;
    await pumpPage(
      tester,
      Builder(
        builder: (context) {
          l10n = AppLocalizations.of(context);
          return const MiuixDshPluginsPage(debugItems: sample);
        },
      ),
      logicalSize: const Size(360, 780),
    );

    expect(find.text('编辑消息'), findsOneWidget);
    expect(find.text('电脑操作'), findsOneWidget);
    expect(find.text('dsh-third-party'), findsOneWidget);
    expect(find.text(l10n.pluginManagerOfficial), findsOneWidget);
    expect(find.text(l10n.pluginManagerDescTitle), findsOneWidget);
    // Windows 专用插件给出平台原因，而不是一个没有任何解释的灰开关。
    expect(find.text(l10n.pluginManagerOnlyOn('Windows')), findsOneWidget);

    // 点分组标题 → 内置那一组收起（卡片不再可点、读屏也看不到），再点回来。
    await tester.tap(find.text(l10n.pluginManagerOfficial));
    await tester.pumpAndSettle();
    expect(find.text('编辑消息').hitTestable(), findsNothing);
    expect(find.text('电脑操作').hitTestable(), findsNothing);
    // 第三方组不受影响
    expect(find.text('dsh-third-party').hitTestable(), findsOneWidget);

    await tester.tap(find.text(l10n.pluginManagerOfficial));
    await tester.pumpAndSettle();
    expect(find.text('编辑消息').hitTestable(), findsOneWidget);

    // 搜索时强制展开：内置组即使收起也要能看到命中的那一条。
    await tester.enterText(find.byType(TextField), '电脑');
    await tester.pumpAndSettle();
    expect(find.text('电脑操作'), findsOneWidget);
    expect(find.text('编辑消息'), findsNothing);
    expect(find.text('dsh-third-party'), findsNothing);
  });

  testWidgets('Material 插件页：分组 / 折叠 / 搜索', (tester) async {
    late AppLocalizations l10n;
    await pumpPage(
      tester,
      Builder(
        builder: (context) {
          l10n = AppLocalizations.of(context);
          return const DshPluginsPage(debugItems: sample);
        },
      ),
      logicalSize: const Size(360, 780),
    );
    expect(find.text('编辑消息'), findsOneWidget);
    expect(find.text(l10n.pluginManagerOnlyOn('Windows')), findsOneWidget);

    await tester.tap(find.text(l10n.pluginManagerOfficial));
    await tester.pumpAndSettle();
    expect(find.text('编辑消息').hitTestable(), findsNothing);

    await tester.enterText(find.byType(TextField), '编辑');
    await tester.pumpAndSettle();
    expect(find.text('编辑消息'), findsOneWidget);
    expect(find.text('dsh-third-party'), findsNothing);
  });
}
