// lib/services/nav_bus.dart
//
// 跨层导航请求总线：平台通道（安卓 Shortcut）→ 主壳的切 tab 指令。
//
// 用「自增序号 + 目标 tab」的记录当值：ValueNotifier 只在值变化时通知，
// 若只存目标 index，「点 Shortcut 去发现页 → 切回仪表盘 → 再点 Shortcut」
// 第二次的值与上次相同就不会通知，快捷方式直接失灵。seq 每次自增保证必通知。
import 'package:flutter/foundation.dart';

class NavBus {
  NavBus._();

  static int _seq = 0;

  /// 切 tab 请求：(seq 递增序号, index 目标 tab)。
  static final ValueNotifier<({int seq, int index})> tabRequest = ValueNotifier(
    (seq: 0, index: -1),
  );

  /// 请求切到第 [index] 个 tab（0 仪表盘 / 1 发现 / 2 设置）。
  static void requestTab(int index) {
    tabRequest.value = (seq: ++_seq, index: index);
  }
}
