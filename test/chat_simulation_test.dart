import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/chat_simulation_page.dart';
import 'package:local2api/ui/miuix/miuix_chat_simulation_page.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/chat_sim_store.dart';
import 'package:local2api/services/chat_simulation.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _wordCountAndFormat();

  group('对话存档', () {
    late ChatSimStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = ChatSimStore();
      await store.load();
    });

    tearDown(() => store.dispose());

    test('存了能读回来（含角色/耗时/失败标记/响应模型）', () async {
      store.save('zen', [
        ChatMsg(ChatRole.system, 'You are a helpful assistant.'),
        ChatMsg(ChatRole.user, '你好'),
        ChatMsg(ChatRole.assistant, '你好呀', elapsedMs: 470),
        ChatMsg(
          ChatRole.assistant,
          '来自路由',
          elapsedMs: 900,
          model: 'zen-free',
          lane: 'space-bunny-free',
        ),
        ChatMsg(ChatRole.assistant, '上游 403', error: true),
      ]);
      await store.flush();

      // 新开一个 store 模拟重启
      final again = ChatSimStore();
      await again.load();
      final msgs = again.messagesOf('zen');
      expect(msgs.map((m) => m.role), [
        ChatRole.system,
        ChatRole.user,
        ChatRole.assistant,
        ChatRole.assistant,
        ChatRole.assistant,
      ]);
      expect(msgs[2].content, '你好呀');
      expect(msgs[2].elapsedMs, 470);
      expect(msgs[3].model, 'zen-free');
      expect(msgs[3].lane, 'space-bunny-free');
      expect(msgs[4].error, isTrue);
      again.dispose();
    });

    test('按组分开存，互不串味', () async {
      store.save('group-a', [ChatMsg(ChatRole.user, 'A 的问题')]);
      store.save('group-b', [ChatMsg(ChatRole.user, 'B 的问题')]);
      await store.flush();

      expect(store.messagesOf('group-a').single.content, 'A 的问题');
      expect(store.messagesOf('group-b').single.content, 'B 的问题');
      expect(store.messagesOf('group-c'), isEmpty);
    });

    test('条数超上限时保留最近的', () async {
      store.save('zen', [
        for (var i = 0; i < ChatSimStore.maxMessages + 20; i++)
          ChatMsg(ChatRole.user, '第 $i 条'),
      ]);
      final kept = store.messagesOf('zen');
      expect(kept, hasLength(ChatSimStore.maxMessages));
      expect(kept.last.content, '第 ${ChatSimStore.maxMessages + 19} 条');
    });

    test('remove 之后读不到', () async {
      store.save('zen', [ChatMsg(ChatRole.user, 'hi')]);
      store.remove('zen');
      expect(store.messagesOf('zen'), isEmpty);
    });
  });

  group('仅发送（不请求模型回复）', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await chatSimStore.load();
      chatSimStore.clear();
    });

    tearDown(() => chatSimStore.clear());

    test('发出去就完事：不追加 assistant，也不动已有消息', () async {
      final sim = ChatSimController(
        model: 'zen-free',
        config: ProxyConfig(),
        scope: 'opencodezen',
      );
      sim.add(ChatRole.user, '在吗');
      final before = sim.messages.length;

      final sent = await sim.sendOnly();

      expect(sent, isTrue);
      expect(
        sim.messages,
        hasLength(before),
        reason: '只发不等 = 不会多出一条回答，这正是它和 send() 的差别',
      );
      expect(sim.sending, isFalse);

      await chatSimStore.flush();
      sim.dispose();
    });

    test('一条内容都没有时不发，返回 false', () async {
      final sim = ChatSimController(
        model: 'm',
        config: ProxyConfig(),
        scope: 'empty',
      );
      sim.messages.clear();
      sim.add(ChatRole.user, '   ');

      expect(await sim.sendOnly(), isFalse);
      expect(sim.messages, hasLength(1));

      await chatSimStore.flush();
      sim.dispose();
    });
  });

  group('对话模拟：默认保存/恢复', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await chatSimStore.load();
      chatSimStore.clear();
    });

    tearDown(() => chatSimStore.clear());

    test('存过就以存档为准：新开控制器 restore 出同一串历史', () async {
      final config = ProxyConfig();
      final first = ChatSimController(
        model: 'zen-free',
        config: config,
        scope: 'opencodezen',
      );
      first.add(ChatRole.user, '第一问');
      first.add(ChatRole.assistant, '第一答');
      first.add(ChatRole.user, '第二问');
      await chatSimStore.flush();
      first.dispose();

      // 重新进页面（新控制器 = 新一次打开）
      final second = ChatSimController(
        model: 'zen-free',
        config: config,
        scope: 'opencodezen',
      );
      second.restore();

      expect(second.restored, isTrue);
      expect(second.messages.map((m) => m.role), [
        ChatRole.system,
        ChatRole.user,
        ChatRole.assistant,
        ChatRole.user,
      ]);
      expect(second.messages.last.content, '第二问');
      second.dispose();
    });

    test('没存过就是默认那条系统提示词', () {
      final sim = ChatSimController(
        model: 'm',
        config: ProxyConfig(),
        scope: 'fresh',
      );
      sim.restore();
      expect(sim.restored, isFalse);
      expect(sim.messages, hasLength(1));
      expect(sim.messages.single.role, ChatRole.system);
      sim.dispose();
    });

    test('清空之后不会被「恢复」回来', () async {
      final config = ProxyConfig();
      final sim = ChatSimController(
        model: 'zen-free',
        config: config,
        scope: 'opencodezen',
      );
      sim.add(ChatRole.user, '要清掉的');
      await chatSimStore.flush();

      sim.clear();
      await chatSimStore.flush();

      final reopened = ChatSimController(
        model: 'zen-free',
        config: config,
        scope: 'opencodezen',
      );
      reopened.restore();
      expect(reopened.restored, isFalse);
      expect(reopened.messages, hasLength(1));
      reopened.dispose();
      sim.dispose();
    });
  });
}

void _wordCountAndFormat() {
  group('响应模型标注', () {
    test('没有车道时就用回显的模型名', () {
      final m = ChatMsg(ChatRole.assistant, 'x', model: 'lane-s');
      expect(m.servedModel, 'lane-s');
      expect(m.routed, isFalse);
    });

    test('有车道时优先车道；车道 ≠ 回显名才算走了路由', () {
      final m = ChatMsg(
        ChatRole.assistant,
        'x',
        model: 'zen-free',
        lane: 'space-bunny-free',
      );
      expect(m.servedModel, 'space-bunny-free');
      expect(m.routed, isTrue);
    });

    test('都没有就是 null（比如失败提示那条）', () {
      final m = ChatMsg(ChatRole.assistant, '上游 403', error: true);
      expect(m.servedModel, isNull);
      expect(m.routed, isFalse);
    });

    test('手改过的消息不再挂着旧模型名', () {
      final sim = ChatSimController(
        model: 'zen-free',
        config: ProxyConfig(),
        scope: '',
      );
      sim.messages.add(
        ChatMsg(
          ChatRole.assistant,
          '原答案',
          model: 'zen-free',
          lane: 'space-bunny-free',
        ),
      );
      sim.edit(1, ChatRole.assistant, '我改的');
      expect(sim.messages[1].model, isNull);
      expect(sim.messages[1].lane, isNull);
      sim.dispose();
    });
  });

  group('字数与耗时', () {
    test('CJK 按字算、英文按词算（Chatbox 那套口径）', () {
      expect(chatWordCount('你好呀'), 3);
      expect(chatWordCount('You are a helpful assistant.'), 5);
      expect(chatWordCount('你好呀 hello world'), 5);
      expect(chatWordCount('   '), 0);
    });

    test('耗时格式化', () {
      expect(formatElapsed(null), '–');
      expect(formatElapsed(470), '0.47s');
      expect(formatElapsed(12300), '12.3s');
      expect(formatElapsed(63000), '1m03s');
    });
  });

  group('对话模拟页', () {
    late ConfigStore configStore;
    late ServerController controller;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await chatSimStore.load();
      chatSimStore.clear();
      configStore = ConfigStore();
      await configStore.load();
      controller = ServerController(configStore);
    });

    tearDown(() {
      controller.dispose();
      chatSimStore.clear();
    });

    testWidgets('miuix 版：渲染系统提示词、自动保存说明与启动服务提示', (tester) async {
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

      expect(find.text(ChatSimController.defaultSystemPrompt), findsOneWidget);
      expect(find.text('启动服务'), findsOneWidget);

      // 卸载页面（会触发一次「退出前落盘」）并让 store 的防抖定时器跑完，
      // 否则测试收尾时会报 "A Timer is still pending"
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('Material 版：进页面就把上次的对话接回来', (tester) async {
      // 先塞一段历史（模拟上次聊过）
      chatSimStore.save('opencodezen', [
        ChatMsg(ChatRole.system, ChatSimController.defaultSystemPrompt),
        ChatMsg(ChatRole.user, '上次问过的'),
        ChatMsg(ChatRole.assistant, '上次答过的'),
      ]);
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

      expect(find.text('上次问过的'), findsOneWidget);
      expect(find.text('上次答过的'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('Material 版：输入行带语音输入按钮（未收音 = mic_none）', (tester) async {
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

      expect(find.byIcon(Icons.mic_none), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('Material 版：页脚标出响应模型，走路由时连请求的对外名一起标', (
      tester,
    ) async {
      chatSimStore.save('opencodezen', [
        ChatMsg(ChatRole.system, ChatSimController.defaultSystemPrompt),
        ChatMsg(ChatRole.user, '问一句'),
        ChatMsg(
          ChatRole.assistant,
          '答一句',
          model: 'zen-free',
          lane: 'space-bunny-free',
        ),
      ]);
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

      expect(
        find.text('响应模型 space-bunny-free（请求 zen-free）'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('miuix 版：页脚同样标出响应模型', (tester) async {
      chatSimStore.save('opencodezen', [
        ChatMsg(ChatRole.system, ChatSimController.defaultSystemPrompt),
        ChatMsg(ChatRole.user, '问一句'),
        ChatMsg(ChatRole.assistant, '答一句', model: 'lane-s'),
      ]);
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
                  model: 'lane-s',
                  scope: 'opencodezen',
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 页头多了一条「角色卡」选择条，消息列表整体下移一行：最后一条
      // 气泡的页脚可能落在视口外（ListView 惰性构建），滚到底再断言。
      await tester.dragFrom(
        tester.getCenter(find.byType(ListView)),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      expect(find.text('响应模型 lane-s'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    });
  });
}
