// lib/ui/miuix/miuix_lab_logs_page.dart
//
// SillyTavern 运行日志（miuix 版）。从实验室首页的「日志」进来，独立一页，
// 不再挤在设置卡片里。
//
// 列表用 `reverse: true` + 倒序数据：新行永远贴在底部，用户往上翻看历史时
// 也不会被新日志顶走（相当于自动吸底，但不需要 ScrollController 手动补偿）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../l10n/app_localizations.dart';
import '../../services/lab/silly_tavern_service.dart';
import '../../widgets/miuix/miuix_app_icon.dart';
import '../../widgets/miuix/miuix_blur_top_bar.dart';
import '../../widgets/miuix/miuix_toast.dart';

class MiuixLabLogsPage extends StatefulWidget {
  const MiuixLabLogsPage({super.key});

  @override
  State<MiuixLabLogsPage> createState() => _MiuixLabLogsPageState();
}

class _MiuixLabLogsPageState extends State<MiuixLabLogsPage> {
  final SillyTavernService _st = SillyTavernService.instance;

  Future<void> _copy() async {
    final l10n = AppLocalizations.of(context);
    if (_st.logs.isEmpty) {
      showMiuixToast(context, l10n.labLogsEmpty, error: true);
      return;
    }
    await Clipboard.setData(ClipboardData(text: _st.logs.join('\n')));
    if (!mounted) return;
    showMiuixToast(context, l10n.labLogsCopied);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    return AnimatedBuilder(
      animation: _st,
      builder: (context, _) {
        final logs = _st.logs;
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
                  onPressed: logs.isEmpty ? null : _st.clearLogs,
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
