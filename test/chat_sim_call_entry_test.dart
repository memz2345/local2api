// 对话模拟页底栏「通话」入口的回归测试（Material + miuix 双风格）。
//
// 三块：
// 1) 底栏有通话按钮，点开是「语音 / 视频」二选一弹层；
// 2) 视频选项跟 Omni 模型走：组里没有 omni 就置灰（带原因），有就可用；
// 3) 选语音通话推入通话页，对端显示名 = 当前角色卡名（不是组名）。
//
// 注意：推入后的通话页有常驻动画（六边形 / 波纹），**不能 pumpAndSettle**，
// 全部固定时长 pump；STT 平台通道要 mock（同 call_page_test）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/chat_sim_store.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/call_page.dart';
import 'package:local2api/ui/chat_simulation_page.dart';
import 'package:local2api/ui/miuix/miuix_call_page.dart';
import 'package:local2api/ui/miuix/miuix_chat_simulation_page.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sttChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sttChannel, (call) async {
          switch (call.method) {
            case 'has_permission':
              return true;
            case 'initialize':
              return true;
            case 'locales':
              return <Map<String, Object>>[];
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sttChannel, null);
    chatSimStore.clear();
  });

  group('Material', () {
    late ConfigStore configStore;
    late ServerController controller;

    setUp(() async {
      configStore = ConfigStore();
      await configStore.load();
      controller = ServerController(configStore);
    });
    tearDown(() => controller.dispose());

    Widget page({required List<String> groupModels, String scope = 'm-call'}) =>
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: ChatSimulationPage(
          controller: controller,
          model: 'zen-free',
          groupName: '本地模型',
          scope: scope,
          groupModels: groupModels,
        ),
      );

    /// 卸载到只剩 MaterialApp 骨架，把通话页的常驻动画计时器收掉。
    Future<void> teardown(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1500));
    }

    testWidgets('底栏有通话按钮，弹层是语音/视频二选一', (tester) async {
      await tester.pumpWidget(page(groupModels: const []));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.call_outlined), findsOneWidget);
      await tester.tap(find.byTooltip('通话'));
      await tester.pumpAndSettle();

      expect(find.text('语音通话'), findsOneWidget);
      expect(find.text('视频通话'), findsOneWidget);
      // 语音选项带角色摘要（没有角色卡 = 回落组名）。
      expect(find.textContaining('本地模型'), findsWidgets);
      await teardown(tester);
    });

    testWidgets('组里没有 Omni：视频置灰（onTap 为空）且带原因', (tester) async {
      await tester.pumpWidget(page(groupModels: const ['longcat-free']));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('通话'));
      await tester.pumpAndSettle();
      expect(find.text('视频通话需要 Omni 模型'), findsOneWidget);

      final inkwells = find.ancestor(
        of: find.text('视频通话'),
        matching: find.byType(InkWell),
      );
      expect(inkwells, findsOneWidget);
      final InkWell inkwell = tester.widget(inkwells.first);
      expect(inkwell.onTap, isNull);
      await teardown(tester);
    });

    testWidgets('组里有 Omni：视频可用，点语音推入通话页并显示角色名', (tester) async {
      // 预置：这个 scope 应用过内置角色卡「流萤」。
      chatSimStore.setCharacter('omni-m', 'builtin.firefly');
      await tester.pumpWidget(
        page(
          groupModels: const ['qwen3-omni'],
          scope: 'omni-m',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('通话'));
      await tester.pumpAndSettle();
      // 语音选项摘要 = 当前角色名。（顶栏标题现在也叫角色名，所以这里
      // 认完整的摘要文案，不能全树搜「流萤」。）
      expect(find.text('和 流萤 通话'), findsOneWidget);

      await tester.tap(find.text('语音通话'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // 通话页起来了，对端显示的是角色名而不是组名。
      expect(find.byType(CallPage), findsOneWidget);
      expect(
        find.descendant(of: find.byType(CallPage), matching: find.text('流萤')),
        findsOneWidget,
      );
      expect(find.text('本地模型'), findsNothing);
      await teardown(tester);
    });
  });

  group('miuix', () {
    late ConfigStore configStore;
    late ServerController controller;

    setUp(() async {
      configStore = ConfigStore();
      await configStore.load();
      controller = ServerController(configStore);
    });
    tearDown(() => controller.dispose());

    Widget page({required List<String> groupModels, String scope = 'x-call'}) =>
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
                groupName: '本地模型',
                scope: scope,
                groupModels: groupModels,
              ),
            );
          },
        ),
      );

    Future<void> teardown(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1500));
    }

    testWidgets('底栏有通话按钮，弹层是语音/视频二选一', (tester) async {
      await tester.pumpWidget(page(groupModels: const ['qwen3-omni']));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.call_outlined), findsOneWidget);
      await tester.tap(find.byTooltip('通话'));
      await tester.pumpAndSettle();

      expect(find.text('语音通话'), findsOneWidget);
      expect(find.text('视频通话'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('组里没有 Omni：视频置灰（enabled=false）且带原因', (tester) async {
      await tester.pumpWidget(page(groupModels: const ['longcat-free']));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('通话'));
      await tester.pumpAndSettle();
      expect(find.text('视频通话需要 Omni 模型'), findsOneWidget);

      final prefs = find.ancestor(
        of: find.text('视频通话'),
        matching: find.byType(MiuixArrowPreference),
      );
      expect(prefs, findsOneWidget);
      final MiuixArrowPreference pref = tester.widget(prefs.first);
      expect(pref.enabled, isFalse);
      await teardown(tester);
    });

    testWidgets('组里有 Omni：视频可用，点语音推入通话页并显示角色名', (tester) async {
      chatSimStore.setCharacter('omni-x', 'builtin.firefly');
      await tester.pumpWidget(
        page(groupModels: const ['qwen3-omni'], scope: 'omni-x'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('通话'));
      await tester.pumpAndSettle();
      // 同 Material 侧：顶栏标题也叫角色名，这里认完整摘要文案。
      expect(find.text('和 流萤 通话'), findsOneWidget);

      await tester.tap(find.text('语音通话'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(MiuixCallPage), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MiuixCallPage),
          matching: find.text('流萤'),
        ),
        findsOneWidget,
      );
      expect(find.text('本地模型'), findsNothing);
      await teardown(tester);
    });

    testWidgets('选视频通话：直接以视频模式接通（有画面占位区）', (tester) async {
      await tester.pumpWidget(
        page(groupModels: const ['qwen3-omni'], scope: 'omni-v'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('通话'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('视频通话'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(MiuixCallPage), findsOneWidget);
      expect(find.text('摄像头画面 · 暂未接入'), findsOneWidget);
      await teardown(tester);
    });
  });
}
