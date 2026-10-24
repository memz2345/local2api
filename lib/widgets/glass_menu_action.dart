import 'package:flutter/material.dart';

import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:local2api/services/native_menu_service.dart';

/// 玻璃菜单动作项（NaviFlash search_video_menu 中的通用部分提取）。
class GlassMenuAction {
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  final Widget? trailing;

  final bool isDestructive;

  final bool isEnabled;

  const GlassMenuAction({
    required this.icon,
    required this.text,
    required this.onTap,
    this.trailing,
    this.isDestructive = false,
    this.isEnabled = true,
  });
}

/// 把动作列表映射为原生菜单项；带非 Icon trailing 时返回 null
/// （表示无法用原生菜单表达，调用方回退 Flutter 弹层）。
List<NativeMenuItem>? nativeItemsOfActions(List<GlassMenuAction> actions) {
  final items = <NativeMenuItem>[];
  for (final action in actions) {
    var checked = false;
    final trailing = action.trailing;
    if (trailing != null) {
      if (trailing is Icon) {
        checked = trailing.icon == Icons.check;
      } else {
        return null;
      }
    }
    items.add(
      NativeMenuItem(
        text: action.text,
        icon: action.icon,
        checked: checked,
        destructive: action.isDestructive,
        enabled: action.isEnabled,
        onTap: action.onTap,
      ),
    );
  }
  return items;
}

/// 尝试用原生菜单展示动作列表（本项目未移植原生菜单宿主，
/// NativeMenuService 桩恒返回 false，走调用方的 Flutter 回退）。
Future<bool> tryShowNativeGlassMenu(
  BuildContext context, {
  required List<GlassMenuAction> actions,
  required Offset globalPosition,
  double menuWidth = 220,
}) async {
  if (actions.isEmpty) return false;
  final items = nativeItemsOfActions(actions);
  if (items == null) return false;
  return NativeMenuService.showMenu(
    context,
    items: items,
    position: globalPosition,
    width: menuWidth,
  );
}

/// 构建单个玻璃菜单项。
GlassMenuItem buildGlassMenuItem(
  GlassMenuAction action,
  Brightness brightness, {
  VoidCallback? onTap,
}) {
  final foreground = brightness == Brightness.dark
      ? const Color(0xFFE6E6E6)
      : const Color(0xFF1A1A1A);
  return GlassMenuItem(
    title: action.text,
    icon: Icon(action.icon),
    isDestructive: action.isDestructive,
    enabled: action.isEnabled,
    trailing: action.trailing,
    height: 44.0,
    iconSize: 18.0,
    titleStyle: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: action.isDestructive ? null : foreground,
    ),
    onTap: onTap ?? action.onTap,
  );
}
