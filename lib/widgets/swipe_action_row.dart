import 'package:flutter/material.dart';

/// 「左滑删除」的一行（照用户给的 UITEST.html 那套手感做的）。
///
/// 机制与参考实现一一对应：
/// - 右侧固定着一条**动作胶囊**，宽度**跟着滑动距离实时增长**（左缘贴着卡片
///   右缘），所以拖动过程中看到的是「胶囊从右边长出来」而不是固定槽位。
/// - 卡片跟手左移；胶囊里的图标在滑过 30px 后渐显 + 放大，滑到阈值时完全显形。
/// - 松手判定：滑过**行宽的 35%**（或速度够快且滑过 24px）= 提交；
///   提交时卡片飞出屏幕左侧、胶囊一路铺满整行、图标淡出，随后行高收到 0。
/// - 没到阈值就按同一条缓动弹回（卡片回位 + 胶囊缩回 0）。
///
/// 提交是**不可逆的视觉过程**，但业务动作放在最后：[onCommit] 在收起动画
/// 跑完之后才回调，调用方那时再去改数据 + 弹「已删除 / 恢复」。
/// 这样动画期间行还在列表里，下面的行会平滑上移，而不是突然跳一下。
class SwipeActionRow extends StatefulWidget {
  const SwipeActionRow({
    super.key,
    required this.child,
    required this.actionIcon,
    required this.actionColor,
    required this.onCommit,
    this.actionInset = 5,
    this.foregroundCornerRadius = 16,
    this.thresholdFraction = 0.35,
    this.gapBottom = 8,
    this.semanticLabel,
  });

  /// 前景内容（整行卡片），会跟着手指左移。
  final Widget child;

  final IconData actionIcon;

  /// 动作胶囊的底色（删除用主题 error 色）。
  final Color actionColor;

  /// 收起动画结束后回调 —— 调用方在这里真正删数据、弹 snackbar。
  final VoidCallback onCommit;

  /// 胶囊上下各留多少（参考图是 5px）。
  final double actionInset;

  /// 前景卡片的圆角（拖动时给它加一层投影用）。
  final double foregroundCornerRadius;

  /// 触发阈值占行宽的比例（参考图 0.35）。
  final double thresholdFraction;

  /// 行间距：跟着收起动画一起收到 0。
  final double gapBottom;

  final String? semanticLabel;

  @override
  State<SwipeActionRow> createState() => SwipeActionRowState();
}

enum _Phase { idle, dragging, reverting, committing, done }

class SwipeActionRowState extends State<SwipeActionRow>
    with TickerProviderStateMixin {
  /// 前景卡片的位移（px，向左为正）。
  late final AnimationController _offset = AnimationController.unbounded(
    vsync: this,
  );

  /// 胶囊宽度（px）。拖动/回弹时与 [_offset] 同步；提交时独立铺满整行。
  late final AnimationController _pill = AnimationController.unbounded(
    vsync: this,
  );

  /// 提交阶段图标的淡出（1 → 0）。
  late final AnimationController _icon = AnimationController(
    vsync: this,
    value: 1,
  );

  /// 行高收起（1 → 0）。
  late final AnimationController _collapse = AnimationController(
    vsync: this,
    value: 1,
  );

  _Phase _phase = _Phase.idle;
  double _rowWidth = 0;

  @override
  void dispose() {
    _offset.dispose();
    _pill.dispose();
    _icon.dispose();
    _collapse.dispose();
    super.dispose();
  }

  bool get _busy => _phase != _Phase.idle && _phase != _Phase.dragging;

  double get _threshold => _rowWidth * widget.thresholdFraction;

  /// 图标渐显进度：滑过 30px 才开始，到阈值完全显形。
  double get _iconProgress {
    if (_phase == _Phase.committing || _phase == _Phase.done) return 0;
    final start = 30.0;
    final end = _threshold <= start ? start + 1 : _threshold;
    return ((_offset.value - start) / (end - start)).clamp(0.0, 1.0);
  }

  void _onDragStart(DragStartDetails _) {
    if (_busy) return;
    _phase = _Phase.dragging;
    setState(() {});
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_phase != _Phase.dragging) return;
    // 只认左滑；右滑不动（右侧胶囊本来就只往左露）
    final next = (_offset.value - d.primaryDelta!).clamp(0.0, _rowWidth);
    _offset.value = next;
    _pill.value = next;
  }

  void _onDragEnd(DragEndDetails d) {
    if (_phase != _Phase.dragging) return;
    final v = d.primaryVelocity ?? 0;
    // 位移过阈值，或甩得够快又已经滑出一点 —— 与参考实现的 (d > 35% ||
    // vx < -0.5px/ms && d > 24px) 等价
    final commit =
        _offset.value > _threshold || (v < -500 && _offset.value > 24);
    if (commit) {
      _commit();
    } else {
      _revert();
    }
  }

  /// 未达阈值：卡片弹回 + 胶囊缩回（参考图 .38s / .32s 那条 cubic）。
  void _revert() {
    _phase = _Phase.reverting;
    setState(() {});
    const curve = Cubic(0.25, 0.8, 0.25, 1);
    _offset.animateTo(
      0,
      duration: const Duration(milliseconds: 380),
      curve: curve,
    );
    _pill
        .animateTo(0, duration: const Duration(milliseconds: 320), curve: curve)
        .whenComplete(() {
          if (mounted) setState(() => _phase = _Phase.idle);
        });
  }

  /// 达阈值：飞出 + 胶囊铺满 + 收起行高，最后回调业务。
  Future<void> _commit() async {
    if (_busy) return;
    setState(() => _phase = _Phase.committing);
    const curve = Cubic(0.4, 0, 0.2, 1);
    const fly = Duration(milliseconds: 300);

    // 图标先退场（参考图 .15s）
    _icon.animateTo(0, duration: const Duration(milliseconds: 150));

    final flyDone = _offset.animateTo(
      _rowWidth * 1.15,
      duration: fly,
      curve: curve,
    );
    // 从当前宽度平滑铺满整行
    final pillDone = _pill.animateTo(_rowWidth, duration: fly, curve: curve);
    await Future.wait([flyDone, pillDone]);
    if (!mounted) return;

    // 收起：高度与行距一起到 0
    await _collapse.animateTo(
      0,
      duration: const Duration(milliseconds: 340),
      curve: curve,
    );
    if (!mounted) return;
    setState(() => _phase = _Phase.done);
    widget.onCommit();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _rowWidth = constraints.maxWidth;
        return SizeTransition(
          sizeFactor: _collapse,
          // 收起时对齐上边：下面的行才是「顶上来」而不是「往下缩」
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: widget.gapBottom),
            child: AnimatedBuilder(
              animation: Listenable.merge([_offset, _pill, _icon]),
              builder: (context, child) {
                final dragging = _phase == _Phase.dragging;
                final progress = _iconProgress;
                final pillWidth = _pill.value.clamp(0.0, _rowWidth);
                return Stack(
                  children: [
                    // 动作胶囊：贴右缘、宽度跟手、两端全圆角、图标居中
                    if (pillWidth > 0)
                      Positioned(
                        top: widget.actionInset,
                        bottom: widget.actionInset,
                        right: 0,
                        width: pillWidth,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: ColoredBox(
                            color: widget.actionColor,
                            child: Center(
                              child: Opacity(
                                opacity: _icon.value * progress,
                                child: Transform.scale(
                                  scale: 0.5 + 0.5 * progress,
                                  child: Icon(
                                    widget.actionIcon,
                                    size: 46,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Transform.translate(
                      offset: Offset(-_offset.value, 0),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: _onDragStart,
                        onHorizontalDragUpdate: _onDragUpdate,
                        onHorizontalDragEnd: _onDragEnd,
                        // 拖动时给卡片一点投影（参考图的 .dragging 阴影）
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              widget.foregroundCornerRadius,
                            ),
                            boxShadow: dragging
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.14,
                                      ),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ]
                                : null,
                          ),
                          child: child,
                        ),
                      ),
                    ),
                  ],
                );
              },
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}
