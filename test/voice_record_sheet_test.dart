// 「按住说话」录音弹层（VoiceRecordSession + 两版弹层共用逻辑）的回归测试。
//
// 覆盖：
// 1) 按住 → 引擎出定稿 → 松手 → 弹层带着文本关掉（miuix 版全流程）；
// 2) 快速点按（< 最小按住时长）不提交，弹层留在原地可重按；
// 3) 引擎不可用（initialize 失败）给「设备不支持」文案；
// 4) 松手时一条结果都没有 → 不关弹层，提示「没听清」。
//
// STT 平台通道全 mock（同 call_page_test 的做法）：引擎结果用
// textRecognition 平台消息从 native 侧打回 Dart。
//
// 按住时长判定用的是真实墙钟（DateTime.now），所以「按住」必须用
// tester.runAsync 真等一小段时间，pump 的 fake 时间不算数。
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/speech_input_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';
import 'package:local2api/widgets/miuix/miuix_voice_record_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sttChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');

  /// mock 状态：引擎初始化结果 / listen 是否被调过 / listen 后要不要
  /// 自动从「native」推一版定稿。
  bool initOk = true;
  bool listenCalled = false;
  int listenCount = 0;
  String? autoFinal;

  Future<void> fireResult(String text, bool isFinal) async {
    final json =
        '{"recognizedWords":"$text","finalResult":$isFinal,'
        '"alternates":[{"recognizedWords":"$text","confidence":0.85}],'
        '"resultType":${isFinal ? 2 : 0}}';
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          sttChannel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('textRecognition', json),
          ),
          (_) {},
        );
  }

  /// 从「native」推一条识别错误 —— 插件 Android 侧 `notifyError` 的原样报文
  /// （`{"errorMsg":…,"permanent":true}`，见 SpeechToTextPlugin.sendError）。
  Future<void> fireError(String errorMsg) async {
    final json = '{"errorMsg":"$errorMsg","permanent":true}';
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          sttChannel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('notifyError', json),
          ),
          (_) {},
        );
  }

  /// 宿主页：点「open」弹出录音层，把弹层 future 交给 [onOpen] 的返回值。
  Widget host(Future<String?> Function() onOpen) => MiuixThemeController(
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
            colorScheme: materialSchemeFromMiuix(miuix.colors, miuix.brightness),
          ),
          home: Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => onOpen(),
                child: const Text('open'),
              ),
            ),
          ),
        );
      },
    ),
  );

  setUp(() {
    // 本地 ASR 兜底会碰 SharedPreferences（模型就绪标记）与 path_provider
    // （模型目录），测试环境必须 mock：未 mock 的平台通道在 FakeAsync 里
    // 永远不完成，会把收音主流程堵死。
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.path,
    );
    initOk = true;
    listenCalled = false;
    listenCount = 0;
    autoFinal = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sttChannel, (call) async {
          switch (call.method) {
            case 'has_permission':
              return true;
            case 'initialize':
              return initOk;
            case 'locales':
              return <Map<String, Object>>[];
            case 'listen':
              listenCalled = true;
              listenCount++;
              final f = autoFinal;
              if (f != null) {
                // 模拟 Windows SAPI：按住中途断句出定稿。
                unawaited(fireResult(f, true));
              }
              return true;
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
  });

  /// 大麦克风（弹层里 behavior: opaque 且带 onPointerUp 的那颗 Listener；
  /// 滚动区的 Listener 是 [down, panZoomStart]，没有 up）。
  Finder micButton() => find.byWidgetPredicate(
    (w) =>
        w is Listener &&
        w.behavior == HitTestBehavior.opaque &&
        w.onPointerUp != null,
  );

  /// 打开弹层并完成过渡，返回弹层的 future（pop 时带结果）。
  Future<Future<String?>> openSheet(WidgetTester tester) async {
    Future<String?>? popped;
    await tester.pumpWidget(
      host(() {
        popped = showMiuixVoiceRecordSheet(
          tester.element(find.text('open')),
        );
        return popped!;
      }),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('按住说话'), findsOneWidget);
    return popped!;
  }

  // ⚠️ 必须排第一：SpeechToText 是进程级单例，initialize 成功一次后就
  // 不再走通道（_initWorked 短路），「初始化失败」只能在全进程首次模拟。
  testWidgets('引擎不可用：文案区给「设备不支持」', (tester) async {
    initOk = false;
    await openSheet(tester);

    await tester.startGesture(tester.getCenter(micButton()));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // 本地 ASR 兜底的模型检查里有 250ms 的磁盘/通道超时兜底，fake 时间
    // 走过它 ensureReady 才会落定（见 LocalAsrService._fileExists）。
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('当前设备不支持语音输入'), findsOneWidget);
    // 引擎没起来，弹层不会自己关（future 未完成）。
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('按住 → 出定稿 → 松手 → 弹层带文本关闭', (tester) async {
    final popped = await openSheet(tester);

    autoFinal = '你好你好';
    final gesture = await tester.startGesture(tester.getCenter(micButton()));
    await tester.pump(); // begin() → ensureReady → start(listen)
    await tester.pump();
    await fireResult('你好你好', true);
    await tester.pump();
    // 收音中：实时文本出现。
    expect(find.text('你好你好'), findsOneWidget);

    // 真实墙钟等过最小按住时长。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 450)),
    );
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 900));

    final text = await popped;
    expect(text, '你好你好');
    expect(listenCalled, isTrue);
  });

  /// 安卓上第一次收音（尤其「刚拿到麦克风权限」之后）识别服务往往还没绑定
  /// 好，`startListening` 会立刻回 `error_client`。它是转瞬即逝的客户端侧
  /// 握手失败 —— 以前这条错误直接糊到界面上（「语音输入失败：error_client」），
  /// 现在服务层静默重开一次，用户看不到任何报错。
  testWidgets('error_client：静默重开一次，不把错误甩给界面', (tester) async {
    final popped = await openSheet(tester);

    final gesture = await tester.startGesture(tester.getCenter(micButton()));
    await tester.pump(); // begin() → ensureReady → start(listen)
    await tester.pump();
    await tester.pump();
    expect(listenCount, 1);

    // 引擎回一条 error_client（识别服务还没绑定好）。
    await fireError('error_client');
    await tester.pump();
    // 仍在收音态：界面上不该出现任何失败文案。
    expect(find.textContaining('error_client'), findsNothing);
    expect(find.text('正在聆听…'), findsOneWidget);

    // 等过服务层那拍重开延迟（320ms）→ 引擎被重新 listen 了一次。
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(listenCount, 2, reason: 'error_client 之后应该静默重开一次');

    // 重开这一轮拿到定稿 → 正常带文本关闭。
    await fireResult('你好', true);
    await tester.pump();
    expect(find.text('你好'), findsOneWidget);

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 450)),
    );
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 900));
    expect(await popped, '你好');
  });

  testWidgets('快速点按不提交，弹层留在原地可重按', (tester) async {
    final popped = await openSheet(tester);

    final gesture = await tester.startGesture(tester.getCenter(micButton()));
    await tester.pump();
    await tester.pump();
    await gesture.up(); // 立刻松手（真实间隔 ≈ 0 < 350ms）
    await tester.pump(const Duration(milliseconds: 200));

    expect(listenCalled, isTrue); // 按下确实起了引擎
    expect(find.text('按住说话'), findsOneWidget); // 回到初始提示
    expect(find.text('没听清，再按住说一次'), findsNothing);

    // 弹层还开着：再按住一轮，这次给结果 → 正常带文本关闭。
    autoFinal = '你好';
    final g2 = await tester.startGesture(tester.getCenter(micButton()));
    await tester.pump();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 450)),
    );
    await g2.up();
    await tester.pump(const Duration(milliseconds: 900));
    expect(await popped, '你好');
  });

  testWidgets('松手时一条结果都没有：不关弹层，提示没听清', (tester) async {
    await openSheet(tester);

    final gesture = await tester.startGesture(tester.getCenter(micButton()));
    await tester.pump();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 450)),
    );
    await gesture.up();
    // 宽限 2.6s 是 fake 定时器 —— 用 pump 推进 fake 时钟驱动它。
    await tester.pump(const Duration(milliseconds: 2800));
    await tester.pump();

    expect(listenCalled, isTrue);
    expect(find.text('没听清，再按住说一次'), findsOneWidget);
    // 弹层还开着（future 未完成）。
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  test('SpeechReady 判定：服务层枚举齐全（防手滑删值）', () {
    expect(SpeechReady.values.length, 4);
  });
}
