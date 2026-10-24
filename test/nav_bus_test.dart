import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/nav_bus.dart';

/// NavBus：平台通道（安卓 Shortcut）→ 主壳切 tab 的请求总线。
///
/// 核心语义在「同一个 tab 连点两次也必须触发」：值用 (seq, index) 记录，
/// 只存 index 时重复请求不通知，快捷方式第二次点就失灵。
void main() {
  test('首次请求带目标 tab，且从 -1（无请求）起步', () {
    expect(NavBus.tabRequest.value.index, -1);
    NavBus.requestTab(1);
    expect(NavBus.tabRequest.value.index, 1);
  });

  test('重复请求同一个 tab 也会通知（seq 递增）', () {
    var notified = 0;
    void listener() => notified++;
    NavBus.tabRequest.addListener(listener);
    addTearDown(() => NavBus.tabRequest.removeListener(listener));

    NavBus.requestTab(1);
    expect(notified, 1);
    // 中间切走，再点同一个 tab：值里的 index 没变，但 seq 变了 → 仍通知
    NavBus.requestTab(0);
    NavBus.requestTab(1);
    expect(notified, 3);
    expect(NavBus.tabRequest.value.index, 1);
  });
}
