#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <psapi.h>      // GetModuleFileNameExW（按 exe 路径认同一份安装）
#include <shobjidl.h>   // SetCurrentProcessExplicitAppUserModelID
#include <shellapi.h>
#include <string>
#include <vector>

#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "psapi.lib")

#include "flutter_window.h"
#include "jumplist.h"
#include "utils.h"

namespace {

// 与 win32_window.cpp 里注册的主窗口类名一致：只认这个类的顶层窗口。
constexpr wchar_t kRunnerWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

struct RunningInstance {
  const wchar_t* exe_path;
  DWORD self_pid;
  HWND hwnd;
};

BOOL CALLBACK FindRunnerWindow(HWND hwnd, LPARAM lparam) {
  auto* found = reinterpret_cast<RunningInstance*>(lparam);
  if (found->hwnd) return FALSE;  // 已找到，停止枚举

  DWORD pid = 0;
  ::GetWindowThreadProcessId(hwnd, &pid);
  if (!pid || pid == found->self_pid) return TRUE;
  // ⚠️ 不要用 IsWindowVisible 过滤：收进托盘后窗口是 SW_HIDE 状态，
  // 「点 Toast 上的设置」和跳转列表都要能把动作转给这个隐藏实例。
  // 同一个 exe + 同一个窗口类已经足够定位（多实例按 exe 路径区分）。

  wchar_t cls[128] = {};
  if (::GetClassNameW(hwnd, cls, 128) == 0) return TRUE;
  if (wcscmp(cls, kRunnerWindowClass) != 0) return TRUE;

  HANDLE proc = ::OpenProcess(
      PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ, FALSE, pid);
  if (!proc) return TRUE;
  wchar_t path[MAX_PATH] = {};
  DWORD len = ::GetModuleFileNameExW(proc, nullptr, path, MAX_PATH);
  ::CloseHandle(proc);
  if (len == 0) return TRUE;

  // 只匹配同一份可执行文件：别的目录里再装一套 Local2API 时不会误发。
  if (_wcsicmp(path, found->exe_path) != 0) return TRUE;

  found->hwnd = hwnd;
  return FALSE;
}

// 已有实例在跑：把跳转列表的动作转发过去，本进程随即退出。
// 不这么做的话，点一次「启动服务」会拉起第二个 Local2API，两个实例抢同一个
// 监听端口 —— 后起的那个直接绑不上，用户看到的却是「点了没反应」。
bool ForwardActionToRunningInstance(const std::string& action) {
  wchar_t exe_path[MAX_PATH] = {};
  ::GetModuleFileNameW(nullptr, exe_path, MAX_PATH);

  RunningInstance target{exe_path, ::GetCurrentProcessId(), nullptr};
  ::EnumWindows(FindRunnerWindow, reinterpret_cast<LPARAM>(&target));
  if (!target.hwnd) return false;  // 没有运行中的实例 → 走冷启动

  COPYDATASTRUCT cds;
  cds.dwData = jumplist::kCopyDataMagic;
  cds.cbData = static_cast<DWORD>(action.size());
  cds.lpData = const_cast<char*>(action.data());
  LRESULT sent = ::SendMessageTimeoutW(
      target.hwnd, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&cds),
      SMTO_ABORTIFHUNG, 2000, nullptr);
  if (!sent) return false;  // 转发失败（对方卡死等）：冷启动兜底

  // 「不再提示」不该把窗口从托盘里弹出来 —— 用户点它就是想安静地留在托盘。
  if (action != "tray_hint_off") {
    ::ShowWindow(target.hwnd, SW_RESTORE);
    ::SetForegroundWindow(target.hwnd);
  }
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // ⚠️ 必须在创建【任何窗口】之前设好进程级 AUMID：否则顶层窗口拿到的是
  // 「默认 AUMID」，右键任务栏图标时 Windows 用默认 AUMID 去查跳转列表，
  // 我们写进去的那份永远不显示（同 NaviFlash 的「关键修复」）。
  ::SetCurrentProcessExplicitAppUserModelID(jumplist::kAppUserModelID);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  // 点跳转列表项启动时带的 --l2a-action=…：先试单实例转发，成功后本进程退出。
  const std::string action = jumplist::ParseActionArg(command_line_arguments);
  if (!action.empty() && ForwardActionToRunningInstance(action)) {
    return EXIT_SUCCESS;
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"local2api", origin, size)) {
    return EXIT_FAILURE;
  }
  // 冷启动（没有实例在跑时点跳转列表）：动作先暂存，Dart 就绪后经
  // consumeLaunchArgs 取回分发。
  jumplist::SetPendingAction(action);
  // ⚠️ 必须是 false：Dart 侧的 WindowService（window_manager +
  // tray_manager）接管了关闭 —— 原生层在这儿 PostQuitMessage 的话，
  // onWindowClose 永远轮不到跑，「最小化到托盘 / 退出」那个询问框就看不见了。
  // 真正的退出由 WindowService.quitApp() 走 windowManager.destroy() 发起。
  window.SetQuitOnClose(false);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
