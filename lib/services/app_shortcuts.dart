// lib/services/app_shortcuts.dart
//
// 安卓长按图标快捷入口（App Shortcuts，自 InstallerX-Revived 模式移植）。
//
// 三个入口：启动/关闭服务（标签随运行状态换）、查看 token 用量、发现页。
// 全部走动态 Shortcut：Dart 在启动与服务状态变化时重发清单（标签用 l10n
// 现算），原生 ShortcutHost 负责注册；点触后经 MainActivity（singleTop）
// 带回 "shortcut" extra 暂存，Dart 在回到前台时取走分发。
//
// 注意：动态 Shortcut 在 App 首次运行后才注册；进程被杀后标签可能滞后
// （如 config.autoStart 已把服务拉起，但快捷方式还写着「启动服务」），
// 此时点它是幂等的「切换」语义——运行中就停、停止就启动，回前台后标签
// 立即纠正。

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppShortcuts {
  AppShortcuts._();

  static const MethodChannel _channel = MethodChannel(
    'com.memz2345.local2api/shortcuts',
  );

  /// 通道不可用（非 Android 壳 / 插件未注册）时置 false，避免反复撞。
  bool _supported = !kIsWeb && Platform.isAndroid;

  static final AppShortcuts instance = AppShortcuts._();

  Future<void> publish({
    required String toggleLabel,
    required String statsLabel,
    required String discoverLabel,
  }) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('publish', {
        'shortcuts': [
          {'id': 'toggle_server', 'label': toggleLabel, 'icon': 'power'},
          {'id': 'token_stats', 'label': statsLabel, 'icon': 'chart'},
          {'id': 'discover', 'label': discoverLabel, 'icon': 'compass'},
        ],
      });
    } on PlatformException {
      _supported = false;
    } on MissingPluginException {
      _supported = false;
    }
  }

  /// 取走暂存的 Shortcut 动作 id（无则 null）。
  Future<String?> takePending() async {
    if (!_supported) return null;
    try {
      return await _channel.invokeMethod<String>('takePending');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
