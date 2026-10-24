import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 上下文占用圆环（对齐 opencode 桌面端的 ProgressCircle）：
/// 双圆 —— 底圈弱色描一整圈，进度圈从顶部（-90°）按百分比画弧，
/// 圆头笔帽；占用 ≥90% 时进度圈换 error 色提醒快满。
/// [label] 非空时在右侧补一截百分比小字（等宽数字，跳不动）。
class ContextRing extends StatelessWidget {
  const ContextRing({
    super.key,
    required this.percent,
    this.size = 16,
    this.strokeWidth = 2,
    this.label,
    this.trackColor,
  });

  /// 0..100。
  final double percent;

  final double size;
  final double strokeWidth;

  /// 非空时在圆环右侧显示（一般是取整后的百分比）。
  final String? label;

  /// 底圈颜色。null 用 Material 的 `surfaceContainerHighest`；
  /// miuix 那套没有这个 token，传它的 `onSurfaceVariantActions` 更贴。
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hot = percent >= 90;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(
              percent: percent / 100,
              strokeWidth: strokeWidth,
              trackColor: trackColor ?? cs.surfaceContainerHighest,
              progressColor: hot ? cs.error : cs.primary,
            ),
          ),
        ),
        if (label != null && label!.isNotEmpty) ...[
          const SizedBox(width: 5),
          Text(
            label!,
            style: TextStyle(
              fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: hot ? cs.error : cs.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.percent,
    required this.strokeWidth,
    required this.trackColor,
    required this.progressColor,
  });

  /// 0..1。
  final double percent;
  final double strokeWidth;
  final Color trackColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    final sw = strokeWidth;
    final radius = (math.min(size.width, size.height) - sw) / 2;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: math.max(0.0, radius),
    );
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..color = trackColor;
    canvas.drawArc(rect, 0, 2 * math.pi, false, track);
    final p = math.max(0.0, math.min(1.0, percent));
    if (p <= 0) return;
    final progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round
      ..color = progressColor;
    // -pi/2 = 从顶部起笔（opencode 同款 rotate(-90deg) 的等价画法）。
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * p, false, progress);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.percent != percent ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.progressColor != progressColor ||
      oldDelegate.strokeWidth != strokeWidth;
}
