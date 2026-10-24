import 'package:flutter/material.dart';

/// NaviFlash 原生菜单的数据类（保留原签名）。
///
/// 本项目未移植 NativeMenuHost.kt（原生弹出菜单），服务桩直接返回
/// false，调用方（morph 组件/设置屏）会走各自的 Flutter 弹层回退路径。
class NativeMenuItem {
  final String text;

  final String? subtitle;

  final IconData? icon;

  final bool checked;

  final bool destructive;

  final bool enabled;

  final bool closeAfter;

  final VoidCallback onTap;

  const NativeMenuItem({
    required this.text,
    required this.onTap,
    this.subtitle,
    this.icon,
    this.checked = false,
    this.destructive = false,
    this.enabled = true,
    this.closeAfter = true,
  });
}

/// 原生菜单服务桩：永远返回 false（不可用）。
class NativeMenuService {
  NativeMenuService._();

  static bool enabled = false;

  static Future<bool> showMenu(
    BuildContext context, {
    required List<NativeMenuItem> items,
    required Offset position,
    double width = 220,
  }) {
    return Future.value(false);
  }

  static Future<bool> showMoreSheet(
    BuildContext context, {
    required String title,
    required List<NativeMenuItem> items,
    List<NativeMenuItem> Function()? refreshProvider,
  }) {
    return Future.value(false);
  }
}
