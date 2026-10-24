// lib/ui/miuix/miuix_active_connections_page.dart
//
// 活跃连接页（miuix 版，对应 Material 版 `ActiveConnectionsPage`）。
// 数据源与「已持续」的口径都在 Material 版那份里共用，这里只换渲染。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';

import '../active_connections_page.dart' show formatActiveDuration;

class MiuixActiveConnectionsPage extends StatefulWidget {
  const MiuixActiveConnectionsPage({super.key, required this.controller});

  final ServerController controller;

  @override
  State<MiuixActiveConnectionsPage> createState() =>
      _MiuixActiveConnectionsPageState();
}

class _MiuixActiveConnectionsPageState
    extends State<MiuixActiveConnectionsPage> {
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();

  /// 「已持续」的心跳：1s 一跳。
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
          title: l10n.activeConnectionsTitle,
          navigationIcon: MiuixIconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const MiuixAppIcon(
              AppIconNames.back,
              fallback: Icons.arrow_back,
            ),
          ),
        ),
        content: (padding) => MiuixScrollBehaviorListener(
          behavior: _behavior,
          child: ValueListenableBuilder<List<ActiveConnection>>(
            valueListenable: widget.controller.server.activeSessions,
            builder: (context, sessions, _) => ListView(
              // 内容不满屏时也要能拖动，否则大标题永远折叠不了
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(16, padding.top + 8, 16, 40),
              children: [
                if (sessions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: MiuixText(
                        l10n.activeConnectionsEmpty,
                        fontSize: 15,
                        textAlign: TextAlign.center,
                        color: colors.onSurfaceVariantSummary,
                      ),
                    ),
                  )
                else
                  for (final s in sessions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MiuixActiveConnectionCard(session: s),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiuixActiveConnectionCard extends StatelessWidget {
  const _MiuixActiveConnectionCard({required this.session});

  final ActiveConnection session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final elapsed = DateTime.now().difference(session.startedAt);
    final started =
        '${session.startedAt.hour.toString().padLeft(2, '0')}:'
        '${session.startedAt.minute.toString().padLeft(2, '0')}:'
        '${session.startedAt.second.toString().padLeft(2, '0')}';

    return MiuixGroupCard(
      cornerRadius: 16,
      insideMargin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MiuixAppIcon(
                AppIconNames.link,
                fallback: Icons.hub_outlined,
                size: 18,
                color: colors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MiuixText(
                  session.clientIp,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: MiuixText(
                  formatActiveDuration(elapsed),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _MiuixInfoLine(
            icon: Icons.smart_toy_outlined,
            label: l10n.modelLabel,
            value: session.model,
          ),
          const SizedBox(height: 2),
          _MiuixInfoLine(
            icon: Icons.route_outlined,
            label: l10n.activeConnPath,
            value: '${session.method} ${session.path}',
            mono: true,
          ),
          const SizedBox(height: 4),
          MiuixText(
            '${l10n.activeConnStarted} $started · '
            '${l10n.activeConnDuration} ${formatActiveDuration(elapsed)}',
            fontSize: 12,
            color: colors.onSurfaceVariantSummary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _MiuixInfoLine extends StatelessWidget {
  const _MiuixInfoLine({
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
    final colors = MiuixTheme.of(context).colors;
    return Row(
      children: [
        Icon(icon, size: 15, color: colors.onSurfaceVariantActions),
        const SizedBox(width: 6),
        MiuixText(
          '$label: ',
          fontSize: 13,
          color: colors.onSurfaceVariantSummary,
        ),
        Expanded(
          child: MiuixText(
            value,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFamily: mono ? 'monospace' : null,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
