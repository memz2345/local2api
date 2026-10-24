import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/app_settings.dart';
import 'package:local2api/services/liquid_glass_bar_service.dart';
import 'package:local2api/services/nav_bus.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/widgets/floating_bottom_bar.dart';
import 'package:local2api/widgets/glass_bottom_bar.dart';
import 'package:local2api/widgets/ios_backdrop.dart';
import 'package:local2api/widgets/page_background.dart';
import 'package:local2api/widgets/page_switcher.dart';
import 'package:provider/provider.dart';

import 'side_bar_shell.dart';
import 'dashboard_page.dart';
import 'home_fab.dart';
import 'home_shell_nav.dart';
import 'profiles_page.dart';
import 'settings_page.dart';

// HomeShellNav 的正式定义搬到了 home_shell_nav.dart（窄/宽两种布局的壳是
// 两棵独立 State，都得住读写它，留在本文件会让 side_bar_shell 反向 import
// 本文件形成环）。这里 re-export，保持既有 `import 'home_shell.dart' show HomeShellNav;`
// 的调用点不用改。
export 'home_shell_nav.dart' show HomeShellNav;

/// 主框架：窄屏 = IndexedStack 三页（仪表盘 / 发现 / 设置）+ 液态玻璃底栏；
/// 宽屏（≥768）= 常驻侧边栏 Shell（NaviFlash 同款）。
///
/// Android 上底栏默认使用平台通道原生底栏（ComposeView 液态玻璃，
/// 见 LiquidGlassBarHost.kt）；show 失败或非 Android 时回退到
/// Flutter 液态玻璃底栏（GlassBottomBar）。
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.controller,
    required this.settings,
  });

  final ServerController controller;
  final AppSettings settings;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with RouteAware {
  int _index = HomeShellNav.index;

  // ---- 原生底栏状态（NaviFlash bilibili_recommend_page 同款同步逻辑） ----
  bool _isTopRoute = true;
  Route<dynamic>? _nativeBarRoute;
  bool _nativeBarShown = false;
  String? _nativeBarSizeKey;
  int? _nativeBarIndex;

  /// 各 tab 页自己的滚动位置（逻辑像素）：IndexedStack 会保留每页位置，
  /// 切页时要把新页的位置告诉原生，补偿才不会拿着上一页的位移去平移。
  ///
  /// 存在 [HomeShellNav] 里：换 UI 引擎会把整棵 shell 换掉，留在本地
  /// State 会连滚动位置一起归零。
  final Map<int, double> _pagePixels = HomeShellNav.pagePixels;

  /// 底栏样式：液态玻璃（默认，原生 ComposeView）/ 普通导航栏 / 悬浮胶囊。
  NavBarStyle get _navBarStyle => context.watch<SettingsService>().navBarStyle;

  bool get _glassEnabled => _navBarStyle == NavBarStyle.glass;

  bool get _useNativeBar => LiquidGlassBarService.canUseNative && _glassEnabled;

  List<GlassBottomBarTab> _tabs(AppLocalizations l10n) => [
    GlassBottomBarTab(
      label: l10n.navDashboard,
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
    ),
    GlassBottomBarTab(
      label: l10n.navDiscover,
      icon: Icons.explore_outlined,
      selectedIcon: Icons.explore,
    ),
    GlassBottomBarTab(
      label: l10n.navSettings,
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
    ),
  ];

  @override
  void initState() {
    super.initState();
    LiquidGlassBarService.bindTabSelected(_onNativeTabTap);
    // 安卓 Shortcut「发现页」入口：请求切到发现 tab
    NavBus.tabRequest.addListener(_onNavBusTab);
  }

  void _onNavBusTab() {
    final i = NavBus.tabRequest.value.index;
    if (i < 0 || i == _index) return;
    _onTabTap(i);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == null || route == _nativeBarRoute) return;
    if (_nativeBarRoute != null) {
      liquidGlassBarRouteObserver.unsubscribe(this);
    }
    _nativeBarRoute = route;
    liquidGlassBarRouteObserver.subscribe(this, route);
    _isTopRoute = route.isCurrent;
  }

  @override
  void didPushNext() {
    // 上面压了新页面：原生底栏收掉
    _isTopRoute = false;
    _hideNativeBottomBar();
  }

  @override
  void didPopNext() {
    _isTopRoute = true;
    if (mounted) setState(() {}); // 触发 build → _syncNativeBottomBar 重新显示
  }

  @override
  void dispose() {
    liquidGlassBarRouteObserver.unsubscribe(this);
    _nativeBarRoute = null;
    _pager.dispose();
    LiquidGlassBarService.unbindTabSelected(_onNativeTabTap);
    NavBus.tabRequest.removeListener(_onNavBusTab);
    if (LiquidGlassBarService.ownsVisibleBar(_onNativeTabTap)) {
      unawaited(LiquidGlassBarService.hide());
    }
    super.dispose();
  }

  /// 一级页共用的分页控制器：底栏点击（含原生底栏回调）走 `animateToPage`，
  /// 左右滑动由 `PageView` 驱动，两者共用同一个 controller，动画一致。
  final PageController _pager = PageController(initialPage: HomeShellNav.index);

  void _onTabTap(int i) {
    if (i == _index) return;
    setState(() {
      _index = i;
      HomeShellNav.index = i;
    });
    if (_pager.hasClients) {
      _pager.animateToPage(
        i,
        duration: kPageTransitionDuration,
        curve: kPageTransitionCurve,
      );
    }
  }

  void _onNativeTabTap(int index) {
    if (index < 0 || index >= _tabs(AppLocalizations.of(context)).length) {
      return;
    }
    _onTabTap(index);
  }

  /// 与 [HomeShellNav.index] 对齐：横屏时页面换成 [SideBarShell]（另一棵 State），
  /// 那边可能已经改过选中 tab；转回窄屏后本地 _index 与分页控制器都得跟上，
  /// 否则会跳回离开前的那一页。
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

  void _hideNativeBottomBar() {
    if (!_nativeBarShown) return;
    _nativeBarShown = false;
    _nativeBarSizeKey = null;
    _nativeBarIndex = null;
    unawaited(LiquidGlassBarService.hide());
  }

  /// 与原生底栏保持同步：显示/换页/尺寸变化时 show 或 updateIndex。
  void _syncNativeBottomBar({required bool visible}) {
    if (!visible || !_isTopRoute) {
      _hideNativeBottomBar();
      return;
    }
    final index = _index;
    final size = MediaQuery.sizeOf(context);
    final key = '${size.width.round()}x${size.height.round()}';
    if (_nativeBarShown &&
        _nativeBarSizeKey == key &&
        _nativeBarIndex == index) {
      return;
    }
    final needShow = !_nativeBarShown || _nativeBarSizeKey != key;
    _nativeBarSizeKey = key;
    _nativeBarIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (needShow) {
        final l10n = AppLocalizations.of(context);
        final ok = await LiquidGlassBarService.show(
          context: context,
          tabs: [
            for (final t in _tabs(l10n))
              LiquidGlassBarTab(
                id: t.label,
                label: t.label,
                icon: t.icon!,
                selectedIcon: t.selectedIcon ?? t.icon,
              ),
          ],
          index: index,
          height: LiquidGlassBarService.barHeight,
          accent: Theme.of(context).colorScheme.primary,
        );
        if (!ok) {
          // 原生底栏不可用：永久回退 Flutter 玻璃底栏
          LiquidGlassBarService.enabled = false;
          if (mounted) setState(() {});
          return;
        }
        _nativeBarShown = true;
      } else {
        // 原生在 updateIndex 里会把旧图作废并立刻重抓一帧
        await LiquidGlassBarService.updateIndex(index);
      }
      LiquidGlassBarService.reportScroll(_pagePixels[index] ?? 0);
    });
  }

  Widget _buildNativeBottomBarSlot() =>
      SizedBox(height: LiquidGlassBarService.slotHeight(context));

  /// 玻璃折射的背景是「抓回来的上一帧」，天生滞后 1~2 帧；把内容的绝对滚动
  /// 位置交给原生，由它在绘制时按「当前位置 - 该帧位置」平移旧图，滚动时
  /// 玻璃里的画面才和身后对得上。重抓本身由逐帧 sync 驱动（见 service）。
  bool _onScrollNotification(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is! ScrollUpdateNotification && n is! ScrollEndNotification) {
      return false;
    }
    final pixels = n.metrics.pixels;
    _pagePixels[_index] = pixels;
    LiquidGlassBarService.reportScroll(pixels);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    // 宽屏 / 横屏：常驻侧边栏（NaviFlash 同款），无底栏
    if (MediaQuery.sizeOf(context).width >= kSideBarBreakpoint) {
      return SideBarShell(
        controller: widget.controller,
        settings: widget.settings,
      );
    }

    final tabs = _tabs(l10n);
    // 从横屏侧栏壳转回来时，先把 tab 位置同步回共享值（详见方法注释）。
    _syncIndexFromNav();
    final pages = [
      DashboardPage(controller: widget.controller),
      ProfilesPage(controller: widget.controller),
      SettingsPage(controller: widget.controller, settings: widget.settings),
    ];

    final useNative = _useNativeBar;
    _syncNativeBottomBar(visible: useNative);

    final Widget bottomBar;
    if (useNative) {
      // 空占位；原生 ComposeView 画真正的底栏
      bottomBar = _buildNativeBottomBarSlot();
    } else if (_navBarStyle == NavBarStyle.floating) {
      // 悬浮胶囊（InstallerX FloatingBottomBar 非玻璃档）：Material 配色注入。
      // Material 侧底栏始终毛玻璃（blur + 半透明色调，与毛玻璃顶栏同参数）。
      bottomBar = SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: FloatingBottomBar(
            blurred: true,
            blurSigma: 12,
            items: [
              for (final t in tabs)
                FloatingBottomBarItem(
                  label: t.label,
                  iconBuilder: (selected) =>
                      Icon(selected ? (t.selectedIcon ?? t.icon) : t.icon),
                ),
            ],
            selectedIndex: _index,
            onSelected: _onTabTap,
            colors: FloatingBottomBarColors(
              containerColor: cs.surfaceContainer.withValues(alpha: 0.72),
              indicatorColor: cs.primary.withValues(alpha: 0.15),
              contentColor: cs.onSurfaceVariant,
              activeContentColor: cs.primary,
            ),
          ),
        ),
      );
    } else if (!_glassEnabled) {
      // 普通导航栏：Material 3 NavigationBar。Material 侧始终毛玻璃
      // （半透明 surfaceContainer 当色调，sigma 与毛玻璃顶栏一致）。
      bottomBar = ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: NavigationBar(
            backgroundColor: cs.surfaceContainer.withValues(alpha: 0.72),
            surfaceTintColor: Colors.transparent,
            selectedIndex: _index,
            onDestinationSelected: _onTabTap,
            destinations: [
              for (final t in tabs)
                NavigationDestination(
                  icon: Icon(t.icon),
                  selectedIcon: t.selectedIcon == null
                      ? null
                      : Icon(t.selectedIcon!),
                  label: t.label,
                ),
            ],
          ),
        ),
      );
    } else {
      // 原生不可用时的回退：Flutter 液态玻璃底栏
      bottomBar = SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: GlassBottomBar(
            tabs: tabs,
            selectedIndex: _index,
            onTabSelected: _onTabTap,
          ),
        ),
      );
    }

    final slotH = useNative ? LiquidGlassBarService.slotHeight(context) : 88.0;

    return Scaffold(
      backgroundColor: cs.surfaceContainer,
      extendBody: true,
      body: Stack(
        children: [
          // NaviFlash 同款页面背景（微渐变画布）
          Positioned.fill(
            child: PageBackground(baseColor: cs.surfaceContainer),
          ),
          Positioned.fill(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
              // 一级页之间做左右平移切换（与 miuix 壳同一套），
              // 不再用瞬切的 IndexedStack。
              child: PageView(
                controller: _pager,
                onPageChanged: (i) => setState(() {
                  _index = i;
                  HomeShellNav.index = i;
                }),
                children: [
                  for (final page in pages)
                    KeepAlivePage(child: IosBackdropScale(child: page)),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: buildHomeFab(
        context,
        index: _index,
        controller: widget.controller,
      ),
      floatingActionButtonLocation: HomeFabAboveBarLocation(slotH),
      bottomNavigationBar: bottomBar,
    );
  }
}
