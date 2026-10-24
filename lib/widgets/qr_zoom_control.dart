import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 轮盘展开的方位：贴屏幕底边（手机竖屏）或贴屏幕左边缘（平板/宽屏，
/// 预览竖排在左侧时，整个轮盘坐标系顺时针转 90°）。
enum QrDialEdge { bottom, left }

/// 扫码变焦控制（Material / miuix 扫码页共用）。
///
/// 刻度盘按小米相机的 ZoomCircleRuler 逆向还原（见反编译笔记）：
/// - **对数刻度**：0.6x→100x 全量程压在 140° 圆弧上（每 1° ≈ +3.83% 倍率），
///   所以 0.6→1、1→2、2→5、5→10 的弧距是 14°/19°/25°/19°，高倍率不挤；
/// - **轮盘**：表盘半径 199、圆心沉到屏幕外（边内 95），拖动按触点绕
///   圆心的角度 1:1 带动轮盘（环内按半径衰减），顺时针拨=缩小；
/// - **磁吸**：拖动中距档位 <0.34° 就吸住；松手（非惯性）按 0.1/0.2 容差
///   吸附最近档位；快速滑动有惯性衰减，惯性不吸附（MIUI 同款）；
/// - **点按弧线**：把点到的刻度转到指针下（等价于跳到该倍率），3° 内吸档。
/// - **背景**：圆心处 50% 黑圆盘（r=204）+ 外缘细环（对应原版
///   circle_ruler_pan[_bg|_outer] 矢量层）；左边缘模式再叠整条 50% 黑边条。
///
/// 收起态是「预设胶囊」：`0.6 ··· 1x ··· 2`，当前档深色圆片 + 主题色字。
/// 显隐由 [visible] 受控（点胶囊 / 预览滑动调出 / 超时自动收起都走
/// [onVisibleChanged]），父级还负责在轮盘展开时铺一层点击收起的暗幕。
class QrZoomControl extends StatefulWidget {
  const QrZoomControl({
    super.key,
    required this.value,
    required this.hasUltraWide,
    required this.accent,
    required this.onChanged,
    required this.visible,
    required this.onVisibleChanged,
    this.edge = QrDialEdge.bottom,
  });

  /// 当前倍率（0.6–10 或 1–10）。
  final double value;

  /// 设备后置是否有超广角（有则轮盘从 0.6x 起）。
  final bool hasUltraWide;

  /// 强调色：Material 传 `colorScheme.primary`，miuix 传 `MiuixTheme` 主色。
  final Color accent;

  /// 倍率变化（拖动 / 惯性 / 动画期间每帧回调）。
  final ValueChanged<double> onChanged;

  /// 轮盘是否展开（受控）。
  final bool visible;

  /// 显隐变化（胶囊点开 / 点大字收起 / 4s 无操作自动收起）。
  final ValueChanged<bool> onVisibleChanged;

  /// 轮盘贴边方位。
  final QrDialEdge edge;

  @override
  State<QrZoomControl> createState() => QrZoomControlState();
}

class QrZoomControlState extends State<QrZoomControl>
    with SingleTickerProviderStateMixin {
  // ---- 刻度数学（ZoomCircleRuler 逆向值）---------------------------------

  /// 全量程 0.6x→100x 压在 140° 上：Z4^140 = 100/0.6，即每 1° 倍率 ×3.83%。
  static final double _z4 =
      math.pow(10, math.log(166.66666666666669) / math.ln10 / 140).toDouble();

  /// 轮盘基准倍率（MIUI 的 C2，恒为 0.6；无超广角时下限钳到 1x 的角度）。
  static const double _baseZoom = 0.6;

  /// 表盘半径 / 刻度高 / 圆心沉到边外的深度 / 轮盘带宽度（逆向 dimens）。
  static const double _radius = 199;
  static const double _tickLen = 9.5;
  static const double _centerBelow = 95;
  static const double _dialSpan = 176;

  /// 拖动磁吸半径（°）、点按吸档容差（°）、惯性衰减时间常数、角速度上限。
  static const double _magnetDeg = 0.34;
  static const double _tapSnapDeg = 3;
  static const double _flingTauMs = 350;
  static const double _flingMaxDegPerS = 144; // MIUI 限速 500px/s ÷ 199dp

  /// 预览滑动调出轮盘的灵敏度：span × 0.85 的滑动 ≈ 走完整个量程。
  static const double _swipeCoverage = 0.85;

  List<double> get _stops =>
      widget.hasUltraWide ? const [0.6, 1, 2, 5, 10] : const [1, 2, 5, 10];

  /// 倍率 → 轮盘角度（°）。0.6x 在 0°，1x≈14°，2x≈33°，5x≈58°，10x≈77°。
  double _posOf(double zoom) => math.log(zoom / _baseZoom) / math.log(_z4);

  /// 轮盘角度 → 倍率。
  double _zoomAt(double pos) => _baseZoom * math.pow(_z4, pos);

  double get _posMin => _posOf(widget.hasUltraWide ? 0.6 : 1.0);
  double get _posMax => _posOf(10);

  // ---- 运行态 -------------------------------------------------------------

  /// 轮盘当前角度（°）。当前倍率恒等于 _zoomAt(_wheel)。
  double _wheel = 0;

  bool _dragging = false;
  bool _flinging = false;
  bool _animating = false;

  Ticker? _ticker;
  double _flingVelocity = 0;
  DateTime _flingLast = DateTime.now();
  DateTime _animStart = DateTime.now();
  double _animFrom = 0;
  double _animTo = 0;
  Duration _animDuration = const Duration(milliseconds: 150);

  // 拖动参照：上一次触点的角度与距离。
  double _lastTouchDeg = 0;
  double _lastTouchDist = 0;

  // 收起态 4s 无操作自动收起（对应 MIUI 轮盘的展示超时）。
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    _wheel = _clampPos(_posOf(widget.value));
  }

  @override
  void didUpdateWidget(QrZoomControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部改了倍率（捏合 / 镜头重置）且本地没在动 → 跟随。
    if (!_dragging && !_flinging && !_animating &&
        (widget.value - _zoomAt(_wheel)).abs() > 0.005) {
      _wheel = _clampPos(_posOf(widget.value));
    } else {
      // 超广角信息迟到 / 消失会改量程，兜底钳回界内。
      _wheel = _clampPos(_wheel);
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _ticker?.dispose();
    super.dispose();
  }

  double _clampPos(double pos) => pos.clamp(_posMin, _posMax);

  String _format(double m) =>
      (m * 10).round() % 10 == 0 ? m.toStringAsFixed(0) : m.toStringAsFixed(1);

  void _emit() => widget.onChanged(_zoomAt(_wheel));

  void _setVisible(bool v) {
    if (widget.visible == v) return;
    widget.onVisibleChanged(v);
  }

  void _markActive() {
    _idleTimer?.cancel();
    if (widget.visible) {
      _idleTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && !_dragging && !_flinging && !_animating) {
          _setVisible(false);
        }
      });
    }
  }

  // ---- 给父级的接口：预览滑动直接带动轮盘 ---------------------------------

  /// 预览上单指滑动调焦：[px] 为沿滑动轴的有符号位移（右/下为正 =
  /// 顺时针拨轮 = 缩小），[span] 是预览短边长，用于换算灵敏度。
  /// 首次调用会自动展开轮盘（MIUI 的横滑调尺同款）。
  void applySwipe(double px, double span) {
    if (!_dragging && !_flinging && !_animating) {
      _stopTicker();
      if (!widget.visible) _setVisible(true);
      final k = _posMax / math.max(1, span * _swipeCoverage);
      _wheel = _clampPos(_wheel - px * k);
      for (final stop in _stops) {
        final sp = _posOf(stop);
        if ((_wheel - sp).abs() < _magnetDeg) _wheel = sp;
      }
      _emit();
      _markActive();
      if (mounted) setState(() {});
    }
  }

  // ---- 动画 / 惯性 --------------------------------------------------------

  void _startTicker() {
    _ticker ??= createTicker(_onTick)..start();
  }

  void _stopTicker() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
  }

  /// 惯性：角速度指数衰减（时间常数 350ms），不吸档（MIUI 同款）。
  void _startFling(double degPerSecond) {
    _flinging = true;
    _flingVelocity =
        degPerSecond.clamp(-_flingMaxDegPerS, _flingMaxDegPerS);
    _flingLast = DateTime.now();
    _startTicker();
  }

  /// 缓动到目标角度（预设 / 点按 / 松手吸附）。
  void _animateTo(double pos, {Duration? duration}) {
    _animating = true;
    _animFrom = _wheel;
    _animTo = _clampPos(pos);
    _animStart = DateTime.now();
    _animDuration = duration ?? const Duration(milliseconds: 150);
    if ((_animTo - _animFrom).abs() < 0.001) {
      _animating = false;
      return;
    }
    _startTicker();
  }

  void _onTick(Duration elapsed) {
    final now = DateTime.now();
    if (_animating) {
      final t = (now.difference(_animStart).inMicroseconds /
              _animDuration.inMicroseconds)
          .clamp(0.0, 1.0);
      _wheel = _animFrom + (_animTo - _animFrom) * Curves.easeOutCubic.transform(t);
      _emit();
      if (t >= 1) {
        _animating = false;
        _stopTicker();
        _markActive();
      }
    } else if (_flinging) {
      final ms = now.difference(_flingLast).inMicroseconds / 1000;
      _flingLast = now;
      _wheel = _clampPos(_wheel + _flingVelocity * ms / 1000);
      _flingVelocity *= math.exp(-ms / _flingTauMs);
      _emit();
      if (_wheel >= _posMax - 0.001 ||
          _wheel <= _posMin + 0.001 ||
          _flingVelocity.abs() < 2) {
        _flinging = false;
        _stopTicker();
        _markActive();
      }
    } else {
      _stopTicker();
    }
    if (mounted) setState(() {});
  }

  // ---- 手势（触点角度 1:1 带动轮盘）--------------------------------------

  /// 轮盘圆心：bottom 沉在组件底边之下，left 沉在左边缘之外。
  Offset _center(Size size) => widget.edge == QrDialEdge.bottom
      ? Offset(size.width / 2, size.height + _centerBelow)
      : Offset(-_centerBelow, size.height / 2);

  /// 触点相对圆心的弧角（°）：0 = 弧顶（指针方向），顺时针为正。
  double _degOf(Offset local, Size size) {
    final c = _center(size);
    final dx = local.dx - c.dx;
    final dy = local.dy - c.dy;
    return widget.edge == QrDialEdge.bottom
        ? math.atan2(dx, -dy) * 180 / math.pi
        : math.atan2(dy, dx) * 180 / math.pi;
  }

  /// 弧角 [deg] 处半径 [r] 的屏幕坐标。
  Offset _polar(double deg, double r, Size size) {
    final c = _center(size);
    final rad = deg * math.pi / 180;
    final d = widget.edge == QrDialEdge.bottom
        ? Offset(math.sin(rad), -math.cos(rad))
        : Offset(math.cos(rad), math.sin(rad));
    return c + d * r;
  }

  /// 弧角 [deg] 处的切向单位向量（弧角增大方向），算惯性角速度用。
  Offset _tangent(double deg) {
    final rad = deg * math.pi / 180;
    return widget.edge == QrDialEdge.bottom
        ? Offset(math.cos(rad), math.sin(rad))
        : Offset(-math.sin(rad), math.cos(rad));
  }

  void _onPanStart(DragStartDetails d) {
    _stopTicker();
    _flinging = false;
    _animating = false;
    _dragging = true;
    _markActive();
    final size = _dialSize ?? Size(320, _dialSpan);
    _lastTouchDeg = _degOf(d.localPosition, size);
    _lastTouchDist = (_polar(_lastTouchDeg, _radius, size) - _center(size)).distance;
    _pendingStart = d.localPosition;
  }

  Offset? _pendingStart;
  Size? _dialSize;

  void _onPanUpdate(DragUpdateDetails d) {
    if (!_dragging) return;
    final size = _dialSize ?? Size(320, _dialSpan);
    final local =
        _pendingStart == null ? d.localPosition : _pendingStart! + d.delta;
    _pendingStart = local;
    final deg = _degOf(local, size);
    final dist = (_polar(deg, _radius, size) - _center(size)).distance;
    var delta = deg - _lastTouchDeg;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    _lastTouchDeg = deg;
    // 环内衰减：MIUI 的 m()——触点在环半径 - 刻度高之外按 1.0 计。
    final m = math.min(1.0, dist / (_radius - _tickLen));
    // 物理轮盘：手指顺时针拨，轮面跟着顺时针转，指针下读数变小（缩小）。
    var next = _clampPos(_wheel - delta * m);
    // 拖动磁吸：吸到最近的档位角（±0.34°）。
    for (final stop in _stops) {
      final sp = _posOf(stop);
      if ((next - sp).abs() < _magnetDeg) next = sp;
    }
    if (next != _wheel) {
      _wheel = next;
      _emit();
    }
    if (mounted) setState(() {});
  }

  void _onPanEnd(DragEndDetails d) {
    _dragging = false;
    _pendingStart = null;
    final v = d.velocity.pixelsPerSecond;
    // 把线速度换成角速度：最后触点处的切向分量 / 触点半径。
    final tangent = v.dx * _tangent(_lastTouchDeg).dx +
        v.dy * _tangent(_lastTouchDeg).dy;
    final degPerS =
        tangent / _lastTouchDist.clamp(40.0, _radius).toDouble() * 180 / math.pi;
    if (degPerS.abs() > 30) {
      // 轮面跟手：拨动方向取反（见 _onPanUpdate）。
      _startFling(-degPerS);
      return;
    }
    // 松手吸附（MIUI t() 容差：<2x 吸 0.1、<10x 吸 0.2）。
    final zoom = _zoomAt(_wheel);
    for (final stop in _stops) {
      final tol = stop < 2 ? 0.1 : 0.2;
      if ((zoom - stop).abs() < tol) {
        _animateTo(_posOf(stop));
        return;
      }
    }
    _markActive();
  }

  /// 点按弧线：把点到的刻度转到指针下；3° 内吸档；点弧外收起。
  void _onTapUp(TapUpDetails d) {
    final size = _dialSize ?? Size(320, _dialSpan);
    final deg = _degOf(d.localPosition, size);
    final dist = (_polar(deg, _radius, size) - _center(size)).distance;
    if ((dist - _radius).abs() > 25) {
      _setVisible(false);
      _idleTimer?.cancel();
      return;
    }
    var zoom = _zoomAt(_clampPos(deg + _wheel));
    for (final stop in _stops) {
      if ((_posOf(stop) - deg - _wheel).abs() < _tapSnapDeg) zoom = stop;
    }
    zoom = zoom.clamp(_zoomAt(_posMin), 10.0);
    _animateTo(_posOf(zoom));
    _markActive();
  }

  // ---- 构建 ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (widget.edge == QrDialEdge.left) {
      // 左边缘模式：轮盘条贴左、胶囊留在预览底部中间（抬高避开提示文字）。
      return Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: const Interval(0, 1, curve: Cubic(0.46, 0.7, 0.25, 1)),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween(begin: 0.85, end: 1.0).animate(animation),
                  child: child,
                ),
              ),
              child: widget.visible
                  ? _buildDial(key: const Key('zoom-dial'))
                  : const SizedBox.shrink(key: Key('zoom-dial-hole')),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 48),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: widget.visible ? 0 : 1,
                child: IgnorePointer(
                  ignoring: widget.visible,
                  child: _buildPill(key: const Key('zoom-pill')),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: const Interval(0, 1, curve: Cubic(0.46, 0.7, 0.25, 1)),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween(begin: 0.85, end: 1.0).animate(animation),
            child: child,
          ),
        ),
        child: widget.visible
            ? _buildDial(key: const Key('zoom-dial'))
            : _buildPill(key: const Key('zoom-pill')),
      ),
    );
  }

  /// 收起态：`0.6 ··· 1x ··· 2` 预设胶囊，点它展开轮盘。
  Widget _buildPill({Key? key}) {
    final stops = _stops;
    final currentPos = _posOf(widget.value);
    final first = (currentPos.round() - 1).clamp(0, stops.length - 3).toInt();
    var nearest = 0;
    for (var i = 1; i < stops.length; i++) {
      if ((widget.value - stops[i]).abs() <
          (widget.value - stops[nearest]).abs()) {
        nearest = i;
      }
    }

    return Semantics(
      key: key,
      button: true,
      label: '${_format(widget.value)}x',
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            _setVisible(true);
            _markActive();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Text(
                        '···',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                  _PillChip(
                    label: _format(stops[first + i]),
                    current: first + i == nearest,
                    accent: widget.accent,
                    onTap: () {
                      // 点预设：先动画转过去，动画里逐帧回调。
                      _animateTo(_posOf(stops[first + i]));
                      _markActive();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 展开态：对数刻度轮盘 + 当前倍率大字 + 背景暗盘。
  Widget _buildDial({Key? key}) {
    final isLeft = widget.edge == QrDialEdge.left;
    return KeyedSubtree(
      key: key,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _dialSize = isLeft
              ? Size(_dialSpan, constraints.maxHeight)
              : Size(constraints.maxWidth, _dialSpan);
          return SizedBox(
            width: isLeft ? _dialSpan : double.infinity,
            height: isLeft ? double.infinity : _dialSpan,
            child: Stack(
              children: [
                // 左边缘模式：整条 50% 黑边条（MIUI Pad 的全视图暗幕）。
                if (isLeft) Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: 0.5))),
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: _onPanEnd,
                    onTapUp: _onTapUp,
                    child: CustomPaint(
                      painter: _ZoomDialPainter(
                        wheel: _wheel,
                        stops: _stops,
                        accent: widget.accent,
                        posMin: _posMin,
                        posMax: _posMax,
                        edge: widget.edge,
                      ),
                    ),
                  ),
                ),
                // 当前倍率大字：bottom 在弧顶上方，left 在指针右侧，点它收起。
                if (!isLeft)
                  Positioned(
                    top: 20,
                    left: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: () => _setVisible(false),
                      child: Text(
                        '${_format(widget.value)}x',
                        textAlign: TextAlign.center,
                        style: _valueTextStyle,
                      ),
                    ),
                  )
                else
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 2,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _setVisible(false),
                      child: Center(
                        child: Text('${_format(widget.value)}x', style: _valueTextStyle),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  TextStyle get _valueTextStyle => TextStyle(
        color: widget.accent,
        fontSize: 21,
        fontWeight: FontWeight.w800,
        shadows: const [Shadow(blurRadius: 12, color: Colors.black45)],
      );
}

/// 胶囊里的单个预设档位：当前档位是深色圆片 + 主题色字，其余纯白字。
class _PillChip extends StatelessWidget {
  const _PillChip({
    required this.label,
    required this.current,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool current;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      current ? '${label}x' : label,
      style: TextStyle(
        color: current ? accent : Colors.white,
        fontSize: 16,
        fontWeight: current ? FontWeight.w700 : FontWeight.w500,
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: current
          ? Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              child: text,
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: text,
            ),
    );
  }
}

/// 轮盘画笔：对数刻度沿弧排布、随 [_wheel]（当前角度）滚动。
///
/// 屏幕角 = 档位角 - 轮盘角；指针固定在弧顶。刻度全部 9.5 高：
/// 档位刻度 stroke 1.0 全亮 + 标签（10sp、随刻度倾斜、半径内缩 30.5），
/// 3x 加粗刻度全亮，细刻度（每 0.1x）stroke 0.6、5x 之后 0.3→0.16 渐隐，
/// 量程带为 9.5 宽、0.16 透明的弧；背景是 50% 黑圆盘 + 外缘细环
/// （对应原版 circle_ruler_pan[_bg|_outer]）。
class _ZoomDialPainter extends CustomPainter {
  _ZoomDialPainter({
    required this.wheel,
    required this.stops,
    required this.accent,
    required this.posMin,
    required this.posMax,
    required this.edge,
  });

  final double wheel;
  final List<double> stops;
  final Color accent;
  final double posMin;
  final double posMax;
  final QrDialEdge edge;

  static const double _radius = 199;
  static const double _tickLen = 9.5;
  static const double _centerBelow = 95;
  static const double _baseZoom = 0.6;
  static const double _visibleDeg = 66;

  static final double _z4 =
      math.pow(10, math.log(166.66666666666669) / math.ln10 / 140).toDouble();

  double _posOf(double zoom) => math.log(zoom / _baseZoom) / math.log(_z4);

  @override
  void paint(Canvas canvas, Size size) {
    // 圆弧伸到组件外（圆心沉在边外），裁掉出界部分。
    canvas.clipRect(Offset.zero & size);
    final isLeft = edge == QrDialEdge.left;
    final center = isLeft
        ? Offset(-_centerBelow, size.height / 2)
        : Offset(size.width / 2, size.height + _centerBelow);

    Offset polar(double deg, double radius) {
      final rad = deg * math.pi / 180;
      final d = isLeft
          ? Offset(math.cos(rad), math.sin(rad))
          : Offset(math.sin(rad), -math.cos(rad));
      return center + d * radius;
    }

    // 背景暗盘：50% 黑圆盘（r=204）+ 外缘细环（r 194–204 @0.1 + 发丝线 @0.08）。
    canvas.drawCircle(
      center,
      _radius + 5,
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );
    canvas.drawCircle(
      center,
      _radius - _tickLen / 2,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _tickLen,
    );
    canvas.drawCircle(
      center,
      _radius - 0.5,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    void drawTick(double zoom, {required double alpha, required double stroke}) {
      final deg = _posOf(zoom) - wheel;
      if (deg.abs() > _visibleDeg) return;
      canvas.drawLine(
        polar(deg, _radius),
        polar(deg, _radius - _tickLen),
        Paint()
          ..color = Colors.white.withValues(alpha: alpha)
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    // 量程带：轮盘空间里从下限到上限的一条淡弧。
    final bandRect = Rect.fromCircle(center: center, radius: _radius - _tickLen / 2);
    final bandStart = isLeft ? posMin - wheel : posMin - wheel - 90;
    canvas.drawArc(
      bandRect,
      bandStart * math.pi / 180,
      (posMax - posMin) * math.pi / 180,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _tickLen,
    );

    // 细刻度：每 0.1x 一根；5x 起随角度 0.3→0.16 渐隐（MIUI 同款）。
    final fadeStart = _posOf(5);
    final fadeEnd = _posOf(10);
    var v = 0.7;
    while (v < 10) {
      final isMajor = stops.any((s) => (s - v).abs() < 0.0001);
      final isBold = !isMajor && (v - 3.0).abs() < 0.0001;
      // 低于量程下限（无超广角时 <1x）的刻度不可达，不画。
      if (!isMajor && !isBold && v >= stops.first - 0.0001) {
        final pos = _posOf(v);
        final alpha = pos <= fadeStart
            ? 0.30
            : pos >= fadeEnd
            ? 0.16
            : 0.30 + (pos - fadeStart) / (fadeEnd - fadeStart) * (0.16 - 0.30);
        drawTick(v, alpha: alpha, stroke: 0.6);
      }
      v += 0.1;
    }

    // 3x 加粗刻度（MIUI 的 bold gradation：f2926h 除去档位后的 3x）。
    if (stops.first <= 3 && 3 <= stops.last) {
      drawTick(3, alpha: 0.95, stroke: 1.0);
    }

    // 档位刻度 + 标签（标签随刻度倾斜，内缩 30.5）。
    for (final stop in stops) {
      final deg = _posOf(stop) - wheel;
      if (deg.abs() > _visibleDeg) continue;
      canvas.drawLine(
        polar(deg, _radius),
        polar(deg, _radius - _tickLen),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.95)
          ..strokeWidth = 1.0
          ..strokeCap = StrokeCap.round,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: stop == 10 ? '10' : '$stop'.replaceAll('.0', ''),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelCenter = polar(deg, _radius - 30.5);
      canvas.save();
      canvas.translate(labelCenter.dx, labelCenter.dy);
      canvas.rotate(deg * math.pi / 180);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    // 指针：弧顶一根主题色 2×15 圆头刻度（MIUI 金色指针位）。
    canvas.drawLine(
      polar(0, _radius),
      polar(0, _radius - 15),
      Paint()
        ..color = accent
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ZoomDialPainter old) =>
      old.wheel != wheel ||
      old.accent != accent ||
      old.posMin != posMin ||
      old.posMax != posMax ||
      old.edge != edge ||
      old.stops.length != stops.length ||
      old.stops.first != stops.first;
}
