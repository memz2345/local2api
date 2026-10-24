import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/model_schedule.dart';
import 'package:local2api/services/network_utils.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/widgets/app_toast.dart';
import 'package:local2api/widgets/expressive_app_bar.dart';
import 'package:local2api/widgets/frosted_page_bar.dart';

/// 峰谷时段策略页（Material 版）—— **总览**。
///
/// 日常配置的入口在上游编辑页（「峰谷时段」区块，只列该上游的模型）；
/// 这一页把所有策略摊开看，新建时可以跨上游多选模型。
///
/// 一条策略 = 一组对外模型 + 方向（正向允许 / 反向禁止）+ 星期 + 小时区间。
/// 判定是「先命中先生效」，一条都不命中 = 全天可用。
///
/// 模拟对话永远不受这些策略限制：它带 `x-local2api-sim` 头，代理侧直接放行，
/// 否则调试窗口会被自己配的策略挡在门外。
class SchedulePolicyPage extends StatelessWidget {
  const SchedulePolicyPage({
    super.key,
    required this.controller,
    this.targetPool,
    this.managedBy,
  });

  final ServerController controller;

  /// 限定范围：只列（也只在编辑时提供）这些模型的策略。
  /// 上游编辑页进来时给该上游的模型；null = 全部（总览模式）。
  final List<String>? targetPool;

  /// 该上游的配置档案 id —— 老数据里的「组级」规则按它匹配，也得算进来。
  final String? managedBy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final pool = targetPool;
    final rules = pool == null
        ? controller.config.scheduleRules
        : scheduleRulesOfUpstream(
            controller.config,
            modelNames: pool,
            managedBy: managedBy,
          );
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => FrostedBarPage(
        title: l10n.scheduleTitle,
        actions: [
          MorphIconButton(
            icon: Icons.add_circle_outline,
            tooltip: l10n.scheduleAdd,
            transparent: true,
            onTap: () => showScheduleRuleSheet(
              context: context,
              controller: controller,
              targetPool: pool,
            ),
          ),
        ],
        floatingActionButton: FloatingActionButton(
          tooltip: l10n.scheduleAdd,
          onPressed: () => showScheduleRuleSheet(
            context: context,
            controller: controller,
            targetPool: pool,
          ),
          child: const Icon(Icons.add),
        ),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          padding: EdgeInsets.fromLTRB(
            16,
            frostedPageBarInset(context) + 8,
            16,
            120,
          ),
          children: [
            if (rules.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Center(
                  child: Text(
                    l10n.scheduleEmpty,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              for (final rule in rules)
                Padding(
                  key: ValueKey(rule.id),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ScheduleRuleCard(
                    controller: controller,
                    rule: rule,
                    onEdit: () => showScheduleRuleSheet(
                      context: context,
                      controller: controller,
                      existing: rule,
                      targetPool: pool,
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// 弹出策略编辑面板。Material 与 miuix 两份页面共用这一份业务逻辑，
/// 只有外壳（底部抽屉 / 卡片对话框）不同。
///
/// 传 [existing] = 编辑，传 null = 新建。[targetPool] 限定可选的模型
/// （上游编辑页里传该上游自己的模型；不传 = 全部对外模型）。
Future<void> showScheduleRuleSheet({
  required BuildContext context,
  required ServerController controller,
  ScheduleRule? existing,
  List<String>? targetPool,
  List<String>? presetTargets,
}) async {
  final l10n = AppLocalizations.of(context);
  final pool = targetPool ?? scheduleModelNames(controller.config);
  if (pool.isEmpty && existing == null) {
    showAppToast(context, l10n.scheduleEmpty);
    return;
  }
  final draft = existing != null
      ? ScheduleRule.fromJson(existing.toJson())
      : ScheduleRule(
          id: NetworkUtils.newId(),
          targets: presetTargets ?? [if (pool.isNotEmpty) pool.first],
        );
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (sheetContext) => SafeArea(
      child: StatefulBuilder(
        builder: (context, setSheet) {
          final theme = Theme.of(context);
          final cs = theme.colorScheme;
          final weekdays = MaterialLocalizations.of(context).narrowWeekdays;
          final allSelected =
              pool.isNotEmpty && draft.targets.length == pool.length;
          final dayText = draft.weekdays.length == 7
              ? l10n.scheduleAllDay
              : [
                  for (final wd in draft.weekdays) weekdays[wd % 7],
                ].join(' ');
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
            ),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      existing == null ? l10n.scheduleAdd : l10n.scheduleTitle,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 14),
                    // 适用模型：多选；「全选」= 以前那条「整个模型组」的语义
                    Text(
                      l10n.scheduleTargetModel,
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        FilterChip(
                          label: Text(l10n.scheduleSelectAll),
                          visualDensity: VisualDensity.compact,
                          selected: allSelected,
                          onSelected: (on) => setSheet(() {
                            draft.targets = on ? List<String>.of(pool) : [];
                          }),
                        ),
                        for (final name in pool)
                          FilterChip(
                            label: Text(name),
                            visualDensity: VisualDensity.compact,
                            selected: draft.targets.contains(name),
                            onSelected: (on) => setSheet(() {
                              final next = List<String>.of(draft.targets);
                              if (on) {
                                if (!next.contains(name)) next.add(name);
                              } else {
                                next.remove(name);
                              }
                              draft.targets = next;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // 正向 / 反向
                    SegmentedButton<ScheduleMode>(
                      segments: [
                        ButtonSegment(
                          value: ScheduleMode.allow,
                          label: Text(l10n.scheduleModeAllow),
                        ),
                        ButtonSegment(
                          value: ScheduleMode.deny,
                          label: Text(l10n.scheduleModeDeny),
                        ),
                      ],
                      selected: {draft.mode},
                      onSelectionChanged: (s) =>
                          setSheet(() => draft.mode = s.first),
                    ),
                    const SizedBox(height: 16),
                    // 星期：点「选择」弹 Flutter 原生日历，选哪天就切换哪个星期
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.scheduleWeekdays,
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                        Text(
                          dayText,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () => _pickWeekday(context, setSheet, draft),
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text(l10n.schedulePickWeekday),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 起止时间：点开是 Flutter 原生的时间选择器
                    Text(
                      l10n.scheduleHours,
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _TimeField(
                            label: l10n.scheduleStartHour,
                            value: _hourLabel(draft.startHour),
                            onTap: () =>
                                _pickHour(context, setSheet, draft, isStart: true),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Icon(Icons.arrow_forward, size: 18),
                        ),
                        Expanded(
                          child: _TimeField(
                            label: l10n.scheduleEndHour,
                            value: _hourLabel(draft.endHour),
                            onTap: () => _pickHour(
                              context,
                              setSheet,
                              draft,
                              isStart: false,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ActionChip(
                        avatar: const Icon(Icons.all_inclusive, size: 16),
                        label: Text(l10n.scheduleAllDay),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setSheet(() {
                          draft.startHour = 0;
                          draft.endHour = 24;
                        }),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.scheduleEnabled),
                      value: draft.enabled,
                      onChanged: (v) => setSheet(() => draft.enabled = v),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (existing != null)
                          TextButton.icon(
                            onPressed: () {
                              final cfg = controller.config;
                              cfg.scheduleRules.removeWhere(
                                (r) => r.id == existing.id,
                              );
                              controller.store.update(cfg);
                              Navigator.of(context).pop();
                              showAppToast(context, l10n.scheduleDeleted);
                            },
                            icon: Icon(Icons.delete_outline, color: cs.error),
                            label: Text(
                              l10n.scheduleDelete,
                              style: TextStyle(color: cs.error),
                            ),
                          ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(l10n.cancel),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: draft.targets.isEmpty
                              ? null
                              : () {
                                  final cfg = controller.config;
                                  final list = cfg.scheduleRules;
                                  final at = existing == null
                                      ? -1
                                      : list.indexWhere(
                                          (r) => r.id == existing.id,
                                        );
                                  if (at >= 0) {
                                    list[at] = draft;
                                  } else {
                                    list.add(draft);
                                  }
                                  controller.store.update(cfg);
                                  Navigator.of(context).pop();
                                  showAppToast(context, l10n.scheduleSaved);
                                },
                          child: Text(l10n.saveBtn),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

/// `9:00` / 全天（24:00）。
String _hourLabel(int hour) => '${hour == 24 ? 24 : hour}:00';

/// 点开 Flutter 原生日历：选中的那一天决定「切换哪个星期」。
///
/// 只取 `weekday`，具体年月日不参与业务；再点一次可以接着切换别的星期。
Future<void> _pickWeekday(
  BuildContext context,
  StateSetter setSheet,
  ScheduleRule draft,
) async {
  final l10n = AppLocalizations.of(context);
  final picked = await showDatePicker(
    context: context,
    initialDate: DateTime.now(),
    firstDate: DateTime(2000, 1, 1),
    lastDate: DateTime(2100, 12, 31),
    helpText: l10n.schedulePickWeekday,
    cancelText: l10n.cancel,
    confirmText: l10n.confirm,
  );
  if (picked == null) return;
  final wd = picked.weekday;
  setSheet(() {
    final next = List<int>.of(draft.weekdays);
    if (next.contains(wd)) {
      next.remove(wd);
    } else {
      next.add(wd);
    }
    next.sort();
    draft.weekdays = next;
  });
}

/// 点开 Flutter 原生时间选择器。结束时间选 0 点当作「到当天结束」（= 24）。
Future<void> _pickHour(
  BuildContext context,
  StateSetter setSheet,
  ScheduleRule draft, {
  required bool isStart,
}) async {
  final l10n = AppLocalizations.of(context);
  final current = isStart
      ? draft.startHour
      : (draft.endHour >= 24 ? 0 : draft.endHour);
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: current.clamp(0, 23), minute: 0),
    helpText: isStart ? l10n.scheduleStartHour : l10n.scheduleEndHour,
    cancelText: l10n.cancel,
    confirmText: l10n.confirm,
  );
  if (picked == null) return;
  setSheet(() {
    if (isStart) {
      draft.startHour = picked.hour;
    } else {
      draft.endHour = picked.hour == 0 ? 24 : picked.hour;
    }
  });
}

/// 一个只读的时间格子，点一下弹时间选择器。
class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(value, style: theme.textTheme.titleMedium),
            ),
            Icon(
              Icons.schedule,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// 一条策略的卡片：对象名 + 方向 + 星期 + 时段 + 启停。
class ScheduleRuleCard extends StatelessWidget {
  const ScheduleRuleCard({
    super.key,
    required this.controller,
    required this.rule,
    required this.onEdit,
  });

  final ServerController controller;
  final ScheduleRule rule;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final weekdays = MaterialLocalizations.of(context).narrowWeekdays;
    final dayText = rule.weekdays.length == 7
        ? l10n.scheduleAllDay
        : [
            for (final wd in rule.weekdays) weekdays[wd % 7],
          ].join(' ');
    final targetText = rule.targets.isEmpty
        ? '—'
        : (rule.targets.length == 1
              ? rule.targets.first
              : l10n.modelCountLabel('${rule.targets.length}'));
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.schedule_outlined,
                    size: 20,
                    color: rule.enabled ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      targetText,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Switch(
                    value: rule.enabled,
                    onChanged: (v) {
                      rule.enabled = v;
                      controller.store.update(controller.config);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ScheduleTag(
                    text: rule.mode == ScheduleMode.allow
                        ? l10n.scheduleModeAllow
                        : l10n.scheduleModeDeny,
                    color: rule.mode == ScheduleMode.allow
                        ? cs.primary
                        : cs.error,
                  ),
                  ScheduleTag(text: dayText, color: cs.secondary),
                  ScheduleTag(
                    text: scheduleHourRangeLabel(
                      l10n,
                      rule.startHour,
                      rule.endHour,
                    ),
                    color: cs.secondary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 卡片上的小标签，两套风格共用。
class ScheduleTag extends StatelessWidget {
  const ScheduleTag({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
