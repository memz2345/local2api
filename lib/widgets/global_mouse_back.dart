// lib/widgets/global_mouse_back.dart
//
// 全局鼠标/键盘操作（自 NaviFlash GlobalMouseBackWrapper 移植）：
//   - 鼠标侧键（后退键，buttons & 8）→ 根 Navigator 回退一次；
//   - ESC 键 → 同样回退一次。
// 语义与系统返回一致：对话框/菜单等顶层路由优先关闭；在根页面无事发生。
// 不吞事件（返回 false / translucent Listener），与其它监听保持非独占语义。
//
// 挂在 MaterialApp.builder 里包住 Navigator，鼠标事件用 translucent
// Listener 才能在手势竞技场之外收到（不影响页面自身手势）。
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class GlobalMouseBackWrapper extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const GlobalMouseBackWrapper({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  @override
  State<GlobalMouseBackWrapper> createState() => _GlobalMouseBackWrapperState();
}

class _GlobalMouseBackWrapperState extends State<GlobalMouseBackWrapper> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  /// ESC 与鼠标侧键行为一致：全局路由回退一次。
  /// 不吞事件（返回 false），与侧键监听保持同样非独占语义。
  bool _handleKeyEvent(KeyEvent event) {
    // KeyDownEvent 仅按下瞬间触发一次（长按重复是 KeyRepeatEvent，
    // 不会进这里），语义与侧键单击一致。
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      widget.navigatorKey.currentState?.maybePop();
    }
    return false;
  }

  void _handlePointerEvent(PointerEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      if (event is PointerDownEvent) {
        // buttons & 8 = 鼠标后退侧键（kBackMouseButton）
        if (event.buttons & 8 != 0) {
          widget.navigatorKey.currentState?.maybePop();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerEvent,
      onPointerUp: _handlePointerEvent,
      child: widget.child,
    );
  }
}
