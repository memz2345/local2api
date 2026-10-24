import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:local2api/widgets/liquid_glass.dart';
import 'package:local2api/widgets/ui_settings.dart';

class GlassBottomBarTab {
  final String label;
  final IconData? icon;
  final IconData? selectedIcon;

  /// 自定义图标构造。给了它就用它，忽略 [icon] / [selectedIcon]。
  ///
  /// 场景：miuix 风格的图标是 `MiuixVectorIcon`（不是 IconData），
  /// 没法塞进 [icon]。底栏内部的 `TabBarItem` 会用
  /// `IconTheme(color: 选中/未选中色, size: iconSize)` 包住图标，
  /// 所以只要用会读 IconTheme 的图标组件（如 `MiuixAppIcon`），
  /// 选中态/尺寸都能自动跟上，不需要在这里传颜色。
  final Widget Function(bool selected)? iconBuilder;

  const GlassBottomBarTab({
    required this.label,
    this.icon,
    this.selectedIcon,
    this.iconBuilder,
  }) : assert(
         iconBuilder != null || icon != null,
         'GlassBottomBarTab 至少要给 icon 或 iconBuilder',
       );
}

/// 液态玻璃底栏（从 NaviFlash 移植，固定使用玻璃模式）。
class GlassBottomBar extends StatelessWidget {
  final List<GlassBottomBarTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final double barHeight;

  /// 右侧附加按钮（搜索等场景，本 App 暂未使用，保留 API 兼容）。
  final GlassTabBarExtraButton? extraButton;

  const GlassBottomBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onTabSelected,
    this.barHeight = 60,
    this.extraButton,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool jelly = UiSettings.liquidGlassBottomBarJelly;
    // 必须用运行时的着色器能力（naviGlassAdvanced = fragmentRenderingEnabled
    // && ImageFilter.isShaderFilterSupported），不能只看那个编译期常量。
    // 只看常量的话，在没有 shader filter 的平台上（软件渲染的模拟器、
    // 老设备的 GL 后端）依然会走 GlassQuality.premium 的片元着色器路径，
    // 实测会把渲染进程直接打崩 —— 底栏一出现模拟器就整个掉线。
    final bool advanced = naviGlassAdvanced;
    // NaviFlash 同款参数：轻玻璃底 + 果冻变形指示器。
    final bar = GlassTabBar.bottom(
      extraButton: extraButton,
      tabs: [
        for (final tab in tabs)
          GlassTab(
            label: tab.label,
            icon: tab.iconBuilder?.call(false) ?? Icon(tab.icon!),
            activeIcon:
                tab.iconBuilder?.call(true) ??
                Icon(tab.selectedIcon ?? tab.icon!),
            glowColor: colorScheme.primary.withValues(alpha: 0.22),
          ),
      ],
      selectedIndex: selectedIndex,
      onTabSelected: onTabSelected,
      barHeight: barHeight,
      horizontalPadding: 12,
      verticalPadding: 8,
      enableBlend: true,
      blendAmount: 10,
      iconSize: 22,
      labelFontSize: 12,
      selectedIconColor: colorScheme.primary,
      selectedLabelColor: colorScheme.primary,
      unselectedIconColor: colorScheme.onSurface.withValues(alpha: 0.72),
      unselectedLabelColor: colorScheme.onSurface.withValues(alpha: 0.72),
      selectedLabelStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      indicatorColor: colorScheme.primary.withValues(alpha: 0.10),
      settings: buildNaviGlassSettings(
        blur: 12,
        thickness: 14,
        tintOpacity: 0.02,
        lightIntensity: 0.05,
        ambientStrength: 0,
        fresnelStrength: 0.5,
        glowIntensity: 0.08,
        specularSharpness: GlassSpecularSharpness.soft,
        shadowElevation: 0,
      ),
      indicatorSettings: buildNaviGlassSettings(
        blur: 4,
        thickness: 16,
        tintOpacity: 0.1,
        lightIntensity: 0.04,
        ambientStrength: 0.01,
        ambientRim: 0.01,
        fresnelStrength: 0.18,
        glowIntensity: 0,
        chromaticAberration: 0,
        shadowElevation: 0,
        specularSharpness: GlassSpecularSharpness.soft,
      ),
      quality: advanced ? GlassQuality.premium : GlassQuality.minimal,
      maskingQuality: (jelly && advanced)
          ? MaskingQuality.high
          : MaskingQuality.off,
      indicatorPinchStrength: 0.32,
      magnification: 1.08,
      glowBlurRadius: 16,
      glowSpreadRadius: 2,
      glowOpacity: 0.22,
      interactionGlowColor: colorScheme.primary.withValues(alpha: 0.32),
      pressScale: 1.02,
    );
    return bar;
  }
}
