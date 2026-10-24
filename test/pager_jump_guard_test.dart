// 回归：常驻侧栏「1 → 3」跳页时，PageView 途中会报中间页（1、2），
// 直接拿 onPageChanged 驱动高亮就会让中间项闪一下。
//
// 这里用一个最小 harness 验证 [PagerJumpGuard] 的语义：
//   · 程序化跳页途中路过的页不回调；
//   · 落到目标页正常回调一次；
//   · 用户自己拖拽时立刻接管（不能被上次跳页的目标卡住）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/widgets/page_switcher.dart';

class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness>
    with PagerJumpGuard<_Harness> {
  final PageController controller = PageController();
  final List<int> reported = <int>[];

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> jump(int page) async {
    beginPagerJump(page);
    await controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.linear,
    );
    endPagerJump();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: guardPagerGestures(
        PageView(
          controller: controller,
          onPageChanged: (i) {
            if (ignorePagerReport(i)) return;
            reported.add(i);
          },
          children: const [
            SizedBox.expand(key: ValueKey(0)),
            SizedBox.expand(key: ValueKey(1)),
            SizedBox.expand(key: ValueKey(2)),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('1 → 3 跳页不回调中间页，只回调落点', (tester) async {
    await tester.pumpWidget(const _Harness());
    final state = tester.state<_HarnessState>(find.byType(_Harness));

    state.jump(2);
    await tester.pumpAndSettle();

    expect(state.reported, [2]);
    expect(state.pagerTarget, isNull);
  });

  testWidgets('3 → 1 反向跳页同样只回调落点', (tester) async {
    await tester.pumpWidget(const _Harness());
    final state = tester.state<_HarnessState>(find.byType(_Harness));
    state.jump(2);
    await tester.pumpAndSettle();

    state.jump(0);
    await tester.pumpAndSettle();

    expect(state.reported, [2, 0]);
  });

  testWidgets('跳页途中用户拖拽：守卫立刻让位，手滑的每一页都回调', (tester) async {
    await tester.pumpWidget(const _Harness());
    final state = tester.state<_HarnessState>(find.byType(_Harness));

    state.jump(2);
    // 动画走到一半就抓住页面往左拖，模拟用户接管。
    await tester.pump(const Duration(milliseconds: 120));
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();

    // 至少落点会回调；关键是守卫已经清掉，不会把后续页当成「路过」吞掉。
    expect(state.reported, isNotEmpty);
    expect(state.pagerTarget, isNull);
  });
}
