import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../app_toast.dart';

/// 把 [MiuixSnackbarHostState] 沿树暴露出去，让任意深度的 miuix 页面能弹提示。
///
/// flutter_miuix 的 README 里写着 `MiuixSnackbarHost.of(context)`，
/// 但源码里**没有**这个静态方法（`MiuixSnackbarHost` 只是个 StatelessWidget），
/// 所以这层查找只能自己搭：外壳把 state 同时喂给 host 和本 scope。
class MiuixToastScope extends InheritedWidget {
  const MiuixToastScope({super.key, required this.state, required super.child});

  final MiuixSnackbarHostState state;

  static MiuixSnackbarHostState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MiuixToastScope>()?.state;

  @override
  bool updateShouldNotify(MiuixToastScope oldWidget) =>
      oldWidget.state != state;
}

/// miuix 风格的提示：树上挂着 snackbar host 就走它（HyperOS 那张卡片），
/// 没有就退回全局 toast —— 子页面被 push 到壳外面时属于这种情况。
void showMiuixToast(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  final state = MiuixToastScope.maybeOf(context);
  if (state != null) {
    state.showSnackbar(message);
    return;
  }
  showAppToast(context, message, error: error);
}
