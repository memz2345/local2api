import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/widgets/miuix/miuix_dialog.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:provider/provider.dart';

/// 退出时「要不要保存」的三个选择（与 Material 版同义，各存一份免得互引）。
enum MiuixFontWeightExitAction { save, discard }

/// miuix 风格的文字粗细页（对应 Material 版 `FontWeightScreen`）。
///
/// 档位、滑杆范围、示例预览与保存逻辑与 Material 版一致
/// （都走 `SettingsService.setFontWeight`，落盘时同样被 clamp 到 300..800），
/// 这里只换渲染：顶栏 MiuixSmallTopAppBar，滑杆 MiuixSlider，
/// 预设行 MiuixCard，保存按钮 MiuixButton。
class MiuixFontWeightScreen extends StatefulWidget {
  const MiuixFontWeightScreen({super.key});

  @override
  State<MiuixFontWeightScreen> createState() => _MiuixFontWeightScreenState();
}

class _MiuixFontWeightScreenState extends State<MiuixFontWeightScreen> {
  /// 二级页统一的可折叠大标题行为；`MiuixBlurTopBar` 读它，
  /// `MiuixScrollBehaviorListener` 在外层把滚动通知喂给它。
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();

  @override
  void dispose() {
    _behavior.state.dispose();
    super.dispose();
  }

  late double _selectedWeight;

  /// 进页面时 settings 里的值：跟它不一样就是「改了还没确认」。
  late double _initialWeight;

  /// 已经在弹窗里做了决定（保存 / 放弃），放行这一次 pop。
  bool _exitDecided = false;

  bool get _dirty => _selectedWeight != _initialWeight;

  static const _presets = <_WeightPreset>[
    _WeightPreset(100, '极细', 'Thin'),
    _WeightPreset(300, '细', 'Light'),
    _WeightPreset(400, '常规', 'Regular'),
    _WeightPreset(500, '中等', 'Medium'),
    _WeightPreset(700, '粗', 'Bold'),
    _WeightPreset(900, '极粗', 'Black'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedWeight = Provider.of<SettingsService>(
      context,
      listen: false,
    ).fontWeight;
    _initialWeight = _selectedWeight;
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

  String _presetLabel(double v, AppLocalizations l10n) {
    for (final p in _presets) {
      if (p.value == v) return _weightNumberLabel(v, l10n);
    }
    return l10n.displayWeightCustom(v.toInt());
  }

  String _weightNumberLabel(double v, AppLocalizations l10n) {
    switch (v) {
      case 100:
        return l10n.displayWeightThin(100);
      case 300:
        return l10n.displayWeightLight(300);
      case 400:
        return l10n.displayWeightRegular(400);
      case 500:
        return l10n.displayWeightMedium(500);
      case 700:
        return l10n.displayWeightBold(700);
      case 900:
        return l10n.displayWeightBlack(900);
    }
    return l10n.displayWeightCustom(v.toInt());
  }

  String _weightLabel(double v, AppLocalizations l10n) {
    switch (v) {
      case 100:
        return l10n.fontWeightThin;
      case 300:
        return l10n.fontWeightLight;
      case 400:
        return l10n.fontWeightRegular;
      case 500:
        return l10n.fontWeightMedium;
      case 700:
        return l10n.fontWeightBold;
      case 900:
        return l10n.fontWeightBlack;
    }
    return l10n.fontWeightRegular;
  }

  void _save() {
    final settings = Provider.of<SettingsService>(context, listen: false);
    settings.setFontWeight(_selectedWeight);
    _initialWeight = _selectedWeight;
    _leave();
  }

  /// 放行一次退出：先标记已决定并重建，等这一帧结束再 pop，
  /// 否则保存完还会被自己的拦截再问一遍。
  void _leave() {
    setState(() => _exitDecided = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  /// 滑块/预设改过但没点保存就退出：弹 miuix 对话框，问要不要存。
  ///
  /// 外观对照 miuix 规范的底部对话框：squircle 圆角卡片、标题居中、
  /// 正文左对齐、底部一排等宽药丸按钮（左次右主）。
  Future<void> _confirmExit() async {
    final l10n = AppLocalizations.of(context);
    final action = await showMiuixDialog<MiuixFontWeightExitAction>(
      context: context,
      title: l10n.fontWeightUnsavedTitle,
      message: l10n.fontWeightUnsavedBody(_selectedWeight.toInt()),
      actions: [
        MiuixDialogAction(
          label: l10n.cancel,
          onPressed: (ctx) => Navigator.of(ctx).pop(),
        ),
        MiuixDialogAction(
          label: l10n.fontWeightUnsavedDiscard,
          onPressed: (ctx) =>
              Navigator.of(ctx).pop(MiuixFontWeightExitAction.discard),
        ),
        MiuixDialogAction(
          label: l10n.fontWeightUnsavedSave,
          primary: true,
          onPressed: (ctx) =>
              Navigator.of(ctx).pop(MiuixFontWeightExitAction.save),
        ),
      ],
    );
    if (!mounted || action == null) return; // 取消：接着调
    if (action == MiuixFontWeightExitAction.save) {
      final settings = Provider.of<SettingsService>(context, listen: false);
      settings.setFontWeight(_selectedWeight);
      _initialWeight = _selectedWeight;
    }
    _leave();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;

    // 改过没保存就退出：拦一下，底部问要不要存（返回手势 / 顶栏返回都走这里）。
    return PopScope(
      canPop: !_dirty || _exitDecided,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmExit();
      },
      child: Material(
        type: MaterialType.transparency,
        child: MiuixScaffold(
          containerColor: colors.surface,
          topBar: MiuixBlurTopBar(
            scrollBehavior: _behavior,
            title: l10n.displayFontWeight,
            navigationIcon: MiuixIconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const MiuixAppIcon(
                AppIconNames.back,
                fallback: Icons.arrow_back,
              ),
            ),
            actions: [
              MiuixIconButton(
                onPressed: _save,
                child: const MiuixAppIcon(
                  AppIconNames.check,
                  fallback: Icons.check,
                ),
              ),
            ],
          ),
          // 内容铺满整页、顶栏画在其上；顶栏高度垫进 padding，从栏下穿过。
          content: (padding) => MiuixScrollBehaviorListener(
            behavior: _behavior,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(16, padding.top + 4, 16, 40),
              children: [
                _buildPreviewCard(colors, l10n),
                const SizedBox(height: 16),
                MiuixSmallTitle(l10n.displayScaleFineTune),
                _buildSliderCard(colors, l10n),
                const SizedBox(height: 16),
                MiuixSmallTitle(l10n.displayScalePresets),
                for (final p in _presets) _buildPresetRow(p, colors, l10n),
                const SizedBox(height: 16),
                MiuixButton(
                  onPressed: _save,
                  colors: MiuixButtonColors(
                    color: colors.primary,
                    contentColor: colors.onPrimary,
                    disabledColor: colors.disabledPrimary,
                    disabledContentColor: colors.disabledOnPrimaryButton,
                  ),
                  insideMargin: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.save_outlined, size: 18),
                      const SizedBox(width: 8),
                      MiuixText(l10n.fontWeightSaveApply),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSliderCard(MiuixColors colors, AppLocalizations l10n) {
    return MiuixGroupCard(
      cornerRadius: 16,
      insideMargin: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.text_fields,
                size: 20,
                color: colors.onSurfaceSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MiuixSlider(
                  value: _selectedWeight,
                  min: 100,
                  max: 900,
                  steps: 8,
                  onValueChanged: (v) => setState(() => _selectedWeight = v),
                ),
              ),
              SizedBox(
                width: 44,
                child: MiuixText(
                  _selectedWeight.toInt().toString(),
                  textAlign: TextAlign.right,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              l10n.fontWeightSampleText,
              style: TextStyle(
                fontWeight: _toFontWeight(_selectedWeight),
                fontSize: 15,
                height: 1.6,
                color: colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetRow(
    _WeightPreset p,
    MiuixColors colors,
    AppLocalizations l10n,
  ) {
    final isSelected = _selectedWeight == p.value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MiuixGroupCard(
        insideMargin: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        feedbackType: MiuixPressFeedbackType.sink,
        onPressed: () => setState(() => _selectedWeight = p.value),
        colors: isSelected
            ? MiuixCardColors(
                color: colors.primaryContainer,
                contentColor: colors.onPrimaryContainer,
              )
            : null,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected
                    ? colors.primary
                    : colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  'A',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: _toFontWeight(p.value),
                    color: isSelected
                        ? colors.onPrimary
                        : colors.onSurfaceSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MiuixText(
                    _weightLabel(p.value, l10n),
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                  const SizedBox(height: 2),
                  MiuixText(
                    '${p.english} · ${p.value.toInt()}',
                    fontSize: 12,
                    color: isSelected
                        ? colors.onPrimaryContainer
                        : colors.onSurfaceVariantSummary,
                  ),
                ],
              ),
            ),
            if (isSelected)
              MiuixAppIcon(
                AppIconNames.check,
                fallback: Icons.check_circle,
                size: 22,
                color: colors.primary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard(MiuixColors colors, AppLocalizations l10n) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: colors.primary,
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: Center(
              child: Text(
                'Aa',
                style: TextStyle(
                  fontSize: 64,
                  fontWeight: _toFontWeight(_selectedWeight),
                  color: colors.onPrimary,
                  height: 1.1,
                ),
              ),
            ),
          ),
          Container(
            color: colors.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Column(
              children: [
                Text(
                  _presetLabel(_selectedWeight, l10n),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'font-weight: ${_selectedWeight.toInt()}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.primary.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeightPreset {
  final double value;
  final String label;
  final String english;

  const _WeightPreset(this.value, this.label, this.english);
}
