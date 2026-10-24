#include "native_edit_menu.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>
#include <vector>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodChannel;
using flutter::MethodResult;

constexpr char kChannelName[] = "local2api/text_edit_menu";

// 通道对象要保持存活，注册一次、随进程结束。
std::unique_ptr<MethodChannel<EncodableValue>> g_channel;

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  int size = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(),
                                 static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring wide(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()),
                      wide.data(), size);
  return wide;
}

const EncodableValue* ValueOrNull(const EncodableMap* map, const char* key) {
  auto it = map->find(EncodableValue(key));
  return it == map->end() ? nullptr : &it->second;
}

bool GetBool(const EncodableMap* map, const char* key) {
  const auto* v = ValueOrNull(map, key);
  return v != nullptr && std::holds_alternative<bool>(*v) &&
         std::get<bool>(*v);
}

std::string GetString(const EncodableMap* map, const char* key) {
  const auto* v = ValueOrNull(map, key);
  if (v == nullptr || !std::holds_alternative<std::string>(*v)) {
    return std::string();
  }
  return std::get<std::string>(*v);
}

double GetDouble(const EncodableMap* map, const char* key) {
  const auto* v = ValueOrNull(map, key);
  if (v == nullptr) {
    return 0.0;
  }
  if (const auto* d = std::get_if<double>(v)) {
    return *d;
  }
  if (const auto* i = std::get_if<int32_t>(v)) {
    return static_cast<double>(*i);
  }
  if (const auto* l = std::get_if<int64_t>(v)) {
    return static_cast<double>(*l);
  }
  return 0.0;
}

// 菜单项 id = 在 Dart 传来的 items 数组里的序号 + 1（0 保留给"未选择"）。
const char* ActionOf(UINT id, const std::vector<std::string>& actions) {
  if (id == 0 || id > actions.size()) {
    return nullptr;
  }
  return actions[id - 1].c_str();
}

void ShowEditMenu(const EncodableMap* args, HWND menu_host,
                  std::unique_ptr<MethodResult<EncodableValue>> result) {
  // Dart 传来的是 Flutter 全局坐标（逻辑像素，原点=视图客户区左上角）；
  // 按 DPI 换算成物理客户区坐标，再映射到屏幕。
  const double x = GetDouble(args, "x");
  const double y = GetDouble(args, "y");
  const UINT dpi = GetDpiForWindow(menu_host);
  POINT pt = {static_cast<LONG>(x * dpi / 96.0),
              static_cast<LONG>(y * dpi / 96.0)};
  ClientToScreen(menu_host, &pt);

  // items: [{action, label, enabled}, ...]；标签由 Dart 侧按应用语言传
  // （l10n 已就绪），原生端只管画。
  std::vector<std::string> actions;
  HMENU menu = CreatePopupMenu();
  if (menu != nullptr) {
    const EncodableValue* items_value = ValueOrNull(args, "items");
    if (items_value != nullptr) {
      if (const auto* items = std::get_if<EncodableList>(items_value)) {
        for (const auto& item_value : *items) {
          const auto* item = std::get_if<EncodableMap>(&item_value);
          if (item == nullptr) {
            continue;
          }
          const std::string action = GetString(item, "action");
          if (action.empty()) {
            AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
            continue;
          }
          actions.push_back(action);
          const std::wstring label =
              Utf8ToWide(GetString(item, "label"));
          const UINT flags =
              MF_STRING | (GetBool(item, "enabled") ? MF_ENABLED : MF_GRAYED);
          AppendMenuW(menu, flags,
                      static_cast<UINT_PTR>(actions.size()), label.c_str());
        }
      }
    }

    SetForegroundWindow(menu_host);
    const UINT cmd = TrackPopupMenuEx(
        menu,
        TPM_LEFTALIGN | TPM_TOPALIGN | TPM_RIGHTBUTTON | TPM_RETURNCMD |
            TPM_NONOTIFY,
        pt.x, pt.y, menu_host, nullptr);
    // TrackPopupMenu 经典补位：否则菜单关闭后窗口收不到一次 WM_ACTIVATE。
    PostMessage(menu_host, WM_NULL, 0, 0);
    DestroyMenu(menu);

    const char* action = ActionOf(cmd, actions);
    if (action != nullptr) {
      result->Success(EncodableValue(action));
      return;
    }
  }
  // 未选择（点外面 / Esc）或菜单创建失败 → null。
  result->Success();
}

}  // namespace

namespace native_edit_menu {

void RegisterTextEditMenuChannel(flutter::FlutterViewController* controller,
                                 HWND menu_host) {
  g_channel = std::make_unique<MethodChannel<EncodableValue>>(
      controller->engine()->messenger(), kChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler(
      [menu_host](const MethodCall<EncodableValue>& call,
                  std::unique_ptr<MethodResult<EncodableValue>> result) {
        if (call.method_name().compare("show") != 0) {
          result->NotImplemented();
          return;
        }
        const auto* args = std::get_if<EncodableMap>(call.arguments());
        if (args == nullptr) {
          result->Error("bad_args", "show requires a map of arguments");
          return;
        }
        ShowEditMenu(args, menu_host, std::move(result));
      });
}

}  // namespace native_edit_menu
