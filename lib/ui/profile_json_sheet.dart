import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/config_profile.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/profile_export.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:local2api/widgets/app_toast.dart';
import 'package:provider/provider.dart';

/// 「查看 JSON」弹层（Material 版）：格式化展示这一组的有效 JSON，
/// 可复制、可导出成 .json 文件。导入仍走 FAB「新建上游」。
Future<void> showProfileJsonSheet(
  BuildContext context,
  ConfigProfile profile,
  ProxyConfig config,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ProfileJsonSheet(profile: profile, config: config),
);

class _ProfileJsonSheet extends StatelessWidget {
  const _ProfileJsonSheet({required this.profile, required this.config});

  final ConfigProfile profile;
  final ProxyConfig config;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // 打开时从注册表取最新一份：页面持有的 profile 可能是进车道页时的快照，
    // 「更新 / 刷新模型」之后就旧了。
    final fresh = context.read<ProfileStore>().profileOf(profile.id) ?? profile;
    final text = profileJsonText(fresh, config);
    final isBuiltin = fresh.source.kind == ProfileSourceKind.builtin;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.profileJsonTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              // 内置组的 JSON 是代码生成的，明说一句；导入组就用组名当副标题。
              isBuiltin ? l10n.profileJsonBuiltin : fresh.name,
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
                        fileName: jsonFileNameFor(fresh.name),
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
