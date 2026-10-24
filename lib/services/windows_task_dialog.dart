// lib/services/windows_task_dialog.dart
//
// Windows 原生**任务对话框**门面（Win32 TaskDialog + 命令链接），
// 自 NaviFlash `services/windows_task_dialog.dart` 移植，实现在
// windows/runner/task_dialog.cpp。
//
// 观感就是系统原生的那条路子：一行主标题 + 若干「图标 + 主文本 + 副标题」的
// 命令链接。非 Windows 平台（安卓 / iOS）由 Flutter 侧的同构对话框承担，
// 见 lib/services/quick_tasks.dart 的 showTaskDialog。

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 一个命令链接：主文本 + 副标题（副标题可空）。
typedef TaskDialogLink = ({String text, String subtitle});

/// 任务对话框的结果。
class TaskDialogResult {
  const TaskDialogResult({required this.index, required this.verified});

  /// 选中的命令链接下标（0 起）。
  final int index;

  /// 底部复选框（给了 [verificationText] 才会出现）的勾选状态。
  ///
  /// 用来把「这一次的选择」提升成「以后的默认行为」—— 典型的如关闭确认框里
  /// 的「下次也是这样」。没给复选框文案时恒为 false。
  final bool verified;
}

abstract final class WindowsTaskDialog {
  WindowsTaskDialog._();

  static const MethodChannel _channel = MethodChannel(
    'com.memz2345.local2api/task_dialog',
  );

  /// 测试里想走 Flutter 兜底路径时把它置 true（仅影响 isSupported）。
  @visibleForTesting
  static bool debugForceUnsupported = false;

  static bool get isSupported =>
      !kIsWeb && Platform.isWindows && !debugForceUnsupported;

  /// 弹出任务对话框；取消 / 关闭 / 创建失败返回 null。
  ///
  /// [verificationText] 给非空值时，对话框底部会多一行复选框（TaskDialog 的
  /// verification flag），勾选状态经 [TaskDialogResult.verified] 拿回来。
  static Future<TaskDialogResult?> show({
    required String title,
    required String heading,
    String? content,
    required List<TaskDialogLink> links,
    String? verificationText,
  }) async {
    if (!isSupported || links.isEmpty) return null;
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'show',
        {
          'title': title,
          'heading': heading,
          if (content != null && content.isNotEmpty) 'content': content,
          if (verificationText != null && verificationText.isNotEmpty)
            'verification': verificationText,
          'links': [
            for (final link in links)
              {'text': link.text, 'subtitle': link.subtitle},
          ],
        },
      );
      if (result == null) return null;
      final index = result['index'];
      if (index is! int || index < 0) return null;
      return TaskDialogResult(
        index: index,
        verified: result['verified'] == true,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
