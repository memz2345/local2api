import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// AppMarket 同款的「渐变模糊顶栏」（miuix 可选外观，对应
/// `MarketScaffold` 的 `AdaptiveTopAppBar` 区块）：
///
/// - 顶栏本体**全透明**（`MiuixTopAppBar(color: transparent)`，不开毛玻璃、
///   不做大标题模糊）—— 只有样式，没有背景；
/// - 顶部叠一条**渐进模糊带**：高度与顶栏本体等高（状态栏 + 52dp，见
///   `build` 里的说明），模糊从顶边满强度沿衰减曲线过渡到底边的完全清晰，
///   叠 `surface @ 30%` 压字（色一路淡到 0），整条带
///   的强度跟着顶栏折叠度淡入 —— 内容没滚进来时带是隐形的，滚入后逐渐
///   显形（AppMarket 用 `alpha = collapsedFraction` 驱动，见
///   `MarketScaffold.kt` 的 `HidingMainTabScaffold`）。
///
/// ## 模糊带怎么画的，以及为什么不能用 Opacity 淡入
///
/// 用的是 [ProgressiveBlur]（vendored `liquid_glass_widgets`，`main.dart` 里
/// `LiquidGlassWidgets.initialize()` 已经 preload 过它的着色器）：一次 backdrop
/// 采样 + 两趟可分离高斯，逐像素按到顶边的距离取 sigma。这是 Compose 侧
/// `Modifier.progressiveTextureBlur`（AGSL RuntimeShader 单 pass 变半径模糊）
/// 在 Flutter 上的对等物。
///
/// **淡入必须靠改 `maxSigma`，不能靠在外层套 `Opacity`。** 祖先 `Opacity`
/// 会 `saveLayer` 另起一个 backdrop root，内部的 `BackdropFilter` 就只能糊到
/// 这个 layer 组**里面**的东西 —— 而组里除了它自己啥也没有，于是模糊糊的是
/// 空气，画面上只剩 tint 那层半透明色，看起来就是「透明、没模糊」。
/// 早先的多切片实现（`MiuixProgressiveBlurBand`，14 片 `BackdropFilter`
/// 逼近变半径）正是栽在这上面，已删除。
///
/// AppMarket 是把**满强度**的模糊整层按 `collapsedFraction` 调不透明度；
/// Flutter 的 `BackdropFilter` 做不到「糊完再半透明叠加」而不引入 saveLayer，
/// 所以这里改成让 sigma 自己从 0 长到满值 —— `ProgressiveBlur` 的文档也是
/// 这么建议的（"Drive maxSigma from a scroll offset to fade the blur in/out"）。
/// 观感上是连续的「越滚越糊」，比整层淡入更顺。
///
/// 「启用模糊」关掉或渲染路径不支持着色器时调用方（[MiuixBlurTopBar]）
/// 不应走到这里 —— 本组件不做开关判断（`naviGlassAdvanced` 已经把
/// `ImageFilter.isShaderFilterSupported` 一起判掉了）。
class MiuixGradientBlurTopBar extends StatelessWidget {
  const MiuixGradientBlurTopBar({
    super.key,
    required this.title,
    this.navigationIcon,
    this.actions,
    this.scrollBehavior,
  });

  final String title;
  final Widget? navigationIcon;
  final List<Widget>? actions;
  final MiuixScrollBehavior? scrollBehavior;

  /// 满强度端的模糊半径（dp）—— AppMarket `progressiveBarBlur` 的
  /// `blurRadius = 10f`。换成 sigma 用 flutter_miuix 的同一套系数
  /// （`MiuixBlurDefaults.blurRadiusToSigma = 0.45`）。
  static const double blurRadius = 10;

  /// 满强度端的 sigma（逻辑像素）。
  static const double maxSigma = blurRadius * 0.45;

  /// 着色器的渐变 gamma。AppMarket 用的是 miuix 的 `curve = 2.2f`，其强度
  /// 曲线是 `1 − smoothstep(g)^2.2`；本项目的着色器是 `pow(1 − g, falloff)`，
  /// 两者不同形。这里取 1.2（着色器的出厂默认）而不是去凑中点强度：
  /// 凑中点（falloff ≈ 0.4）会在带的**下边缘**留一段没衰减干净的模糊，
  /// 变成一条肉眼可见的硬切边 —— 而「干净地溶解到完全清晰」正是渐进模糊
  /// 存在的意义。
  static const double falloff = 1.2;

  /// 模糊之上**顶边**叠的压字色不透明度 —— AppMarket 的 `surface @ 0.3f`
  /// （`BlendColorEntry(color = surface.copy(0.3f))`）。
  ///
  /// 注意：这里只给顶边的值，色要一路淡到 0（见 [_ProgressiveBand]）。
  /// 早先整条平铺 0.3 的写法会在带的**下边缘**留下一条色阶突变 —— 模糊本身
  /// 在底边已经衰减到 0，但压字色没衰减，于是「带内(色+内容)」与「带外(纯
  /// 内容)」在边界处对不上，画面上就是一道肉眼可见的分界线（material 侧的
  /// [GradientBlurPanel] 一直用的是淡出的色，所以没这个问题）。
  static const double tintAlphaTop = 0.3;

  /// 模糊之下**底边**叠的压字色不透明度。必须是 0：底边要干净地溶解回页面
  /// 本体，否则就是上面说的那条硬边。
  static const double tintAlphaBottom = 0;

  /// 折叠度 → 模糊强度。AppMarket 是整层 alpha 线性淡入
  /// （`graphicsLayer { alpha = scrollBehavior.state.collapsedFraction }`），
  /// 这里同样取线性，只是把「淡入」换成「sigma 生长」—— 见上面的说明。
  static double _intensityFor(double collapsedFraction) =>
      collapsedFraction.clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    // 模糊带跟**顶栏本体等高**：顶栏折叠后高 = 状态栏 + 52dp
    // （flutter_miuix 的 `MiuixTopAppBarDefaults.collapsedHeight`）。
    //
    // 早先按 AppMarket 的 `max(状态栏 × 2, 56dp)` 取带高，比栏矮一截（状态栏
    // 24dp 时差 20dp）—— 带的**下边缘**于是落在标题行中间：那里的内容本来该
    // 是清楚的，却被带着的矩形边界硬生生截断，画面上就是一条横贯全宽的
    // 「分界线」。material 侧的 [GradientBlurPanel] 是铺满整条栏的，下边缘
    // 正好落在栏底（栏外本来就该清晰），所以不会有这个观感。这里对齐栏高。
    //
    // 56dp 兜底：桌面端读不到状态栏 inset（0），别让带子退化成一条细线。
    final bandHeight =
        (MediaQuery.paddingOf(context).top +
                MiuixTopAppBarDefaults.collapsedHeight)
            .clamp(56.0, double.infinity);
    final state = scrollBehavior?.state;

    return Stack(
      children: [
        // 渐进模糊带：画在顶栏**之下**（Stack 先画的在下）。
        //
        // 这里是刻意与 AppMarket 反着的：`HidingMainTabScaffold` 把渐进模糊
        // Box 排在 `TopAppBar` 之后（盖在栏上），因为它那条栏 `title = ""`、
        // 只有会淡出的 largeTitle —— 折叠后栏上没有字，盖住也无所谓。
        // 我们这条栏折叠后是要显示小标题与动作图标的，盖在上面会被
        // surface@30% 洗淡一层，所以带子放在栏下面：内容糊了，字还是清的。
        if (state != null)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: IgnorePointer(
              child: ListenableBuilder(
                listenable: state,
                builder: (context, _) {
                  final t = state.collapsedFraction.clamp(0.0, 1.0);
                  // 一点没滚就直接不画：省掉一次 backdrop 采样 + 两趟着色器。
                  if (t <= 0.001) return const SizedBox.shrink();
                  return _ProgressiveBand(
                    height: bandHeight,
                    intensity: _intensityFor(t),
                    tint: colors.surface,
                  );
                },
              ),
            ),
          ),
        MiuixTopAppBar(
          title: title,
          navigationIcon: navigationIcon,
          actions: actions,
          scrollBehavior: scrollBehavior,
          // 透明只有样式：没有底色、不开毛玻璃、不做大标题模糊
          // （AppMarket 用的是不带模糊的 TopAppBar）。
          color: Colors.transparent,
          blurred: false,
          largeTitleBlurRadius: 0,
        ),
      ],
    );
  }
}

/// 一条渐进模糊带：着色器模糊在下、压字色在上。
///
/// 两层都平铺在带高里，**中间不许插任何 `Opacity` / `ShaderMask` /
/// `ColorFiltered`** —— 见 [MiuixGradientBlurTopBar] 的说明：那会另起
/// backdrop root，模糊就糊不到滚上来的页面内容了。淡入靠 [intensity]
/// 同时调 sigma 与 tint 的 alpha。
///
/// 压字色是**自上而下淡到 0** 的渐变（不是平铺）—— 与 material 侧的
/// [GradientBlurPanel] 同款。平铺会在带的下边缘留下一条分界线，见
/// [MiuixGradientBlurTopBar.tintAlphaTop] 的说明。
class _ProgressiveBand extends StatelessWidget {
  const _ProgressiveBand({
    required this.height,
    required this.intensity,
    required this.tint,
  });

  final double height;

  /// 0 = 完全清晰且透明，1 = 满强度（[MiuixGradientBlurTopBar.maxSigma] +
  /// 顶边 `surface @ tintAlphaTop`）。
  final double intensity;

  /// 压字色的基色（`MiuixColors.surface`）。
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final i = intensity.clamp(0.0, 1.0);
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ProgressiveBlur(
            maxSigma: MiuixGradientBlurTopBar.maxSigma * i,
            direction: ProgressiveBlurDirection.topToBottom,
            falloff: MiuixGradientBlurTopBar.falloff,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  tint.withValues(
                    alpha: MiuixGradientBlurTopBar.tintAlphaTop * i,
                  ),
                  tint.withValues(
                    alpha: MiuixGradientBlurTopBar.tintAlphaBottom * i,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
