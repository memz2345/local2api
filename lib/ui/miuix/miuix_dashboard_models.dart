import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/server_controller.dart';

import 'miuix_upstream_edit_page.dart';

/// 仪表盘的「上游服务 + 对外模型」分区（miuix 版，对应 `modelSections`）。
///
/// 跳转一律进 miuix 版上游编辑页，不再回到 Material 实现。
/// [upstreamsSectionKey] 挂在「上游服务」分区头上，供状态卡跳转定位。
List<Widget> miuixModelSections(
  BuildContext context,
  ServerController controller, {
  Key? upstreamsSectionKey,
}) {
  final l10n = AppLocalizations.of(context);
  final colors = MiuixTheme.of(context).colors;
  final upstreams = controller.config.upstreams;
  final exposed = <ModelEntry>[];
  for (final u in upstreams) {
    if (!u.enabled) continue;
    for (final m in u.models) {
      if (m.enabled) exposed.add(m);
    }
  }
  return [
    _MiuixSectionHeader(
      title: l10n.exposedModelsTitle,
      trailing: MiuixText(
        '${exposed.length}',
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: colors.onSurfaceVariantSummary,
      ),
    ),
    MiuixGroupCard(
      insideMargin: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: exposed.isEmpty
          ? MiuixText(
              l10n.noExposedModels,
              fontSize: 13,
              color: colors.onSurfaceVariantSummary,
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in exposed)
                  _MiuixPill(
                    label: m.publicName,
                    background: colors.secondaryContainer,
                    foreground: colors.onSecondaryContainer,
                  ),
              ],
            ),
    ),
    _MiuixSectionHeader(
      key: upstreamsSectionKey,
      title: l10n.upstreams,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 峰谷时段已经挪进「编辑上游」页（备注下面），这一排只留新建上游。
          MiuixIconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MiuixUpstreamEditPage(controller: controller),
              ),
            ),
            child: const MiuixAppIcon(
              AppIconNames.addCircle,
              fallback: Icons.add_circle_outline,
            ),
          ),
        ],
      ),
    ),
    MiuixGroupCard(
      insideMargin: EdgeInsets.zero,
      child: upstreams.isEmpty
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: MiuixText(
                l10n.noUpstreams,
                fontSize: 13,
                color: colors.onSurfaceVariantSummary,
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < upstreams.length; i++) ...[
                  if (i > 0) const MiuixHorizontalDivider(),
                  _MiuixUpstreamRow(
                    controller: controller,
                    upstream: upstreams[i],
                  ),
                ],
              ],
            ),
    ),
  ];
}

class _MiuixUpstreamRow extends StatelessWidget {
  const _MiuixUpstreamRow({required this.controller, required this.upstream});

  final ServerController controller;
  final Upstream upstream;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final count = upstream.models.where((m) => m.enabled).length;
    return MiuixArrowPreference(
      title: upstream.name,
      summary: upstream.baseUrl,
      startAction: Icon(
        switch (upstream.type) {
          UpstreamType.ollama => Icons.blur_circular,
          UpstreamType.llamacpp => Icons.memory,
          UpstreamType.openai => Icons.cloud_outlined,
          UpstreamType.anthropic => Icons.psychology_outlined,
          UpstreamType.localTts => Icons.record_voice_over_outlined,
        },
        size: 24,
        color: upstream.enabled
            ? colors.primary
            : colors.onSurfaceVariantSummary,
      ),
      // 类型徽标 + 模型数放主行下方：miuix 偏好行的 end 槽最多拿剩余宽度的 60%，
      // 把胶囊和 49dp 宽的开关挤在一排会在窄屏溢出。
      bottomAction: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            _MiuixPill(
              label: switch (upstream.type) {
                UpstreamType.openai => l10n.typeOpenai,
                UpstreamType.anthropic => l10n.typeAnthropic,
                UpstreamType.llamacpp => l10n.typeLlamacpp,
                UpstreamType.ollama => l10n.typeOllama,
                UpstreamType.localTts => l10n.typeLocalTts,
              },
              background: colors.secondaryContainer,
              foreground: colors.onSecondaryContainer,
            ),
            const SizedBox(width: 8),
            MiuixText(
              l10n.modelCountLabel('$count'),
              fontSize: 12,
              color: colors.onSurfaceVariantSummary,
            ),
          ],
        ),
      ),
      endActions: [
        MiuixSwitch(
          value: upstream.enabled,
          onChanged: (v) {
            upstream.enabled = v;
            controller.store.update(controller.config);
          },
        ),
      ],
      onClick: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              MiuixUpstreamEditPage(controller: controller, upstream: upstream),
        ),
      ),
    );
  }
}

/// 分组小标题（可带尾部动作）。
class _MiuixSectionHeader extends StatelessWidget {
  const _MiuixSectionHeader({super.key, required this.title, this.trailing});

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

/// 胶囊标签：替代 Material 的 InputChip / 自绘 badge。
class _MiuixPill extends StatelessWidget {
  const _MiuixPill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: MiuixText(
        label,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: foreground,
      ),
    );
  }
}
