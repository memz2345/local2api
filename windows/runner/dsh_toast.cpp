// windows/runner/dsh_toast.cpp
//
// 实现见 dsh_toast.h。这里只做四件事：
//   1. 把 Dart 给的结构拼成 ToastGeneric XML（文本 / 输入框 / 按钮 /
//      进度条 / 静音）；
//   2. 用 tag+group 原地替换同一条通知（进度条 Stepper 就这么更新）；
//   3. 给每条 Toast 挂 Activated / Dismissed，把按钮、输入框内容、关闭
//      原因回传给 Dart；
//   4. 失败一律吞掉并返回 false —— 通知只是锦上添花，不能影响 dsh。

#include "dsh_toast.h"

#include "tray_toast.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Data.Xml.Dom.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.UI.Notifications.h>

#include <windows.h>
#include <shobjidl.h>  // GetCurrentProcessExplicitAppUserModelID

#include <cstdint>
#include <map>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

#include "jumplist.h"

#pragma comment(lib, "windowsapp.lib")

namespace dsh_toast {
namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using winrt::Windows::Data::Xml::Dom::XmlDocument;
using winrt::Windows::UI::Notifications::ToastActivatedEventArgs;
using winrt::Windows::UI::Notifications::ToastDismissedEventArgs;
using winrt::Windows::UI::Notifications::ToastDismissalReason;
using winrt::Windows::UI::Notifications::NotificationSetting;
using winrt::Windows::UI::Notifications::ToastNotification;
using winrt::Windows::UI::Notifications::ToastNotificationManager;

constexpr char kChannelName[] = "com.memz2345.local2api/dsh_toast";
constexpr wchar_t kReplyInputId[] = L"reply";

std::unique_ptr<flutter::MethodChannel<EncodableValue>> g_channel;
HWND g_owner = nullptr;

struct ActiveToast {
  ToastNotification toast{nullptr};
  winrt::event_token activated{};
  winrt::event_token dismissed{};
  uint64_t generation = 0;
};

std::map<std::wstring, ActiveToast> g_active;
uint64_t g_next_generation = 1;
// 诊断计数：Show = 会弹横幅；Update = 静默原地替换。集成测试用它确认
// 「模型每次都弹一条」的回归不会再出现。
uint64_t g_show_count = 0;
uint64_t g_update_count = 0;

std::string WideToUtf8(const std::wstring& s) {
  if (s.empty()) return {};
  const int len = ::WideCharToMultiByte(CP_UTF8, 0, s.c_str(),
                                        static_cast<int>(s.size()), nullptr, 0,
                                        nullptr, nullptr);
  if (len <= 0) return {};
  std::string out(static_cast<size_t>(len), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()),
                        out.data(), len, nullptr, nullptr);
  return out;
}

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return {};
  const int len = ::MultiByteToWideChar(CP_UTF8, 0, s.c_str(),
                                        static_cast<int>(s.size()), nullptr, 0);
  if (len <= 0) return {};
  std::wstring out(static_cast<size_t>(len), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()),
                        out.data(), len);
  return out;
}

std::wstring TrimWide(const std::wstring& s) {
  const auto first = s.find_first_not_of(L" \t\r\n");
  if (first == std::wstring::npos) return {};
  const auto last = s.find_last_not_of(L" \t\r\n");
  return s.substr(first, last - first + 1);
}

/// XML 文本转义 + 去掉 XML 1.0 不允许的控制字符（保留换行/制表）。
std::wstring EscapeXml(const std::wstring& s) {
  std::wstring out;
  out.reserve(s.size());
  for (const wchar_t c : s) {
    if (c < 0x20 && c != L'\n' && c != L'\r' && c != L'\t') continue;
    switch (c) {
      case L'&':
        out += L"&amp;";
        break;
      case L'<':
        out += L"&lt;";
        break;
      case L'>':
        out += L"&gt;";
        break;
      case L'"':
        out += L"&quot;";
        break;
      case L'\'':
        out += L"&apos;";
        break;
      default:
        out += c;
        break;
    }
  }
  return out;
}

std::wstring TextNode(const std::wstring& text) {
  if (text.empty()) return {};
  return L"<text>" + EscapeXml(text) + L"</text>";
}

std::string GetString(const EncodableMap& map, const char* key,
                      const std::string& fallback = {}) {
  const auto it = map.find(EncodableValue(key));
  if (it == map.end()) return fallback;
  if (const auto* value = std::get_if<std::string>(&it->second)) return *value;
  return fallback;
}

bool GetBool(const EncodableMap& map, const char* key, bool fallback = false) {
  const auto it = map.find(EncodableValue(key));
  if (it == map.end()) return fallback;
  if (const auto* value = std::get_if<bool>(&it->second)) return *value;
  return fallback;
}

double GetDouble(const EncodableMap& map, const char* key,
                 double fallback = 0.0) {
  const auto it = map.find(EncodableValue(key));
  if (it == map.end()) return fallback;
  if (const auto* value = std::get_if<double>(&it->second)) return *value;
  if (const auto* value = std::get_if<int32_t>(&it->second)) return *value;
  if (const auto* value = std::get_if<int64_t>(&it->second)) {
    return static_cast<double>(*value);
  }
  return fallback;
}

const EncodableList* GetList(const EncodableMap& map, const char* key) {
  const auto it = map.find(EncodableValue(key));
  if (it == map.end()) return nullptr;
  return std::get_if<EncodableList>(&it->second);
}

std::wstring ToastAumid() {
  PWSTR raw = nullptr;
  if (SUCCEEDED(::GetCurrentProcessExplicitAppUserModelID(&raw)) && raw) {
    std::wstring id(raw);
    ::CoTaskMemFree(raw);
    if (!id.empty()) return id;
  }
  return jumplist::kAppUserModelID;
}

std::wstring ActiveKey(const std::wstring& group, const std::wstring& tag) {
  return group + L"|" + tag;
}

struct ParsedAction {
  std::string key;
  std::string value;
  std::string tag;
  std::string group;
};

/// `--l2a-action=dsh_toast;k=option;tag=...;group=...;v=2`
ParsedAction ParseAction(const std::string& raw) {
  ParsedAction out;
  std::string body = raw;
  const std::string prefix = "--l2a-action=";
  if (body.rfind(prefix, 0) == 0) body = body.substr(prefix.size());
  size_t start = 0;
  while (start <= body.size()) {
    const size_t end = body.find(';', start);
    const std::string part = body.substr(
        start, end == std::string::npos ? std::string::npos : end - start);
    const size_t eq = part.find('=');
    if (eq != std::string::npos) {
      const std::string name = part.substr(0, eq);
      const std::string value = part.substr(eq + 1);
      if (name == "k") out.key = value;
      else if (name == "v") out.value = value;
      else if (name == "tag") out.tag = value;
      else if (name == "group") out.group = value;
    }
    if (end == std::string::npos) break;
    start = end + 1;
  }
  return out;
}

std::wstring BuildActionArguments(const std::wstring& tag,
                                  const std::wstring& group,
                                  const std::string& key,
                                  const std::string& value = {}) {
  std::wstring args = L"--l2a-action=dsh_toast;k=" + Utf8ToWide(key) +
                      L";tag=" + tag + L";group=" + group;
  if (!value.empty()) args += L";v=" + Utf8ToWide(value);
  return args;
}

struct PostedEvent {
  EncodableValue value;
};

void PostEvent(EncodableMap map) {
  if (g_owner == nullptr) return;
  auto* event = new PostedEvent{EncodableValue(std::move(map))};
  if (!::PostMessage(g_owner, kToastEventMessage, 0,
                     reinterpret_cast<LPARAM>(event))) {
    delete event;
  }
}

void EmitEvent(const std::string& type,
               const std::wstring& tag,
               const std::wstring& group,
               const std::string& key,
               const std::string& value,
               const std::string& text,
               const std::string& reason = {}) {
  EncodableMap map;
  map[EncodableValue("type")] = EncodableValue(type);
  map[EncodableValue("tag")] = EncodableValue(WideToUtf8(tag));
  map[EncodableValue("group")] = EncodableValue(WideToUtf8(group));
  if (!key.empty()) map[EncodableValue("key")] = EncodableValue(key);
  if (!value.empty()) map[EncodableValue("value")] = EncodableValue(value);
  if (!text.empty()) map[EncodableValue("text")] = EncodableValue(text);
  if (!reason.empty()) map[EncodableValue("reason")] = EncodableValue(reason);
  PostEvent(std::move(map));
}

void RevokeHandlers(ActiveToast& active) {
  try {
    active.toast.Activated(active.activated);
  } catch (...) {
  }
  try {
    active.toast.Dismissed(active.dismissed);
  } catch (...) {
  }
}

/// 撤掉句柄但**不**主动隐藏：同 tag+group 的下一次 Show 会原地替换，
/// 先 Hide 再 Show 会让进度条每更新一次就闪一下。
void DropActive(const std::wstring& key) {
  const auto it = g_active.find(key);
  if (it == g_active.end()) return;
  RevokeHandlers(it->second);
  g_active.erase(it);
}

void HideActive(const std::wstring& key) {
  const auto it = g_active.find(key);
  if (it == g_active.end()) return;
  try {
    RevokeHandlers(it->second);
    ToastNotificationManager::CreateToastNotifier(
        winrt::hstring(ToastAumid()))
        .Hide(it->second.toast);
  } catch (...) {
  }
  g_active.erase(it);
}

void OnToastDismissed(const std::wstring& key,
                      const std::wstring& tag,
                      const std::wstring& group,
                      uint64_t generation,
                      const ToastDismissedEventArgs& args) {
  const auto it = g_active.find(key);
  if (it == g_active.end() || it->second.generation != generation) return;
  std::string reason = "user";
  switch (args.Reason()) {
    case ToastDismissalReason::ApplicationHidden:
      reason = "app";
      break;
    case ToastDismissalReason::TimedOut:
      // 横幅超时只是淡出，通知还在操作中心里。进度 / 询问都要继续原地
      // 更新，不能把句柄扔掉 —— 扔掉之后下一次只能 Show，同一条通知会
      // 重新弹一次横幅（模型每调一次工具就弹一条的根源之一）。
      return;
    case ToastDismissalReason::UserCanceled:
    default:
      reason = "user";
      break;
  }
  RevokeHandlers(it->second);
  g_active.erase(it);
  EmitEvent("dismissed", tag, group, {}, {}, {}, reason);
}

void OnToastActivated(const std::wstring& key,
                      const std::wstring& tag,
                      const std::wstring& group,
                      uint64_t generation,
                      const winrt::Windows::Foundation::IInspectable& args) {
  const auto it = g_active.find(key);
  if (it == g_active.end() || it->second.generation != generation) return;

  std::string raw_arguments;
  std::string text;
  try {
    const auto activated = args.as<ToastActivatedEventArgs>();
    raw_arguments = winrt::to_string(activated.Arguments());
    for (const auto& pair : activated.UserInput()) {
      const std::string input_key = winrt::to_string(pair.Key());
      std::string input_value;
      try {
        input_value = winrt::to_string(
            pair.Value().as<winrt::Windows::Foundation::IStringable>().ToString());
      } catch (...) {
        continue;
      }
      if (input_key == "reply") {
        text = input_value;
      } else if (text.empty()) {
        text = input_value;
      }
    }
  } catch (...) {
  }

  const ParsedAction action = ParseAction(raw_arguments);
  std::string key_name = action.key;
  if (key_name.empty()) key_name = "open";
  const std::string trimmed_text = WideToUtf8(TrimWide(Utf8ToWide(text)));
  EmitEvent(trimmed_text.empty() ? "action" : "reply", tag, group, key_name,
            action.value, trimmed_text);
}

struct ButtonSpec {
  std::string key;
  std::string label;
  std::string value;
  bool submit = false;
};

std::wstring BuildToastXml(const EncodableMap& args,
                           const std::wstring& tag,
                           const std::wstring& group,
                           const std::string& launch_key) {
  const std::wstring title = Utf8ToWide(GetString(args, "title"));
  const std::wstring body = Utf8ToWide(GetString(args, "body"));
  const std::wstring detail = Utf8ToWide(GetString(args, "detail"));
  const bool has_progress = GetBool(args, "progress");
  const double progress = GetDouble(args, "progressValue", 0.0);
  const std::wstring progress_text = Utf8ToWide(GetString(args, "progressText"));
  const bool input = GetBool(args, "input");
  const std::wstring placeholder =
      Utf8ToWide(GetString(args, "inputPlaceholder"));
  const bool silent = GetBool(args, "silent");
  const bool long_duration = GetBool(args, "longDuration");

  std::vector<ButtonSpec> buttons;
  if (const auto* list = GetList(args, "buttons")) {
    for (const auto& item : *list) {
      const auto* map = std::get_if<EncodableMap>(&item);
      if (map == nullptr) continue;
      ButtonSpec spec;
      spec.key = GetString(*map, "key");
      spec.label = GetString(*map, "label");
      spec.value = GetString(*map, "value");
      spec.submit = GetBool(*map, "submit");
      if (spec.key.empty() || spec.label.empty()) continue;
      buttons.push_back(std::move(spec));
      if (buttons.size() >= 5) break;
    }
  }

  const std::wstring launch =
      BuildActionArguments(tag, group, launch_key.empty() ? "open" : launch_key);
  std::wstring xml = L"<toast";
  if (long_duration) xml += L" duration=\"long\"";
  xml += L" activationType=\"foreground\" launch=\"" + EscapeXml(launch) +
         L"\"><visual><binding template=\"ToastGeneric\">";
  xml += TextNode(title.empty() ? L"DeepSeek Harness" : title);
  xml += TextNode(body);
  xml += TextNode(detail);
  if (has_progress) {
    double clamped = progress;
    if (clamped < 0) clamped = 0;
    if (clamped > 1) clamped = 1;
    std::wostringstream value_stream;
    value_stream.setf(std::ios::fixed);
    value_stream.precision(4);
    value_stream << clamped;
    xml += L"<progress";
    if (!progress_text.empty()) {
      xml += L" status=\"" + EscapeXml(progress_text) + L"\"";
      xml += L" valueStringOverride=\"" + EscapeXml(progress_text) + L"\"";
    }
    xml += L" value=\"" + value_stream.str() + L"\"/>";
  }
  xml += L"</binding></visual>";

  if (input || !buttons.empty()) {
    xml += L"<actions>";
    if (input) {
      xml += L"<input id=\"" + std::wstring(kReplyInputId) +
             L"\" type=\"text\" placeHolderContent=\"" +
             EscapeXml(placeholder) + L"\"/>";
    }
    for (const auto& button : buttons) {
      const std::wstring arguments =
          BuildActionArguments(tag, group, button.key, button.value);
      xml += L"<action content=\"" + EscapeXml(Utf8ToWide(button.label)) +
             L"\" arguments=\"" + EscapeXml(arguments) + L"\"";
      if (input && button.submit) {
        xml += L" hint-inputId=\"" + std::wstring(kReplyInputId) + L"\"";
      }
      xml += L"/>";
    }
    xml += L"</actions>";
  }
  if (silent) xml += L"<audio silent=\"true\"/>";
  xml += L"</toast>";
  return xml;
}

bool ShowToast(const EncodableMap& args) {
  try {
    const std::wstring tag = Utf8ToWide(GetString(args, "tag", "dsh"));
    const std::wstring group = Utf8ToWide(GetString(args, "group", "dsh"));
    const std::wstring launch_key = Utf8ToWide(GetString(args, "launchKey", "open"));
    const bool silent = GetBool(args, "silent");
    const std::wstring xml = BuildToastXml(args, tag, group,
                                           WideToUtf8(launch_key));
    const auto key = ActiveKey(group, tag);

    XmlDocument doc;
    doc.LoadXml(winrt::hstring(xml));
    ToastNotification toast(doc);
    toast.Tag(winrt::hstring(tag));
    toast.Group(winrt::hstring(group));

    ActiveToast active;
    active.toast = toast;
    active.generation = g_next_generation++;
    const uint64_t generation = active.generation;
    active.activated = toast.Activated(
        [key, tag, group, generation](
            const ToastNotification&,
            const winrt::Windows::Foundation::IInspectable& event_args) {
          OnToastActivated(key, tag, group, generation, event_args);
        });
    active.dismissed = toast.Dismissed(
        [key, tag, group, generation](const ToastNotification&,
                                      const ToastDismissedEventArgs& event_args) {
          OnToastDismissed(key, tag, group, generation, event_args);
        });

    auto notifier = ToastNotificationManager::CreateToastNotifier(
        winrt::hstring(ToastAumid()));

    // 静默更新（silent=true）用 `ToastNotification::SuppressPopup`：同
    // tag+group 的通知在操作中心里原地替换，但**不重新弹横幅**。之前一律
    // Show，模型每调一次工具 / 每思考一次就弹一条，用户根本没法用。
    //
    // 不用 `ToastNotifier::Update`：它只接受 `NotificationData`（数据绑定
    // 模板），我们发的是静态 ToastGeneric XML，塞不进去。
    if (silent) {
      // 老系统上这个属性可能不存在：失败就算了，至少音频是静音的。
      try {
        toast.SuppressPopup(true);
      } catch (...) {
      }
    }

    // 新 toast 已经挂好事件回调；旧句柄只撤销回调，不 Hide（Hide 再
    // Show 会让 Stepper 闪一下）。
    DropActive(key);
    g_active.emplace(key, std::move(active));
    if (silent) {
      ++g_update_count;
    } else {
      ++g_show_count;
    }
    try {
      notifier.Show(toast);
    } catch (...) {
      HideActive(key);
      throw;
    }
    return true;
  } catch (const winrt::hresult_error& error) {
    OutputDebugStringW(
        (std::wstring(L"[dsh_toast] show failed: ") + error.message().c_str() +
         L"\n")
            .c_str());
    return false;
  } catch (...) {
    OutputDebugStringW(L"[dsh_toast] show failed: unknown\n");
    return false;
  }
}

void CancelOne(const std::wstring& tag, const std::wstring& group) {
  const auto key = ActiveKey(group, tag);
  HideActive(key);
  try {
    ToastNotificationManager::History().Remove(
        winrt::hstring(tag), winrt::hstring(group),
        winrt::hstring(ToastAumid()));
  } catch (...) {
  }
}

void CancelGroup(const std::wstring& group) {
  const std::wstring prefix = group + L"|";
  std::vector<std::wstring> keys;
  for (const auto& entry : g_active) {
    if (entry.first.rfind(prefix, 0) == 0) keys.push_back(entry.first);
  }
  for (const auto& key : keys) HideActive(key);
  try {
    ToastNotificationManager::History().RemoveGroup(
        winrt::hstring(group), winrt::hstring(ToastAumid()));
  } catch (...) {
  }
}

void HandleCall(const flutter::MethodCall<EncodableValue>& call,
                std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();
  const auto* args = std::get_if<EncodableMap>(call.arguments());

  if (method == "ping") {
    result->Success(EncodableValue(true));
    return;
  }
  if (method == "setting") {
    try {
      const auto notifier = ToastNotificationManager::CreateToastNotifier(
          winrt::hstring(ToastAumid()));
      std::string name = "unknown";
      switch (notifier.Setting()) {
        case NotificationSetting::Enabled:
          name = "enabled";
          break;
        case NotificationSetting::DisabledForApplication:
          name = "disabledForApplication";
          break;
        case NotificationSetting::DisabledForUser:
          name = "disabledForUser";
          break;
        case NotificationSetting::DisabledByGroupPolicy:
          name = "disabledByGroupPolicy";
          break;
        case NotificationSetting::DisabledByManifest:
          name = "disabledByManifest";
          break;
        default:
          break;
      }
      result->Success(EncodableValue(name));
    } catch (...) {
      result->Success(EncodableValue("error"));
    }
    return;
  }
  if (method == "history") {
    try {
      const auto history = ToastNotificationManager::History().GetHistory(
          winrt::hstring(ToastAumid()));
      EncodableList tags;
      for (const auto& toast : history) {
        EncodableMap item;
        item[EncodableValue("tag")] = EncodableValue(winrt::to_string(toast.Tag()));
        item[EncodableValue("group")] = EncodableValue(winrt::to_string(toast.Group()));
        tags.emplace_back(std::move(item));
      }
      result->Success(EncodableValue(tags));
    } catch (...) {
      result->Success(EncodableValue(EncodableList{}));
    }
    return;
  }
  if (method == "stats") {
    EncodableMap stats;
    stats[EncodableValue("show")] =
        EncodableValue(static_cast<int64_t>(g_show_count));
    stats[EncodableValue("update")] =
        EncodableValue(static_cast<int64_t>(g_update_count));
    result->Success(EncodableValue(stats));
    return;
  }
  if (method == "show") {
    if (args == nullptr) {
      result->Success(EncodableValue(false));
      return;
    }
    if (!tray_toast::EnsureShortcut()) {
      OutputDebugStringW(L"[dsh_toast] start menu shortcut unavailable\n");
    }
    result->Success(EncodableValue(ShowToast(*args)));
    return;
  }
  if (method == "cancel") {
    if (args != nullptr) {
      CancelOne(Utf8ToWide(GetString(*args, "tag", "dsh")),
                Utf8ToWide(GetString(*args, "group", "dsh")));
    }
    result->Success(EncodableValue(true));
    return;
  }
  if (method == "cancelGroup") {
    if (args != nullptr) {
      CancelGroup(Utf8ToWide(GetString(*args, "group", "dsh")));
    }
    result->Success(EncodableValue(true));
    return;
  }
  result->NotImplemented();
}

}  // namespace

void RegisterChannel(flutter::BinaryMessenger* messenger, HWND owner) {
  // owner 是 Flutter 子窗口；事件要 Post 给顶层窗口，才能进
  // FlutterWindow::MessageHandler。
  g_owner = owner == nullptr ? nullptr : ::GetAncestor(owner, GA_ROOT);
  g_channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler(HandleCall);
}

bool HandleWindowMessage(HWND hwnd,
                         UINT message,
                         WPARAM wparam,
                         LPARAM lparam,
                         LRESULT* result) {
  if (message != kToastEventMessage) return false;
  UNREFERENCED_PARAMETER(hwnd);
  UNREFERENCED_PARAMETER(wparam);
  auto* event = reinterpret_cast<PostedEvent*>(lparam);
  if (event != nullptr) {
    if (g_channel) {
      g_channel->InvokeMethod(
          "onEvent",
          std::make_unique<EncodableValue>(std::move(event->value)));
    }
    delete event;
  }
  if (result != nullptr) *result = 0;
  return true;
}

}  // namespace dsh_toast
