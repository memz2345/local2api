import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:local2api/widgets/widgets.dart';
import 'package:local2api/widgets/page_background.dart';
import '../services/settings_service.dart';
import '../l10n/app_localizations.dart';

/// 退出时「要不要保存」的三个选择。
enum FontWeightExitAction { save, discard }

class FontWeightScreen extends StatefulWidget {
  const FontWeightScreen({super.key});

  @override
  State<FontWeightScreen> createState() => _FontWeightScreenState();
}

class _FontWeightScreenState extends State<FontWeightScreen> {
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
    final settings = Provider.of<SettingsService>(context, listen: false);
    _selectedWeight = settings.fontWeight;
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

  String _presetLabel(double v) {
    final l10n = AppLocalizations.of(context);
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

  /// 放行一次退出。
  ///
  /// PopScope 的 canPop 要等重建完才变 true，所以先 setState 标记「已决定」，
  /// 再等这一帧结束才 pop —— 否则保存完还会被自己的拦截再问一遍。
  void _leave() {
    setState(() => _exitDecided = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  /// 滑块/预设改过但没点保存就退出：居中弹一句，问要不要存。
  ///
  /// 走标准 Material 居中对话框（`AlertDialog`）；miuix 那边是
  /// `showMiuixDialog` 的贴底卡片，两套风格各按自己的规范来。
  Future<void> _confirmExit() async {
    final l10n = AppLocalizations.of(context);
    final action = await showDialog<FontWeightExitAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.fontWeightUnsavedTitle),
        content: Text(l10n.fontWeightUnsavedBody(_selectedWeight.toInt())),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(FontWeightExitAction.discard),
            child: Text(l10n.fontWeightUnsavedDiscard),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(FontWeightExitAction.save),
            child: Text(l10n.fontWeightUnsavedSave),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return; // 取消：接着调
    if (action == FontWeightExitAction.save) {
      final settings = Provider.of<SettingsService>(context, listen: false);
      settings.setFontWeight(_selectedWeight);
      _initialWeight = _selectedWeight;
    }
    _leave();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    // 改过没保存就退出：拦一下，底部问要不要存（返回手势 / 顶栏返回都走这里）。
    return PopScope(
      canPop: !_dirty || _exitDecided,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmExit();
      },
      child: Scaffold(
        backgroundColor: cs.surfaceContainer,
        body: Stack(
          children: [
            PageBackground(baseColor: cs.surfaceContainer),
            CustomScrollView(
              physics: const ClampingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                ExpressiveSliverAppBar(
                  title: l10n.displayFontWeight,
                  leading: MorphIconButton(
                    icon: Icons.arrow_back,
                    tooltip: l10n.commonBackTooltip,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: MorphIconButton(
                        icon: Icons.check,
                        tooltip: l10n.commonSave,
                        onTap: _save,
                      ),
                    ),
                  ],
                ),

                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildPreviewCard(cs),

                      const SizedBox(height: 24),

                      _buildSectionTitle(context, l10n.displayScaleFineTune),
                      const SizedBox(height: 12),
                      MorphItem(
                        selected: false,
                        isFirst: true,
                        isLast: true,
                        interactive: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.text_fields,
                                    size: 20,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Slider(
                                      value: _selectedWeight,
                                      min: 100,
                                      max: 900,
                                      divisions: 8,
                                      label: _selectedWeight.toInt().toString(),
                                      activeColor: cs.primary,
                                      inactiveColor: cs.surfaceContainerHighest,
                                      onChanged: (v) =>
                                          setState(() => _selectedWeight = v),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 44,
                                    child: Text(
                                      _selectedWeight.toInt().toString(),
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: cs.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),

                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(
                                    kItemRadius,
                                  ),
                                ),
                                child: Text(
                                  l10n.fontWeightSampleText,
                                  style: TextStyle(
                                    fontWeight: _toFontWeight(_selectedWeight),
                                    fontSize: 15,
                                    height: 1.6,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      _buildSectionTitle(context, l10n.displayScalePresets),
                      const SizedBox(height: 12),
                      ...buildMorphSegmentedList(
                        _presets.map((p) {
                          final isSelected = _selectedWeight == p.value;
                          return MorphRowItem(
                            interactive: true,
                            child: InkWell(
                              onTap: () =>
                                  setState(() => _selectedWeight = p.value),
                              borderRadius: BorderRadius.circular(
                                kItemPressedRadius,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? cs.primaryContainer
                                            : cs.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(
                                          kItemRadius,
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          'A',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: _toFontWeight(p.value),
                                            color: isSelected
                                                ? cs.onPrimaryContainer
                                                : cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _weightLabel(p.value, l10n),
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: isSelected
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                              color: cs.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${p.english} · ${p.value.toInt()}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: cs.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    AnimatedOpacity(
                                      opacity: isSelected ? 1 : 0,
                                      duration: kMorphDuration,
                                      child: Icon(
                                        Icons.check_circle,
                                        size: 22,
                                        color: cs.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 32),

                      FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(l10n.fontWeightSaveApply),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              kItemPressedRadius,
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard(ColorScheme cs) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(kGroupRadius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: cs.primary,
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: Center(
              child: Text(
                'Aa',
                style: TextStyle(
                  fontSize: 64,
                  fontWeight: _toFontWeight(_selectedWeight),
                  color: cs.onPrimary,
                  height: 1.1,
                ),
              ),
            ),
          ),

          Container(
            color: cs.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Column(
              children: [
                Text(
                  _presetLabel(_selectedWeight),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'font-weight: ${_selectedWeight.toInt()}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cs.primary.withValues(alpha: 0.6),
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

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      textAlign: TextAlign.left,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.primary,
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
