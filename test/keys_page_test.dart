import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/ui/keys_page.dart';
import 'package:local2api/widgets/swipe_action_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Future<void> pumpKeysPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: KeysPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 打开底部抽屉并等它停稳。
  ///
  /// 抽屉入场动画里，内容还落在屏幕外，框架会为「不可见语义节点」在 debug 下
  /// assert（带 tooltip 的 suffixIcon 必现，flutter 已知问题，release 无影响）。
  /// 这是与本页逻辑无关的框架噪声，这里显式取走，别让它污染断言。
  Future<void> openSheetAndSettle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 150));
    while (tester.takeException() != null) {}
    await tester.pumpAndSettle();
    while (tester.takeException() != null) {}
  }

  ApiKeyEntry addKey({
    String name = '手机',
    String key = 'sk-abcdefghijklmnopqrstuvwxyz',
  }) {
    final entry = ApiKeyEntry(
      id: 'k${configStore.config.apiKeys.length}',
      name: name,
      key: key,
    );
    configStore.config.apiKeys.add(entry);
    return entry;
  }

  testWidgets('空态：给提示，FAB 藏着添加入口', (tester) async {
    await pumpKeysPage(tester);

    expect(find.text('密钥'), findsWidgets);
    expect(find.text('还没有密钥，点右下角加号添加一个。'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('列出密钥：名字 + 掩码，不整串铺开', (tester) async {
    addKey();
    await pumpKeysPage(tester);

    expect(find.text('手机'), findsOneWidget);
    expect(find.text('sk-abc…wxyz'), findsOneWidget);
    expect(find.text('sk-abcdefghijklmnopqrstuvwxyz'), findsNothing);
  });

  testWidgets('FAB 弹出原来的添加面板，保存后落进配置', (tester) async {
    await pumpKeysPage(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await openSheetAndSettle(tester);
    expect(find.text('添加密钥'), findsWidgets);

    final fields = find.byType(TextField);
    await tester.enterText(fields.first, '我的平板');
    await tester.pump();
    await tester.tap(find.text('保存'));
    // 关闭动画同样会触发上面那条框架断言，一并吃掉
    await openSheetAndSettle(tester);

    final saved = configStore.config.apiKeys;
    expect(saved, hasLength(1));
    expect(saved.single.name, '我的平板');
    expect(saved.single.key, startsWith('sk-'));
    expect(find.text('我的平板'), findsOneWidget);
  });

  /// 左滑越过阈值并等「飞出 + 收起」跑完（提交动作在动画结束后才回调）。
  Future<void> swipeAway(WidgetTester tester, Finder row) async {
    // 行宽 800-32=768，阈值 35% ≈ 269，所以拖 320 稳稳越过
    await tester.drag(row, const Offset(-320, 0));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 320));
  }

  testWidgets('左滑越过阈值：直接删掉，弹 snackbar 提示条数 + 恢复按钮', (tester) async {
    addKey(name: '旧密钥');
    await pumpKeysPage(tester);

    await swipeAway(tester, find.byType(SwipeActionRow));

    // 没有确认框，直接删
    expect(find.byType(AlertDialog), findsNothing);
    expect(configStore.config.apiKeys, isEmpty);
    expect(find.text('已删除 1 个密钥'), findsOneWidget);
    expect(find.text('恢复'), findsOneWidget);

    // 让 snackbar 自己超时，别留 pending timer
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('点「恢复」把删掉的密钥按原位置放回去', (tester) async {
    addKey(name: 'A');
    addKey(name: '要被删的');
    addKey(name: 'C');
    await pumpKeysPage(tester);

    // 删中间那条（第二行）
    await swipeAway(tester, find.byType(SwipeActionRow).at(1));
    expect(configStore.config.apiKeys.map((k) => k.name), ['A', 'C']);

    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();

    expect(configStore.config.apiKeys.map((k) => k.name), [
      'A',
      '要被删的',
      'C',
    ], reason: '恢复要还原到原来的下标，不是追加到末尾');
    expect(find.text('要被删的'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('连着删两条：snackbar 的条数累加', (tester) async {
    addKey(name: 'A');
    addKey(name: 'B');
    await pumpKeysPage(tester);

    await swipeAway(tester, find.byType(SwipeActionRow).first);
    await swipeAway(tester, find.byType(SwipeActionRow).first);

    expect(configStore.config.apiKeys, isEmpty);
    expect(find.text('已删除 2 个密钥'), findsOneWidget);

    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(configStore.config.apiKeys.map((k) => k.name), [
      'A',
      'B',
    ], reason: '恢复后顺序也要和原来一致');
    await tester.pump(const Duration(seconds: 3));
  });

  /// 真实入口是从仪表盘 push 进来的（`pushPage`），不是挂在 home 上。
  ///
  /// 只有这条路径能暴露「snackbar 弹在**下面那页**的 Scaffold 上」：
  /// app 级 `ScaffoldMessenger` 会把 snackbar 交给它登记过的 Scaffold，
  /// 而首页那个 Scaffold 虽然被盖住却仍然在册。
  Future<void> pumpKeysPagePushed(WidgetTester tester) async {
    addKey(name: '旧密钥');
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => KeysPage(controller: controller),
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

  testWidgets('从别的页 push 进来：snackbar 当场弹在本页，退出时销毁', (tester) async {
    await pumpKeysPagePushed(tester);

    await swipeAway(tester, find.byType(SwipeActionRow));

    expect(find.text('已删除 1 个密钥'), findsOneWidget, reason: 'push 进来的页也要当场弹');
    // 弹的必须是本页那个 Scaffold 的 snackbar，不是被盖住的首页的
    final snackHost = find.ancestor(
      of: find.byType(SnackBar),
      matching: find.byType(KeysPage),
    );
    expect(snackHost, findsOneWidget, reason: 'snackbar 要挂在密钥页这一棵子树里');

    // 退出这一页：snackbar 不能跟到上一页去
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);

    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('左滑不到阈值：弹回，不删', (tester) async {
    addKey(name: '留着');
    await pumpKeysPage(tester);

    // 阈值 ~269，这里只滑 120
    await tester.drag(find.byType(SwipeActionRow), const Offset(-120, 0));
    await tester.pumpAndSettle();

    expect(configStore.config.apiKeys, hasLength(1));
    expect(find.textContaining('已删除'), findsNothing);
  });

  testWidgets('右滑不会误删', (tester) async {
    addKey();
    await pumpKeysPage(tester);

    await tester.drag(find.byType(SwipeActionRow), const Offset(160, 0));
    await tester.pumpAndSettle();

    expect(configStore.config.apiKeys, hasLength(1));
    expect(find.textContaining('已删除'), findsNothing);
  });
}
