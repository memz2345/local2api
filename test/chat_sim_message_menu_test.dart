// test/chat_sim_message_menu_test.dart
//
// 对话模拟：助手消息的长按菜单（复制 / 删除 / 朗读 / 重新回答 / 下载）、
// 「重新回答」的截断语义、顶栏标题跟角色名、导出文件名规则。
//
// 下载这一项只在编了原生编码器的平台出现（[TtsMessageExport.isSupported]
// = Android），host 侧测试跑在 Windows/macOS/Linux 上，所以这里断言的是
// **不出现**；真机上的下载链路只能手工验证。
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/character_store.dart';
import 'package:local2api/services/chat_sim_store.dart';
import 'package:local2api/services/chat_simulation.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/tts/tts_export_service.dart';
import 'package:local2api/services/tts/tts_message_export.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/chat_simulation_page.dart';
import 'package:local2api/ui/miuix/miuix_chat_simulation_page.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 用手机比例的测试画布。默认的 800×600 逻辑像素太矮：消息列表会从底部
/// 输入台下面穿过，最后一条气泡正好被盖住，长按落不到气泡上。
void usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatSimController.regenerateFrom', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await chatSimStore.load();
      chatSimStore.clear();
    });

    tearDown(() => chatSimStore.clear());

    ChatSimController seed(List<ChatMsg> msgs, {String scope = 'regen'}) {
      final sim = ChatSimController(
        model: 'zen-free',
        config: ProxyConfig(),
        scope: scope,
      );
      sim.messages
        ..clear()
        ..addAll(msgs);
      return sim;
    }

    test('从中间那条助手消息重答：它和它之后的都丢掉，前缀原样留着', () async {
      final sim = seed([
        ChatMsg(ChatRole.system, 'sys'),
        ChatMsg(ChatRole.user, '第一问'),
        ChatMsg(ChatRole.assistant, '第一答'),
        ChatMsg(ChatRole.user, '第二问'),
        ChatMsg(ChatRole.assistant, '第二答'),
      ]);

      await sim.regenerateFrom(2); // 「第一答」那条

      final contents = sim.messages.map((m) => m.content).toList();
      expect(contents, contains('sys'));
      expect(contents, contains('第一问'));
      expect(contents, isNot(contains('第一答')), reason: '被重答的那条要丢掉');
      expect(contents, isNot(contains('第二问')), reason: '它之后的也一起丢');
      expect(contents, isNot(contains('第二答')));
      // 前缀顺序不能乱：system 在最前，紧接着那条 user 是重发的历史尾巴
      expect(sim.messages[0].role, ChatRole.system);
      expect(sim.messages[1].role, ChatRole.user);
      expect(sim.messages[1].content, '第一问');

      await chatSimStore.flush();
      sim.dispose();
    });

    test('前缀里没有 user 消息就只截断、不重发', () async {
      final sim = seed([
        ChatMsg(ChatRole.system, 'sys'),
        ChatMsg(ChatRole.assistant, '凭空来的回答'),
      ]);

      await sim.regenerateFrom(1);

      expect(sim.messages, hasLength(1));
      expect(sim.messages.single.role, ChatRole.system);
      expect(sim.sending, isFalse, reason: '没东西可问就不该发请求');

      await chatSimStore.flush();
      sim.dispose();
    });

    test('index 越界什么都不做', () async {
      final sim = seed([ChatMsg(ChatRole.system, 'sys')]);

      await sim.regenerateFrom(-1);
      await sim.regenerateFrom(99);

      expect(sim.messages, hasLength(1));

      await chatSimStore.flush();
      sim.dispose();
    });
  });

  group('TtsExportService.fileNameFor', () {
    final at = DateTime(2026, 10, 15, 9, 8, 7);

    test('三种格式的扩展名：silk 与 slk 同物不同名', () {
      expect(
        TtsExportService.fileNameFor(TtsExportFormat.mp3, at: at),
        '朗读_20261015_090807.mp3',
      );
      expect(
        TtsExportService.fileNameFor(TtsExportFormat.silk, at: at),
        '朗读_20261015_090807.silk',
      );
      expect(
        TtsExportService.fileNameFor(TtsExportFormat.slk, at: at),
        '朗读_20261015_090807.slk',
      );
    });

    test('带 label（角色名）时进文件名，非法字符换成下划线', () {
      expect(
        TtsExportService.fileNameFor(
          TtsExportFormat.silk,
          at: at,
          label: '流萤',
        ),
        '流萤_20261015_090807.silk',
      );
      expect(
        TtsExportService.fileNameFor(
          TtsExportFormat.mp3,
          at: at,
          label: 'a/b:c*d?"e<f>g|h i',
        ),
        'a_b_c_d_e_f_g_h_i_20261015_090807.mp3',
      );
    });

    test('label 只有空白或全是分隔符时回落「朗读」', () {
      expect(
        TtsExportService.fileNameFor(TtsExportFormat.mp3, at: at, label: '  '),
        '朗读_20261015_090807.mp3',
      );
      expect(
        TtsExportService.fileNameFor(TtsExportFormat.mp3, at: at, label: '///'),
        '朗读_20261015_090807.mp3',
      );
    });

    test('超长 label 截到 48 字，时间戳不会被挤掉', () {
      final name = TtsExportService.fileNameFor(
        TtsExportFormat.slk,
        at: at,
        label: 'x' * 120,
      );
      expect(name, endsWith('_20261015_090807.slk'));
      expect(name.length, lessThanOrEqualTo(48 + 1 + 15 + 4));
    });

    test('SILK 系才认 -tencent；MP3 与它无关', () {
      expect(TtsExportFormat.silk.isSilk, isTrue);
      expect(TtsExportFormat.slk.isSilk, isTrue);
      expect(TtsExportFormat.mp3.isSilk, isFalse);
      // silk 与 slk 的 MIME 一致（就是同一种容器）
      expect(TtsExportFormat.silk.mime, TtsExportFormat.slk.mime);
      // 默认开腾讯兼容：下 silk/slk 基本就是为了发微信/QQ
      expect(TtsMessageExport.defaultTencent, isTrue);
    });
  });

  group('对话模拟页：助手消息长按菜单', () {
    late ConfigStore configStore;
    late ServerController controller;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await chatSimStore.load();
      chatSimStore.clear();
      // clear() 只清消息，scope→角色卡 的映射得单独摘掉，否则会漏进下一个用例
      chatSimStore.setCharacter('opencodezen', null);
      await characterStore.load();
      configStore = ConfigStore();
      await configStore.load();
      controller = ServerController(configStore);
    });

    tearDown(() {
      controller.dispose();
      chatSimStore.clear();
    });

    void seedHistory(String scope) {
      chatSimStore.save(scope, [
        ChatMsg(ChatRole.system, ChatSimController.defaultSystemPrompt),
        ChatMsg(ChatRole.user, '问一句'),
        ChatMsg(ChatRole.assistant, '答一句'),
      ]);
    }

    Future<void> pumpMaterial(WidgetTester tester, {String scope = 'opencodezen'}) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: ChatSimulationPage(
            controller: controller,
            model: 'zen-free',
            scope: scope,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> pumpMiuix(WidgetTester tester, {String scope = 'opencodezen'}) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(
        MiuixThemeController(
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
                home: MiuixChatSimulationPage(
                  controller: controller,
                  model: 'zen-free',
                  groupName: 'OpenCode Zen',
                  scope: scope,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// 收尾：卸载页面（触发退出前落盘）并让 store 的防抖定时器跑完，
    /// 否则测试收尾会报 "A Timer is still pending"。
    Future<void> teardownPage(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    }

    testWidgets('Material 版：长按助手气泡弹菜单，五项齐全（下载按平台）', (
      tester,
    ) async {
      seedHistory('opencodezen');
      await pumpMaterial(tester);

      // 长按气泡里的角色标签 —— 正文是 SelectableText，长按它会被「选词」
      // 手势吃掉，落不到气泡的 InkWell 上。
      await tester.longPress(find.text('助手').first);
      await tester.pumpAndSettle();

      expect(find.text('消息操作'), findsOneWidget);
      expect(find.text('复制'), findsWidgets);
      expect(find.text('删除'), findsWidgets);
      expect(find.text('朗读'), findsWidgets);
      expect(find.text('重新回答'), findsWidgets);
      // host 上没有原生编码器 → 「下载音频」不该出现（点了也只会报错）
      expect(
        find.text('下载音频'),
        TtsMessageExport.isSupported ? findsWidgets : findsNothing,
      );

      await teardownPage(tester);
    });

    testWidgets('Material 版：菜单里的「删除」删掉那条助手消息', (tester) async {
      seedHistory('opencodezen');
      await pumpMaterial(tester);
      expect(find.text('答一句'), findsOneWidget);

      await tester.longPress(find.text('助手').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();

      expect(find.text('答一句'), findsNothing);
      // 用户那条不受影响
      expect(find.text('问一句'), findsOneWidget);

      await teardownPage(tester);
    });

    testWidgets('Material 版：长按用户气泡仍是直接删（不弹菜单）', (tester) async {
      seedHistory('opencodezen');
      await pumpMaterial(tester);

      await tester.longPress(find.text('用户').first);
      await tester.pumpAndSettle();

      expect(find.text('消息操作'), findsNothing);
      expect(find.text('问一句'), findsNothing);

      await teardownPage(tester);
    });

    testWidgets('miuix 版：长按助手气泡弹菜单，四项齐全（下载按平台）', (
      tester,
    ) async {
      seedHistory('opencodezen');
      await pumpMiuix(tester);

      await tester.longPress(find.text('助手').first);
      await tester.pumpAndSettle();

      expect(find.text('消息操作'), findsOneWidget);
      expect(find.text('复制'), findsWidgets);
      expect(find.text('删除'), findsWidgets);
      expect(find.text('朗读'), findsWidgets);
      expect(find.text('重新回答'), findsWidgets);
      expect(
        find.text('下载音频'),
        TtsMessageExport.isSupported ? findsWidgets : findsNothing,
      );

      await teardownPage(tester);
    });
  });

  group('对话模拟页：顶栏标题跟角色名', () {
    late ConfigStore configStore;
    late ServerController controller;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await chatSimStore.load();
      chatSimStore.clear();
      // clear() 只清消息，scope→角色卡 的映射得单独摘掉，否则会漏进下一个用例
      chatSimStore.setCharacter('opencodezen', null);
      await characterStore.load();
      configStore = ConfigStore();
      await configStore.load();
      controller = ServerController(configStore);
    });

    tearDown(() {
      controller.dispose();
      chatSimStore.clear();
    });

    testWidgets('Material 版：加载了角色卡就用角色名，没加载用「对话模拟」', (
      tester,
    ) async {
      // 内置卡（流萤）在 characterStore 里恒有，id 前缀 builtin.
      final firefly = builtinCharacters().first;
      chatSimStore.setCharacter('opencodezen', firefly.id);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: ChatSimulationPage(
            controller: controller,
            model: 'zen-free',
            scope: 'opencodezen',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(firefly.name), findsWidgets);
      expect(find.text('对话模拟'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('Material 版：没加载角色卡时标题仍是「对话模拟」', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: ChatSimulationPage(
            controller: controller,
            model: 'zen-free',
            scope: 'opencodezen',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('对话模拟'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('miuix 版：加载了角色卡就用角色名', (tester) async {
      final firefly = builtinCharacters().first;
      chatSimStore.setCharacter('opencodezen', firefly.id);

      await tester.pumpWidget(
        MiuixThemeController(
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
                home: MiuixChatSimulationPage(
                  controller: controller,
                  model: 'zen-free',
                  groupName: 'OpenCode Zen',
                  scope: 'opencodezen',
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(firefly.name), findsWidgets);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    });
  });
}
