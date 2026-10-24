import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/widgets/ios_push_transition.dart';

/// 回归：push 转场两层几何必须锁在同一进度上（miuix-nav 的单 float 语义）。
///
/// 曾经的 bug：框架在每条路由**入场的第一帧**会把路由置 offstage 并把
/// `animation` 顶成 kAlwaysCompleteAnimation（value=1.0，Hero 测量用，
/// 见 `ModalRoute.offstage` 文档）。驱动器在这一帧被播种到「已落位」，
/// 之后真实动画从 0 起步，状态机整条轨迹全乱 —— 入场页起手一段几乎不动，
/// 被覆盖层却在正常视差，两层错位、中间漏出黑边（pop 无 offstage 帧，
/// 所以退场一直正常）。修法是跳过预热帧并 `MiuixNavSettleDriver.reset()`。
///
/// 这里钉两条性质（都以 miuix-nav `NavTransitions.MiuixDefault` 为准）：
///   1. 入场页位移 = (1 - settleCurve(raw)) × width（整条烘焙曲线）；
///   2. 任意时刻入场页左边缘不得越过被覆盖页右边缘（不允许露黑边）。
void main() {
  testWidgets('push：入场几何贴 settle 曲线，全程无黑边', (tester) async {
    tester.view.physicalSize = const Size(540, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(backgroundColor: Colors.white, body: SizedBox()),
      ),
    );
    await tester.pumpAndSettle();

    final width = tester.getSize(find.byType(Scaffold).first).width;
    final coverRightBefore = width; // 被覆盖页满宽，右边缘在 width 处
    final navigator = tester.state(find.byType(Navigator).first) as NavigatorState;
    final route = MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: Colors.red,
        body: const Center(child: Text('PUSHED', key: ValueKey('pushed'))),
      ),
    );
    navigator.push(route);

    final curve = MiuixNavSettleCurve();
    final pushedFinder = find.byKey(const ValueKey('pushed'), skipOffstage: false);
    final animation = route.animation!;

    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 70));
      final raw = animation.value;
      if (raw <= 0 || raw >= 1) continue;
      final enterLeft =
          tester.getTopLeft(pushedFinder).dx -
          (width - tester.getSize(pushedFinder).width) / 2;
      final coverRight = coverRightBefore - 0.25 * curve.transform(raw) * width;
      // 1) 入场位移 = (1 - settleCurve(raw)) × width
      expect(
        enterLeft,
        closeTo((1 - curve.transform(raw)) * width, 1.5),
        reason: 'raw=$raw 入场位移没跟上烘焙曲线',
      );
      // 2) 无黑边：入场页左边缘必须在被覆盖页右边缘之内
      expect(
        enterLeft,
        lessThanOrEqualTo(coverRight + 0.5),
        reason: 'raw=$raw 两层之间漏出黑边',
      );
    }
    await tester.pumpAndSettle();
  });

  testWidgets('pop：退场全程无黑边（本来正常，钉住别回归）', (tester) async {
    tester.view.physicalSize = const Size(540, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(backgroundColor: Colors.white, body: SizedBox()),
      ),
    );
    await tester.pumpAndSettle();

    final width = tester.getSize(find.byType(Scaffold).first).width;
    final navigator = tester.state(find.byType(Navigator).first) as NavigatorState;
    final route = MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: Colors.red,
        body: const Center(child: Text('PUSHED', key: ValueKey('pushed'))),
      ),
    );
    navigator.push(route);
    await tester.pumpAndSettle();

    final curve = MiuixNavSettleCurve();
    final pushedFinder = find.byKey(const ValueKey('pushed'), skipOffstage: false);
    final animation = route.animation!;
    navigator.pop();

    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 70));
      final raw = animation.value;
      if (raw <= 0 || raw >= 1) continue;
      // pop 是镜像：两层进度都是 1 - settleCurve(1 - raw)
      final v = 1 - curve.transform(1 - raw);
      final enterLeft =
          tester.getTopLeft(pushedFinder).dx -
          (width - tester.getSize(pushedFinder).width) / 2;
      final coverRight = width - 0.25 * v * width;
      expect(
        enterLeft,
        closeTo((1 - v) * width, 1.5),
        reason: 'raw=$raw 退场位移没跟上镜像曲线',
      );
      expect(
        enterLeft,
        lessThanOrEqualTo(coverRight + 0.5),
        reason: 'raw=$raw 退场两层之间漏出黑边',
      );
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pushed')), findsNothing);
  });
}
