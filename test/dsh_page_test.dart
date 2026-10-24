// DeepSeek Harness「更多设置」页（Material / miuix 两套）在桌面上的渲染回归：
//   · 三段结构（运行状态 / 安装 / API 配置）都在；
//   · 安卓专属的行（Node 运行时安装、运行模式、Android 兼容层）在非安卓宿主
//     不出现 —— 这些是安卓端支持新增的入口，靠 Platform.isAndroid 门控；
//   · 「应用内打开 / 打开」只在运行中出现，未启动时都不渲染。
//
// 只做渲染断言，不触发 npm / node 启动。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/dsh_page.dart';
import 'package:local2api/ui/miuix/miuix_dsh_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpPage(
    WidgetTester tester,
    Widget page, {
    required bool miuix,
  }) async {
    // 两套页面都很长；给足高度，避免懒加载的 ListView 把通知区裁在屏幕外。
    tester.view.physicalSize = const Size(1400, 5200);
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

  for (final style in [false, true]) {
    final label = style ? 'miuix' : 'Material';

    testWidgets('$label DSH 页：三段齐、安卓专属行不出现', (tester) async {
      await pumpPage(
        tester,
        style
            ? const MiuixDshPage()
            : const DshPage(),
        miuix: style,
      );
      // DshService 是进程级单例；这里只验渲染结果，不依赖 init 的完成时序。
      expect(find.text('运行状态'), findsOneWidget);
      // 「安装」既是分区标题也是未装时的动作行文案。
      expect(find.text('安装'), findsAtLeastNWidgets(1));
      expect(find.text('API 配置'), findsOneWidget);
      expect(find.text('写入 dsh 配置'), findsOneWidget);

      // 安卓专属：Node 运行时安装 / 运行模式 / Shizuku / 兼容层。
      expect(find.text('安装 Node.js'), findsNothing);
      expect(find.text('运行模式'), findsNothing);
      expect(find.text('Android 兼容层'), findsNothing);
      // 打开入口只在运行中出现，未启动时两套都不该有。
      expect(find.text('应用内打开'), findsNothing);

      // Windows 宿主：系统通知区在，且只保留跨平台的任务行；
      // 安卓专属的权限 / 实时更新 / 电池优化不出现。
      if (Platform.isWindows) {
        expect(find.text('通知'), findsOneWidget);
        expect(find.text('发一条测试通知'), findsOneWidget);
        expect(find.text('运行任务'), findsOneWidget);
        expect(find.text('通知权限'), findsNothing);
        expect(find.text('实时更新'), findsNothing);
        expect(find.text('忽略电池优化'), findsNothing);
      }
    });
  }
}
