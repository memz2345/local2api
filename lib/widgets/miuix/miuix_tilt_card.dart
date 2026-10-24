import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';

/// 自制的 miuix Card：修掉包版 [MiuixCard] 在 tilt 按压反馈下「只有内容倾斜、
/// 卡片本体不倾斜」的问题。
///
/// 包版的结构是 Transform 包住卡片、ClipRRect 再包住 Transform——裁切在
/// 变换**外面**且不随之下动，所以背景被钉死在原位，看起来只有内容在动。
/// Compose 原版（`Card.kt`）里 `modifier.pressable(...)` 挂在
/// `squircleSurface` **之前**，也就是先裁切、后变换：卡面（背景+内容）
/// 作为一个整体绕触点对角倾斜，轮廓跟着动。
///
/// 这里照 Compose 的顺序重排：DecoratedBox(背景) → ClipPath(squircle) →
/// Transform(tilt/sink) → 按压遮罩 → 手势/焦点/语义。
/// 其余行为（spring 规格、按压透明度、squircle、MiuixContentColor）与包版一致。
class MiuixTiltCard extends StatefulWidget {
  const MiuixTiltCard({
    super.key,
    this.cornerRadius = MiuixCardDefaults.cornerRadius,
    this.insideMargin = MiuixCardDefaults.insideMargin,
    this.colors,
    this.onPressed,
    this.onLongPress,
    this.feedbackType = MiuixPressFeedbackType.none,
    this.child,
  });

  final double cornerRadius;
  final EdgeInsetsGeometry insideMargin;
  final MiuixCardColors? colors;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final MiuixPressFeedbackType feedbackType;
  final Widget? child;

  @override
  State<MiuixTiltCard> createState() => _MiuixTiltCardState();
}

class _MiuixTiltCardState extends State<MiuixTiltCard>
    with TickerProviderStateMixin {
  static const double _kHoverAlphaDelta = 0.06;
  static const double _kFocusAlphaDelta = 0.08;
  static const double _kPressAlphaDelta = 0.10;

  bool _isPressed = false;
  bool _isHovered = false;
  bool _isFocused = false;

  late final AnimationController _overlayController;
  late final AnimationController _sinkController;
  late final AnimationController _tiltXController;
  late final AnimationController _tiltYController;
  double _tiltXTarget = 0;
  double _tiltYTarget = 0;
  Alignment _tiltOrigin = Alignment.center;

  @override
  void initState() {
    super.initState();
    _overlayController = AnimationController.unbounded(vsync: this);
    _sinkController = AnimationController.unbounded(vsync: this)..value = 1.0;
    _tiltXController = AnimationController.unbounded(vsync: this);
    _tiltYController = AnimationController.unbounded(vsync: this);
  }

  @override
  void dispose() {
    _overlayController.dispose();
    _sinkController.dispose();
    _tiltXController.dispose();
    _tiltYController.dispose();
    super.dispose();
  }

  bool get _enabled => widget.onPressed != null || widget.onLongPress != null;

  double get _targetOverlayAlpha {
    var alpha = 0.0;
    if (_isHovered) alpha += _kHoverAlphaDelta;
    if (_isFocused) alpha += _kFocusAlphaDelta;
    if (_isPressed) alpha += _kPressAlphaDelta;
    return alpha;
  }

  void _animateOverlay(SpringDescription spring) {
    _overlayController.animateWith(
      _SpringSimulation(
        spring,
        start: _overlayController.value,
        end: _targetOverlayAlpha,
      ),
    );
  }

  void _animateSink() {
    _sinkController.animateWith(
      _SpringSimulation(
        folmeSpring(damping: 0.8, response: 0.4),
        start: _sinkController.value,
        end: _isPressed ? 0.94 : 1.0,
      ),
    );
  }

  void _animateTilt() {
    final tx = _isPressed ? _tiltXTarget : 0.0;
    final ty = _isPressed ? _tiltYTarget : 0.0;
    _tiltXController.animateWith(
      _SpringSimulation(
        folmeSpring(damping: 0.6, response: 0.4),
        start: _tiltXController.value,
        end: tx,
      ),
    );
    _tiltYController.animateWith(
      _SpringSimulation(
        folmeSpring(damping: 0.6, response: 0.4),
        start: _tiltYController.value,
        end: ty,
      ),
    );
  }

  void _setPressed(bool value, {Offset? normalizedPosition}) {
    if (_isPressed == value) return;
    _isPressed = value;
    if (value &&
        normalizedPosition != null &&
        widget.feedbackType == MiuixPressFeedbackType.tilt) {
      // 触点落在哪个象限，卡片就绕对角翻起——与 Compose TiltFeedback 一致。
      _tiltOrigin = Alignment(
        normalizedPosition.dx < 0.5 ? 1.0 : -1.0,
        normalizedPosition.dy < 0.5 ? 1.0 : -1.0,
      );
      _tiltXTarget = (normalizedPosition.dy < 0.5 ? 1.0 : -1.0) * 8.0;
      _tiltYTarget = (normalizedPosition.dx < 0.5 ? -1.0 : 1.0) * 8.0;
    }
    _animateOverlay(
      value
          ? folmeSpring(damping: 1.0, response: 0.2)
          : folmeSpring(damping: 0.95, response: 0.35),
    );
    switch (widget.feedbackType) {
      case MiuixPressFeedbackType.sink:
        _animateSink();
      case MiuixPressFeedbackType.tilt:
        _animateTilt();
      case MiuixPressFeedbackType.none:
        break;
    }
  }

  void _setHovered(bool value) {
    if (_isHovered == value) return;
    _isHovered = value;
    _animateOverlay(
      value
          ? folmeSpring(damping: 1.0, response: 0.6)
          : folmeSpring(damping: 0.96, response: 0.2),
    );
  }

  void _setFocused(bool value) {
    if (_isFocused == value) return;
    _isFocused = value;
    _animateOverlay(
      value
          ? folmeSpring(damping: 1.0, response: 0.6)
          : folmeSpring(damping: 0.96, response: 0.2),
    );
  }

  void _activate() {
    if (!_enabled) return;
    _setPressed(false);
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final cardColors =
        widget.colors ?? MiuixCardDefaults.defaultColors(context);
    final shape = MiuixSquircleBorder(
      cornerRadius: widget.cornerRadius,
      enabled: widget.cornerRadius > 0,
    );
    final theme = MiuixTheme.maybeOf(context);
    final overlayColor = theme?.colors.onBackground ?? const Color(0xFF000000);

    // 背景 + 内容 + 遮罩先合成一层，再整体按 squircle 裁切。
    Widget content = Padding(padding: widget.insideMargin, child: widget.child);
    content = MiuixContentColor(
      color: cardColors.contentColor,
      child: DecoratedBox(
        decoration: ShapeDecoration(color: cardColors.color, shape: shape),
        child: content,
      ),
    );
    // 按压遮罩画在裁切内侧，squircle 以外的部分天然不可见。
    content = Stack(
      fit: StackFit.passthrough,
      children: [
        content,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _overlayController,
              builder: (context, _) {
                final alpha = _overlayController.value.clamp(0.0, 1.0);
                if (alpha <= 0) return const SizedBox.shrink();
                return ColoredBox(color: overlayColor.withValues(alpha: alpha));
              },
            ),
          ),
        ),
      ],
    );
    content = ClipPath(
      clipper: ShapeBorderClipper(
        shape: shape,
        textDirection: Directionality.maybeOf(context),
      ),
      child: content,
    );

    // 裁切之后才做倾斜/下沉变换：卡面轮廓跟着一起动（对应 Compose 里
    // pressable 挂在 squircleSurface 之前的顺序）。
    switch (widget.feedbackType) {
      case MiuixPressFeedbackType.sink:
        content = AnimatedBuilder(
          animation: _sinkController,
          builder: (context, child) =>
              Transform.scale(scale: _sinkController.value, child: child),
          child: content,
        );
      case MiuixPressFeedbackType.tilt:
        content = AnimatedBuilder(
          animation: Listenable.merge([_tiltXController, _tiltYController]),
          builder: (context, child) => Transform(
            alignment: _tiltOrigin,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              // 注意取负号：Compose 的 rotationX/rotationY 走 RenderNode 的
              // 相机投影（android.graphics.Camera，取逆），而 Flutter 的
              // Matrix4.rotateX/rotateY 是对物体直接施加标准旋转矩阵——
              // 同一个数值在两边的视觉方向正好相反。_tiltX/YTarget 保存的是
              // Compose 语义的角度（触上半部 → rotationX=+tilt，对应「触点
              // 角下沉/向内」），这里取负喂给 Flutter 才能渲染出同向效果。
              ..rotateX(-_tiltXController.value * 0.0174533)
              ..rotateY(-_tiltYController.value * 0.0174533),
            child: child,
          ),
          child: content,
        );
      case MiuixPressFeedbackType.none:
        break;
    }

    return Semantics(
      button: true,
      enabled: _enabled,
      onTap: _enabled ? _activate : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled
            ? (d) {
                final box = context.findRenderObject() as RenderBox?;
                final size = box?.size ?? Size.zero;
                final pos = size.isEmpty
                    ? const Offset(0.5, 0.5)
                    : Offset(
                        (d.localPosition.dx / size.width).clamp(0.0, 1.0),
                        (d.localPosition.dy / size.height).clamp(0.0, 1.0),
                      );
                _setPressed(true, normalizedPosition: pos);
              }
            : null,
        onTapUp: _enabled
            ? (_) {
                _setPressed(false);
                widget.onPressed!();
              }
            : null,
        onTapCancel: _enabled ? () => _setPressed(false) : null,
        onLongPress: _enabled ? widget.onLongPress : null,
        child: MouseRegion(
          cursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: _enabled ? (_) => _setHovered(true) : null,
          onExit: _enabled ? (_) => _setHovered(false) : null,
          child: FocusableActionDetector(
            enabled: _enabled,
            onShowFocusHighlight: _enabled ? _setFocused : null,
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
            },
            actions: <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  _activate();
                  return null;
                },
              ),
            },
            child: content,
          ),
        ),
      ),
    );
  }
}

/// 用 [SpringDescription] 驱动的简单模拟，把 [AnimationController.animateWith]
/// 接到 SpringSimulation 上（同包版 MiuixPressable 的做法）。
class _SpringSimulation extends Simulation {
  _SpringSimulation(this.desc, {required double start, required double end})
    : _simulation = SpringSimulation(desc, start, end, 0);

  final SpringDescription desc;
  final SpringSimulation _simulation;

  @override
  double x(double time) => _simulation.x(time);

  @override
  double dx(double time) => _simulation.dx(time);

  @override
  bool isDone(double time) => _simulation.isDone(time);
}
