// lib/ui/lab_logs_page.dart
//
// SillyTavern 运行日志（Material 版）。从实验室首页的「日志」进来，
// 独立一页；miuix 版是 `ui/miuix/miuix_lab_logs_page.dart`。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/lab/silly_tavern_service.dart';
import '../widgets/app_toast.dart';
import '../widgets/expressive_app_bar.dart' show MorphIconButton;
import '../widgets/frosted_page_bar.dart';

class LabLogsPage extends StatefulWidget {
  const LabLogsPage({super.key});

  @override
  State<LabLogsPage> createState() => _LabLogsPageState();
}

class _LabLogsPageState extends State<LabLogsPage> {
  final SillyTavernService _st = SillyTavernService.instance;

  Future<void> _copy() async {
    final l10n = AppLocalizations.of(context);
    if (_st.logs.isEmpty) {
      showAppToast(context, l10n.labLogsEmpty, error: true);
      return;
    }
    await Clipboard.setData(ClipboardData(text: _st.logs.join('\n')));
    if (!mounted) return;
    showAppToast(context, l10n.labLogsCopied);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AnimatedBuilder(
      animation: _st,
      builder: (context, _) {
        final logs = _st.logs;
        return FrostedBarPage(
          title: l10n.labLogs,
          actions: [
            MorphIconButton(
              icon: Icons.copy_all_outlined,
              iconSize: 22,
              tooltip: l10n.labCopyLogs,
              transparent: true,
              onTap: _copy,
            ),
            MorphIconButton(
              icon: Icons.delete_outline,
              iconSize: 22,
              tooltip: l10n.labClearLogs,
              transparent: true,
              onTap: logs.isEmpty ? null : _st.clearLogs,
            ),
          ],
          child: logs.isEmpty
              ? Center(
                  child: Text(
                    l10n.labLogsEmpty,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    frostedPageBarInset(context) + 8,
                    16,
                    32,
                  ),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final line = logs[logs.length - 1 - index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: SelectableText(
                        line,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.45,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
