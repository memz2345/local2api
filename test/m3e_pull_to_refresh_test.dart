import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/src/expressive_loading_indicator.dart';
import 'package:local2api/src/loading_indicator_m3e.dart';
import 'package:local2api/widgets/m3e_pull_to_refresh.dart';

/// 阈值 80 × DragMultiplier 0.5 → 原始位移要超过 160 才会触发刷新。
const double _kTriggerPull = 300;
const double _kSubThresholdPull = 100;

Finder _indicator() => find.byType(ExpressiveLoadingIndicator);

/// 指示器在不定态时会跑 Timer.periodic + 重复动画，
/// 测试结束前必须让它收回 idle，否则 pumpAndSettle 挂起、timer 报未清。
Future<void> _settleIdle(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

Widget _list() => ListView.builder(
  itemCount: 60,
  itemBuilder: (context, i) => SizedBox(height: 60, child: Text('$i')),
);

/// 父级托管 isRefreshing 的壳：由测试持有的 [refreshing] 驱动，
/// 这样测试翻状态时不用去碰 State.setState（protected 成员）。
class _Hoisted extends StatefulWidget {
  const _Hoisted({required this.onRefresh, required this.refreshing});

  final Future<void> Function() onRefresh;
  final ValueNotifier<bool> refreshing;

  @override
  State<_Hoisted> createState() => _HoistedState();
}

class _HoistedState extends State<_Hoisted> {
  @override
  void initState() {
    super.initState();
    widget.refreshing.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.refreshing.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: M3EPullToRefresh(
        isRefreshing: widget.refreshing.value,
        onRefresh: widget.onRefresh,
        child: _list(),
      ),
    ),
  );
}

Widget _plain({required Future<void> Function() onRefresh}) => MaterialApp(
  home: Scaffold(
    body: M3EPullToRefresh(isRefreshing: false, onRefresh: onRefresh, child: _list()),
  ),
);

void main() {
  group('下拉触发判定', () {
    testWidgets('拉过阈值松手才回调 onRefresh，没拉够不回调', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_plain(onRefresh: () async => calls++));

      await tester.drag(find.byType(ListView), const Offset(0, _kSubThresholdPull));
      await _settleIdle(tester);
      expect(calls, 0, reason: '位移折半后没过阈值，不该触发');

      await tester.drag(find.byType(ListView), const Offset(0, _kTriggerPull));
      await tester.pump();
      expect(calls, 1);
      await _settleIdle(tester);
    });

    testWidgets('没贴顶时下拉不触发（列表已滚下去）', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_plain(onRefresh: () async => calls++));

      // 先滚到中间，extentBefore > 0
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await _settleIdle(tester);

      await tester.drag(find.byType(ListView), const Offset(0, _kTriggerPull));
      await _settleIdle(tester);
      expect(calls, 0);
    });
  });

  group('指示器形态', () {
    testWidgets('指示器就是 48×48，不会被槽的紧宽度拉成整页宽', (tester) async {
      // 回归：槽是 Positioned(left:0, right:0, height:0)，宽度是紧约束。
      // OverflowBox 不放宽度的话 SizedBox(48,48) 会变成「整页宽 × 48」，
      // M3E 形状按 size.width 缩放 → 画出一坨跨屏巨物。
      await tester.pumpWidget(_plain(onRefresh: () async {}));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ListView)),
      );
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();

      expect(_indicator(), findsOneWidget);
      expect(tester.getSize(_indicator()), const Size(48, 48));
      // 容器的装饰盒（圆角底）也该是 48×48，不是一条横贯整屏的带子
      final decorated = find.descendant(
        of: find.byType(LoadingIndicatorM3E),
        matching: find.byType(DecoratedBox),
      );
      expect(tester.getSize(decorated.first), const Size(48, 48));

      await gesture.up();
      await _settleIdle(tester);
    });

    testWidgets('拖拽中走定态，进度随位移增长且越阈值后夹在 1.0', (tester) async {
      await tester.pumpWidget(_plain(onRefresh: () async {}));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ListView)),
      );
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      expect(_indicator(), findsOneWidget);
      final early = tester.widget<ExpressiveLoadingIndicator>(_indicator()).value;
      expect(early, isNotNull, reason: '拖拽阶段必须是定态');
      expect(early!, greaterThan(0.0));
      expect(early, lessThan(1.0));

      // 远超阈值：张力曲线让 fraction 封顶 2.0，定态进度夹到 1.0
      await gesture.moveBy(const Offset(0, 4000));
      await tester.pump();
      expect(
        tester.widget<ExpressiveLoadingIndicator>(_indicator()).value,
        1.0,
      );

      await gesture.up();
      await _settleIdle(tester);
    });

    testWidgets('刷新中切成不定态，父级置回 false 后收起', (tester) async {
      final gate = Completer<void>();
      final refreshing = ValueNotifier<bool>(false);
      addTearDown(refreshing.dispose);
      await tester.pumpWidget(
        _Hoisted(onRefresh: () => gate.future, refreshing: refreshing),
      );

      await tester.drag(find.byType(ListView), const Offset(0, _kTriggerPull));
      await tester.pump();
      expect(
        tester.widget<ExpressiveLoadingIndicator>(_indicator()).value,
        isNull,
        reason: '刷新中该跑不定态形变',
      );

      // 托管方接手：置 true（此时内部已是 refresh，不该重复展开）
      refreshing.value = true;
      await tester.pump();
      expect(_indicator(), findsOneWidget);

      // 干完活：置回 false → 收起
      refreshing.value = false;
      gate.complete();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(_indicator(), findsNothing, reason: '收起后不该再渲染指示器');
    });

    testWidgets('父级直接置 isRefreshing=true 时自动展开（程序化刷新）', (tester) async {
      final refreshing = ValueNotifier<bool>(false);
      addTearDown(refreshing.dispose);
      await tester.pumpWidget(
        _Hoisted(onRefresh: () async {}, refreshing: refreshing),
      );
      expect(_indicator(), findsNothing);

      refreshing.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_indicator(), findsOneWidget);
      expect(
        tester.widget<ExpressiveLoadingIndicator>(_indicator()).value,
        isNull,
      );

      refreshing.value = false;
      await tester.pump();
      await tester.pumpAndSettle();
      expect(_indicator(), findsNothing);
    });
  });

  group('开关与嵌套', () {
    testWidgets('enabled=false 时下拉不触发', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: M3EPullToRefresh(
              isRefreshing: false,
              onRefresh: () async => calls++,
              enabled: false,
              child: _list(),
            ),
          ),
        ),
      );

      await tester.drag(find.byType(ListView), const Offset(0, _kTriggerPull));
      await _settleIdle(tester);
      expect(calls, 0);
    });

    testWidgets('只认 depth==0 的滚动通知，内层横向列表不触发', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: M3EPullToRefresh(
              isRefreshing: false,
              onRefresh: () async => calls++,
              child: ListView(
                children: [
                  SizedBox(
                    height: 120,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: const [SizedBox(width: 800, height: 120)],
                    ),
                  ),
                  for (var i = 0; i < 40; i++)
                    SizedBox(height: 60, child: Text('$i')),
                ],
              ),
            ),
          ),
        ),
      );

      // 横着拽内层列表：不该把外层下拉刷新带起来
      final inner = find.byType(ListView).at(1);
      await tester.drag(inner, const Offset(-200, 0));
      await _settleIdle(tester);
      expect(calls, 0);
    });
  });
}
