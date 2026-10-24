import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:local2api/widgets/miuix/miuix_gradient_blur_top_bar.dart';

/// 回归：渐变模糊顶栏「看起来是透明的、没有模糊」。
///
/// 根因是淡入方式：旧实现把整条模糊带（14 片 `BackdropFilter` 切片）包在一个
/// `Opacity(alpha: collapsedFraction)` 里。祖先 `Opacity` 会 `saveLayer` 另起
/// 一个 backdrop root，组内的 `BackdropFilter` 只能糊到这个 layer 组**内部**
/// 的东西 —— 而组里除了它自己什么也没有，于是模糊糊的是空气，画面上只剩
/// tint 那层半透明色，看着就是「透明、没模糊」。
///
/// 现在淡入靠改 `ProgressiveBlur.maxSigma`（着色器单 pass 变半径模糊），
/// 整条带外面**不许**再有任何会另起 backdrop root 的 widget。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget harness(MiuixScrollBehavior behavior) => MiuixThemeController(
    child: MaterialApp(
      home: Scaffold(
        body: MiuixGradientBlurTopBar(title: '标题', scrollBehavior: behavior),
      ),
    ),
  );

  /// 泵一次顶栏，返回可以驱动折叠度的 state。
  Future<MiuixTopAppBarState> pumpBar(WidgetTester tester) async {
    final state = MiuixTopAppBarState();
    await tester.pumpWidget(
      harness(MiuixExitUntilCollapsedScrollBehavior(state: state)),
    );
    await tester.pumpAndSettle();
    return state;
  }

  /// 把折叠度拨到 [fraction]（0 = 完全展开，1 = 完全折叠）再泵一帧。
  ///
  /// 必须在 pump **之后**拨：`MiuixTopAppBar` 会按自己量到的大标题展开量
  /// 回写 `heightOffsetLimit`，预设的值会被它盖掉（`collapsedFraction` =
  /// `heightOffset / heightOffsetLimit`，两个都是负数）。
  Future<void> collapseTo(
    WidgetTester tester,
    MiuixTopAppBarState state,
    double fraction,
  ) async {
    state
      ..heightOffsetLimit = -100
      ..heightOffset = -100 * fraction.clamp(0.0, 1.0);
    await tester.pump();
  }

  /// 从 [ProgressiveBlur] 往上走到 [MiuixGradientBlurTopBar] 本体为止，把路上
  /// 那些会另起 backdrop root（从而让 `BackdropFilter` 糊不到页面内容）的
  /// widget 收集出来。**必须是空的。**
  ///
  /// 只查这一段：顶栏之上是 MaterialApp / 路由那些框架自己的层，跟本回归无关。
  List<Widget> backdropRootOffenders(WidgetTester tester) {
    final barElement = tester.element(find.byType(MiuixGradientBlurTopBar));
    final blurElement = tester.element(find.byType(ProgressiveBlur));
    final offenders = <Widget>[];
    blurElement.visitAncestorElements((ancestor) {
      if (ancestor == barElement) return false;
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

  group('MiuixGradientBlurTopBar', () {
    testWidgets('完全展开（collapsedFraction = 0）时不画模糊带', (tester) async {
      final state = await pumpBar(tester);
      await collapseTo(tester, state, 0);
      expect(find.byType(ProgressiveBlur), findsNothing);
    });

    testWidgets('完全折叠时是满强度渐进模糊 + 自上而下淡到 0 的压字色', (tester) async {
      final state = await pumpBar(tester);
      await collapseTo(tester, state, 1);

      final blur = tester.widget<ProgressiveBlur>(find.byType(ProgressiveBlur));
      // AppMarket progressiveBarBlur：blurRadius 10 × 0.45 = sigma 4.5
      expect(blur.maxSigma, closeTo(4.5, 0.001));
      expect(blur.direction, ProgressiveBlurDirection.topToBottom);

      // 压字色：顶边 surface@30%、底边淡到 0 的**渐变**（不是平铺）。
      final gradients = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(MiuixGradientBlurTopBar),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((b) => b.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.gradient)
          .whereType<LinearGradient>()
          .toList();
      expect(gradients, isNotEmpty, reason: '缺压字色渐变层');
      final colors = gradients.first.colors;
      expect(colors.length, 2);
      expect(
        colors.first.a,
        closeTo(0.3, 0.01),
        reason: '顶边压字色应为 surface@30%',
      );
      expect(
        colors.last.a,
        0.0,
        reason: '底边压字色必须淡到完全透明，否则带的下边缘会留一条分界线',
      );
    });

    testWidgets('回归：压字色不许再整条平铺（那正是分界线的来源）', (tester) async {
      final state = await pumpBar(tester);
      await collapseTo(tester, state, 1);

      // 平铺的 surface@XX% 会在带底边留下色阶突变：模糊在底边已衰减到 0，
      // 但平铺色没有，于是「带内」与「带外」对不上，画面上就是一道硬边。
      final flatTints = tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byType(MiuixGradientBlurTopBar),
              matching: find.byType(ColoredBox),
            ),
          )
          .where((b) => b.color.a > 0.01)
          .toList();
      expect(
        flatTints,
        isEmpty,
        reason: '压字色必须是自上而下淡到 0 的渐变，不能整条平铺',
      );
    });

    testWidgets('回归：模糊层外面没有任何会另起 backdrop root 的 widget', (
      tester,
    ) async {
      final state = await pumpBar(tester);
      await collapseTo(tester, state, 1);
      expect(
        backdropRootOffenders(tester),
        isEmpty,
        reason: '模糊带外面套了 Opacity / ShaderMask 之类的层，BackdropFilter '
            '会糊不到滚上来的页面内容，看起来就是透明的',
      );
    });

    testWidgets('sigma 随折叠度单调增长，且不超过满强度', (tester) async {
      final state = await pumpBar(tester);
      final sigmas = <double>[];
      for (final f in [0.1, 0.3, 0.5, 0.8, 1.0]) {
        await collapseTo(tester, state, f);
        final blur = tester.widget<ProgressiveBlur>(
          find.byType(ProgressiveBlur),
        );
        sigmas.add(blur.maxSigma);
        expect(blur.maxSigma, lessThanOrEqualTo(4.5 + 1e-9));
        expect(blur.maxSigma, greaterThan(0));
      }
      for (var i = 0; i < sigmas.length - 1; i++) {
        expect(
          sigmas[i],
          lessThan(sigmas[i + 1]),
          reason: '折叠度第 $i 到 ${i + 1} 档之间模糊没有变强：$sigmas',
        );
      }
      expect(sigmas.last, closeTo(4.5, 0.001));
    });

    testWidgets('带高 = 状态栏 + 52dp（折叠栏高），无状态栏 inset 时兜底 56', (
      tester,
    ) async {
      // 默认测试环境状态栏 inset 为 0 → 兜底 56
      // （带高必须跟顶栏本体等高：矮一截的话它的下边缘会落在标题行中间，
      // 内容被截断成一条横贯全宽的分界线。）
      final state = await pumpBar(tester);
      await collapseTo(tester, state, 1);
      final heights = tester
          .widgetList<SizedBox>(
            find.ancestor(
              of: find.byType(ProgressiveBlur),
              matching: find.byType(SizedBox),
            ),
          )
          .map((b) => b.height)
          .whereType<double>()
          .toList();
      expect(heights, contains(56.0));
    });
  });
}
