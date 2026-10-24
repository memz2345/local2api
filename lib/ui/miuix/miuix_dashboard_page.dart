import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';

import '../quick_task_actions.dart' show showQuickTaskDialog;
import 'miuix_dashboard_keys.dart';
import 'miuix_dashboard_models.dart';
import 'miuix_dashboard_server.dart';

/// 仪表盘（miuix 版，对应 Material 版 `DashboardPage`）。
///
/// 与 Material 版一样只管顺序与滚动容器，分区内容在
/// miuix_dashboard_server / miuix_dashboard_models / miuix_dashboard_keys 里；
/// 整页随 [ServerController] 重建，卡片内部要更细粒度实时值的仍各自用
/// ValueListenableBuilder。
///
/// 顶栏走 HyperOS 一级页规范：可折叠大标题 + 毛玻璃背景（`blurred: true`，
/// 对应 InstallerX 的 `installerMiuixBlurEffect` 毛玻璃顶栏），布局用包里的
/// [MiuixScaffold]：内容铺满整页、顶栏画在其上，内容滚动时从顶栏下面穿过，
/// BackdropFilter 才有东西可糊；[MiuixScrollBehaviorListener] 把滚动通知喂给
/// behavior（对应 InstallerX 里 `TopAppBar(scrollBehavior)` 配
/// `nestedScroll(scrollBehavior.nestedScrollConnection)` 那一对）。
class MiuixDashboardPage extends StatefulWidget {
  const MiuixDashboardPage({super.key, required this.controller});

  final ServerController controller;

  @override
  State<MiuixDashboardPage> createState() => _MiuixDashboardPageState();
}

class _MiuixDashboardPageState extends State<MiuixDashboardPage> {
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();
  final GlobalKey _upstreamsSectionKey = GlobalKey();
  final GlobalKey _keysSectionKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();

  /// MiuixScaffold 回传的内容内边距；top 即顶栏当前高度（含状态栏），
  /// 状态卡滚动定位时用它把目标行停在毛玻璃顶栏下方而不是钻到栏底下。
  EdgeInsets _contentPadding = EdgeInsets.zero;

  @override
  void dispose() {
    _behavior.state.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 把某个分区滚到顶栏正下方（状态卡的「上游服务 / 密钥」跳转）。
  void _scrollToSection(GlobalKey key) {
    final targetContext = key.currentContext;
    if (targetContext == null) return;
    final scrollable = Scrollable.maybeOf(targetContext);
    final position = scrollable?.position;
    if (scrollable == null || position == null || !position.hasPixels) {
      return;
    }
    final viewportBox = scrollable.context.findRenderObject() as RenderBox?;
    final targetBox = targetContext.findRenderObject() as RenderBox?;
    if (viewportBox == null ||
        targetBox == null ||
        !targetBox.attached ||
        !viewportBox.attached) {
      return;
    }
    final dy = targetBox.localToGlobal(Offset.zero, ancestor: viewportBox).dy;
    final target = (position.pixels + dy - _contentPadding.top).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    position.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MiuixScaffold(
      containerColor: MiuixTheme.of(context).colors.surface,
      topBar: MiuixBlurTopBar(
        title: l10n.dashboardTitle,
        scrollBehavior: _behavior,
        // 与 Material 版同一份「任务」清单（Windows 走原生 TaskDialog，
        // 这里弹 miuix 风格的卡片弹窗）。miuix 顶栏图标不带 tooltip。
        actions: [
          MiuixIconButton(
            onPressed: () => showQuickTaskDialog(context, widget.controller),
            child: const MiuixAppIcon(
              AppIconNames.list,
              fallback: Icons.task_alt,
            ),
          ),
        ],
      ),
      content: (padding) {
        _contentPadding = padding;
        return MiuixScrollBehaviorListener(
          behavior: _behavior,
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) => ListView(
              controller: _scrollController,
              // 折叠量按滚动位置直接映射，必须是 Clamping 才有到顶语义
              physics: const ClampingScrollPhysics(),
              // 状态卡跳转要按 GlobalKey 定位「上游服务 / 密钥」分区，而
              // ListView 默认只构建视口附近的子项，折叠区外的分区拿不到
              // context。仪表盘子项总量有限（就这几个分区），把缓存区间
              // 拉满让全部子项常驻构建，跳转才能定位。
              scrollCacheExtent: ScrollCacheExtent.pixels(100000),
              // 顶栏画在内容之上，这里把顶栏当前高度垫进 padding；
              // 折叠时 padding 跟着收，内容从栏下穿过（InstallerX 同款）。
              padding: EdgeInsets.fromLTRB(16, padding.top, 16, 110),
              children: [
                // 风险提示条：「仪表盘」大标题与出血状态大卡之间（图3 样式，可关闭）
                miuixWarningsTipSection(widget.controller),
                ...miuixServerSections(
                  widget.controller,
                  onOpenUpstreams: () => _scrollToSection(_upstreamsSectionKey),
                  onOpenKeys: () => _scrollToSection(_keysSectionKey),
                ),
                ...miuixModelSections(
                  context,
                  widget.controller,
                  upstreamsSectionKey: _upstreamsSectionKey,
                ),
                ...miuixKeySections(
                  context,
                  widget.controller,
                  keysSectionKey: _keysSectionKey,
                ),
                miuixRecentLogsSection(widget.controller),
              ],
            ),
          ),
        );
      },
    );
  }
}
