import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';

void _noop(bool _) {}

/// 回归：miuix 卡片首/尾列表项的选中态（按压/hold 遮罩）是**直角**，会盖过
/// 卡片的圆角、看起来「露在卡片外面」。
///
/// 根因在 flutter_miuix：`MiuixBasicComponent` 的 hold/按压遮罩是一块直角
/// `ColoredBox`，而 `MiuixCard` 只用 ShapeDecoration 画背景、不裁切子节点。
/// [MiuixGroupCard] 把整张卡按自己的 squircle 裁一刀，遮罩就只露出与卡片
/// 轮廓一致的圆角。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget harness(Widget child) => MiuixThemeController(
    child: MaterialApp(home: Scaffold(body: Center(child: child))),
  );

  testWidgets('卡片内容整体被裁到 squircle 里，遮罩不再是直角外露', (tester) async {
    await tester.pumpWidget(
      harness(
        const MiuixGroupCard(
          cornerRadius: 20,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 首行：holdDownState = true 就是「选中态」，遮罩是直角 ColoredBox
              MiuixSwitchPreference(
                title: 'first',
                value: true,
                onChanged: _noop,
                holdDownState: true,
              ),
              MiuixSwitchPreference(
                title: 'last',
                value: false,
                onChanged: _noop,
                holdDownState: true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    // 裁切层必须在最外层、且形状就是卡片那颗 squircle
    final clip = tester.widget<ClipPath>(
      find.descendant(
        of: find.byType(MiuixGroupCard),
        matching: find.byType(ClipPath),
      ).first,
    );
    final clipper = clip.clipper! as ShapeBorderClipper;
    expect(clipper.shape, isA<MiuixSquircleBorder>());
    expect(
      (clipper.shape as MiuixSquircleBorder).cornerRadius,
      20,
      reason: '裁切圆角要和卡片一致，否则不是「和卡片一样圆角」',
    );

    // 两行的选中遮罩（直角 ColoredBox）都必须在裁切层**内侧**
    final colored = find.descendant(
      of: find.byType(MiuixGroupCard),
      matching: find.byType(ColoredBox),
    );
    expect(colored, findsWidgets);
    for (final box in colored.evaluate()) {
      final clipped = find
          .descendant(
            of: find.ancestor(of: find.byWidget(box.widget), matching: find.byType(ClipPath)),
            matching: find.byWidget(box.widget),
          )
          .evaluate();
      expect(clipped, isNotEmpty, reason: '有遮罩没被卡片裁到');
    }
  });

  testWidgets('圆角 0 时退化成普通矩形，不额外画圆角', (tester) async {
    await tester.pumpWidget(
      harness(
        const MiuixGroupCard(
          cornerRadius: 0,
          child: MiuixSwitchPreference(
            title: 'row',
            value: true,
            onChanged: _noop,
            holdDownState: true,
          ),
        ),
      ),
    );
    await tester.pump();
    final clip = tester.widget<ClipPath>(
      find
          .descendant(
            of: find.byType(MiuixGroupCard),
            matching: find.byType(ClipPath),
          )
          .first,
    );
    expect((clip.clipper! as ShapeBorderClipper).shape, isA<MiuixSquircleBorder>());
    // 仍然裁切（保证遮罩不外露），只是形状退化为矩形
    expect(clip.clipBehavior, isNot(Clip.none));
  });
}
