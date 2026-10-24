import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../predictive_back_sheet.dart';

/// miuix 风格的底部操作面板外壳。**miuix 页面的弹层统一走这个函数。**
///
/// 与 Material 侧的 `showAppBottomSheet` 对齐 —— 外壳仍是 Material 的
/// `showModalBottomSheet`（flutter_miuix 的 `MiuixOverlayBottomSheet` 是
/// **声明式**的、必须挂在 `MiuixScaffold` 的 popupHost 上，没法从任意命令式
/// 调用点弹出来），但补齐两件事：
///
/// 1. **预测式返回**：包一层 [PredictiveBackSheet]，Android 14+ 的返回手势
///    过程中面板跟手缩放/平移，中途松手取消会回弹 —— 与 Material 侧同一套实现。
/// 2. **miuix 配色与圆角**：底色取 `MiuixTheme.colors.surfaceContainer`，
///    顶部两角走 squircle（`MiuixBottomSheetDefaults.cornerRadius` = 28），
///    底部直角（贴在屏幕底边，圆角会漏底色）。
Future<T?> showMiuixBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useSafeArea = true,
  Color? backgroundColor,
  double? cornerRadius,
  bool enablePredictiveBack = true,
}) {
  final colors = MiuixTheme.of(context).colors;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useSafeArea: useSafeArea,
    backgroundColor: backgroundColor ?? colors.surfaceContainer,
    shape: _TopSquircleBorder(
      cornerRadius: cornerRadius ?? MiuixBottomSheetDefaults.cornerRadius,
    ),
    builder: (sheetContext) => PredictiveBackSheet(
      enabled: enablePredictiveBack,
      child: builder(sheetContext),
    ),
  );
}

/// 只有上面两角是连续圆角（squircle）、下两角直角的边框。
///
/// 实现与 flutter_miuix 的 `MiuixBottomSheetDefaults.cornerRadius` 配套的那份
/// `_TopSquircleBorder` 同构（control = 0.643 是它的定值）。`paint` 留空是刻意的：
/// `Material` 画底色用的是 `getOuterPath`（见 `_ShapeBorderPaint`），不走 `paint`。
class _TopSquircleBorder extends ShapeBorder {
  const _TopSquircleBorder({required this.cornerRadius});

  final double cornerRadius;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final r = cornerRadius.clamp(0.0, rect.width / 2);
    if (r <= 0) return Path()..addRect(rect);
    const control = 0.643;
    final handle = r * (1 - control);
    return Path()
      ..moveTo(rect.left + r, rect.top)
      ..lineTo(rect.right - r, rect.top)
      ..cubicTo(
        rect.right - handle,
        rect.top,
        rect.right,
        rect.top + handle,
        rect.right,
        rect.top + r,
      )
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..lineTo(rect.left, rect.top + r)
      ..cubicTo(
        rect.left,
        rect.top + handle,
        rect.left + handle,
        rect.top,
        rect.left + r,
        rect.top,
      )
      ..close();
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) =>
      _TopSquircleBorder(cornerRadius: cornerRadius * t);
}
