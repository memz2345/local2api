// Windows 下的文本框「原生右键菜单」桥接。
//
// 右键 TextField 时不再弹 Flutter 自绘的 AdaptiveTextSelectionToolbar（黑底
// 两项那种），而是走平台通道让 Windows runner 用 Win32 TrackPopupMenu 弹
// 系统原生编辑菜单（撤消/剪切/复制/粘贴/删除/全选，置灰状态跟随选区），
// 菜单锚点（右键位置）从 Dart 传过去，选中的动作回传后用 Flutter 自己的
// 编辑命令执行 —— 文本逻辑全在 Dart，原生只负责画菜单。
//
// 非 Windows 平台原样回落默认菜单，桌面端注册入口见 windows/runner。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:local2api/l10n/app_localizations.dart';

/// 与 windows/runner/native_edit_menu.cpp 对应的通道。
const MethodChannel _channel = MethodChannel('local2api/text_edit_menu');

/// [TextField.contextMenuBuilder] / [TextFormField.contextMenuBuilder] 直接
/// 挂这个函数：Windows 弹原生菜单，其它平台走 Flutter 默认。
Widget textContextMenuBuilder(BuildContext context, EditableTextState state) {
  if (!Platform.isWindows) {
    return AdaptiveTextSelectionToolbar.editableText(editableTextState: state);
  }
  return _WindowsNativeEditMenu(context: context, state: state);
}

/// 一条原生菜单项的静态描述（标签 + 是否可用），渲染交给原生端。
class _NativeMenuItem {
  const _NativeMenuItem(this.action, this.label, {required this.enabled});

  /// 回传动作 id：undo / cut / copy / paste / delete / selectAll
  final String action;
  final String label;
  final bool enabled;
}

class _WindowsNativeEditMenu extends StatefulWidget {
  const _WindowsNativeEditMenu({required this.context, required this.state});

  /// contextMenuBuilder 收到的外层 context（挂菜单文案的 l10n 用）。
  final BuildContext context;
  final EditableTextState state;

  @override
  State<_WindowsNativeEditMenu> createState() => _WindowsNativeEditMenuState();
}

class _WindowsNativeEditMenuState extends State<_WindowsNativeEditMenu> {
  @override
  void initState() {
    super.initState();
    // 等这一帧布局完（锚点已就位）再弹原生菜单。
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  Future<void> _show() async {
    final state = widget.state;
    if (!mounted) return;
    final l10n = AppLocalizations.of(widget.context);
    final selection = state.textEditingValue.selection;
    final hasSelection = !selection.isCollapsed && selection.isValid;

    // 顺序对齐 Windows 记事本那条菜单：撤消 | 剪切/复制/粘贴/删除 | 全选。
    final items = [
      _NativeMenuItem(
        'undo',
        l10n.editMenuUndo,
        enabled: true, // Dart 侧没有公开的 undo 栈查询；无可撤销时原生命令是空操作
      ),
      _NativeMenuItem('cut', l10n.editMenuCut, enabled: state.cutEnabled),
      _NativeMenuItem('copy', l10n.editMenuCopy, enabled: state.copyEnabled),
      _NativeMenuItem('paste', l10n.editMenuPaste, enabled: state.pasteEnabled),
      _NativeMenuItem('delete', l10n.editMenuDelete, enabled: hasSelection),
      _NativeMenuItem(
        'selectAll',
        l10n.editMenuSelectAll,
        enabled: state.selectAllEnabled,
      ),
    ];

    // 右键位置：EditableTextState.contextMenuAnchors.primaryAnchor 取的正是
    // 最近一次 secondary tap 的全局（逻辑像素）坐标；无右键记录时回退选区锚点。
    final anchor = state.contextMenuAnchors.primaryAnchor;

    String? action;
    try {
      action = await _channel.invokeMethod<String>('show', <String, Object?>{
        'x': anchor.dx,
        'y': anchor.dy,
        'items': [
          for (final item in items)
            {
              'action': item.action,
              'label': item.label,
              'enabled': item.enabled,
            },
        ],
      });
    } on PlatformException {
      // runner 没注册通道（旧版 exe？）就静默退回，别崩。
      return;
    } on MissingPluginException {
      return;
    }
    if (!mounted || action == null) return;
    _applyAction(action);
  }

  void _applyAction(String action) {
    final state = widget.state;
    final items = state.contextMenuButtonItems;
    switch (action) {
      case 'undo':
        // 标准文本编辑意图：EditableText 内部挂了对应的 Action。
        Actions.invoke(
          state.context,
          const UndoTextIntent(SelectionChangedCause.longPress),
        );
      case 'delete':
        // contextMenuButtonItems 不含删除：手动把选区抠掉。
        final value = state.textEditingValue;
        final selection = value.selection;
        if (!selection.isCollapsed && selection.isValid) {
          state.updateEditingValue(value.replaced(selection, ''));
        }
      default:
        // cut / copy / paste / selectAll 走框架自己的按钮回调，行为与
        // AdaptiveTextSelectionToolbar 完全一致。
        for (final item in items) {
          if (item.type.name == action) {
            item.onPressed?.call();
            break;
          }
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 原生菜单在平台侧渲染，Flutter 这边不画东西；
    // 通道不可用时菜单区域保持空白（右键仍会更新选区，无碍使用）。
    return const SizedBox.shrink();
  }
}
