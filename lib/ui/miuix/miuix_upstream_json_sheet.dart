import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/profile_export.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';

/// miuix 风格的「上游 JSON」弹层：格式化展示这一个上游的 JSON，
/// 可复制、可导出成 .json 文件。
///
/// 内容由 [upstreamJsonText] 生成（**apiKey 会被抹掉**），与档案级的
/// 「查看 JSON」同一个原则 —— 这一份是看/分享用的。
Future<void> showMiuixUpstreamJsonSheet(
  BuildContext context,
  Upstream upstream,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: MiuixTheme.of(context).colors.surface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => _MiuixUpstreamJsonSheet(upstream: upstream),
);

class _MiuixUpstreamJsonSheet extends StatelessWidget {
  const _MiuixUpstreamJsonSheet({required this.upstream});

  final Upstream upstream;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    // 打开时重新序列化一次：弹层可能放在「保存」之后（页面持有的对象是同一个，
    // 但序列化结果得是当下的）。
    final text = upstreamJsonText(upstream);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MiuixText(
              l10n.upstreamJsonTitle,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
            const SizedBox(height: 4),
            MiuixText(
              upstream.name,
              fontSize: 12,
              color: colors.onSurfaceVariantSummary,
            ),
            const SizedBox(height: 10),
            Flexible(
              child: MiuixGroupCard(
                insideMargin: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
                MiuixTextButton(
                  l10n.profileJsonCopy,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (!context.mounted) return;
                    showMiuixToast(context, l10n.profileJsonCopied);
                  },
                ),
                const SizedBox(width: 8),
                MiuixTextButton(
                  l10n.profileJsonExport,
                  onPressed: () async {
                    try {
                      final path = await exportTextFile(
                        fileName: jsonFileNameFor(upstream.name),
                        text: text,
                      );
                      if (!context.mounted || path == null) return;
                      showMiuixToast(context, l10n.profileJsonExported(path));
                    } catch (e) {
                      if (!context.mounted) return;
                      showMiuixToast(
                        context,
                        l10n.profileJsonExportFailed('$e'),
                        error: true,
                      );
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
