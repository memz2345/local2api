import 'dart:io';

import 'package:flex_seed_scheme/flex_seed_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField;
import 'package:local2api/widgets/miuix/miuix_text_field.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_info_card.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';
import 'package:local2api/widgets/miuix/miuix_page_popup_host.dart';
import 'package:local2api/widgets/miuix/miuix_bottom_sheet.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/widgets/miuix/miuix_dialog.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/image_color_analyzer.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/src/theme_seed_ext.dart';
import 'package:local2api/widgets/color_palette.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';
import 'package:provider/provider.dart';

/// miuix 风格的主题选择页（对应 Material 版 `ThemeSelectorScreen`）。
///
/// 取色、预设/自定义色板、调色板变体与主题模式等业务逻辑全部共用
/// `SettingsService` 与 `analyzeImageColor`，这里只换渲染：
/// 顶栏 MiuixSmallTopAppBar，分组用 MiuixCard + 各类 Preference，
/// 自定义主题对话框里的取色器换成 MiuixColorPicker，提示走 showMiuixToast。
class MiuixThemeSelectorScreen extends StatefulWidget {
  final bool isSplitView;
  final Function(String routeName)? onNavigate;
  final VoidCallback? onBack;

  const MiuixThemeSelectorScreen({
    super.key,
    this.isSplitView = false,
    this.onNavigate,
    this.onBack,
  });

  @override
  State<MiuixThemeSelectorScreen> createState() =>
      _MiuixThemeSelectorScreenState();
}

class _MiuixThemeSelectorScreenState extends State<MiuixThemeSelectorScreen> {
  /// 二级页统一的可折叠大标题行为；`MiuixBlurTopBar` 读它，
  /// `MiuixScrollBehaviorListener` 在外层把滚动通知喂给它。
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();

  @override
  void dispose() {
    _behavior.state.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _presetColors {
    final l10n = AppLocalizations.of(context);
    return [
      {'name': l10n.colorDefaultGreen, 'color': const Color(0xFF386A20)},
      {'name': l10n.colorPink, 'color': Colors.pink},
      {'name': l10n.colorRed, 'color': Colors.red},
      {'name': l10n.colorOrange, 'color': Colors.orange},
      {'name': l10n.colorAmber, 'color': Colors.amber},
      {'name': l10n.colorYellow, 'color': Colors.yellow},
      {'name': l10n.colorLime, 'color': Colors.lime},
      {'name': l10n.colorLightGreen, 'color': Colors.lightGreen},
      {'name': l10n.colorGreen, 'color': Colors.green},
      {'name': l10n.colorCyan, 'color': Colors.cyan},
      {'name': l10n.colorTeal, 'color': Colors.teal},
      {'name': l10n.colorLightBlue, 'color': Colors.lightBlue},
      {'name': l10n.colorBlue, 'color': Colors.blue},
      {'name': l10n.colorIndigo, 'color': Colors.indigo},
      {'name': l10n.colorPurple, 'color': Colors.purple},
      {'name': l10n.colorDeepPurple, 'color': Colors.deepPurple},
      {'name': l10n.colorBlueGrey, 'color': Colors.blueGrey},
      {'name': l10n.colorBrown, 'color': Colors.brown},
      {'name': l10n.colorGrey, 'color': Colors.grey},
    ];
  }

  bool _isAnalyzing = false;
  bool _isDragging = false;

  void _handleBack() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    showMiuixToast(context, message, error: error);
  }

  Future<void> _pickColorFromImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked != null) {
      await _analyzeAndApplyColor(File(picked.path));
    }
  }

  Future<void> _analyzeAndApplyColor(File file) async {
    if (_isAnalyzing) return;
    if (!await file.exists()) return;
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _isAnalyzing = true);
    try {
      final bytes = await file.readAsBytes();
      final color = await analyzeImageColor(bytes);
      if (!mounted) return;
      final settingsService = context.read<SettingsService>();
      await settingsService.setThemeSeedColor(color);
      await settingsService.setUseDynamicColor(false);
      if (!mounted) return;
      _toast(l10n.themeColorExtracted);
    } catch (e) {
      if (mounted) _toast(l10n.themeColorFailed('$e'), error: true);
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  void _handleDrop(List<Object?> files) {
    final l10n = AppLocalizations.of(context);
    if (files.isEmpty) return;
    final path = files.first.toString().replaceAll('file://', '');
    final file = File(path);
    final ext = file.path.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext)) {
      _analyzeAndApplyColor(file);
    } else {
      _toast(l10n.themeImageOnly);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final settingsService = context.watch<SettingsService>();
    final useDynamicColor = settingsService.useDynamicColor;
    final isPureBlackVisible = settingsService.themeMode != ThemeMode.light;

    return PopScope(
      canPop: widget.onBack == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      // 弹层宿主罩在 Scaffold 外面：菜单按全局锚点定位，宿主必须整屏覆盖
      child: MiuixPagePopupHost(
        child: Material(
          type: MaterialType.transparency,
          child: MiuixScaffold(
            containerColor: colors.surface,
            topBar: MiuixBlurTopBar(
              scrollBehavior: _behavior,
              title: l10n.themeTitle,
              navigationIcon: MiuixIconButton(
                onPressed: _handleBack,
                child: const MiuixAppIcon(
                  AppIconNames.back,
                  fallback: Icons.arrow_back,
                ),
              ),
              actions: [
                MiuixIconButton(
                  onPressed: () => _showMoreSheet(settingsService),
                  child: const MiuixAppIcon(
                    AppIconNames.more,
                    fallback: Icons.more_vert,
                  ),
                ),
              ],
            ),
            floatingActionButton: Tooltip(
              message: l10n.themeNewTheme,
              child: MiuixFloatingActionButton(
                onPressed: () => _showCustomThemeDialog(context),
                child: const Icon(Icons.add),
              ),
            ),
            // 内容铺满整页、顶栏画在其上；顶栏高度垫进 padding，从栏下穿过。
            content: (padding) => MiuixScrollBehaviorListener(
              behavior: _behavior,
              child: Stack(
                children: [
                  DragTarget<List<String>>(
                    onWillAcceptWithDetails: (data) {
                      setState(() => _isDragging = true);
                      return true;
                    },
                    onLeave: (_) => setState(() => _isDragging = false),
                    onAcceptWithDetails: (details) {
                      setState(() => _isDragging = false);
                      _handleDrop(details.data);
                    },
                    builder: (context, candidateData, rejectedData) =>
                        _buildContent(
                          colors,
                          l10n,
                          settingsService,
                          useDynamicColor,
                          isPureBlackVisible,
                          topInset: padding.top,
                        ),
                  ),
                  if (_isDragging)
                    Container(
                      color: colors.primaryContainer.withValues(alpha: 0.85),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.image_search,
                              size: 64,
                              color: colors.onPrimaryContainer,
                            ),
                            const SizedBox(height: 16),
                            MiuixText(
                              l10n.themeDropHint,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: colors.onPrimaryContainer,
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_isAnalyzing)
                    Container(
                      color: Colors.black54,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    MiuixColors colors,
    AppLocalizations l10n,
    SettingsService settingsService,
    bool useDynamicColor,
    bool isPureBlackVisible, {
    double topInset = 0,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(16, topInset + 8, 16, 96),
      children: [
        // 自定义颜色关掉时：最上方提示「需要启用自定义颜色」。
        // 它是状态提示（开关一开就自己没了），不给 X。
        if (!settingsService.useCustomThemeColors) ...[
          MiuixInfoCard(text: l10n.themeCustomColorsNeeded),
          const SizedBox(height: 16),
        ],
        MiuixSmallTitle(l10n.themeAppearance),
        MiuixGroupCard(
          child: Column(
            children: [
              // 主题模式走 HyperOS 同款下拉菜单（行旁悬浮弹出、选中带对勾），
              // 不再落到底部抽屉 —— 对应 InstallerX 的 OverlayDropdownPreference。
              MiuixOverlayDropdownPreference(
                title: l10n.searchThemeMode,
                items: [
                  for (final mode in ThemeMode.values) _getThemeModeText(mode),
                ],
                selectedIndex: settingsService.themeMode.index,
                startAction: const Icon(Icons.flashlight_on_outlined),
                onSelectedIndexChange: (i) =>
                    settingsService.setThemeMode(ThemeMode.values[i]),
              ),
              _AnimatedCollapse(
                visible: isPureBlackVisible,
                child: MiuixSwitchPreference(
                  title: l10n.searchPureBlack,
                  summary: settingsService.isPureBlackMode
                      ? l10n.themeDarkBlackened
                      : l10n.themeOff,
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
        MiuixSmallTitle(l10n.themeColorsSection),
        MiuixGroupCard(
          child: Column(
            children: [
              // 自定义颜色关掉时「配色」区禁用变灰（顶部 info 提示去开它）。
              MiuixArrowPreference(
                title: l10n.themePaletteStyle,
                summary: settingsService.schemeVariant.variantName,
                startAction: const Icon(Icons.palette_outlined),
                enabled:
                    settingsService.useCustomThemeColors && !useDynamicColor,
                onClick:
                    settingsService.useCustomThemeColors && !useDynamicColor
                    ? () => _showSchemeVariantPicker(context, settingsService)
                    : null,
              ),
              MiuixSwitchPreference(
                title: l10n.themeFollowSystem,
                summary: useDynamicColor ? l10n.themeEnabled : l10n.themeOff,
                startAction: const Icon(Icons.wallpaper_outlined),
                value: useDynamicColor,
                enabled: settingsService.useCustomThemeColors,
                onChanged: (value) => settingsService.setUseDynamicColor(value),
              ),
            ],
          ),
        ),
        _AnimatedCollapse(
          visible: !useDynamicColor,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: MiuixGroupCard(
              insideMargin: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MiuixText(
                    l10n.themePickColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  const SizedBox(height: 16),
                  _buildColorGrid(settingsService, useDynamicColor),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildColorGrid(
    SettingsService settingsService,
    bool useDynamicColor,
  ) {
    final colors = MiuixTheme.of(context).colors;
    final currentSeed = settingsService.themeSeedColor;
    final customThemes = settingsService.customThemes;
    final variant = settingsService.schemeVariant;
    final brightness = Theme.of(context).brightness;

    final children = <Widget>[];

    for (var i = 0; i < customThemes.length; i++) {
      final theme = customThemes[i];
      final color = Color(theme['color'] as int);
      final name = theme['name'] as String;
      final isSelected =
          color.toARGB32() == currentSeed.toARGB32() && !useDynamicColor;
      children.add(
        _buildPaletteItem(
          colors: colors,
          variant: variant,
          brightness: brightness,
          color: color,
          name: name,
          isSelected: isSelected,
          onTap: () {
            settingsService.setThemeSeedColor(color);
            settingsService.setUseDynamicColor(false);
            _toast(AppLocalizations.of(context).themeSwitched(name));
          },
          onLongPress: () =>
              _showDeleteConfirmDialog(context, i, name, settingsService),
        ),
      );
    }

    for (final preset in _presetColors) {
      final color = preset['color'] as Color;
      final name = preset['name'] as String;
      final isSelected =
          color.toARGB32() == currentSeed.toARGB32() && !useDynamicColor;
      children.add(
        _buildPaletteItem(
          colors: colors,
          variant: variant,
          brightness: brightness,
          color: color,
          name: name,
          isSelected: isSelected,
          onTap: () {
            settingsService.setThemeSeedColor(color);
            settingsService.setUseDynamicColor(false);
            _toast(AppLocalizations.of(context).themeSwitched(name));
          },
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 22,
      runSpacing: 18,
      children: children,
    );
  }

  Widget _buildPaletteItem({
    required MiuixColors colors,
    required FlexSchemeVariant variant,
    required Brightness brightness,
    required Color color,
    required String name,
    required bool isSelected,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ColorPalette(
            colorScheme: color.asColorSchemeSeed(variant, brightness),
            selected: isSelected,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 64,
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isSelected
                    ? colors.primary
                    : colors.onSurfaceVariantSummary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 顶栏「更多」：复制色号 / 从图片取色。miuix 没有命令式菜单入口，用底部抽屉。
  Future<void> _showMoreSheet(SettingsService settingsService) async {
    final l10n = AppLocalizations.of(context);
    await showMiuixBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SheetAction(
                icon: Icons.content_copy,
                label: l10n.themeCopyColor,
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final color = settingsService.themeSeedColor;
                  final hex =
                      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
                  await Clipboard.setData(ClipboardData(text: hex));
                  _toast(l10n.themeColorCopied(hex));
                },
              ),
              _SheetAction(
                icon: Icons.image,
                label: l10n.themePickFromImage,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pickColorFromImage();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSchemeVariantPicker(
    BuildContext context,
    SettingsService service,
  ) async {
    final seed = service.themeSeedColor;
    final brightness = Theme.of(context).brightness;
    await showMiuixBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final variant in FlexSchemeVariant.values)
                MiuixRadioButtonPreference(
                  title: variant.variantName,
                  selected: service.schemeVariant == variant,
                  radioButtonLocation: MiuixRadioButtonLocation.end,
                  startAction: SizedBox(
                    width: 36,
                    height: 36,
                    child: ColorPalette(
                      colorScheme: seed.asColorSchemeSeed(variant, brightness),
                      selected: false,
                      showBgColor: false,
                    ),
                  ),
                  onClick: () {
                    service.setSchemeVariant(variant);
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _getThemeModeText(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return AppLocalizations.of(context).drawerLightMode;
      case ThemeMode.dark:
        return AppLocalizations.of(context).drawerDarkMode;
      case ThemeMode.system:
        return AppLocalizations.of(context).drawerSystemMode;
    }
  }

  void _showDeleteConfirmDialog(
    BuildContext context,
    int index,
    String name,
    SettingsService service,
  ) {
    final l10n = AppLocalizations.of(context);
    showMiuixDialog<void>(
      context: context,
      title: l10n.themeDeleteTitle,
      message: l10n.themeDeleteConfirm(name),
      actions: [
        MiuixDialogAction(
          label: l10n.commonCancel,
          onPressed: (ctx) => Navigator.of(ctx).pop(),
        ),
        MiuixDialogAction(
          label: l10n.commonDelete,
          destructive: true,
          onPressed: (ctx) {
            service.removeCustomTheme(index);
            Navigator.of(ctx).pop();
            _toast(l10n.themeDeleted(name));
          },
        ),
      ],
    );
  }

  void _showCustomThemeDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nameController = TextEditingController();
    final hexController = TextEditingController(text: '#0000FF');
    Color tempColor = Colors.blue;

    showMiuixDialog<void>(
      context: context,
      title: l10n.themeCreateTitle,
      // 表单与动作行进同一个 StatefulBuilder：创建按钮的可用性要跟着
      // 名称输入实时变化，所以动作行放在内容里而不是走 actions。
      content: StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          void updateColorFromText(String input) {
            try {
              Color newColor;
              if (input.startsWith('#')) {
                newColor = Color(
                  int.parse(input.substring(1), radix: 16) + 0xFF000000,
                );
              } else if (input.contains(',')) {
                final parts = input
                    .split(',')
                    .map((s) => int.parse(s.trim()))
                    .toList();
                newColor = Color.fromRGBO(parts[0], parts[1], parts[2], 1);
              } else {
                newColor = Color(int.parse(input, radix: 16) + 0xFF000000);
              }
              setDialogState(() => tempColor = newColor);
            } catch (_) {}
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MiuixTextField(
                controller: nameController,
                label: l10n.themeNameLabel,
                useLabelAsPlaceholder: true,
                singleLine: true,
                onChanged: (_) => setDialogState(() {}),
              ),
              const SizedBox(height: 16),
              MiuixColorPicker(
                color: tempColor,
                onColorChanged: (color) {
                  // 种子色必须不透明：MiuixColorPicker 带 alpha 滑杆，
                  // 这里强制拉满 alpha，与 Material 版 enableAlpha:false 对齐。
                  final opaque = Color(
                    0xFF000000 | (color.toARGB32() & 0xFFFFFF),
                  );
                  final newHex =
                      '#${(opaque.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
                  setDialogState(() {
                    tempColor = opaque;
                    if (hexController.text != newHex) {
                      hexController.text = newHex;
                      hexController.selection = TextSelection.fromPosition(
                        TextPosition(offset: newHex.length),
                      );
                    }
                  });
                },
              ),
              const SizedBox(height: 16),
              MiuixTextField(
                controller: hexController,
                label: l10n.themeHexLabel,
                useLabelAsPlaceholder: true,
                singleLine: true,
                trailingIcon: MiuixIconButton(
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (data?.text != null) {
                      hexController.text = data!.text!;
                      hexController.selection = TextSelection.fromPosition(
                        TextPosition(offset: data.text!.length),
                      );
                      updateColorFromText(data.text!);
                    }
                  },
                  child: const Icon(Icons.content_paste, size: 18),
                ),
                onChanged: (value) => updateColorFromText(value),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: MiuixDialogButton(
                      label: l10n.commonCancel,
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MiuixDialogButton(
                      label: l10n.commonCreate,
                      primary: true,
                      onPressed: nameController.text.trim().isEmpty
                          ? null
                          : () async {
                              final newName = nameController.text.trim();
                              final service = dialogContext
                                  .read<SettingsService>();
                              await service.addCustomTheme(newName, tempColor);
                              if (dialogContext.mounted) {
                                Navigator.of(dialogContext).pop();
                                _toast(l10n.themeCreated(newName));
                              }
                            },
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 底部抽屉里的一行动作（与发现页 miuix 版同款）。
class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MiuixGroupCard(
        insideMargin: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        feedbackType: MiuixPressFeedbackType.sink,
        onPressed: onTap,
        child: Row(
          children: [
            Icon(icon, size: 20, color: colors.onSurface),
            const SizedBox(width: 12),
            MiuixText(label, color: colors.onSurface),
          ],
        ),
      ),
    );
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
