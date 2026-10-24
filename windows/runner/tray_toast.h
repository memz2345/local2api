#ifndef RUNNER_TRAY_TOAST_H_
#define RUNNER_TRAY_TOAST_H_

// windows/runner/tray_toast.h
//
// 托盘提示用的原生 Windows Toast（WinRT ToastGeneric + 两个操作按钮）。
//
// 为什么不用 fluttertoast / 应用内浮层：这个提示发生在「窗口已经收进托盘、
// 客户区整个不可见」之后，Flutter 画什么用户都看不到；只有系统通知中心里的
// Toast 能穿透出来。为什么要自己写而不是拉 local_notifier：那个包不支持
// 按钮（action buttons），而这里要的正是「不再提示 / 设置」两个动作。
//
// 动作回传走的是跳转列表同一条路：按钮的 arguments 写成
// `--l2a-action=<动作串>`，点击后系统会用 Start Menu 快捷方式重新拉起本 exe，
// main.cpp 的单实例转发把参数递给已经在跑的实例，Dart 侧在
// JumpListService.onAction 里收到。
//
// 因此首次弹 Toast 前必须保证 Start Menu 里有带 AUMID 的快捷方式 ——
// 非打包（Win32）进程没有它时 ToastNotificationManager 会直接抛
// 0x80070490（ELEMENT_NOT_FOUND）。[EnsureShortcut] 做的就是这件事。

#include <flutter/binary_messenger.h>
#include <windows.h>

namespace tray_toast {

/// 确保开始菜单里有带本应用 AUMID 的快捷方式。
///
/// 非打包 Win32 进程弹任何 Toast 之前都必须有它，否则
/// ToastNotificationManager 抛 0x80070490。托盘提示会自动补；dsh 通知
/// 桥（dsh_toast.cpp）直接复用这一个实现，避免两处 AUMID 写法漂移。
bool EnsureShortcut();

/// 注册 "com.memz2345.local2api/tray_toast" 通道。
/// 方法只有一个 `show`，参数：title / body / dismissLabel / dismissArgs /
/// settingsLabel / settingsArgs，返回 bool（false = 系统不支持或弹出失败）。
void RegisterChannel(flutter::BinaryMessenger* messenger, HWND owner);

}  // namespace tray_toast

#endif  // RUNNER_TRAY_TOAST_H_
