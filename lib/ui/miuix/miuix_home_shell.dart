import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/app_settings.dart';
import 'package:local2api/services/nav_bus.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/widgets/floating_bottom_bar.dart';
import 'package:local2api/widgets/liquid_glass.dart' show naviGlassAdvanced;
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/page_switcher.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';
import 'package:provider/provider.dart';

import '../home_fab.dart' show HomeFabAboveBarLocation;
import '../home_shell_nav.dart';
import 'miuix_dashboard_page.dart';
import 'miuix_home_fab.dart';
import 'miuix_profiles_page.dart';
import 'miuix_settings_page.dart';
import 'miuix_side_bar_shell.dart';

/// 宽屏阈值，与 Material 壳保持一致。
const double kMiuixSideBarBreakpoint = 768;

/// 普通导航栏（MiuixNavigationBar）分支的槽高给 FAB 抬升与 snackbar 让位用。
/// 与 Material 壳回退到 Flutter 底栏时的 88.0 保持一致。
const double kMiuixBarSlot = 88.0;

/// 玻璃底栏（MiuixGlassNavigationBar）分支的固定槽高：栏高 54 + 底边距 10 +
/// 顶部呼吸 6；系统手势条 inset 由 FAB 定位时另加（见 build 里的 slotH）。
const double kMiuixGlassBarSlot = 70.0;

/// 悬浮胶囊底栏分支的固定槽高：栏高 64 + 底边距 10 + 顶部呼吸 4。
const double kMiuixFloatingBarSlot = 78.0;

/// miuix 风格的主框架（对应 InstallerX 的 `MiuixMainPageWrapper`）。
///
/// 三个一级页（仪表盘 / 发现 / 设置）都是 miuix 实现，各自渲染 miuix 顶栏。
///
/// 底栏（SettingsService.navBarStyle 三选一）：
/// - **液态玻璃（默认）**：flutter_miuix 自带的 [MiuixGlassNavigationBar] ——
///   与 compose-miuix-ui 同一份 GlassNavigationBar.kt 的 Flutter 移植
///   （胶囊玻璃 + 指示器弹簧拖动 + show/hide 模糊动画）。玻璃要折射的
///   背景由 [MiuixLayerBackdropCapture] 实时捕获整棵页面内容（含滚到栏下的
///   部分），经 [MiuixLayerBackdrop] 喂给栏体取样。着色器不可用的软渲染
///   （模拟器）上退回普通栏，跟顶栏毛玻璃的开关同一个理由。
/// - **悬浮**：InstallerX `FloatingBottomBar`（非玻璃档）同款实色胶囊，
///   配色取 miuix 主题（surfaceContainer / primary）。
/// - **普通**：miuix 自带的 MiuixNavigationBar（HyperOS 分栏样式）。
class MiuixHomeShell extends StatefulWidget {
  const MiuixHomeShell({
    super.key,
    required this.controller,
    required this.settings,
  });

  final ServerController controller;
  final AppSettings settings;

  @override
  State<MiuixHomeShell> createState() => _MiuixHomeShellState();
}

class _MiuixHomeShellState extends State<MiuixHomeShell>
    with PagerJumpGuard<MiuixHomeShell> {
  // 位置存 [HomeShellNav]（跨 UI 引擎共享）：换风格时本 shell 会被整棵换掉，
  // 留在本地 State 就「一切风格就跳回仪表盘页」了。Material 壳读的是同一份。
  int _index = HomeShellNav.index;

  /// 一级页共用的分页控制器。底栏点击走 `animateToPage`，左右滑动由
  /// `PageView` 自己驱动 —— 两者共用同一个 controller，所以「点底栏」和
  /// 「手滑」的动画完全一致（对应 InstallerX 的 `mainPagerState.animateToPage`）。
  final PageController _pager = PageController(initialPage: HomeShellNav.index);

  final MiuixSnackbarHostState _snackbar = MiuixSnackbarHostState();

  /// 玻璃底栏的背景提供者：捕获对象在 build 里登记，栏体按全局坐标取样。
  final MiuixLayerBackdrop _backdrop = MiuixLayerBackdrop();

  bool get _glassWanted =>
      context.watch<SettingsService>().navBarStyle == NavBarStyle.glass;

  bool get _floatingWanted =>
      context.watch<SettingsService>().navBarStyle == NavBarStyle.floating;

  /// 玻璃底栏真正可用 = 设置开了 + 渲染路径支持着色器滤镜（软渲染模拟器
  /// 上 MiuixTextureBlur 会崩，与顶栏毛玻璃同一个开关）。
  bool get _useGlassBar => _glassWanted && naviGlassAdvanced;

  /// 悬浮 / 普通底栏的毛玻璃：跟「启用模糊」总开关走（顶栏同款效果，
  /// blur + tint），软渲染上同样不开（BackdropFilter 会崩）。
  bool get _barBlur =>
      context.watch<SettingsService>().useBlur && naviGlassAdvanced;

  ({String label, MiuixVectorIcon icon}) _tabInfo(
    int index,
    AppLocalizations l10n,
  ) => switch (index) {
    0 => (
      label: l10n.navDashboard,
      icon: MiuixIcons.extended.byName(AppIconNames.dashboard)!,
    ),
    1 => (
      label: l10n.navDiscover,
      icon: MiuixIcons.extended.byName(AppIconNames.discover)!,
    ),
    _ => (
      label: l10n.navSettings,
      icon: MiuixIcons.extended.byName(AppIconNames.settings)!,
    ),
  };

  int get _tabCount => 3;

  @override
  void initState() {
    super.initState();
    // 安卓 Shortcut「发现页」入口：请求切到发现 tab
    NavBus.tabRequest.addListener(_onNavBusTab);
  }

  void _onNavBusTab() {
    final i = NavBus.tabRequest.value.index;
    if (i < 0 || i == _index) return;
    _onTabTap(i);
  }

  @override
  void dispose() {
    _pager.dispose();
    _backdrop.dispose();
    NavBus.tabRequest.removeListener(_onNavBusTab);
    super.dispose();
  }

  void _onTabTap(int i) {
    if (i == _index) return;
    // 先切高亮（底栏立刻响应），再让分页滑过去。
    setState(() {
      _index = i;
      HomeShellNav.index = i;
    });
    if (_pager.hasClients) {
      // 1 → 3 跳页途中 PageView 会报中间页，[PagerJumpGuard] 吞掉这些报告，
      // 底栏只在落到目标页时才改高亮。
      beginPagerJump(i);
      _pager
          .animateToPage(
            i,
            duration: kPageTransitionDuration,
            curve: kPageTransitionCurve,
          )
          .whenComplete(endPagerJump);
    }
  }

  /// 与 [HomeShellNav.index] 对齐：横屏时页面换成 [MiuixSideBarShell]（另一棵
  /// State），那边可能已经改过选中 tab；转回窄屏后本地 _index 与分页控制器
  /// 都得跟上，否则会跳回离开前的那一页。
  ///
  /// 只在 build 的窄屏分支里调用：宽屏分支整棵交给侧栏壳，本 State 的
  /// _index / _pager 处在「冻结」状态，不该被牵动。
  void _syncIndexFromNav() {
    final nav = HomeShellNav.index;
    if (nav == _index) return;
    _index = nav;
    final pager = _pager;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (pager.hasClients && pager.page?.round() != nav) {
        pager.jumpToPage(nav);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;

    if (MediaQuery.sizeOf(context).width >= kMiuixSideBarBreakpoint) {
      return MiuixSideBarShell(
        controller: widget.controller,
        settings: widget.settings,
      );
    }

    final useGlass = _useGlassBar;
    final useFloating = _floatingWanted && !useGlass;
    // 从横屏侧栏壳转回来时，先把 tab 位置同步回共享值（详见方法注释）。
    _syncIndexFromNav();

    final pages = [
      MiuixDashboardPage(controller: widget.controller),
      MiuixProfilesPage(controller: widget.controller),
      MiuixSettingsPage(
        controller: widget.controller,
        settings: widget.settings,
      ),
    ];

    final Widget bottomBar;
    if (useGlass) {
      // miuix 玻璃底栏（compose-miuix-ui 的 Flutter 移植版）：胶囊玻璃浮在
      // 内容上，背景用 [MiuixLayerBackdropCapture] 抓到的实时快照折射。
      bottomBar = SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: MiuixGlassNavigationBar(
            backdrop: _backdrop,
            items: [
              for (var i = 0; i < _tabCount; i++)
                MiuixGlassNavigationItem(
                  label: _tabInfo(i, l10n).label,
                  icon: MiuixAppIcon.vector(_tabInfo(i, l10n).icon),
                ),
            ],
            selectedIndex: _index,
            onSelect: _onTabTap,
          ),
        ),
      );
    } else if (useFloating) {
      // 悬浮胶囊（InstallerX FloatingBottomBar 非玻璃档）：miuix 配色注入。
      // 开模糊时胶囊变毛玻璃（blur + 半透明色调，顶栏同款）。
      final blur = _barBlur;
      bottomBar = SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: FloatingBottomBar(
            blurred: blur,
            blurSigma: 10.8,
            items: [
              for (var i = 0; i < _tabCount; i++)
                FloatingBottomBarItem(
                  label: _tabInfo(i, l10n).label,
                  iconBuilder: (selected) => MiuixAppIcon.vector(
                    _tabInfo(i, l10n).icon,
                    // 矢量图标不吃 IconTheme 的状态色，这里直接给。
                    color: selected
                        ? colors.primary
                        : colors.onSurfaceVariantActions,
                  ),
                ),
            ],
            selectedIndex: _index,
            onSelected: _onTabTap,
            colors: FloatingBottomBarColors(
              containerColor: blur
                  ? colors.surfaceContainer.withValues(alpha: 0.65)
                  : colors.surfaceContainer,
              indicatorColor: colors.primary.withValues(alpha: 0.15),
              contentColor: colors.onSurface,
              activeContentColor: colors.primary,
            ),
          ),
        ),
      );
    } else {
      // 普通导航栏：miuix 自带分栏底栏。开模糊时整条栏毛玻璃
      // （BackdropFilter 罩住含手势条 inset 的整块，半透明 surface 当色调）。
      final blur = _barBlur;
      final bar = MiuixNavigationBar(
        color: blur ? colors.surface.withValues(alpha: 0.6) : null,
        children: [
          for (var i = 0; i < _tabCount; i++)
            MiuixNavigationBarItem(
              selected: _index == i,
              onPressed: () => _onTabTap(i),
              icon: MiuixAppIcon.vector(_tabInfo(i, l10n).icon),
              label: _tabInfo(i, l10n).label,
            ),
        ],
      );
      bottomBar = blur
          ? ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10.8, sigmaY: 10.8),
                child: bar,
              ),
            )
          : bar;
    }

    final slotH = useGlass
        ? MediaQuery.paddingOf(context).bottom + kMiuixGlassBarSlot
        : useFloating
        ? MediaQuery.paddingOf(context).bottom + kMiuixFloatingBarSlot
        : kMiuixBarSlot;

    return MiuixToastScope(
      state: _snackbar,
      child: Scaffold(
        backgroundColor: colors.surface,
        // 内容要铺到底栏下面，玻璃才有东西可折射
        extendBody: true,
        body: MiuixLayerBackdropCapture(
          backdrop: _backdrop,
          child: Stack(
            children: [
              Positioned.fill(
                // 一级页之间做左右平移切换（对应 InstallerX 的 HorizontalPager），
                // 不再用瞬切的 IndexedStack。
                child: guardPagerGestures(
                  PageView(
                    controller: _pager,
                    // 跳页途中路过的中间页不参与高亮同步（否则底栏中间项会
                    // 闪一下）；手滑切页照常跟随。
                    onPageChanged: (i) {
                      if (ignorePagerReport(i)) return;
                      if (i == _index) return;
                      setState(() {
                        _index = i;
                        HomeShellNav.index = i;
                      });
                    },
                    children: [
                      // 保活：PageView 默认会回收离屏页，滚动位置/探测结果会丢，
                      // 这里强制 keep-alive，保持原来 IndexedStack 的语义。
                      for (final page in pages) KeepAlivePage(child: page),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                // 抬到底栏上方，别被玻璃栏压住
                bottom: slotH,
                child: MiuixSnackbarHost(state: _snackbar),
              ),
            ],
          ),
        ),
        floatingActionButton: buildMiuixHomeFab(
          context,
          index: _index,
          controller: widget.controller,
        ),
        floatingActionButtonLocation: HomeFabAboveBarLocation(slotH),
        bottomNavigationBar: bottomBar,
      ),
    );
  }
}
