import 'package:flutter/physics.dart';

/// 从 NaviFlash 移植的 UI 组件所需的静态开关/参数集合。
///
/// NaviFlash 里这些值来自 SettingsService（用户可调），本项目把它们
/// 固定为 NaviFlash 的默认值，避免拖一整套设置服务进来。
class UiSettings {
  UiSettings._();

  /// 毛玻璃转场 / iOS 推入动画总开关（frosted_route、ios_backdrop 读取）。
  static const bool heroTransitionBlurEnabled = true;

  /// 着色器级液态玻璃渲染（false 时玻璃组件退化为低保真模式）。
  /// 实际的 ImageFilter.isShaderFilterSupported 检测在 liquid_glass.dart 里做。
  static const bool fragmentRenderingEnabled = true;

  // ---- 液态玻璃默认参数（NaviFlash SettingsService 默认值） ----
  static const double liquidGlassThickness = 20.0;
  static const double liquidGlassBlur = 10.0;
  static const double liquidGlassTintOpacity = 0.0;
  static const double liquidGlassSaturation = 1.0;
  static const double liquidGlassRefractiveIndex = 1.3;
  static const double liquidGlassLightIntensity = 0.0;
  static const double liquidGlassAmbientStrength = 0.0;
  static const double liquidGlassLightAngle = 3.1415926535897932 / 2;
  static const double liquidGlassChromaticAberration = 0.02;
  static const bool liquidGlassMenusDisabled = false;

  /// 底栏果冻变形（masking 高质量）。
  static const bool liquidGlassBottomBarJelly = true;

  /// NaviTabBarViewScrollPhysics 用的弹簧参数。
  static final SpringDescription naviSpringDescription =
      SpringDescription.withDampingRatio(
        mass: 0.6,
        stiffness: 170,
        ratio: 0.86,
      );
}
