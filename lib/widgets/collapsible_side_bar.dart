// lib/widgets/collapsible_side_bar.dart
//
// 宽屏 / 横屏侧边栏（从 NaviFlash collapsible_side_bar.dart 移植）：
//   - 固定显示在左侧；收起态 = M3 竖向导航栏（NavigationRail，纯图标），
//     展开态 = Gmail 风格胶囊 list（图标 + 文字，胶囊选中态）
//   - 最顶上 Material 风格 menu 按钮：点击展开（menu → menu_open），
//     再点一下缩回去（menu_open → menu）；图标始终与导航项/列表项对齐
//   - 展开/收起状态全局共享（跨页面一致）并持久化
//   - 点击菜单项不推路由：由宿主切换内容区，无转场动画
//   - 背景色与内容区一致（不画自己的底色，由宿主画布提供），
//     与内容区之间不画分隔线，留空即可
//   - 竖屏（窄屏）不使用本组件，仍走液态玻璃底栏
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/widgets/app_tooltip.dart';

class CollapsibleSideBar extends StatefulWidget {
  /// 当前所在 tab 序号（高亮对应菜单项）。
  final int currentIndex;

  /// 点击菜单项回调（宿主切换内容区，不推路由）。
  final ValueChanged<int> onNavigate;

  const CollapsibleSideBar({
    super.key,
    required this.currentIndex,
    required this.onNavigate,
  });

  // ── 宽度 ──
  /// 收起态宽度 = NavigationRail 的 minWidth（竖向导航栏）。
  static const double minWidth = 80;

  /// 展开态宽度（胶囊 list）。
  static const double expandedWidth = 224;

  /// 展开 / 收起动画时长与曲线（宽度、底部高度共用）。
  static const Duration animDuration = Duration(milliseconds: 260);
  static const Curve animCurve = Curves.easeInOutCubic;

  // ── 展开 / 收起状态：全局共享并持久化（所有页面共用同一个侧边栏状态） ──
  static final ValueNotifier<bool> expanded = ValueNotifier(false);
  static bool _loaded = false;

  /// 从本地恢复展开状态（页面首次构建侧边栏时调用）。
  static Future<void> loadExpandedState() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      expanded.value = prefs.getBool('sideBarExpanded') ?? false;
    } catch (_) {}
  }

  /// 切换展开 / 收起并持久化。
  static Future<void> toggle() async {
    expanded.value = !expanded.value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sideBarExpanded', expanded.value);
    } catch (_) {}
  }

  @override
  State<CollapsibleSideBar> createState() => _CollapsibleSideBarState();
}

class _CollapsibleSideBarState extends State<CollapsibleSideBar> {
  @override
  void initState() {
    super.initState();
    CollapsibleSideBar.loadExpandedState();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: CollapsibleSideBar.expanded,
      builder: (context, isExpanded, _) {
        // 用 RepaintBoundary 隔离侧边栏宽度动画，避免每帧重绘右侧 IndexedStack 内容
        return RepaintBoundary(
          child: AnimatedContainer(
            duration: CollapsibleSideBar.animDuration,
            curve: CollapsibleSideBar.animCurve,
            width: isExpanded
                ? CollapsibleSideBar.expandedWidth
                : CollapsibleSideBar.minWidth,
            // 背景色与内容区保持一致（宿主画布统一提供），不画自己的底色
            color: Colors.transparent,
            // 关键：动画期间 width 从 80→224 渐变，但 child（展开态完整内容）
            // 在 isExpanded 翻 true 的瞬间就立即切换，需要 ~224 才放得下；
            // 若不裁剪，动画前期 width 还停在 80 时，展开态 Row 可用宽度
            // 仅 20（80 - padding），会触发 RenderFlex overflow（黄黑条纹）
            clipBehavior: Clip.hardEdge,
            // 收起 = 竖向导航栏；展开 = 胶囊 list；用 Key 避免动画期间子树复用导致的布局抖动
            child: KeyedSubtree(
              key: ValueKey(isExpanded),
              child: isExpanded
                  ? _buildExpandedList(cs, l10n)
                  : _buildCollapsedRail(cs, l10n),
            ),
          ),
        );
      },
    );
  }

  List<(IconData, IconData, String)> _tabs(AppLocalizations l10n) => [
    (Icons.dashboard_outlined, Icons.dashboard, l10n.navDashboard),
    (Icons.explore_outlined, Icons.explore, l10n.navDiscover),
    (Icons.settings_outlined, Icons.settings, l10n.navSettings),
  ];

  /// 收起态：极简竖栏（顶部 menu，导航图标纵列沉底）。
  Widget _buildCollapsedRail(ColorScheme cs, AppLocalizations l10n) {
    final tabs = _tabs(l10n);
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: CollapsibleSideBar.minWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 最顶部：menu 胶囊按钮 ──
            // 锚点：按钮居中于 80 宽竖栏 → 左边距 (80-44)/2 = 18，图标
            // 中心 x = 40，top = 安全区 + 8。展开态的 menu_open 按钮
            // 按同一锚点逐像素对位，收起/展开切换时按钮原位不变。
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: CollapsibleSideBar.minWidth,
                    height: 44,
                    child: Center(
                      child: _CapsuleIconButton(
                        icon: Icons.menu,
                        tooltip: l10n.sideBarExpand,
                        onTap: CollapsibleSideBar.toggle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(),
            // ── 底部导航：图标纵列 ──
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < tabs.length; i++) ...[
                    if (i > 0) const SizedBox(height: 6),
                    _CollapsedNavItem(
                      icon: tabs[i].$2,
                      outlinedIcon: tabs[i].$1,
                      label: tabs[i].$3,
                      isSelected: widget.currentIndex == i,
                      onTap: () => widget.onNavigate(i),
                    ),
                  ],
                ],
              ),
            ),
            // 底部安全区占位
            SafeArea(top: false, child: const SizedBox(height: 4)),
          ],
        ),
      ),
    );
  }

  /// 展开态：Gmail 风格胶囊 list。
  Widget _buildExpandedList(ColorScheme cs, AppLocalizations l10n) {
    final tabs = _tabs(l10n);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 顶部：胶囊 menu 按钮（与收起态逐像素对位） ──
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: _CapsuleIconButton(
                    icon: Icons.menu_open,
                    tooltip: l10n.sideBarCollapse,
                    onTap: CollapsibleSideBar.toggle,
                  ),
                ),
              ),
            ),
          ),
        ),
        // ── 胶囊 list ──
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
            children: [
              for (var i = 0; i < tabs.length; i++)
                _gmailCapsuleItem(
                  cs,
                  icon: tabs[i].$1,
                  selectedIcon: tabs[i].$2,
                  title: tabs[i].$3,
                  tabIndex: i,
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 展开态胶囊：紧凑胶囊（回退贴边，宽自适应文字结束，非全宽拉伸）。
  Widget _gmailCapsuleItem(
    ColorScheme cs, {
    required IconData icon,
    required IconData selectedIcon,
    required String title,
    required int tabIndex,
  }) {
    final isSelected = widget.currentIndex == tabIndex;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: AnimatedContainer(
          duration: CollapsibleSideBar.animDuration,
          curve: CollapsibleSideBar.animCurve,
          decoration: BoxDecoration(
            color: isSelected ? cs.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(28),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                if (tabIndex == widget.currentIndex) return;
                widget.onNavigate(tabIndex);
              },
              borderRadius: BorderRadius.circular(28),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 图标：空心/实心交叉淡入淡出 + 颜色过渡（与收起态
                    // 导航项同款 M3 动画），避免硬切
                    AnimatedSwitcher(
                      duration: kThemeAnimationDuration,
                      switchInCurve: Curves.easeInOutCubicEmphasized,
                      switchOutCurve: Curves.easeInOutCubicEmphasized.flipped,
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: Icon(
                        key: ValueKey<bool>(isSelected),
                        isSelected ? selectedIcon : icon,
                        size: 22,
                        color: isSelected
                            ? cs.onPrimaryContainer
                            : cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Flexible(
                      // 文字颜色/字重随选中态平滑过渡（AnimatedDefaultTextStyle）
                      child: AnimatedDefaultTextStyle(
                        duration: kThemeAnimationDuration,
                        curve: Curves.easeInOutCubicEmphasized,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected
                              ? cs.onPrimaryContainer
                              : cs.onSurfaceVariant,
                        ),
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 收起态底部单项：选中时 primaryContainer 胶囊 + 下方文字，未选中仅图标。
///
/// 选中胶囊直接复用 SDK 的 [NavigationIndicator]（NavigationRail /
/// NavigationBar 的 M3 选中指示器就是它），拿到与原生完全一致的动画：
///   - 出现：胶囊从 40% 宽沿 X 轴弹性放大到 100%（easeInOutCubicEmphasized）
///     + 100ms 淡入；消失：反向缩小 + 淡出；
///   - 尺寸 56×32 / Stadium 与 NavigationRail 的 M3 指示器规格一致。
class _CollapsedNavItem extends StatefulWidget {
  final IconData icon;
  final IconData outlinedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CollapsedNavItem({
    required this.icon,
    required this.outlinedIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_CollapsedNavItem> createState() => _CollapsedNavItemState();
}

class _CollapsedNavItemState extends State<_CollapsedNavItem>
    with SingleTickerProviderStateMixin {
  /// 指示器动画：与 NavigationRail 完全相同的驱动方式——200ms
  /// （kThemeAnimationDuration）线性 controller，选中 forward / 取消选中
  /// reverse，emphasized 曲线由 NavigationIndicator 内部叠加（照抄原生
  /// navigation_rail.dart 的 _initControllers + didUpdateWidget 逻辑）。
  /// ⚠️ 在 initState 里创建（惰性 late 字段会在 dispose 首访时去查已失效的
  /// TickerMode 祖先）。
  late final AnimationController _indicatorController;

  @override
  void initState() {
    super.initState();
    _indicatorController = AnimationController(
      duration: kThemeAnimationDuration,
      vsync: this,
      value: widget.isSelected ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(_CollapsedNavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected != oldWidget.isSelected) {
      // NavigationRail 同款：新选中项 forward，失焦项 reverse
      widget.isSelected
          ? _indicatorController.forward()
          : _indicatorController.reverse();
    }
  }

  @override
  void dispose() {
    _indicatorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selectedBg = cs.primaryContainer;
    final selectedFg = cs.onPrimaryContainer;
    // 图标：空心/实心字形交叉淡入淡出 + 颜色随选中态 200ms 过渡
    // （M3 emphasized 曲线），避免"啪"一下硬切
    final iconWidget = AnimatedSwitcher(
      duration: kThemeAnimationDuration,
      switchInCurve: Curves.easeInOutCubicEmphasized,
      switchOutCurve: Curves.easeInOutCubicEmphasized.flipped,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: Icon(
        key: ValueKey<bool>(widget.isSelected),
        widget.isSelected ? widget.icon : widget.outlinedIcon,
        size: 24,
        color: widget.isSelected ? selectedFg : cs.onSurfaceVariant,
      ),
    );
    // 56×32 胶囊盒：指示器（Ink，画在下方 Material 的 ink 层）与图标
    // 叠放。胶囊由 Ink 绘制后，波纹/高亮出现在胶囊之上、图标之下
    // （原生 NavigationBar 的层序）。水波纹只圈住 56×32 胶囊本身
    // （M3 NavigationRail 同款），不包住下方文字。
    final pill = SizedBox(
      width: 56,
      height: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          NavigationIndicator(
            animation: _indicatorController,
            color: selectedBg,
            width: 56,
            height: 32,
            shape: const StadiumBorder(),
          ),
          iconWidget,
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(16),
                child: pill,
              ),
            ),
            // 仅选中项显示文字，未选中只显示图标；AnimatedSize 让文字
            // 出现/消失有高度过渡，TweenAnimationBuilder 再补一个淡入，
            // 不会瞬间跳位
            AnimatedSize(
              duration: CollapsibleSideBar.animDuration,
              curve: CollapsibleSideBar.animCurve,
              alignment: Alignment.topCenter,
              child: widget.isSelected && widget.label.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: kThemeAnimationDuration,
                        curve: Curves.easeInOutCubicEmphasized,
                        builder: (context, opacity, child) =>
                            Opacity(opacity: opacity, child: child),
                        child: Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                            height: 1,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox(height: 2),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部 menu 按钮：无背景，仅图标 + Tooltip。
/// 容器固定 44×44 正圆（CircleBorder 裁剪 + 圆形水波纹）。
class _CapsuleIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _CapsuleIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppTooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 22, color: cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
