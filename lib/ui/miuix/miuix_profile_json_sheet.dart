import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/config_profile.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/profile_export.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';
import 'package:provider/provider.dart';

/// miuix 风格的「查看 JSON」弹层：格式化展示这一组的有效 JSON，
/// 可复制、可导出成 .json 文件。
///
/// 看的是**有效档案**（用户起过的名字 / 写过的说明 / 模型页改过的模型列表 /
/// 注入的实时车道都在里面），不是原始订阅文档 —— 这样「看到的」就是这一组
/// 现在的真实样子，更新/刷新模型之后再打开就是新的。
/// 导入仍走 FAB 那颗「新建上游」。
Future<void> showMiuixProfileJsonSheet(
  BuildContext context,
  ConfigProfile profile,
  ProxyConfig config,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: MiuixTheme.of(context).colors.surface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => _MiuixProfileJsonSheet(profile: profile, config: config),
);

class _MiuixProfileJsonSheet extends StatelessWidget {
  const _MiuixProfileJsonSheet({required this.profile, required this.config});

  final ConfigProfile profile;
  final ProxyConfig config;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    // 打开时从注册表取最新一份：页面持有的 profile 可能是进车道页时的快照，
    // 「更新 / 刷新模型」之后就旧了。
    final fresh = context.read<ProfileStore>().profileOf(profile.id) ?? profile;
    final text = profileJsonText(fresh, config);
    final isBuiltin = fresh.source.kind == ProfileSourceKind.builtin;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MiuixText(
              l10n.profileJsonTitle,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
            const SizedBox(height: 4),
            MiuixText(
              // 内置组的 JSON 是代码生成的，明说一句；导入组就用组名当副标题。
              isBuiltin ? l10n.profileJsonBuiltin : fresh.name,
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
                        fileName: jsonFileNameFor(fresh.name),
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
