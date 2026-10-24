import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';

/// 短页面（内容不满一屏）上拉时，折叠量要跟着「未消费的越界量」走 ——
/// 这是对 flutter_miuix 短页路径的补丁，回归防线就靠这几条。
void main() {
  /// 造一条短页面的滚动指标：min == max == 0（内容不满一屏，pixels 钉死 0）。
  ScrollMetrics shortPageMetrics() => FixedScrollMetrics(
    minScrollExtent: 0,
    maxScrollExtent: 0,
    pixels: 0,
    viewportDimension: 600,
    axisDirection: AxisDirection.down,
    devicePixelRatio: 1.0,
  );

  /// 长页面的指标：可滚行程远大于展开量（这里已滚 30px）。
  ScrollMetrics longPageMetrics() => FixedScrollMetrics(
    minScrollExtent: 0,
    maxScrollExtent: 2000,
    pixels: 30,
    viewportDimension: 600,
    axisDirection: AxisDirection.down,
    devicePixelRatio: 1.0,
  );

  /// OverscrollNotification 需要一个真的 BuildContext（它是 ScrollContext），
  /// 从一棵最小的树上拿一个。
  Future<BuildContext> pumpContext(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          ctx = context;
          return const SizedBox();
        },
      ),
    );
    return ctx;
  }

  OverscrollNotification overscroll(
    BuildContext context,
    double amount, {
    ScrollMetrics? metrics,
    bool withDrag = true,
  }) => OverscrollNotification(
    metrics: metrics ?? shortPageMetrics(),
    context: context,
    overscroll: amount,
    dragDetails: withDrag
        ? DragUpdateDetails(
            globalPosition: const Offset(200, 400),
            delta: const Offset(0, -20),
          )
        : null,
  );

  MiuixShortPageScrollBehavior behaviorWithExpansion(double expansion) {
    final behavior = MiuixShortPageScrollBehavior();
    behavior.state.heightOffsetLimit = -expansion;
    return behavior;
  }

  testWidgets('短页面上拉：越界量按 1:1 记进折叠量，并钳在展开量上', (tester) async {
    final ctx = await pumpContext(tester);
    final behavior = behaviorWithExpansion(60);

    behavior.handleScroll(overscroll(ctx, 25));
    expect(behavior.state.heightOffset, -25);

    behavior.handleScroll(overscroll(ctx, 25));
    expect(behavior.state.heightOffset, -50);

    // 折到底就停住（setter 钳制），继续上拉不越界
    behavior.handleScroll(overscroll(ctx, 40));
    expect(behavior.state.heightOffset, -60);
  });

  testWidgets('短页面下拉：把折叠中的标题逐步放回去', (tester) async {
    final ctx = await pumpContext(tester);
    final behavior = behaviorWithExpansion(60);
    behavior.handleScroll(overscroll(ctx, 50));
    expect(behavior.state.heightOffset, -50);

    // overscroll < 0 = 顶部下拉 → 展开
    behavior.handleScroll(overscroll(ctx, -20));
    expect(behavior.state.heightOffset, -30);

    behavior.handleScroll(overscroll(ctx, -100));
    expect(behavior.state.heightOffset, 0);
  });

  testWidgets('长页面不掺和：折叠量由父类按滚动位置同步，不能双倍记账', (tester) async {
    final ctx = await pumpContext(tester);
    final behavior = behaviorWithExpansion(60);
    // 长页面已滚 30px：父类把折叠量同步成 -30；这里的越界量若再被记一次
    // 就会变成 -60（甚至更小）
    behavior.handleScroll(overscroll(ctx, 50, metrics: longPageMetrics()));
    expect(behavior.state.heightOffset, -30);
  });

  testWidgets('惯性 / 吸附动画的越界（dragDetails 为空）不算', (tester) async {
    final ctx = await pumpContext(tester);
    final behavior = behaviorWithExpansion(60);
    behavior.handleScroll(overscroll(ctx, 50, withDrag: false));
    expect(behavior.state.heightOffset, 0);
  });

  testWidgets('展开量未测出 / pinned（limit 不是负数）时不动作', (tester) async {
    final ctx = await pumpContext(tester);
    final behavior = MiuixShortPageScrollBehavior(); // limit = -∞
    behavior.handleScroll(overscroll(ctx, 50));
    expect(behavior.state.heightOffset, 0);

    behavior.state.pin(); // SmallTopAppBar 的 pinned 语义
    behavior.handleScroll(overscroll(ctx, 50));
    expect(behavior.state.heightOffset, 0);
  });
}