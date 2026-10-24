// 对话设置页（Material 版）的回归：TTS 拆成独立一页 + 自动播放开关落盘。
//
// 只测「入口 + 开关」两件事：TTS 设置页本体（模型下载 / 试听）要碰
// path_provider 与真实文件系统，那部分不在 widget test 里铺。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/services/tts/tts_settings.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/chat_settings_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConfigStore configStore;
  late ServerController controller;
  late SettingsService display;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    configStore = ConfigStore();
    await configStore.load();
    controller = ServerController(configStore);
    controller.webUiAutoStart = false;
    display = SettingsService();
    await display.load();
  });

  tearDown(() {
    controller.dispose();
    display.dispose();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsService>.value(
        value: display,
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: ChatSettingsPage(controller: controller),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets('对话设置：TTS 入口与自动播放开关都在，配置项不再平铺', (tester) async {
    await pumpPage(tester);

    expect(find.text('对话设置'), findsOneWidget);
    expect(find.text('TTS 设置'), findsOneWidget);
    expect(find.text('本地模型、服务商与试听'), findsOneWidget);
    expect(find.text('自动播放 TTS'), findsOneWidget);
    expect(find.text('角色卡'), findsWidgets);
    // 本地 TTS 那一整块搬到 TTS 设置页了
    expect(find.text('本地 TTS（Qwen3-TTS）'), findsNothing);
    // 长说明按需求删掉了
    expect(find.textContaining('下载 Qwen3-TTS 1.7B 模型后'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('自动播放开关写进 TtsSettings 并落盘', (tester) async {
    await pumpPage(tester);
    final tts = TtsSettings.instance;
    await tts.load();
    await tts.setAutoPlay(false);
    await tester.pumpAndSettle();

    expect(tts.autoPlay, isFalse);
    await tester.tap(find.byType(Switch));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(tts.autoPlay, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('tts.autoPlay'), isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(tts.autoPlay, isFalse);
    expect(prefs.containsKey('tts.autoPlay'), isFalse);
  });
}
