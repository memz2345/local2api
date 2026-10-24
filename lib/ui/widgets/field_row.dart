// CMFA 式的「一行一个字段」行（Material 版）：左图标 + 小标签 + 当前值 +
// 下划线，右端铅笔 / 控件。上游编辑页与角色卡编辑页共用。
//
// ⚠️ 那层 `Material(type: transparency)` 是**必须**的：这一页铺在
// FrostedBarPage 的 `PageBackground` 上，而 `InkWell`/`IconButton` 的墨迹
// 画在最近的祖先 Material 上 —— 不自己套一层，ripple 就落在背景底下看不见。
import 'package:flutter/material.dart';

class FieldRow extends StatelessWidget {
  const FieldRow({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    this.valueIsHint = false,
    this.onTap,
    this.control,
    this.endIcon,
  });

  final IconData icon;
  final String label;

  /// 当前值。为 null = 这一行没有「值」这一行（开关行、动作行），
  /// 标签自己居中占一行。
  final String? value;

  /// 值只是占位（没填）→ 灰一档。
  final bool valueIsHint;
  final VoidCallback? onTap;

  /// 右端的真实控件（开关、转圈）。给了它就不画 [endIcon]。
  final Widget? control;

  /// 右端图标，默认铅笔（=「点我改这一项」）。
  final IconData? endIcon;

  static const BorderRadius _shape = BorderRadius.all(Radius.circular(16));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasValue = value != null;

    final end =
        control ??
        (onTap == null
            ? const SizedBox.shrink()
            : IconButton(
                onPressed: onTap,
                icon: Icon(
                  endIcon ?? Icons.edit_outlined,
                  size: 22,
                  color: cs.onSurfaceVariant,
                ),
              ));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: _shape,
        child: InkWell(
          onTap: onTap,
          borderRadius: _shape,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 26, color: cs.onSurface),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (hasValue)
                        Padding(
                          padding: const EdgeInsets.only(left: 4, top: 10),
                          child: Text(
                            label,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      SizedBox(
                        height: hasValue ? null : 60,
                        child: Row(
                          crossAxisAlignment: hasValue
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                                child: Text(
                                  hasValue ? value! : label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w500,
                                    height: 1.2,
                                    color: valueIsHint
                                        ? cs.onSurfaceVariant.withValues(
                                            alpha: 0.8,
                                          )
                                        : cs.onSurface,
                                  ),
                                ),
                              ),
                            ),
                            end,
                          ],
                        ),
                      ),
                      Container(
                        height: 1,
                        color: cs.outlineVariant.withValues(alpha: 0.9),
                      ),
                    ],
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
