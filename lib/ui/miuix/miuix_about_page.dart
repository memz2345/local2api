import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/widgets/effect/bg_effect_background.dart';
import 'package:local2api/widgets/effect/texture_set_state.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_bottom_sheet.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'miuix_open_source_licenses_page.dart';

/// 应用名 / 版本号：关于页与设置页共用（与 pubspec version 保持一致）。
const String kAppName = 'Local2API';
const String kAppVersion = '0.1.0';

/// 关于页（miuix 版）—— InstallerX-Revived 的 MiuixAboutPage 同款布局：
/// 上半屏是会动的「效果背景」着色器（shaders/bg_effect.frag），居中 logo +
/// 应用名 + 版本，下方卡片描述信息；滚动时背景随之淡出。点 logo 弹出
/// 「纹理集」调试面板（效果变体 / 动态背景 / 模糊参数，InstallerX 同款彩蛋）。
///
/// 卡片在开着模糊时用 flutter_miuix 的 [MiuixTextureBlur] 对背景快照取毛玻璃
/// （MiuixLayerBackdropCapture 录背景、卡片按偏移采样），对应 InstallerX
/// 「渐变本身就是卡片的模糊源」的做法；模糊关掉就回落普通卡片。
class MiuixAboutPage extends StatefulWidget {
  const MiuixAboutPage({super.key, required this.settings});

  final SettingsService settings;

  @override
  State<MiuixAboutPage> createState() => _MiuixAboutPageState();
}

class _MiuixAboutPageState extends State<MiuixAboutPage> {
  final ScrollController _scrollController = ScrollController();

  /// 卡片毛玻璃的取样源：录的是效果背景那一层。
  final MiuixLayerBackdrop _backdrop = MiuixLayerBackdrop();

  /// 纹理集参数（面板与背景/卡片共用一份）。
  late final TextureSetState _texture = TextureSetState(
    defaultBlur: widget.settings.useBlur,
  );

  /// 滚动进度（0..1，以 logo 头部高度为尺度）：背景随它淡到 surface
  /// （浅色变白 / 深色变黑），logo → 应用名 → 版本按错开的区间依次隐去。
  double _scrollProgress = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _texture.addListener(_onTextureChanged);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _texture.removeListener(_onTextureChanged);
    _texture.dispose();
    _backdrop.dispose();
    super.dispose();
  }

  void _onScroll() {
    // 以「logo 头部高度」为尺度把滚动距离折成 0..1，超过就钳住。
    final progress = (_scrollController.offset / 320).clamp(0.0, 1.0);
    if (progress != _scrollProgress) setState(() => _scrollProgress = progress);
  }

  /// [start]..[end] 区间线性淡出（错开区间 = 元素一个接一个隐）。
  double _fadeOf(double start, double end) =>
      (1.0 - ((_scrollProgress - start) / (end - start))).clamp(0.0, 1.0);

  void _onTextureChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      type: MaterialType.transparency,
      child: MiuixScaffold(
        containerColor: colors.surface,
        // 无顶栏（InstallerX 关于页同款）：背景铺满整页，返回键悬浮在
        // 背景之上，内容从状态栏底下开始。
        content: (padding) => Stack(
          children: [
            // 效果背景铺满整页：MiuixLayerBackdropCapture 把它录下来给卡片
            // 做毛玻璃源；向下滑时 alpha 压到 0，页面渐渐变回白/黑 surface。
            Positioned.fill(
              child: MiuixLayerBackdropCapture(
                backdrop: _backdrop,
                child: BgEffectBackground(
                  variant: _texture.variant,
                  dark: dark,
                  dynamic: _texture.dynamicBg,
                  enabled: _texture.effectBg,
                  alpha: 1.0 - _scrollProgress,
                  saturateOffset: _texture.noise,
                ),
              ),
            ),
            SafeArea(
              child: ListView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                children: [
                  const SizedBox(height: 72),
                  _buildLogoHeader(l10n, colors),
                  const SizedBox(height: 32),
                  _blurCard(
                    insideMargin: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: MiuixText(l10n.aboutDesc, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  _blurCard(
                    insideMargin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _row(
                          l10n.versionLabel,
                          value: kAppVersion,
                          icon: Icons.verified_user_outlined,
                        ),
                        const MiuixHorizontalDivider(),
                        _row(
                          l10n.aboutComponents,
                          value: 'Flutter · flutter_miuix',
                          icon: Icons.layers_outlined,
                        ),
                        const MiuixHorizontalDivider(),
                        _row(
                          l10n.textureSetTitle,
                          value: l10n.aboutEntryDesc,
                          icon: Icons.auto_awesome_outlined,
                          onClick: _showTextureSetSheet,
                        ),
                        const MiuixHorizontalDivider(),
                        _row(
                          l10n.aboutOpenLicenses,
                          icon: Icons.menu_book_outlined,
                          onClick: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  const MiuixOpenSourceLicensesPage(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 返回键悬浮在背景上（不随内容滚动）
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 2, 0, 0),
                  child: MiuixIconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const MiuixAppIcon(
                      AppIconNames.back,
                      fallback: Icons.arrow_back,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 居中的 logo + 应用名 + 版本（InstallerX 关于页同款头）。
  ///
  /// 向下滑时三个元素按错开的进度区间依次渐隐（图标 → 名称 → 版本），
  /// 图标还带一点缩放，对应 InstallerX 的 graphicsLayer alpha/scale。
  Widget _buildLogoHeader(AppLocalizations l10n, MiuixColors colors) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        // 点 logo 弹纹理集（InstallerX 非 stable 包的彩蛋入口）
        Transform.scale(
          scale: 0.92 + 0.08 * _fadeOf(0.0, 0.35),
          child: Opacity(
            opacity: _fadeOf(0.0, 0.35),
            child: GestureDetector(
              onTap: _showTextureSetSheet,
              child: Container(
                width: 96,
                height: 96,
                decoration: ShapeDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: dark
                        ? const [Color(0xFF8B5CF6), Color(0xFF4F46E5)]
                        : const [Color(0xFFA78BFA), Color(0xFF6366F1)],
                  ),
                  shape: const MiuixSquircleBorder(cornerRadius: 28),
                  shadows: [
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
          child: MiuixText(
            kAppName,
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Opacity(
          opacity: _fadeOf(0.36, 0.68),
          child: MiuixText(
            '${l10n.versionLabel} $kAppVersion',
            fontSize: 14,
            color: colors.onSurfaceVariantSummary,
          ),
        ),
      ],
    );
  }

  /// 一行信息（图标 + 标题 + 值/箭头）；onClick 为空就是纯展示行。
  Widget _row(
    String title, {
    String? value,
    IconData? icon,
    VoidCallback? onClick,
  }) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixBasicComponent(
      title: title,
      summary: value,
      startAction: icon == null
          ? null
          : Icon(icon, size: 22, color: colors.onSurface),
      endActions: onClick == null
          ? const []
          : [
              MiuixAppIcon(
                AppIconNames.forward,
                fallback: Icons.chevron_right,
                size: 20,
                color: colors.onSurfaceVariantActions,
              ),
            ],
      onClick: onClick,
    );
  }

  /// 卡片：模糊开着时用背景快照做毛玻璃（卡片本体透明），否则普通卡片。
  Widget _blurCard({
    required Widget child,
    EdgeInsetsGeometry insideMargin = MiuixCardDefaults.insideMargin,
  }) {
    if (!_texture.blurEnable || !_texture.effectBg) {
      return MiuixGroupCard(insideMargin: insideMargin, child: child);
    }
    return MiuixTextureBlur(
      backdrop: _backdrop,
      shape: const MiuixSquircleBorder(
        cornerRadius: MiuixCardDefaults.cornerRadius,
      ),
      blurRadius: _texture.blurRadius,
      colors: _texture.blurColors(
        Theme.of(context).brightness == Brightness.dark,
      ),
      child: Padding(padding: insideMargin, child: child),
    );
  }

  // ------------------------------------------------------------------
  // 纹理集（Texture Set）调试面板 —— InstallerX 点 logo 弹的那一块
  // ------------------------------------------------------------------

  void _showTextureSetSheet() {
    final l10n = AppLocalizations.of(context);
    showMiuixBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        builder: (ctx, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: ListenableBuilder(
            listenable: _texture,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MiuixText(
                  l10n.textureSetTitle,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                _variantRow(l10n),
                const SizedBox(height: 12),
                MiuixGroupCard(
                  insideMargin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      MiuixSwitchPreference(
                        title: l10n.textureSetEffectBg,
                        value: _texture.effectBg,
                        onChanged: (v) => _texture.set((s) => s.effectBg = v),
                      ),
                      const MiuixHorizontalDivider(),
                      MiuixSwitchPreference(
                        title: l10n.textureSetDynamicBg,
                        value: _texture.dynamicBg,
                        onChanged: (v) => _texture.set((s) => s.dynamicBg = v),
                      ),
                      const MiuixHorizontalDivider(),
                      MiuixSwitchPreference(
                        title: l10n.textureSetBlurEnable,
                        value: _texture.blurEnable,
                        onChanged: (v) => _texture.set((s) => s.blurEnable = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                MiuixGroupCard(
                  insideMargin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _blendModeRow(l10n),
                const SizedBox(height: 16),
                MiuixButton(
                  onPressed: () => _texture.reset(widget.settings.useBlur),
                  child: MiuixText(l10n.textureSetReset),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 效果变体 OS3/OS2：二选一胶囊（弹层里用不了 popup 宿主，参考对话
  /// 模拟页角色片的做法）。
  Widget _variantRow(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: MiuixText(l10n.textureSetEffectVariant, fontSize: 14),
        ),
        Row(
          children: [
            _chip(
              l10n.textureSetOs3,
              _texture.variant == BgEffectVariant.os3,
              () => _texture.setVariant(BgEffectVariant.os3),
            ),
            const SizedBox(width: 8),
            _chip(
              l10n.textureSetOs2,
              _texture.variant == BgEffectVariant.os2,
              () => _texture.setVariant(BgEffectVariant.os2),
            ),
          ],
        ),
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    final colors = MiuixTheme.of(context).colors;
    return Expanded(
      child: MiuixGroupCard(
        cornerRadius: 12,
        insideMargin: const EdgeInsets.symmetric(vertical: 10),
        feedbackType: MiuixPressFeedbackType.sink,
        onPressed: onTap,
        colors: selected
            ? MiuixCardColors(
                color: colors.primary,
                contentColor: colors.onPrimary,
              )
            : null,
        child: Center(
          child: MiuixText(
            label,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
    final colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: MiuixText(label, fontSize: 14)),
              MiuixText(
                format(value),
                fontSize: 13,
                color: colors.onSurfaceVariantSummary,
              ),
            ],
          ),
          MiuixSlider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onValueChanged: onChanged,
          ),
        ],
      ),
    );
  }

  /// 混合模式：行尾 Prev/Next 循环切换（InstallerX 同款交互）。
  Widget _blendModeRow(AppLocalizations l10n) {
    final colors = MiuixTheme.of(context).colors;
    final current = _texture.blendPreset;
    return MiuixGroupCard(
      insideMargin: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Expanded(child: MiuixText(l10n.textureSetBlendMode, fontSize: 14)),
          MiuixIconButton(
            onPressed: () => _texture.set(
              (s) => s.blendIndex =
                  (s.blendIndex - 1 + blendModePresets.length) %
                  blendModePresets.length,
            ),
            // chevronBackward 在 miuix 图标集里有（AppIconNames 没收录），
            // 直接按名字取，回落 Material 左箭头。
            child: const MiuixAppIcon(
              'chevronBackward',
              fallback: Icons.chevron_left,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 84,
            child: MiuixText(
              current.label(l10n),
              fontSize: 13,
              textAlign: TextAlign.center,
              color: colors.primary,
              fontWeight: FontWeight.w600,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          MiuixIconButton(
            onPressed: () => _texture.set(
              (s) =>
                  s.blendIndex = (s.blendIndex + 1) % blendModePresets.length,
            ),
            child: const MiuixAppIcon(
              AppIconNames.forward,
              fallback: Icons.chevron_right,
            ),
          ),
        ],
      ),
    );
  }
}
