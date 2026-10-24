// lib/services/device_corner_service.dart
//
// 设备**物理屏幕**四角的圆角半径（逻辑像素 / dp）。
//
// 为什么需要它：iOS 风格页面切换里，新页面从尾侧滑入、转场期间保持圆角，
// 那两个圆角在观感上正好落在**屏幕左上 / 左下角**，所以贴合屏幕本身的圆角
// 时最自然。硬编码 26 在圆角屏上会偏小（卡片像浮在屏内），在方角屏上又会
// 凭空造出圆角。
//
// 取值链（原生侧实现）：
//   - Android：`WindowInsets.getRoundedCorner`（API 31+ 官方 API）→
//     `Display.getRoundedCorner` → 私有 dimen 资源；见 DeviceCornerChannel.kt。
//   - iOS：`UIScreen._displayCornerRadius`（KVC，私有属性，取不到返回 0）。
//   - 其他平台（桌面等）：一律 0（显示器没有圆角）。
//
// 读不到（返回 0）时 [resolve] 会回退到用户在设置页调的手动值 —— 也就是说
// 这个特性**永远不会让效果比手动值更差**。
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'settings_service.dart';

abstract final class DeviceCornerService {
  static const MethodChannel _channel = MethodChannel(
    'com.memz2345.local2api/device_corners',
  );

  /// 自动模式下允许采用的最大圆角（防御异常大的上报值）。
  static const double kMaxAutoRadius = 64.0;

  /// 最近一次读到的屏幕圆角（dp）。0 = 未知（方角屏 / 平台不支持 / 读取失败）。
  static double _detected = 0;

  /// 探测来源标签，仅用于日志与设置页提示（windowInsets / display /
  /// resource / displayCornerRadius / none）。
  static String _source = 'none';

  static double get detected => _detected;

  /// 是否真的读到了设备值（false 时自动模式会回退手动值）。
  static bool get hasDeviceValue => _detected > 0;

  static String get source => _source;

  /// 测试用：绕过平台判断（`Platform.isAndroid` 在宿主机测试里恒为 false）。
  @visibleForTesting
  static bool debugForceSupported = false;

  static bool get _supported =>
      debugForceSupported || Platform.isAndroid || Platform.isIOS;

  /// 启动时读一次并缓存。之后 [resolve] 走同步读，转场构建器每帧都要用，
  /// 不能是异步的。
  ///
  /// 失败一律静默降级为「未知」，不影响启动流程。
  static Future<void> load() async {
    if (!_supported) {
      _detected = 0;
      _source = 'none';
      return;
    }
    try {
      final Map<Object?, Object?>? reply = await _channel
          .invokeMethod<Map<Object?, Object?>>('getCornerRadius');
      final num? radius = reply?['radiusDp'] as num?;
      _detected = (radius?.toDouble() ?? 0).clamp(0.0, kMaxAutoRadius);
      _source = (reply?['source'] as String?) ?? 'none';
      // 不用 kDebugMode 包：profile / release 下也要能从
      // `adb logcat | grep 设备屏幕圆角` 看到真实取值，方便真机排查。
      debugPrint('📐 设备屏幕圆角: $_detected dp (来源 $_source)');
    } on MissingPluginException {
      _detected = 0;
      _source = 'none';
    } on PlatformException catch (e) {
      _detected = 0;
      _source = 'none';
      debugPrint('⚠️ 读取设备屏幕圆角失败: ${e.message}');
    }
  }

  /// 本次转场实际使用的圆角。
  ///
  /// [auto] 打开且读到了设备值 → 设备值；否则 → [manual]（设置页滑块）。
  static double resolve({required bool auto, required double manual}) {
    if (!auto || _detected <= 0) return manual;
    return _detected.clamp(0.0, kMaxAutoRadius);
  }

  /// 一步到位：直接按当前设置算。
  static double resolveFor(SettingsService settings) => resolve(
    auto: settings.iosPushTransitionCornerAuto,
    manual: settings.iosPushTransitionCornerRadius,
  );

  /// 测试用：直接注入探测结果（跳过通道）。
  @visibleForTesting
  static void debugSetDetected(double value, {String source = 'test'}) {
    _detected = value;
    _source = value > 0 ? source : 'none';
  }
}
