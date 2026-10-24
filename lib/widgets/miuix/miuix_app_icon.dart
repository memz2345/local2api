import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

/// miuix 语义图标：优先渲染 Miuix 自带矢量图标，图标集里确实没有对应物时
/// 才回落到 Material 字形。
///
/// 为什么要这层：miuix 的图标是 HyperOS 自己的一套（extended 156 枚、
/// OS4 176 枚），线宽与比喻都跟 Material Icons 不一样。miuix 风格界面里
/// 直接摆 Material 图标，是"看着不像 MIUI"最直接的来源之一。
/// 但两套并不完全重叠（比如 `Icons.stop`、`Icons.bolt` 在 miuix 里没有），
/// 所以这里保留 [fallback]，按语义择优而不是硬凑。
///
/// ## 取色（重要）
///
/// flutter_miuix 的 `MiuixContentColor.of()` 在**找不到祖先时直接返回纯黑**
/// （见其 `miuix_content_color.dart`）。所以裸用 `MiuixIcon(vector: x)` 而不写
/// tint，只要不在 Card / Button / Surface 这类会提供内容色的容器里，
/// **深色模式下就是一颗黑图标**（底栏图标就是这么变黑的）。
///
/// 本封装改成按这个优先级取色，最后两级是关键兜底：
/// 1. 显式传入的 [color]；
/// 2. 祖先 `MiuixContentColor`（存在才算，不复用它那个黑色兜底）；
/// 3. `IconTheme`——miuix 的 NavigationBar / NavigationRail 以及
///    liquid_glass 的 TabBarItem 都是用 `IconTheme` 传状态色和尺寸的；
/// 4. `MiuixTheme.colors.onSurface`。
///
/// 尺寸同理：`size` 为空时读 `IconTheme.size`，读不到才用 [MiuixIcon] 的默认 24。
class MiuixAppIcon extends StatelessWidget {
  /// 按 [name] 从 `MiuixIcons.extended` 取图标。
  const MiuixAppIcon(
    this.name, {
    super.key,
    this.fallback,
    this.size,
    this.color,
  }) : vector = null;

  /// 直接给一个已经解析好的 [MiuixVectorIcon]（调用方已 `byName` 拿过时用）。
  const MiuixAppIcon.vector(
    MiuixVectorIcon this.vector, {
    super.key,
    this.size,
    this.color,
  }) : name = '',
       fallback = null;

  /// `MiuixIcons.extended` 里的图标名（小驼峰，如 `more`、`chevronForward`）。
  final String name;

  /// 直接指定的矢量图标；非空时优先于 [name]。
  final MiuixVectorIcon? vector;

  /// 名称不在 miuix 图标集里、也没给 [vector] 时的 Material 回落字形。
  final IconData? fallback;

  /// 尺寸。`null` 时先读 `IconTheme.size`，再退到 [MiuixIcon] 的默认值。
  final double? size;

  /// 颜色。`null` 时按上面文档里的优先级解析。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved = vector ?? MiuixIcons.extended.byName(name);
    final tint = color ?? miuixAppIconTint(context);
    final iconSize = size ?? IconTheme.of(context).size;

    if (resolved != null) {
      return MiuixIcon(vector: resolved, size: iconSize, tint: tint);
    }
    assert(
      fallback != null,
      'MiuixAppIcon("$name")：miuix 图标集里没有这个名字，必须给 fallback',
    );
    return Icon(fallback, size: iconSize, color: tint);
  }
}

/// [MiuixAppIcon] 用的默认取色：见该类文档里的四级优先级。
Color miuixAppIconTint(BuildContext context) {
  final contentColor = context
      .dependOnInheritedWidgetOfExactType<MiuixContentColor>();
  if (contentColor != null) return contentColor.color;

  final themeColor = IconTheme.of(context).color;
  if (themeColor != null) return themeColor;

  return MiuixTheme.maybeOf(context)?.colors.onSurface ??
      const Color(0xFFFFFFFF);
}

/// 常用图标的语义常量，集中一处便于将来统一换图标。
///
/// 每个值都是 `MiuixIcons.extended` 的名字；名字拼错会在运行时静默回落
/// Material 字形，[MiuixAppIcon] 里的 assert 只覆盖"没给 fallback"的情况，
/// 所以改动这里时请对照 `miuix_extended_icons.dart` 的名单。
abstract final class AppIconNames {
  // ---- 导航（一级页：仪表盘 / 发现 / 设置）----
  /// 仪表盘：网格总览。
  static const dashboard = 'gridView';

  /// 发现：商店语义（挑可安装的配置档案）。
  static const discover = 'store';

  /// 设置。
  static const settings = 'settings';

  // ---- 通用动作 ----
  static const back = 'back';
  static const forward = 'chevronForward';
  static const more = 'more';
  static const add = 'add';
  static const addCircle = 'addCircle';
  static const close = 'close';

  /// 圆形轮廓 + 竖线，实际渲染出来是个**电源符号**（⏻）—— 语义上正好用来
  /// 表示「已停止 / 未启动」。别和 `close`（裸 ×）、`clear`（斜线扫掠形）混。
  static const closeCircle = 'close2';

  static const check = 'ok';
  static const refresh = 'refresh';
  static const delete = 'delete';
  static const edit = 'edit';
  static const copy = 'copy';
  static const paste = 'paste';
  static const link = 'link';
  static const share = 'share';
  static const download = 'download';
  static const upload = 'uploadCloud';
  static const search = 'search';
  static const info = 'info';

  /// 电话（听筒）—— 通话功能与入口按钮用。
  static const phone = 'phone';
  static const help = 'help';
  static const reset = 'reset';
  static const rename = 'rename';
  static const tune = 'tune';
  static const theme = 'theme';
  static const image = 'image';
  static const album = 'album';
  static const play = 'play';
  static const pause = 'pause';
  static const scan = 'scan';
  static const translate = 'translate';
  static const file = 'file';
  static const folder = 'folder';

  /// 便签形 —— 「备注」这类自由文本字段用它。
  static const note = 'notes';
  static const lock = 'lock';
  static const list = 'listView';
  static const sort = 'sort';
  static const update = 'update';
  static const show = 'show';
  static const hide = 'hide';
  static const filter = 'filter';
  static const selectAll = 'selectAll';
  static const report = 'report';
  static const home = 'home';
  static const timer = 'timer';
  static const stopwatch = 'stopwatch';
  static const recent = 'recent';
  static const community = 'community';
  static const store = 'store';
  static const grid = 'gridView';
  static const layers = 'layers';
  static const worldClock = 'worldClock';
  static const cloud = 'cloudFill';
  static const backup = 'backup';
  static const recording = 'recording';
}
