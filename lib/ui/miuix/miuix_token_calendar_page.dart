import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_info_card.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/usage_stats.dart';
import 'package:local2api/ui/token_stats_page.dart'
    show formatHitRate, formatTokens;
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/widgets/miuix/miuix_bottom_sheet.dart';
import 'package:local2api/widgets/month_slide_switcher.dart';

import 'miuix_today_fab.dart';

/// 用量日历（miuix 版，对应 Material 版 `TokenCalendarPage`）。
///
/// 一样的账本、一样的交互：月历打点看哪天用得多，点日期弹当天活动，
/// 点模型卡片带着「那天 + 那个模型」回统计页。这里只换渲染。
class MiuixTokenCalendarPage extends StatefulWidget {
  const MiuixTokenCalendarPage({super.key, this.initialDay});

  /// 进来就选中的那天，默认今天。
  final DateTime? initialDay;

  @override
  State<MiuixTokenCalendarPage> createState() => _MiuixTokenCalendarPageState();
}

class _MiuixTokenCalendarPageState extends State<MiuixTokenCalendarPage> {
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();

  late DateTime _month;
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
    _behavior.state.dispose();
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
      if (day.month != _month.month || day.year != _month.year) {
        _monthShift = 0;
        _month = DateTime(day.year, day.month);
      }
    });
  }

  /// 点日期：选中 + 从底部弹出那天的活动。
  Future<void> _pickDay(DateTime day) async {
    _select(day);
    final focus = await showMiuixBottomSheet<TokenStatsFocus?>(
      context: context,
      builder: (ctx) => SafeArea(
        top: false,
        child: _MiuixDayActivities(
          day: day,
          scrollable: true,
          onPickModel: (model) =>
              Navigator.of(ctx).pop(TokenStatsFocus(day: day, model: model)),
        ),
      ),
    );
    if (!mounted || focus == null) return;
    Navigator.of(context).pop(focus);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;

    final monthMap = usageStats.monthMap(_month);
    final dayRecords = usageStats.ofDay(_selected);
    final dayModels = usageStats.modelsOfDay(_selected);
    // 横屏：左日历 + 右侧当天模型调用，双栏；竖屏维持单列。
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return Material(
      type: MaterialType.transparency,
      child: MiuixScaffold(
        containerColor: colors.surface,
        // 不看当月时给一颗「回今天」：翻得越远越需要一键回来。
        floatingActionButton: UsageStats.isCurrentMonth(_month)
            ? null
            : MiuixTodayFab(onPressed: _goToday),
        topBar: MiuixBlurTopBar(
          scrollBehavior: _behavior,
          title: l10n.usageCalendar,
          navigationIcon: MiuixIconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const MiuixAppIcon(
              AppIconNames.back,
              fallback: Icons.arrow_back,
            ),
          ),
        ),
        // 内容铺满整页、顶栏画在其上；顶栏高度垫进 padding，从栏下穿过。
        content: (padding) => MiuixScrollBehaviorListener(
          behavior: _behavior,
          child: isLandscape
              ? _landscapeBody(
                  colors: colors,
                  topInset: padding.top,
                  monthMap: monthMap,
                  dayRecords: dayRecords,
                  dayModels: dayModels,
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  padding: EdgeInsets.fromLTRB(16, padding.top + 4, 16, 40),
                  children: [
                    MiuixDismissibleInfoCard(
                      id: 'intro.usageCalendar',
                      text: l10n.usageCalendarIntro,
                    ),
                    const SizedBox(height: 12),
                    _MiuixMonthHeader(
                      month: _month,
                      onPrev: () => _shiftMonth(-1),
                      onNext: () => _shiftMonth(1),
                      onToday: () =>
                          _select(UsageStats.startOfDay(DateTime.now())),
                    ),
                    const SizedBox(height: 10),
                    // 星期表头固定不动，只有下面的格子翻页。
                    const _MiuixWeekdayHeader(),
                    const SizedBox(height: 6),
                    // 左右滑动切月：只包网格，别吃掉下面活动列表的滚动。
                    MonthSwipeArea(
                      onShift: _shiftMonth,
                      child: MonthSlideSwitcher(
                        direction: _monthShift,
                        child: KeyedSubtree(
                          key: ValueKey<DateTime>(_month),
                          child: _MiuixMonthGrid(
                            month: _month,
                            selected: _selected,
                            monthMap: monthMap,
                            onPick: _pickDay,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    MiuixSmallTitle(
                      l10n.usageCalendarDayModels(
                        _dayLabel(context, _selected),
                      ),
                      insideMargin: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 8),
                    _MiuixDayActivities(
                      day: _selected,
                      scrollable: false,
                      emptyRecords: dayRecords.isEmpty,
                      models: dayModels,
                      onPickModel: (m) => Navigator.of(
                        context,
                      ).pop(TokenStatsFocus(day: _selected, model: m)),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// 横屏双栏：左侧月历（限宽居中，别把格子撑成大方块），右侧当天模型调用。
  /// 点日期只选中（右栏跟着换），点模型卡片才带着焦点回统计页。
  Widget _landscapeBody({
    required MiuixColors colors,
    required double topInset,
    required Map<DateTime, UsageSummary> monthMap,
    required List<TokenUsage> dayRecords,
    required List<UsageModelDay> dayModels,
  }) {
    final l10n = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 6,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(16, topInset + 4, 16, 24),
                children: [
                  MiuixDismissibleInfoCard(
                    id: 'intro.usageCalendar',
                    text: l10n.usageCalendarIntro,
                  ),
                  const SizedBox(height: 12),
                  _MiuixMonthHeader(
                    month: _month,
                    onPrev: () => _shiftMonth(-1),
                    onNext: () => _shiftMonth(1),
                    onToday: _goToday,
                  ),
                  const SizedBox(height: 10),
                  // 星期表头固定不动，只有下面的格子翻页。
                  const _MiuixWeekdayHeader(),
                  const SizedBox(height: 6),
                  MonthSwipeArea(
                    onShift: _shiftMonth,
                    child: MonthSlideSwitcher(
                      direction: _monthShift,
                      child: KeyedSubtree(
                        key: ValueKey<DateTime>(_month),
                        child: _MiuixMonthGrid(
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
        Container(width: 1, color: colors.surfaceContainerHigh),
        Expanded(
          flex: 5,
          // 顶栏画在内容之上，右栏自己把顶栏高度垫进去（同左侧列表）。
          child: Padding(
            padding: EdgeInsets.only(top: topInset),
            child: _MiuixDayActivities(
              day: _selected,
              scrollable: true,
              emptyRecords: dayRecords.isEmpty,
              models: dayModels,
              onPickModel: (m) => Navigator.of(
                context,
              ).pop(TokenStatsFocus(day: _selected, model: m)),
            ),
          ),
        ),
      ],
    );
  }
}

String _dayLabel(BuildContext context, DateTime day) =>
    MaterialLocalizations.of(context).formatMediumDate(day);

/// 月份切换行：‹ 年月 › + 回今天。
class _MiuixMonthHeader extends StatelessWidget {
  const _MiuixMonthHeader({
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
    final label = MaterialLocalizations.of(context).formatMonthYear(month);

    return Row(
      children: [
        MiuixIconButton(
          onPressed: onPrev,
          child: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: MiuixText(
            label,
            textAlign: TextAlign.center,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        MiuixIconButton(
          onPressed: onNext,
          child: const Icon(Icons.chevron_right),
        ),
        MiuixTextButton(l10n.usageRangeToday, onPressed: onToday),
      ],
    );
  }
}

/// 月历网格：周一起头，格子亮度按当天 token 量给。
class _MiuixMonthGrid extends StatelessWidget {
  const _MiuixMonthGrid({
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
    final today = UsageStats.startOfDay(DateTime.now());

    // 周日开头（narrowWeekdays 本身就是 日-六 顺序）：
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
            return _MiuixDayCell(
              day: day,
              total: summary?.total ?? 0,
              ratio: summary == null ? 0 : summary.total / maxTotal,
              selected:
                  day.year == selected.year &&
                  day.month == selected.month &&
                  day.day == selected.day,
              isToday:
                  day.year == today.year &&
                  day.month == today.month &&
                  day.day == today.day,
              onTap: () => onPick(day),
            );
          }(),
      ],
    );
  }
}

class _MiuixDayCell extends StatelessWidget {
  const _MiuixDayCell({
    required this.day,
    required this.total,
    required this.ratio,
    required this.selected,
    required this.isToday,
    required this.onTap,
  });

  final DateTime day;
  final int total;
  final double ratio;
  final bool selected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final has = total > 0;

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: has
                ? colors.primary.withValues(
                    alpha: 0.14 + 0.46 * ratio.clamp(0.0, 1.0),
                  )
                : colors.surfaceContainerHigh.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
            border: selected
                ? Border.all(color: colors.primary, width: 2)
                : isToday
                ? Border.all(color: colors.primary.withValues(alpha: 0.45))
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MiuixText(
                '${day.day}',
                fontSize: 14,
                fontWeight: selected || isToday ? FontWeight.w800 : null,
                color: isToday
                    ? colors.primary
                    : (has ? colors.onSurface : colors.onSurfaceVariantSummary),
              ),
              if (has) ...[
                const SizedBox(height: 1),
                MiuixText(
                  formatTokens(total),
                  fontSize: 9,
                  color: colors.onSurfaceVariantSummary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 某天的活动：一个模型一张卡片（内联与底部弹窗共用）。
class _MiuixDayActivities extends StatelessWidget {
  const _MiuixDayActivities({
    required this.day,
    required this.onPickModel,
    this.scrollable = false,
    this.models,
    this.emptyRecords,
  });

  final DateTime day;
  final ValueChanged<String> onPickModel;
  final bool scrollable;
  final List<UsageModelDay>? models;
  final bool? emptyRecords;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final list = models ?? usageStats.modelsOfDay(day);

    if (list.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(
          vertical: scrollable ? 28 : 16,
          horizontal: 16,
        ),
        child: Center(
          child: MiuixText(
            (emptyRecords ?? true)
                ? l10n.usageCalendarEmptyDay
                : l10n.usageNoUsageData,
            fontSize: 14,
            textAlign: TextAlign.center,
            color: colors.onSurfaceVariantSummary,
          ),
        ),
      );
    }

    final cards = <Widget>[
      for (final m in list)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _MiuixModelActivityCard(
            item: m,
            onTap: () => onPickModel(m.model),
          ),
        ),
    ];

    if (!scrollable) return Column(children: cards);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
            child: MiuixText(
              l10n.usageCalendarDayModels(_dayLabel(context, day)),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          ...cards,
        ],
      ),
    );
  }
}

/// 一张模型卡片：模型名 + 请求数 + 输入/输出/命中 + 命中率。
class _MiuixModelActivityCard extends StatelessWidget {
  const _MiuixModelActivityCard({required this.item, required this.onTap});

  final UsageModelDay item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final s = item.summary;

    return MiuixGroupCard(
      insideMargin: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      feedbackType: MiuixPressFeedbackType.sink,
      onPressed: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.smart_toy_outlined, size: 16, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: MiuixText(
                  item.model,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              MiuixText(
                '${s.requests} ${l10n.usageRequests}',
                fontSize: 11,
                color: colors.onSurfaceVariantSummary,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: MiuixText(
                  '${l10n.usageInput} ${formatTokens(s.input)}'
                  ' · ${l10n.usageOutput} ${formatTokens(s.output)}',
                  fontSize: 12,
                  color: colors.onSurfaceVariantSummary,
                ),
              ),
              if (s.cacheHit > 0)
                MiuixText(
                  '⚡${formatTokens(s.cacheHit)} ${formatHitRate(s.hitRate)}',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF2BA471),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 星期表头（日-六）：固定不动，不参与翻月动画。
class _MiuixWeekdayHeader extends StatelessWidget {
  const _MiuixWeekdayHeader();

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final narrow = MaterialLocalizations.of(context).narrowWeekdays;
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Center(
              child: MiuixText(
                narrow[i],
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariantSummary,
              ),
            ),
          ),
      ],
    );
  }
}
