// windows/runner/jumplist.cpp
//
// 见同目录 .h 的说明。实现照 NaviFlash 的 BuildFlashShellLink /
// BuildFlashJumpList 路子，改动点：
//   · 任务项与「最近」项都改成 Dart 下发（NaviFlash 的任务三项是 C++ 写死的）；
//   · 动作参数前缀换 --l2a-action；
//   · WM_COPYDATA 载荷标记换 'L2A1'，只带一个动作串（本项目不需要
//     「打开方式」传文件路径那一套多参数分隔载荷）。
#include "jumplist.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <objbase.h>
#include <propsys.h>
#include <propkey.h>
#include <propvarutil.h>
#include <shobjidl.h>
#include <shellapi.h>
#include <shlobj.h>
#include <string>
#include <vector>

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "propsys.lib")

namespace jumplist {

const wchar_t* kAppUserModelID = L"com.memz2345.local2api";
const char* kActionArgPrefix = "--l2a-action=";

namespace {

/// 命令行前缀的宽字符版：快捷方式的参数是 wchar_t，命令行解析走 UTF-8，
/// 两个形态都指向同一个字面量，别各写一份字符串。
const wchar_t* kActionArgPrefixW = L"--l2a-action=";

const char* kChannelName = "com.memz2345.local2api/jumplist";

/// 「最近」区最多几条（NaviFlash 同款：5 条，再多任务栏菜单放不下）。
constexpr int kMaxRecentItems = 5;

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return {};
  int len = ::MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
  if (len <= 0) return {};
  std::wstring ws(len - 1, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, &ws[0], len);
  return ws;
}

std::string WideToUtf8(const wchar_t* w) {
  if (!w || !w[0]) return {};
  int len = ::WideCharToMultiByte(CP_UTF8, 0, w, -1, nullptr, 0, nullptr,
                                  nullptr);
  if (len <= 0) return {};
  std::string s(len - 1, '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, w, -1, &s[0], len, nullptr, nullptr);
  return s;
}

std::string g_pending_action;

flutter::BinaryMessenger* g_messenger = nullptr;
HWND g_owner = nullptr;
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel;

std::string Str(const flutter::EncodableMap* map, const char* key) {
  if (!map) return {};
  auto it = map->find(flutter::EncodableValue(key));
  if (it == map->end()) return {};
  if (const auto* s = std::get_if<std::string>(&it->second)) return *s;
  return {};
}

/// 一条跳转列表项 = 指向本 exe 的快捷方式，带 --l2a-action=<action>。
IShellLinkW* MakeShellLink(const std::wstring& exe_path,
                           const std::string& action,
                           const std::wstring& title,
                           const std::wstring& subtitle) {
  IShellLinkW* link = nullptr;
  if (FAILED(::CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                IID_IShellLinkW,
                                reinterpret_cast<void**>(&link))) ||
      !link) {
    return nullptr;
  }
  link->SetPath(exe_path.c_str());

  // 工作目录 = exe 所在目录：Flutter 桌面端要能从那里找到 data/ 资源。
  std::wstring exe_dir(exe_path);
  size_t slash = exe_dir.find_last_of(L"\\/");
  if (slash != std::wstring::npos) exe_dir = exe_dir.substr(0, slash);
  link->SetWorkingDirectory(exe_dir.c_str());

  link->SetArguments(
      (std::wstring(kActionArgPrefixW) + Utf8ToWide(action)).c_str());
  link->SetDescription(subtitle.empty() ? title.c_str() : subtitle.c_str());

  // PKEY_Title 决定菜单里显示的文字（SetDescription 只当副标题用）；
  // PKEY_AppUserModel_ID 必须与列表的 AppID 一致，否则该项不显示。
  IPropertyStore* props = nullptr;
  if (SUCCEEDED(link->QueryInterface(IID_IPropertyStore,
                                     reinterpret_cast<void**>(&props))) &&
      props) {
    PROPVARIANT pv_title;
    ::InitPropVariantFromString(title.c_str(), &pv_title);
    props->SetValue(PKEY_Title, pv_title);
    ::PropVariantClear(&pv_title);

    PROPVARIANT pv_aumid;
    ::InitPropVariantFromString(kAppUserModelID, &pv_aumid);
    props->SetValue(PKEY_AppUserModel_ID, pv_aumid);
    ::PropVariantClear(&pv_aumid);

    props->Commit();
    props->Release();
  }
  return link;
}

/// 用户在菜单里手动删过的项（按启动参数匹配）：这次重建列表时跳过，
/// 否则删掉的条目会被我们反复塞回去（Windows 的约定做法）。
std::vector<std::wstring> CollectRemovedArgs(IUnknown* removed) {
  std::vector<std::wstring> out;
  IObjectArray* arr = nullptr;
  if (FAILED(removed->QueryInterface(IID_IObjectArray,
                                     reinterpret_cast<void**>(&arr))) ||
      !arr) {
    return out;
  }
  UINT count = 0;
  arr->GetCount(&count);
  for (UINT i = 0; i < count; i++) {
    IUnknown* unk = nullptr;
    if (SUCCEEDED(arr->GetAt(i, IID_IUnknown,
                            reinterpret_cast<void**>(&unk))) &&
        unk) {
      IShellLinkW* link = nullptr;
      if (SUCCEEDED(unk->QueryInterface(IID_IShellLinkW,
                                        reinterpret_cast<void**>(&link))) &&
          link) {
        wchar_t buf[MAX_PATH] = {};
        link->GetArguments(buf, MAX_PATH);
        if (buf[0]) out.push_back(buf);
        link->Release();
      }
      unk->Release();
    }
  }
  arr->Release();
  return out;
}

bool Build(const flutter::EncodableMap& payload) {
  // 线程内可能已由 Flutter 引擎初始化过 COM；再次调用返回 S_FALSE，
  // 这时不能在本函数末尾 CoUninitialize，否则会关掉外层的初始化。
  HRESULT hr_com = ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  bool need_uninit = SUCCEEDED(hr_com);

  wchar_t exe_path[MAX_PATH] = {};
  ::GetModuleFileNameW(nullptr, exe_path, MAX_PATH);

  ICustomDestinationList* dest = nullptr;
  HRESULT hr =
      ::CoCreateInstance(CLSID_DestinationList, nullptr, CLSCTX_INPROC_SERVER,
                         IID_ICustomDestinationList,
                         reinterpret_cast<void**>(&dest));
  if (FAILED(hr) || !dest) {
    if (need_uninit) ::CoUninitialize();
    return false;
  }
  dest->SetAppID(kAppUserModelID);

  UINT min_slots = 0;
  IObjectArray* removed = nullptr;
  hr = dest->BeginList(&min_slots, IID_IObjectArray,
                       reinterpret_cast<void**>(&removed));
  if (FAILED(hr)) {
    dest->Release();
    if (need_uninit) ::CoUninitialize();
    return false;
  }
  std::vector<std::wstring> removed_args;
  if (removed) {
    removed_args = CollectRemovedArgs(removed);
    removed->Release();
  }

  auto add_links = [&](const flutter::EncodableValue* value,
                       const std::wstring& category, int limit,
                       bool as_tasks) -> bool {
    const auto* list =
        value ? std::get_if<flutter::EncodableList>(value) : nullptr;
    if (!list || list->empty()) return false;

    IObjectCollection* col = nullptr;
    if (FAILED(::CoCreateInstance(CLSID_EnumerableObjectCollection, nullptr,
                                  CLSCTX_INPROC_SERVER, IID_IObjectCollection,
                                  reinterpret_cast<void**>(&col))) ||
        !col) {
      return false;
    }
    int added = 0;
    for (const auto& item : *list) {
      if (added >= limit) break;
      const auto* map = std::get_if<flutter::EncodableMap>(&item);
      std::string action = Str(map, "action");
      std::string name = Str(map, "name");
      if (action.empty()) continue;
      if (name.empty()) name = action;

      std::wstring expected =
          std::wstring(kActionArgPrefixW) + Utf8ToWide(action);
      bool was_removed = false;
      for (const auto& ra : removed_args) {
        if (ra == expected) {
          was_removed = true;
          break;
        }
      }
      if (was_removed) continue;

      IShellLinkW* link =
          MakeShellLink(exe_path, action, Utf8ToWide(name),
                        Utf8ToWide(Str(map, "subtitle")));
      if (!link) continue;
      col->AddObject(link);
      link->Release();
      added++;
    }
    bool ok = added > 0;
    if (ok) {
      // 任务区走 AddUserTasks（Windows 自己画「任务 / Tasks」小标题），
      // 「最近」区是自定义类别，标题由 Dart 下发。
      HRESULT h = as_tasks ? dest->AddUserTasks(col)
                           : dest->AppendCategory(category.c_str(), col);
      ok = SUCCEEDED(h);
    }
    col->Release();
    return ok;
  };

  auto find = [&](const char* key) -> const flutter::EncodableValue* {
    auto it = payload.find(flutter::EncodableValue(key));
    return it == payload.end() ? nullptr : &it->second;
  };

  // 顺序：先「最近」类别，再「任务」区 —— 与 NaviFlash 一致，Windows 会把
  // 用户任务画在列表顶部。
  add_links(find("recents"), Utf8ToWide(Str(&payload, "recentTitle")),
            kMaxRecentItems, false);
  add_links(find("tasks"), L"", 10, true);

  hr = dest->CommitList();
  bool success = SUCCEEDED(hr);
  if (!success) dest->AbortList();

  dest->Release();
  if (need_uninit) ::CoUninitialize();
  return success;
}

}  // namespace

std::string ParseActionArg(const std::vector<std::string>& args) {
  const std::string prefix(kActionArgPrefix);
  for (const auto& arg : args) {
    if (arg.rfind(prefix, 0) == 0 && arg.size() > prefix.size()) {
      return arg.substr(prefix.size());
    }
  }
  return {};
}

void SetPendingAction(const std::string& action) {
  if (!action.empty()) g_pending_action = action;
}

std::string TakePendingAction() {
  std::string out;
  out.swap(g_pending_action);
  return out;
}

void RegisterChannel(flutter::BinaryMessenger* messenger, HWND owner) {
  g_messenger = messenger;
  g_owner = owner;
  g_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        const std::string& method = call.method_name();
        if (method == "setJumpList") {
          const auto* map =
              std::get_if<flutter::EncodableMap>(call.arguments());
          bool ok = map ? Build(*map) : false;
          result->Success(flutter::EncodableValue(ok));
        } else if (method == "clearJumpList") {
          ICustomDestinationList* dest = nullptr;
          HRESULT hr = ::CoCreateInstance(
              CLSID_DestinationList, nullptr, CLSCTX_INPROC_SERVER,
              IID_ICustomDestinationList,
              reinterpret_cast<void**>(&dest));
          if (SUCCEEDED(hr) && dest) {
            dest->SetAppID(kAppUserModelID);
            dest->DeleteList(kAppUserModelID);
            dest->Release();
          }
          result->Success(flutter::EncodableValue(true));
        } else if (method == "consumeLaunchArgs") {
          // 冷启动（点跳转列表时没有实例在跑）：返回动作并清除，只消费一次。
          flutter::EncodableMap payload;
          payload[flutter::EncodableValue("action")] =
              flutter::EncodableValue(TakePendingAction());
          result->Success(flutter::EncodableValue(payload));
        } else {
          result->NotImplemented();
        }
      });
}

bool HandleCopyData(HWND hwnd, LPARAM lparam) {
  (void)hwnd;
  const COPYDATASTRUCT* cds =
      reinterpret_cast<const COPYDATASTRUCT*>(lparam);
  if (!cds || cds->dwData != kCopyDataMagic || !cds->lpData ||
      cds->cbData == 0) {
    return false;
  }
  std::string action(static_cast<const char*>(cds->lpData), cds->cbData);
  while (!action.empty() && action.back() == '\0') action.pop_back();
  if (action.empty() || !g_channel) return false;

  // 已有实例在跑：动作交给它（与冷启动共用同一套分发），本进程随后退出。
  g_pending_action = action;
  g_channel->InvokeMethod("onAction",
                          std::make_unique<flutter::EncodableValue>(action));
  return true;
}

}  // namespace jumplist
