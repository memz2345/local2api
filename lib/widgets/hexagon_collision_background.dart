import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 通话背景「双六边形」（对齐 vivo 通话背景里的 Collision / 碰撞款）。
///
/// 两个大圆角六边形（主题主色 + 一层浅灰）沿对角线缓缓相向、轻触再分开，
/// 同时各自轻微摆动。颜色全部取自当前 `Theme.colorScheme` —— material 与
/// miuix 两边都靠这同一份色系（miuix 的颜色经 `materialSchemeFromMiuix`
/// 桥接进同一个 colorScheme），所以六边形自动跟随各自的主题色。
///
/// 用法：铺在通话页最底层（`Stack` 里的 `Positioned.fill`）。
class HexagonCollisionBackground extends StatefulWidget {
  const HexagonCollisionBackground({super.key, this.animate = true});

  /// 关掉动画只画静止一帧（测试用；正常页面别关）。
  final bool animate;

  @override
  State<HexagonCollisionBackground> createState() =>
      _HexagonCollisionBackgroundState();
}

class _HexagonCollisionBackgroundState extends State<HexagonCollisionBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _HexagonCollisionPainter(
          progress: _controller,
          background: cs.surfaceContainerLowest,
          primary: cs.primary,
          secondary: cs.surfaceContainerHighest,
        ),
      ),
    );
  }
}

class _HexagonCollisionPainter extends CustomPainter {
  _HexagonCollisionPainter({
    required this.progress,
    required this.background,
    required this.primary,
    required this.secondary,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color background;
  final Color primary;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    if (size.isEmpty) return;

    // 周期进度 → 0..1..0 的平滑往复（靠 cos 往返，来回无跳跃）。
    final t = progress.value;
    final s = (1 - math.cos(2 * math.pi * t)) / 2;

    // 尺寸与构图按 vivo 原预览图逐像素实测反推：
    // - 半径 ≈ 0.628 × 屏幕短边（竖屏看宽度、宽屏看高度）——宽屏下不能按
    //   宽度算，否则两块都大过整屏、副色被主色盖住像只剩一个；
    // - 主色块中心 (0.79w, 0.12h)、副色块中心 (0.21w, 0.72h)，
    //   同向旋转约 14°（从 pointy-top 起）——屏幕里各露出一个完整的
    //   圆角顶点 + 一条完整边，宽屏下允许两块自然重叠。
    final r = size.shortestSide * 0.628;
    final baseA = Offset(size.width * 0.790, size.height * 0.117);
    final baseB = Offset(size.width * 0.213, size.height * 0.723);
    const tilt = 0.248; // ≈ 14.2°
    // 「碰撞」：沿对角连线相向靠近（各挪 0.09 屏高），往复呼吸。
    final axis = baseB - baseA;
    final u = axis / axis.distance;
    final span = size.height * 0.09 * s;
    final aCenter = baseA + u * span;
    final bCenter = baseB - u * span;

    // 摆动：在 14° 基础朝向上叠 ±约 3° 的反向慢摆（两块一正一负呼应）。
    final swing = math.sin(2 * math.pi * t) * 0.05;
    final aRot = tilt + swing;
    final bRot = tilt - swing;

    final corner = r * 0.095; // 圆角（按原图圆角弧长反推）
    canvas.drawPath(
      _roundedHexagon(bCenter, r, corner, bRot),
      Paint()
        ..color = secondary
        ..isAntiAlias = true,
    );
    canvas.drawPath(
      _roundedHexagon(aCenter, r, corner, aRot),
      Paint()
        ..color = primary
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_HexagonCollisionPainter old) =>
      old.background != background ||
      old.primary != primary ||
      old.secondary != secondary;
}

/// 圆角正六边形（pointy-top：尖角朝上下），[rotation] 追加旋转。
///
/// 圆角用「顶点两侧各退一段、以顶点为控制点的二次贝塞尔」拼接 —— 与
/// Flutter 画圆角多边形的手感一致，顶点处不会出现尖刺。
Path _roundedHexagon(
  Offset center,
  double radius,
  double corner,
  double rotation,
) {
  final pts = <Offset>[
    for (var i = 0; i < 6; i++)
      center +
          Offset(
                math.cos(-math.pi / 2 + rotation + i * math.pi / 3),
                math.sin(-math.pi / 2 + rotation + i * math.pi / 3),
              ) *
              radius,
  ];
  final path = Path();
  for (var i = 0; i < 6; i++) {
    final v = pts[i];
    final prev = pts[(i + 5) % 6];
    final next = pts[(i + 1) % 6];
    final inDir = v - prev;
    final outDir = next - v;
    final tIn = math.min(corner, inDir.distance / 2) / inDir.distance;
    final tOut = math.min(corner, outDir.distance / 2) / outDir.distance;
    final pIn = v - inDir * tIn;
    final pOut = v + outDir * tOut;
    if (i == 0) {
      path.moveTo(pIn.dx, pIn.dy);
    } else {
      path.lineTo(pIn.dx, pIn.dy);
    }
    path.quadraticBezierTo(v.dx, v.dy, pOut.dx, pOut.dy);
  }
  path.close();
  return path;
}
