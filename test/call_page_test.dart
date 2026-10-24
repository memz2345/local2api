// 「AI 通话」页（基础链路版）+ 双六边形背景 + Omni 判定的回归测试。
//
// 注意：
// - 通话页有常驻动画（六边形壁纸 / 呼叫波纹），**不能用 pumpAndSettle**，
//   全部用固定时长 pump；
// - 语音识别平台通道必须 mock：不 mock 时 channel 返回 null →
//   has_permission=false → 会去碰 permission_handler（测试环境挂起）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/call_settings.dart';
import 'package:local2api/services/chat_sim_store.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/miuix/miuix_call_page.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';
import 'package:local2api/widgets/hexagon_collision_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'miuix_finders.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sttChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');

  group('Omni 模型判定', () {
    test('名字含 omni（大小写不敏感）才算', () {
      expect(isOmniModelName('qwen3-omni'), isTrue);
      expect(isOmniModelName('Qwen3-Omni:30b'), isTrue);
      expect(isOmniModelName('OMNI'), isTrue);
      expect(isOmniModelName('gpt-4o'), isFalse);
      expect(isOmniModelName(''), isFalse);
    });

    test('omniModelOf 只挑启用中的条目（看对外名或真实目标名）', () {
      final up = Upstream(
        id: 'u1',
        name: 'Local',
        baseUrl: 'http://x',
        models: [
          ModelEntry(publicName: 'qwen3-omni', enabled: false),
          ModelEntry(publicName: 'gpt-4o'),
          ModelEntry(publicName: 'local-big', target: 'qwen3-omni:30b'),
        ],
      );
      // 第一条没启用；第三条靠 target 命中
      expect(omniModelOf(up)?.publicName, 'local-big');
      up.models[2].enabled = false;
      expect(omniModelOf(up), isNull);
    });
  });

  group('双六边形背景', () {
    testWidgets('渲染出 CustomPaint 且不抛异常（静止帧）', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: HexagonCollisionBackground(animate: false)),
        ),
      );
      await tester.pump();
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('通话页', () {
    late ConfigStore configStore;
    late ServerController controller;

    /// 语音识别 mock 的初始化结果：true = 设备有识别服务（正常在听）。
    bool mockAsrAvailable = false;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      // 本地 ASR 兜底会问 path_provider 要模型目录；未 mock 的平台通道在
      // FakeAsync 里永远不完成，必须拦下（同 voice_record_sheet_test）。
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => Directory.systemTemp.path,
      );
      configStore = ConfigStore();
      await configStore.load();
      controller = ServerController(configStore);
      mockAsrAvailable = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(sttChannel, (call) async {
            switch (call.method) {
              case 'has_permission':
                return true;
              case 'initialize':
                return mockAsrAvailable;
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
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      controller.dispose();
      chatSimStore.clear();
    });

    Widget page(String model) => MiuixThemeController(
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
            // 外面套 Scaffold：toast 走 ScaffoldMessenger 需要宿主。
            home: Scaffold(
              body: MiuixCallPage(
                controller: controller,
                model: model,
                groupName: '本地模型',
                scope: 'call-test',
              ),
            ),
          );
        },
      ),
    );

    /// 进入通话并越过「接通 + 第一次排听」。
    Future<void> enterCall(WidgetTester tester, String model) async {
      await tester.pumpWidget(page(model));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1500)); // 1.2s 接通
      await tester.pump(const Duration(milliseconds: 300)); // 180ms 排听
      await tester.pump(); // ASR 就绪回调
      // 本地 ASR 兜底的模型检查带 250ms 磁盘超时兜底（真机上是 µs 级的
      // stat，测试环境的 fake async 里要等超时），再给一段 fake 时间让
      // ensureReady 落定。
      await tester.pump(const Duration(milliseconds: 500));
    }

    /// 收尾：卸载页面（dispose 会取消全部 Timer/麦克风/朗读）。
    Future<void> teardownCall(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 700));
    }

    testWidgets('ASR 缺服务时给「语音识别不可用」并可重试', (tester) async {
      mockAsrAvailable = false;
      await enterCall(tester, 'gpt-4o');
      expect(find.textContaining('语音识别不可用'), findsOneWidget);
      // 麦克风按钮是重试入口。
      expect(find.byTooltip('麦克风'), findsOneWidget);
      await tester.tap(find.byTooltip('麦克风'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await teardownCall(tester);
    });

    testWidgets('非 Omni 也能通话：接通后在听、状态行带计时', (tester) async {
      await enterCall(tester, 'gpt-4o');
      expect(find.textContaining('在听'), findsOneWidget);
      expect(find.textContaining(RegExp(r'\d{2}:\d{2}')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await teardownCall(tester);
    });

    testWidgets('非 Omni：视频按钮点击提示需要 Omni，不切模式', (tester) async {
      await enterCall(tester, 'gpt-4o');
      await tester.tap(find.byTooltip('切换到视频通话'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('语音通话'), findsOneWidget);
      expect(find.text('摄像头画面 · 暂未接入'), findsNothing);
      expect(find.text('视频通话需要 Omni 模型'), findsOneWidget); // toast 文案
      // 等 SnackBar 的自动消退计时器走完，别留 pending timer。
      await tester.pump(const Duration(seconds: 5));
      await teardownCall(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Omni：视频模式可切换', (tester) async {
      await enterCall(tester, 'qwen3-omni');
      await tester.tap(find.byTooltip('切换到视频通话'));
      await tester.pump();
      expect(find.text('视频通话'), findsOneWidget);
      expect(find.text('摄像头画面 · 暂未接入'), findsOneWidget);
      await teardownCall(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('挂断：短暂显示「通话已结束」后退出', (tester) async {
      await enterCall(tester, 'qwen3-omni');
      await tester.tap(find.byTooltip('挂断'));
      await tester.pump();
      expect(find.textContaining('通话已结束'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1300));
      await teardownCall(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('左划打开对话记录：显示消息，点遮罩关闭', (tester) async {
      await enterCall(tester, 'qwen3-omni');
      // 关闭态：面板在屏外且被 IgnorePointer 拦着，不可命中。
      expect(find.text('对话记录').hitTestable(), findsNothing);

      // 左划（水平左拖）拉出面板。
      await tester.drag(find.byType(MiuixCallPage), const Offset(-130, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // 滑入动画
      expect(find.text('对话记录').hitTestable(), findsOneWidget);
      // 记录里有默认系统提示词那条（本 scope 的初始对话）。
      expect(find.text('系统').hitTestable(), findsOneWidget);

      // 点遮罩（面板外左侧）关闭。
      await tester.tapAt(const Offset(20, 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('对话记录').hitTestable(), findsNothing);
      await teardownCall(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('通话设置是独立页面：非 Omni 带置灰说明', (tester) async {
      await enterCall(tester, 'gpt-4o');
      await tester.tap(miuixIcon(AppIconNames.settings));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('通话设置'), findsOneWidget);
      expect(find.text('允许打断'), findsOneWidget);
      expect(find.text('允许调用摄像头'), findsOneWidget);
      expect(find.textContaining('当前模型不是 Omni 模型'), findsOneWidget);
      await teardownCall(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('通话设置：Omni 下开关可切换并落盘', (tester) async {
      await enterCall(tester, 'qwen3-omni');
      await tester.tap(miuixIcon(AppIconNames.settings));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('允许调用摄像头'), findsOneWidget);
      // 默认开；点一下变关并写入 prefs。
      await tester.tap(find.text('允许调用摄像头'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(await CallPrefs.loadAllowCamera(), isFalse);
      await teardownCall(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
