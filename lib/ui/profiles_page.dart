import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/widgets/native_text_context_menu.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/lane_probe.dart';
import 'package:local2api/services/profile_service.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/chat_simulation.dart';
import 'package:local2api/widgets/app_toast.dart';
import 'package:local2api/widgets/expressive_app_bar.dart';
import 'package:local2api/widgets/m3e_pull_to_refresh.dart';
import 'package:local2api/widgets/predictive_back_sheet.dart';
import 'package:provider/provider.dart';

import 'chat_simulation_page.dart';
import 'profile_lanes_page.dart';
import 'upstream_edit_page.dart';
import 'upstream_json_sheet.dart';
import 'widgets/common.dart';

/// 发现页（Material 版，对应 miuix 版 `MiuixProfilesPage`）—— **上游服务列表**。
///
/// 每张卡就是一个 [Upstream]（不是「配置档案」）。改名 / 换地址 / 备注 / 模型
/// 都在上游编辑页里改（与仪表盘「上游服务」卡片的加号是同一个页面），
/// 卡片只负责：看状态（启用开关、备注、模型数、测速结论）+ 快捷动作
/// （编辑 / 测速 / 对话模拟）+ 更多菜单（备注 / JSON / 车道 / 刷新模型 / 删除）。
///
/// 为什么不再列「档案卡」：档案是「一组上游从哪来」的模板，仪表盘的
/// 「上游服务」分区已经在管同一批上游，两处并列就是同一件事画两遍。
/// 档案那套机制（内置 Zen、订阅更新、车道回退链）不动，只是不再单独上台面：
/// 它装出来的上游就在这个列表里，档案级动作收进了卡片的「更多」。
class ProfilesPage extends StatefulWidget {
  const ProfilesPage({super.key, required this.controller});

  final ServerController controller;

  @override
  State<ProfilesPage> createState() => _ProfilesPageState();
}

class _ProfilesPageState extends State<ProfilesPage> {
  bool _updating = false;

  /// 下拉刷新 = 跟上游对账「现在还有哪些模型可用」（补新、摘下架）。
  ///
  /// 只有档案归属的上游有可拉取的清单（自建上游没有订阅端）。
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
      showAppToast(
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
    await pushPage(
      context,
      UpstreamEditPage(controller: widget.controller, upstream: upstream),
    );
    if (mounted) setState(() {});
  }

  /// 备注：卡片上的显式入口（不必进编辑页也能写）。
  Future<void> _editNote(Upstream upstream) async {
    final l10n = AppLocalizations.of(context);
    final ctrl = TextEditingController(text: upstream.note);
    final note = await showAppBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom,
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.upstreamNoteLabel,
                style: Theme.of(
                  sheetCtx,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                // Windows 上右键弹原生编辑菜单
                contextMenuBuilder: textContextMenuBuilder,
                controller: ctrl,
                autofocus: true,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: l10n.upstreamNoteLabel,
                  hintText: l10n.upstreamNoteHint,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(sheetCtx).pop(),
                    child: Text(l10n.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(sheetCtx).pop(ctrl.text.trim()),
                    child: Text(l10n.confirm),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (note == null) return;
    upstream.note = note;
    widget.controller.store.update(widget.controller.config);
    if (mounted) setState(() {});
  }

  Future<void> _delete(Upstream upstream) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l10n.deleteUpstreamConfirm(upstream.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(l10n.deleteBtn),
          ),
        ],
      ),
    );
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
    showAppToast(
      context,
      ok ? l10n.profileModelsRefreshed(1) : l10n.profileModelsRefreshFailed,
      error: !ok,
    );
  }

  /// 卡片「更多」：底部抽屉列动作。
  Future<void> _showActions(ProfileStore store, Upstream upstream) async {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final owner = upstream.managedBy == null
        ? null
        : store.profileOf(upstream.managedBy!);

    await showAppBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  upstream.name,
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: Text(l10n.upstreamNoteLabel),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _editNote(upstream);
                },
              ),
              ListTile(
                leading: const Icon(Icons.data_object),
                title: Text(l10n.profileViewJson),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showUpstreamJsonSheet(context, upstream);
                },
              ),
              // 车道与「刷新模型」只对档案归属的上游有意义：
              // 自建上游没有回退链，也没有可拉取的订阅端。
              if (owner != null) ...[
                ListTile(
                  leading: const Icon(Icons.bolt_outlined),
                  title: Text(l10n.profileLanesAction),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    pushPage(
                      context,
                      ProfileLanesPage(
                        profile: owner,
                        controller: widget.controller,
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: Text(l10n.profileRefreshModels),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _refreshOne(store, upstream);
                  },
                ),
              ],
              ListTile(
                leading: Icon(Icons.delete_outline, color: cs.error),
                title: Text(l10n.deleteBtn, style: TextStyle(color: cs.error)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _delete(upstream);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final store = context.watch<ProfileStore>();
    final upstreams = widget.controller.config.upstreams;

    return AnimatedBuilder(
      // 配置一变就整页重建：开关 / 备注 / 删除改的都是 config.upstreams，
      // 没人重建的话点了开关界面不动（数据其实已经改了）。探测结论同理。
      animation: Listenable.merge([widget.controller, laneProbeResults]),
      builder: (context, _) => M3EPullToRefresh(
        isRefreshing: _updating,
        onRefresh: () => _refreshModels(store),
        // 指示器从折叠顶栏下面滑出来，别压在标题上
        edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight,
        semanticsLabel: l10n.profilePullHint,
        child: CustomScrollView(
          // 下拉靠顶部 overscroll 驱动。**不能**只挂裸的 ClampingScrollPhysics：
          // 上游只有一两条时列表内容比视口短，minScrollExtent == maxScrollExtent，
          // ClampingScrollPhysics.shouldAcceptUserOffset 会直接拒绝这次拖拽，
          // 一个滚动通知都发不出来，下拉刷新就死了（miuix 发现页踩过同一个坑）。
          // AlwaysScrollableScrollPhysics 负责「内容不满屏也接受拖拽」，
          // 它作子级、Clamping 作父级，负责到顶后钳住并派发 OverscrollNotification
          // —— 两者缺一不可，对应 Flutter 官方刷新控件的标准写法。
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          slivers: [
            ExpressiveSliverAppBar(title: l10n.discoverTitle),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
              sliver: SliverList.list(
                children: [
                  if (upstreams.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
                      child: Text(
                        l10n.noUpstreams,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    for (final upstream in upstreams)
                      _UpstreamCard(
                        upstream: upstream,
                        onToggle: (v) => _toggle(upstream, v),
                        onEdit: () => _edit(upstream),
                        onSpeedTest: () => _speedTest(upstream),
                        onChatSim: () {
                          final simModel = _simModelOf(upstream)!;
                          pushPage(
                            context,
                            ChatSimulationPage(
                              controller: widget.controller,
                              model: simModel,
                              groupName: upstream.name,
                              scope: upstream.id,
                              // 组内其它启用模型：模拟页里可把上下文指定给谁
                              groupModels: ChatSimulator.groupModelNamesOf(
                                upstream,
                                simModel,
                              ),
                            ),
                          );
                        },
                        onMore: () => _showActions(store, upstream),
                      ),
                ],
              ),
            ),
          ],
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

/// 一张上游卡：点卡片进编辑页，右上开关管启用/停用，
/// 行尾是测速（闪电）、对话模拟与「更多」。
class _UpstreamCard extends StatelessWidget {
  const _UpstreamCard({
    required this.upstream,
    required this.onToggle,
    required this.onEdit,
    required this.onSpeedTest,
    required this.onChatSim,
    required this.onMore,
  });

  final Upstream upstream;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onSpeedTest;
  final VoidCallback onChatSim;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Tag(
                      label: _typeLabel(l10n, upstream.type),
                      color: cs.primary,
                    ),
                    const Spacer(),
                    // 开关 = 启用 / 停用这一个上游（点卡片本体是进编辑页）。
                    Switch(value: upstream.enabled, onChanged: onToggle),
                    // 闪电 = 测速：探测中换转圈，免得连点重入
                    probing
                        ? const SizedBox(
                            width: 40,
                            height: 40,
                            child: Padding(
                              padding: EdgeInsets.all(10),
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                              ),
                            ),
                          )
                        : IconButton(
                            tooltip: l10n.profileSpeedTest,
                            onPressed: onSpeedTest,
                            icon: const Icon(Icons.bolt, size: 20),
                            color: cs.onSurfaceVariant,
                          ),
                    if (simModel != null)
                      IconButton(
                        tooltip: l10n.chatSimTitle,
                        onPressed: onChatSim,
                        icon: const Icon(Icons.forum_outlined, size: 20),
                        color: cs.onSurfaceVariant,
                      ),
                    IconButton(
                      tooltip: l10n.moreAction,
                      onPressed: onMore,
                      icon: const Icon(Icons.more_horiz, size: 20),
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    upstream.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                // 备注优先：用户写的说明比冷冰冰的地址更能说明「这是个啥」。
                if (upstream.note.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      upstream.note.trim(),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    upstream.baseUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.bolt_outlined,
                      size: 15,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n.modelCountLabel('$modelCount'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    if (probing)
                      Text(
                        l10n.laneProbing,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      )
                    else if (results.isEmpty)
                      Text(
                        l10n.laneUntested,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      )
                    else
                      Row(
                        children: [
                          Text(
                            '$usable/${results.length}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: usable > 0 ? cs.primary : cs.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (fastest != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              '${fastest}ms',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
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

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
