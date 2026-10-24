import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField;
import 'package:local2api/widgets/miuix/miuix_text_field.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/lane_probe.dart';
import 'package:local2api/services/chat_simulation.dart';
import 'package:local2api/services/profile_service.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/widgets/miuix/miuix_bottom_sheet.dart';
import 'package:local2api/widgets/miuix/miuix_dialog.dart'
    show confirmDeleteUpstream;
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';
import 'package:provider/provider.dart';

import 'miuix_chat_simulation_page.dart' show pushMiuixChatSimulation;
import 'miuix_profile_lanes_page.dart';
import 'miuix_upstream_edit_page.dart';
import 'miuix_upstream_json_sheet.dart';

/// 发现页（miuix 版，对应 Material 版 `ProfilesPage`）—— **上游服务列表**。
///
/// 每张卡就是一个 [Upstream]（不是「配置档案」）。改名 / 换地址 / 备注 / 模型
/// 都在上游编辑页里改（与仪表盘「上游服务」卡片的加号是同一个页面），
/// 卡片本身只负责：看状态（启用开关、备注、模型数、测速结论）+ 三个快捷动作
/// （编辑 / 测速 / 对话模拟）+ 更多菜单（备注 / JSON / 车道 / 刷新模型 / 删除）。
///
/// 为什么不再列「档案卡」：档案是「一组上游从哪来」的模板，仪表盘的
/// 「上游服务」分区已经在管同一批上游，两处并列就是同一件事画两遍。
/// 档案那套机制（内置 Zen、订阅更新、车道回退链）不动，只是不再单独上台面：
/// 它装出来的上游就在这个列表里，档案级动作收进了卡片的「更多」。
///
/// 顶栏走 HyperOS 一级页规范（可折叠大标题 [MiuixTopAppBar] + 毛玻璃），
/// 下拉刷新拉的是「档案归属上游的可用模型清单」（与 Material 版共用
/// [ProfileService.refreshModelLists]）。
class MiuixProfilesPage extends StatefulWidget {
  const MiuixProfilesPage({super.key, required this.controller});

  final ServerController controller;

  @override
  State<MiuixProfilesPage> createState() => _MiuixProfilesPageState();
}

class _MiuixProfilesPageState extends State<MiuixProfilesPage> {
  bool _updating = false;

  /// 一级页的可折叠大标题行为。同时喂给 [MiuixTopAppBar] 与
  /// [MiuixPullToRefresh.topAppBarScrollBehavior] —— 后者是 InstallerX
  /// （`PullToRefresh(topAppBarScrollBehavior = scrollBehavior)`）的规范接线，
  /// 让下拉与顶栏折叠共用同一个 behavior。
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();

  @override
  void dispose() {
    _behavior.state.dispose();
    super.dispose();
  }

  /// 下拉刷新 = 跟上游对账「现在还有哪些模型可用」（补新、摘下架）。
  ///
  /// 只有档案归属的上游有可拉取的清单（自建上游没有订阅端）；一个都没有时
  /// 直接不跑，别让用户白等一次网络超时。
  Future<void> _refreshModels(ProfileStore store) async {
    if (_updating) return;
    setState(() => _updating = true);
    try {
      final n = await ProfileService.refreshModelLists(
        store: store,
        config: widget.controller.config,
      );
      widget.controller.store.update(widget.controller.config);
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      showMiuixToast(
        context,
        n > 0
            ? l10n.profileModelsRefreshed(n)
            : l10n.profileModelsRefreshFailed,
        error: n == 0,
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  /// 闪电 = 测速：把这一个上游声明的车道逐条实打一遍，结论落在
  /// laneProbeResults 上（卡片读它）。key 用上游 id，卡片据此显示「探测中」。
  Future<void> _speedTest(Upstream upstream) => LaneProbeService.probe(
    key: upstream.id,
    baseUrl: upstream.baseUrl,
    apiKey: upstream.apiKey,
    lanes: _laneNamesOf(upstream),
  );

  void _toggle(Upstream upstream, bool value) {
    upstream.enabled = value;
    widget.controller.store.update(widget.controller.config);
  }

  Future<void> _edit(Upstream upstream) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MiuixUpstreamEditPage(
          controller: widget.controller,
          upstream: upstream,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// 备注：卡片上的显式入口（不必进编辑页也能写）。
  Future<void> _editNote(Upstream upstream) async {
    final l10n = AppLocalizations.of(context);
    final ctrl = TextEditingController(text: upstream.note);
    final note = await showMiuixBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                  child: MiuixText(
                    l10n.upstreamNoteLabel,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                MiuixTextField(
                  controller: ctrl,
                  label: l10n.upstreamNoteHint,
                  useLabelAsPlaceholder: true,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 4,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    MiuixTextButton(
                      l10n.cancel,
                      onPressed: () => Navigator.of(sheetCtx).pop(),
                    ),
                    const SizedBox(width: 12),
                    MiuixTextButton(
                      l10n.confirm,
                      onPressed: () =>
                          Navigator.of(sheetCtx).pop(ctrl.text.trim()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (note == null) return;
    upstream.note = note;
    widget.controller.store.update(widget.controller.config);
    if (mounted) setState(() {});
  }

  /// 删除：确认框走 [confirmDeleteUpstream]（与上游编辑页同一份）。
  Future<void> _delete(Upstream upstream) async {
    final ok = await confirmDeleteUpstream(context, upstream.name);
    if (ok != true || !mounted) return;
    widget.controller.config.upstreams.remove(upstream);
    widget.controller.store.update(widget.controller.config);
    if (mounted) setState(() {});
  }

  /// 只刷这一个上游（档案归属）的可用模型列表。
  Future<void> _refreshOne(ProfileStore store, Upstream upstream) async {
    final profileId = upstream.managedBy;
    if (profileId == null) return;
    final ok = await ProfileService.refreshModelListOf(
      store: store,
      config: widget.controller.config,
      profileId: profileId,
    );
    widget.controller.store.update(widget.controller.config);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    showMiuixToast(
      context,
      ok ? l10n.profileModelsRefreshed(1) : l10n.profileModelsRefreshFailed,
      error: !ok,
    );
  }

  /// 卡片右上「更多」：miuix 没有命令式菜单入口，用底部抽屉列动作。
  Future<void> _showActions(ProfileStore store, Upstream upstream) async {
    final l10n = AppLocalizations.of(context);
    final owner = upstream.managedBy == null
        ? null
        : store.profileOf(upstream.managedBy!);

    await showMiuixBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: MiuixText(
                    upstream.name,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                _SheetAction(
                  iconName: AppIconNames.edit,
                  fallbackIcon: Icons.edit_outlined,
                  label: l10n.upstreamNoteLabel,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _editNote(upstream);
                  },
                ),
                _SheetAction(
                  iconName: AppIconNames.file,
                  fallbackIcon: Icons.data_object,
                  label: l10n.profileViewJson,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    showMiuixUpstreamJsonSheet(context, upstream);
                  },
                ),
                // 车道与「刷新模型」只对档案归属的上游有意义：
                // 自建上游没有回退链，也没有可拉取的订阅端。
                if (owner != null) ...[
                  _SheetAction(
                    iconName: AppIconNames.layers,
                    fallbackIcon: Icons.bolt_outlined,
                    label: l10n.profileLanesAction,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => MiuixProfileLanesPage(
                            profile: owner,
                            controller: widget.controller,
                          ),
                        ),
                      );
                    },
                  ),
                  _SheetAction(
                    iconName: AppIconNames.scan,
                    fallbackIcon: Icons.sync,
                    label: l10n.profileRefreshModels,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _refreshOne(store, upstream);
                    },
                  ),
                ],
                _SheetAction(
                  iconName: AppIconNames.delete,
                  fallbackIcon: Icons.delete_outline,
                  label: l10n.deleteBtn,
                  danger: true,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _delete(upstream);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final store = context.watch<ProfileStore>();
    final upstreams = widget.controller.config.upstreams;

    // 与仪表盘同构：MiuixScaffold 让内容铺满整页、毛玻璃顶栏画在其上，
    // 滚动内容从栏下穿过；下拉刷新头用 contentPadding 平移到栏下方。
    return MiuixScaffold(
      containerColor: MiuixTheme.of(context).colors.surface,
      topBar: MiuixBlurTopBar(
        title: l10n.discoverTitle,
        scrollBehavior: _behavior,
      ),
      content: (padding) => MiuixScrollBehaviorListener(
        behavior: _behavior,
        child: AnimatedBuilder(
          // 配置一变就整页重建：开关 / 备注 / 删除改的都是 config.upstreams，
          // 没人重建的话点了开关界面不动（数据其实已经改了）。探测结论同理。
          animation: Listenable.merge([widget.controller, laneProbeResults]),
          builder: (context, _) => MiuixPullToRefresh(
            isRefreshing: _updating,
            onRefresh: () => _refreshModels(store),
            topAppBarScrollBehavior: _behavior,
            contentPadding: EdgeInsets.only(top: padding.top),
            refreshTexts: [
              l10n.miuixPullToRefresh,
              l10n.miuixReleaseToRefresh,
              l10n.miuixRefreshing,
              l10n.miuixRefreshDone,
            ],
            child: ListView(
              // 下拉靠顶部 overscroll 驱动。这里**不能**用裸的
              // ClampingScrollPhysics：上游只有一两条时列表内容比视口短，
              // minScrollExtent == maxScrollExtent，ClampingScrollPhysics 的
              // shouldAcceptUserOffset 会直接拒绝这次拖拽，一个通知都发不出来，
              // 下拉刷新就死了（实测就是这样）。
              // AlwaysScrollableScrollPhysics 负责「内容不满屏也接受拖拽」，
              // 显式挂 Clamping 作父级负责「到顶后钳住并派发 OverscrollNotification」
              // —— 两者缺一不可，对应 Flutter 官方刷新控件的标准写法。
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(16, padding.top + 4, 16, 110),
              children: [
                if (upstreams.isEmpty)
                  MiuixGroupCard(
                    insideMargin: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: MiuixText(
                      l10n.noUpstreams,
                      fontSize: 13,
                      color: MiuixTheme.of(
                        context,
                      ).colors.onSurfaceVariantSummary,
                    ),
                  )
                else
                  for (final upstream in upstreams)
                    _MiuixUpstreamCard(
                      controller: widget.controller,
                      upstream: upstream,
                      onToggle: (v) => _toggle(upstream, v),
                      onEdit: () => _edit(upstream),
                      onSpeedTest: () => _speedTest(upstream),
                      onMore: () => _showActions(store, upstream),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 这一个上游声明的车道名（跨模型条目去重、保序）。
List<String> _laneNamesOf(Upstream upstream) =>
    <String>{for (final m in upstream.models) ...m.attempts}.toList();

/// 对话模拟要用的对外名：优先路由条目（对外一个名字、内部回退链），
/// 否则第一个启用的模型条目；都没有就不给模拟入口。
String? _simModelOf(Upstream upstream) {
  for (final m in upstream.models) {
    if (ProfileService.isRoute(m)) return m.publicName;
  }
  for (final m in upstream.models) {
    if (m.enabled) return m.publicName;
  }
  return null;
}

/// 一张上游卡：
/// 头行 = 名称 + 类型标签 + 启用开关；中段是备注与地址；再下面是模型数、
/// 测速结论与更新时间；底部一排圆形动作按钮（编辑 / 测速 / 对话模拟）。
class _MiuixUpstreamCard extends StatelessWidget {
  const _MiuixUpstreamCard({
    required this.controller,
    required this.upstream,
    required this.onToggle,
    required this.onEdit,
    required this.onSpeedTest,
    required this.onMore,
  });

  final ServerController controller;
  final Upstream upstream;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onSpeedTest;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;

    final lanes = _laneNamesOf(upstream);
    final results = laneProbeResults
        .forLanes(lanes)
        .whereType<LaneProbe>()
        .toList();
    final usable = results.where((p) => p.verdict == LaneVerdict.usable).length;
    final fastest = results
        .where((p) => p.verdict == LaneVerdict.usable && p.delayMs != null)
        .fold<int?>(
          null,
          (a, p) => a == null || p.delayMs! < a ? p.delayMs : a,
        );
    final probing = laneProbeResults.isTesting(upstream.id);
    final modelCount = upstream.models.where((m) => m.enabled).length;
    final simModel = _simModelOf(upstream);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: MiuixGroupCard(
        insideMargin: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        feedbackType: MiuixPressFeedbackType.sink,
        onPressed: onEdit,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头行：名字 + 类型标签在左，启用开关放行尾。
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      MiuixText(
                        upstream.name,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                      _MiuixTag(
                        label: _typeLabel(l10n, upstream.type),
                        color: colors.primary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                MiuixSwitch(value: upstream.enabled, onChanged: onToggle),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 1,
              color: colors.onSurface.withValues(alpha: 0.08),
            ),
            const SizedBox(height: 12),
            // 备注优先：用户写的说明比冷冰冰的地址更能说明「这是个啥」。
            if (upstream.note.trim().isNotEmpty) ...[
              MiuixText(
                upstream.note.trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                color: colors.onSurface,
              ),
              const SizedBox(height: 4),
            ],
            MiuixText(
              upstream.baseUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              fontSize: 12,
              fontFamily: 'monospace',
              color: colors.onSurfaceVariantSummary,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                MiuixAppIcon(
                  AppIconNames.layers,
                  fallback: Icons.bolt_outlined,
                  size: 15,
                  color: colors.onSurfaceVariantSummary,
                ),
                const SizedBox(width: 4),
                MiuixText(
                  l10n.modelCountLabel('$modelCount'),
                  fontSize: 12,
                  color: colors.onSurfaceVariantSummary,
                ),
                const Spacer(),
                if (probing)
                  MiuixText(
                    l10n.laneProbing,
                    fontSize: 12,
                    color: colors.onSurfaceVariantSummary,
                  )
                else if (results.isEmpty)
                  MiuixText(
                    l10n.laneUntested,
                    fontSize: 12,
                    color: colors.onSurfaceVariantSummary,
                  )
                else
                  Row(
                    children: [
                      MiuixText(
                        '$usable/${results.length}',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: usable > 0 ? colors.primary : colors.error,
                      ),
                      if (fastest != null) ...[
                        const SizedBox(width: 8),
                        MiuixText(
                          '${fastest}ms',
                          fontSize: 12,
                          color: colors.onSurfaceVariantSummary,
                        ),
                      ],
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _MiuixRoundActionButton(
                  tooltip: l10n.editUpstream,
                  onPressed: onEdit,
                  child: MiuixAppIcon(
                    AppIconNames.edit,
                    fallback: Icons.edit_outlined,
                    size: 20,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(width: 10),
                // 闪电 = 测速：探测中换成转圈，避免连点重入。
                if (probing)
                  const _MiuixRoundActionButton(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                  )
                else
                  _MiuixRoundActionButton(
                    tooltip: l10n.fabDelayTest,
                    onPressed: onSpeedTest,
                    child: Icon(Icons.bolt, size: 20, color: colors.onSurface),
                  ),
                if (simModel != null) ...[
                  const SizedBox(width: 10),
                  _MiuixRoundActionButton(
                    tooltip: l10n.chatSimTitle,
                    onPressed: () => pushMiuixChatSimulation(
                      context,
                      controller: controller,
                      model: simModel,
                      groupName: upstream.name,
                      scope: upstream.id,
                      // 组内其它启用模型：模拟页里可把上下文指定给谁
                      groupModels: ChatSimulator.groupModelNamesOf(
                        upstream,
                        simModel,
                      ),
                    ),
                    child: const MiuixAppIcon(
                      AppIconNames.recent,
                      fallback: Icons.forum_outlined,
                      size: 20,
                    ),
                  ),
                  // 通话入口已并入对话模拟页底栏（那边有角色名与视频/语音
                  // 二选一，比这里的裸入口信息全）。
                ],
                const Spacer(),
                _MiuixRoundActionButton(
                  tooltip: l10n.moreAction,
                  onPressed: onMore,
                  child: const MiuixAppIcon(
                    AppIconNames.more,
                    fallback: Icons.more_horiz,
                    size: 20,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 类型标签文案。
String _typeLabel(AppLocalizations l10n, UpstreamType type) => switch (type) {
  UpstreamType.openai => l10n.typeOpenai,
  UpstreamType.anthropic => l10n.typeAnthropic,
  UpstreamType.llamacpp => l10n.typeLlamacpp,
  UpstreamType.ollama => l10n.typeOllama,
  UpstreamType.localTts => l10n.typeLocalTts,
};

/// 圆形灰底动作按钮（与档案卡时期同款：浅灰圆底 + 深色图标）。
class _MiuixRoundActionButton extends StatelessWidget {
  const _MiuixRoundActionButton({
    required this.child,
    this.tooltip,
    this.onPressed,
  });

  final Widget child;
  final String? tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = MiuixTheme.of(context).brightness == Brightness.dark;
    final button = Material(
      color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF2F2F2),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(width: 40, height: 40, child: Center(child: child)),
      ),
    );
    final tip = tooltip;
    return tip == null ? button : Tooltip(message: tip, child: button);
  }
}

/// 抽屉里的一行动作。
class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.iconName,
    required this.fallbackIcon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  /// miuix 图标名（`MiuixIcons.extended`）。
  final String iconName;

  /// miuix 图标集里没有对应物时的 Material 回落字形。
  final IconData fallbackIcon;

  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final tint = danger ? colors.error : colors.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MiuixGroupCard(
        insideMargin: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        feedbackType: MiuixPressFeedbackType.sink,
        onPressed: onTap,
        child: Row(
          children: [
            MiuixAppIcon(
              iconName,
              fallback: fallbackIcon,
              size: 20,
              color: tint,
            ),
            const SizedBox(width: 12),
            MiuixText(label, color: tint),
          ],
        ),
      ),
    );
  }
}

class _MiuixTag extends StatelessWidget {
  const _MiuixTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // MIUI 的连续圆角（squircle）用在所有形状上，即便是 6px 的小标签
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.14),
        shape: MiuixSquircleBorder(cornerRadius: 6),
      ),
      child: MiuixText(
        label,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    );
  }
}
