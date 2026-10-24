// lib/widgets/frosted_page_bar.dart
//
// NaviFlash「分区 / 消息」同款毛玻璃顶栏，移植自 naviflashv2 的
// widgets/frosted_page_bar.dart + msg_feed_common.dart 的顶栏行，
// 滚动折叠行为取 screens/bilibili_region_categories_page.dart 的 _buildTopBar。
//
// 观感要点（都和「普通 AppBar」不一样，别改回 Material 默认）：
// - 顶栏不是 Scaffold.appBar，而是悬浮在内容之上的一层：内容铺满整页、
//   滚动时从顶栏下面穿过，BackdropFilter 才有东西可糊，才是「透明毛玻璃」；
//   用 Scaffold.appBar 的话顶栏下面是一块不透明条，滚动内容永远钻不进去。
// - 因此首屏必须自己垫 [frostedPageBarInset] 的顶部占位，否则第一行被压住。
// - 标题行往下滚过阈值整行收掉、往上滚或回到顶部立刻放回（分区同款），
//   收放用的是 Align.heightFactor 而不是改高度，所以不会跳布局。

import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/widgets/expressive_app_bar.dart';
import 'package:local2api/widgets/liquid_glass.dart' show progressiveTopBarOf;
import 'package:local2api/widgets/page_background.dart';

/// 顶栏净高（不含状态栏），与 NaviFlash kFrostedPageBarHeight 一致。
const double kFrostedPageBarHeight = 56.0;

/// 往下滚过这么多像素才收标题行（分区页 kCollapseThreshold 同款）。
const double kFrostedBarCollapseThreshold = 120.0;

/// 内容需要垫的顶部占位：状态栏 + 标题行 + 可选的下方附加行（如 TabBar）。
///
/// 顶栏本体套了 SafeArea，所以这里必须把状态栏 inset 一起算上，
/// 只算 56 的话首行会钻到毛玻璃底下。
double frostedPageBarInset(BuildContext context, {double bottomHeight = 0}) =>
    MediaQuery.paddingOf(context).top + kFrostedPageBarHeight + bottomHeight;

/// 毛玻璃顶栏本体：返回键 + 标题 + 右侧动作，可挂下方附加行。
class FrostedPageBar extends StatelessWidget {
  const FrostedPageBar({
    super.key,
    required this.title,
    this.actions = const [],
    this.leading,
    this.bottom,
    this.bottomHeight = 0,
    this.titleCollapsed = false,
  });

  final String title;

  /// 右侧动作，用 MorphIconButton 才和左上返回键同一套变形手感。
  final List<Widget> actions;

  /// 自定义左上按钮；为空时给默认返回箭头。
  final Widget? leading;

  /// 顶栏下方的附加行（TabBar 等），和标题行包在同一块毛玻璃里。
  final Widget? bottom;
  final double bottomHeight;

  /// 标题行是否收起（分区同款滚动折叠，由 [FrostedBarPage] 驱动）。
  final bool titleCollapsed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final content = SafeArea(
      bottom: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: titleCollapsed ? 0.0 : 1.0),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            builder: (context, value, child) => ClipRect(
              child: Align(
                heightFactor: value,
                alignment: Alignment.topCenter,
                child: child,
              ),
            ),
            child: SizedBox(
              height: kFrostedPageBarHeight,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  leading ??
                      MorphIconButton(
                        icon: Icons.arrow_back,
                        tooltip: AppLocalizations.of(context).startScreenGoBack,
                        onTap: () => Navigator.of(context).maybePop(),
                        transparent: true,
                      ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  ...actions,
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          if (bottom != null) SizedBox(height: bottomHeight, child: bottom),
        ],
      ),
    );

    // 渐变模糊档（AppMarket 同款）：顶边满强度往下溶解到清晰，压字色也从
    // 0.75 淡到 0 —— 内容滚到栏下是渐渐糊掉，不是撞上一条硬边。
    // 这条栏常驻在滚动内容之上，所以 intensity 恒为 1，不跟折叠度走。
    if (progressiveTopBarOf(context)) {
      return GradientBlurPanel(
        maxSigma: 12,
        tintAlphaTop: 0.75,
        child: content,
      );
    }
    return FrostedPanel(opacity: 0.75, blurSigma: 12, child: content);
  }
}

/// 带毛玻璃顶栏的页面壳：背景画布 + 铺满内容 + 悬浮顶栏 + 滚动折叠。
///
/// [child] 内部的滚动视图自己垫 [frostedPageBarInset] 的顶部占位。
class FrostedBarPage extends StatefulWidget {
  const FrostedBarPage({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.leading,
    this.bottom,
    this.bottomHeight = 0,
    this.collapseOnScroll = false,
    this.floatingActionButton,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final Widget? leading;
  final Widget? bottom;
  final double bottomHeight;

  /// 顶栏是否随下拉滚动收起。**默认常驻**：Material 版不再做「上滑收标题、
  /// 下滑放回来」的花活 —— 滚动时标题行突然消失会让返回键跟着跳，体验更差。
  /// 仍保留这个开关，个别页面想用折叠效果可以显式打开。
  final bool collapseOnScroll;

  final Widget? floatingActionButton;

  @override
  State<FrostedBarPage> createState() => _FrostedBarPageState();
}

class _FrostedBarPageState extends State<FrostedBarPage> {
  bool _collapsed = false;

  bool _onScrollNotification(ScrollNotification n) {
    if (!widget.collapseOnScroll || n is! ScrollUpdateNotification) {
      return false;
    }
    final delta = n.scrollDelta ?? 0;
    var collapsed = _collapsed;
    if (delta > 0 && n.metrics.extentBefore > kFrostedBarCollapseThreshold) {
      collapsed = true;
    } else if (delta < 0 || n.metrics.extentBefore < 1) {
      collapsed = false;
    }
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainer,
      floatingActionButton: widget.floatingActionButton,
      body: Stack(
        children: [
          Positioned.fill(
            child: PageBackground(baseColor: cs.surfaceContainer),
          ),
          Positioned.fill(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
              child: widget.child,
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: FrostedPageBar(
              title: widget.title,
              actions: widget.actions,
              leading: widget.leading,
              bottom: widget.bottom,
              bottomHeight: widget.bottomHeight,
              titleCollapsed: _collapsed,
            ),
          ),
        ],
      ),
    );
  }
}
