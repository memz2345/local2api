import 'dart:ui';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/widgets/app_tooltip.dart';
import 'package:local2api/widgets/liquid_glass.dart';
import 'package:local2api/widgets/long_press_glass_tab_switcher.dart';
import 'morph_card.dart';

class MorphIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final double iconSize;

  final bool frosted;

  final bool transparent;

  final Color? iconColor;

  const MorphIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 40.0,
    this.iconSize = 22.0,
    this.frosted = false,
    this.transparent = false,
    this.iconColor,
  });

  @override
  State<MorphIconButton> createState() => _MorphIconButtonState();
}

class _MorphIconButtonState extends State<MorphIconButton> {
  bool _pressed = false;

  bool _pointerDown = false;

  bool get _deformed => _pressed || _pointerDown;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = cs.secondaryContainer;

    final baseColor = widget.transparent
        ? Colors.transparent
        : widget.frosted
        ? cs.surfaceContainer.withValues(alpha: 0.75)
        : base;
    final pressedColor = widget.transparent
        ? Colors.white.withValues(alpha: 0.18)
        : Color.alphaBlend(
            cs.onSecondaryContainer.withValues(alpha: 0.12),
            baseColor,
          );

    final radius = BorderRadius.circular(_deformed ? kIconBtnRadius : 100.0);

    final splashRadius = widget.transparent
        ? BorderRadius.circular(kIconBtnRadius)
        : radius;

    Widget button = AnimatedContainer(
      duration: kMorphDuration,
      curve: kMorphCurve,
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: _deformed ? pressedColor : baseColor,
        borderRadius: radius,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          borderRadius: splashRadius,
          highlightColor: Colors.transparent,

          splashColor: widget.transparent
              ? Colors.white.withValues(alpha: 0.25)
              : cs.onSecondaryContainer.withValues(alpha: 0.3),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Center(
              child: Icon(
                widget.icon,
                size: widget.iconSize,
                color: widget.iconColor ?? cs.onSecondaryContainer,
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.frosted && !widget.transparent) {
      button = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: button,
        ),
      );
    }

    if (widget.tooltip != null) {
      button = AppTooltip(
        message: widget.tooltip!,
        triggerMode: TooltipTriggerMode.longPress,
        child: button,
      );
    }

    button = Listener(
      onPointerDown: (_) => setState(() => _pointerDown = true),
      onPointerUp: (_) => setState(() => _pointerDown = false),
      onPointerCancel: (_) => setState(() => _pointerDown = false),
      child: button,
    );

    return Center(child: button);
  }
}

class FrostedPanel extends StatelessWidget {
  final double blurSigma;

  final double opacity;

  final Color? color;

  final BorderRadius? borderRadius;

  final Widget child;

  const FrostedPanel({
    super.key,
    required this.child,
    this.blurSigma = 10.0,
    this.opacity = 0.7,
    this.color,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final bg = color ?? colorScheme.surfaceContainer.withValues(alpha: opacity);

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      clipBehavior: Clip.hardEdge,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          decoration: BoxDecoration(
            color: bg,

            border: Border.all(color: bg, width: 0.6),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 渐变（渐进）模糊面板 —— AppMarket 顶栏同款效果的 Material 侧实现。
///
/// 一层 [ProgressiveBlur]（vendored 着色器，单 pass 变半径）把栏下的内容从
/// 顶边的满强度模糊溶解到底边的完全清晰，上面再压一道自上而下淡出的色。
/// 与 [FrostedPanel]（均匀模糊 + 平铺半透明色）的区别就在「溶解」：内容滚到
/// 栏下不是撞上一条硬边，而是渐渐糊掉、渐渐透出来。
///
/// **淡入靠 [intensity] 同时调 sigma 与色的 alpha，外面绝不能再套
/// `Opacity` / `AnimatedOpacity` / `ShaderMask` / `ColorFiltered`** ——
/// 那些会 saveLayer 另起一个 backdrop root，里面的 `BackdropFilter` 就只能
/// 糊到这个 layer 组内部的东西（也就是啥都没有），最后画面上只剩一层半透明
/// 色，看着就是「透明、没模糊」。miuix 侧的渐变模糊顶栏原先正是栽在这上面。
class GradientBlurPanel extends StatelessWidget {
  const GradientBlurPanel({
    super.key,
    required this.child,
    this.maxSigma = 12.0,
    this.falloff = 1.2,
    this.tint,
    this.tintAlphaTop = 0.55,
    this.tintAlphaBottom = 0.0,
    this.intensity = 1.0,
    this.borderRadius,
  });

  /// 顶边（满强度端）的模糊 sigma，逻辑像素。0 = 不糊。
  final double maxSigma;

  /// 着色器的渐变 gamma。> 1 把模糊收在顶边附近、下缘溶解得更干净；
  /// 1.2 是 [ProgressiveBlur] 的出厂默认，也是「下缘不留硬切边」的取值。
  final double falloff;

  /// 压字色的基色。null = `colorScheme.surface`。
  final Color? tint;

  /// 压字色在顶边 / 底边的不透明度（再整体乘 [intensity]）。
  final double tintAlphaTop;
  final double tintAlphaBottom;

  /// 0 = 完全清晰且透明（一层都不画），1 = 满强度。跟着滚动折叠度走。
  final double intensity;

  final BorderRadius? borderRadius;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final i = intensity.clamp(0.0, 1.0);
    final base = tint ?? Theme.of(context).colorScheme.surface;

    Widget panel = Stack(
      fit: StackFit.passthrough,
      children: [
        // 一点没滚就整层不画：省掉一次 backdrop 采样 + 两趟着色器。
        if (i > 0.001) ...[
          Positioned.fill(
            child: ProgressiveBlur(
              maxSigma: maxSigma * i,
              direction: ProgressiveBlurDirection.topToBottom,
              falloff: falloff,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    base.withValues(alpha: tintAlphaTop * i),
                    base.withValues(alpha: tintAlphaBottom * i),
                  ],
                ),
              ),
            ),
          ),
        ],
        child,
      ],
    );

    final radius = borderRadius;
    if (radius != null && radius != BorderRadius.zero) {
      panel = ClipRRect(
        borderRadius: radius,
        clipBehavior: Clip.hardEdge,
        child: panel,
      );
    }
    return panel;
  }
}

class FrostedSheet extends StatelessWidget {
  final Widget child;

  final BorderRadius borderRadius;

  final double blurSigma;

  final double opacity;

  final Color? color;

  final double stretch;

  const FrostedSheet({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.vertical(top: Radius.circular(24)),
    this.blurSigma = 12.0,
    this.opacity = 0.75,
    this.color,
    this.stretch = 0.3,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final legacyColor = (color ?? cs.surfaceContainerLow).withValues(
      alpha: opacity,
    );
    if (!SettingsService.fragmentRenderingEnabled) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(color: legacyColor, child: child),
        ),
      );
    }
    final radius = borderRadius.topLeft.x;
    return GlassShellStretch(
      stretch: stretch,
      shell: ClipRRect(
        borderRadius: borderRadius,
        child: NaviGlass(
          radius: radius,
          blur: blurSigma,
          child: const SizedBox.expand(),
        ),
      ),
      content: child,
    );
  }
}

class ScrollableTabRow extends StatefulWidget {
  const ScrollableTabRow({
    super.key,
    required this.tabs,
    this.padding = EdgeInsets.zero,
  });

  final List<Widget> tabs;
  final EdgeInsetsGeometry padding;

  @override
  State<ScrollableTabRow> createState() => _ScrollableTabRowState();
}

class _ScrollableTabRowState extends State<ScrollableTabRow> {
  late final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;

    final delta = event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (delta == 0) return;
    final pos = _controller.position;
    final target = (pos.pixels + delta).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    _controller.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Listener(
          onPointerSignal: _onPointerSignal,
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Padding(
                padding: widget.padding,
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: widget.tabs,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class FrostedSearchHeader extends StatelessWidget {
  final bool collapsed;

  final ValueListenable<double>? progressListenable;

  final Widget searchBar;

  final List<Widget> tabs;

  final Widget? tabRow;

  final List<GlassTab>? glassTabs;

  final int? glassSelectedIndex;

  final ValueChanged<int>? onGlassTabSelected;

  final double tabBarHeight;

  const FrostedSearchHeader({
    super.key,
    this.collapsed = false,
    this.progressListenable,
    required this.searchBar,
    this.tabs = const [],
    this.tabRow,
    this.glassTabs,
    this.glassSelectedIndex,
    this.onGlassTabSelected,
    this.tabBarHeight = 48.0,
  });

  @override
  Widget build(BuildContext context) {
    return FrostedPanel(
      opacity: 0.75,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (progressListenable != null)
              ValueListenableBuilder<double>(
                valueListenable: progressListenable!,
                builder: (context, p, child) => _collapseBar(1 - p, child!),
                child: searchBar,
              )
            else
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: collapsed ? 0.0 : 1.0),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                builder: (context, value, child) => _collapseBar(value, child!),
                child: searchBar,
              ),

            ClipRect(
              child: SizedBox(
                height: tabBarHeight,
                width: double.infinity,
                child: tabRow ?? _buildTabs(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _collapseBar(double value, Widget child) {
    final v = value.clamp(0.0, 1.0);
    return ClipRect(
      child: Align(
        heightFactor: v,
        alignment: Alignment.topCenter,
        child: FractionalTranslation(
          translation: Offset(0, -(1 - v)),
          child: Opacity(opacity: v, child: child),
        ),
      ),
    );
  }

  Widget _buildTabs(BuildContext context) {
    final normalTabs = ScrollableTabRow(tabs: tabs);
    final glassTabs = this.glassTabs;
    final glassIndex = glassSelectedIndex;
    final onGlassTabSelected = this.onGlassTabSelected;
    if (glassTabs == null ||
        glassIndex == null ||
        onGlassTabSelected == null ||
        glassTabs.isEmpty) {
      return normalTabs;
    }
    return LongPressGlassTabSwitcher(
      tabs: glassTabs,
      selectedIndex: glassIndex,
      onIndexChanged: onGlassTabSelected,
      barHeight: tabBarHeight - 4,
      child: normalTabs,
    );
  }
}

class ExpressiveSliverAppBar extends StatelessWidget {
  final String title;

  final Widget? leading;

  final List<Widget>? actions;

  final double expandedHeight;

  final bool pinned;

  final TextStyle? expandedTitleStyle;

  final TextStyle? collapsedTitleStyle;

  final double blurSigma;

  final double blurOpacity;

  final VoidCallback? onTitleRepeatedTap;

  const ExpressiveSliverAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.expandedHeight = 152.0,
    this.pinned = true,
    this.expandedTitleStyle,
    this.collapsedTitleStyle,
    this.blurSigma = 10.0,
    this.blurOpacity = 0.7,
    this.onTitleRepeatedTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const leadingWidth = 48.0;
    const dur = Duration(milliseconds: 260);
    const curve = Curves.easeInOut;

    final hasLeading = leading != null;
    final topInset = MediaQuery.paddingOf(context).top;
    // 渐变模糊档（设置 + 渲染路径支持着色器）；两套风格共用一个判断。
    final progressive = progressiveTopBarOf(context);
    return SliverAppBar(
      pinned: pinned,
      leading: leading,
      automaticallyImplyLeading: hasLeading,
      actions: actions,
      backgroundColor: Colors.transparent,

      expandedHeight: expandedHeight + topInset,
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final safePadding = MediaQuery.of(context).padding;
          final collapsedHeight = kToolbarHeight + safePadding.top;
          final isCollapsed = constraints.biggest.height <= collapsedHeight;
          // 折叠度：0 = 完全展开，1 = 完全折叠。渐变模糊档用它连续驱动
          // sigma 与压字色，比原来「到阈值就整块淡入」跟手。
          final expandable = expandedHeight + topInset - collapsedHeight;
          final collapsedFraction = expandable <= 0
              ? (isCollapsed ? 1.0 : 0.0)
              : ((expandedHeight + topInset - constraints.biggest.height) /
                        expandable)
                    .clamp(0.0, 1.0);

          Widget titleRow() => SafeArea(
            bottom: false,
            child: Row(
              children: [
                SizedBox(
                  width: hasLeading
                      ? leadingWidth + safePadding.left + 12.0
                      : 8.0,
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: onTitleRepeatedTap,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          collapsedTitleStyle ??
                          TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                    ),
                  ),
                ),

                SizedBox(width: (actions?.length ?? 0) * 48.0 + 16.0),
              ],
            ),
          );

          return Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: collapsedHeight,
                // 渐变模糊档不能用 AnimatedOpacity 包住整块面板 —— 那会
                // saveLayer 另起 backdrop root，模糊就糊不到栏下的内容了。
                // 改成让面板自己的 intensity 跟着折叠度走，只给**文字**
                // 套一层 Opacity（文字里没有 BackdropFilter，安全）。
                child: progressive
                    ? GradientBlurPanel(
                        intensity: collapsedFraction,
                        maxSigma: blurSigma,
                        tintAlphaTop: blurOpacity,
                        child: Opacity(
                          opacity: collapsedFraction,
                          child: titleRow(),
                        ),
                      )
                    : AnimatedOpacity(
                        opacity: isCollapsed ? 1 : 0,
                        duration: dur,
                        curve: curve,
                        child: FrostedPanel(
                          blurSigma: blurSigma,
                          opacity: blurOpacity,
                          child: titleRow(),
                        ),
                      ),
              ),

              AnimatedOpacity(
                opacity: isCollapsed ? 0 : 1,
                duration: dur,
                curve: curve,
                child: AnimatedContainer(
                  duration: dur,
                  curve: curve,
                  alignment: Alignment.bottomLeft,

                  padding: EdgeInsets.only(
                    left: 16.0,
                    top: safePadding.top,
                    bottom: 28.0,
                  ),
                  child: GestureDetector(
                    onTap: onTitleRepeatedTap,
                    child: Text(
                      title,
                      style:
                          expandedTitleStyle ??
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
                          ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
