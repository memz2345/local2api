#include "flutter_window.h"

#include <optional>

#include "dsh_toast.h"
#include "flutter/generated_plugin_registrant.h"
#include "jumplist.h"
#include "native_edit_menu.h"
#include "task_dialog.h"
#include "tray_toast.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  // 文本框右键的原生编辑菜单（Dart 侧 textContextMenuBuilder 调用）。
  native_edit_menu::RegisterTextEditMenuChannel(
      flutter_controller_.get(), flutter_controller_->view()->GetNativeWindow());
  // 任务栏右键的跳转列表（「任务」+「最近」上游组）与原生任务对话框：
  // 两个通道都挂在引擎 messenger 上，窗口 HWND 作为对话框的 owner。
  jumplist::RegisterChannel(flutter_controller_->engine()->messenger(),
                            flutter_controller_->view()->GetNativeWindow());
  task_dialog::RegisterTaskDialogChannel(
      flutter_controller_->engine()->messenger(),
      flutter_controller_->view()->GetNativeWindow());
  // 收进托盘时的系统提示（WinRT Toast + 不再提示 / 设置）。
  tray_toast::RegisterChannel(flutter_controller_->engine()->messenger(),
                              flutter_controller_->view()->GetNativeWindow());
  // DeepSeek Harness 的任务通知（WinRT Toast + 输入框 / 选项 / 进度 / 结果）。
  dsh_toast::RegisterChannel(flutter_controller_->engine()->messenger(),
                             flutter_controller_->view()->GetNativeWindow());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    // 单实例：另一个进程（点跳转列表项新起的那个）把动作转发过来，
    // 交给 jumplist 模块推给 Dart 在本窗口内导航。
    case WM_COPYDATA:
      if (jumplist::HandleCopyData(hwnd, lparam)) {
        return TRUE;
      }
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    default:
      // WinRT Toast 的 Activated/Dismissed 可能从别的线程来：那边只
      // PostMessage，Dart 的通道调用统一回到这条平台线程。
      {
        LRESULT toast_result = 0;
        if (dsh_toast::HandleWindowMessage(hwnd, message, wparam, lparam,
                                           &toast_result)) {
          return toast_result;
        }
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
