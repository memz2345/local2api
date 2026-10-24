import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/widgets/app_toast.dart';
import 'package:local2api/widgets/app_tooltip.dart';
import 'package:local2api/widgets/expressive_app_bar.dart';
import 'package:local2api/widgets/frosted_page_bar.dart';
import 'package:local2api/widgets/swipe_action_row.dart';

import 'dashboard_keys.dart' show showAddKeySheet;
import 'widgets/common.dart' show copyText;

/// 刚删掉、还等着「恢复」的密钥（原下标 + 条目）。
typedef PendingDelete = ({int index, ApiKeyEntry entry});

/// 密钥管理页（Material 版）。
///
/// 顶栏用与「请求日志」同一套 [FrostedBarPage]；右下角 FAB 加号添加密钥
/// （弹的是原来那个面板，不另起一套）；一行一条密钥，**左滑越过行宽 35% 松手
/// 即删**（不弹确认框），删完在底部弹 snackbar「已删除 N 个密钥 + 恢复」。
/// 动画照 UITEST.html 那套：胶囊宽度跟手增长 → 卡片飞出 → 胶囊铺满 → 行高收起。
class KeysPage extends StatefulWidget {
  const KeysPage({super.key, required this.controller});

  final ServerController controller;

  @override
  State<KeysPage> createState() => _KeysPageState();
}

class _KeysPageState extends State<KeysPage> {
  /// 最近删掉、还等着「恢复」的那批。删一次弹一条 snackbar；连着删就把条数累加
  /// 重开一条（把旧的那条挤掉，而不是排队）。
  final List<PendingDelete> _pending = [];

  /// snackbar 序号：连着删时后一条会把前一条顶掉，前一条的 closed 回调不该
  /// 把我们刚攒起来的待恢复列表清空 —— 只认当前这条。
  int _snackbarSeq = 0;

  /// 立即删除：**不弹确认框**，删完弹 snackbar 带「恢复」。
  ///
  /// 行本身在动画跑完后才回调到这里（见 SwipeActionRow），所以删除时机是
  /// 「整行已经飞出去并收起」的那一刻。
  ///
  /// ⚠️ [ctx] 必须是 build 里 `ScaffoldMessenger` **之内**的那个 context，不能
  /// 用 `State.context`：app 级 messenger 会把 snackbar 交给所有登记过的
  /// Scaffold，其中包含把这一页盖在下面的首页 —— 表现就是「在密钥页弹不出来，
  /// 退出密钥页才弹」，退出后还挂在上一页。套一层页面自带的 messenger（见
  /// build），登记的就只有本页那块 Scaffold：当场弹，路由一 pop 跟着子树销毁。
  /// 同理，`showAppToast` 里那条 `ScaffoldMessenger.maybeOf` 兜底也得用这个
  /// context，否则会撞上「no descendant Scaffolds to present to」。
  void _delete(BuildContext ctx, ApiKeyEntry entry) {
    final l10n = AppLocalizations.of(ctx);
    final keys = widget.controller.config.apiKeys;
    final index = keys.indexOf(entry);
    if (index < 0) return;
    keys.removeAt(index);
    widget.controller.store.update(widget.controller.config);
    _pending.insert(0, (index: index, entry: entry));

    final messenger = ScaffoldMessenger.of(ctx);
    final seq = ++_snackbarSeq;
    // 重新开一条：内容要显示累计条数，改文字不如换一条干净
    messenger.removeCurrentSnackBar();
    messenger
        .showSnackBar(
          SnackBar(
            content: Text(l10n.keyDeletedCount(_pending.length)),
            action: SnackBarAction(
              label: l10n.keyRestore,
              onPressed: () => _undoDelete(ctx),
            ),
            duration: const Duration(seconds: 5),
          ),
        )
        .closed
        .then((reason) {
          // 已经被后一条顶掉了：那条的 closed 不该动我们刚攒起来的列表
          if (seq != _snackbarSeq) return;
          // 超时/手动划掉就真的不能恢复了；点「恢复」时已在 _undoDelete 里清空
          if (reason != SnackBarClosedReason.action) _pending.clear();
        });
  }

  /// 把这一批删掉的按原下标放回去。
  ///
  /// _pending 是「新删的在前」，所以**按它本身的顺序**插：每条记的是它被删
  /// 那一刻的下标，先插后删的那条，先删的那条下标才作数。
  void _undoDelete(BuildContext ctx) {
    final l10n = AppLocalizations.of(ctx);
    final keys = widget.controller.config.apiKeys;
    for (final item in _pending) {
      final at = item.index.clamp(0, keys.length);
      keys.insert(at, item.entry);
    }
    final count = _pending.length;
    _pending.clear();
    widget.controller.store.update(widget.controller.config);
    showAppToast(ctx, l10n.keyRestored(count));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final keys = widget.controller.config.apiKeys;

    // snackbar 只认这一页：messenger 必须在 Scaffold 之上、路由之内，
    // 见 _delete 的注释
    return ScaffoldMessenger(
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => FrostedBarPage(
          title: l10n.keysTitle,
          actions: [
            MorphIconButton(
              icon: Icons.add_circle_outline,
              tooltip: l10n.addKey,
              transparent: true,
              onTap: () => showAddKeySheet(context, widget.controller),
            ),
          ],
          floatingActionButton: FloatingActionButton(
            tooltip: l10n.addKey,
            onPressed: () => showAddKeySheet(context, widget.controller),
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
              if (widget.controller.config.apiKeys.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      l10n.keysEmptyPage,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                for (final entry in keys)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SwipeActionRow(
                      // 必须按 id 给 key：删掉一行后如果没 key，Flutter 会把那个
                      // 「已收起」的 State 复用给下一行，下一行就会以收起状态出现
                      // （也划不动）。
                      key: ValueKey(entry.id),
                      actionIcon: Icons.delete_outline,
                      actionColor: theme.colorScheme.error,
                      semanticLabel: l10n.deleteKeyConfirm(
                        entry.name.isEmpty ? _mask(entry.key) : entry.name,
                      ),
                      onCommit: () => _delete(context, entry),
                      child: _KeyCard(
                        controller: widget.controller,
                        entry: entry,
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyCard extends StatelessWidget {
  const _KeyCard({required this.controller, required this.entry});

  final ServerController controller;
  final ApiKeyEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            Icon(
              Icons.key_outlined,
              color: entry.enabled ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name.isEmpty ? l10n.keyValueLabel : entry.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _mask(entry.key),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            AppTooltip(
              message: l10n.copy,
              child: IconButton(
                icon: const Icon(Icons.copy, size: 20),
                onPressed: () => copyText(context, entry.key),
              ),
            ),
            Switch(
              value: entry.enabled,
              onChanged: (v) {
                entry.enabled = v;
                controller.store.update(controller.config);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 密钥打码：留头 6 尾 4，中间省略。
String _mask(String key) {
  if (key.length <= 10) return key;
  return '${key.substring(0, 6)}…${key.substring(key.length - 4)}';
}
