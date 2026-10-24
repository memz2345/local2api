// lib/ui/side_bar_shell.dart
//
// 宽屏 / 横屏主壳（从 NaviFlash SideBarShell 移植的精简版）：
//   - 左侧常驻 CollapsibleSideBar（收起 = M3 竖向导航栏，展开 = 胶囊 list）
//   - 右侧内容卡片：外向圆角 24，四周留空隙露出侧边栏底色
//   - 窄屏（< 768）不使用本组件，走液态玻璃底栏
//   - 整体套 IosBackdropScale：压栈全屏路由时与内容区一起 iOS 景深缩放
import 'package:flutter/material.dart';
import 'package:local2api/services/app_settings.dart';
import 'package:local2api/services/nav_bus.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/widgets/collapsible_side_bar.dart';
import 'package:local2api/widgets/ios_backdrop.dart';
import 'package:local2api/widgets/page_background.dart';
import 'package:local2api/widgets/page_switcher.dart';

import 'dashboard_page.dart';
import 'home_fab.dart';
import 'home_shell_nav.dart';
import 'profiles_page.dart';
import 'settings_page.dart';

/// 宽屏阈值（与 NaviFlash 一致）。
const double kSideBarBreakpoint = 768;

class SideBarShell extends StatefulWidget {
  const SideBarShell({
    super.key,
    required this.controller,
    required this.settings,
  });

  final ServerController controller;
  final AppSettings settings;

  @override
  State<SideBarShell> createState() => _SideBarShellState();
}

class _SideBarShellState extends State<SideBarShell>
    with PagerJumpGuard<SideBarShell> {
  /// 初始 tab 从共享值读：窄屏（底栏壳）可能已经切到别的 tab，横屏换成
  /// 本壳时不能写死成 0，否则一转横屏就跳回仪表盘。
  int _index = HomeShellNav.index;

  /// 与窄屏底栏壳同一套分页控制器：侧栏点击走 `animateToPage`，左右滑动由
  /// `PageView` 驱动，两者共用一个 controller —— 所以常驻侧栏的切页动画和
  /// 底部导航栏完全一致（见 [kPageTransitionDuration] / [kPageTransitionCurve]）。
  final PageController _pager = PageController(initialPage: HomeShellNav.index);

  @override
  void initState() {
    super.initState();
    // 宽屏时本壳才是可见的那一棵：安卓 Shortcut「发现页」入口等外部切 tab
    // 请求（NavBus）必须在这边也监一份，否则窄屏壳的监听只是改了个看不见的
    // _index，横屏点快捷方式没反应（底栏壳那份监听见 _HomeShellState）。
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
    super.dispose();
  }

  void _onNavigate(int i) {
    if (i == _index) return;
    setState(() {
      _index = i;
    });
    // 写回共享值：转回窄屏时底栏壳据此对齐（见 _HomeShellState._syncIndexFromNav）。
    HomeShellNav.index = i;
    if (_pager.hasClients) {
      // 跨页跳转（1 → 3）途中 PageView 会报中间页，[PagerJumpGuard] 把这些
      // 报告吞掉，侧栏高亮只在落到目标页时动。
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pages = [
      DashboardPage(controller: widget.controller),
      ProfilesPage(controller: widget.controller),
      SettingsPage(controller: widget.controller, settings: widget.settings),
    ];

    // 整体背景缩放：压栈全屏路由（显示设置/日志等）时侧边栏与内容区
    // 一起向中心缩小（iOS 景深）。
    // 卡死修复：给侧边栏与内容区各自套 RepaintBoundary，避免宽度动画每帧重绘全树。
    // 外向圆角：内容区为圆角卡片（24px），侧边栏背景透出形成上下外向圆角。
    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      floatingActionButton: buildHomeFab(
        context,
        index: _index,
        controller: widget.controller,
      ),
      body: IosBackdropScale(
        child: ColoredBox(
          // 统一画布：侧边栏（透明）与内容区卡片区分
          color: cs.surfaceContainerLow,
          child: SafeArea(
            top: true,
            bottom: false,
            left: false,
            right: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RepaintBoundary(
                  child: CollapsibleSideBar(
                    currentIndex: _index,
                    onNavigate: _onNavigate,
                  ),
                ),
                // 内容区卡片：外向圆角 24，四周留空隙露出侧边栏底色
                Expanded(
                  child: RepaintBoundary(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: ColoredBox(
                          // 内容区底色用 surfaceContainer，与页面背景 token 对齐
                          //（页面 Scaffold 透明，背景由这层 + PageBackground 提供）
                          color: cs.surfaceContainer,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: PageBackground(
                                  baseColor: cs.surfaceContainer,
                                ),
                              ),
                              // 一级页之间做左右平移切换（与窄屏底栏壳同一套），
                              // 不再用瞬切的 IndexedStack。保活由 KeepAlivePage
                              // 负责：PageView 默认会回收离屏页，滚动位置/探测
                              // 结果会丢，这里恢复原 IndexedStack 的保活语义。
                              Positioned.fill(
                                child: guardPagerGestures(
                                  PageView(
                                    controller: _pager,
                                    // 手滑切页时同步高亮与共享值（点侧栏那条
                                    // 路径在 _onNavigate 里）；跳页途中路过的
                                    // 中间页不参与，否则中间项会闪一下。
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
                                        KeepAlivePage(
                                          child: IosBackdropScale(child: page),
                                        ),
                                    ],
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
