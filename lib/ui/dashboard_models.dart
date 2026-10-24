import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/widgets/app_tooltip.dart';

import 'upstream_edit_page.dart';
import 'widgets/common.dart';

/// 仪表盘的「上游服务 + 对外模型」分区。
/// [upstreamsSectionKey] 挂在「上游服务」分组卡上，供状态卡跳转定位。
List<Widget> modelSections(
  BuildContext context,
  ServerController controller, {
  Key? upstreamsSectionKey,
}) {
  final l10n = AppLocalizations.of(context);
  final theme = Theme.of(context);
  final upstreams = controller.config.upstreams;
  final exposed = <ModelEntry>[];
  for (final u in upstreams) {
    if (!u.enabled) continue;
    for (final m in u.models) {
      if (m.enabled) exposed.add(m);
    }
  }
  return [
    SectionCard(
      title: l10n.exposedModelsTitle,
      trailing: Text('${exposed.length}', style: theme.textTheme.labelLarge),
      child: exposed.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                l10n.noExposedModels,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in exposed)
                  InputChip(
                    label: Text(m.publicName),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {},
                  ),
              ],
            ),
    ),
    SectionCard(
      key: upstreamsSectionKey,
      title: l10n.upstreams,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 峰谷时段已经挪进「编辑上游」页（备注下面），这一排只留新建上游。
          AppTooltip(
            message: l10n.addUpstream,
            child: IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () =>
                  pushPage(context, UpstreamEditPage(controller: controller)),
            ),
          ),
        ],
      ),
      child: upstreams.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                l10n.noUpstreams,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < upstreams.length; i++) ...[
                  if (i > 0) const Divider(),
                  _UpstreamTile(controller: controller, upstream: upstreams[i]),
                ],
              ],
            ),
    ),
  ];
}

class _UpstreamTile extends StatelessWidget {
  const _UpstreamTile({required this.controller, required this.upstream});

  final ServerController controller;
  final Upstream upstream;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final count = upstream.models.where((m) => m.enabled).length;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => pushPage(
        context,
        UpstreamEditPage(controller: controller, upstream: upstream),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Row(
          children: [
            Icon(
              switch (upstream.type) {
                UpstreamType.ollama => Icons.blur_circular,
                UpstreamType.llamacpp => Icons.memory,
                UpstreamType.openai => Icons.cloud_outlined,
                UpstreamType.anthropic => Icons.psychology_outlined,
                UpstreamType.localTts => Icons.record_voice_over_outlined,
              },
              size: 26,
              color: upstream.enabled
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          upstream.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          switch (upstream.type) {
                            UpstreamType.openai => l10n.typeOpenai,
                            UpstreamType.anthropic => l10n.typeAnthropic,
                            UpstreamType.llamacpp => l10n.typeLlamacpp,
                            UpstreamType.ollama => l10n.typeOllama,
                            UpstreamType.localTts => l10n.typeLocalTts,
                          },
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${upstream.baseUrl}  ·  ${l10n.modelCountLabel('$count')}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Switch(
              value: upstream.enabled,
              onChanged: (v) {
                upstream.enabled = v;
                controller.store.update(controller.config);
              },
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
