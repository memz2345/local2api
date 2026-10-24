import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

/// 可折叠大标题的滚动行为（项目版）：补上 flutter_miuix 短页面缺的那半截。
///
/// 背景：flutter_miuix 的 [MiuixExitUntilCollapsedScrollBehavior] 对「内容不满
/// 一屏」的短页面走 `_handleShortPageScroll`，折叠量按 `pixels -
/// minScrollExtent` 记账。但项目统一用 `ClampingScrollPhysics`（下拉刷新与
/// 越界位移都要靠 `OverscrollNotification`，不能用允许越界的物理），短页面
/// 的 pixels 永远钉在 0，上拉只剩一条 OverscrollNotification（视觉位移由
/// `MiuixOverscrollIndicator` 画），标题就**完全不折叠** —— 和 InstallerX /
/// 原版 miuix 的嵌套滚动语义（顶栏直接吃掉列表没消费掉的那段越界量）对不上。
///
/// 补法：短页面下，手指拖动产生的未消费越界量按 1:1 记进折叠量 ——
/// `overscroll > 0`（内容向上越界 / 往下拽列表）→ 折叠，
/// `overscroll < 0`（顶部下拉）→ 展开；松手仍交给父类的短页吸附逻辑，
/// 按 [MiuixTopAppBarDefaults.titleCoverHandoff]（50%）停靠到近端，
/// 不会停在半折叠态。
///
/// 长页面不掺和：越界只发生在列表两端，折叠量已由父类的位置同步管住，
/// 这里再记一次会双倍记账（顶部回弹时标题会抖）。
class MiuixShortPageScrollBehavior
    extends MiuixExitUntilCollapsedScrollBehavior {
  MiuixShortPageScrollBehavior({
    super.state,
    super.canScroll,
    super.snapOnRelease,
    super.snapDuration,
    super.snapCurve,
    super.lockSmallTitleUntilTop,
  });

  /// 最近一次滚动体的 metrics（[MiuixShortPageScrollListener] 从
  /// `ScrollMetricsNotification` 喂进来），用来判断是不是短页面。
  ScrollMetrics? _metrics;

  void observeMetrics(ScrollMetrics metrics) => _metrics = metrics;

  /// 桌面端鼠标滚轮的折叠补丁。
  ///
  /// 触屏拖动靠 [handleScroll] 里的越界记账折叠；但滚轮走的是
  /// `ScrollPosition.pointerScroll`，目标位置被直接钳在 `[min, max]` 内 ——
  /// 短页面 max == min，滚轮在边界上**一条通知都不会发**，折叠量就没账可记。
  /// 这里在指针层直接补：短页面（可滚行程 < 展开量）时把滚轮增量按 1:1
  /// 记进折叠量；长页面的折叠仍由位置同步管，这里不掺和。
  void foldByPointerScroll(double dy) {
    if (dy == 0) return;
    final limit = state.heightOffsetLimit;
    if (!limit.isFinite || limit >= 0) return;
    final expansion = -limit;
    final metrics = _metrics;
    if (metrics != null &&
        (metrics.maxScrollExtent - metrics.minScrollExtent) >=
            expansion - 1.0) {
      return; // 长页面：位置同步已经覆盖，别再记一遍
    }
    // setter 自带钳制到 [limit, 0]：折到底就停住，反向滚就逐步恢复。
    state.heightOffset = state.heightOffset - dy;
  }

  @override
  bool handleScroll(ScrollNotification n) {
    super.handleScroll(n);
    if (n is OverscrollNotification) {
      _foldByOverscroll(n);
    }
    return false;
  }

  /// 把未消费的越界量直接记进折叠量（等价原版嵌套滚动的 onPostScroll 段）。
  void _foldByOverscroll(OverscrollNotification n) {
    // 只看直接子滚动体的竖向滚动，跟父类同一套过滤。
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return;
    // 只跟手指：惯性 / 吸附动画引发的越界（dragDetails 为空）不算，
    // 否则松手后的回弹动画会把标题又拽回去。
    if (n.dragDetails == null) return;
    final limit = state.heightOffsetLimit;
    // 展开量还没测出来（-∞），或 SmallTopAppBar 把上限钉成 0（pinned）。
    if (!limit.isFinite || limit >= 0) return;
    final expansion = -limit;
    if ((n.metrics.maxScrollExtent - n.metrics.minScrollExtent) >=
        expansion - 1.0) {
      return; // 长页面：位置同步已经覆盖，别再记一遍
    }
    // setter 自带钳制到 [limit, 0]：折到底就停住，往下拽就逐步恢复。
    state.heightOffset = state.heightOffset - n.overscroll;
  }
}

/// [MiuixShortPageScrollBehavior] 专用的滚动接线（比包版的
/// `MiuixScrollBehaviorListener` 多干两件事）：
///
/// 1. 把 `ScrollMetricsNotification`（布局/尺寸变化时必发）喂给
///    [MiuixShortPageScrollBehavior.observeMetrics]，让 behavior 能判断
///    当前是不是短页面；
/// 2. 在指针层监听滚轮事件，短页面下由
///    [MiuixShortPageScrollBehavior.foldByPointerScroll] 折叠大标题 ——
///    触屏拖动的折叠仍走包版那条 `OverscrollNotification` 通路。
///
/// 短页面（实验室 / SillyTavern 设置等）用这个替换包版监听器即可，
/// 构造参数一致，是个 drop-in。
class MiuixShortPageScrollListener extends StatelessWidget {
  const MiuixShortPageScrollListener({
    super.key,
    required this.behavior,
    required this.child,
  });

  final MiuixShortPageScrollBehavior behavior;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<Notification>(
      onNotification: (notification) {
        if (notification is ScrollMetricsNotification) {
          behavior.observeMetrics(notification.metrics);
        } else if (notification is ScrollNotification) {
          behavior.handleScroll(notification);
        }
        return false;
      },
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            behavior.foldByPointerScroll(event.scrollDelta.dy);
          }
        },
        child: child,
      ),
    );
  }
}
