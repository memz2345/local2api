import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';
import 'package:local2api/widgets/swipe_action_row.dart';

import 'miuix_dashboard_keys.dart' show showMiuixAddKeySheet;

/// 刚删掉、还等着「恢复」的密钥（原下标 + 条目）。
typedef PendingDelete = ({int index, ApiKeyEntry entry});

/// 密钥管理页（miuix 版，对应 Material 版 `KeysPage`）。
///
/// 顶栏与 miuix 二级页统一（`MiuixBlurTopBar`，和请求日志页同款）；
/// 右下角 miuix FAB 加号添加（弹原来那个 miuix 添加面板）；
/// 一行一条密钥，**左滑越过行宽 35% 松手即删**（不弹确认框），删完弹
/// snackbar「已删除 N 个密钥 + 恢复」。
class MiuixKeysPage extends StatefulWidget {
  const MiuixKeysPage({super.key, required this.controller});

  final ServerController controller;

  @override
  State<MiuixKeysPage> createState() => _MiuixKeysPageState();
}

class _MiuixKeysPageState extends State<MiuixKeysPage> {
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();

  /// 最近删掉、还等着「恢复」的那批。删一次弹一条 snackbar；连着删就把条数
  /// 累加后重开一条（把旧那条挤掉，而不是排队）。
  final List<PendingDelete> _pending = [];

  /// snackbar 序号：连着删时后一条会把前一条顶掉，前一条的 closed 回调不该
  /// 把我们刚攒起来的待恢复列表清空 —— 只认当前这条。
  int _snackbarSeq = 0;

  /// 这一页自己的 miuix snackbar host（挂在下面 `MiuixScaffold(snackbarHost:)`）。
  final MiuixSnackbarHostState _snackHost = MiuixSnackbarHostState();

  @override
  void dispose() {
    _behavior.state.dispose();
    _snackHost.dispose();
    super.dispose();
  }

  /// 立即删除：**不弹确认框**，删完弹 snackbar 带「恢复」。
  ///
  /// 由行在「飞出 + 收起」动画跑完后回调过来（见 SwipeActionRow）。
  void _delete(ApiKeyEntry entry) {
    final keys = widget.controller.config.apiKeys;
    final index = keys.indexOf(entry);
    if (index < 0) return;
    keys.removeAt(index);
    widget.controller.store.update(widget.controller.config);
    _pending.insert(0, (index: index, entry: entry));
    unawaited(_showDeletedSnackbar());
  }

  /// 弹「已删除 N 个密钥 + 恢复」。
  ///
  /// ⚠️ 用 miuix 自己的 snackbar host，不用 Material 的 `SnackBar`：这一页是
  /// `MiuixScaffold`，底下**没有** Material `Scaffold` 能承载 snackbar，而 app 级
  /// `ScaffoldMessenger` 只会把它交给登记过的 Scaffold —— 也就是把这一页盖住的
  /// 首页那块。表现就是用户报的「在密钥页弹不出来，退出密钥页才弹」，而且退出后
  /// 还挂在上一页。host 挂在本页的 Scaffold 上：当场弹，路由一 pop 跟着子树销毁。
  Future<void> _showDeletedSnackbar() async {
    final l10n = AppLocalizations.of(context);
    final seq = ++_snackbarSeq;
    // 连着删：先把还挂着的那条收掉，重开一条带累计条数的，而不是排两条
    final previous = await _snackHost.newestSnackbarData();
    if (previous != null) await previous.dismiss();
    final result = await _snackHost.showSnackbar(
      l10n.keyDeletedCount(_pending.length),
      actionLabel: l10n.keyRestore,
      duration: const MiuixSnackbarDuration.custom(5000),
    );
    if (!mounted) return;
    // 已经被后一条顶掉了：那条的结果不该动我们刚攒起来的列表
    if (seq != _snackbarSeq) return;
    if (result == MiuixSnackbarResult.actionPerformed) {
      _undoDelete();
    } else {
      // 超时/划掉就真的不能恢复了；点「恢复」时在 _undoDelete 里已经清空
      _pending.clear();
    }
  }

  /// 按原下标放回去（倒着插，下标才不会被自己挤偏）。
  void _undoDelete() {
    final l10n = AppLocalizations.of(context);
    final keys = widget.controller.config.apiKeys;
    for (final item in _pending.reversed) {
      keys.insert(item.index.clamp(0, keys.length), item.entry);
    }
    final count = _pending.length;
    _pending.clear();
    widget.controller.store.update(widget.controller.config);
    showMiuixToast(context, l10n.keyRestored(count));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final keys = widget.controller.config.apiKeys;

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => Material(
        type: MaterialType.transparency,
        child: MiuixScaffold(
          containerColor: colors.surface,
          // 删除密钥后的「已删除 N 个 + 恢复」弹在这一页上，见 _showDeletedSnackbar
          snackbarHost: MiuixSnackbarHost(state: _snackHost),
          topBar: MiuixBlurTopBar(
            scrollBehavior: _behavior,
            title: l10n.keysTitle,
            navigationIcon: MiuixIconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const MiuixAppIcon(
                AppIconNames.back,
                fallback: Icons.arrow_back,
              ),
            ),
            actions: [
              MiuixIconButton(
                onPressed: () =>
                    showMiuixAddKeySheet(context, widget.controller),
                child: const MiuixAppIcon(
                  AppIconNames.addCircle,
                  fallback: Icons.add_circle_outline,
                ),
              ),
            ],
          ),
          floatingActionButton: MiuixFloatingActionButton(
            onPressed: () => showMiuixAddKeySheet(context, widget.controller),
            child: const MiuixAppIcon(AppIconNames.add, fallback: Icons.add),
          ),
          // 内容铺满整页、顶栏画在其上；顶栏高度垫进 padding，从栏下穿过。
          content: (padding) => MiuixScrollBehaviorListener(
            behavior: _behavior,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(16, padding.top + 4, 16, 120),
              children: [
                if (keys.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: MiuixText(
                        l10n.keysEmptyPage,
                        fontSize: 14,
                        textAlign: TextAlign.center,
                        color: colors.onSurfaceVariantSummary,
                      ),
                    ),
                  )
                else
                  for (final entry in keys)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SwipeActionRow(
                        // 必须按 id 给 key：删掉一行后如果没 key，Flutter 会把
                        // 那个「已收起」的 State 复用给下一行，下一行就会以
                        // 收起状态出现（也划不动）。
                        key: ValueKey(entry.id),
                        actionIcon: Icons.delete_outline,
                        actionColor: colors.error,
                        foregroundCornerRadius: MiuixCardDefaults.cornerRadius,
                        semanticLabel: l10n.deleteKeyConfirm(
                          entry.name.isEmpty ? _mask(entry.key) : entry.name,
                        ),
                        onCommit: () => _delete(entry),
                        child: _MiuixKeyCard(
                          controller: widget.controller,
                          entry: entry,
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
}

class _MiuixKeyCard extends StatelessWidget {
  const _MiuixKeyCard({required this.controller, required this.entry});

  final ServerController controller;
  final ApiKeyEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    return MiuixGroupCard(
      insideMargin: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          MiuixAppIcon(
            AppIconNames.lock,
            fallback: Icons.key_outlined,
            size: 20,
            color: entry.enabled
                ? colors.primary
                : colors.onSurfaceVariantSummary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MiuixText(
                  entry.name.isEmpty ? l10n.keyValueLabel : entry.name,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                MiuixText(
                  _mask(entry.key),
                  fontSize: 12,
                  fontFamily: 'monospace',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  color: colors.onSurfaceVariantSummary,
                ),
              ],
            ),
          ),
          MiuixIconButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: entry.key));
              if (!context.mounted) return;
              showMiuixToast(context, l10n.copied);
            },
            child: const Icon(Icons.copy, size: 18),
          ),
          MiuixSwitch(
            value: entry.enabled,
            onChanged: (v) {
              entry.enabled = v;
              controller.store.update(controller.config);
            },
          ),
        ],
      ),
    );
  }
}

/// 密钥打码：留头 6 尾 4，中间省略。
String _mask(String key) {
  if (key.length <= 10) return key;
  return '${key.substring(0, 6)}…${key.substring(key.length - 4)}';
}
