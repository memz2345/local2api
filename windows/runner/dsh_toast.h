#ifndef RUNNER_DSH_TOAST_H_
#define RUNNER_DSH_TOAST_H_

// windows/runner/dsh_toast.h
//
// DeepSeek Harness 的 Windows 系统通知桥（WinRT ToastGeneric）。
//
// 和安卓那条通知链路对齐，但实现完全在 Windows 原生侧：
//   · 进度：一条带 ProgressBar 的常驻 Toast，按 tag/group 原地替换；
//   · 询问：Toast 正文 + 输入框（RemoteInput 的 Windows 对应物是
//     <input type="text"/> + hint-inputId）；
//   · 选项：正文里列 1/2/3，按钮也映射到选项；输入框里打 1/2/3 由
//     Dart 侧映射成预置选项，别的文字当自定义回答；
//   · 完成：标题 = 会话标题，正文 = agent 输出。
//
// 交互事件走 <actions> 的 arguments（`--l2a-action=dsh_toast;...`），
// ToastNotification.Activated 在本进程时直接回传；进程不在时系统会用
// 开始菜单快捷方式拉起本 exe，main.cpp 的单实例转发照旧兜底。
// 非打包 Win32 进程必须先有带 AUMID 的快捷方式，这里复用
// tray_toast::EnsureShortcut()。

#include <flutter/binary_messenger.h>
#include <windows.h>

#include <string>

namespace dsh_toast {

/// 原生 -> Dart 的事件消息。FlutterWindow::MessageHandler 转交给
/// [HandleWindowMessage]。
constexpr UINT kToastEventMessage = WM_APP + 0x271;

/// 注册 "com.memz2345.local2api/dsh_toast" 通道。
///
/// 方法：
///   · show       展示 / 替换一条 Toast，返回 bool
///   · cancel     撤掉指定 tag+group 的 Toast
///   · cancelGroup 撤掉整组
///   · ping       通道探活（返回 true）
///   · stats      诊断计数（show / update），集成测试用
void RegisterChannel(flutter::BinaryMessenger* messenger, HWND owner);

/// 处理 [kToastEventMessage]：把原生侧攒好的事件推给 Dart。
/// 不是本模块的消息返回 false。
bool HandleWindowMessage(HWND hwnd,
                         UINT message,
                         WPARAM wparam,
                         LPARAM lparam,
                         LRESULT* result);

}  // namespace dsh_toast

#endif  // RUNNER_DSH_TOAST_H_
