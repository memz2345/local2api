import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_bottom_sheet.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:provider/provider.dart';

/// 外观快速面板（miuix 版，对应 Material 版 `showThemeQuickSheet`）。
///
/// 仍然只有「主题模式 + 纯黑 + 动态取色」这三项快捷入口，
/// 写的也是同一个 SettingsService，与显示设置页天然同步。
/// 抽屉外壳沿用 Material 的 showModalBottomSheet（本项目 miuix 壳是
/// Material Scaffold），底色与圆角取 miuix 值；分段选择换成 MiuixTabRow。
Future<void> showMiuixThemeQuickSheet(BuildContext context) {
  return showMiuixBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _MiuixThemeQuickPanel(),
  );
}

class _MiuixThemeQuickPanel extends StatelessWidget {
  const _MiuixThemeQuickPanel();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final settings = context.watch<SettingsService>();
    final modeIndex = ThemeMode.values.indexOf(settings.themeMode);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: MiuixText(
                l10n.appearancePanelTitle,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
              child: MiuixText(
                l10n.displayThemeMode,
                fontSize: 13,
                color: colors.onSurfaceVariantSummary,
              ),
            ),
            MiuixTabRow(
              tabs: [l10n.themeSystem, l10n.themeLight, l10n.themeDark],
              selectedTabIndex: modeIndex < 0 ? 0 : modeIndex,
              onTabSelected: (i) => settings.setThemeMode(ThemeMode.values[i]),
            ),
            const SizedBox(height: 14),
            MiuixGroupCard(
              insideMargin: EdgeInsets.zero,
              child: Column(
                children: [
                  MiuixSwitchPreference(
                    title: l10n.displayPureBlack,
                    summary: settings.isPureBlackMode
                        ? l10n.displayPureBlackOn
                        : l10n.displayOff,
                    startAction: const Icon(Icons.brightness_2_outlined),
                    value: settings.isPureBlackMode,
                    onChanged: settings.setIsPureBlackMode,
                  ),
                  const MiuixHorizontalDivider(),
                  MiuixSwitchPreference(
                    title: l10n.displayThemeColor,
                    summary: l10n.displayFollowSystemColor,
                    startAction: const Icon(Icons.palette_outlined),
                    value: settings.useDynamicColor,
                    onChanged: settings.setUseDynamicColor,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
