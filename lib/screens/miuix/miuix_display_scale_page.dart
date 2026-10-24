import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_info_card.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:provider/provider.dart';

/// miuix 风格的显示缩放页（对应 Material 版 `DisplayScalePage`）。
///
/// 缩放范围、预设档位、示例预览与即时落盘逻辑与 Material 版完全一致
/// （都走 `SettingsService.setDisplayScale`），这里只换渲染：
/// 顶栏用 MiuixSmallTopAppBar，滑块用 MiuixSlider，预设行用 MiuixCard。
class MiuixDisplayScalePage extends StatefulWidget {
  const MiuixDisplayScalePage({super.key});

  @override
  State<MiuixDisplayScalePage> createState() => _MiuixDisplayScalePageState();
}

class _MiuixDisplayScalePageState extends State<MiuixDisplayScalePage> {
  @override
  void dispose() {
    _behavior.state.dispose();
    super.dispose();
  }

  /// 一级/二级页统一的可折叠大标题行为；`MiuixBlurTopBar` 读它，
  /// `MiuixScrollBehaviorListener` 在上面那层把滚动通知喂给它。
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();
  late double _scale;

  static const double _minScale = 0.50;
  static const double _maxScale = 2.00;
  static const double _step = 0.05;

  static const List<_ScalePreset> _presets = [
    _ScalePreset(label: '50%', value: 0.50),
    _ScalePreset(label: '75%', value: 0.75),
    _ScalePreset(label: '100%', value: 1.00),
    _ScalePreset(label: '125%', value: 1.25),
    _ScalePreset(label: '150%', value: 1.50),
    _ScalePreset(label: '200%', value: 2.00),
  ];

  static const List<({String title, String subtitle, IconData icon})>
  _sampleItems = [
    (
      title: '视频标题示例',
      subtitle: '视频简介文字示例：用于预览界面文字随缩放比例的变化。',
      icon: Icons.play_circle_outline,
    ),
    (
      title: '示例合集 · 播放列表',
      subtitle: '第 3 集 / 共 12 集 · 连载中 · 双语字幕',
      icon: Icons.video_library_outlined,
    ),
    (
      title: '简介文字示例',
      subtitle: '较长的简介文字会自动换行或省略，方便检查缩放后的排版效果。',
      icon: Icons.closed_caption_outlined,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _scale = context.read<SettingsService>().displayScale;
  }

  void _applyScale(double value) {
    final clamped = value.clamp(_minScale, _maxScale);
    setState(() => _scale = clamped);
    context.read<SettingsService>().setDisplayScale(clamped);
  }

  void _resetToDefault() => _applyScale(1.0);

  String _scaleDescription(AppLocalizations l10n) {
    if (_scale < 0.75) return l10n.displayScaleCompact;
    if (_scale < 1.0) return l10n.displayScaleSmall;
    if (_scale == 1.0) return l10n.displayScaleDefault;
    if (_scale <= 1.25) return l10n.displayScaleLarge;
    if (_scale <= 1.5) return l10n.displayScaleLargeFont;
    return l10n.displayScaleHuge;
  }

  String _scaleHint(double v, AppLocalizations l10n) {
    if (v <= 0.50) return l10n.displayScaleMin;
    if (v <= 0.75) return l10n.displayScaleCompactBig;
    if (v <= 1.00) return l10n.displayScaleSystemDefault;
    if (v <= 1.25) return l10n.displayScaleLarge;
    if (v <= 1.50) return l10n.displayScaleLargeFontShort;
    return l10n.displayScaleHuge;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;

    return Material(
      type: MaterialType.transparency,
      child: MiuixScaffold(
        containerColor: colors.surface,
        topBar: MiuixBlurTopBar(
          scrollBehavior: _behavior,
          title: l10n.displayScaleTitle,
          navigationIcon: MiuixIconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const MiuixAppIcon(
              AppIconNames.back,
              fallback: Icons.arrow_back,
            ),
          ),
          actions: [
            MiuixIconButton(
              onPressed: _resetToDefault,
              child: const MiuixAppIcon(
                AppIconNames.reset,
                fallback: Icons.restart_alt,
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
              _buildSliderCard(colors),
              const SizedBox(height: 16),
              MiuixSmallTitle(l10n.displayScalePresets),
              for (final p in _presets) _buildPresetRow(p, colors, l10n),
              const SizedBox(height: 16),
              _buildNoteCard(l10n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSliderCard(MiuixColors colors) {
    return MiuixGroupCard(
      cornerRadius: 16,
      insideMargin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.zoom_in, size: 20, color: colors.onSurfaceSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: MiuixSlider(
                  value: _scale,
                  min: _minScale,
                  max: _maxScale,
                  steps: ((_maxScale - _minScale) / _step).round(),
                  onValueChanged: _applyScale,
                ),
              ),
              SizedBox(
                width: 48,
                child: MiuixText(
                  '${(_scale * 100).round()}%',
                  textAlign: TextAlign.right,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                MiuixText(
                  '50%',
                  fontSize: 11,
                  color: colors.onSurfaceVariantSummary,
                ),
                MiuixText(
                  '200%',
                  fontSize: 11,
                  color: colors.onSurfaceVariantSummary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetRow(
    _ScalePreset p,
    MiuixColors colors,
    AppLocalizations l10n,
  ) {
    final isSelected = (_scale - p.value).abs() < 0.001;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MiuixGroupCard(
        insideMargin: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        feedbackType: MiuixPressFeedbackType.sink,
        onPressed: () => _applyScale(p.value),
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
                    fontSize: 12 + p.value * 6,
                    fontWeight: FontWeight.w600,
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
                    p.label,
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                  const SizedBox(height: 2),
                  MiuixText(
                    _scaleHint(p.value, l10n),
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

  Widget _buildNoteCard(AppLocalizations l10n) {
    return MiuixDismissibleInfoCard(
      id: 'intro.displayScale',
      text: l10n.displayScaleNote,
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
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(_scale)),
              child: Column(
                children: [
                  Text(
                    '${(_scale * 100).round()}%',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w700,
                      color: colors.onPrimary,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _scaleDescription(l10n),
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.onPrimary.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            color: colors.surfaceContainerHigh,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(_scale)),
              child: Column(
                children: _sampleItems
                    .map((s) => _buildSampleTile(s, colors))
                    .toList(),
              ),
            ),
          ),
          Container(
            color: colors.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'textScaler: ${_scale.toStringAsFixed(2)}',
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

  Widget _buildSampleTile(
    ({String title, String subtitle, IconData icon}) sample,
    MiuixColors colors,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: colors.primaryContainer,
            radius: 22,
            child: Icon(
              sample.icon,
              size: 22,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sample.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sample.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceSecondary,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            size: 18,
            color: colors.onSurfaceSecondary.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }
}

class _ScalePreset {
  final String label;
  final double value;
  const _ScalePreset({required this.label, required this.value});
}
