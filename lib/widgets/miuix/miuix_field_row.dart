// CMFA 式的「一行一个字段」行（miuix 版）：图标 + 字段名 + 当前值 + 行尾铅笔。
//
// 上游编辑页与角色卡编辑页共用；点行开编辑器的动作由调用方给 [onTap]，
// 行尾默认画铅笔（=「点我改这一项」），传了 [endActions] 就用调用方的
// （比如音色样本行的「移除」按钮）。
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField;
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';

class MiuixFieldRow extends StatelessWidget {
  const MiuixFieldRow({
    super.key,
    required this.iconName,
    required this.fallbackIcon,
    required this.title,
    required this.value,
    this.valueIsHint = false,
    this.onTap,
    this.endActions,
  });

  /// miuix 图标名（找不到时回落 [fallbackIcon]）。
  final String iconName;
  final IconData fallbackIcon;
  final String title;
  final String value;

  /// 没填的占位再淡一档（对应图里灰的「未填写」行）。
  final bool valueIsHint;
  final VoidCallback? onTap;

  /// 自定义行尾动作；不给就画默认铅笔。
  final List<Widget>? endActions;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixBasicComponent(
      title: title,
      summary: value,
      summaryColor: MiuixBasicComponentColors(
        color: valueIsHint
            ? colors.onSurfaceVariantSummary.withValues(alpha: 0.6)
            : colors.onSurfaceVariantSummary,
        disabledColor: colors.disabledOnSecondaryVariant,
      ),
      startAction: MiuixAppIcon(
        iconName,
        fallback: fallbackIcon,
        size: 24,
        color: colors.onSurface,
      ),
      endActions:
          endActions ??
          [
            MiuixAppIcon(
              AppIconNames.edit,
              fallback: Icons.edit_outlined,
              size: 20,
              color: colors.onSurfaceVariantActions,
            ),
          ],
      onClick: onTap,
    );
  }
}
