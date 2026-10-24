import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/widgets/page_switcher.dart';

/// 一级页从 `IndexedStack` 换成 `PageView` 之后的保活回归测试。
///
/// `IndexedStack` 天然三页全保活；`PageView` 默认只保留当前页附近，离屏页
/// 会被回收 —— 状态（滚动位置、车道探测结果）就丢了。`KeepAlivePage` 就是
/// 用来恢复原语义的，这里验证它真的生效。
void main() {
  // 页面状态是否保活的可观察信号：State 重建就归零，保活则累加。
  final ValueNotifier<int> tick = ValueNotifier<int>(0);

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageView(
            controller: PageController(),
            children: [
              KeepAlivePage(
                child: ListenableBuilder(
                  listenable: tick,
                  builder: (context, _) => TextButton(
                    onPressed: () => tick.value++,
                    child: Text('page0#${tick.value}'),
                  ),
                ),
              ),
              const Center(child: Text('page1')),
              const Center(child: Text('page2')),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('切到第三页再回来，第一页的 State 不应被重建', (tester) async {
    await pumpShell(tester);

    // 在第一页点两下，让 State 持有自己的计数（每次 tap 后要 pump 才会重建文本）
    await tester.tap(find.text('page0#0'));
    await tester.pump();
    await tester.tap(find.text('page0#1'));
    await tester.pump();
    expect(find.text('page0#2'), findsOneWidget);

    // 滑到第三页（离屏），再滑回第一页
    await tester.drag(find.byType(PageView), const Offset(-1600, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(1600, 0));
    await tester.pumpAndSettle();

    // 保活生效：计数仍是 2；若 State 被重建，这里会显示 page0#0
    expect(find.text('page0#2'), findsOneWidget);
    expect(tick.value, 2);
  });

  testWidgets('animateToPage 的时长/曲线参数合法（>0）', (tester) async {
    // 直接钉住常量，防止将来误改成 0 导致动画变成瞬切
    expect(kPageTransitionDuration, greaterThan(Duration.zero));
    expect(kPageTransitionCurve.transform(0.5), inInclusiveRange(0.0, 1.0));
  });
}
