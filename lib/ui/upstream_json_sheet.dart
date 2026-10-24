import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/profile_export.dart';
import 'package:local2api/widgets/app_toast.dart';
import 'package:local2api/widgets/predictive_back_sheet.dart';

/// 「上游 JSON」弹层（Material 版，对应 miuix 版 `showMiuixUpstreamJsonSheet`）：
/// 格式化展示这一个上游的 JSON，可复制、可导出成 .json 文件。
///
/// 内容由 [upstreamJsonText] 生成（**apiKey 会被抹掉**），与档案级的
/// 「查看 JSON」同一个原则 —— 这一份是看/分享用的。
Future<void> showUpstreamJsonSheet(BuildContext context, Upstream upstream) =>
    showAppBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _UpstreamJsonSheet(upstream: upstream),
    );

class _UpstreamJsonSheet extends StatelessWidget {
  const _UpstreamJsonSheet({required this.upstream});

  final Upstream upstream;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = upstreamJsonText(upstream);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.upstreamJsonTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              upstream.name,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    text,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (!context.mounted) return;
                    showAppToast(context, l10n.profileJsonCopied);
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(l10n.profileJsonCopy),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    try {
                      final path = await exportTextFile(
                        fileName: jsonFileNameFor(upstream.name),
                        text: text,
                      );
                      if (!context.mounted || path == null) return;
                      showAppToast(context, l10n.profileJsonExported(path));
                    } catch (e) {
                      if (!context.mounted) return;
                      showAppToast(
                        context,
                        l10n.profileJsonExportFailed('$e'),
                        error: true,
                      );
                    }
                  },
                  icon: const Icon(Icons.save_alt, size: 18),
                  label: Text(l10n.profileJsonExport),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
