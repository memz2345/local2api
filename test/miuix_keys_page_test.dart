import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/miuix/miuix_keys_page.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';
import 'package:local2api/widgets/swipe_action_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 密钥页 snackbar 的宿主问题（miuix 那一套）。
///
/// 用户报的 bug：左滑删完密钥，snackbar 在本页根本不弹，要退出密钥页才弹出来，
/// 而且退出后还挂在上一页。成因是这一页是 `MiuixScaffold`，底下没有 Material
/// `Scaffold` 能承载 `SnackBar`，app 级 `ScaffoldMessenger` 只能把它交给登记过的
/// 首页 Scaffold。修法是改挂在本页的 `MiuixSnackbarHost` 上。
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

  tearDown(() => controller.dispose());

  ApiKeyEntry addKey({required String name}) {
    final entry = ApiKeyEntry(
      id: 'k$name',
      name: name,
      key: 'sk-$name-0123456789',
    );
    configStore.config.apiKeys.add(entry);
    return entry;
  }

  Widget tree(Widget home) => MiuixThemeController(
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
          home: home,
        );
      },
    ),
  );

  /// 从另一页 push 进来 —— 真实入口是仪表盘的「管理密钥」，只有这条路径能暴露
  /// 「snackbar 弹到被盖住的首页上」。
  Future<void> pumpPushed(WidgetTester tester) async {
    await tester.pumpWidget(
      tree(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MiuixKeysPage(controller: controller),
                  ),
                ),
                child: const Text('去密钥页'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('去密钥页'));
    await tester.pumpAndSettle();
  }

  /// 左滑越过阈值（行宽 768，35% ≈ 269）并等「飞出 + 收起」跑完。
  Future<void> swipeAway(WidgetTester tester, Finder row) async {
    await tester.drag(row, const Offset(-320, 0));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pumpAndSettle();
  }

  testWidgets('删密钥：snackbar 当场弹在本页，点「恢复」能放回去', (tester) async {
    addKey(name: '手机');
    await pumpPushed(tester);

    await swipeAway(tester, find.byType(SwipeActionRow));

    expect(configStore.config.apiKeys, isEmpty);
    expect(find.text('已删除 1 个密钥'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('已删除 1 个密钥'), matching: find.byType(MiuixKeysPage)),
      findsOneWidget,
      reason: 'snackbar 必须挂在密钥页这一棵子树里，不是被盖住的首页',
    );

    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();

    expect(configStore.config.apiKeys.map((k) => k.name), ['手机']);
    // 「已恢复」那条 toast 有自己的存活时长，收尾推干净
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('退出密钥页时 snackbar 跟着销毁，不挂到上一页', (tester) async {
    addKey(name: '手机');
    await pumpPushed(tester);

    await swipeAway(tester, find.byType(SwipeActionRow));
    expect(find.text('已删除 1 个密钥'), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect(find.text('已删除 1 个密钥'), findsNothing);
    expect(find.byType(MiuixSnackbar), findsNothing);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('连着删两条：只留一条 snackbar，条数累加', (tester) async {
    addKey(name: 'A');
    addKey(name: 'B');
    await pumpPushed(tester);

    await swipeAway(tester, find.byType(SwipeActionRow).first);
    await swipeAway(tester, find.byType(SwipeActionRow).first);

    expect(configStore.config.apiKeys, isEmpty);
    expect(find.text('已删除 2 个密钥'), findsOneWidget);
    expect(find.text('已删除 1 个密钥'), findsNothing, reason: '旧那条要被顶掉，不是排队');

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });
}
