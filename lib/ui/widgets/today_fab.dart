// lib/ui/widgets/today_fab.dart
//
// 日历页右下角「回今天」的悬浮按钮。
//
// 两条共用规则（Material / miuix 各渲染一份，判据在这里）：
// 1. 只在**不看当月**时出现 —— 已经在当月，按钮没有意义；
// 2. 中文界面写「今」字，其余语言用日历图标（一个字比图标更像 miuix，
//    但别的语言写 "Today" 太宽，放不进圆按钮）。

import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';

/// 中文字形里就一个「今」最合适，其余语言走图标。
bool todayFabShowsText(BuildContext context) {
  final locale = Localizations.maybeLocaleOf(context);
  return (locale?.languageCode ?? AppLocalizations.of(context).localeName)
      .startsWith('zh');
}

/// 图标态用的字形。
const IconData kTodayFabIcon = Icons.today;

/// 「今」的字号：与 24dp 图标视觉等重。
const double kTodayFabTextSize = 20;

/// Material 版：FloatingActionButton（圆角方形，跟项目其余 FAB 同款）。
class TodayFab extends StatelessWidget {
  const TodayFab({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final showText = todayFabShowsText(context);
    return FloatingActionButton(
      tooltip: l10n.usageCalendarBackToday,
      onPressed: onPressed,
      child: showText
          ? const Text(
              '今',
              style: TextStyle(
                fontSize: kTodayFabTextSize,
                fontWeight: FontWeight.w700,
              ),
            )
          : const Icon(kTodayFabIcon),
    );
  }
}
