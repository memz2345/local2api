import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/usage_stats.dart';
import 'package:local2api/ui/token_stats_page.dart'
    show formatHitRate, formatTokens;
import 'package:local2api/widgets/frosted_page_bar.dart';
import 'package:local2api/widgets/month_slide_switcher.dart';
import 'package:local2api/widgets/predictive_back_sheet.dart';
import 'package:local2api/widgets/widgets.dart';

import 'widgets/today_fab.dart';

/// 用量日历（Material 版）：一个月里哪天用了多少、那天调用了哪些模型。
///
/// 顶上是一张月历（格子越亮 = 当天 token 越多），底下是选中那天的
/// 「活动」—— 一个模型一张卡片。点日期会把那天的活动从底部弹出来；
/// 点某张模型卡片则带着「这一天 + 这个模型」回统计页看明细。
class TokenCalendarPage extends StatefulWidget {
  const TokenCalendarPage({super.key, this.initialDay});

  /// 进来就选中的那天，默认今天。
  final DateTime? initialDay;

  @override
  State<TokenCalendarPage> createState() => _TokenCalendarPageState();
}

class _TokenCalendarPageState extends State<TokenCalendarPage> {
  /// 正在显示的月份（固定为当月 1 号）。
  late DateTime _month;

  /// 选中的那天（00:00）。
  late DateTime _selected;

  /// 最近一次翻月方向：+1 下个月（新月份从右滑入）、-1 上个月（从左滑入）、
  /// 0 非翻月跳转（点「今天」/ 补位格翻月）只淡入淡出。
  int _monthShift = 0;

  @override
  void initState() {
    super.initState();
    _selected = UsageStats.startOfDay(widget.initialDay ?? DateTime.now());
    _month = DateTime(_selected.year, _selected.month);
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

  void _shiftMonth(int delta) {
    setState(() {
      _monthShift = delta;
      _month = DateTime(_month.year, _month.month + delta);
    });
  }

  /// 回今天：选中今天并把月份翻回去（补位格翻月也是这个动作）。
  void _goToday() => _select(UsageStats.startOfDay(DateTime.now()));

  void _select(DateTime day) {
    setState(() {
      _selected = day;
      // 点到的日子可能来自相邻月份的补位格，跟着把月份翻过去。
      if (day.month != _month.month || day.year != _month.year) {
        _monthShift = 0;
        _month = DateTime(day.year, day.month);
      }
    });
  }

  /// 点日期：选中 + 从底部弹出那天的活动。
  Future<void> _pickDay(DateTime day) async {
    _select(day);
    final focus = await showAppBottomSheet<TokenStatsFocus?>(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kGroupRadius)),
      ),
      builder: (ctx) => FrostedSheet(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(kGroupRadius),
        ),
        child: SafeArea(
          top: false,
          child: _DayActivities(
            day: day,
            scrollable: true,
            onPickModel: (model) =>
                Navigator.of(ctx).pop(TokenStatsFocus(day: day, model: model)),
          ),
        ),
      ),
    );
    if (!mounted || focus == null) return;
    // 选了模型就把焦点带回统计页；只是关掉弹窗就留在日历上继续翻。
    Navigator.of(context).pop(focus);
  }

  /// 点内联卡片：直接带着焦点回统计页。
  void _openInStats(TokenStatsFocus focus) => Navigator.of(context).pop(focus);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final monthMap = usageStats.monthMap(_month);
    final dayRecords = usageStats.ofDay(_selected);
    final dayModels = usageStats.modelsOfDay(_selected);
    // 横屏：左日历 + 右侧当天模型调用，双栏；竖屏维持单列。
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return FrostedBarPage(
      title: l10n.usageCalendar,
      // 不看当月时给一颗「回今天」：翻得越远越需要一键回来。
      floatingActionButton: UsageStats.isCurrentMonth(_month)
          ? null
          : TodayFab(onPressed: _goToday),
      child: isLandscape
          ? _landscapeBody(
              theme: theme,
              monthMap: monthMap,
              dayRecords: dayRecords,
              dayModels: dayModels,
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                frostedPageBarInset(context) + 8,
                16,
                24,
              ),
              children: [
                Text(
                  l10n.usageCalendarIntro,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                _MonthHeader(
                  month: _month,
                  onPrev: () => _shiftMonth(-1),
                  onNext: () => _shiftMonth(1),
                  onToday: _goToday,
                ),
                const SizedBox(height: 10),
                // 星期表头固定不动，只有下面的格子翻页。
                const _WeekdayHeader(),
                const SizedBox(height: 6),
                // 左右滑动切月：只包网格，别吃掉下面活动列表的滚动。
                MonthSwipeArea(
                  onShift: _shiftMonth,
                  child: MonthSlideSwitcher(
                    direction: _monthShift,
                    child: KeyedSubtree(
                      key: ValueKey<DateTime>(_month),
                      child: _MonthGrid(
                        month: _month,
                        selected: _selected,
                        monthMap: monthMap,
                        onPick: _pickDay,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  l10n.usageCalendarDayModels(_dayLabel(context, _selected)),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _DayActivities(
                  day: _selected,
                  scrollable: false,
                  emptyRecords: dayRecords.isEmpty,
                  models: dayModels,
                  onPickModel: (m) =>
                      _openInStats(TokenStatsFocus(day: _selected, model: m)),
                ),
              ],
            ),
    );
  }

  /// 横屏双栏：左侧月历（限宽居中，别把格子撑成大方块），右侧当天模型调用。
  /// 点日期只选中（右栏跟着换），点模型卡片才带着焦点回统计页。
  Widget _landscapeBody({
    required ThemeData theme,
    required Map<DateTime, UsageSummary> monthMap,
    required List<TokenUsage> dayRecords,
    required List<UsageModelDay> dayModels,
  }) {
    final l10n = AppLocalizations.of(context);
    final cs = theme.colorScheme;
    final topInset = frostedPageBarInset(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 6,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, topInset + 8, 16, 24),
                children: [
                  Text(
                    l10n.usageCalendarIntro,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _MonthHeader(
                    month: _month,
                    onPrev: () => _shiftMonth(-1),
                    onNext: () => _shiftMonth(1),
                    onToday: _goToday,
                  ),
                  const SizedBox(height: 10),
                  // 星期表头固定不动，只有下面的格子翻页。
                  const _WeekdayHeader(),
                  const SizedBox(height: 6),
                  MonthSwipeArea(
                    onShift: _shiftMonth,
                    child: MonthSlideSwitcher(
                      direction: _monthShift,
                      child: KeyedSubtree(
                        key: ValueKey<DateTime>(_month),
                        child: _MonthGrid(
                          month: _month,
                          selected: _selected,
                          monthMap: monthMap,
                          onPick: _select,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        VerticalDivider(width: 1, thickness: 1, color: cs.outlineVariant),
        Expanded(
          flex: 5,
          child: _DayActivities(
            day: _selected,
            scrollable: true,
            emptyRecords: dayRecords.isEmpty,
            models: dayModels,
            onPickModel: (m) =>
                _openInStats(TokenStatsFocus(day: _selected, model: m)),
          ),
        ),
      ],
    );
  }
}

String _dayLabel(BuildContext context, DateTime day) {
  final m = MaterialLocalizations.of(context);
  return m.formatMediumDate(day);
}

/// 月份切换行：‹ 2026年10月 › + 回今天。
class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final label = MaterialLocalizations.of(context).formatMonthYear(month);

    return Row(
      children: [
        MorphIconButton(
          icon: Icons.chevron_left,
          tooltip: l10n.usageCalendarPrevMonth,
          transparent: true,
          onTap: onPrev,
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        MorphIconButton(
          icon: Icons.chevron_right,
          tooltip: l10n.usageCalendarNextMonth,
          transparent: true,
          onTap: onNext,
        ),
        TextButton(onPressed: onToday, child: Text(l10n.usageRangeToday)),
      ],
    );
  }
}

/// 月历网格：周一起头，格子亮度按当天 token 量给。
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.monthMap,
    required this.onPick,
  });

  final DateTime month;
  final DateTime selected;
  final Map<DateTime, UsageSummary> monthMap;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final today = UsageStats.startOfDay(DateTime.now());

    // 周日开头（MaterialLocalizations 的 narrowWeekdays 本身就是 日-六）：
    // DateTime.weekday 周一=1…周日=7，取 %7 让周日落在第 0 列。
    final leading = month.weekday % 7;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cells = ((leading + daysInMonth) / 7).ceil() * 7;
    final maxTotal = monthMap.values.fold<int>(
      1,
      (a, s) => a > s.total ? a : s.total,
    );

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.92,
      children: [
        for (var i = 0; i < cells; i++)
          () {
            final index = i - leading;
            if (index < 0 || index >= daysInMonth) {
              return const SizedBox.shrink();
            }
            final day = DateTime(month.year, month.month, index + 1);
            final summary = monthMap[day];
            return _DayCell(
              day: day,
              total: summary?.total ?? 0,
              ratio: summary == null ? 0 : summary.total / maxTotal,
              hasCacheHit: (summary?.cacheHit ?? 0) > 0,
              selected:
                  day.year == selected.year &&
                  day.month == selected.month &&
                  day.day == selected.day,
              isToday:
                  day.year == today.year &&
                  day.month == today.month &&
                  day.day == today.day,
              tooltip: summary == null
                  ? null
                  : '${formatTokens(summary.total)} · ${l10n.usageRequests} ${summary.requests}',
              onTap: () => onPick(day),
            );
          }(),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.total,
    required this.ratio,
    required this.hasCacheHit,
    required this.selected,
    required this.isToday,
    required this.onTap,
    this.tooltip,
  });

  final DateTime day;
  final int total;
  final double ratio;
  final bool hasCacheHit;
  final bool selected;
  final bool isToday;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final has = total > 0;

    final bg = has
        ? cs.primary.withValues(alpha: 0.14 + 0.46 * ratio.clamp(0.0, 1.0))
        : cs.surfaceContainerHighest.withValues(alpha: 0.35);

    final cell = Padding(
      padding: const EdgeInsets.all(2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: selected
              ? Border.all(color: cs.primary, width: 2)
              : isToday
              ? Border.all(color: cs.primary.withValues(alpha: 0.45))
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: selected || isToday
                    ? FontWeight.w800
                    : FontWeight.w500,
                color: isToday
                    ? cs.primary
                    : (has ? cs.onSurface : cs.onSurfaceVariant),
              ),
            ),
            if (has) ...[
              const SizedBox(height: 1),
              Text(
                formatTokens(total),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 9.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: tooltip == null ? cell : Tooltip(message: tooltip, child: cell),
    );
  }
}

/// 某天的活动：一个模型一张卡片。
///
/// 内联（日历页下半部分）和底部弹窗共用同一份渲染。
class _DayActivities extends StatelessWidget {
  const _DayActivities({
    required this.day,
    required this.onPickModel,
    this.scrollable = false,
    this.models,
    this.emptyRecords,
  });

  final DateTime day;
  final ValueChanged<String> onPickModel;

  /// 弹窗里要能滚（模型多的时候），内联就交给外层 ListView。
  final bool scrollable;

  /// 外面算好了就传进来，省得再查一遍。
  final List<UsageModelDay>? models;
  final bool? emptyRecords;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final list = models ?? usageStats.modelsOfDay(day);

    if (list.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          8,
          scrollable ? 24 : 12,
          8,
          scrollable ? 28 : 12,
        ),
        child: Center(
          child: Text(
            (emptyRecords ?? true)
                ? l10n.usageCalendarEmptyDay
                : l10n.usageNoUsageData,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final cards = <Widget>[
      for (final m in list)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _ModelActivityCard(item: m, onTap: () => onPickModel(m.model)),
        ),
    ];

    if (!scrollable) return Column(children: cards);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
            child: Text(
              l10n.usageCalendarDayModels(_dayLabel(context, day)),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ...cards,
        ],
      ),
    );
  }
}

/// 一张模型卡片：模型名 + 请求数 + 输入/输出/命中 + 命中率。
class _ModelActivityCard extends StatelessWidget {
  const _ModelActivityCard({required this.item, required this.onTap});

  final UsageModelDay item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = item.summary;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.smart_toy_outlined, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.model,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${s.requests} ${l10n.usageRequests}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${l10n.usageInput} ${formatTokens(s.input)}'
                    ' · ${l10n.usageOutput} ${formatTokens(s.output)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                if (s.cacheHit > 0)
                  Text(
                    '⚡${formatTokens(s.cacheHit)} ${formatHitRate(s.hitRate)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF2BA471),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 星期表头（日-六）：固定不动，不参与翻月动画。
class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final narrow = MaterialLocalizations.of(context).narrowWeekdays;
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Center(
              child: Text(
                narrow[i],
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
