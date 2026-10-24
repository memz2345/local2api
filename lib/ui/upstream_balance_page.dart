import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/upstream_balance.dart';
import 'package:local2api/src/loading_indicator_m3e.dart';
import 'package:local2api/widgets/expressive_app_bar.dart';
import 'package:local2api/widgets/frosted_page_bar.dart';
import 'package:local2api/widgets/m3e_pull_to_refresh.dart';

import 'widgets/common.dart' show SectionCard;

/// 上游余额页（Material 版，对应 miuix 版 `MiuixUpstreamBalancePage`）。
///
/// 从编辑上游页的「余额」那一行进：地址与密钥用的是**父页当前草稿**
/// （[probe] 现造），所以没保存也能直接查。右上角是刷新，列表也支持下拉刷新。
///
/// 展示口径刻意把「查询接口」写出来：new-api 的美元数是从 quota 按
/// `1 美元 = 500000` 折算的，OpenAI 那两个 dashboard 路径是未文档化的兼容
/// 探针 —— 用户看到数字的同时也得看到它是从哪个口径来的。
class UpstreamBalancePage extends StatefulWidget {
  const UpstreamBalancePage({
    super.key,
    required this.probe,
    this.upstreamName = '',
  });

  /// 用父页当前表单值现造一个上游（查余额要地址 / 密钥）。
  final Upstream Function() probe;

  /// 页头显示的上游名（可空）。
  final String upstreamName;

  @override
  State<UpstreamBalancePage> createState() => _UpstreamBalancePageState();
}

class _UpstreamBalancePageState extends State<UpstreamBalancePage> {
  UpstreamBalance? _balance;
  BalanceException? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
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
    return FrostedBarPage(
      title: l10n.balanceTitle,
      actions: [
        MorphIconButton(
          icon: Icons.refresh,
          tooltip: l10n.fabRefresh,
          transparent: true,
          onTap: _busy ? null : _refresh,
        ),
      ],
      child: M3EPullToRefresh(
        // 下拉刷新与右上角刷新按钮共用 _refresh：isRefreshing 由本页面托管
        // （_busy 变 true 起转，变 false 收起），和发现页同一套接线。
        isRefreshing: _busy,
        onRefresh: _refresh,
        // 指示器从毛玻璃顶栏下面滑出来，别压在标题上
        edgeOffset: frostedPageBarInset(context),
        semanticsLabel: l10n.balancePullHint,
        child: ListView(
          // 下拉靠顶部 overscroll 驱动。**不能**只挂裸的 ClampingScrollPhysics：
          // 余额页内容常不满屏，minScrollExtent == maxScrollExtent 时
          // ClampingScrollPhysics.shouldAcceptUserOffset 会直接拒绝这次拖拽，
          // 一个滚动通知都发不出来，下拉刷新就死了（发现页踩过同一个坑）。
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          padding: EdgeInsets.only(
            top: frostedPageBarInset(context) + 8,
            bottom: 32,
          ),
          children: [
            if (widget.upstreamName.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  widget.upstreamName.trim(),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            SectionCard(
              child: _hero(l10n),
            ),
            if (_balance != null && _balance!.details.isNotEmpty)
              SectionCard(
                title: l10n.balanceDetailsTitle,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final d in _balance!.details)
                      _DetailRow(
                        label: balanceDetailLabel(l10n, d),
                        value: d.valueText,
                      ),
                  ],
                ),
              ),
            if (_balance != null && balanceFootnote(l10n, _balance!).isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Text(
                  balanceFootnote(l10n, _balance!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _hero(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (_busy && _balance == null && _error == null) {
      return Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: LoadingIndicatorM3E(
              constraints: BoxConstraints.tightFor(width: 22, height: 22),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              l10n.balanceRefreshing,
              style: theme.textTheme.titleMedium,
            ),
          ),
        ],
      );
    }
    if (_error != null) {
      final e = _error!;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: cs.error),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.balanceFailed(balanceErrorText(l10n, e)),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  balanceHintFor(l10n, e.kind),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    final b = _balance;
    final amount = b == null
        ? l10n.balanceNoData
        : (b.amountDisplay.isEmpty ? l10n.balanceNoData : b.amountDisplay);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.balanceAvailableLabel,
          style: theme.textTheme.labelMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          amount,
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 34,
          ),
        ),
        if (b != null && b.accountUsable != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                b.accountUsable! ? Icons.check_circle_outline : Icons.block,
                size: 18,
                color: b.accountUsable! ? cs.primary : cs.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  b.accountUsable! ? l10n.balanceStatusOk : l10n.balanceStatusBad,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ],
        if (b != null) ...[
          const SizedBox(height: 8),
          Text(
            '${l10n.balanceSourceLabel}: ${b.source}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          Text(
            l10n.balanceUpdatedAt(_clock(b.fetchedAt)),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  static String _clock(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0') }:'
      '${d.minute.toString().padLeft(2, '0')}:'
      '${d.second.toString().padLeft(2, '0')}';
}

/// 一行「标签 - 值」（余额明细用；miuix 版有自己的同构行）。
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 明细行的标签（服务层只给 [BalanceDetailKind]，文案在这层取）。
String balanceDetailLabel(AppLocalizations l10n, BalanceDetail d) =>
    switch (d.kind) {
      BalanceDetailKind.balance when d.currency != null =>
        '${l10n.balanceAvailableLabel}（${d.currency}）',
      BalanceDetailKind.balance => l10n.balanceAvailableLabel,
      BalanceDetailKind.granted => l10n.balanceGrantedLabel,
      BalanceDetailKind.toppedUp => l10n.balanceToppedUpLabel,
      BalanceDetailKind.used => l10n.balanceUsedLabel,
      BalanceDetailKind.requests => l10n.balanceRequestsLabel,
      BalanceDetailKind.group => l10n.balanceGroupLabel,
      BalanceDetailKind.limit => l10n.balanceLimitLabel,
    };

/// 页脚那句补充说明：quota 折算要讲清楚，其它情况只报时间。
String balanceFootnote(AppLocalizations l10n, UpstreamBalance b) =>
    b.quotaConverted ? l10n.balanceQuotaNote : '';

/// 失败原因文案（服务层的 message 是中文兜底，这里按种类给本地化说法）。
String balanceErrorText(AppLocalizations l10n, BalanceException e) =>
    switch (e.kind) {
      BalanceFailure.noKey => l10n.balanceNoKey,
      BalanceFailure.unauthorized => l10n.balanceUnauthorized,
      BalanceFailure.unsupported => l10n.balanceUnsupported,
      BalanceFailure.badResponse => l10n.balanceBadResponse,
      BalanceFailure.network => e.message,
    };

/// 失败种类下该给用户的一步操作提示。
String balanceHintFor(AppLocalizations l10n, BalanceFailure kind) =>
    switch (kind) {
      BalanceFailure.noKey => l10n.balanceNoKeyHint,
      BalanceFailure.unauthorized => l10n.balanceUnauthorizedHint,
      BalanceFailure.unsupported => l10n.balanceUnsupportedHint,
      BalanceFailure.badResponse => l10n.balanceUnsupportedHint,
      BalanceFailure.network => l10n.balanceNetworkHint,
    };
