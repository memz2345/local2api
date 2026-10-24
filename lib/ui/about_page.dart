import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/ui/miuix/miuix_about_page.dart'
    show kAppName, kAppVersion;
import 'package:local2api/ui/open_source_licenses_page.dart';
import 'package:local2api/widgets/effect/bg_effect_background.dart';
import 'package:local2api/widgets/effect/texture_set_state.dart';

/// 关于页（Material 版，对应 miuix 版 `MiuixAboutPage`）：同为 InstallerX
/// 的效果背景 + 居中 logo 头，卡片用半透明 surface 让背景透出来。点 logo
/// 弹「纹理集」面板（与 miuix 版共用 [TextureSetState]，控件是 Material 的）。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key, required this.settings});

  final SettingsService settings;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  final ScrollController _scrollController = ScrollController();
  late final TextureSetState _texture = TextureSetState(
    defaultBlur: widget.settings.useBlur,
  );
  double _scrollProgress = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _texture.dispose();
    super.dispose();
  }

  void _onScroll() {
    final progress = (_scrollController.offset / 320).clamp(0.0, 1.0);
    if (progress != _scrollProgress) setState(() => _scrollProgress = progress);
  }

  /// [start]..[end] 区间线性淡出（错开区间 = logo → 名称 → 版本依次隐去）。
  double _fadeOf(double start, double end) =>
      (1.0 - ((_scrollProgress - start) / (end - start))).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: BgEffectBackground(
                dark: theme.brightness == Brightness.dark,
                alpha: 1.0 - _scrollProgress,
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).backButtonTooltip,
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                    children: [
                      _buildLogoHeader(l10n, cs),
                      const SizedBox(height: 32),
                      _card(
                        cs,
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            l10n.aboutDesc,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _card(
                        cs,
                        Column(
                          children: [
                            _row(
                              l10n.versionLabel,
                              value: kAppVersion,
                              icon: Icons.verified_user_outlined,
                              cs: cs,
                              theme: theme,
                            ),
                            const Divider(height: 1),
                            _row(
                              l10n.aboutComponents,
                              value: 'Flutter · flutter_miuix',
                              icon: Icons.layers_outlined,
                              cs: cs,
                              theme: theme,
                            ),
                            const Divider(height: 1),
                            _row(
                              l10n.textureSetTitle,
                              value: l10n.aboutEntryDesc,
                              icon: Icons.auto_awesome_outlined,
                              cs: cs,
                              theme: theme,
                              onTap: _showTextureSetSheet,
                            ),
                            const Divider(height: 1),
                            _row(
                              l10n.aboutOpenLicenses,
                              icon: Icons.menu_book_outlined,
                              cs: cs,
                              theme: theme,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      const OpenSourceLicensesPage(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoHeader(AppLocalizations l10n, ColorScheme cs) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Transform.scale(
          scale: 0.92 + 0.08 * _fadeOf(0.0, 0.35),
          child: Opacity(
            opacity: _fadeOf(0.0, 0.35),
            child: GestureDetector(
              onTap: _showTextureSetSheet,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: dark
                        ? const [Color(0xFF8B5CF6), Color(0xFF4F46E5)]
                        : const [Color(0xFFA78BFA), Color(0xFF6366F1)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.35),
                      blurRadius: 32,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.lan_outlined,
                  size: 44,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Opacity(
          opacity: _fadeOf(0.18, 0.5),
          child: Text(
            kAppName,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 6),
        Opacity(
          opacity: _fadeOf(0.36, 0.68),
          child: Text(
            '${l10n.versionLabel} $kAppVersion',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _card(ColorScheme cs, Widget child) {
    return Material(
      color: cs.surfaceContainerHighest.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.55 : 0.72,
      ),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _row(
    String title, {
    String? value,
    required IconData icon,
    required ColorScheme cs,
    required ThemeData theme,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: cs.onSurface),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.bodyMedium),
                  if (value != null)
                    Text(
                      value,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right, size: 22, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // 纹理集（Texture Set）：与 miuix 版同一份参数，控件走 Material
  // ------------------------------------------------------------------

  void _showTextureSetSheet() {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          maxChildSize: 0.92,
          minChildSize: 0.4,
          builder: (ctx, scrollCtrl) => SingleChildScrollView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: ListenableBuilder(
              listenable: _texture,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.textureSetTitle,
                    style: Theme.of(sheetCtx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<BgEffectVariant>(
                    segments: [
                      ButtonSegment(
                        value: BgEffectVariant.os3,
                        label: Text(l10n.textureSetOs3),
                      ),
                      ButtonSegment(
                        value: BgEffectVariant.os2,
                        label: Text(l10n.textureSetOs2),
                      ),
                    ],
                    selected: {_texture.variant},
                    onSelectionChanged: (s) => _texture.setVariant(s.first),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: Text(l10n.textureSetEffectBg),
                    value: _texture.effectBg,
                    onChanged: (v) => _texture.set((s) => s.effectBg = v),
                  ),
                  SwitchListTile(
                    title: Text(l10n.textureSetDynamicBg),
                    value: _texture.dynamicBg,
                    onChanged: (v) => _texture.set((s) => s.dynamicBg = v),
                  ),
                  SwitchListTile(
                    title: Text(l10n.textureSetBlurEnable),
                    value: _texture.blurEnable,
                    onChanged: (v) => _texture.set((s) => s.blurEnable = v),
                  ),
                  _slider(
                    l10n.textureSetBlurRadius,
                    _texture.blurRadius,
                    0,
                    200,
                    (v) => _texture.set((s) => s.blurRadius = v),
                    format: (v) => v.round().toString(),
                  ),
                  _slider(
                    l10n.textureSetNoise,
                    _texture.noise,
                    0,
                    0.5,
                    (v) => _texture.set((s) => s.noise = v),
                    format: (v) => v.toStringAsFixed(3),
                  ),
                  _slider(
                    l10n.textureSetBrightness,
                    _texture.brightness,
                    -1,
                    1,
                    (v) => _texture.set((s) => s.brightness = v),
                    format: (v) => v.toStringAsFixed(2),
                  ),
                  _slider(
                    l10n.textureSetContrast,
                    _texture.contrast,
                    0,
                    3,
                    (v) => _texture.set((s) => s.contrast = v),
                    format: (v) => v.toStringAsFixed(2),
                  ),
                  _slider(
                    l10n.textureSetSaturation,
                    _texture.saturation,
                    0,
                    3,
                    (v) => _texture.set((s) => s.saturation = v),
                    format: (v) => v.toStringAsFixed(2),
                  ),
                  Row(
                    children: [
                      Expanded(child: Text(l10n.textureSetBlendMode)),
                      IconButton(
                        onPressed: () => _texture.set(
                          (s) => s.blendIndex =
                              (s.blendIndex - 1 + blendModePresets.length) %
                              blendModePresets.length,
                        ),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text(_texture.blendPreset.label(l10n)),
                      IconButton(
                        onPressed: () => _texture.set(
                          (s) => s.blendIndex =
                              (s.blendIndex + 1) % blendModePresets.length,
                        ),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () => _texture.reset(widget.settings.useBlur),
                    child: Text(l10n.textureSetReset),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    required String Function(double) format,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(format(value), style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
