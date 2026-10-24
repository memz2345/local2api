import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_info_card.dart';
import 'package:local2api/widgets/miuix/miuix_tilt_card.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';
import 'package:provider/provider.dart';

import 'miuix_active_connections_page.dart';
import 'miuix_logs_page.dart';
import 'miuix_token_stats_page.dart';

/// 仪表盘的「服务」分区（miuix 版，对应 Material 版 `serverControlSections`）。
///
/// 分区顺序：状态卡 → 接入地址 → 请求统计（风险提示已挪到页面顶部，
/// 见 [miuixWarningsTipSection]）。
/// 状态/错误/计数这些实时值仍然各自用 ValueListenableBuilder 精确重建，
/// 没有因为换皮就把粒度放大到整页。
List<Widget> miuixServerSections(
  ServerController controller, {
  VoidCallback? onOpenUpstreams,
  VoidCallback? onOpenKeys,
}) => [
  const SizedBox(height: 4),
  _MiuixStatusGrid(
    controller: controller,
    onOpenUpstreams: onOpenUpstreams,
    onOpenKeys: onOpenKeys,
  ),
  _MiuixEndpointSection(controller: controller),
  _MiuixStatsSection(controller: controller),
];

/// 仪表盘顶部的风险提示（「仪表盘」标题与出血大卡之间）。
///
/// 图2 / InstallerX 配置页样式：**一个 info 一张淡蓝提示卡**（蓝底蓝字 +
/// 行尾 X），一张卡里绝不塞两条 info。关闭逐条记忆（见
/// [SettingsService.warningsTipDismissedSigOf]）：按「警告组合签名」记，
/// 同一条的组合不变不再弹，组合一变（新增/消失某条）就重新显示。
Widget miuixWarningsTipSection(ServerController controller) =>
    _MiuixWarningsSection(controller: controller);

/// 最近请求分区（miuix 版，排在仪表盘末尾）。
Widget miuixRecentLogsSection(ServerController controller) =>
    _MiuixRecentLogsSection(controller: controller);

/// 分组小标题（可带尾部动作）。MiuixSmallTitle 只吃文本，
/// Material 版 SectionCard 的 title+trailing 这里自己拼一行。
class _MiuixSectionHeader extends StatelessWidget {
  const _MiuixSectionHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 18, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: MiuixSmallTitle(title, insideMargin: EdgeInsets.zero),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 首页状态网格（miuix 版，对应 InstallerX 的 `MiuixStatusGrid` / KSU 的
/// `StatusCard`）。
///
/// 大卡照 InstallerX 1:1：三槽位（状态标题 20sp SemiBold / 状态描述 14sp
/// Medium α0.8 / 第三槽 14sp）；右下角 170dp 大水印图标按 offset(50,38)
/// 出血、被卡面裁掉一部分（与 InstallerX/KSU 的 `CheckCircleOutline` /
/// `ErrorOutline` 角标同款）；容器色二态 —— 动态取色时 secondaryContainer /
/// errorContainer，固定主题时用 InstallerX 的硬编码配色（暗 0xFF1A3825 /
/// 0xFF381A1A，亮 0xFFDFFAE4 / 0xFFFAEEEE），水印 tint 用 0xFF36D167 /
/// 0xFFD13636（动态取色时 primary / error @0.8）。
/// 本 App 的「启动中」归入激活态；点大卡启停服务。
/// 两张小卡可点：分别滚到「上游服务 / API 密钥」分区（对应 InstallerX 里
/// `MiuixStatCard(onClick = …)` 的跳转语义，管理界面就是本页分区）。
///
/// 按压反馈用 [MiuixTiltCard]：tilt 时整个卡面（背景+内容）一起绕触点
/// 对角倾斜，与 InstallerX 的 `PressFeedbackType.Tilt` 一致；包版 MiuixCard
/// 的 tilt 只动内容不动卡面。
class _MiuixStatusGrid extends StatelessWidget {
  const _MiuixStatusGrid({
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
    final theme = MiuixTheme.of(context);
    final colors = theme.colors;
    final useDynamic = context.read<SettingsService>().useDynamicColor;
    final isDark = theme.brightness == Brightness.dark;
    final config = controller.config;
    final address = '${config.listenHost}:${config.listenPort}';

    return Padding(
      // 横向不能再加 16：外层 ListView 已统一给过 16，这里再加会让上面三张卡
      // （状态大卡 + 两张数值卡）比下面的接入地址/提示/统计卡窄一圈。
      padding: const EdgeInsets.symmetric(vertical: 4),
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
              // 二态配色，与 InstallerX/KSU 完全一致；「启动中」归激活态。
              final Color container;
              final Color onContainer;
              if (useDynamic) {
                container = active
                    ? colors.secondaryContainer
                    : colors.errorContainer;
                onContainer = active
                    ? colors.onSecondaryContainer
                    : colors.onErrorContainer;
              } else {
                container = active
                    ? (isDark
                          ? const Color(0xFF1A3825)
                          : const Color(0xFFDFFAE4))
                    : (isDark
                          ? const Color(0xFF381A1A)
                          : const Color(0xFFFAEEEE));
                onContainer = colors.onSurface;
              }
              final descColor = onContainer.withValues(alpha: 0.8);
              // 水印 tint：动态取色 primary/error @0.8；固定主题用 InstallerX
              // 的 miuixHomeStatusCardColorActivated / Deactivated。
              final iconTint = useDynamic
                  ? (active ? colors.primary : colors.error).withValues(
                      alpha: 0.8,
                    )
                  : active
                  ? const Color(0xFF36D167)
                  : const Color(0xFFD13636);

              return ValueListenableBuilder<String?>(
                valueListenable: controller.server.lastError,
                builder: (context, lastError, _) => MiuixTiltCard(
                  colors: MiuixCardColors(
                    color: container,
                    contentColor: onContainer,
                  ),
                  onPressed: starting ? null : controller.toggle,
                  feedbackType: MiuixPressFeedbackType.tilt,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 角落背景水印：170dp 大图标，向右下出血 50/38，被卡面
                      // squircle 裁掉一部分 —— InstallerX/KSU 的原版做法。
                      Positioned(
                        right: -50,
                        bottom: -38,
                        child: Icon(
                          active
                              ? Icons.check_circle_outline_rounded
                              : Icons.error_outline_rounded,
                          size: 170,
                          color: iconTint,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MiuixText(
                              starting
                                  ? l10n.serverStarting
                                  : running
                                  ? l10n.serverRunning
                                  : errored
                                  ? l10n.serverErrorTitle
                                  : l10n.serverStopped,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: onContainer,
                            ),
                            const SizedBox(height: 2),
                            MiuixText(
                              starting
                                  ? l10n.homeStatusDescStarting
                                  : running
                                  ? l10n.homeStatusDescRunning
                                  : errored
                                  ? l10n.homeStatusDescError
                                  : l10n.homeStatusDescStopped,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: descColor,
                            ),
                            const SizedBox(height: 36),
                            // 第三槽位：异常时给错误详情，否则给监听地址
                            // （地址只在这里出现一次，不在描述里重复）
                            MiuixText(
                              errored && lastError != null
                                  ? lastError
                                  : address,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: errored ? colors.error : descColor,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _MiuixHomeStatCard(
                    title: l10n.upstreams,
                    value: '${config.upstreams.length}',
                    onOpen: onOpenUpstreams,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MiuixHomeStatCard(
                    title: l10n.keysTitle,
                    value: '${config.apiKeys.length}',
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

/// 首页数值小卡（对应 InstallerX 的 `MiuixStatCard`）：
/// 标题（15sp `onSurfaceVariantSummary`）在上、数值（26sp `onSurface`）在下，
/// 左对齐、两卡等高。可点击：滚到对应管理分区，按压 tilt（InstallerX 同款）。
class _MiuixHomeStatCard extends StatelessWidget {
  const _MiuixHomeStatCard({
    required this.title,
    required this.value,
    this.onOpen,
  });

  final String title;
  final String value;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixTiltCard(
      insideMargin: const EdgeInsets.all(16),
      onPressed: onOpen,
      feedbackType: MiuixPressFeedbackType.tilt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          MiuixText(
            title,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: colors.onSurfaceVariantSummary,
          ),
          MiuixText(
            value,
            fontSize: 26,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
        ],
      ),
    );
  }
}

class _MiuixEndpointSection extends StatelessWidget {
  const _MiuixEndpointSection({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final config = controller.config;
    if (config.listenHost != '0.0.0.0') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MiuixSectionHeader(title: l10n.endpointTitle),
          MiuixGroupCard(
            insideMargin: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            child: _MiuixCopyableRow(
              value: 'http://127.0.0.1:${config.listenPort}/v1',
              icon: Icons.computer,
            ),
          ),
        ],
      );
    }
    final ips = controller.lanAddresses;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MiuixSectionHeader(
          title: l10n.endpointTitle,
          trailing: MiuixText(
            '/v1',
            fontSize: 12,
            color: colors.onSurfaceVariantSummary,
          ),
        ),
        MiuixGroupCard(
          insideMargin: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          child: Column(
            children: [
              if (ips.isEmpty)
                _MiuixCopyableRow(
                  value: 'http://0.0.0.0:${config.listenPort}/v1',
                )
              else
                for (final ip in ips)
                  _MiuixCopyableRow(
                    value: 'http://$ip:${config.listenPort}/v1',
                    icon: Icons.lan,
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiuixWarningsSection extends StatelessWidget {
  const _MiuixWarningsSection({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final config = controller.config;
    final bool noKeys = config.apiKeys.isEmpty;
    final bool noRules = config.cidrRules.isEmpty;
    if (!noKeys && !noRules) return const SizedBox.shrink();
    // 关闭按「警告组合签名」逐条记忆：同一条的组合不变就不再弹，
    // 组合一变（新增/消失某条）就重新显示。见
    // SettingsService.warningsTipDismissedSigOf。
    final String sig = [if (noKeys) 'keys', if (noRules) 'rules'].join('+');
    final settings = context.watch<SettingsService>();
    // 一个 info 一张卡（图2 样式）：两张提示就是两张卡，绝不合卡。
    final cards = <Widget>[
      if (noKeys && settings.warningsTipDismissedSigOf('keys') != sig)
        _MiuixWarningCard(
          id: 'keys',
          sig: sig,
          title: l10n.noKeysWarningTitle,
          body: l10n.noKeysWarningBody,
        ),
      if (noRules && settings.warningsTipDismissedSigOf('rules') != sig)
        _MiuixWarningCard(
          id: 'rules',
          sig: sig,
          title: l10n.noCidrWarningTitle,
          body: l10n.noCidrWarningBody,
        ),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            cards[i],
          ],
        ],
      ),
    );
  }
}

/// 一条风险提示卡（InstallerX `MiuixCards.kt` 的 `TipCard` 配方，
/// 配置页那张淡蓝 info 就是它）：`primaryContainer` 25% 透明打底、
/// primary 蓝字（标题粗体、正文跟上），行尾 X 逐条关闭。
/// 一张卡只装一个 info，多条提示拆多张卡。
class _MiuixWarningCard extends StatelessWidget {
  const _MiuixWarningCard({
    required this.id,
    required this.sig,
    required this.title,
    required this.body,
  });

  /// 关闭记忆的键（keys / rules），见 [SettingsService.warningsTipDismissedSigOf]。
  final String id;

  /// 关闭时的警告组合签名：组合一变这条就重新显示。
  final String sig;

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return MiuixInfoCard(
      title: title,
      text: body,
      onClose: () =>
          context.read<SettingsService>().setWarningsTipDismissedSig(id, sig),
    );
  }
}

class _MiuixStatsSection extends StatelessWidget {
  const _MiuixStatsSection({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MiuixSectionHeader(
          title: l10n.statsTitle,
          // 这一页是本机代理的 token 账本（输入 / 输出 / 缓存命中），
          // 放在请求统计旁边最顺手。
          trailing: MiuixTextButton(
            l10n.usageOpen,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const MiuixTokenStatsPage(),
              ),
            ),
          ),
        ),
        MiuixGroupCard(
          insideMargin: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          child: Row(
            children: [
              ValueListenableBuilder<int>(
                valueListenable: controller.server.totalRequests,
                builder: (_, v, _) => _MiuixStatTile(
                  label: l10n.statTotalRequests,
                  value: '$v',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MiuixLogsPage(
                        controller: controller,
                        initialFilter: LogStatusFilter.all,
                      ),
                    ),
                  ),
                ),
              ),
              ValueListenableBuilder<int>(
                valueListenable: controller.server.totalErrors,
                builder: (_, v, _) => _MiuixStatTile(
                  label: l10n.statErrors,
                  value: '$v',
                  color: v > 0 ? colors.error : null,
                  // 点「失败」进日志页就只看失败 —— 省得再筛一次。
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MiuixLogsPage(
                        controller: controller,
                        initialFilter: LogStatusFilter.failed,
                      ),
                    ),
                  ),
                ),
              ),
              ValueListenableBuilder<int>(
                valueListenable: controller.server.activeConnections,
                builder: (_, v, _) => _MiuixStatTile(
                  label: l10n.statActive,
                  value: '$v',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          MiuixActiveConnectionsPage(controller: controller),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiuixStatTile extends StatelessWidget {
  const _MiuixStatTile({
    required this.label,
    required this.value,
    this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final Color? color;

  /// 给了就整块可点（三个数字分别跳到对应的明细页）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final tile = Column(
      children: [
        MiuixText(
          value,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: color,
        ),
        const SizedBox(height: 2),
        MiuixText(
          label,
          fontSize: 12,
          color: colors.onSurfaceVariantSummary,
          textAlign: TextAlign.center,
        ),
      ],
    );
    if (onTap == null) return Expanded(child: tile);
    return Expanded(
      child: MiuixGroupCard(
        cornerRadius: 12,
        insideMargin: const EdgeInsets.symmetric(vertical: 6),
        feedbackType: MiuixPressFeedbackType.sink,
        onPressed: onTap,
        child: tile,
      ),
    );
  }
}

class _MiuixRecentLogsSection extends StatelessWidget {
  const _MiuixRecentLogsSection({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MiuixSectionHeader(
          title: l10n.recentLogs,
          trailing: MiuixTextButton(
            l10n.viewAll,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MiuixLogsPage(controller: controller),
              ),
            ),
          ),
        ),
        MiuixGroupCard(
          insideMargin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: ValueListenableBuilder<List<RequestLogEntry>>(
            valueListenable: controller.server.logs,
            builder: (context, logs, _) {
              if (logs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: MiuixText(
                      l10n.noLogsYet,
                      fontSize: 13,
                      color: colors.onSurfaceVariantSummary,
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
                          _MiuixStatusDot(status: e.status),
                          const SizedBox(width: 10),
                          Expanded(
                            child: MiuixText(
                              '${e.method} ${e.path}  ${e.model}',
                              fontSize: 13,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          MiuixText(
                            '${e.durationMs}ms',
                            fontSize: 12,
                            color: colors.onSurfaceVariantSummary,
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MiuixStatusDot extends StatelessWidget {
  const _MiuixStatusDot({required this.status});

  final int status;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final color = status < 300
        ? const Color(0xFF2BA471)
        : status < 400
        ? const Color(0xFFE39A2B)
        : colors.error;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// 可复制的地址行（miuix 版）：等宽地址 + MiuixIconButton 复制。
class _MiuixCopyableRow extends StatelessWidget {
  const _MiuixCopyableRow({required this.value, this.icon});

  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon ?? Icons.link,
            size: 16,
            color: colors.onSurfaceVariantSummary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: MiuixText(
              value,
              fontSize: 14,
              fontFamily: 'monospace',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          MiuixIconButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              showMiuixToast(context, l10n.copied);
            },
            child: const Icon(Icons.copy, size: 18),
          ),
        ],
      ),
    );
  }
}
