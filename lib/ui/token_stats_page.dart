import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/usage_stats.dart';
import 'package:local2api/widgets/app_toast.dart';
import 'package:local2api/ui/token_calendar_page.dart';
import 'package:local2api/ui/widgets/common.dart' show pushPage;
import 'package:local2api/widgets/expressive_app_bar.dart';
import 'package:local2api/widgets/frosted_page_bar.dart';
import 'package:local2api/widgets/navi_oval_tab_row.dart';

/// 时间范围挡位。`custom` 是日历里挑出来的某一天，只在有值时出现。
enum _Range { today, days7, days30, custom, all }

DateTime _startOfToday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// 某段的起点（含）。`custom` 用日历挑的那天 00:00。
DateTime? _rangeFrom(_Range r, DateTime? day) => switch (r) {
  _Range.today => _startOfToday(),
  _Range.days7 => _startOfToday().subtract(const Duration(days: 6)),
  _Range.days30 => _startOfToday().subtract(const Duration(days: 29)),
  _Range.custom => day == null ? null : UsageStats.startOfDay(day),
  _Range.all => null,
};

/// 某段的终点（含）。只有 `custom` 需要封口，其余都开到「现在」。
DateTime? _rangeTo(_Range r, DateTime? day) => r == _Range.custom && day != null
    ? UsageStats.startOfDay(
        day,
      ).add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1))
    : null;

String _rangeLabel(AppLocalizations l10n, _Range r, DateTime? day) =>
    switch (r) {
      _Range.today => l10n.usageRangeToday,
      _Range.days7 => l10n.usageRange7,
      _Range.days30 => l10n.usageRange30,
      _Range.custom =>
        day == null ? l10n.usageRangeToday : '${day.month}/${day.day}',
      _Range.all => l10n.usageRangeAll,
    };

/// 数字缩写：1234 → 1.2k，1234567 → 1.2M。原始数字放 tooltip。
String formatTokens(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) {
    final v = n / 1000;
    return '${v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)}k';
  }
  final v = n / 1000000;
  return '${v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)}M';
}

String formatHitRate(double rate) => '${(rate * 100).toStringAsFixed(1)}%';

/// Token 统计页（Material 版）：看某个模型在某段时间里的
/// 输入 / 输出 / 缓存命中 / 未命中，以及按天的柱状图与最近明细。
///
/// 数据来源是本机代理的记账（`UsageStats`），不抓包、不上报，
/// 只存汇总数字。
class TokenStatsPage extends StatefulWidget {
  const TokenStatsPage({super.key});

  @override
  State<TokenStatsPage> createState() => _TokenStatsPageState();
}

class _TokenStatsPageState extends State<TokenStatsPage> {
  _Range _range = _Range.days7;

  /// 选中的那一把本机 API Key：`null` = 全部，**空串** = 没带密钥的调用。
  String? _keyId;

  /// null = 全部模型。
  String? _model;

  /// 日历挑出来的那天；只有 `_Range.custom` 时才用得上。
  DateTime? _customDay;

  @override
  void initState() {
    super.initState();
    usageStats.addListener(_onChanged);
  }

  @override
  void dispose() {
    usageStats.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// 进日历翻日子；点中某张模型卡片后带着「那天 + 那个模型」回到这里。
  Future<void> _openCalendar() async {
    final focus = await pushPage<TokenStatsFocus>(
      context,
      TokenCalendarPage(
        initialDay: _range == _Range.custom ? _customDay : null,
      ),
    );
    if (!mounted || focus == null) return;
    setState(() {
      _model = focus.model;
      _customDay = UsageStats.startOfDay(focus.day);
      _range = _Range.custom;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final from = _rangeFrom(_range, _customDay);
    final to = _rangeTo(_range, _customDay);

    // 密钥下拉按「当前时间段、不挑 key」来列：否则选中某把 key 之后下拉
    // 里就只剩它自己，切不回去了。
    final keyRefs = usageStats.keysWithin(from: from, to: to);
    final keyId = _keyId != null && keyRefs.any((k) => k.id == _keyId)
        ? _keyId
        : null;

    // 模型下拉收窄到「这把 key、这段时间里真打过的模型」——没调用过的模型不占选项。
    final models = usageStats.modelsOfKey(keyId, from: from, to: to);
    final model = (_model != null && models.contains(_model)) ? _model : null;

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
              ? _startOfToday()
              : DateTime.fromMillisecondsSinceEpoch(records.last.timeMs)),
      to: to,
    );

    // 顶栏与「请求日志」页同一套（FrostedBarPage + MorphIconButton）；
    // 时间范围是页面级的互斥筛选，按 NaviFlash 分区/搜索的做法进顶栏自带的
    // tab 行，不再是内容区的一排 ChoiceChip。
    final ranges = [
      for (final r in _Range.values)
        if (r != _Range.custom || _customDay != null) r,
    ];
    final rangeLabels = [
      for (final r in ranges) _rangeLabel(l10n, r, _customDay),
    ];
    return FrostedBarPage(
      title: l10n.usageTitle,
      actions: [
        MorphIconButton(
          icon: Icons.calendar_month_outlined,
          tooltip: l10n.usageCalendarOpen,
          transparent: true,
          onTap: _openCalendar,
        ),
        if (usageStats.records.isNotEmpty)
          MorphIconButton(
            icon: Icons.delete_sweep_outlined,
            tooltip: l10n.usageClear,
            transparent: true,
            onTap: _clear,
          ),
      ],
      bottomHeight: kNaviOvalTabRowHeight,
      bottom: NaviOvalTabRow(
        labels: rangeLabels,
        selectedIndex: ranges.indexOf(_range),
        onTap: (i) => setState(() => _range = ranges[i]),
        glassTabs: naviGlassTabsFromLabels(rangeLabels),
      ),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          // 首屏占位要把 tab 行那一条也算进去。
          frostedPageBarInset(context, bottomHeight: kNaviOvalTabRowHeight) + 8,
          16,
          24,
        ),
        children: [
          Text(
            l10n.usageIntro,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          // 两个筛选维度（API Key / 模型），照 DeepSeek 账单页那样并排；
          // 时间范围在顶栏的 tab 行里。
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: _filter(
                      cs: cs,
                      theme: theme,
                      icon: Icons.key_outlined,
                      label: l10n.usageApiKeyFilter,
                      enabled: keyRefs.isNotEmpty,
                      items: [
                        l10n.usageAllApiKeys,
                        for (final k in keyRefs)
                          k.display(l10n.usageKeyAnonymous),
                      ],
                      selectedIndex: keyId == null
                          ? 0
                          : 1 + keyRefs.indexWhere((k) => k.id == keyId),
                      onChanged: (i) => setState(() {
                        _keyId = i == 0 || i == null ? null : keyRefs[i - 1].id;
                        _model = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _filter(
                      cs: cs,
                      theme: theme,
                      icon: Icons.smart_toy_outlined,
                      label: l10n.usageModelFilter,
                      enabled: models.isNotEmpty,
                      items: [l10n.usageAllModelsShort, for (final m in models) m],
                      selectedIndex: model == null
                          ? 0
                          : models.indexOf(model) + 1,
                      onChanged: (i) => setState(
                        () => _model = i == 0 || i == null ? null : models[i - 1],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          _SummaryGrid(l10n: l10n, summary: summary),
          const SizedBox(height: 18),
          if (records.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  l10n.usageEmpty,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else ...[
            Text(
              l10n.usageByModel,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            _ModelTable(rows: rows, l10n: l10n),
            const SizedBox(height: 18),
            Text(
              l10n.usageByDay,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            _DayChart(days: days),
            const SizedBox(height: 18),
            Text(
              l10n.usageRecent,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            for (final r in records.take(50)) _UsageRow(usage: r),
          ],
        ],
      ),
    );
  }

  /// 一个筛选维度：标签 + 下拉。选项为空时禁用（比如压根没有出过账的 key）。
  Widget _filter({
    required ColorScheme cs,
    required ThemeData theme,
    required IconData icon,
    required String label,
    required bool enabled,
    required List<String> items,
    required int selectedIndex,
    required ValueChanged<int?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<int>(
          // FormField 只在第一次建时吃 initialValue：不加 key 的话，代码里
          // 把选择改回去（换 key 清空模型、日历回填）时下拉还显示旧值。
          key: ValueKey('$label-$selectedIndex'),
          initialValue: enabled ? selectedIndex : 0,
          isDense: true,
          isExpanded: true,
          items: [
            for (var i = 0; i < items.length; i++)
              DropdownMenuItem<int>(value: i, child: Text(items[i])),
          ],
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
  }

  Future<void> _clear() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.usageClear),
        content: Text(l10n.usageClearConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    usageStats.clear();
    showAppToast(context, l10n.usageCleared);
  }
}

/// 汇总指标：合计 / 输入 / 输出 / 命中 / 未命中 / 命中率（+ 请求数）。
class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.l10n, required this.summary});

  final AppLocalizations l10n;
  final UsageSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hit = summary.cacheHit > 0;
    final items = <({String label, String value, Color? color, String? hint})>[
      (
        label: l10n.usageTotal,
        value: formatTokens(summary.total),
        color: null,
        hint: '${summary.total}',
      ),
      (
        label: l10n.usageInput,
        value: formatTokens(summary.input),
        color: null,
        hint: '${summary.input}',
      ),
      (
        label: l10n.usageOutput,
        value: formatTokens(summary.output),
        color: null,
        hint: '${summary.output}',
      ),
      (
        label: l10n.usageCacheHit,
        value: formatTokens(summary.cacheHit),
        color: hit ? const Color(0xFF2BA471) : cs.onSurfaceVariant,
        hint: '${summary.cacheHit}',
      ),
      (
        label: l10n.usageCacheMiss,
        value: formatTokens(summary.cacheMiss),
        color: null,
        hint: '${summary.cacheMiss}',
      ),
      (
        label: l10n.usageHitRate,
        value: formatHitRate(summary.hitRate),
        color: hit ? const Color(0xFF2BA471) : cs.onSurfaceVariant,
        hint: formatHitRate(summary.hitRate),
      ),
      (
        label: l10n.usageRequests,
        value: '${summary.requests}',
        color: null,
        hint: '${summary.requests}',
      ),
      (
        label: l10n.usageReasoning,
        value: formatTokens(summary.reasoning),
        color: null,
        hint: '${summary.reasoning}',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 520 ? 4 : 2;
        final width = (constraints.maxWidth - 8 * (columns - 1)) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: Tooltip(
                  message: item.hint ?? item.value,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.value,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: item.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 「各模型用量」表：一行一个模型，末行合计。
///
/// **只列这段时间里真调用过的模型** —— 一个调用都没有的模型不占行。
class _ModelTable extends StatelessWidget {
  const _ModelTable({required this.rows, required this.l10n});

  final List<UsageModelUsage> rows;
  final AppLocalizations l10n;

  /// 六列排满之后还能看清的宽度；屏幕比这窄就横向滑着看。
  static const double _minWidth = 520;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (rows.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Center(
            child: Text(
              l10n.usageNoModelCalls,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
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
    }) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: align,
            style: (head
                    ? theme.textTheme.labelSmall
                    : theme.textTheme.bodySmall)
                ?.copyWith(
                  fontSize: head ? 11 : 12,
                  fontWeight: strong || head ? FontWeight.w700 : FontWeight.w500,
                  color: head
                      ? cs.onSurfaceVariant
                      : (strong ? cs.primary : null),
                ),
          ),
        );

    TableRow lineRow(List<Widget> cells, {bool bold = false}) => TableRow(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.outlineVariant, width: bold ? 1.4 : 0.6),
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
            cell(r.model, align: TextAlign.left),
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

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= _minWidth) return table;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: _minWidth, child: table),
            );
          },
        ),
      ),
    );
  }
}

/// 按天柱状图（不引第三方图表库：几根立着的方块就够看趋势）。
class _DayChart extends StatelessWidget {
  const _DayChart({required this.days});

  final List<UsageDay> days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (days.isEmpty) return const SizedBox.shrink();
    final shown = days.length > 30 ? days.sublist(days.length - 30) : days;
    final maxTotal = shown
        .map((d) => d.summary.total)
        .fold<int>(1, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in shown)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Tooltip(
                  message:
                      '${d.day.month}/${d.day.day}\n'
                      '${formatTokens(d.summary.total)}'
                      '\n${d.summary.requests} req',
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        formatTokens(d.summary.total),
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 9,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // 柱子分两段：下半是缓存命中，上半是其余；命中越高颜色越绿
                      Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height:
                                (d.summary.total - d.summary.cacheHit).clamp(
                                  0,
                                  1 << 30,
                                ) /
                                maxTotal *
                                100,
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.55),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3),
                              ),
                            ),
                          ),
                          Container(
                            height:
                                d.summary.cacheHit.clamp(0, 1 << 30) /
                                maxTotal *
                                100,
                            decoration: const BoxDecoration(
                              color: Color(0xFF2BA471),
                              borderRadius: BorderRadius.vertical(
                                bottom: Radius.circular(3),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${d.day.month}/${d.day.day}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 9,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 一条明细。
class _UsageRow extends StatelessWidget {
  const _UsageRow({required this.usage});

  final TokenUsage usage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final at = DateTime.fromMillisecondsSinceEpoch(usage.timeMs);
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    final noUsage = usage.total == 0 && usage.cacheHit == 0;
    // 副标题：上游 · 车道，外加这把 key 的叫法。
    final sub = <String>[
      if (usage.lane.isNotEmpty && usage.lane != usage.model)
        '${usage.upstream} · ${usage.lane}',
      if (usage.hasApiKey)
        usage.apiKeyName.isNotEmpty ? usage.apiKeyName : usage.apiKeyLabel,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(
              '$hh:$mm',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  usage.model,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (noUsage)
            Text(
              l10n.usageNoUsageData,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            )
          else
            Text(
              '↑${formatTokens(usage.input)} ↓${formatTokens(usage.output)}'
              '${usage.cacheHit > 0 ? ' ⚡${formatTokens(usage.cacheHit)}' : ''}',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}
