import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/l10n/app_localizations.dart';

/// 对话框里的一个动作按钮。
class MiuixDialogAction {
  const MiuixDialogAction({
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.destructive = false,
  });

  final String label;

  /// 点击回调，参数是**对话框自己的** BuildContext。
  ///
  /// 关闭对话框由回调自己负责（`Navigator.of(dialogContext).pop(结果)`）。
  /// 之所以把 context 传进来而不是让调用点用页面的 context：对话框走的是
  /// 根 Navigator（`showGeneralDialog` 默认 useRootNavigator），页面若处在
  /// 嵌套 Navigator 里，用页面的 context pop 会关错东西。
  final void Function(BuildContext dialogContext) onPressed;

  /// 主色实心按钮（一组里只放一个，一般是最右侧那个）；
  /// 其余是浅色次级按钮 —— 对齐 miuix 对话框「左次右主」的排布。
  final bool primary;

  /// 破坏性动作（删除之类）用 miuix 的 error 红，而不是主色蓝。
  final bool destructive;
}

/// 对话框标准动作按钮（HyperOS 同款圆角方形，非胶囊）：主色实心 / 浅色次级 / error 红，`onPressed` 为
/// null 时禁用。`showMiuixDialog` 的动作行由它拼装；内容里需要自带动作区
/// （比如按钮可用性要跟着表单状态走）时单独用，样式与动作行保持一致。
class MiuixDialogButton extends StatelessWidget {
  const MiuixDialogButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.destructive = false,
  });

  final String label;

  /// 为 null 表示禁用。
  final VoidCallback? onPressed;

  final bool primary;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final MiuixButtonColors buttonColors;
    if (destructive) {
      buttonColors = MiuixButtonColors(
        color: colors.error,
        contentColor: colors.onError,
        disabledColor: colors.error,
        disabledContentColor: colors.onError,
      );
    } else if (primary) {
      buttonColors = MiuixButtonColors(
        color: colors.primary,
        contentColor: colors.onPrimary,
        disabledColor: colors.disabledPrimary,
        disabledContentColor: colors.disabledOnPrimaryButton,
      );
    } else {
      buttonColors = MiuixButtonColors(
        color: colors.surfaceContainerHighest,
        contentColor: colors.onSurface,
        disabledColor: colors.surfaceContainerHighest,
        disabledContentColor: colors.onSurfaceSecondary,
      );
    }
    return MiuixButton(
      onPressed: onPressed,
      cornerRadius: 14,
      minWidth: 0,
      insideMargin: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      colors: buttonColors,
      child: MiuixText(
        label,
        fontSize: 15,
        fontWeight: primary || destructive ? FontWeight.w600 : FontWeight.w500,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// miuix 风格的对话框（命令式，一次调用拿到结果）。
///
/// **为什么不用 flutter_miuix 的 `MiuixOverlayDialog`**：那是**声明式**的，
/// 靠 `MiuixPopupRegistry` + `MiuixPopupHost` 渲染；而本项目的 miuix 页面
/// 用的是 Material `Scaffold`（`MiuixPagePopupHost` 只在本页内部建宿主，
/// 覆盖不到 Navigator 上层的路由），从任意命令式调用点弹不出来。
/// 所以这里用 Material 的 `showGeneralDialog` 当外壳，**外观与动效按 miuix 来**。
///
/// 外观对齐 miuix `DialogDefaults`：
///   - 圆角 32 的 squircle（`MiuixSquircleBorder`），底色 `colors.background`；
///   - 左右外边距 12、内边距 24；
///   - 标题居中加粗，正文左对齐（与上游 OverlayDialog 的排版一致）；
///   - 动作按钮是等宽圆角方形（cornerRadius 14），间距 12。
///
/// [bottom] 决定落点：true 贴屏幕底边、false 居中，**留空则跟随屏幕方向**
/// （竖屏贴底、横屏居中）—— 对应 miuix 「小屏底部对话框 / 大屏居中对话框」
/// 两档；动效也跟着分档：贴底走小屏的「自身高度下方滑入」，居中走大屏的
/// 「淡入 + 0.8→1 缩放」（Kotlin 侧 `smallDialogEnter` / `largeDialogEnter`，
/// 这里用同形的减速曲线 `Cubic(0, 0, 0.2, 1)` 近似，300ms 内观感一致）。
Future<T?> showMiuixDialog<T>({
  required BuildContext context,
  String? title,
  String? message,
  Widget? content,
  List<MiuixDialogAction> actions = const <MiuixDialogAction>[],
  bool? bottom,
  bool barrierDismissible = true,
}) {
  final colors = MiuixTheme.of(context).colors;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    // 与 MiuixPopupHost 的 windowDimming 同色
    barrierColor: const Color(0x4D000000),
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (ctx, _, _) => _MiuixDialogPanel(
      title: title,
      message: message,
      content: content,
      actions: actions,
      bottom: bottom,
      colors: colors,
    ),
    transitionBuilder: (ctx, animation, _, child) {
      final placeBottom = _bottomAligned(bottom, ctx);
      final curved = CurvedAnimation(
        parent: animation,
        curve: _miuixDialogCurve,
      );
      if (!placeBottom) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1).animate(curved),
            child: child,
          ),
        );
      }
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

/// 「删除上游」的确认框 —— 两处入口共用这一份，不再各写一套。
///
/// 以前发现页（[ProfilesPage] 的 miuix 版）走的是底部抽屉 + 两个纯文字按钮，
/// 上游编辑页走的是 [showMiuixDialog] + 红色删除按钮，同一个动作两个长相。
/// 现在统一到后者：HyperOS 居中大圆角卡、左取消右删除（error 红）。
/// 它与「退出前是否保存」那类询问框（见 `miuix_font_weight_screen`）是同一个
/// 底座，观感一致。
Future<bool> confirmDeleteUpstream(BuildContext context, String name) async {
  final l10n = AppLocalizations.of(context);
  final ok = await showMiuixDialog<bool>(
    context: context,
    title: l10n.deleteUpstreamConfirm(name),
    actions: [
      MiuixDialogAction(
        label: l10n.cancel,
        onPressed: (ctx) => Navigator.of(ctx).pop(false),
      ),
      MiuixDialogAction(
        label: l10n.deleteBtn,
        destructive: true,
        onPressed: (ctx) => Navigator.of(ctx).pop(true),
      ),
    ],
  );
  return ok == true;
}

/// 是否贴底：显式给了 [bottom] 就用它，否则竖屏贴底、横屏居中。
bool _bottomAligned(bool? bottom, BuildContext context) =>
    bottom ?? MediaQuery.orientationOf(context) == Orientation.portrait;

/// Kotlin `MiuixPopupDefaults._decelerate15`：进场减速、退场（同一条曲线反向）加速。
const Curve _miuixDialogCurve = Cubic(0.0, 0.0, 0.2, 1.0);

class _MiuixDialogPanel extends StatelessWidget {
  const _MiuixDialogPanel({
    required this.title,
    required this.message,
    required this.content,
    required this.actions,
    required this.bottom,
    required this.colors,
  });

  final String? title;
  final String? message;
  final Widget? content;
  final List<MiuixDialogAction> actions;

  /// 是否贴底；null = 跟随屏幕方向。
  final bool? bottom;

  final MiuixColors colors;

  @override
  Widget build(BuildContext context) {
    final system = MediaQuery.paddingOf(context);
    // 键盘弹出时面板要跟着上移（内容可能带输入框的场景）
    final imeBottom = MediaQuery.viewInsetsOf(context).bottom;
    final bottomInset = math.max(system.bottom, imeBottom);
    final placeBottom = _bottomAligned(bottom, context);

    Widget column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              title!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colors.onBackground,
              ),
            ),
          ),
        if (message != null)
          Padding(
            padding: EdgeInsets.only(bottom: actions.isEmpty ? 4 : 20),
            child: Text(
              message!,
              style: TextStyle(fontSize: 15, color: colors.onSurfaceSecondary),
            ),
          ),
        // 内容区限高可滚（高度上限来自外层 Padding 的可视高度）：表单类
        // 对话框（取色器 + 输入框）在小屏、横屏或键盘弹出时不会顶破卡片。
        if (content != null)
          Flexible(child: SingleChildScrollView(child: content)),
        if (actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(
                    child: MiuixDialogButton(
                      label: actions[i].label,
                      primary: actions[i].primary,
                      destructive: actions[i].destructive,
                      onPressed: () => actions[i].onPressed(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );

    column = DecoratedBox(
      decoration: ShapeDecoration(
        color: colors.background,
        shape: const MiuixSquircleBorder(cornerRadius: 32),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: column,
      ),
    );

    return Align(
      alignment: placeBottom ? Alignment.bottomCenter : Alignment.center,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, system.top + 12, 12, bottomInset + 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          // 只在**卡片自己**身上吃掉点击：点空白处要能落到遮罩上，
          // 否则 barrierDismissible 永远不生效（外层不能铺满整屏）。
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            // Material 兜底：对话框路由不在页面的 Material 层级里，缺了它
            // 面板里的裸 Text 会继承 WidgetsApp 那条「错误样式」（红色等宽
            // 字体 + 黄色双下划线），MiuixTextField 内层的 Material TextField
            // 也会找不到 Material 祖先。transparency 不引入额外背景色。
            child: Material(type: MaterialType.transparency, child: column),
          ),
        ),
      ),
    );
  }
}
