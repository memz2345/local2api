import 'dart:ui';

import 'package:flutter/material.dart';

/// Metro 磁贴式按压倾斜（移植自 naviflashv2 的 `MetroTileInteraction`，
/// 即 B 站视频卡片的「按下绕触点 3D 倾斜、随手指实时跟随、松手回弹」手感）。
///
/// 与 miuix 的 tilt 反馈（MiuixTiltCard）不是一回事：miuix tilt 触点只取
/// 象限、角度锁死；这里是连续的——触点相对卡片中心的偏移直接映射成倾角
/// （最多 ±0.12 弧度），手指在卡内移动时倾斜跟着走，松手 easeOutBack 弹回。
///
/// 手势用 pan 组而非 tap 组：子级的轻点/长按/右键赢得竞技场时，本组的
/// [onTapCancel] 会触发并复位倾斜，不干扰卡片原有点击行为。
/// [onTapStart] 在「按住原地松开」时回调锁定的倾角（视频卡片用来做
/// 点开时的动效起点），本项目用不到，参数留空即可。
class MetroTileInteraction extends StatefulWidget {
  const MetroTileInteraction({
    super.key,
    required this.child,
    this.onTapStart,
    this.showBorder = true,
    this.pressScale = 0.96,
  });

  final Widget child;

  /// 松手（未发生拖动）时回调当前锁定的倾角。
  final void Function(double rotateY, double rotateX)? onTapStart;

  /// 按压/悬停时是否显示白色描边。视频卡片关闭描边：保留卡片自身
  /// 圆角与 ripple，不在卡片上叠加方角描边（圆角不统一）。
  final bool showBorder;

  /// 按压时缩放到该值（1.0 = 不缩放，仅倾斜）。视频卡片只保留倾斜
  /// 手感，传 1.0 去掉「被压一下」的缩放。
  final double pressScale;

  @override
  State<MetroTileInteraction> createState() => _MetroTileInteractionState();
}

class _MetroTileInteractionState extends State<MetroTileInteraction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;
  double _currentRotateX = 0.0;
  double _currentRotateY = 0.0;
  double _scale = 1.0;
  double _lockedRotateX = 0.0;
  double _lockedRotateY = 0.0;
  bool _isHovering = false;
  bool _isPressed = false;
  bool _isInside = false;
  bool _panAccepted = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      reverseDuration: const Duration(milliseconds: 300),
    );
    _curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutBack,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _calculateLockTilt(Offset localPos, Size size) {
    final double centerX = size.width / 2;
    final double centerY = size.height / 2;
    final double percentX = ((localPos.dx - centerX) / centerX).clamp(
      -1.2,
      1.2,
    );
    final double percentY = ((localPos.dy - centerY) / centerY).clamp(
      -1.2,
      1.2,
    );
    _lockedRotateY = -percentX * 0.12;
    _lockedRotateX = percentY * 0.12;
    setState(() {
      _currentRotateY = _lockedRotateY;
      _currentRotateX = _lockedRotateX;
      _scale = widget.pressScale;
    });
  }

  void _handlePanDown(DragDownDetails details) {
    _panAccepted = false;
    setState(() {
      _isPressed = true;
      _isInside = true;
    });
    final RenderBox box = context.findRenderObject() as RenderBox;
    _calculateLockTilt(details.localPosition, box.size);
    _controller.forward();
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset localPos = details.localPosition;
    final bool isCurrentlyInside =
        localPos.dx >= 0 &&
        localPos.dx <= box.size.width &&
        localPos.dy >= 0 &&
        localPos.dy <= box.size.height;
    if (isCurrentlyInside != _isInside) {
      setState(() => _isInside = isCurrentlyInside);
      if (isCurrentlyInside) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
    if (isCurrentlyInside) {
      // 手指/鼠标在卡片内移动时，倾斜实时跟随当前指针位置
      // （而不是停留在按下瞬间的锁定值）
      _calculateLockTilt(localPos, box.size);
    }
  }

  void _handleRelease() {
    if (!_isPressed) return;
    // 拖动进行中（pan 已赢得竞技场）：倾斜正在实时跟随指针，
    // 此时子级 tap 被取消触发的 release 不应打断，等真正松手再恢复
    if (_panAccepted) return;
    setState(() => _isPressed = false);
    if (_isInside) widget.onTapStart?.call(_lockedRotateY, _lockedRotateX);
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onPanDown: _handlePanDown,
        onPanStart: (_) => _panAccepted = true,
        onPanUpdate: _handlePanUpdate,
        onPanEnd: (_) {
          _panAccepted = false;
          _handleRelease();
        },
        onPanCancel: () {
          _panAccepted = false;
          _handleRelease();
        },
        // 子手势（轻点/长按/右键）赢得竞技场时本组 tap 被拒绝，
        // onTapCancel 会触发 → 重置倾斜状态，不干扰卡片原有行为
        onTapCancel: _handleRelease,
        child: AnimatedBuilder(
          animation: _curve,
          builder: (context, child) => Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0008)
              ..scaleByDouble(lerpDouble(1.0, _scale, _curve.value)!, 1, 1, 1)
              ..rotateX(_currentRotateX * _curve.value)
              ..rotateY(_currentRotateY * _curve.value),
            child: Stack(
              children: [
                widget.child,
                if (widget.showBorder && (_isHovering || _isPressed))
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
