import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/widgets/predictive_back_sheet.dart';
import 'package:provider/provider.dart';

/// 设置页 FAB 用的外观快速面板：主题模式 + 纯黑 + 动态取色。
///
/// 只做「不滚到对应分区也能改这三项」的快捷入口，控件语义与显示设置页一致，
/// 都写 SettingsService，两边状态自然同步。
Future<void> showThemeQuickSheet(BuildContext context) {
  return showAppBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetCtx) => const _ThemeQuickPanel(),
  );
}

class _ThemeQuickPanel extends StatelessWidget {
  const _ThemeQuickPanel();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final settings = context.watch<SettingsService>();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.appearancePanelTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              l10n.displayThemeMode,
              style: theme.textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: const Icon(Icons.brightness_auto, size: 18),
                  label: Text(l10n.themeSystem),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: const Icon(Icons.light_mode_outlined, size: 18),
                  label: Text(l10n.themeLight),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: const Icon(Icons.dark_mode_outlined, size: 18),
                  label: Text(l10n.themeDark),
                ),
              ],
              selected: {settings.themeMode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => settings.setThemeMode(s.first),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.displayPureBlack),
              value: settings.isPureBlackMode,
              onChanged: settings.setIsPureBlackMode,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.displayThemeColor),
              subtitle: Text(
                l10n.displayFollowSystemColor,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              value: settings.useDynamicColor,
              onChanged: settings.setUseDynamicColor,
            ),
          ],
        ),
      ),
    );
  }
}
