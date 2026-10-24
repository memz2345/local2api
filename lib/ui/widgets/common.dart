import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/src/enums.dart';
import 'package:local2api/widgets/app_tooltip.dart';
import 'package:local2api/widgets/app_toast.dart';
import 'package:provider/provider.dart';

/// 推入新页面：走 MaterialPageRoute，
/// 由 PageTransitionsTheme 里的 IosPushPageTransitionsBuilder 提供
/// NaviFlash 原版 iOS 推入动画（右滑入 + 圆角收拢 + 旧页左移压暗）。
Future<T?> pushPage<T>(
  BuildContext context,
  Widget page, {
  RouteSettings? settings,
}) {
  return Navigator.of(
    context,
  ).push(MaterialPageRoute<T>(settings: settings, builder: (_) => page));
}

/// 按当前界面风格挑一份页面实现推入。
///
/// 双风格是「同一个页面写两份」（对应 InstallerX 的 main / miuix 两套），
/// 业务逻辑共用，所以跳转点只需要在这里选一次，不必每处都写 if。
/// 两份实例都会被构造出来，所以页面构造函数必须保持廉价（别在里头做 IO）。
Future<T?> pushStyledPage<T>(
  BuildContext context, {
  required Widget material,
  required Widget miuix,
}) {
  final style = context.read<SettingsService>().uiStyle;
  return pushPage<T>(context, style.isMiuix ? miuix : material);
}

/// 带标题的圆角分组卡片。
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 8),
  });

  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: margin,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null || trailing != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title ?? '',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                      ?trailing,
                    ],
                  ),
                ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// 统计小方块。
///
/// [onTap] 给了就整块可点（仪表盘的三个数字分别跳到对应的明细页）。
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tile = Column(
      children: [
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    if (onTap == null) return Expanded(child: tile);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: tile,
        ),
      ),
    );
  }
}

void copyText(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  final l10n = AppLocalizations.of(context);
  showAppToast(context, l10n.copied);
}

/// 可复制的地址行。
class CopyableRow extends StatelessWidget {
  const CopyableRow({super.key, required this.value, this.icon});

  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon ?? Icons.link,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          AppTooltip(
            message: l10n.copy,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () => copyText(context, value),
            ),
          ),
        ],
      ),
    );
  }
}
