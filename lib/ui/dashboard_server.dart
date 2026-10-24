import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:local2api/services/server_controller.dart';

import 'active_connections_page.dart';
import 'logs_page.dart';
import 'token_stats_page.dart';
import 'widgets/common.dart';

/// 仪表盘的「服务」分区：启停、接入地址、风险提示、统计。
List<Widget> serverControlSections(
  ServerController controller, {
  VoidCallback? onOpenUpstreams,
  VoidCallback? onOpenKeys,
}) => [
  const SizedBox(height: 8),
  _StatusGrid(
    controller: controller,
    onOpenUpstreams: onOpenUpstreams,
    onOpenKeys: onOpenKeys,
  ),
  _EndpointCard(controller: controller),
  _WarningsCard(controller: controller),
  _StatsCard(controller: controller),
];

/// 最近请求分区：排在仪表盘末尾。
Widget recentLogsSection(ServerController controller) =>
    _RecentLogsCard(controller: controller);

/// 首页状态卡（Material 版，对应 InstallerX 的 `InstallerStatusCard`）。
///
/// InstallerX Material 首页是一张横幅卡：左侧状态图标（28dp）、右侧标题 +
/// 描述两行，容器色按状态二分（激活 = primaryContainer，未激活 =
/// errorContainer）；本 App 在此之上细分出「启动中」与「真异常」，异常时
/// 描述槽让位给错误详情。下面一排两张数值小卡（对应 `StatCard`）：
/// 大数值（headlineMedium，primary 色）在上、标签（labelMedium）在下，
/// 全部居中，容器色 surfaceBright，可点 —— 分别滚到「上游服务 / API 密钥」
/// 分组（InstallerX 里这两张卡也是 onClick 跳管理页）。
class _StatusGrid extends StatelessWidget {
  const _StatusGrid({
    required this.controller,
    this.onOpenUpstreams,
    this.onOpenKeys,
  });

  final ServerController controller;
  final VoidCallback? onOpenUpstreams;
  final VoidCallback? onOpenKeys;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder<ServerState>(
            valueListenable: controller.server.state,
            builder: (context, state, _) {
              final running = state == ServerState.running;
              final starting = state == ServerState.starting;
              final errored = state == ServerState.error;
              final active = running || starting;
              // InstallerX 二态（激活/未激活）；本 App 的「未启动」很常见，
              // 停止态沿用未激活的 errorContainer，与参考实现一致。
              final container = active
                  ? cs.primaryContainer
                  : cs.errorContainer;
              final content = active
                  ? cs.onPrimaryContainer
                  : cs.onErrorContainer;

              return ValueListenableBuilder<String?>(
                valueListenable: controller.server.lastError,
                builder: (context, lastError, _) => Card(
                  margin: EdgeInsets.zero,
                  color: container,
                  clipBehavior: Clip.antiAlias,
                  elevation: 1,
                  child: InkWell(
                    onTap: starting ? null : controller.toggle,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        children: [
                          Icon(
                            errored
                                ? Icons.error_outline
                                : active
                                ? Icons.task_alt
                                : Icons.warning_amber_rounded,
                            size: 28,
                            color: content,
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  starting
                                      ? l10n.serverStarting
                                      : running
                                      ? l10n.serverRunning
                                      : errored
                                      ? l10n.serverErrorTitle
                                      : l10n.serverStopped,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: content,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  // 异常且有详情时描述槽让位给错误详情。
                                  errored && lastError != null
                                      ? lastError
                                      : starting
                                      ? l10n.homeStatusDescStarting
                                      : running
                                      ? l10n.homeStatusDescRunning
                                      : errored
                                      ? l10n.homeStatusDescError
                                      : l10n.homeStatusDescStopped,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: content.withValues(alpha: 0.85),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          // 两张等高小卡。两个卡片内容结构一致，但字重/行高随系统缩放变化，
          // 所以用 IntrinsicHeight 而不是写死高度。
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _HomeStatCard(
                    title: l10n.upstreams,
                    value: '${controller.config.upstreams.length}',
                    onOpen: onOpenUpstreams,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _HomeStatCard(
                    title: l10n.keysTitle,
                    value: '${controller.config.apiKeys.length}',
                    onOpen: onOpenKeys,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 首页数值小卡（对应 InstallerX 的 `StatCard`）：ElevatedCard，数值
/// （headlineMedium、primary 色）在上、标签（labelMedium）在下，全部居中。
class _HomeStatCard extends StatelessWidget {
  const _HomeStatCard({required this.title, required this.value, this.onOpen});

  final String title;
  final String value;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 1,
      color: cs.surfaceBright,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w500,
                  color: cs.primary,
                ),
              ),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EndpointCard extends StatelessWidget {
  const _EndpointCard({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final config = controller.config;
    if (config.listenHost != '0.0.0.0') {
      return SectionCard(
        title: l10n.endpointTitle,
        child: CopyableRow(
          value: 'http://127.0.0.1:${config.listenPort}/v1',
          icon: Icons.computer,
        ),
      );
    }
    final ips = controller.lanAddresses;
    return SectionCard(
      title: l10n.endpointTitle,
      trailing: Text('/v1', style: Theme.of(context).textTheme.labelSmall),
      child: ips.isEmpty
          ? CopyableRow(value: 'http://0.0.0.0:${config.listenPort}/v1')
          : Column(
              children: [
                for (final ip in ips)
                  CopyableRow(
                    value: 'http://$ip:${config.listenPort}/v1',
                    icon: Icons.lan,
                  ),
              ],
            ),
    );
  }
}

class _WarningsCard extends StatelessWidget {
  const _WarningsCard({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final config = controller.config;
    final bool noKeys = config.apiKeys.isEmpty;
    final bool noRules = config.cidrRules.isEmpty;
    if (!noKeys && !noRules) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (noKeys) ...[
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.noKeysWarningTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 26),
                  child: Text(
                    l10n.noKeysWarningBody,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
              if (noRules) ...[
                if (noKeys) const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.public,
                      size: 18,
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.noCidrWarningTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 26),
                  child: Text(
                    l10n.noCidrWarningBody,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SectionCard(
      title: l10n.statsTitle,
      trailing: TextButton(
        onPressed: () => pushPage(context, const TokenStatsPage()),
        child: Text(l10n.usageOpen),
      ),
      child: Row(
        children: [
          ValueListenableBuilder<int>(
            valueListenable: controller.server.totalRequests,
            builder: (_, v, _) => StatTile(
              label: l10n.statTotalRequests,
              value: '$v',
              onTap: () => pushPage(
                context,
                LogsPage(
                  controller: controller,
                  initialFilter: LogStatusFilter.all,
                ),
              ),
            ),
          ),
          ValueListenableBuilder<int>(
            valueListenable: controller.server.totalErrors,
            builder: (_, v, _) => StatTile(
              label: l10n.statErrors,
              value: '$v',
              color: v > 0 ? theme.colorScheme.error : null,
              // 点「失败」进日志页就只看失败 —— 省得再筛一次。
              onTap: () => pushPage(
                context,
                LogsPage(
                  controller: controller,
                  initialFilter: LogStatusFilter.failed,
                ),
              ),
            ),
          ),
          ValueListenableBuilder<int>(
            valueListenable: controller.server.activeConnections,
            builder: (_, v, _) => StatTile(
              label: l10n.statActive,
              value: '$v',
              onTap: () => pushPage(
                context,
                ActiveConnectionsPage(controller: controller),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentLogsCard extends StatelessWidget {
  const _RecentLogsCard({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SectionCard(
      title: l10n.recentLogs,
      trailing: TextButton(
        onPressed: () => pushPage(context, LogsPage(controller: controller)),
        child: Text(l10n.viewAll),
      ),
      child: ValueListenableBuilder<List<RequestLogEntry>>(
        valueListenable: controller.server.logs,
        builder: (context, logs, _) {
          if (logs.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  l10n.noLogsYet,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }
          return Column(
            children: [
              for (final e in logs.take(4))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      _StatusDot(status: e.status),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${e.method} ${e.path}  ${e.model}',
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${e.durationMs}ms',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final int status;

  @override
  Widget build(BuildContext context) {
    final color = status < 300
        ? Colors.green
        : status < 400
        ? Colors.orange
        : Theme.of(context).colorScheme.error;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
