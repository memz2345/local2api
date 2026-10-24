// lib/ui/miuix/miuix_today_fab.dart
//
// 日历页「回今天」按钮（miuix 版）。判据与文案规则在
// `lib/ui/widgets/today_fab.dart`，这里只换 `MiuixFloatingActionButton`。

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/l10n/app_localizations.dart';

import '../widgets/today_fab.dart'
    show kTodayFabIcon, kTodayFabTextSize, todayFabShowsText;

class MiuixTodayFab extends StatelessWidget {
  const MiuixTodayFab({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final showText = todayFabShowsText(context);
    return Semantics(
      label: l10n.usageCalendarBackToday,
      child: MiuixFloatingActionButton(
        onPressed: onPressed,
        child: showText
            ? const MiuixText(
                '今',
                fontSize: kTodayFabTextSize,
                fontWeight: FontWeight.w700,
              )
            : const Icon(kTodayFabIcon, size: 24),
      ),
    );
  }
}
