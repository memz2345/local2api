// lib/widgets/month_slide_switcher.dart
//
// 月份网格的「整页平移」切换器：新内容从一侧滑入的同时，旧内容向另一侧
// 滑出 —— 与主页底栏切 tab 的 PageView 动画同款（340ms / fastOutSlowIn）。
//
// 为什么不用 AnimatedSwitcher：它的 transitionBuilder 对新旧两份内容共用
// 一条 tween，旧内容只是把同一条动画倒放，会朝**进入方向**退出去（下月时
// 新旧一起向右跑），不是对向滑动。这里显式区分 in/out 两条平移。
//
// 用法：`MonthSlideSwitcher(direction: d, child: KeyedSubtree(key: ..., child: ...))`
// —— child 的 key 一变即触发一轮切换；direction 取 +1（新内容从右进）/
// -1（从左进）/ 0（不做平移，只淡入淡出，用于「今天」这类跳转）。
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'page_switcher.dart' show kPageTransitionCurve, kPageTransitionDuration;

/// 左右滑动切月的手势区。
///
/// 为什么要单独一层：月历是 `GridView`（竖屏还在 `ListView` 里），横向手势
/// 会被纵向滚动抢走，而「慢但拖得远」这类手势光看速度又会漏掉。所以这里
/// 自己挂一个 [PanGestureRecognizer]：
/// - 只在**横向位移占优**时才把手势认下来（`_HorizontalSwipeRecognizer`），
///   纵向滚动照旧归外层 ListView；
/// - 认下来之后「速度过阈值」或「拖够距离」任一满足即翻月，慢拖也认。
///
/// 只包月历网格这一块，别包整页 —— 包整页会把下面当天活动列表的滚动也吃掉。
class MonthSwipeArea extends StatefulWidget {
  const MonthSwipeArea({super.key, required this.onShift, required this.child});

  /// +1 = 下个月（手指向左滑），-1 = 上个月（手指向右滑）。
  final ValueChanged<int> onShift;

  final Widget child;

  /// 判为「横扫」的最小水平速度（逻辑像素/秒）。
  static const double minVelocity = 220;

  /// 判为「横扫」的最小水平位移（慢速长拖也认）。
  static const double minDistance = 70;

  @override
  State<MonthSwipeArea> createState() => _MonthSwipeAreaState();
}

class _MonthSwipeAreaState extends State<MonthSwipeArea> {
  /// 这一轮的累计横向位移。
  double _dx = 0;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.deferToChild,
      gestures: <Type, GestureRecognizerFactory>{
        // 用横向拖拽识别器：它自己只认「横向位移占优」的手势，纵向滚动
        // 照旧归外层 ListView（竞技场判给它）。
        HorizontalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              HorizontalDragGestureRecognizer
            >(
              () => HorizontalDragGestureRecognizer(),
              (HorizontalDragGestureRecognizer r) {
                r.onStart = (_) => _dx = 0;
                r.onUpdate = (d) => _dx += d.delta.dx;
                r.onEnd = (d) {
                  final dx = _dx;
                  if (dx.abs() < MonthSwipeArea.minDistance) return;
                  final v = d.primaryVelocity ?? 0;
                  // 快扫按速度、慢拖按位移；方向都以「手指往哪走」为准：
                  // 手指向左滑（负）是看下一个月。
                  if (v.abs() >= MonthSwipeArea.minVelocity) {
                    widget.onShift(v < 0 ? 1 : -1);
                  } else {
                    widget.onShift(dx < 0 ? 1 : -1);
                  }
                };
              },
            ),
      },
      child: widget.child,
    );
  }
}

class MonthSlideSwitcher extends StatefulWidget {
  const MonthSlideSwitcher({
    super.key,
    required this.direction,
    required this.child,
  });

  /// +1：新内容自右滑入、旧内容向左滑出；-1：方向相反；0：仅淡入淡出。
  final int direction;

  /// 需要带会变化的 Key（如 `ValueKey<DateTime>(month)`）才会触发切换。
  final Widget child;

  @override
  State<MonthSlideSwitcher> createState() => _MonthSlideSwitcherState();
}

class _MonthSlideSwitcherState extends State<MonthSlideSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: kPageTransitionDuration,
    value: 1,
  );

  /// 正在退场的旧内容；动画结束即释放。
  Widget? _outgoing;
  int _dir = 1;

  @override
  void didUpdateWidget(covariant MonthSlideSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.child.key, widget.child.key)) {
      setState(() {
        _outgoing = oldWidget.child;
        _dir = widget.direction;
      });
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = kPageTransitionCurve.transform(
          _controller.value.clamp(0.0, 1.0),
        );
        final outgoing = _outgoing;
        final showOutgoing = outgoing != null && t < 1;

        // 动画跑完把旧内容丢掉，别一直多挂一棵子树。
        if (outgoing != null && t >= 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _controller.value >= 1) {
              setState(() => _outgoing = null);
            }
          });
        }

        if (_dir == 0) {
          // 无方向感的跳转（点「今天」/ 补位格翻月）：只淡入淡出。
          return Stack(
            children: [
              if (showOutgoing)
                Positioned.fill(
                  child: Opacity(opacity: 1 - t, child: outgoing),
                ),
              Opacity(opacity: t, child: widget.child),
            ],
          );
        }

        // 对向平移：in 从 _dir 侧进、out 往 -_dir 侧走（与 PageView 一致）。
        return ClipRect(
          child: Stack(
            children: [
              if (showOutgoing)
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: FractionalTranslation(
                      translation: Offset(-_dir * t, 0),
                      child: outgoing,
                    ),
                  ),
                ),
              FractionalTranslation(
                translation: Offset(_dir * (1 - t), 0),
                child: widget.child,
              ),
            ],
          ),
        );
      },
    );
  }
}
