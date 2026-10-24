// miuix 首页 FAB 的回归：鼠标 hover 开着气泡时，父级重建不能把红块炸出来。
//
// 症状（只在桌面端出现，触屏没有 hover 所以看不到）：
//   setState() or markNeedsBuild() called during build.
//   The widget on which setState() or markNeedsBuild() was called was:
//     _OverlayEntryWidget-…
//   The widget which was currently being built when the offending call was made was:
//     _MiuixFab
// 根因在 flutter_miuix 1.3.0：`_MiuixTooltipBoxState.didUpdateWidget` 在气泡
// 还开着时直接对 OverlayEntry 调 markNeedsBuild()，而父级重建发生在 build
// 阶段内。修法见 miuix_home_fab.dart 的 _MiuixFab 文档（缓存气泡的 widget
// 实例，走 Element.updateChild 的「实例相同」快路径）。
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/miuix/miuix_home_fab.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConfigStore store;
  late ServerController controller;
  late SettingsService display;
  var rebuilds = 0;

  setUp(() async {
    rebuilds = 0;
    SharedPreferences.setMockInitialValues({});
    store = ConfigStore();
    await store.load();
    controller = ServerController(store);
    controller.webUiAutoStart = false;
    display = SettingsService();
    await display.load();
  });

  tearDown(() {
    controller.dispose();
    display.dispose();
  });

  /// 外壳：MiuixTheme + MaterialApp + 一个 Scaffold，FAB 挂在槽位上。
  /// [nonce] 变一次就是一次「父级重建」——正是点完 FAB 后会发生的事。
  Widget tree(int nonce) {
    rebuilds = nonce;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: display),
      ],
      child: MiuixThemeController(
        colorSchemeMode: miuixColorSchemeModeOf(themeMode: ThemeMode.light),
        keyColor: const Color(0xFF386A20),
        child: Builder(
          builder: (context) {
            final miuix = MiuixTheme.of(context);
            return MaterialApp(
              locale: const Locale('zh', 'CN'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: AppTheme.light().copyWith(
                colorScheme: materialSchemeFromMiuix(
                  miuix.colors,
                  miuix.brightness,
                ),
              ),
              home: Builder(
                builder: (fabContext) => Scaffold(
                  // nonce 进树：换值即触发这条 Scaffold 的重建
                  body: Center(child: Text('nonce $nonce')),
                  floatingActionButton: buildMiuixHomeFab(
                    fabContext,
                    index: 1,
                    controller: controller,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<TestGesture> mouse(WidgetTester tester) async {
    final gesture =
        await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(5, 5));
    addTearDown(gesture.removePointer);
    await tester.pump();
    return gesture;
  }

  Future<void> hoverFab(WidgetTester tester, TestGesture gesture) async {
    await gesture.moveTo(
      tester.getCenter(find.byType(MiuixFloatingActionButton)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  Future<void> hoverOut(WidgetTester tester, TestGesture gesture) async {
    await gesture.moveTo(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  testWidgets('hover 打开气泡后父级重建：不炸 markNeedsBuild', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(tree(0));
    await tester.pumpAndSettle();
    expect(find.byType(MiuixFloatingActionButton), findsOneWidget);

    await hoverFab(tester, await mouse(tester));
    // 气泡确实开着（这正是触发库里那句 markNeedsBuild 的前提）
    expect(find.byType(MiuixPlainTooltip), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 点完 FAB 之后外壳重建 / 服务状态变化都会走到这里
    await tester.pumpWidget(tree(1));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '重建了 $rebuilds 次');
    expect(find.byType(MiuixFloatingActionButton), findsOneWidget);
  });

  testWidgets('启停 FAB 跟着 server.state 换图标，且状态变化不炸', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: display),
        ],
        child: MiuixThemeController(
          colorSchemeMode: miuixColorSchemeModeOf(themeMode: ThemeMode.light),
          keyColor: const Color(0xFF386A20),
          child: Builder(
            builder: (context) {
              final miuix = MiuixTheme.of(context);
              return MaterialApp(
                locale: const Locale('zh', 'CN'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: AppTheme.light().copyWith(
                  colorScheme: materialSchemeFromMiuix(
                    miuix.colors,
                    miuix.brightness,
                  ),
                ),
                home: Builder(
                  builder: (fabContext) => Scaffold(
                    body: const Center(child: Text('仪表盘')),
                    floatingActionButton: buildMiuixHomeFab(
                      fabContext,
                      index: 0,
                      controller: controller,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await mouse(tester);
    await hoverFab(tester, gesture);
    expect(find.text('启动服务'), findsOneWidget);

    // 状态直接推进 running：FAB 自己监听，父级一次 rebuild 都不给
    controller.server.state.value = ServerState.running;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 气泡超时自动收起后再 hover：文案要跟着状态走
    await hoverOut(tester, gesture);
    await hoverFab(tester, gesture);
    expect(find.text('停止服务'), findsOneWidget);
    expect(find.text('启动服务'), findsNothing);
  });
}
