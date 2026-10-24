import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/services/settings_service.dart';

import 'miuix_group_card.dart';

/// miuix 信息提示卡（InstallerX `ui/page/miuix/widgets/MiuixCards.kt` 里
/// `TipCard` 的 Flutter 移植，配置页那张淡蓝 info 就是它）。
///
/// 上游配方：
///   - 底 = `primaryContainer` **25% 透明**。这条是关键：直接拿
///     `primaryContainer` 当底会跟 `primary` 蓝字撞色 —— 全默认（静态
///     HyperOS）配色下 `primaryContainer` 是 `0xFF5D9BFF` 这种中蓝，
///     蓝底蓝字根本看不清（所以之前那版看着很奇怪）；
///   - 文字 = `primary` 蓝 + 半粗，`body2`（14sp）；标题加一档大小/字重；
///   - 行尾 X：22dp 的 `primary` 蓝图标，只关这一张卡；
///   - 内边距 16（有 X 时右侧收到 12）。
class MiuixInfoCard extends StatelessWidget {
  const MiuixInfoCard({
    super.key,
    required this.text,
    this.title,
    this.onClose,
  });

  /// 正文。
  final String text;

  /// 可选标题（「标题 + 说明」两行式，仪表盘风险提示在用）。
  final String? title;

  /// 给了就在行尾画 X。
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixGroupCard(
      insideMargin: EdgeInsets.fromLTRB(16, 16, onClose == null ? 16 : 12, 16),
      colors: MiuixCardColors(
        color: colors.primaryContainer.withValues(alpha: 0.25),
        contentColor: colors.onSurface,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  MiuixText(
                    title!,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.primary,
                  ),
                  const SizedBox(height: 4),
                ],
                MiuixText(
                  text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ],
            ),
          ),
          if (onClose != null) ...[
            const SizedBox(width: 8),
            MiuixIconButton(
              onPressed: onClose,
              minWidth: 36,
              minHeight: 36,
              child: Icon(Icons.close, size: 22, color: colors.primary),
            ),
          ],
        ],
      ),
    );
  }
}

/// 可关闭的说明卡：X 的关闭状态按 [id] 记在 [SettingsService] 里
/// （关了就记住，重启后不再显示 —— 见 `SettingsService.dismissInfoCard`）。
/// 直接丢进页面的列表里用，页面自己不用管状态；只重建这张卡，不动整页。
class MiuixDismissibleInfoCard extends StatelessWidget {
  const MiuixDismissibleInfoCard({
    super.key,
    required this.id,
    required this.text,
  });

  /// 关闭记忆的键，各页唯一（如 `intro.keys`），不复用。
  final String id;

  final String text;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: SettingsService.infoCardDismissals,
      builder: (context, _, _) {
        if (SettingsService.infoCardDismissed(id)) {
          return const SizedBox.shrink();
        }
        return MiuixInfoCard(
          text: text,
          onClose: () => SettingsService.dismissInfoCard(id),
        );
      },
    );
  }
}
