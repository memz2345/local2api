#ifndef RUNNER_NATIVE_EDIT_MENU_H_
#define RUNNER_NATIVE_EDIT_MENU_H_

// flutter 头文件要在 windows.h 之前引入（与 flutter_window.h 同序，
// windows.h 的宏会打断 C++ client wrapper 的声明解析）。
#include <flutter/flutter_view_controller.h>

#include <windows.h>

namespace native_edit_menu {

// 注册 "local2api/text_edit_menu" 平台通道：Dart 侧右键文本框时调用 show
// 方法，这里用 Win32 TrackPopupMenu 弹原生编辑菜单（撤消/剪切/复制/粘贴/
// 删除/全选），点击项以字符串回传（undo/cut/copy/paste/delete/selectAll），
// 取消返回 null。文本编辑逻辑全部在 Dart 侧执行。
//
// [menu_host] 用 Flutter 视图的 HWND：坐标换算（Dart 全局逻辑坐标 → 屏幕
// 物理坐标）与菜单归属窗口都是它。
void RegisterTextEditMenuChannel(flutter::FlutterViewController* controller,
                                 HWND menu_host);

}  // namespace native_edit_menu

#endif  // RUNNER_NATIVE_EDIT_MENU_H_
