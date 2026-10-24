// test/device_corner_service_test.dart
//
// 页面推入转场的「自适应圆角」：
//   1. [DeviceCornerService.resolve] 的自动 / 手动取舍（读不到一律回退手动值，
//      读到离谱的大值要夹到上限）；
//   2. [DeviceCornerService.load] 走原生通道拿设备值（含失败降级）；
//   3. app 级接线：主题里那个 [IosPushPageTransitionsBuilder] 的圆角必须跟着
//      设备值 / 设置走 —— 光有服务不算修好，漏接 theme 就是老样子写死 26。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/app_settings.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/device_corner_service.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/src/enums.dart';
import 'package:local2api/ui/app.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/widgets/ios_push_transition.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const MethodChannel _channel = MethodChannel(
  'com.memz2345.local2api/device_corners',
);

/// 主题里那个转场构建器的圆角。
double _themeCorner(WidgetTester tester) {
  final app = tester.widget<MaterialApp>(find.byType(MaterialApp).first);
  final builders = app.theme!.pageTransitionsTheme.builders;
  final builder = builders[TargetPlatform.android];
  expect(builder, isA<IosPushPageTransitionsBuilder>());
  return (builder! as IosPushPageTransitionsBuilder).cornerRadius;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    DeviceCornerService.debugSetDetected(0);
    DeviceCornerService.debugForceSupported = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('resolve：自动 / 手动取舍', () {
    test('关掉自动就用滑块的手动值', () {
      DeviceCornerService.debugSetDetected(40);
      expect(DeviceCornerService.resolve(auto: false, manual: 18), 18);
    });

    test('开着自动且读到了设备值 → 用设备值', () {
      DeviceCornerService.debugSetDetected(40);
      expect(DeviceCornerService.resolve(auto: true, manual: 18), 40);
    });

    test('开着自动但读不到（方角屏 / 桌面）→ 回退手动值', () {
      DeviceCornerService.debugSetDetected(0);
      expect(DeviceCornerService.resolve(auto: true, manual: 18), 18);
      expect(DeviceCornerService.hasDeviceValue, isFalse);
    });

    test('异常大的上报值夹到上限', () {
      DeviceCornerService.debugSetDetected(999);
      expect(
        DeviceCornerService.resolve(auto: true, manual: 18),
        DeviceCornerService.kMaxAutoRadius,
      );
    });
  });

  group('load：走原生通道', () {
    test('读到 dp 半径与来源', () async {
      DeviceCornerService.debugForceSupported = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            expect(call.method, 'getCornerRadius');
            return {'radiusDp': 32.5, 'source': 'windowInsets'};
          });

      await DeviceCornerService.load();

      expect(DeviceCornerService.detected, closeTo(32.5, 0.001));
      expect(DeviceCornerService.hasDeviceValue, isTrue);
      expect(DeviceCornerService.source, 'windowInsets');
    });

    test('通道返回 0（方角屏）→ 视为未知', () async {
      DeviceCornerService.debugForceSupported = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            return {'radiusDp': 0, 'source': 'none'};
          });

      await DeviceCornerService.load();

      expect(DeviceCornerService.detected, 0);
      expect(DeviceCornerService.hasDeviceValue, isFalse);
    });

    test('原生报错 → 静默降级为未知，不抛', () async {
      DeviceCornerService.debugForceSupported = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            throw PlatformException(code: 'BOOM');
          });

      await DeviceCornerService.load();

      expect(DeviceCornerService.detected, 0);
      expect(DeviceCornerService.source, 'none');
    });

    test('非移动平台直接跳过（不碰通道）', () async {
      // 宿主测试机不是 android / ios，_supported 为 false。
      DeviceCornerService.debugForceSupported = false;
      DeviceCornerService.debugSetDetected(40);

      await DeviceCornerService.load();

      expect(DeviceCornerService.detected, 0);
      expect(DeviceCornerService.source, 'none');
    });
  });

  group('主题接线：转场圆角跟着设备 / 设置走', () {
    test('AppTheme 默认圆角就是兜底值，传参能改', () {
      final dflt = AppTheme.light().pageTransitionsTheme.builders;
      expect(
        (dflt[TargetPlatform.android]! as IosPushPageTransitionsBuilder)
            .cornerRadius,
        AppTheme.kDefaultCornerRadius,
      );
      final custom = AppTheme.light(
        cornerRadius: 34,
      ).pageTransitionsTheme.builders;
      expect(
        (custom[TargetPlatform.iOS]! as IosPushPageTransitionsBuilder)
            .cornerRadius,
        34,
      );
    });

    Future<SettingsService> pumpApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 2800);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      // 测试字体偏宽，某些 Row 会出「伪溢出」，与本用例无关。
      final prevOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
          return;
        }
        prevOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = prevOnError);

      SharedPreferences.setMockInitialValues({});
      final settings = AppSettings();
      final display = SettingsService();
      final store = ConfigStore();
      final profileStore = ProfileStore();
      await Future.wait([
        settings.load(),
        display.load(),
        store.load(),
        profileStore.load(),
      ]);
      final controller = ServerController(store);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(value: display),
            ChangeNotifierProvider<ProfileStore>.value(value: profileStore),
          ],
          child: Local2ApiApp(settings: settings, controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      return display;
    }

    testWidgets('自动开 + 读到设备值 → 主题用设备圆角', (tester) async {
      DeviceCornerService.debugSetDetected(36);
      await pumpApp(tester);

      expect(_themeCorner(tester), 36);
    });

    testWidgets('关掉自动 → 用滑块手动值；改滑块主题跟着变', (tester) async {
      DeviceCornerService.debugSetDetected(36);
      final display = await pumpApp(tester);
      expect(_themeCorner(tester), 36, reason: '起步应该是设备值');

      await display.setIosPushTransitionCornerAuto(false);
      await tester.pumpAndSettle();
      expect(
        _themeCorner(tester),
        26,
        reason: '关掉自动后应回落到滑块的默认值',
      );

      await display.setIosPushTransitionCornerRadius(12);
      await tester.pumpAndSettle();
      expect(_themeCorner(tester), 12, reason: '滑块改了主题没跟上');
    });

    testWidgets('读不到设备圆角（桌面）→ 用手动值', (tester) async {
      DeviceCornerService.debugSetDetected(0);
      final display = await pumpApp(tester);

      expect(_themeCorner(tester), 26);

      await display.setIosPushTransitionCornerRadius(20);
      await tester.pumpAndSettle();
      expect(_themeCorner(tester), 20);
    });

    testWidgets('miuix 分支同样吃自适应圆角', (tester) async {
      DeviceCornerService.debugSetDetected(30);
      final display = await pumpApp(tester);

      await display.setUiStyle(UiStyle.miuix);
      await tester.pumpAndSettle();

      expect(_themeCorner(tester), 30);
    });
  });
}
