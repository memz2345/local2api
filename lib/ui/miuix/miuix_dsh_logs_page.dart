// lib/ui/miuix/miuix_dsh_logs_page.dart
//
// DeepSeek Harness 运行日志（miuix 版）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../l10n/app_localizations.dart';
import '../../services/lab/dsh_service.dart';
import '../../widgets/miuix/miuix_app_icon.dart';
import '../../widgets/miuix/miuix_blur_top_bar.dart';
import '../../widgets/miuix/miuix_toast.dart';

class MiuixDshLogsPage extends StatefulWidget {
  const MiuixDshLogsPage({super.key});

  @override
  State<MiuixDshLogsPage> createState() => _MiuixDshLogsPageState();
}

class _MiuixDshLogsPageState extends State<MiuixDshLogsPage> {
  final DshService _dsh = DshService.instance;

  Future<void> _copy() async {
    final l10n = AppLocalizations.of(context);
    if (_dsh.logs.isEmpty) {
      showMiuixToast(context, l10n.labLogsEmpty, error: true);
      return;
    }
    await Clipboard.setData(ClipboardData(text: _dsh.logs.join('\n')));
    if (!mounted) return;
    showMiuixToast(context, l10n.labLogsCopied);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    return AnimatedBuilder(
      animation: _dsh,
      builder: (context, _) {
        final logs = _dsh.logs;
        return Material(
          type: MaterialType.transparency,
          child: MiuixScaffold(
            containerColor: colors.surface,
            topBar: MiuixBlurTopBar(
              title: l10n.labLogs,
              navigationIcon: MiuixIconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const MiuixAppIcon(
                  AppIconNames.back,
                  fallback: Icons.arrow_back,
                ),
              ),
              actions: [
                MiuixIconButton(
                  onPressed: _copy,
                  child: const MiuixAppIcon(
                    AppIconNames.copy,
                    fallback: Icons.copy_all_outlined,
                  ),
                ),
                MiuixIconButton(
                  onPressed: logs.isEmpty ? null : _dsh.clearLogs,
                  child: const MiuixAppIcon(
                    AppIconNames.delete,
                    fallback: Icons.delete_outline,
                  ),
                ),
              ],
            ),
            content: (padding) => Padding(
              padding: EdgeInsets.only(top: padding.top),
              child: logs.isEmpty
                  ? Center(
                      child: MiuixText(
                        l10n.labLogsEmpty,
                        fontSize: 14,
                        color: colors.onSurfaceVariantSummary,
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
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
                              color: colors.onSurfaceVariantSummary,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        );
      },
    );
  }
}
