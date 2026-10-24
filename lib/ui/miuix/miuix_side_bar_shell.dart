import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/app_settings.dart';
import 'package:local2api/services/nav_bus.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/ui/home_shell_nav.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';
import 'package:local2api/widgets/page_switcher.dart';

import 'miuix_dashboard_page.dart';
import 'miuix_home_fab.dart';
import 'miuix_profiles_page.dart';
import 'miuix_settings_page.dart';

/// miuix 风格的宽屏主壳：左侧 MiuixNavigationRail + 右侧内容区。
///
/// 与 Material 版 SideBarShell 的差异：HyperOS 的侧栏自带展开/折叠弹簧动画
/// （MiuixNavigationRailState 驱动栏宽、项目布局、选中背景与字号），
/// 不需要自己做宽度补间与 RepaintBoundary 那套防卡死处理。
class MiuixSideBarShell extends StatefulWidget {
  const MiuixSideBarShell({
    super.key,
    required this.controller,
    required this.settings,
  });

  final ServerController controller;
  final AppSettings settings;

  @override
  State<MiuixSideBarShell> createState() => _MiuixSideBarShellState();
}

class _MiuixSideBarShellState extends State<MiuixSideBarShell>
    with PagerJumpGuard<MiuixSideBarShell> {
  /// 初始 tab 从共享值读：窄屏（底栏壳）可能已经切到别的 tab，横屏换成
  /// 本壳时不能写死成 0，否则一转横屏就跳回仪表盘。
  int _index = HomeShellNav.index;

  final MiuixNavigationRailState _rail = MiuixNavigationRailState();
  final MiuixSnackbarHostState _snackbar = MiuixSnackbarHostState();

  /// 与窄屏底栏壳同一套分页控制器：侧栏点击走 `animateToPage`，左右滑动由
  /// `PageView` 驱动，两者共用一个 controller —— 常驻侧栏的切页动画因此和
  /// 底部导航栏完全一致（InstallerX 那边 `HorizontalPager` + `pagerState.animateToPage`
  /// 也是这个做法，宽窄两套壳共用同一个 pager 语义）。
  final PageController _pager = PageController(initialPage: HomeShellNav.index);

  void _onNavigate(int i) {
    if (i == _index) return;
    setState(() {
      _index = i;
    });
    // 写回共享值：转回窄屏时底栏壳据此对齐（见 _MiuixHomeShellState._syncIndexFromNav）。
    HomeShellNav.index = i;
    if (_pager.hasClients) {
      // 1 → 3 这种跨页跳转，PageView 途中会报中间页；[PagerJumpGuard] 把
      // 这些报告吞掉，侧栏高亮只在落到目标页时才跟着动。
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

  @override
  void initState() {
    super.initState();
    // 宽屏时本壳才是可见的那一棵：安卓 Shortcut「发现页」入口等外部切 tab
    // 请求（NavBus）必须在这边也监一份，否则窄屏壳那份只是改了个看不见的
    // _index，横屏点快捷方式没反应（底栏壳那份监听见 _MiuixHomeShellState）。
    NavBus.tabRequest.addListener(_onNavBusTab);
  }

  void _onNavBusTab() {
    final i = NavBus.tabRequest.value.index;
    if (i < 0 || i >= HomeShellNav.tabCount) return;
    _onNavigate(i);
  }

  @override
  void dispose() {
    NavBus.tabRequest.removeListener(_onNavBusTab);
    _pager.dispose();
    _rail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final tabs = [
      (
        label: l10n.navDashboard,
        icon: MiuixIcons.extended.byName(AppIconNames.dashboard)!,
      ),
      (
        label: l10n.navDiscover,
        icon: MiuixIcons.extended.byName(AppIconNames.discover)!,
      ),
      (
        label: l10n.navSettings,
        icon: MiuixIcons.extended.byName(AppIconNames.settings)!,
      ),
    ];

    final pages = [
      MiuixDashboardPage(controller: widget.controller),
      MiuixProfilesPage(controller: widget.controller),
      MiuixSettingsPage(
        controller: widget.controller,
        settings: widget.settings,
      ),
    ];

    // 弹窗根提到壳层：包里的锚点坐标是窗口系（localToGlobal），默认渲染进
    // 页面自己的 MiuixScaffold 弹层宿主（原点在 rail 右侧）会整体偏移 rail
    // 宽度 —— rail 展开越宽偏得越多，菜单直接出屏。把 root 注册表提到这里，
    // MiuixPopupHost 作为壳的根包装器铺满整窗，坐标系重新对齐；遮罩层也
    // 顺理成章盖住 rail（HyperOS 同款）。
    // 页面区再用 LayoutBuilder 覆写 MediaQuery.size：MiuixTopAppBar 用
    // MediaQuery.sizeOf 计算小标题居中位置，页面在 rail 右侧时按全窗宽
    // 居中会偏出页面中心，覆写后顶栏按自身实际宽度居中。
    return MiuixToastScope(
      state: _snackbar,
      child: MiuixPopupScope(
        establishRoot: true,
        child: MiuixPopupHost(
          child: Scaffold(
            backgroundColor: colors.surface,
            floatingActionButton: buildMiuixHomeFab(
              context,
              index: _index,
              controller: widget.controller,
            ),
            body: SafeArea(
              right: false,
              bottom: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MiuixNavigationRail(
                    state: _rail,
                    children: [
                      for (var i = 0; i < tabs.length; i++)
                        MiuixNavigationRailItem(
                          selected: _index == i,
                          onPressed: () => _onNavigate(i),
                          // 走 MiuixAppIcon.vector：它会读 NavigationRailItem 用
                          // IconTheme 传下来的状态色与尺寸（裸 MiuixIcon 会走
                          // MiuixContentColor 的黑色兜底）
                          icon: MiuixAppIcon.vector(tabs[i].icon),
                          label: tabs[i].label,
                        ),
                    ],
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          size: Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          ),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              // 一级页之间做左右平移切换（与窄屏底栏壳同一套），
                              // 不再用瞬切的 IndexedStack；KeepAlivePage 恢复
                              // 原 IndexedStack 的「离屏页也保活」语义（PageView
                              // 默认会回收离屏页，滚动位置与探测结果会丢）。
                              child: guardPagerGestures(
                                PageView(
                                  controller: _pager,
                                  // 手滑切页时同步高亮与共享值（点侧栏那条路径
                                  // 在 _onNavigate 里）；跳页途中路过的中间页
                                  // 不参与，否则中间项会闪一下。
                                  onPageChanged: (i) {
                                    if (ignorePagerReport(i)) return;
                                    if (i == _index) return;
                                    setState(() {
                                      _index = i;
                                      HomeShellNav.index = i;
                                    });
                                  },
                                  children: [
                                    for (final page in pages)
                                      KeepAlivePage(child: page),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: MiuixSnackbarHost(state: _snackbar),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
