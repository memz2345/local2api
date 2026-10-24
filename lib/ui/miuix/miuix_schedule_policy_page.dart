import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField;
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/model_schedule.dart';
import 'package:local2api/services/network_utils.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/widgets/miuix/miuix_bottom_sheet.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';

/// 峰谷时段策略页（miuix 版，对应 Material 版 `SchedulePolicyPage`）—— **总览**。
///
/// 数据与写入目标与 Material 版完全一致（同一份 `ProxyConfig.scheduleRules`），
/// 只换渲染：外壳 `MiuixScaffold` + `MiuixBlurTopBar`，条目用 `MiuixGroupCard`，
/// 二选一走 `_MiuixChoiceChip`（不用 Material 的 SegmentedButton）。
///
/// 日期 / 时间选择器两套风格都用 Flutter 原生的 `showDatePicker` /
/// `showTimePicker` —— 不另做 miuix 皮肤。
class MiuixSchedulePolicyPage extends StatefulWidget {
  const MiuixSchedulePolicyPage({
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
  State<MiuixSchedulePolicyPage> createState() =>
      _MiuixSchedulePolicyPageState();
}

class _MiuixSchedulePolicyPageState extends State<MiuixSchedulePolicyPage> {
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();

  @override
  void dispose() {
    _behavior.state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final pool = widget.targetPool;
    final rules = pool == null
        ? widget.controller.config.scheduleRules
        : scheduleRulesOfUpstream(
            widget.controller.config,
            modelNames: pool,
            managedBy: widget.managedBy,
          );

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => Material(
        type: MaterialType.transparency,
        child: MiuixScaffold(
          containerColor: colors.surface,
          topBar: MiuixBlurTopBar(
            scrollBehavior: _behavior,
            title: l10n.scheduleTitle,
            navigationIcon: MiuixIconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const MiuixAppIcon(
                AppIconNames.back,
                fallback: Icons.arrow_back,
              ),
            ),
            actions: [
              MiuixIconButton(
                onPressed: () => _openEditor(null),
                child: const MiuixAppIcon(
                  AppIconNames.addCircle,
                  fallback: Icons.add_circle_outline,
                ),
              ),
            ],
          ),
          floatingActionButton: MiuixFloatingActionButton(
            onPressed: () => _openEditor(null),
            child: const MiuixAppIcon(AppIconNames.add, fallback: Icons.add),
          ),
          content: (padding) => MiuixScrollBehaviorListener(
            behavior: _behavior,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(16, padding.top + 4, 16, 120),
              children: [
                if (rules.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: MiuixText(
                        l10n.scheduleEmpty,
                        fontSize: 14,
                        textAlign: TextAlign.center,
                        color: colors.onSurfaceVariantSummary,
                      ),
                    ),
                  )
                else
                  for (final rule in rules)
                    Padding(
                      key: ValueKey(rule.id),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: MiuixScheduleRuleCard(
                        controller: widget.controller,
                        rule: rule,
                        onEdit: () => _openEditor(rule),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openEditor(ScheduleRule? existing) =>
      showMiuixScheduleRuleSheet(
        context: context,
        controller: widget.controller,
        existing: existing,
        targetPool: widget.targetPool,
      );
}

/// miuix 版策略编辑面板（与 Material 版共用 [ScheduleRule]，只换外壳）。
///
/// [targetPool] 限定可选模型（上游编辑页传该上游自己的模型）。
Future<void> showMiuixScheduleRuleSheet({
  required BuildContext context,
  required ServerController controller,
  ScheduleRule? existing,
  List<String>? targetPool,
  List<String>? presetTargets,
}) async {
  final l10n = AppLocalizations.of(context);
  final colors = MiuixTheme.of(context).colors;
  final pool = targetPool ?? scheduleModelNames(controller.config);
  if (pool.isEmpty && existing == null) {
    showMiuixToast(context, l10n.scheduleEmpty);
    return;
  }
  final draft = existing != null
      ? ScheduleRule.fromJson(existing.toJson())
      : ScheduleRule(
          id: NetworkUtils.newId(),
          targets: presetTargets ?? [if (pool.isNotEmpty) pool.first],
        );

  await showMiuixBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (context, setSheet) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                    child: MiuixText(
                      existing == null ? l10n.scheduleAdd : l10n.scheduleTitle,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  // 适用模型：多选；「全选」= 以前那条「整个模型组」的语义
                  MiuixGroupCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
                          child: MiuixText(
                            l10n.scheduleTargetModel,
                            fontSize: 13,
                            color: colors.onSurfaceVariantSummary,
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _MiuixPickChip(
                              label: l10n.scheduleSelectAll,
                              selected:
                                  pool.isNotEmpty &&
                                  draft.targets.length == pool.length,
                              onTap: () => setSheet(() {
                                draft.targets =
                                    draft.targets.length == pool.length
                                    ? <String>[]
                                    : List<String>.of(pool);
                              }),
                            ),
                            for (final name in pool)
                              _MiuixPickChip(
                                label: name,
                                selected: draft.targets.contains(name),
                                onTap: () => setSheet(() {
                                  final next = List<String>.of(draft.targets);
                                  if (next.contains(name)) {
                                    next.remove(name);
                                  } else {
                                    next.add(name);
                                  }
                                  draft.targets = next;
                                }),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 正向 / 反向
                  Row(
                    children: [
                      _MiuixChoiceChip(
                        label: l10n.scheduleModeAllow,
                        selected: draft.mode == ScheduleMode.allow,
                        onTap: () =>
                            setSheet(() => draft.mode = ScheduleMode.allow),
                      ),
                      const SizedBox(width: 8),
                      _MiuixChoiceChip(
                        label: l10n.scheduleModeDeny,
                        selected: draft.mode == ScheduleMode.deny,
                        onTap: () =>
                            setSheet(() => draft.mode = ScheduleMode.deny),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 星期：点「选择」弹 Flutter 原生日历，选哪天就切换哪个星期
                  MiuixGroupCard(
                    onPressed: () => _pickWeekday(context, setSheet, draft),
                    insideMargin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MiuixText(
                          l10n.scheduleWeekdays,
                          fontSize: 13,
                          color: colors.onSurfaceVariantSummary,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: MiuixText(
                                draft.weekdays.length == 7
                                    ? l10n.scheduleAllDay
                                    : [
                                        for (final wd in draft.weekdays)
                                          _weekdayLabel(context, wd),
                                      ].join(' '),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            MiuixText(
                              l10n.schedulePickWeekday,
                              fontSize: 13,
                              color: colors.primary,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 起止时间：点开是 Flutter 原生的时间选择器
                  MiuixGroupCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
                          child: MiuixText(
                            l10n.scheduleHours,
                            fontSize: 13,
                            color: colors.onSurfaceVariantSummary,
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _MiuixTimeField(
                                label: l10n.scheduleStartHour,
                                value: _hourLabel(draft.startHour),
                                onTap: () => _pickHour(
                                  context,
                                  setSheet,
                                  draft,
                                  isStart: true,
                                ),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: MiuixAppIcon(
                                AppIconNames.forward,
                                fallback: Icons.arrow_forward,
                                size: 16,
                              ),
                            ),
                            Expanded(
                              child: _MiuixTimeField(
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
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          children: [
                            _MiuixPickChip(
                              label: l10n.scheduleAllDay,
                              selected:
                                  draft.startHour == 0 && draft.endHour >= 24,
                              onTap: () => setSheet(() {
                                draft.startHour = 0;
                                draft.endHour = 24;
                              }),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  MiuixSwitchPreference(
                    title: l10n.scheduleEnabled,
                    value: draft.enabled,
                    onChanged: (v) => setSheet(() => draft.enabled = v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (existing != null)
                        Expanded(
                          child: MiuixButton(
                            onPressed: () {
                              final cfg = controller.config;
                              cfg.scheduleRules.removeWhere(
                                (r) => r.id == existing.id,
                              );
                              controller.store.update(cfg);
                              Navigator.of(sheetCtx).pop();
                              showMiuixToast(context, l10n.scheduleDeleted);
                            },
                            child: MiuixText(
                              l10n.scheduleDelete,
                              color: colors.error,
                            ),
                          ),
                        ),
                      if (existing != null) const SizedBox(width: 8),
                      Expanded(
                        child: MiuixButton(
                          colors: MiuixButtonColors(
                            color: colors.primary,
                            contentColor: colors.onPrimary,
                            disabledColor: colors.disabledPrimaryButton,
                            disabledContentColor:
                                colors.disabledOnPrimaryButton,
                          ),
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
                                  Navigator.of(sheetCtx).pop();
                                  showMiuixToast(context, l10n.scheduleSaved);
                                },
                          child: MiuixText(l10n.saveBtn),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// `9:00` / `24:00`。
String _hourLabel(int hour) => '${hour == 24 ? 24 : hour}:00';

/// 点开 Flutter 原生日历：选中的那一天决定「切换哪个星期」。
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

/// 一行「时间」格子，点一下弹时间选择器（miuix 版）。
class _MiuixTimeField extends StatelessWidget {
  const _MiuixTimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixGroupCard(
      cornerRadius: 12,
      onPressed: onTap,
      insideMargin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MiuixText(
            label,
            fontSize: 12,
            color: colors.onSurfaceVariantSummary,
          ),
          const SizedBox(height: 2),
          MiuixText(value, fontSize: 15, fontWeight: FontWeight.w600),
        ],
      ),
    );
  }
}

/// 星期的短名：`DateTime.weekday`（1=周一 … 7=周日）→ MaterialLocalizations
/// 的 narrowWeekdays（下标 0=周日），所以周日要绕回 0。
String _weekdayLabel(BuildContext context, int weekday) =>
    MaterialLocalizations.of(context).narrowWeekdays[weekday % 7];

/// 一条策略的卡片（miuix 版）：对象名 + 方向 + 星期 + 时段 + 启停。
class MiuixScheduleRuleCard extends StatelessWidget {
  const MiuixScheduleRuleCard({
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
    final colors = MiuixTheme.of(context).colors;
    final dayText = rule.weekdays.length == 7
        ? l10n.scheduleAllDay
        : [
            for (final wd in rule.weekdays) _weekdayLabel(context, wd),
          ].join(' ');
    final targetText = rule.targets.isEmpty
        ? '—'
        : (rule.targets.length == 1
              ? rule.targets.first
              : l10n.modelCountLabel('${rule.targets.length}'));
    return MiuixGroupCard(
      onPressed: onEdit,
      insideMargin: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.schedule_outlined,
                size: 20,
                color: rule.enabled
                    ? colors.primary
                    : colors.onSurfaceVariantSummary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MiuixText(
                  targetText,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              MiuixSwitch(
                value: rule.enabled,
                onChanged: (v) {
                  rule.enabled = v;
                  controller.store.update(controller.config);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _MiuixTag(
                text: rule.mode == ScheduleMode.allow
                    ? l10n.scheduleModeAllow
                    : l10n.scheduleModeDeny,
                color: rule.mode == ScheduleMode.allow
                    ? colors.primary
                    : colors.error,
              ),
              _MiuixTag(text: dayText, color: colors.onSurfaceVariantSummary),
              _MiuixTag(
                text: scheduleHourRangeLabel(l10n, rule.startHour, rule.endHour),
                color: colors.onSurfaceVariantSummary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 多选 / 二选一的小胶囊（miuix 侧不用 Material 的 ChoiceChip）。
class _MiuixPickChip extends StatelessWidget {
  const _MiuixPickChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixGroupCard(
      cornerRadius: 12,
      insideMargin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      feedbackType: MiuixPressFeedbackType.sink,
      onPressed: onTap,
      colors: selected
          ? MiuixCardColors(
              color: colors.primary,
              contentColor: colors.onPrimary,
            )
          : null,
      child: MiuixText(
        label,
        fontSize: 13,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// 二选一片（与设置页 `ruleAllow/ruleDeny` 那组同款）。
class _MiuixChoiceChip extends StatelessWidget {
  const _MiuixChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return Expanded(
      child: MiuixGroupCard(
        cornerRadius: 12,
        insideMargin: const EdgeInsets.symmetric(vertical: 10),
        feedbackType: MiuixPressFeedbackType.sink,
        onPressed: onTap,
        colors: selected
            ? MiuixCardColors(
                color: colors.primary,
                contentColor: colors.onPrimary,
              )
            : null,
        child: Center(
          child: MiuixText(
            label,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class _MiuixTag extends StatelessWidget {
  const _MiuixTag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return MiuixText(
      text,
      fontSize: 12,
      color: color,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
