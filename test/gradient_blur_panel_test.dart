import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:local2api/widgets/expressive_app_bar.dart';

/// Material 侧渐变模糊面板的回归。
///
/// 与 miuix 侧那条（`test/miuix_gradient_blur_top_bar_test.dart`）守的是同一
/// 个坑：模糊层外面**不能**有会 saveLayer 另起 backdrop root 的 widget
/// （Opacity / AnimatedOpacity / ShaderMask / ColorFiltered），否则
/// BackdropFilter 糊不到栏下滚上来的页面内容，看上去就只是一层半透明色。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget harness(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  /// 从 [ProgressiveBlur] 往上走到 [GradientBlurPanel] 本体为止，收集路上
  /// 会另起 backdrop root 的 widget。**必须是空的。**
  List<Widget> backdropRootOffenders(WidgetTester tester) {
    final panelElement = tester.element(find.byType(GradientBlurPanel));
    final blurElement = tester.element(find.byType(ProgressiveBlur));
    final offenders = <Widget>[];
    blurElement.visitAncestorElements((ancestor) {
      if (ancestor == panelElement) return false;
      final w = ancestor.widget;
      final killsBackdrop =
          (w is Opacity && w.opacity < 1.0) ||
          (w is AnimatedOpacity && w.opacity < 1.0) ||
          (w is FadeTransition && w.opacity.value < 1.0) ||
          w is ShaderMask ||
          w is ColorFiltered;
      if (killsBackdrop) offenders.add(w);
      return true;
    });
    return offenders;
  }

  /// 面板里那层压字渐变（限定在 [GradientBlurPanel] 子树内取，免得撞到
  /// MaterialApp 自己的装饰）。
  LinearGradient tintGradientOf(WidgetTester tester) => tester
      .widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(GradientBlurPanel),
          matching: find.byType(DecoratedBox),
        ),
      )
      .map((b) => b.decoration)
      .whereType<BoxDecoration>()
      .map((d) => d.gradient)
      .whereType<LinearGradient>()
      .first;

  group('GradientBlurPanel', () {
    testWidgets('intensity = 0 时一层都不画（不留合成开销）', (tester) async {
      await tester.pumpWidget(
        harness(
          const GradientBlurPanel(
            intensity: 0,
            child: SizedBox(height: 56, width: 200),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ProgressiveBlur), findsNothing);
      // 子节点照常渲染
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('intensity = 1 时按 maxSigma 满强度糊，压字色走渐变', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          const GradientBlurPanel(
            maxSigma: 12,
            tintAlphaTop: 0.75,
            tint: Color(0xFF112233),
            child: SizedBox(height: 56, width: 200),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final blur = tester.widget<ProgressiveBlur>(find.byType(ProgressiveBlur));
      expect(blur.maxSigma, 12);
      expect(blur.direction, ProgressiveBlurDirection.topToBottom);

      // 压字色是自上而下淡出的渐变，不是平铺一块
      final gradient = tintGradientOf(tester);
      expect(
        gradient.colors.first,
        const Color(0xFF112233).withValues(alpha: 0.75),
      );
      expect(
        gradient.colors.last,
        const Color(0xFF112233).withValues(alpha: 0.0),
      );
    });

    testWidgets('sigma 与压字色都随 intensity 线性缩放', (tester) async {
      final sigmas = <double>[];
      final topAlphas = <double>[];
      for (final i in [0.25, 0.5, 1.0]) {
        await tester.pumpWidget(
          harness(
            GradientBlurPanel(
              intensity: i,
              maxSigma: 12,
              tintAlphaTop: 0.8,
              tint: const Color(0xFF112233),
              child: const SizedBox(height: 56, width: 200),
            ),
          ),
        );
        await tester.pumpAndSettle();
        sigmas.add(
          tester.widget<ProgressiveBlur>(find.byType(ProgressiveBlur)).maxSigma,
        );
        topAlphas.add(tintGradientOf(tester).colors.first.a);
      }
      expect(sigmas, [3.0, 6.0, 12.0]);
      expect(topAlphas, [0.2, 0.4, 0.8]);
    });

    testWidgets('回归：模糊层外面没有任何会另起 backdrop root 的 widget', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          const GradientBlurPanel(
            child: SizedBox(height: 56, width: 200),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        backdropRootOffenders(tester),
        isEmpty,
        reason: '面板里糊的层外面套了 Opacity / ShaderMask 之类的东西，'
            'BackdropFilter 会糊不到栏下的页面内容，看起来就是透明的',
      );
    });
  });
}
