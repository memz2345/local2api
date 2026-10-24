import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';

import 'miuix_log_filter_bar.dart';

/// 全量请求日志页（miuix 版，对应 Material 版 `LogsPage`）。
///
/// 日志源仍是 `controller.server.logs` 这一个 ValueNotifier，
/// 空态与全量态都用 ValueListenableBuilder 精确重建；
/// 顶栏用 [MiuixBlurTopBar]（毛玻璃 + 可折叠大标题模糊）+ 返回键，
/// 内容铺满整页从栏下穿过（与仪表盘/发现/设置同款）。
class MiuixLogsPage extends StatefulWidget {
  const MiuixLogsPage({
    super.key,
    required this.controller,
    this.initialFilter,
  });

  final ServerController controller;

  /// 仪表盘的统计卡片带进来的预选（点「失败」进来只看失败）。
  final LogStatusFilter? initialFilter;

  @override
  State<MiuixLogsPage> createState() => _MiuixLogsPageState();
}

class _MiuixLogsPageState extends State<MiuixLogsPage> {
  /// 二级页统一的可折叠大标题行为；`MiuixBlurTopBar` 读它，
  /// `MiuixScrollBehaviorListener` 在外层把滚动通知喂给它。
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();

  late LogStatusFilter _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter ?? LogStatusFilter.all;
  }

  @override
  void dispose() {
    _behavior.state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    return Material(
      type: MaterialType.transparency,
      child: MiuixScaffold(
        containerColor: colors.surface,
        topBar: MiuixBlurTopBar(
          scrollBehavior: _behavior,
          title: l10n.logsTitle,
          navigationIcon: MiuixIconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const MiuixAppIcon(
              AppIconNames.back,
              fallback: Icons.arrow_back,
            ),
          ),
          actions: [
            MiuixIconButton(
              onPressed: () {
                widget.controller.server.logs.value = [];
                showMiuixToast(context, l10n.logsCleared);
              },
              child: const MiuixAppIcon(
                AppIconNames.delete,
                fallback: Icons.delete_sweep_outlined,
              ),
            ),
          ],
        ),
        // 内容铺满整页、顶栏画在其上；顶栏高度垫进 padding，从栏下穿过。
        content: (padding) => MiuixScrollBehaviorListener(
          behavior: _behavior,
          child: ValueListenableBuilder<List<RequestLogEntry>>(
            valueListenable: widget.controller.server.logs,
            builder: (context, logs, _) {
              // 筛选只影响显示：清空按钮清的还是全部日志。
              final shown = [
                for (final e in logs)
                  if (logEntryMatches(e, _filter)) e,
              ];
              return ListView(
                // 内容不满屏时也要能拖动，否则大标题永远折叠不了
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(16, padding.top + 8, 16, 40),
                children: [
                  MiuixLogFilterBar(
                    value: _filter,
                    onChanged: (f) => setState(() => _filter = f),
                  ),
                  const SizedBox(height: 12),
                  if (shown.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: MiuixText(
                          logs.isEmpty
                              ? l10n.noLogsYet
                              : l10n.logsEmptyFiltered,
                          fontSize: 15,
                          textAlign: TextAlign.center,
                          color: colors.onSurfaceVariantSummary,
                        ),
                      ),
                    )
                  else
                    for (final e in shown) _MiuixLogRow(entry: e),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MiuixLogRow extends StatelessWidget {
  const _MiuixLogRow({required this.entry});

  final RequestLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final e = entry;
    final time =
        '${e.time.hour.toString().padLeft(2, '0')}:'
        '${e.time.minute.toString().padLeft(2, '0')}:'
        '${e.time.second.toString().padLeft(2, '0')}';
    final statusColor = e.status < 300
        ? const Color(0xFF2BA471)
        : e.status < 400
        ? const Color(0xFFE39A2B)
        : colors.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MiuixGroupCard(
        cornerRadius: 16,
        insideMargin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                MiuixText(
                  time,
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: colors.onSurfaceVariantSummary,
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: MiuixText(
                    '${e.status}',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: MiuixText(
                    '${e.method} ${e.path}',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                MiuixText(
                  '${e.durationMs}ms',
                  fontSize: 12,
                  color: colors.onSurfaceVariantSummary,
                ),
              ],
            ),
            const SizedBox(height: 3),
            MiuixText(
              '${l10n.modelLabel}: ${e.model}   ·   '
              '${l10n.clientLabel}: ${e.client}   ·   ${e.upstream}',
              fontSize: 12,
              color: colors.onSurfaceVariantSummary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (e.error != null)
              MiuixText(
                e.error!,
                fontSize: 12,
                color: colors.error,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}
