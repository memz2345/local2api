import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/widgets/app_toast.dart';
import 'package:local2api/widgets/expressive_app_bar.dart';
import 'package:local2api/widgets/frosted_page_bar.dart';
import 'package:local2api/widgets/navi_oval_tab_row.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:local2api/services/server_controller.dart';

import 'widgets/log_filter_bar.dart';

/// 全量请求日志页。
///
/// [initialFilter]：仪表盘的统计卡片带进来的预选（点「失败」进来只看失败）。
class LogsPage extends StatefulWidget {
  const LogsPage({super.key, required this.controller, this.initialFilter});

  final ServerController controller;
  final LogStatusFilter? initialFilter;

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  late LogStatusFilter _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter ?? LogStatusFilter.all;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // 页面级的互斥筛选进顶栏 tab 行（NaviFlash 分区/搜索同款），不再是内容区
    // 悬浮的 FilterChip 一排；顶栏的毛玻璃面板会把这一行和标题行包在同一块里。
    final filterLabels = [
      for (final f in LogStatusFilter.values) logFilterLabel(l10n, f),
    ];
    return FrostedBarPage(
      title: l10n.logsTitle,
      actions: [
        MorphIconButton(
          icon: Icons.delete_sweep_outlined,
          tooltip: l10n.clearLogs,
          transparent: true,
          onTap: () {
            widget.controller.server.logs.value = [];
            showAppToast(context, l10n.logsCleared);
          },
        ),
      ],
      bottomHeight: kNaviOvalTabRowHeight,
      bottom: NaviOvalTabRow(
        labels: filterLabels,
        selectedIndex: LogStatusFilter.values.indexOf(_filter),
        onTap: (i) => setState(() => _filter = LogStatusFilter.values[i]),
        glassTabs: naviGlassTabsFromLabels(filterLabels),
      ),
      child: ValueListenableBuilder<List<RequestLogEntry>>(
        valueListenable: widget.controller.server.logs,
        builder: (context, logs, _) {
          // 筛选只影响显示：清空按钮清的还是全部日志。
          final shown = [
            for (final e in logs)
              if (logEntryMatches(e, _filter)) e,
          ];
          // 首屏占位 = 状态栏 + 标题行 + tab 行（顶栏悬浮在内容之上，
          // 内容得自己让开）。
          final topInset = frostedPageBarInset(
            context,
            bottomHeight: kNaviOvalTabRowHeight,
          );
          if (shown.isEmpty) {
            return Padding(
              padding: EdgeInsets.only(top: topInset + 24),
              child: Center(
                child: Text(
                  logs.isEmpty ? l10n.noLogsYet : l10n.logsEmptyFiltered,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(16, topInset + 8, 16, 24),
            itemCount: shown.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, i) => _LogRow(entry: shown[i]),
          );
        },
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final RequestLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final e = entry;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _timeOf(e.time),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: _statusColor(
                    context,
                    e.status,
                  ).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${e.status}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _statusColor(context, e.status),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 「方法 路径」可能很长（长路径 / 长查询串），给它一个可收缩的槽
              // 而不是让它把时长挤出去 —— 不套 Expanded 会横向溢出。
              Expanded(
                child: Text(
                  '${e.method} ${e.path}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${e.durationMs}ms',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${l10n.modelLabel}: ${e.model}   ·   ${l10n.clientLabel}: ${e.client}   ·   ${e.upstream}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (e.error != null)
            Text(
              e.error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

/// 时:分:秒（日志行的时间戳）。
String _timeOf(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

Color _statusColor(BuildContext context, int status) {
  if (status < 300) return Colors.green;
  if (status < 400) return Colors.orange;
  return Theme.of(context).colorScheme.error;
}
