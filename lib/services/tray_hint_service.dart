// lib/services/tray_hint_service.dart
//
// 「收进托盘了，我还在」这条系统提示的 Dart 侧。
//
// 原生实现见 windows/runner/tray_toast.cpp（WinRT ToastGeneric + 两个按钮）。
// 只有 Windows 有这个能力，其它平台 [isSupported] 为 false，调用方直接跳过。
//
// 按钮点击**不会**在本进程里回调（非打包 Win32 进程的 Toast 没有 COM
// activator）：系统会用 Start Menu 快捷方式再拉一个本 exe，命令行带
// `--l2a-action=…`，main.cpp 的单实例转发把它交给已在运行的实例，
// 最终落到 JumpListService.onAction → dispatchQuickAction。
// 所以这里的两个动作串必须与 [QuickAction] 里的常量一致。

import 'dart:io';

import 'package:flutter/services.dart';

class TrayHintService {
  TrayHintService._();

  static final TrayHintService instance = TrayHintService._();

  static const MethodChannel _channel = MethodChannel(
    'com.memz2345.local2api/tray_toast',
  );

  static bool get isSupported => Platform.isWindows;

  /// 弹一条「我在这里」的系统通知。返回 false = 系统不支持 / 弹出失败。
  Future<bool> show({
    required String title,
    required String body,
    required String dismissLabel,
    required String settingsLabel,
  }) async {
    if (!isSupported) return false;
    try {
      final shown = await _channel.invokeMethod<bool>('show', {
        'title': title,
        'body': body,
        'dismissLabel': dismissLabel,
        // 与 QuickAction.trayHintOff / trayHintSettings 对齐；改一处必须改两处。
        'dismissArgs': '--l2a-action=tray_hint_off',
        'settingsLabel': settingsLabel,
        'settingsArgs': '--l2a-action=tray_hint_settings',
      });
      return shown ?? false;
    } catch (_) {
      // 老系统 / 通道未注册（widget test）：提示弹不出来不该影响收托盘本身。
      return false;
    }
  }
}
