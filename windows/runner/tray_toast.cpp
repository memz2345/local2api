// windows/runner/tray_toast.cpp
//
// 实现见 tray_toast.h 的模块说明。这里的重点是三件事：
//   1. 首次弹之前把带 AUMID 的 Start Menu 快捷方式补上（非打包进程弹 Toast
//      的前提，缺了会抛 0x80070490）；
//   2. 拼 ToastGeneric XML，带两个 foreground 按钮，arguments 直接写成
//      `--l2a-action=…`（由 main.cpp 的单实例转发交给 Dart）；
//   3. 失败一律返回 false，绝不把异常抛回 Flutter。

#include "tray_toast.h"

#include "jumplist.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <shlobj.h>
#include <shobjidl.h>
#include <propkey.h>
#include <propvarutil.h>
#include <windows.h>

// C++/WinRT 投影（必须在 windows.h 之后包含）
#include <winrt/Windows.Data.Xml.Dom.h>
#include <winrt/Windows.UI.Notifications.h>

#include <string>

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "propsys.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "windowsapp.lib")

namespace tray_toast {
namespace {

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return std::wstring();
  const int len = ::MultiByteToWideChar(CP_UTF8, 0, s.c_str(),
                                        static_cast<int>(s.size()), nullptr, 0);
  if (len <= 0) return std::wstring();
  std::wstring out(static_cast<size_t>(len), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()),
                        out.data(), len);
  return out;
}

std::wstring EscapeXml(const std::wstring& s) {
  std::wstring out;
  out.reserve(s.size());
  for (const wchar_t c : s) {
    switch (c) {
      case L'&': out += L"&amp;"; break;
      case L'<': out += L"&lt;"; break;
      case L'>': out += L"&gt;"; break;
      case L'"': out += L"&quot;"; break;
      case L'\'': out += L"&apos;"; break;
      default: out += c; break;
    }
  }
  return out;
}

/// 非打包桌面进程想弹 Toast，Start Menu 里必须有一份 AppID = AUMID 的
/// 快捷方式，否则 ToastNotificationManager 抛 ELEMENT_NOT_FOUND。
/// 已经存在就跳过（用户手动改过指向也不覆盖）。
bool EnsureStartMenuShortcut() {
  PWSTR programs = nullptr;
  if (FAILED(::SHGetKnownFolderPath(FOLDERID_Programs, KF_FLAG_DEFAULT,
                                    nullptr, &programs)) ||
      programs == nullptr) {
    return false;
  }
  std::wstring lnk_path = std::wstring(programs) + L"\\Local2API.lnk";
  ::CoTaskMemFree(programs);

  if (::GetFileAttributesW(lnk_path.c_str()) != INVALID_FILE_ATTRIBUTES) {
    return true;
  }

  wchar_t exe_path[MAX_PATH] = {};
  if (::GetModuleFileNameW(nullptr, exe_path, MAX_PATH) == 0) return false;

  IShellLinkW* link = nullptr;
  if (FAILED(::CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&link)))) {
    return false;
  }
  link->SetPath(exe_path);
  link->SetArguments(L"");
  link->SetDescription(L"Local2API");
  link->SetIconLocation(exe_path, 0);

  IPropertyStore* store = nullptr;
  if (SUCCEEDED(link->QueryInterface(IID_PPV_ARGS(&store)))) {
    PROPVARIANT pv;
    ::InitPropVariantFromString(jumplist::kAppUserModelID, &pv);
    store->SetValue(PKEY_AppUserModel_ID, pv);
    store->Commit();
    ::PropVariantClear(&pv);
    store->Release();
  }

  IPersistFile* file = nullptr;
  bool saved = false;
  if (SUCCEEDED(link->QueryInterface(IID_PPV_ARGS(&file)))) {
    saved = SUCCEEDED(file->Save(lnk_path.c_str(), TRUE));
    file->Release();
  }
  link->Release();
  return saved;
}

/// Toast 的 AUMID 取进程显式值（main.cpp 已设），取不到兜底同名。
std::wstring ToastAumid() {
  PWSTR raw = nullptr;
  if (SUCCEEDED(::GetCurrentProcessExplicitAppUserModelID(&raw)) && raw) {
    std::wstring id(raw);
    ::CoTaskMemFree(raw);
    if (!id.empty()) return id;
  }
  return jumplist::kAppUserModelID;
}

bool ShowToast(const std::wstring& title, const std::wstring& body,
               const std::wstring& dismiss_label,
               const std::wstring& dismiss_args,
               const std::wstring& settings_label,
               const std::wstring& settings_args) {
  try {
    using namespace winrt::Windows::Data::Xml::Dom;
    using namespace winrt::Windows::UI::Notifications;

    // 点 Toast 正文 = 打开设置（跟「设置」按钮同一个动作）。
    std::wstring xml =
        L"<toast activationType=\"foreground\" launch=\"" +
        EscapeXml(settings_args) + L"\">"
        L"<visual><binding template=\"ToastGeneric\">"
        L"<text>" + EscapeXml(title) + L"</text>"
        L"<text>" + EscapeXml(body) + L"</text>"
        L"</binding></visual><actions>"
        L"<action content=\"" + EscapeXml(dismiss_label) +
        L"\" activationType=\"foreground\" arguments=\"" +
        EscapeXml(dismiss_args) + L"\"/>"
        L"<action content=\"" + EscapeXml(settings_label) +
        L"\" activationType=\"foreground\" arguments=\"" +
        EscapeXml(settings_args) + L"\"/>"
        L"</actions></toast>";

    XmlDocument doc;
    doc.LoadXml(xml);
    ToastNotification toast(doc);
    ToastNotificationManager::CreateToastNotifier(
        winrt::hstring(ToastAumid()))
        .Show(toast);
    return true;
  } catch (const winrt::hresult_error& e) {
    OutputDebugStringW(
        (std::wstring(L"[tray_toast] show failed: ") + e.message().c_str() +
         L"\n")
            .c_str());
    return false;
  } catch (...) {
    return false;
  }
}

void HandleCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                    result) {
  if (call.method_name() != "show") {
    result->NotImplemented();
    return;
  }
  std::string title = "Local2API";
  std::string body;
  std::string dismiss_label = "Don't show again";
  std::string dismiss_args = "--l2a-action=tray_hint_off";
  std::string settings_label = "Settings";
  std::string settings_args = "--l2a-action=tray_hint_settings";

  if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
    auto read = [args](const char* key, std::string& out) {
      const auto it = args->find(flutter::EncodableValue(key));
      if (it == args->end()) return;
      if (const auto* v = std::get_if<std::string>(&it->second)) out = *v;
    };
    read("title", title);
    read("body", body);
    read("dismissLabel", dismiss_label);
    read("dismissArgs", dismiss_args);
    read("settingsLabel", settings_label);
    read("settingsArgs", settings_args);
  }

  if (!EnsureStartMenuShortcut()) {
    OutputDebugStringW(L"[tray_toast] start menu shortcut unavailable\n");
  }
  const bool shown =
      ShowToast(Utf8ToWide(title), Utf8ToWide(body), Utf8ToWide(dismiss_label),
                Utf8ToWide(dismiss_args), Utf8ToWide(settings_label),
                Utf8ToWide(settings_args));
  result->Success(flutter::EncodableValue(shown));
}

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel;

}  // namespace

bool EnsureShortcut() { return EnsureStartMenuShortcut(); }

void RegisterChannel(flutter::BinaryMessenger* messenger, HWND owner) {
  UNREFERENCED_PARAMETER(owner);
  g_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "com.memz2345.local2api/tray_toast",
      &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler(HandleCall);
}

}  // namespace tray_toast
