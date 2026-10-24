import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/network_utils.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/widgets/app_toast.dart';
import 'package:local2api/widgets/frosted_page_bar.dart';
import 'package:local2api/widgets/native_text_context_menu.dart';
import 'package:local2api/widgets/predictive_back_sheet.dart';
import 'package:local2api/widgets/swipe_action_row.dart';

/// 刚删掉、还等着「恢复」的规则（原下标 + 条目）。
typedef _PendingRuleDelete = ({int index, CidrRule entry});

/// IP 访问规则页（Material 版，交互与 `KeysPage` 同款）。
///
/// 右下角 FAB 添加规则；一行一条，**左滑越过行宽 35% 松手即删**
/// （不弹确认框），删完弹 snackbar「已删除 N 条规则 + 恢复」。
class IpRulesPage extends StatefulWidget {
  const IpRulesPage({super.key, required this.controller});

  final ServerController controller;

  @override
  State<IpRulesPage> createState() => _IpRulesPageState();
}

class _IpRulesPageState extends State<IpRulesPage> {
  final List<_PendingRuleDelete> _pending = [];
  int _snackbarSeq = 0;

  /// 立即删除：不弹确认框，删完弹 snackbar 带「恢复」。
  ///
  /// [ctx] 必须是 build 里页面自带 `ScaffoldMessenger` 之内的那个 context
  /// （同密钥页：app 级 messenger 会把 snackbar 交给被盖住的首页）。
  void _delete(BuildContext ctx, CidrRule entry) {
    final l10n = AppLocalizations.of(ctx);
    final rules = widget.controller.config.cidrRules;
    final index = rules.indexOf(entry);
    if (index < 0) return;
    rules.removeAt(index);
    widget.controller.store.update(widget.controller.config);
    _pending.insert(0, (index: index, entry: entry));

    final messenger = ScaffoldMessenger.of(ctx);
    final seq = ++_snackbarSeq;
    messenger.removeCurrentSnackBar();
    messenger
        .showSnackBar(
          SnackBar(
            content: Text(l10n.ruleDeletedCount('${_pending.length}')),
            action: SnackBarAction(
              label: l10n.keyRestore,
              onPressed: () => _undoDelete(ctx),
            ),
            duration: const Duration(seconds: 5),
          ),
        )
        .closed
        .then((reason) {
          if (seq != _snackbarSeq) return;
          if (reason != SnackBarClosedReason.action) _pending.clear();
        });
  }

  void _undoDelete(BuildContext ctx) {
    final l10n = AppLocalizations.of(ctx);
    final rules = widget.controller.config.cidrRules;
    for (final item in _pending) {
      final at = item.index.clamp(0, rules.length);
      rules.insert(at, item.entry);
    }
    final count = _pending.length;
    _pending.clear();
    widget.controller.store.update(widget.controller.config);
    showAppToast(ctx, l10n.ruleRestored('$count'));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rules = widget.controller.config.cidrRules;

    // snackbar 只认这一页（同密钥页的处理，见 _delete 注释）
    return ScaffoldMessenger(
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => FrostedBarPage(
          title: l10n.accessRules,
          floatingActionButton: FloatingActionButton(
            tooltip: l10n.addRule,
            onPressed: () => _showAddRuleSheet(context),
            child: const Icon(Icons.add),
          ),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              frostedPageBarInset(context) + 8,
              16,
              120,
            ),
            children: [
              Text(
                l10n.accessRuleDesc,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (rules.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      l10n.ipRulesEmpty,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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
                      actionColor: theme.colorScheme.error,
                      semanticLabel: l10n.deleteBtn,
                      onCommit: () => _delete(context, rule),
                      child: _RuleCard(
                        controller: widget.controller,
                        rule: rule,
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  /// 添加规则面板（自设置页的 IP 规则分区原样搬来）。
  Future<void> _showAddRuleSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final cidrCtrl = TextEditingController();
    bool allow = true;
    await showAppBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.addRule,
                    style: Theme.of(sheetCtx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    // Windows 上右键弹原生编辑菜单
                    contextMenuBuilder: textContextMenuBuilder,
                    controller: cidrCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: l10n.accessRules,
                      hintText: l10n.cidrHint,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: true, label: Text(l10n.ruleAllow)),
                      ButtonSegment(value: false, label: Text(l10n.ruleDeny)),
                    ],
                    selected: {allow},
                    onSelectionChanged: (s) => setSheet(() => allow = s.first),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      final cidr = cidrCtrl.text.trim();
                      if (NetworkUtils.parseCidr(cidr) == null) {
                        showAppToast(context, l10n.cidrInvalid);
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
                    child: Text(l10n.saveBtn),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// 一条规则卡：放行/拒绝徽标 + CIDR + 启用开关。
class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.controller, required this.rule});

  final ServerController controller;
  final CidrRule rule;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tint = rule.allow ? Colors.green.shade700 : cs.error;
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            Icon(
              rule.allow ? Icons.gpp_good_outlined : Icons.gpp_bad_outlined,
              color: rule.enabled ? tint : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rule.cidr,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    rule.allow ? l10n.ruleAllow : l10n.ruleDeny,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: rule.enabled ? tint : cs.onSurfaceVariant,
                    ),
                  ),
                ],
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
      ),
    );
  }
}
