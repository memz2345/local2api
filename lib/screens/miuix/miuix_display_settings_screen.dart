import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';
import 'package:local2api/widgets/miuix/miuix_bottom_sheet.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/src/enums.dart';
import 'package:local2api/services/device_corner_service.dart';
import 'package:local2api/services/display_mode_service.dart';
import 'package:provider/provider.dart';

import 'miuix_display_scale_page.dart';
import 'miuix_display_mode_screen.dart';
import 'miuix_font_weight_screen.dart';
import 'miuix_theme_selector_screen.dart';

/// miuix 风格的显示设置页（对应 Material 版 `DisplaySettingsScreen`）。
///
/// 它是「主题 / 文字粗细 / 显示缩放」三个子页的入口，跳转一律走 miuix 版子页。
/// 主题模式、纯黑、种子色名称等展示逻辑与 Material 版一致（共用 SettingsService），
/// 只换渲染：折叠大标题顶栏换成 MiuixSmallTopAppBar（与 miuix 子页壳一致），
/// 各行用 MiuixArrowPreference / MiuixSwitchPreference，分组用 MiuixCard。
class MiuixDisplaySettingsScreen extends StatefulWidget {
  final bool isSplitView;
  final VoidCallback? onBack;

  const MiuixDisplaySettingsScreen({
    super.key,
    this.isSplitView = false,
    this.onBack,
  });

  @override
  State<MiuixDisplaySettingsScreen> createState() =>
      _MiuixDisplaySettingsScreenState();
}

class _MiuixDisplaySettingsScreenState
    extends State<MiuixDisplaySettingsScreen> {
  /// 二级页统一的可折叠大标题行为；`MiuixBlurTopBar` 读它，
  /// `MiuixScrollBehaviorListener` 在外层把滚动通知喂给它。
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();

  @override
  void dispose() {
    _behavior.state.dispose();
    super.dispose();
  }

  void _handleBack() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _navigateTo(String route) {
    Widget page;
    switch (route) {
      case '/display-scale':
        page = const MiuixDisplayScalePage();
        break;
      case '/display-mode':
        page = const MiuixDisplayModeScreen();
        break;
      case '/font-weight':
        page = const MiuixFontWeightScreen();
        break;
      case '/theme':
        page = MiuixThemeSelectorScreen(isSplitView: widget.isSplitView);
        break;
      default:
        return;
    }
    HapticFeedback.lightImpact();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  String _getThemeModeText(ThemeMode mode) {
    final l10n = AppLocalizations.of(context);
    switch (mode) {
      case ThemeMode.light:
        return l10n.displayThemeLight;
      case ThemeMode.dark:
        return l10n.displayThemeDark;
      case ThemeMode.system:
        return l10n.drawerSystemMode;
    }
  }

  IconData _getThemeModeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode_outlined;
      case ThemeMode.dark:
        return Icons.dark_mode_outlined;
      case ThemeMode.system:
        return Icons.brightness_auto_outlined;
    }
  }

  Future<void> _showThemeModePicker(
    BuildContext context,
    SettingsService service,
  ) async {
    await showMiuixBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in ThemeMode.values)
              MiuixRadioButtonPreference(
                title: _getThemeModeText(mode),
                selected: service.themeMode == mode,
                radioButtonLocation: MiuixRadioButtonLocation.end,
                startAction: Icon(_getThemeModeIcon(mode)),
                onClick: () {
                  service.setThemeMode(mode);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Windows 专属：「关闭按钮行为」三选一。
  ///
  /// 选了某一档之后，点标题栏 X 就直接按它执行；想回到「每次问」来这里改。
  Future<void> _showWindowClosePicker(
    BuildContext context,
    SettingsService service,
  ) async {
    await showMiuixBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final behavior in WindowCloseBehavior.values)
              MiuixRadioButtonPreference(
                title: _getWindowCloseText(behavior),
                summary: _getWindowCloseSummary(behavior),
                selected: service.windowCloseBehavior == behavior,
                radioButtonLocation: MiuixRadioButtonLocation.end,
                onClick: () {
                  service.setWindowCloseBehavior(behavior);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  String _getWindowCloseText(WindowCloseBehavior behavior) {
    final l10n = AppLocalizations.of(context);
    return switch (behavior) {
      WindowCloseBehavior.ask => l10n.winCloseAsk,
      WindowCloseBehavior.minimizeToTray => l10n.winCloseTray,
      WindowCloseBehavior.exit => l10n.winCloseExit,
    };
  }

  String _getWindowCloseSummary(WindowCloseBehavior behavior) {
    final l10n = AppLocalizations.of(context);
    return switch (behavior) {
      WindowCloseBehavior.ask => l10n.winCloseAskSummary,
      WindowCloseBehavior.minimizeToTray => l10n.winCloseTraySummary,
      WindowCloseBehavior.exit => l10n.winCloseExitSummary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final settingsService = context.watch<SettingsService>();
    final isPureBlackVisible = settingsService.themeMode != ThemeMode.light;

    final seedScheme = ColorScheme.fromSeed(
      seedColor: settingsService.themeSeedColor,
    );

    return PopScope(
      canPop: widget.onBack == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Material(
        type: MaterialType.transparency,
        child: MiuixScaffold(
          containerColor: colors.surface,
          topBar: MiuixBlurTopBar(
            scrollBehavior: _behavior,
            title: l10n.displaySettingsTitle,
            navigationIcon: widget.isSplitView
                ? null
                : MiuixIconButton(
                    onPressed: _handleBack,
                    child: const MiuixAppIcon(
                      AppIconNames.back,
                      fallback: Icons.arrow_back,
                    ),
                  ),
          ),
          // 内容铺满整页、顶栏画在其上；顶栏高度垫进 padding，从栏下穿过。
          content: (padding) => MiuixScrollBehaviorListener(
            behavior: _behavior,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(16, padding.top + 8, 16, 48),
              children: [
                MiuixSmallTitle(l10n.displaySectionAppearance),
                MiuixGroupCard(
                  child: Column(
                    children: [
                      MiuixArrowPreference(
                        title: l10n.displayThemeMode,
                        summary: _getThemeModeText(settingsService.themeMode),
                        startAction: Icon(
                          _getThemeModeIcon(settingsService.themeMode),
                        ),
                        onClick: () =>
                            _showThemeModePicker(context, settingsService),
                      ),
                      _AnimatedCollapse(
                        visible: isPureBlackVisible,
                        child: MiuixSwitchPreference(
                          title: l10n.displayPureBlack,
                          summary: settingsService.isPureBlackMode
                              ? l10n.displayPureBlackOn
                              : l10n.displayOff,
                          startAction: const Icon(Icons.brightness_2_outlined),
                          value: settingsService.isPureBlackMode,
                          onChanged: (value) =>
                              settingsService.setIsPureBlackMode(value),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                MiuixSmallTitle(l10n.displaySectionPersonalize),
                MiuixGroupCard(
                  child: Column(
                    children: [
                      MiuixArrowPreference(
                        title: l10n.displayThemeColor,
                        summary: settingsService.useDynamicColor
                            ? l10n.displayFollowSystemColor
                            : _getSeedColorName(settingsService.themeSeedColor),
                        startAction: const Icon(Icons.palette_outlined),
                        endActions: [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: ClipOval(
                              child: CustomPaint(
                                size: const Size(22, 22),
                                painter: _FourColorPainter(
                                  topLeft: seedScheme.primaryContainer,
                                  topRight: seedScheme.secondaryContainer,
                                  bottomLeft: seedScheme.primary,
                                  bottomRight: seedScheme.secondary,
                                ),
                              ),
                            ),
                          ),
                        ],
                        onClick: () => _navigateTo('/theme'),
                      ),
                      MiuixArrowPreference(
                        title: l10n.displayFontWeight,
                        summary: _getFontWeightLabel(
                          settingsService.fontWeight,
                        ),
                        startAction: const Icon(Icons.format_bold_outlined),
                        endActions: [
                          Text(
                            'A',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: _toFontWeight(
                                settingsService.fontWeight,
                              ),
                              color: colors.onSurfaceSecondary,
                            ),
                          ),
                        ],
                        onClick: () => _navigateTo('/font-weight'),
                      ),
                      MiuixArrowPreference(
                        title: l10n.displayScaleTitle,
                        summary: _getScaleDescription(
                          settingsService.displayScale,
                        ),
                        startAction: const Icon(Icons.zoom_in_outlined),
                        endActions: [
                          Text(
                            '${(settingsService.displayScale * 100).round()}%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.primary,
                            ),
                          ),
                        ],
                        onClick: () => _navigateTo('/display-scale'),
                      ),
                      // ── 屏幕帧率（仅 Android；NaviFlash 同款）──
                      if (Platform.isAndroid)
                        MiuixArrowPreference(
                          title: l10n.displayModeTitle,
                          summary: DisplayModeService.labelOf(
                            settingsService.displayMode,
                            autoText: l10n.displayModeAuto,
                          ),
                          startAction: const Icon(Icons.speed_outlined),
                          onClick: () => _navigateTo('/display-mode'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // ── 页面推入转场的圆角 ──
                // 只调圆角；转场速率 / 压暗 / 曲线都固定在
                // IosPushPageTransitionsBuilder 的默认值上。
                MiuixSmallTitle(l10n.displayIosPushTransitionCorner),
                MiuixGroupCard(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
                        child: Row(
                          children: [
                            Icon(
                              Icons.rounded_corner_outlined,
                              size: 22,
                              color: colors.onSurfaceSecondary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: MiuixSlider(
                                value: settingsService
                                    .iosPushTransitionCornerRadius
                                    .clamp(0.0, 48.0),
                                min: 0,
                                max: 48,
                                steps: 48,
                                // 「自动生效中」时置灰：设备值说了算。自动开着
                                // 但读不到设备值（桌面 / 老系统）时，滑块就是
                                // 生效值，必须保持可拖。
                                onValueChanged:
                                    settingsService
                                            .iosPushTransitionCornerAuto &&
                                        DeviceCornerService.hasDeviceValue
                                    ? null
                                    : (v) => settingsService
                                          .setIosPushTransitionCornerRadius(v),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 44,
                              child: MiuixText(
                                '${DeviceCornerService.resolveFor(settingsService).round()}',
                                textAlign: TextAlign.right,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: colors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      MiuixSwitchPreference(
                        title: l10n.displayIosPushTransitionCornerAuto,
                        summary:
                            settingsService.iosPushTransitionCornerAuto &&
                                !DeviceCornerService.hasDeviceValue
                            ? l10n.displayIosPushTransitionCornerUnsupported
                            : null,
                        startAction: const Icon(Icons.phone_android_outlined),
                        value: settingsService.iosPushTransitionCornerAuto,
                        onChanged: (value) => settingsService
                            .setIosPushTransitionCornerAuto(value),
                      ),
                    ],
                  ),
                ),
                // ── 桌面窗口（仅 Windows）──
                if (Platform.isWindows) ...[
                  const SizedBox(height: 24),
                  MiuixSmallTitle(l10n.winCloseSection),
                  MiuixGroupCard(
                    child: Column(
                      children: [
                        MiuixArrowPreference(
                          title: l10n.winCloseBehaviorTitle,
                          summary: switch (settingsService
                              .windowCloseBehavior) {
                            WindowCloseBehavior.ask => l10n.winCloseAsk,
                            WindowCloseBehavior.minimizeToTray =>
                              l10n.winCloseTray,
                            WindowCloseBehavior.exit => l10n.winCloseExit,
                          },
                          startAction: const Icon(
                            Icons.desktop_windows_outlined,
                          ),
                          onClick: () => _showWindowClosePicker(
                            context,
                            settingsService,
                          ),
                        ),
                        const Divider(height: 1),
                        MiuixSwitchPreference(
                          title: l10n.winTrayHintTitle,
                          summary: l10n.winTrayHintSummary,
                          startAction: const Icon(
                            Icons.notifications_active_outlined,
                          ),
                          value: settingsService.trayHintEnabled,
                          onChanged: settingsService.setTrayHintEnabled,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getSeedColorName(Color color) {
    final l10n = AppLocalizations.of(context);
    final presets = {
      0xFF386A20: l10n.displaySeedDefaultGreen,
      Colors.pink.toARGB32(): l10n.displaySeedPink,
      Colors.red.toARGB32(): l10n.displaySeedRed,
      Colors.orange.toARGB32(): l10n.displaySeedOrange,
      Colors.amber.toARGB32(): l10n.displaySeedAmber,
      Colors.yellow.toARGB32(): l10n.displaySeedYellow,
      Colors.lime.toARGB32(): l10n.displaySeedLime,
      Colors.lightGreen.toARGB32(): l10n.displaySeedLightGreen,
      Colors.green.toARGB32(): l10n.displaySeedGreen,
      Colors.cyan.toARGB32(): l10n.displaySeedCyan,
      Colors.teal.toARGB32(): l10n.displaySeedTeal,
      Colors.lightBlue.toARGB32(): l10n.displaySeedLightBlue,
      Colors.blue.toARGB32(): l10n.displaySeedBlue,
      Colors.indigo.toARGB32(): l10n.displaySeedIndigo,
      Colors.purple.toARGB32(): l10n.displaySeedPurple,
      Colors.deepPurple.toARGB32(): l10n.displaySeedDeepPurple,
      Colors.blueGrey.toARGB32(): l10n.displaySeedBlueGrey,
      Colors.brown.toARGB32(): l10n.displaySeedBrown,
      Colors.grey.toARGB32(): l10n.displaySeedGrey,
    };
    return presets[color.toARGB32()] ?? l10n.displaySeedCustom;
  }

  String _getFontWeightLabel(double weight) {
    final l10n = AppLocalizations.of(context);
    if (weight <= 100) return l10n.displayWeightThin(100);
    if (weight <= 300) return l10n.displayWeightLight(300);
    if (weight <= 400) return l10n.displayWeightRegular(400);
    if (weight <= 500) return l10n.displayWeightMedium(500);
    if (weight <= 700) return l10n.displayWeightBold(700);
    if (weight <= 900) return l10n.displayWeightBlack(900);
    return l10n.displayWeightCustom(weight.toInt());
  }

  FontWeight _toFontWeight(double v) {
    if (v <= 100) return FontWeight.w100;
    if (v <= 200) return FontWeight.w200;
    if (v <= 300) return FontWeight.w300;
    if (v <= 400) return FontWeight.w400;
    if (v <= 500) return FontWeight.w500;
    if (v <= 600) return FontWeight.w600;
    if (v <= 700) return FontWeight.w700;
    if (v <= 800) return FontWeight.w800;
    return FontWeight.w900;
  }

  String _getScaleDescription(double scale) {
    final l10n = AppLocalizations.of(context);
    if (scale < 0.75) return l10n.displayScaleCompact;
    if (scale < 1.0) return l10n.displayScaleSmall;
    if (scale == 1.0) return l10n.displayScaleDefault;
    if (scale <= 1.25) return l10n.displayScaleLarge;
    if (scale <= 1.5) return l10n.displayScaleLargeFont;
    return l10n.displayScaleHuge;
  }
}

/// 四色圆盘画笔（本地复刻 Material 版 `FourColorPainter`，避免改动共享文件）。
class _FourColorPainter extends CustomPainter {
  final Color topLeft, topRight, bottomLeft, bottomRight;

  _FourColorPainter({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final paint = Paint();

    paint.color = topLeft;
    canvas.drawRect(Rect.fromLTWH(0, 0, w / 2, h / 2), paint);

    paint.color = topRight;
    canvas.drawRect(Rect.fromLTWH(w / 2, 0, w / 2, h / 2), paint);

    paint.color = bottomLeft;
    canvas.drawRect(Rect.fromLTWH(0, h / 2, w / 2, h / 2), paint);

    paint.color = bottomRight;
    canvas.drawRect(Rect.fromLTWH(w / 2, h / 2, w / 2, h / 2), paint);
  }

  @override
  bool shouldRepaint(covariant _FourColorPainter oldDelegate) {
    return oldDelegate.topLeft != topLeft ||
        oldDelegate.topRight != topRight ||
        oldDelegate.bottomLeft != bottomLeft ||
        oldDelegate.bottomRight != bottomRight;
  }
}

/// 展开/收起动画（本地复刻 Material 版同名私有助手，避免改动共享文件）。
///
/// 与 Material 原版有一处刻意差异：原版用 `AnimatedContainer(maxHeight: 0)`
/// 收起，会把子节点强行压到 0 高从而触发 RenderFlex overflow（原版靠 ClipRect
/// 遮住、生产里不可见但仍是布局报错）。这里改用 `ClipRect + Align(heightFactor)`：
/// 子节点始终按自然高度布局再被裁剪，收起时不会溢出。视觉上的收拢/淡出保持一致。
class _AnimatedCollapse extends StatelessWidget {
  final bool visible;
  final Widget child;

  const _AnimatedCollapse({required this.visible, required this.child});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: visible ? 1.0 : 0.0),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        builder: (context, value, cached) => ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: value,
            child: FractionalTranslation(
              translation: Offset(0, (value - 1) * 0.2),
              child: Opacity(opacity: value, child: cached),
            ),
          ),
        ),
        child: child,
      ),
    );
  }
}
