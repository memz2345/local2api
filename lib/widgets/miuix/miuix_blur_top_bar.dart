import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:provider/provider.dart';

import '../../services/settings_service.dart';
import '../liquid_glass.dart';
import 'miuix_gradient_blur_top_bar.dart';

/// miuix 顶栏统一壳（一级 / 二级页共用）：毛玻璃 + 大标题折叠模糊，
/// 各页效果与仪表盘 / 发现 / 设置完全一致。
///
/// 两档模糊都跟设置里的「启用模糊」总开关走（[SettingsService.useBlur]），
/// 关掉时整栏回到原版纯色背景。毛玻璃（[MiuixTopAppBar.blurred]）只在
/// 支持着色器滤镜的渲染路径上开（[naviGlassAdvanced]，软渲染模拟器会崩）。
///
/// 「渐变模糊顶栏」（[SettingsService.progressiveTopBar]，AppMarket 同款）
/// 开启时整栏换成透明顶栏 + 顶部渐进模糊带 —— 同样要求模糊开着且渲染路径
/// 支持着色器，条件不满足就退回常规样式。
///
/// 毛玻璃要虚化的是「滚到栏下的内容」，所以顶栏必须画在滚动内容**之上**
/// （MiuixScaffold 的 topBar 正是这样）—— 页面别再用
/// `Column[顶栏, 列表]` 的旧排法，那栏下永远是纯背景，模糊看不见。
class MiuixBlurTopBar extends StatelessWidget {
  const MiuixBlurTopBar({
    super.key,
    required this.title,
    this.navigationIcon,
    this.actions,
    this.scrollBehavior,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String title;
  final Widget? navigationIcon;
  final List<Widget>? actions;
  final MiuixScrollBehavior? scrollBehavior;

  /// 顶栏底色。null = 各页面的出厂底色（`colors.surface`）。
  ///
  /// 传透明色（如扫码页浮在取景画面上）时整栏**全透明只有样式**：
  /// 毛玻璃与大标题模糊一并关掉 —— 背景都没了再糊一层只会更脏。
  final Color? backgroundColor;

  /// 标题颜色（大 / 小标题同用）。透明底栏浮在相机画面上时给
  /// `Colors.white` 之类的亮色，不然浅色主题的深字在取景上看不见。
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final blurOn = _useBlurOf(context);
    // 渐进模糊这一档的门槛与 Material 侧共用一个判断（设置开着 + 渲染路径
    // 跑得动 fragment shader），见 liquid_glass.dart 的 progressiveTopBarOf。
    if (blurOn && progressiveTopBarOf(context)) {
      return MiuixGradientBlurTopBar(
        title: title,
        navigationIcon: navigationIcon,
        actions: actions,
        scrollBehavior: scrollBehavior,
      );
    }
    final transparent = backgroundColor != null;
    return MiuixTopAppBar(
      title: title,
      navigationIcon: navigationIcon,
      actions: actions,
      scrollBehavior: scrollBehavior,
      titleColor: foregroundColor,
      largeTitleColor: foregroundColor,
      // 顶栏底色必须跟页面背景同色，否则未折叠时整条顶栏是一块与页面
      // 不同色的「脏」带（毛玻璃色调同理偏色）。
      //
      // 这里用的是 `surface`，与各 miuix 页面的
      // `MiuixScaffold(containerColor: colors.surface)` 对齐，也正是
      // MiuixScaffold 的出厂默认值。**别再改回 `background`**：
      // HyperOS 静态配色里 `background == surfaceContainer`（深色都是
      // #242424、浅色都是纯白），而 MiuixCard 默认底色就是 surfaceContainer
      // —— 页面一旦用 background，卡片就跟背景糊成一片、主次不分
      // （InstallerX 的页面正是 `surface`：深色纯黑 / 浅色 #F7F7F7）。
      color: backgroundColor ?? MiuixTheme.of(context).colors.surface,
      blurred: blurOn && naviGlassAdvanced && !transparent,
      largeTitleBlurRadius: blurOn && !transparent ? 12 : 0,
    );
  }

  /// 极简测试环境可能没挂 [SettingsService]，读不到就按出厂默认（开）处理。
  static bool _useBlurOf(BuildContext context) {
    try {
      return context.watch<SettingsService>().useBlur;
    } catch (_) {
      return true;
    }
  }
}
