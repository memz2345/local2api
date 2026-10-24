// windows/runner/task_dialog.cpp
//
// 见同目录 .h 的说明。实现要点（与 NaviFlash 同一份）：
//   · TDF_USE_COMMAND_LINKS：按钮变成「图标 + 主文本 + 副标题」的命令链接，
//     按钮文字用 `主文本\n副标题` 的形式给（TaskDialog 的约定，副标题自动小字）。
//   · 不加 TDCBF_CANCEL_BUTTON：选项本身就是「算了吧」，多一个取消按钮反而啰嗦；
//     Esc / 标题栏 X 靠 TDF_ALLOW_DIALOG_CANCELLATION 仍然能关 → 返回 kCancelled。
//   · TaskDialogIndirect 自带模态消息循环，返回前会一直泵消息；它**不会**发
//     WM_QUIT（这点和手写模态循环不同，别自己 PostQuitMessage，会杀掉引擎主循环）。
#include "task_dialog.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <commctrl.h>
#include <string>
#include <vector>

#pragma comment(lib, "comctl32.lib")

namespace task_dialog {
namespace {

/// 命令链接的按钮 id 从这里开始，返回值再减回去。
constexpr int kFirstButtonId = 2000;

const char* kChannelName = "com.memz2345.local2api/task_dialog";

/// 通道实例的持有者：必须在整个进程生命周期内活着（引擎只存裸指针语义的
/// 注册项，对象一析构通道就失联）。
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel;

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return {};
  int len = ::MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
  if (len <= 0) return {};
  std::wstring ws(len - 1, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, &ws[0], len);
  return ws;
}

std::wstring StrOrEmpty(const flutter::EncodableMap* map, const char* key) {
  if (!map) return {};
  auto it = map->find(flutter::EncodableValue(key));
  if (it == map->end()) return {};
  if (const auto* s = std::get_if<std::string>(&it->second)) {
    return Utf8ToWide(*s);
  }
  return {};
}

Options FromArgs(const flutter::EncodableMap& args) {
  Options options;
  options.title = StrOrEmpty(&args, "title");
  options.heading = StrOrEmpty(&args, "heading");
  options.content = StrOrEmpty(&args, "content");
  // 可选：给了就在对话框底部挂一行复选框（「下次也是这样」那一类）。
  options.verification = StrOrEmpty(&args, "verification");

  auto it = args.find(flutter::EncodableValue("links"));
  if (it != args.end()) {
    if (const auto* list = std::get_if<flutter::EncodableList>(&it->second)) {
      for (const auto& item : *list) {
        const auto* link = std::get_if<flutter::EncodableMap>(&item);
        CommandLink cl;
        cl.text = StrOrEmpty(link, "text");
        cl.subtitle = StrOrEmpty(link, "subtitle");
        if (!cl.text.empty()) options.links.push_back(std::move(cl));
      }
    }
  }
  return options;
}

}  // namespace

Result Show(HWND owner, const Options& options) {
  if (options.links.empty()) return Result{kFailed, false};

  // TaskDialog（含命令链接样式）依赖 ComCtl32 v6
  INITCOMMONCONTROLSEX icc = {sizeof(icc), ICC_STANDARD_CLASSES};
  ::InitCommonControlsEx(&icc);

  // `主文本\n副标题`：TaskDialog 会把换行后那行渲染成小字副标题
  std::vector<std::wstring> texts;
  texts.reserve(options.links.size());
  for (const CommandLink& link : options.links) {
    std::wstring text = link.text;
    if (!link.subtitle.empty()) text += L"\n" + link.subtitle;
    texts.push_back(std::move(text));
  }

  std::vector<TASKDIALOG_BUTTON> buttons(texts.size());
  for (size_t i = 0; i < texts.size(); ++i) {
    buttons[i].nButtonID = kFirstButtonId + static_cast<int>(i);
    buttons[i].pszButtonText = texts[i].c_str();
  }

  TASKDIALOGCONFIG config = {sizeof(config)};
  config.hwndParent = owner;
  config.dwFlags = TDF_USE_COMMAND_LINKS | TDF_ALLOW_DIALOG_CANCELLATION |
                   TDF_POSITION_RELATIVE_TO_WINDOW;
  config.pszWindowTitle = options.title.empty() ? nullptr : options.title.c_str();
  config.pszMainInstruction =
      options.heading.empty() ? nullptr : options.heading.c_str();
  config.pszContent = options.content.empty() ? nullptr : options.content.c_str();
  config.pszMainIcon = TD_INFORMATION_ICON;
  config.pButtons = buttons.data();
  config.cButtons = static_cast<UINT>(buttons.size());
  config.nDefaultButton = kFirstButtonId;

  // 底部复选框（verification text）：**只要 pszVerificationText 非空就会出现**，
  // commctrl 里并没有一个「显示复选框」的 dwFlags 位 —— 唯一相关的
  // TDF_VERIFICATION_FLAG_CHECKED 是「默认勾上」，这里不勾（让用户自己选）。
  config.pszVerificationText =
      options.verification.empty() ? nullptr : options.verification.c_str();

  int pressed = 0;
  BOOL verified = FALSE;
  // 第 3 个 out 参数是单选按钮（我们用命令链接，不用它），第 4 个才是复选框。
  const HRESULT hr =
      ::TaskDialogIndirect(&config, &pressed, nullptr, &verified);
  if (FAILED(hr)) return Result{kFailed, false};
  if (pressed >= kFirstButtonId) {
    return Result{pressed - kFirstButtonId, verified == TRUE};
  }
  return Result{kCancelled, verified == TRUE};
}

void RegisterTaskDialogChannel(flutter::BinaryMessenger* messenger,
                               HWND owner) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([owner](
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (call.method_name() != "show") {
      result->NotImplemented();
      return;
    }
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args) {
      result->Success();  // null = 没选（与取消同一口径）
      return;
    }
    const Result chosen = Show(owner, FromArgs(*args));
    if (chosen.index < 0) {
      result->Success();  // 取消 / 创建失败都回 null，由 Dart 侧决定要不要兜底
      return;
    }
    result->Success(flutter::EncodableMap({
        {flutter::EncodableValue("index"),
         flutter::EncodableValue(chosen.index)},
        {flutter::EncodableValue("verified"),
         flutter::EncodableValue(chosen.verified)},
    }));
  });
  // 通道对象要活得比这次注册久（Flutter 只在销毁时清理）：放在模块级静态里，
  // 窗口重建时直接换掉上一份，避免旧对象持着已失效的 messenger 还挂在引擎上。
  g_channel = std::move(channel);
}

}  // namespace task_dialog
