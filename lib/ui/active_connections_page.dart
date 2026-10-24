// lib/ui/active_connections_page.dart
//
// 活跃连接页（Material 版）：谁在连、在跑哪个模型、连了多久。
//
// 数据源是 `ProxyServer.activeSessions` —— 请求进站建条目、响应写完才移除，
// 所以 SSE / 长连接会一直挂着（这正是要看的）。「已持续」按 1 秒一跳的
// 心跳重算，页面在前台时才是活的。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/widgets/frosted_page_bar.dart';

class ActiveConnectionsPage extends StatefulWidget {
  const ActiveConnectionsPage({super.key, required this.controller});

  final ServerController controller;

  @override
  State<ActiveConnectionsPage> createState() => _ActiveConnectionsPageState();
}

class _ActiveConnectionsPageState extends State<ActiveConnectionsPage> {
  /// 「已持续」的心跳：1s 一跳，只 rebuild 一个空 setState（便宜）。
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return FrostedBarPage(
      title: l10n.activeConnectionsTitle,
      child: ValueListenableBuilder<List<ActiveConnection>>(
        valueListenable: widget.controller.server.activeSessions,
        builder: (context, sessions, _) {
          if (sessions.isEmpty) {
            return Padding(
              padding: EdgeInsets.only(top: frostedPageBarInset(context) + 24),
              child: Center(
                child: Text(
                  l10n.activeConnectionsEmpty,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: EdgeInsets.fromLTRB(
              16,
              frostedPageBarInset(context) + 8,
              16,
              24,
            ),
            itemCount: sessions.length,
            itemBuilder: (context, i) =>
                _ActiveConnectionCard(session: sessions[i]),
          );
        },
      ),
    );
  }
}

class _ActiveConnectionCard extends StatelessWidget {
  const _ActiveConnectionCard({required this.session});

  final ActiveConnection session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final elapsed = DateTime.now().difference(session.startedAt);
    final started =
        '${session.startedAt.hour.toString().padLeft(2, '0')}:'
        '${session.startedAt.minute.toString().padLeft(2, '0')}:'
        '${session.startedAt.second.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.hub_outlined, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    session.clientIp,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    formatActiveDuration(elapsed),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _InfoLine(
              icon: Icons.smart_toy_outlined,
              label: l10n.modelLabel,
              value: session.model,
            ),
            const SizedBox(height: 2),
            _InfoLine(
              icon: Icons.route_outlined,
              label: l10n.activeConnPath,
              value: '${session.method} ${session.path}',
              mono: true,
            ),
            const SizedBox(height: 2),
            Text(
              '${l10n.activeConnStarted} $started · ${l10n.activeConnDuration} ${formatActiveDuration(elapsed)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
    this.mono = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: [
        Icon(icon, size: 15, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontFamily: mono ? 'monospace' : null,
              fontFeatures: mono ? const [FontFeature.tabularFigures()] : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// 已持续时间：`1:05:03` / `12:07`（超过一小时才带小时）。
String formatActiveDuration(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}
