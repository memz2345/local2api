#ifndef RUNNER_TASK_DIALOG_H_
#define RUNNER_TASK_DIALOG_H_

// windows/runner/task_dialog.h
//
// 通用**任务对话框**（Win32 TaskDialog + 命令链接），移植自 NaviFlash
// windows/runner/task_dialog.{h,cpp}，给 Dart 侧一个「一个主标题 + 若干带
// 副标题的选项」的原生询问框：
//
//   任务
//   ➡ 启动服务            监听 0.0.0.0:8080
//   ➡ 暂停服务            断开当前连接
//   ➡ 设置                主题 / 服务 / 网络
//
// 为什么用 TaskDialog 而不是 MessageBox：命令链接（图标 + 主文本 + 副标题）
// 只有 TaskDialog 支持，观感是系统原生的那条路子。
// 依赖 ComCtl32 v6 —— runner.exe.manifest 里必须声明 Common-Controls 6.0，
// 否则 TaskDialogIndirect 直接返回 E_NOTIMPL（NaviFlash 踩过）。
//
// 非 Windows 平台（安卓 / iOS）由 Dart 侧的 Flutter 对话框承担，见
// lib/services/quick_tasks.dart。

#include <flutter/binary_messenger.h>
#include <windows.h>

#include <string>
#include <vector>

namespace task_dialog {

/// 一个命令链接（主文本 + 副标题，副标题可空）。
struct CommandLink {
  std::wstring text;
  std::wstring subtitle;
};

struct Options {
  std::wstring title;    // 窗口标题（标题栏）
  std::wstring heading;  // 主指令（大字号那行）
  std::wstring content;  // 可选正文（小字号）
  // 可选的复选框文案（TDF_VERIFICATION_FLAG_PRESENT）。非空时对话框底部多一行
  // 「☐ 下次也是这样」，勾选状态经 [Result::verified] 回传 —— 用来让用户把
  // 这一次的选择记成默认行为（Windows 关闭按钮那句询问就是这么落地的）。
  std::wstring verification;
  std::vector<CommandLink> links;
};

/// 返回值：
///   · [index] >= 0 = 选中的链接下标；[kCancelled] = 关闭 / Esc / 取消；
///     [kFailed] = 创建失败（老系统不支持等，调用方应回退）。
///   · [verified] = 底部复选框的勾选状态（没给 verification 文案时恒为 false）。
constexpr int kCancelled = -1;
constexpr int kFailed = -2;

struct Result {
  int index = kFailed;
  bool verified = false;
};

Result Show(HWND owner, const Options& options);

// 注册 "com.memz2345.local2api/task_dialog" 通道：Dart 调 show（map 参数，
// 可选 "verification"），返回 map ——
//   {"index": int, "verified": bool}
// 取消 / 失败返回 null。
void RegisterTaskDialogChannel(flutter::BinaryMessenger* messenger,
                               HWND owner);

}  // namespace task_dialog

#endif  // RUNNER_TASK_DIALOG_H_
