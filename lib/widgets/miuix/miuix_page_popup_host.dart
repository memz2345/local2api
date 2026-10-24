import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

/// 给「不是 `MiuixScaffold` 的 miuix 页面」补一套弹层宿主。
///
/// 为什么需要：flutter_miuix 的下拉菜单/弹窗默认渲染进**根 popup 注册表**
/// （`MiuixOverlayDropdownPreference` → `renderInRootScaffold: true` →
/// `MiuixPopupScope.of(context, root: true)`），而根注册表是 `MiuixScaffold`
/// 建立的。项目的 miuix 二级页大多已经换成 `MiuixScaffold`（自带
/// `MiuixPopupHost`）；少数仍是别的外壳、没有 `MiuixScaffold` 的页面，
/// 拿到的是**进程级 fallback 注册表**，
/// 而那个注册表没有任何宿主去渲染它 —— 表现为「菜单点下去毫无反应」。
///
/// 用法：把页面 body 包一层，本页就自成 root，菜单画在本页的宿主里。
/// 已经用 `MiuixScaffold` 的页面不需要包（那是重复建 root）。
class MiuixPagePopupHost extends StatelessWidget {
  const MiuixPagePopupHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MiuixPopupScope(
      // 本页自成 root：菜单渲染进下面这个宿主，而不是全进程的 fallback
      establishRoot: true,
      // MiuixPopupHost 自带 Stack(fit: expand) 与返回键接管，直接当容器用
      child: MiuixPopupHost(child: child),
    );
  }
}
