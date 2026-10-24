import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField;
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/network_utils.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/widgets/miuix/miuix_bottom_sheet.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_info_card.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';
import 'package:local2api/widgets/miuix/miuix_text_field.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';
import 'package:local2api/widgets/swipe_action_row.dart';

/// 刚删掉、还等着「恢复」的规则（原下标 + 条目）。
typedef _PendingRuleDelete = ({int index, CidrRule entry});

/// IP 访问规则页（miuix 版，交互与 `MiuixKeysPage` 同款）。
///
/// 右下角 miuix FAB 添加规则；一行一条，**左滑越过行宽 35% 松手即删**
/// （不弹确认框），删完弹 snackbar「已删除 N 条规则 + 恢复」。
class MiuixIpRulesPage extends StatefulWidget {
  const MiuixIpRulesPage({super.key, required this.controller});

  final ServerController controller;

  @override
  State<MiuixIpRulesPage> createState() => _MiuixIpRulesPageState();
}

class _MiuixIpRulesPageState extends State<MiuixIpRulesPage> {
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();

  /// 最近删掉、还等着「恢复」的那批。
  final List<_PendingRuleDelete> _pending = [];

  /// snackbar 序号：连着删时只认当前这条（同密钥页的处理）。
  int _snackbarSeq = 0;

  final MiuixSnackbarHostState _snackHost = MiuixSnackbarHostState();

  @override
  void dispose() {
    _behavior.state.dispose();
    _snackHost.dispose();
    super.dispose();
  }

  /// 立即删除：不弹确认框，删完弹 snackbar 带「恢复」。
  void _delete(CidrRule entry) {
    final rules = widget.controller.config.cidrRules;
    final index = rules.indexOf(entry);
    if (index < 0) return;
    rules.removeAt(index);
    widget.controller.store.update(widget.controller.config);
    _pending.insert(0, (index: index, entry: entry));
    unawaited(_showDeletedSnackbar());
  }

  Future<void> _showDeletedSnackbar() async {
    final l10n = AppLocalizations.of(context);
    final seq = ++_snackbarSeq;
    final previous = await _snackHost.newestSnackbarData();
    if (previous != null) await previous.dismiss();
    final result = await _snackHost.showSnackbar(
      l10n.ruleDeletedCount('${_pending.length}'),
      actionLabel: l10n.keyRestore,
      duration: const MiuixSnackbarDuration.custom(5000),
    );
    if (!mounted) return;
    if (seq != _snackbarSeq) return;
    if (result == MiuixSnackbarResult.actionPerformed) {
      _undoDelete();
    } else {
      _pending.clear();
    }
  }

  /// 按原下标放回去（倒着插，下标才不会被自己挤偏）。
  void _undoDelete() {
    final l10n = AppLocalizations.of(context);
    final rules = widget.controller.config.cidrRules;
    for (final item in _pending.reversed) {
      rules.insert(item.index.clamp(0, rules.length), item.entry);
    }
    final count = _pending.length;
    _pending.clear();
    widget.controller.store.update(widget.controller.config);
    showMiuixToast(context, l10n.ruleRestored('$count'));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final rules = widget.controller.config.cidrRules;

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => Material(
        type: MaterialType.transparency,
        child: MiuixScaffold(
          containerColor: colors.surface,
          snackbarHost: MiuixSnackbarHost(state: _snackHost),
          topBar: MiuixBlurTopBar(
            scrollBehavior: _behavior,
            title: l10n.accessRules,
            navigationIcon: MiuixIconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const MiuixAppIcon(
                AppIconNames.back,
                fallback: Icons.arrow_back,
              ),
            ),
          ),
          floatingActionButton: MiuixFloatingActionButton(
            onPressed: () => _showAddRuleSheet(context),
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
                MiuixDismissibleInfoCard(
                  id: 'intro.ipRules',
                  text: l10n.accessRuleDesc,
                ),
                const SizedBox(height: 12),
                if (rules.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: MiuixText(
                        l10n.ipRulesEmpty,
                        fontSize: 14,
                        textAlign: TextAlign.center,
                        color: colors.onSurfaceVariantSummary,
                      ),
                    ),
                  )
                else
                  for (final rule in List<CidrRule>.of(rules))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SwipeActionRow(
                        // 必须按 id 给 key：删掉一行后如果没 key，Flutter 会把
                        // 那个「已收起」的 State 复用给下一行（同密钥页的坑）。
                        key: ValueKey(rule.id),
                        actionIcon: Icons.delete_outline,
                        actionColor: colors.error,
                        foregroundCornerRadius: MiuixCardDefaults.cornerRadius,
                        semanticLabel: l10n.deleteBtn,
                        onCommit: () => _delete(rule),
                        child: _MiuixRuleCard(
                          controller: widget.controller,
                          rule: rule,
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 添加规则面板（自设置页的 IP 规则分区原样搬来）。
  Future<void> _showAddRuleSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final cidrCtrl = TextEditingController();
    bool allow = true;
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                    child: MiuixText(
                      l10n.addRule,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  MiuixTextField(
                    controller: cidrCtrl,
                    label: l10n.cidrHint,
                    useLabelAsPlaceholder: true,
                    singleLine: true,
                    onChanged: (_) => setSheet(() {}),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _MiuixChoiceChip(
                        label: l10n.ruleAllow,
                        selected: allow,
                        onTap: () => setSheet(() => allow = true),
                      ),
                      const SizedBox(width: 8),
                      _MiuixChoiceChip(
                        label: l10n.ruleDeny,
                        selected: !allow,
                        onTap: () => setSheet(() => allow = false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: MiuixButton(
                      onPressed: () {
                        final cidr = cidrCtrl.text.trim();
                        if (NetworkUtils.parseCidr(cidr) == null) {
                          showMiuixToast(
                            sheetCtx,
                            l10n.cidrInvalid,
                            error: true,
                          );
                          return;
                        }
                        widget.controller.config.cidrRules.add(
                          CidrRule(
                            id: NetworkUtils.newId(),
                            cidr: cidr,
                            allow: allow,
                          ),
                        );
                        widget.controller.store.update(widget.controller.config);
                        Navigator.pop(sheetCtx);
                      },
                      colors: MiuixButtonColors(
                        color: colors.primary,
                        contentColor: colors.onPrimary,
                        disabledColor: colors.disabledPrimaryButton,
                        disabledContentColor: colors.disabledOnPrimaryButton,
                      ),
                      child: MiuixText(l10n.saveBtn),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一条规则卡：放行/拒绝胶囊 + CIDR + 启用开关。
class _MiuixRuleCard extends StatelessWidget {
  const _MiuixRuleCard({required this.controller, required this.rule});

  final ServerController controller;
  final CidrRule rule;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final tint = rule.allow ? const Color(0xFF2BA471) : colors.error;
    return MiuixGroupCard(
      insideMargin: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          MiuixAppIcon(
            rule.allow ? 'checkCircle' : 'cancelCircle',
            fallback: rule.allow
                ? Icons.gpp_good_outlined
                : Icons.gpp_bad_outlined,
            size: 20,
            color: rule.enabled
                ? tint
                : colors.onSurfaceVariantSummary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MiuixText(
                  rule.cidr,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                MiuixText(
                  rule.allow ? l10n.ruleAllow : l10n.ruleDeny,
                  fontSize: 12,
                  color: rule.enabled
                      ? tint
                      : colors.onSurfaceVariantSummary,
                ),
              ],
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
    );
  }
}

/// 允许 / 拒绝的选择胶囊（自设置页搬来）。
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
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: selected ? colors.onPrimary : colors.onSurface,
          ),
        ),
      ),
    );
  }
}
