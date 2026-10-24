import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import 'miuix_tilt_card.dart';

/// miuix 分组卡片：**一张自绘的卡**，不再包包版的 [MiuixCard]。
///
/// 为什么不能包（flutter_miuix 1.3.0 的坑，按下的「外圈」就是它）：
/// 包版 [MiuixCard] → [MiuixPressable] 的结构是 `Transform(sink) → Stack →
/// 遮罩`——按压遮罩画在 sink 缩放变换的**外面**，按下时卡片缩到 0.94、
/// 遮罩还撑满原尺寸，卡片四周就露出一圈 10% 的暗环；而且遮罩是直角
/// `BorderRadius` 裁切、卡面是 squircle，角落上还错位。Compose 原版
/// （`Card.kt`）里 `modifier.pressable(...)` 挂在 `squircleSurface` 之前：
/// 背景先画、遮罩盖在卡面里、整卡（含遮罩）一起缩放，天然没有这圈。
///
/// 所以这里直接委托 [MiuixTiltCard] —— 它已经按 Compose 的顺序自绘：
/// 背景+内容+遮罩合成一层 → 按 squircle 裁切 → 再做 sink/tilt 变换。
/// 遮罩随卡片一起缩放、只露在卡面轮廓内，这就是「只有一张卡」。
/// 早期版本曾靠外层 ClipPath 兜直角遮罩，治标不治本，已废弃。
class MiuixGroupCard extends StatelessWidget {
  const MiuixGroupCard({
    super.key,
    this.cornerRadius = MiuixCardDefaults.cornerRadius,
    this.insideMargin = MiuixCardDefaults.insideMargin,
    this.colors,
    this.onPressed,
    this.onLongPress,
    this.feedbackType = MiuixPressFeedbackType.none,
    this.child,
  });

  /// 圆角半径，与 [MiuixCard.cornerRadius] 一致。
  final double cornerRadius;

  /// 内边距，与 [MiuixCard.insideMargin] 一致。
  final EdgeInsetsGeometry insideMargin;

  /// 颜色配置，默认取 `MiuixCardDefaults.defaultColors`。
  final MiuixCardColors? colors;

  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;

  /// 按压反馈类型（sink/tilt），与 [MiuixCard.feedbackType] 一致。
  final MiuixPressFeedbackType feedbackType;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return MiuixTiltCard(
      cornerRadius: cornerRadius,
      insideMargin: insideMargin,
      colors: colors,
      onPressed: onPressed,
      onLongPress: onLongPress,
      feedbackType: feedbackType,
      child: child,
    );
  }
}
