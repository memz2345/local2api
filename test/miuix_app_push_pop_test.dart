import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/app_settings.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/src/enums.dart';
import 'package:local2api/ui/app.dart';
import 'package:local2api/ui/miuix/miuix_create_config_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归：miuix 模式下「推入 / 弹出任意页面」不能炸。
///
/// 曾经的 bug：miuix 的越界指示器（`MiuixOverscrollIndicator`）把回位
/// 控制器写成 `late final AnimationController.unbounded(vsync: this)` 惰性
/// 初始化。从没滚动过的列表（短页面）一辈子不会碰它，于是 `dispose()` 里
/// `_settle.dispose()` 才第一次触发初始化 → `createTicker` 去查 `TickerMode`
/// 祖先 —— 此刻 element 已 deactivate，直接抛
/// 「Looking up a deactivated widget's ancestor is unsafe」。
/// miuix 模式下每个竖向列表都挂着这层指示器（`MiuixOverscrollBehavior`），
/// 所以点加号进创建配置页、再返回，两个方向都会炸。
///
/// 这个用例特意搭**真 app 树**（`Local2ApiApp`）而不是单页：越界行为是
/// app 级 scrollBehavior 装的，只 pump 单页根本碰不到它。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('miuix：发现页加号推入创建配置页、再返回都不报异常', (tester) async {
    // 窄屏（700x1400 逻辑像素 < 768）→ HomeShell 那条路径；
    // 宽度给足是为了避开测试字体偏宽造成的伪溢出
    tester.view.physicalSize = const Size(1400, 2800);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings();
    final displaySettings = SettingsService();
    final store = ConfigStore();
    final profileStore = ProfileStore();
    await Future.wait([
      settings.load(),
      displaySettings.load(),
      store.load(),
      profileStore.load(),
    ]);
    await displaySettings.setUiStyle(UiStyle.miuix);
    final controller = ServerController(store);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: displaySettings),
          ChangeNotifierProvider<ProfileStore>.value(value: profileStore),
        ],
        child: Local2ApiApp(settings: settings, controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    // 切到发现页（底栏第二个标签）
    await tester.tap(find.text('Discover').first);
    await tester.pumpAndSettle();
    expect(find.text('Discover'), findsWidgets);

    // 点加号（miuix 壳用 MiuixFloatingActionButton）
    await tester.tap(find.byType(MiuixFloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.byType(MiuixCreateConfigPage), findsOneWidget);

    // 返回：新页（连同它列表上的越界指示器）dispose，不再抛异常
    final NavigatorState navigator = tester.state(find.byType(Navigator).first);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.byType(MiuixCreateConfigPage), findsNothing);
  });
}