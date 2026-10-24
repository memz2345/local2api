import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_info_card.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/usage_stats.dart';
import 'package:local2api/ui/miuix/miuix_token_calendar_page.dart';
import 'package:local2api/ui/token_stats_page.dart'
    show formatTokens, formatHitRate;
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/widgets/miuix/miuix_dialog.dart';
import 'package:local2api/widgets/miuix/miuix_page_popup_host.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';

/// 时间范围挡位（与 Material 版同一套语义）。
/// `custom` 是日历里挑出来的某一天，只在挑过之后才出现。
enum MiuixUsageRange {
  today,
  days7,
  days30,
  custom,
  all;

  DateTime _startOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// 某段的起点（含）。
  DateTime? from([DateTime? day]) => switch (this) {
    MiuixUsageRange.today => _startOfToday(),
    MiuixUsageRange.days7 => _startOfToday().subtract(const Duration(days: 6)),
    MiuixUsageRange.days30 => _startOfToday().subtract(
      const Duration(days: 29),
    ),
    MiuixUsageRange.custom => day == null ? null : UsageStats.startOfDay(day),
    MiuixUsageRange.all => null,
  };

  /// 某段的终点（含）。只有「某一天」需要封口，其余都开到「现在」。
  DateTime? to([DateTime? day]) => this == MiuixUsageRange.custom && day != null
      ? UsageStats.startOfDay(
          day,
        ).add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1))
      : null;
}

/// Token 统计页（miuix 版，对应 Material 版 `TokenStatsPage`）。
///
/// 看某个模型在某段时间里的输入 / 输出 / 缓存命中 / 未命中 + 按天柱状图 +
/// 最近明细。数据是本机代理的记账（`UsageStats`），不抓包、不上报。
class MiuixTokenStatsPage extends StatefulWidget {
  const MiuixTokenStatsPage({super.key});

  @override
  State<MiuixTokenStatsPage> createState() => _MiuixTokenStatsPageState();
}

class _MiuixTokenStatsPageState extends State<MiuixTokenStatsPage> {
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();

  MiuixUsageRange _range = MiuixUsageRange.days7;

  /// 选中的那一把本机 API Key：`null` = 全部，**空串** = 没带密钥的调用。
  String? _keyId;

  /// null = 全部模型。
  String? _model;

  /// 日历挑出来的那天；只有 `MiuixUsageRange.custom` 时才用得上。
  DateTime? _customDay;

  @override
  void initState() {
    super.initState();
    usageStats.addListener(_onChanged);
  }

  @override
  void dispose() {
    usageStats.removeListener(_onChanged);
    _behavior.state.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// 进日历翻日子；点中某张模型卡片后带着「那天 + 那个模型」回到这里。
  Future<void> _openCalendar() async {
    final focus = await Navigator.of(context).push<TokenStatsFocus>(
      MaterialPageRoute<TokenStatsFocus>(
        builder: (_) => MiuixTokenCalendarPage(
          initialDay: _range == MiuixUsageRange.custom ? _customDay : null,
        ),
      ),
    );
    if (!mounted || focus == null) return;
    setState(() {
      _model = focus.model;
      _customDay = UsageStats.startOfDay(focus.day);
      _range = MiuixUsageRange.custom;
    });
  }

  /// 当前要显示的范围片：「某一天」挑过才占位。
  List<MiuixUsageRange> get _shownRanges => [
    for (final r in MiuixUsageRange.values)
      if (r != MiuixUsageRange.custom || _customDay != null) r,
  ];

  String _rangeLabel(AppLocalizations l10n, MiuixUsageRange r) => switch (r) {
    MiuixUsageRange.today => l10n.usageRangeToday,
    MiuixUsageRange.days7 => l10n.usageRange7,
    MiuixUsageRange.days30 => l10n.usageRange30,
    MiuixUsageRange.custom =>
      _customDay == null
          ? l10n.usageRangeToday
          : '${_customDay!.month}/${_customDay!.day}',
    MiuixUsageRange.all => l10n.usageRangeAll,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;

    final from = _range.from(_customDay);
    final to = _range.to(_customDay);

    // 密钥下拉按「当前时间段、不挑 key」来列：否则选中某把 key 之后下拉
    // 里就只剩它自己，切不回去了。
    final keyRefs = usageStats.keysWithin(from: from, to: to);
    final keyId = _keyId != null && keyRefs.any((k) => k.id == _keyId)
        ? _keyId
        : null;

    // 模型下拉收窄到「这把 key、这段时间里真打过的模型」——没调用过的模型不占选项。
    final allModels = usageStats.modelsOfKey(keyId, from: from, to: to);
    final model = (_model != null && allModels.contains(_model))
        ? _model
        : null;

    final records = usageStats.query(
      model: model,
      apiKeyId: keyId,
      from: from,
      to: to,
    );
    final summary = UsageSummary.of(records);
    // 「各模型用量」表：只列这段时间里真调用过的模型。
    final rows = usageStats
        .byModel(apiKeyId: keyId, from: from, to: to)
        .where((r) => model == null || r.model == model)
        .toList();
    final days = usageStats.byDay(
      model: model,
      apiKeyId: keyId,
      from:
          from ??
          (records.isEmpty
              ? DateTime.now()
              : DateTime.fromMillisecondsSinceEpoch(records.last.timeMs)),
      to: to,
    );

    final keyIndex = keyId == null
        ? 0
        : 1 + keyRefs.indexWhere((k) => k.id == keyId);

    // 弹层宿主罩在 Scaffold 外面：miuix 的菜单是按「全局坐标的锚点」定位的，
    // 宿主必须覆盖整屏，否则弹层整体会偏掉一个顶栏的高度。
    return MiuixPagePopupHost(
      child: Material(
        type: MaterialType.transparency,
        child: MiuixScaffold(
          containerColor: colors.surface,
          topBar: MiuixBlurTopBar(
            scrollBehavior: _behavior,
            title: l10n.usageTitle,
            navigationIcon: MiuixIconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const MiuixAppIcon(
                AppIconNames.back,
                fallback: Icons.arrow_back,
              ),
            ),
            actions: [
              MiuixIconButton(
                onPressed: _openCalendar,
                child: const Icon(Icons.calendar_month_outlined),
              ),
              MiuixIconButton(
                onPressed: usageStats.records.isEmpty ? null : _clear,
                child: const Icon(Icons.delete_sweep_outlined),
              ),
            ],
          ),
          // 内容铺满整页、顶栏画在其上；顶栏高度垫进 padding，从栏下穿过。
          content: (padding) => MiuixScrollBehaviorListener(
            behavior: _behavior,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(16, padding.top + 4, 16, 40),
              children: [
                MiuixDismissibleInfoCard(
                  id: 'intro.usage',
                  text: l10n.usageIntro,
                ),
                const SizedBox(height: 12),
                // 时间范围：等宽胶囊片（与设置页的二选一片同一套做法）。
                // 「某一天」只在日历里挑过之后才占位。
                Row(
                  children: [
                    for (final r in _shownRanges) ...[
                      Expanded(
                        child: _MiuixRangeChip(
                          label: _rangeLabel(l10n, r),
                          selected: _range == r,
                          onTap: () => setState(() => _range = r),
                        ),
                      ),
                      if (r != _shownRanges.last) const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                // 两个筛选维度（按哪个 API Key / 哪个模型），照 DeepSeek
                // 账单页那样并排放在时间维度下面。
                MiuixGroupCard(
                  insideMargin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      MiuixOverlayDropdownPreference(
                        enabled: keyRefs.isNotEmpty,
                        title: l10n.usageApiKeyFilter,
                        startAction: const Icon(Icons.key_outlined),
                        items: [
                          l10n.usageAllApiKeys,
                          for (final k in keyRefs)
                            k.display(l10n.usageKeyAnonymous),
                        ],
                        selectedIndex: keyIndex,
                        onSelectedIndexChange: (i) => setState(() {
                          // 换 key 就把模型清掉：两份下拉的选项集不一样，
                          // 留着旧的选择会查不出东西。
                          _keyId = i == 0 ? null : keyRefs[i - 1].id;
                          _model = null;
                        }),
                      ),
                      const MiuixHorizontalDivider(),
                      MiuixOverlayDropdownPreference(
                        enabled: allModels.isNotEmpty,
                        title: l10n.usageModelFilter,
                        startAction: const Icon(Icons.smart_toy_outlined),
                        items: [
                          l10n.usageAllModelsShort,
                          for (final m in allModels) m,
                        ],
                        selectedIndex: model == null
                            ? 0
                            : allModels.indexOf(model) + 1,
                        onSelectedIndexChange: (i) =>
                            setState(() => _model = i == 0 ? null : allModels[i - 1]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _MiuixSummaryCard(l10n: l10n, summary: summary),
                if (records.isEmpty) ...[
                  const SizedBox(height: 24),
                  Center(
                    child: MiuixText(
                      l10n.usageEmpty,
                      fontSize: 14,
                      textAlign: TextAlign.center,
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 18),
                  MiuixSmallTitle(
                    l10n.usageByModel,
                    insideMargin: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 6),
                  _MiuixModelTable(rows: rows, l10n: l10n),
                  const SizedBox(height: 18),
                  MiuixSmallTitle(
                    l10n.usageByDay,
                    insideMargin: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 6),
                  _MiuixDayChart(days: days, colors: colors),
                  const SizedBox(height: 18),
                  MiuixSmallTitle(
                    l10n.usageRecent,
                    insideMargin: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 6),
                  for (final r in records.take(50))
                    _MiuixUsageCard(usage: r, l10n: l10n, colors: colors),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _clear() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showMiuixDialog<bool>(
      context: context,
      title: l10n.usageClear,
      message: l10n.usageClearConfirm,
      actions: [
        MiuixDialogAction(
          label: l10n.cancel,
          onPressed: (ctx) => Navigator.of(ctx).pop(false),
        ),
        MiuixDialogAction(
          label: l10n.confirm,
          primary: true,
          onPressed: (ctx) => Navigator.of(ctx).pop(true),
        ),
      ],
    );
    if (ok != true || !mounted) return;
    usageStats.clear();
    showMiuixToast(context, l10n.usageCleared);
  }
}

/// 时间范围片：用 MiuixCard 当胶囊（避免在 HyperOS 页面里露出 Material 控件）。
class _MiuixRangeChip extends StatelessWidget {
  const _MiuixRangeChip({
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
    );
  }
}

/// 汇总：合计 / 输入 / 输出 / 命中 / 未命中 / 命中率 / 请求数 / 思考。
class _MiuixSummaryCard extends StatelessWidget {
  const _MiuixSummaryCard({required this.l10n, required this.summary});

  final AppLocalizations l10n;
  final UsageSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final hit = summary.cacheHit > 0;
    final items = <({String label, String value, Color? color})>[
      (label: l10n.usageTotal, value: formatTokens(summary.total), color: null),
      (label: l10n.usageInput, value: formatTokens(summary.input), color: null),
      (
        label: l10n.usageOutput,
        value: formatTokens(summary.output),
        color: null,
      ),
      (
        label: l10n.usageCacheHit,
        value: formatTokens(summary.cacheHit),
        color: hit ? const Color(0xFF2BA471) : null,
      ),
      (
        label: l10n.usageCacheMiss,
        value: formatTokens(summary.cacheMiss),
        color: null,
      ),
      (
        label: l10n.usageHitRate,
        value: formatHitRate(summary.hitRate),
        color: hit ? const Color(0xFF2BA471) : null,
      ),
      (label: l10n.usageRequests, value: '${summary.requests}', color: null),
      (
        label: l10n.usageReasoning,
        value: formatTokens(summary.reasoning),
        color: null,
      ),
    ];

    return MiuixGroupCard(
      insideMargin: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i += 2)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
              child: Row(
                children: [
                  Expanded(
                    child: _MiuixMetric(
                      label: items[i].label,
                      value: items[i].value,
                      color: items[i].color,
                      colors: colors,
                    ),
                  ),
                  Expanded(
                    child: _MiuixMetric(
                      label: items[i + 1].label,
                      value: items[i + 1].value,
                      color: items[i + 1].color,
                      colors: colors,
                    ),
                  ),
                  // 奇数项补位：最后一行本来就只有 2 列，这里保持对齐
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MiuixMetric extends StatelessWidget {
  const _MiuixMetric({
    required this.label,
    required this.value,
    required this.colors,
    this.color,
  });

  final String label;
  final String value;
  final MiuixColors colors;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MiuixText(label, fontSize: 12, color: colors.onSurfaceVariantSummary),
        const SizedBox(height: 2),
        MiuixText(
          value,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: color ?? colors.onSurface,
        ),
      ],
    );
  }
}

/// 「各模型用量」表（DeepSeek 账单页下面那张表）：一行一个模型，末行合计。
///
/// **只列这段时间里真调用过的模型** —— 一个调用都没有的模型不占行。
class _MiuixModelTable extends StatelessWidget {
  const _MiuixModelTable({required this.rows, required this.l10n});

  final List<UsageModelUsage> rows;
  final AppLocalizations l10n;

  /// 六列排满之后还能看清的宽度；屏幕比这窄就横向滑着看。
  static const double _minWidth = 520;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final line = Theme.of(context).dividerColor;

    if (rows.isEmpty) {
      return MiuixGroupCard(
        insideMargin: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        child: Center(
          child: MiuixText(
            l10n.usageNoModelCalls,
            fontSize: 13,
            textAlign: TextAlign.center,
            color: colors.onSurfaceVariantSummary,
          ),
        ),
      );
    }

    final total = rows
        .map((r) => r.summary)
        .fold(const UsageSummary(), (a, b) => a + b);

    Widget cell(
      String text, {
      TextAlign align = TextAlign.right,
      bool head = false,
      bool strong = false,
      bool ellipsis = false,
      int maxLines = 1,
    }) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 9),
          child: MiuixText(
            text,
            fontSize: head ? 11 : 12,
            fontWeight: strong || head ? FontWeight.w700 : FontWeight.w500,
            textAlign: align,
            maxLines: ellipsis ? maxLines : 1,
            overflow: TextOverflow.ellipsis,
            color: head
                ? colors.onSurfaceVariantSummary
                : (strong ? colors.primary : null),
          ),
        );

    TableRow lineRow(List<Widget> cells, {bool bold = false}) => TableRow(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: line, width: bold ? 1.4 : 0.6),
        ),
      ),
      children: cells,
    );

    final table = Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: const <int, TableColumnWidth>{
        0: FlexColumnWidth(2.6),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1),
        4: FlexColumnWidth(1),
        5: FlexColumnWidth(1),
      },
      children: [
        lineRow([
          cell(l10n.usageModelFilter, align: TextAlign.left, head: true),
          cell(l10n.usageCacheHit, head: true),
          cell(l10n.usageCacheMiss, head: true),
          cell(l10n.usageInput, head: true),
          cell(l10n.usageOutput, head: true),
          cell(l10n.usageTotal, head: true),
        ]),
        for (final r in rows)
          lineRow([
            cell(r.model, align: TextAlign.left, ellipsis: true),
            cell(formatTokens(r.summary.cacheHit)),
            cell(formatTokens(r.summary.cacheMiss)),
            cell(formatTokens(r.summary.input)),
            cell(formatTokens(r.summary.output)),
            cell(formatTokens(r.summary.total), strong: true),
          ]),
        lineRow([
          cell(l10n.usageTotalRow, align: TextAlign.left, head: true),
          cell(formatTokens(total.cacheHit)),
          cell(formatTokens(total.cacheMiss)),
          cell(formatTokens(total.input)),
          cell(formatTokens(total.output)),
          cell(formatTokens(total.total), strong: true),
        ], bold: true),
      ],
    );

    return MiuixGroupCard(
      insideMargin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= _minWidth) return table;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: _minWidth, child: table),
          );
        },
      ),
    );
  }
}

/// 按天柱状图：下半段是缓存命中（绿），上半段是其余（主色）。
class _MiuixDayChart extends StatelessWidget {
  const _MiuixDayChart({required this.days, required this.colors});

  final List<UsageDay> days;
  final MiuixColors colors;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    final shown = days.length > 30 ? days.sublist(days.length - 30) : days;
    final maxTotal = shown
        .map((d) => d.summary.total)
        .fold<int>(1, (a, b) => a > b ? a : b);

    return MiuixGroupCard(
      insideMargin: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      child: SizedBox(
        height: 132,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final d in shown)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      MiuixText(
                        formatTokens(d.summary.total),
                        fontSize: 9,
                        color: colors.onSurfaceVariantSummary,
                      ),
                      const SizedBox(height: 2),
                      Container(
                        height:
                            (d.summary.total - d.summary.cacheHit).clamp(
                              0,
                              1 << 30,
                            ) /
                            maxTotal *
                            90,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.55),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3),
                          ),
                        ),
                      ),
                      Container(
                        height:
                            d.summary.cacheHit.clamp(0, 1 << 30) /
                            maxTotal *
                            90,
                        decoration: const BoxDecoration(
                          color: Color(0xFF2BA471),
                        ),
                      ),
                      const SizedBox(height: 4),
                      MiuixText(
                        '${d.day.month}/${d.day.day}',
                        fontSize: 9,
                        color: colors.onSurfaceVariantSummary,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 一条明细（时间 · 模型/车道 · 输入输出命中）。
class _MiuixUsageCard extends StatelessWidget {
  const _MiuixUsageCard({
    required this.usage,
    required this.l10n,
    required this.colors,
  });

  final TokenUsage usage;
  final AppLocalizations l10n;
  final MiuixColors colors;

  @override
  Widget build(BuildContext context) {
    final at = DateTime.fromMillisecondsSinceEpoch(usage.timeMs);
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    final noUsage = usage.total == 0 && usage.cacheHit == 0;
    // 副标题：上游 · 车道，外加这把 key 的叫法（有名字叫名字，否则脱敏串）。
    final sub = <String>[
      if (usage.lane.isNotEmpty && usage.lane != usage.model)
        '${usage.upstream} · ${usage.lane}',
      if (usage.hasApiKey)
        usage.apiKeyName.isNotEmpty ? usage.apiKeyName : usage.apiKeyLabel,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MiuixGroupCard(
        insideMargin: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            SizedBox(
              width: 42,
              child: MiuixText(
                '$hh:$mm',
                fontSize: 12,
                color: colors.onSurfaceVariantSummary,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MiuixText(
                    usage.model,
                    fontSize: 14,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sub.isNotEmpty)
                    MiuixText(
                      sub,
                      fontSize: 11,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      color: colors.onSurfaceVariantSummary,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            MiuixText(
              noUsage
                  ? l10n.usageNoUsageData
                  : '↑${formatTokens(usage.input)} ↓${formatTokens(usage.output)}'
                        '${usage.cacheHit > 0 ? ' ⚡${formatTokens(usage.cacheHit)}' : ''}',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: noUsage ? colors.onSurfaceVariantSummary : null,
            ),
          ],
        ),
      ),
    );
  }
}
