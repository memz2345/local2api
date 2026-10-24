import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/create_config_page.dart';
import 'package:local2api/ui/miuix/miuix_create_config_page.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';
import 'package:local2api/ui/miuix/miuix_upstream_edit_page.dart';
import 'package:local2api/ui/profile_import_sheet.dart';
import 'package:local2api/ui/upstream_edit_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _doc({String id = 'demo'}) => jsonEncode({
  'id': id,
  'name': id.toUpperCase(),
  'upstreams': [
    {
      'id': 'u-$id',
      'name': 'Demo',
      'baseUrl': 'https://a.example/v1',
      'models': [
        {'publicName': 'm1', 'target': 'm1'},
      ],
    },
  ],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProfileStore store;
  late ConfigStore configStore;
  late ServerController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = ProfileStore();
    await store.load();
    configStore = ConfigStore();
    await configStore.load();
    controller = ServerController(configStore);
  });

  tearDown(() {
    store.dispose();
    configStore.dispose();
    controller.dispose();
  });

  /// 落盘是 400ms 防抖 + toast 的 snackbar 有存活时长，收尾都要把它们推完。
  Future<void> settleAll(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  Future<void> pumpMaterial(WidgetTester tester, {required Widget home}) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ProfileStore>.value(
        value: store,
        child: MaterialApp(
          // 不钉 locale 的话测试环境默认 en_US，中文断言全对不上
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    await settleAll(tester);
  }

  /// 按 app.dart 里 miuix 分支的结构搭树（同 miuix_profiles_page_test）。
  Future<void> pumpMiuix(WidgetTester tester, {required Widget home}) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ProfileStore>.value(
        value: store,
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
                locale: const Locale('zh', 'CN'),
                localizationsDelegates:
                    AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: AppTheme.light().copyWith(colorScheme: scheme),
                home: home,
              );
            },
          ),
        ),
      ),
    );
    await settleAll(tester);
  }

  testWidgets('Material 创建配置页：添加配置文件 / 新建上游两行', (tester) async {
    await pumpMaterial(
      tester,
      home: CreateConfigPage(controller: controller),
    );

    expect(find.text('创建配置'), findsOneWidget);
    expect(find.text('添加配置文件'), findsOneWidget);
    expect(find.text('从文件、订阅链接或粘贴 JSON 导入'), findsOneWidget);
    expect(find.text('新建上游'), findsOneWidget);
  });

  testWidgets('Material：点「新建上游」进上游编辑页（不再是导入面板）', (tester) async {
    await pumpMaterial(
      tester,
      home: CreateConfigPage(controller: controller),
    );

    await tester.tap(find.text('新建上游'));
    await settleAll(tester);

    expect(find.byType(UpstreamEditPage), findsOneWidget);
    expect(find.byType(ProfileImportSheet), findsNothing);
  });

  testWidgets('Material：点「添加配置文件」打开导入面板，粘贴 JSON 能导入', (tester) async {
    await pumpMaterial(
      tester,
      home: CreateConfigPage(controller: controller),
    );

    await tester.tap(find.text('添加配置文件'));
    await settleAll(tester);
    expect(find.byType(ProfileImportSheet), findsOneWidget);

    await tester.tap(find.text('粘贴 JSON'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, _doc());
    await tester.pump();
    await tester.tap(find.text('导入'));
    await settleAll(tester);

    expect(store.profiles.map((p) => p.id), contains('demo'));
    expect(find.byType(ProfileImportSheet), findsNothing);
    // 面板关掉后停在创建配置页，让用户接着选下一个入口
    expect(find.byType(CreateConfigPage), findsOneWidget);
  });

  testWidgets('miuix 创建配置页：两行都在，点「新建上游」进 miuix 上游编辑页', (tester) async {
    await pumpMiuix(
      tester,
      home: MiuixCreateConfigPage(controller: controller),
    );

    expect(find.text('创建配置'), findsOneWidget);
    expect(find.text('添加配置文件'), findsOneWidget);
    expect(find.text('从文件、订阅链接或粘贴 JSON 导入'), findsOneWidget);
    expect(find.text('新建上游'), findsOneWidget);

    await tester.tap(find.text('新建上游'));
    await settleAll(tester);

    expect(find.byType(MiuixUpstreamEditPage), findsOneWidget);
  });
}
