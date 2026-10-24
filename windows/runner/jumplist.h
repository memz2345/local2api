#ifndef RUNNER_JUMPLIST_H_
#define RUNNER_JUMPLIST_H_

// windows/runner/jumplist.h
//
// Windows 跳转列表（任务栏右键 / 开始屏幕长按图标那份菜单），自 NaviFlash
// windows/runner/flutter_window.cpp 的 Jump List 段落移植并改造成通用形态：
//
//   · 分区构成由 Dart 下发（本地化文案不在 C++ 里写死）：
//       - 「任务」区 = ICustomDestinationList::AddUserTasks，Windows 自己按
//         系统语言画「任务 / Tasks」这个小标题，所以标题不用我们给；
//         本项目放的是 启动服务 / 暂停服务 / 设置。
//       - 「最近」区 = AppendCategory(标题来自 Dart)，放当前的上游组，
//         点一条直接进那一组的编辑页。
//   · 每条都是指向本 exe 的 IShellLinkW，带 --l2a-action=<动作串>；
//     没有实例在跑 → 冷启动，Dart 通过 consumeLaunchArgs 领取；
//     已有实例在跑 → main.cpp 用 WM_COPYDATA 把动作转给现有实例，
//     这里 InvokeMethod("onAction") 推给 Dart，本进程退出（避免代理端口
//     被第二个实例抢绑）。

#include <flutter/binary_messenger.h>
#include <windows.h>

#include <string>
#include <vector>

namespace jumplist {

// 进程级 AUMID。⚠️ 必须与 main.cpp 里 SetCurrentProcessExplicitAppUserModelID
// 用的是同一个值：窗口拿默认 AUMID 时，任务栏右键去查的是默认 AUMID 的列表，
// 我们写进去的那份永远不显示（NaviFlash 踩过，注释标了「关键修复」）。
extern const wchar_t* kAppUserModelID;

// 冷启动命令行里的动作参数前缀。
extern const char* kActionArgPrefix;  // "--l2a-action="

// 从命令行参数里取动作串（没有返回空串）。
std::string ParseActionArg(const std::vector<std::string>& args);

// main.cpp：冷启动确认要开新窗口后调用，暂存动作等 Dart 领取。
void SetPendingAction(const std::string& action);

// Dart consumeLaunchArgs：取一次即清除。
std::string TakePendingAction();

// 注册 "com.memz2345.local2api/jumplist" 通道。
// [messenger] 是引擎的 BinaryMessenger；[owner] 是顶层窗口 HWND（当前只在
// WM_COPYDATA 转发时把动作推给 Dart 用到通道本身，HWND 留给后续扩展）。
void RegisterChannel(flutter::BinaryMessenger* messenger, HWND owner);

// FlutterWindow::MessageHandler 收到 WM_COPYDATA 时调用：
// 载荷是本应用关心的转发数据则处理并返回 true。
bool HandleCopyData(HWND hwnd, LPARAM lparam);

// WM_COPYDATA 的载荷标记（'L2A1'）：main.cpp 与本模块共用，别各写一份常量。
constexpr UINT32 kCopyDataMagic = 0x4C324131;

}  // namespace jumplist

#endif  // RUNNER_JUMPLIST_H_
