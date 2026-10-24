import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField;
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/upstream_balance.dart';
import 'package:local2api/ui/upstream_balance_page.dart'
    show
        balanceDetailLabel,
        balanceErrorText,
        balanceFootnote,
        balanceHintFor;
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';

/// 上游余额页（miuix 版，对应 Material 版 `UpstreamBalancePage`）。
///
/// 从 miuix 编辑上游页的「余额」那一行进，查的是父页**当前草稿**的地址与
/// 密钥（[probe] 现造），没保存也能查。顶栏右侧是刷新，列表也支持下拉刷新。
///
/// 文案与明细标签跟 Material 版共用同一组纯函数（`balanceDetailLabel` 等），
/// 两边只会长得不一样，不会读出两种口径。
class MiuixUpstreamBalancePage extends StatefulWidget {
  const MiuixUpstreamBalancePage({
    super.key,
    required this.probe,
    this.upstreamName = '',
  });

  /// 用父页当前表单值现造一个上游（查余额要地址 / 密钥）。
  final Upstream Function() probe;

  /// 页头显示的上游名（可空）。
  final String upstreamName;

  @override
  State<MiuixUpstreamBalancePage> createState() =>
      _MiuixUpstreamBalancePageState();
}

class _MiuixUpstreamBalancePageState extends State<MiuixUpstreamBalancePage> {
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();

  UpstreamBalance? _balance;
  BalanceException? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _behavior.state.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await UpstreamBalanceService.fetch(widget.probe());
      if (!mounted) return;
      setState(() {
        _balance = result;
        _error = null;
        _busy = false;
      });
    } on BalanceException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _busy = false;
      });
    } catch (e) {
      // 兜底：服务层不该抛非 BalanceException 的东西，真抛了也别白屏。
      if (!mounted) return;
      setState(() {
        _error = BalanceException(BalanceFailure.network, '$e');
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;

    return Material(
      type: MaterialType.transparency,
      child: MiuixScaffold(
        containerColor: colors.surface,
        topBar: MiuixBlurTopBar(
          title: l10n.balanceTitle,
          scrollBehavior: _behavior,
          navigationIcon: MiuixIconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const MiuixAppIcon(
              AppIconNames.back,
              fallback: Icons.arrow_back,
            ),
          ),
          actions: [
            // miuix 顶栏图标不带 tooltip（与用量统计页同一套做法）。
            MiuixIconButton(
              onPressed: _busy ? null : _refresh,
              child: const MiuixAppIcon(
                AppIconNames.refresh,
                fallback: Icons.refresh,
              ),
            ),
          ],
        ),
        content: (padding) => MiuixScrollBehaviorListener(
          behavior: _behavior,
          child: MiuixPullToRefresh(
            // 下拉刷新与顶栏右侧刷新按钮共用 _refresh：isRefreshing 由本页
            // 托管（_busy 起转、结束收起）。behavior 同时喂顶栏与下拉头，
            // 与发现页同一套 InstallerX 规范接线。
            isRefreshing: _busy,
            onRefresh: _refresh,
            topAppBarScrollBehavior: _behavior,
            contentPadding: EdgeInsets.only(top: padding.top),
            refreshTexts: [
              l10n.miuixPullToRefresh,
              l10n.miuixReleaseToRefresh,
              l10n.miuixRefreshing,
              l10n.miuixRefreshDone,
            ],
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(16, padding.top + 8, 16, 40),
              children: [
                if (widget.upstreamName.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                    child: MiuixText(
                      widget.upstreamName.trim(),
                      fontSize: 13,
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ),
                MiuixGroupCard(
                  insideMargin: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                  child: _hero(l10n, colors),
                ),
                if (_balance != null && _balance!.details.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  MiuixGroupCard(
                    insideMargin: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: MiuixText(
                              l10n.balanceDetailsTitle,
                              fontSize: 13,
                              color: colors.onSurfaceVariantSummary,
                            ),
                          ),
                        ),
                        for (final d in _balance!.details)
                          _MiuixDetailRow(
                            label: balanceDetailLabel(l10n, d),
                            value: d.valueText,
                          ),
                      ],
                    ),
                  ),
                ],
                if (_balance != null &&
                    balanceFootnote(l10n, _balance!).isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                    child: MiuixText(
                      balanceFootnote(l10n, _balance!),
                      fontSize: 12,
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hero(AppLocalizations l10n, MiuixColors colors) {
    // 首屏还没回来：只给一句「查询中」，别摆一个空数字。
    if (_busy && _balance == null && _error == null) {
      return Row(
        children: [
          const MiuixCircularProgressIndicator(size: 20, strokeWidth: 2),
          const SizedBox(width: 14),
          Expanded(
            child: MiuixText(l10n.balanceRefreshing, fontSize: 16),
          ),
        ],
      );
    }
    final e = _error;
    if (e != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MiuixText(
            l10n.balanceFailed(balanceErrorText(l10n, e)),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          const SizedBox(height: 8),
          MiuixText(
            balanceHintFor(l10n, e.kind),
            fontSize: 13,
            color: colors.onSurfaceVariantSummary,
          ),
        ],
      );
    }
    final b = _balance;
    final amount = b == null || b.amountDisplay.isEmpty
        ? l10n.balanceNoData
        : b.amountDisplay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MiuixText(
          l10n.balanceAvailableLabel,
          fontSize: 13,
          color: colors.onSurfaceVariantSummary,
        ),
        const SizedBox(height: 6),
        MiuixText(
          amount,
          fontSize: 32,
          fontWeight: FontWeight.w700,
        ),
        if (b != null && b.accountUsable != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                MiuixAppIcon(
                  b.accountUsable! ? AppIconNames.check : AppIconNames.close,
                  fallback: b.accountUsable!
                      ? Icons.check_circle_outline
                      : Icons.cancel_outlined,
                  size: 20,
                  color: b.accountUsable! ? null : colors.error,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MiuixText(
                    b.accountUsable!
                        ? l10n.balanceStatusOk
                        : l10n.balanceStatusBad,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        if (b != null) ...[
          const SizedBox(height: 12),
          MiuixText(
            '${l10n.balanceSourceLabel}: ${b.source}',
            fontSize: 12,
            color: colors.onSurfaceVariantSummary,
          ),
          const SizedBox(height: 4),
          MiuixText(
            l10n.balanceUpdatedAt(_clock(b.fetchedAt)),
            fontSize: 12,
            color: colors.onSurfaceVariantSummary,
          ),
        ],
      ],
    );
  }

  static String _clock(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}:'
      '${d.second.toString().padLeft(2, '0')}';
}

/// 明细一行：左标签右值（miuix 版，跟 Material 版同一份信息架构）。
class _MiuixDetailRow extends StatelessWidget {
  const _MiuixDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: MiuixText(
              label,
              fontSize: 14,
              color: colors.onSurfaceVariantSummary,
            ),
          ),
          const SizedBox(width: 12),
          MiuixText(value, fontSize: 14, fontWeight: FontWeight.w600),
        ],
      ),
    );
  }
}
