// 「纹理集」（Texture Set）状态：InstallerX 关于页点 logo 弹出的那块调试
// 面板的数据。miuix / Material 两个风格的关于页共用这一份，控件各画各的。
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/l10n/app_localizations.dart';

import 'bg_effect_background.dart';

/// 一个混合模式预设：名字 + 一组叠在模糊背景上的颜色层（对应 InstallerX
/// 的 ColorBlendToken）。
class BlendModePreset {
  const BlendModePreset(this.label, this.entries);

  final String Function(AppLocalizations) label;
  final List<BlendColorEntry> Function(bool dark) entries;
}

final List<BlendModePreset> blendModePresets = [
  BlendModePreset(
    (l10n) => l10n.blendModeDefault,
    (dark) => dark
        // InstallerX 默认档是 PlusDarker 黑 0.6；Flutter 管线只支持标准
        // 模式，用 srcOver 黑 0.6 达成同样的「深色纱罩」观感。
        ? const [BlendColorEntry(Color(0x99000000), BlurBlendMode.srcOver)]
        : const [BlendColorEntry(Color(0x8CFFFFFF), BlurBlendMode.srcOver)],
  ),
  BlendModePreset(
    (l10n) => l10n.blendModeOverlay,
    (dark) => [
      BlendColorEntry(
        dark ? const Color(0x33FFFFFF) : const Color(0x26FFFFFF),
        BlurBlendMode.overlay,
      ),
    ],
  ),
  BlendModePreset(
    (l10n) => l10n.blendModeScreen,
    (_) => const [BlendColorEntry(Color(0x2E808080), BlurBlendMode.screen)],
  ),
  BlendModePreset(
    (l10n) => l10n.blendModeMultiply,
    (dark) => [
      BlendColorEntry(
        dark ? const Color(0x40404080) : const Color(0x26C0C0C0),
        BlurBlendMode.multiply,
      ),
    ],
  ),
  BlendModePreset(
    (l10n) => l10n.blendModePlusLighter,
    (_) => const [BlendColorEntry(Color(0x1FFFFFFF), BlurBlendMode.plus)],
  ),
  BlendModePreset(
    (l10n) => l10n.blendModePlusDarker,
    (_) => const [BlendColorEntry(Color(0x66000000), BlurBlendMode.darken)],
  ),
  BlendModePreset(
    (l10n) => l10n.blendModeLinearLight,
    (_) => const [BlendColorEntry(Color(0x29FFFFFF), BlurBlendMode.softLight)],
  ),
  BlendModePreset(
    (l10n) => l10n.blendModeDifference,
    (_) => const [BlendColorEntry(Color(0x33FFFFFF), BlurBlendMode.difference)],
  ),
];

/// 纹理集当前参数（ChangeNotifier：滑条一动页面与面板同步刷新）。
class TextureSetState extends ChangeNotifier {
  TextureSetState({required bool defaultBlur}) : blurEnable = defaultBlur;

  BgEffectVariant variant = BgEffectVariant.os3;
  bool effectBg = true;
  bool dynamicBg = true;

  /// 卡片毛玻璃默认跟随显示设置里的「模糊」总开关。
  bool blurEnable;
  double blurRadius = 60;

  /// 噪点：驱动背景着色器的噪声去饱和强度（默认取 OS3 浅色预设）。
  double noise = kOs3PhoneLight.saturateOffset;
  double brightness = 0;
  double contrast = 1;
  double saturation = 1;
  int blendIndex = 0;

  BgEffectPreset get preset => switch (variant) {
    BgEffectVariant.os2 => kOs2PhoneLight,
    BgEffectVariant.os3 => kOs3PhoneLight,
  };

  BlendModePreset get blendPreset =>
      blendModePresets[blendIndex % blendModePresets.length];

  /// 卡片毛玻璃的 BlurColors（混合层 + 亮度/对比度/饱和度）。
  BlurColors blurColors(bool dark) => BlurColors(
    blendColors: blendPreset.entries(dark),
    brightness: brightness,
    contrast: contrast,
    saturation: saturation,
  );

  void setVariant(BgEffectVariant v) {
    variant = v;
    // 换变体顺手把噪点对到该变体预设的默认值（和 InstallerX 一样给个合理起点）
    noise = preset.saturateOffset;
    notifyListeners();
  }

  void set(void Function(TextureSetState) mutate) {
    mutate(this);
    notifyListeners();
  }

  void reset(bool defaultBlur) {
    variant = BgEffectVariant.os3;
    effectBg = true;
    dynamicBg = true;
    blurEnable = defaultBlur;
    blurRadius = 60;
    noise = kOs3PhoneLight.saturateOffset;
    brightness = 0;
    contrast = 1;
    saturation = 1;
    blendIndex = 0;
    notifyListeners();
  }
}
