import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/config_profile.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/lane_probe.dart';
import 'package:local2api/services/chat_simulation.dart';
import 'package:local2api/services/profile_service.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/zen/zen_discovery.dart';
import 'package:local2api/ui/chat_simulation_page.dart';
import 'package:local2api/ui/profile_json_sheet.dart';
import 'package:local2api/widgets/expressive_app_bar.dart';
import 'package:local2api/widgets/frosted_page_bar.dart';
import 'package:provider/provider.dart';

/// 车道列表页：照 ClashMetaForAndroid 代理页（design_proxy.xml + ProxyView.kt）
/// 的行结构搬过来 —— 左边两行文字（节点名 + 说明），右侧居中一个延迟数字，
/// 当前选中的整行换底色并带勾；闪电按钮同时放在工具栏和右下角 FAB，
/// 两处都是「测全部」。工具栏那个在测试期间换成进度圈，和 CMFA 的
/// url_test_view / url_test_progress_view 互换一致。
///
/// 旧版把「上游预设」和「路由策略」拆成两页、点一行有两种含义；
/// 现在一个档案一页，点行 = 选为回退链链首，行尾开关 = 这条车道是否单独对外暴露。
class ProfileLanesPage extends StatefulWidget {
  const ProfileLanesPage({
    super.key,
    required this.profile,
    required this.controller,
  });

  final ConfigProfile profile;
  final ServerController controller;

  @override
  State<ProfileLanesPage> createState() => _ProfileLanesPageState();
}

class _ProfileLanesPageState extends State<ProfileLanesPage> {
  @override
  void initState() {
    super.initState();
    laneProbeResults.addListener(_onResultsChanged);
    // 上游清单变了（探测刚刷新过）也要重画，不能停在旧的车道集合上。
    zenDiscovery.addListener(_onResultsChanged);
  }

  @override
  void dispose() {
    laneProbeResults.removeListener(_onResultsChanged);
    zenDiscovery.removeListener(_onResultsChanged);
    super.dispose();
  }

  void _onResultsChanged() {
    if (mounted) setState(() {});
  }

  bool get _testing => laneProbeResults.isTesting(widget.profile.id);

  /// 这个档案装进配置的上游。没激活过就是空。
  List<Upstream> get _installed => [
    for (final u in widget.controller.config.upstreams)
      if (u.managedBy == widget.profile.id) u,
  ];

  /// 本次实际生效的车道集合：装了就用配置里的，没装退回文档声明的。
  List<String> _lanesFor(Upstream? installed) {
    if (installed == null) {
      return <String>{
        for (final t in widget.profile.upstreams)
          ...ProfileService.effectiveLanes(t),
      }.toList();
    }
    return <String>{for (final m in installed.models) ...m.attempts}.toList();
  }

  Future<void> _testAll() async {
    if (_testing) return;
    await ProfileService.probeProfile(
      store: context.read<ProfileStore>(),
      config: widget.controller.config,
      profileId: widget.profile.id,
    );
  }

  /// 点一行 = 选这个节点：把它提到回退链链首，其余按原顺序跟在后面。
  void _onTapLane(Upstream installed, String lane) {
    final config = widget.controller.config;
    ProfileService.selectLane(config, installed.id, lane);
    widget.controller.store.update(config);
    setState(() {});
  }

  /// 行尾开关 = 这条车道要不要单独对外暴露（除了走容灾路由之外）。
  void _onToggleExpose(Upstream installed, String lane, bool on) {
    final config = widget.controller.config;
    ProfileService.setLaneExposed(config, installed.id, lane, on);
    widget.controller.store.update(config);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final installed = _installed;
    // 多上游档案目前只有内置那一份，且它就一个上游；取首个即可，
    // 真出现多个时其余的仍能在「模型」页管理。
    final upstream = installed.isEmpty ? null : installed.first;
    final lanes = _lanesFor(upstream);
    final results = laneProbeResults.forLanes(lanes);
    final host =
        Uri.tryParse(
          upstream?.baseUrl ?? widget.profile.upstreams.first.baseUrl,
        )?.host ??
        '';
    final selected = upstream == null
        ? null
        : ProfileService.selectedLaneOf(widget.controller.config, upstream.id);
    // 对话模拟要请求的对外名：优先容灾路由（zen-free 那种），否则第一个
    // 已启用的模型条目；都没装/没启用就没有模拟入口。
    final simModel = upstream == null
        ? null
        : (ProfileService.primaryRouteOf(
                widget.controller.config,
                upstream.id,
              )?.publicName ??
              upstream.models
                  .where((m) => m.enabled)
                  .map((m) => m.publicName)
                  .firstOrNull);

    return FrostedBarPage(
      title: widget.profile.name,
      collapseOnScroll: false,
      actions: [
        // 对话模拟：把这一组当成下游客户端聊一轮（走本机代理全链路）
        if (simModel != null)
          MorphIconButton(
            icon: Icons.forum_outlined,
            tooltip: l10n.chatSimTitle,
            transparent: true,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ChatSimulationPage(
                  controller: widget.controller,
                  model: simModel,
                  groupName: widget.profile.name,
                  scope: widget.profile.id,
                  // simModel 非空则上游必已装上；带上组内其它可换模型
                  groupModels: ChatSimulator.groupModelNamesOf(
                    upstream!,
                    simModel,
                  ),
                ),
              ),
            ),
          ),
        // 查看 JSON：这一组的有效档案（内置组也能看，标注代码生成）
        MorphIconButton(
          icon: Icons.data_object,
          tooltip: l10n.profileViewJson,
          transparent: true,
          onTap: () => showProfileJsonSheet(
            context,
            widget.profile,
            widget.controller.config,
          ),
        ),
        // 工具栏闪电：测试中换成进度圈（CMFA 的 url_test_view / progress 互换）
        if (_testing)
          const SizedBox(
            width: 40,
            height: 40,
            child: Padding(
              padding: EdgeInsets.all(10),
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          )
        else
          MorphIconButton(
            icon: Icons.bolt,
            tooltip: l10n.fabDelayTest,
            transparent: true,
            onTap: _testAll,
          ),
      ],
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.fabDelayTest,
        onPressed: _testing ? null : _testAll,
        child: const Icon(Icons.bolt),
      ),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          frostedPageBarInset(context) + 8,
          16,
          120,
        ),
        children: [
          Text(
            upstream == null ? l10n.laneHintNotInstalled : l10n.laneHintRoute,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (selected != null) ...[
            const SizedBox(height: 6),
            Text(
              l10n.laneFallbackHint(selected),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
          const SizedBox(height: 10),
          for (var i = 0; i < lanes.length; i++)
            _LaneRow(
              lane: lanes[i],
              probe: results[i],
              host: host,
              current: selected == lanes[i],
              // 没装进配置就没得选也没得暴露
              interactive: upstream != null,
              exposed:
                  upstream != null &&
                  ProfileService.isLaneExposed(
                    widget.controller.config,
                    upstream.id,
                    lanes[i],
                  ),
              onTap: upstream == null
                  ? null
                  : () => _onTapLane(upstream, lanes[i]),
              onToggleExpose: upstream == null
                  ? null
                  : (on) => _onToggleExpose(upstream, lanes[i], on),
            ),
        ],
      ),
    );
  }
}

/// 一条车道 = 一个代理节点行。
class _LaneRow extends StatelessWidget {
  const _LaneRow({
    required this.lane,
    required this.probe,
    required this.current,
    required this.host,
    required this.interactive,
    required this.exposed,
    required this.onTap,
    required this.onToggleExpose,
  });

  final String lane;
  final LaneProbe? probe;
  final bool current;
  final String host;
  final bool interactive;
  final bool exposed;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onToggleExpose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final p = probe;

    final verdictColor = switch (p?.verdict) {
      LaneVerdict.usable => Colors.green,
      LaneVerdict.restricted => Colors.orange,
      LaneVerdict.throttled => Colors.deepOrange,
      // 地区受限只说明本机出口被拦，不是车道坏了，别涂成错误色。
      LaneVerdict.regionBlocked => Colors.lightBlue,
      LaneVerdict.unavailable || LaneVerdict.failed => cs.error,
      _ => cs.onSurfaceVariant,
    };
    final delayText = (p?.delayMs == null) ? '–' : '${p!.delayMs}ms';
    final subtitle = switch (p) {
      null => host,
      _ => switch (p.verdict) {
        LaneVerdict.usable => l10n.laneUsable,
        LaneVerdict.restricted => l10n.laneRestricted,
        LaneVerdict.throttled => l10n.laneThrottled,
        LaneVerdict.regionBlocked => l10n.laneRegionBlocked,
        LaneVerdict.unavailable => l10n.laneUnavailable,
        LaneVerdict.unreachable => l10n.laneNetUnreachable,
        _ => l10n.laneFailed,
      },
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: current ? cs.secondaryContainer : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: current
                      ? Icon(
                          Icons.check,
                          size: 18,
                          color: cs.onSecondaryContainer,
                        )
                      : null,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lane,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: current
                              ? cs.onSecondaryContainer
                              : cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        p?.detail == null || p!.detail!.isEmpty
                            ? subtitle
                            : '$subtitle · ${p.status ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: current
                              ? cs.onSecondaryContainer.withValues(alpha: .75)
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  delayText,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w600,
                    color: p == null ? cs.onSurfaceVariant : verdictColor,
                  ),
                ),
                if (interactive)
                  Switch(value: exposed, onChanged: onToggleExpose),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
