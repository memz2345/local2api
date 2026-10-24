// lib/services/lab/lab_notification_settings.dart
//
// 实验室「通知」那一屏的状态与动作（两套 UI 共用）。
//
// 三个开关各自对应一条系统侧门槛，缺一条通知就发不出去或不升为实时更新：
//   · POST_NOTIFICATIONS（13+ 运行时权限）
//   · 系统允许本应用发实时更新（16+，用户可以在设置里关）
//   · 忽略电池优化（后台长时间跑 node / dsh 的前提）
//
// 状态只在 Android 上有意义，其它平台一律 null（UI 上整段不显示）。

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../android_notifications.dart';
import 'dsh_task_center.dart';
import 'dsh_windows_toast.dart';

class LabNotificationSettings extends ChangeNotifier {
  LabNotificationSettings._();

  static final LabNotificationSettings instance = LabNotificationSettings._();

  bool? _permission;
  bool? _promoted;
  bool? _batteryIgnored;
  bool _loaded = false;

  /// 有没有通知权限（Android 专属；Windows 恒为 null）。
  bool? get permission => _permission;

  /// 系统允许发「实时更新」吗（API 36+）。
  bool? get promoted => _promoted;

  /// 已忽略电池优化吗。
  bool? get batteryIgnored => _batteryIgnored;

  bool get supported =>
      AndroidNotifications.isSupported || DshWindowsToast.isSupported;

  Future<void> refresh() async {
    // Windows 没有运行时通知权限 / 电池优化这一套；状态刷新只对安卓有意义。
    if (!AndroidNotifications.isSupported) return;
    _permission = await AndroidNotifications.hasPermission();
    _promoted = await AndroidNotifications.canPostPromoted();
    _batteryIgnored =
        await AndroidNotifications.isIgnoringBatteryOptimizations();
    _loaded = true;
    notifyListeners();
  }

  /// 挂通知事件回调（回复 / 取消）并刷新状态。重复调用安全。
  Future<void> attach({
    String? replyLabel,
    String? cancelLabel,
    String? openLabel,
    String? inputPlaceholder,
    String? optionsHint,
    String? answerHint,
    String Function(int done, int total)? stepsLabel,
    void Function()? onOpenWeb,
  }) async {
    if (!supported) return;
    await DshTaskCenter.instance.attach(
      replyLabel: replyLabel,
      cancelLabel: cancelLabel,
      openLabel: openLabel,
      inputPlaceholder: inputPlaceholder,
      optionsHint: optionsHint,
      answerHint: answerHint,
      stepsLabel: stepsLabel,
    );
    // 应用级默认动作（app.dart）优先；页面 pop 后不会留下 dead closure。
    if (onOpenWeb != null) DshTaskCenter.instance.onOpenWeb ??= onOpenWeb;
    if (!_loaded) await refresh();
  }

  Future<void> requestPermission() async {
    if (!supported) return;
    await AndroidNotifications.requestPermission();
    // 权限对话框是异步的：不轮询，UI 回到前台再刷（见页面的 didPop 回调）。
    await refresh();
  }

  Future<void> requestIgnoreBattery() async {
    if (!supported) return;
    final ok = await AndroidNotifications.requestIgnoreBatteryOptimizations();
    // 系统对话框同意与否不会在这里返回，回来再读一次真实状态。
    if (!ok) await AndroidNotifications.openBatteryOptimizationSettings();
    await refresh();
  }

  Future<void> openNotificationSettings() =>
      AndroidNotifications.openNotificationSettings();

  /// 发一条演示通知：走真实任务的同一条路径（分段 + 里程碑 + 常驻），
  /// 用来确认「权限 / 实时更新 / 渠道」这套链路通不通。
  Future<NotificationPostResult> sendTestNotification({
    required String title,
    required String text,
    required List<String> steps,
  }) async {
    final center = DshTaskCenter.instance;
    final result = await center.start(title: title, status: text, steps: steps);
    // 走一步，让通知上的分段真的分成「已完成 / 进行中 / 未开始」三色，
    // 一眼能看出这是 ProgressStyle 而不是普通进度条。
    if (steps.length > 1) await center.advance();
    if (DshWindowsToast.isSupported) {
      unawaited(_runWindowsToastDemo(center, steps));
    }
    return result;
  }

  /// Windows 的测试链路：进度条 -> 选项提问（输入框）-> 结果。
  ///
  /// 不 await：提问可能一直等用户，页面按钮不能跟着挂住。
  Future<void> _runWindowsToastDemo(
    DshTaskCenter center,
    List<String> steps,
  ) async {
    final reply = await center.ask(
      question: '测试选项：直接输入 1 / 2 / 3，或输入你自己的内容',
      options: steps,
    );
    if (reply == null) {
      await center.cancelTask();
      return;
    }
    await center.finish(
      title: 'DeepSeek Harness',
      text: '收到回答：$reply',
      subText: '测试通知',
    );
  }
}
