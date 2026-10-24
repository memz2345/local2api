import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/widgets/expressive_app_bar.dart';

import 'dashboard_keys.dart';
import 'dashboard_models.dart';
import 'dashboard_server.dart';
import 'quick_task_actions.dart' show showQuickTaskDialog;

/// 仪表盘：服务控制、上游与对外模型、API 密钥、最近请求合成一屏。
///
/// 分区内容分别在同目录的 dashboard_server / dashboard_models / dashboard_keys
/// 里，这里只负责顺序与滚动容器；整页随 [ServerController] 重建，
/// 卡片内部需要更细粒度的实时值时各自用 ValueListenableBuilder。
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.controller});

  final ServerController controller;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final GlobalKey _upstreamsSectionKey = GlobalKey();
  final GlobalKey _keysSectionKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 把某个分组滚到收起状态钉住的应用栏正下方（状态卡跳转）。
  /// SliverAppBar 折叠后钉住的高度 = 状态栏 + 工具栏。
  void _scrollToSection(GlobalKey key) {
    final targetContext = key.currentContext;
    if (targetContext == null) return;
    final scrollable = Scrollable.maybeOf(targetContext);
    final position = scrollable?.position;
    if (scrollable == null || position == null || !position.hasPixels) return;
    final viewportBox = scrollable.context.findRenderObject() as RenderBox?;
    final targetBox = targetContext.findRenderObject() as RenderBox?;
    if (viewportBox == null ||
        targetBox == null ||
        !targetBox.attached ||
        !viewportBox.attached) {
      return;
    }
    final dy = targetBox.localToGlobal(Offset.zero, ancestor: viewportBox).dy;
    final barInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final target = (position.pixels + dy - barInset).clamp(
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
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => CustomScrollView(
        controller: _scrollController,
        // 状态卡跳转按 GlobalKey 定位分组，缓存区间拉满让全部 sliver
        // 子项常驻构建（仪表盘子项总量有限），折叠区外也拿得到 context。
        scrollCacheExtent: ScrollCacheExtent.pixels(100000),
        slivers: [
          ExpressiveSliverAppBar(
            title: l10n.dashboardTitle,
            // 「任务」= 应用内的快捷任务入口，与 Windows 任务栏跳转列表 /
            // 安卓长按图标那两处是同一份清单（见 quick_actions.dart）。
            // Windows 上弹的是原生 TaskDialog，其它平台是 Material 弹窗。
            actions: [
              MorphIconButton(
                icon: Icons.task_alt,
                tooltip: l10n.tasksDialogTitle,
                transparent: true,
                onTap: () => showQuickTaskDialog(context, widget.controller),
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 110),
            sliver: SliverList.list(
              children: [
                ...serverControlSections(
                  widget.controller,
                  onOpenUpstreams: () => _scrollToSection(_upstreamsSectionKey),
                  onOpenKeys: () => _scrollToSection(_keysSectionKey),
                ),
                ...modelSections(
                  context,
                  widget.controller,
                  upstreamsSectionKey: _upstreamsSectionKey,
                ),
                ...keySections(
                  context,
                  widget.controller,
                  keysSectionKey: _keysSectionKey,
                ),
                recentLogsSection(widget.controller),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
