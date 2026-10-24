// lib/widgets/custom_tabs_picker.dart
//
// 「用哪个浏览器（Custom Tabs）打开」的选择面板 + 打开动作。
//
// 参考 TiebaLite / InstallerX 的做法：装了多个 Chromium 系浏览器时，弹一次
// 单选（记住上次的选择做预选），只装一个就直接开。两套皮与其它弹层一致：
// Material 3 走 `showAppBottomSheet` + `RadioGroup`，miuix 走
// `showMiuixBottomSheet` + `MiuixGroupCard`。

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../services/custom_tabs_service.dart';
import '../services/settings_service.dart';
import 'miuix/miuix_bottom_sheet.dart';
import 'miuix/miuix_group_card.dart';
import 'predictive_back_sheet.dart';

/// 弹出浏览器选择面板。返回值：包名；null = 用户取消。
///
/// 不提供「自动（系统默认）」选项：`CustomTabsClient` 的默认提供者要求
/// **系统默认浏览器**支持 CT，很多机器默认浏览器是裸 WebView 壳，那个选项
/// 会退化成普通 ACTION_VIEW。这里始终显式指定包名。
Future<String?> showCustomTabsBrowserPicker(
  BuildContext context, {
  required List<CustomTabsBrowser> browsers,
  required String selectedPackage,
  required bool useMiuix,
  required String title,
}) {
  final options = browsers.map((b) => b.packageName).toList(growable: false);
  String labelOf(String pkg) {
    for (final b in browsers) {
      if (b.packageName == pkg) return b.label;
    }
    return pkg;
  }

  if (useMiuix) {
    return showMiuixBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                child: MiuixText(
                  title,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: MiuixTheme.of(context).colors.onSurface,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              MiuixGroupCard(
                insideMargin: EdgeInsets.zero,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < options.length; i++) ...[
                      if (i > 0)
                        const Padding(
                          padding: EdgeInsets.only(left: 16),
                          child: MiuixHorizontalDivider(),
                        ),
                      MiuixRadioButtonPreference(
                        title: labelOf(options[i]),
                        selected: options[i] == selectedPackage,
                        insideMargin: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                        onClick: () =>
                            Navigator.of(sheetContext).pop(options[i]),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  return showAppBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            RadioGroup<String>(
              groupValue: selectedPackage,
              onChanged: (value) {
                if (value != null) Navigator.of(sheetContext).pop(value);
              },
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  for (final pkg in options)
                    ListTile(
                      onTap: () => Navigator.of(sheetContext).pop(pkg),
                      leading: IgnorePointer(child: Radio<String>(value: pkg)),
                      title: Text(
                        labelOf(pkg),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// 用 Custom Tabs 打开 [url]。
///
/// [ask]：装了多家浏览器时是否弹选择面板。
///   · 内置浏览器的菜单里点「用 Custom Tabs 打开」= true（明确要挑一家）；
///   · 实验室 / WebUI 的「打开」按钮 = false（沿用上次的选择，静默挑一家）。
///
/// 返回 false = 没开成（没有 Custom Tabs 浏览器 / 原生调用失败），调用方
/// 应当回退到系统浏览器；true = 已处理（含用户在选浏览器时取消）。
Future<bool> openInCustomTabs(
  BuildContext context, {
  required String url,
  required bool useMiuix,
  bool ask = false,
  String? title,
}) async {
  if (url.isEmpty || !CustomTabsService.isSupported) return false;
  final browsers = await CustomTabsService.browsers();
  if (browsers.isEmpty) return false;
  if (!context.mounted) return false;

  final l10n = AppLocalizations.of(context);
  final settings = context.read<SettingsService>();
  final saved = settings.browserCustomTabPackage;
  final savedValid = browsers.any((b) => b.packageName == saved);
  // 兜底顺序：上次选过的那家 → 系统默认 CT 提供者 → 列表第一家
  final fallback = browsers
      .firstWhere((b) => b.isDefault, orElse: () => browsers.first)
      .packageName;

  String target;
  if (!ask || browsers.length == 1) {
    target = savedValid ? saved : fallback;
    if (target != saved) {
      await settings.setBrowserCustomTabPackage(target);
    }
  } else {
    final picked = await showCustomTabsBrowserPicker(
      context,
      browsers: browsers,
      selectedPackage: savedValid ? saved : fallback,
      useMiuix: useMiuix,
      title: title ?? l10n.browserCustomTabPick,
    );
    if (picked == null) return true;
    target = picked;
    await settings.setBrowserCustomTabPackage(picked);
  }
  if (!context.mounted) return false;
  final color = Theme.of(context).colorScheme.surface.toARGB32();
  return CustomTabsService.open(url, packageName: target, toolbarColor: color);
}

/// 「外部打开」的统一入口：优先 Custom Tabs，没装再回退系统浏览器。
///
/// 给实验室（SillyTavern / dsh web）和 WebUI 的「打开」按钮用 —— 这些页面
/// 重前端，塞给系统 WebView 壳体验差，交给 Chromium 系浏览器更稳。
Future<void> openExternalUrl(
  BuildContext context,
  String url, {
  required bool useMiuix,
}) async {
  if (url.isEmpty) return;
  final handled = await openInCustomTabs(context, url: url, useMiuix: useMiuix);
  if (handled) return;
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
}
