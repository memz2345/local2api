import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/config_profile.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/lane_probe.dart';
import 'package:local2api/services/chat_simulation.dart';
import 'package:local2api/services/profile_service.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/zen/zen_discovery.dart';
import 'package:local2api/ui/miuix/miuix_chat_simulation_page.dart';
import 'package:local2api/ui/miuix/miuix_profile_json_sheet.dart';
import 'package:provider/provider.dart';

/// miuix 风格的车道列表页（对应 Material 版 `ProfileLanesPage`）。
///
/// 行结构仍照 ClashMetaForAndroid 代理页那套：左边两行文字（车道名 + 结论），
/// 右侧延迟数字，当前链首整行换底色并带勾；行尾开关是「单独对外暴露」。
/// 判定与选择逻辑全走 ProfileService，与 Material 版共用。
class MiuixProfileLanesPage extends StatefulWidget {
  const MiuixProfileLanesPage({
    super.key,
    required this.profile,
    required this.controller,
  });

  final ConfigProfile profile;
  final ServerController controller;

  @override
  State<MiuixProfileLanesPage> createState() => _MiuixProfileLanesPageState();
}

class _MiuixProfileLanesPageState extends State<MiuixProfileLanesPage> {
  /// 二级页统一的可折叠大标题行为；`MiuixBlurTopBar` 读它，
  /// `MiuixScrollBehaviorListener` 在外层把滚动通知喂给它。
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();
  @override
  void initState() {
    super.initState();
    laneProbeResults.addListener(_onResultsChanged);
    // 上游清单变了（探测刚刷新过）也要重画，不能停在旧的车道集合上
    zenDiscovery.addListener(_onResultsChanged);
  }

  @override
  void dispose() {
    _behavior.state.dispose();
    laneProbeResults.removeListener(_onResultsChanged);
    zenDiscovery.removeListener(_onResultsChanged);
    super.dispose();
  }

  void _onResultsChanged() {
    if (mounted) setState(() {});
  }

  bool get _testing => laneProbeResults.isTesting(widget.profile.id);

  List<Upstream> get _installed => [
    for (final u in widget.controller.config.upstreams)
      if (u.managedBy == widget.profile.id) u,
  ];

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

  void _onTapLane(Upstream installed, String lane) {
    final config = widget.controller.config;
    ProfileService.selectLane(config, installed.id, lane);
    widget.controller.store.update(config);
    setState(() {});
  }

  void _onToggleExpose(Upstream installed, String lane, bool on) {
    final config = widget.controller.config;
    ProfileService.setLaneExposed(config, installed.id, lane, on);
    widget.controller.store.update(config);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final installed = _installed;
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
    // 已启用的模型条目；都没装 / 没启用就不给模拟入口。
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

    return Material(
      type: MaterialType.transparency,
      child: MiuixScaffold(
        containerColor: colors.surface,
        topBar: MiuixBlurTopBar(
          scrollBehavior: _behavior,
          title: widget.profile.name,
          navigationIcon: MiuixIconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const MiuixAppIcon(
              AppIconNames.back,
              fallback: Icons.arrow_back,
            ),
          ),
          actions: [
            // 对话模拟：把这一组当成下游客户端聊一轮（走本机代理全链路）
            if (simModel != null)
              buildMiuixChatSimulationAction(
                context: context,
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
            // 通话入口已并入对话模拟页底栏（角色名 + 视频/语音二选一）。
            // 查看 JSON：这一组的有效档案（内置组也能看，标注代码生成）
            MiuixIconButton(
              onPressed: () => showMiuixProfileJsonSheet(
                context,
                widget.profile,
                widget.controller.config,
              ),
              child: const MiuixAppIcon(
                AppIconNames.file,
                fallback: Icons.data_object,
              ),
            ),
            _testing
                ? const SizedBox(
                    width: 40,
                    height: 40,
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  )
                : MiuixIconButton(
                    onPressed: _testAll,
                    child: const Icon(Icons.bolt),
                  ),
          ],
        ),
        floatingActionButton: Tooltip(
          message: l10n.fabDelayTest,
          child: MiuixFloatingActionButton(
            onPressed: _testing ? null : _testAll,
            child: const Icon(Icons.bolt),
          ),
        ),
        // 内容铺满整页、顶栏画在其上；顶栏高度垫进 padding，从栏下穿过。
        content: (padding) => MiuixScrollBehaviorListener(
          behavior: _behavior,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(16, padding.top + 4, 16, 120),
            children: [
              MiuixText(
                upstream == null
                    ? l10n.laneHintNotInstalled
                    : l10n.laneHintRoute,
                fontSize: 12,
                color: colors.onSurfaceVariantSummary,
              ),
              if (selected != null) ...[
                const SizedBox(height: 6),
                MiuixText(
                  l10n.laneFallbackHint(selected),
                  fontSize: 12,
                  color: colors.primary,
                ),
              ],
              const SizedBox(height: 10),
              for (var i = 0; i < lanes.length; i++)
                _MiuixLaneRow(
                  lane: lanes[i],
                  probe: results[i],
                  host: host,
                  current: selected == lanes[i],
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
        ),
      ),
    );
  }
}

/// 一条车道 = 一个代理节点行（miuix 版）。
class _MiuixLaneRow extends StatelessWidget {
  const _MiuixLaneRow({
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
    final colors = MiuixTheme.of(context).colors;
    final p = probe;

    // 分档配色与 Material 版一致：额度打满与地区受限都会自己恢复或换出口就好，
    // 和「这条车道坏了」是三件事，不能糊成同一个红。
    final verdictColor = switch (p?.verdict) {
      LaneVerdict.usable => const Color(0xFF2BA471),
      LaneVerdict.restricted => const Color(0xFFE39A2B),
      LaneVerdict.throttled => const Color(0xFFE2603B),
      LaneVerdict.regionBlocked => const Color(0xFF4C9BD6),
      LaneVerdict.unavailable || LaneVerdict.failed => colors.error,
      _ => colors.onSurfaceVariantSummary,
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
      padding: const EdgeInsets.only(bottom: 8),
      child: MiuixGroupCard(
        insideMargin: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        feedbackType: MiuixPressFeedbackType.sink,
        onPressed: onTap,
        colors: current
            ? MiuixCardColors(
                color: colors.primaryContainer,
                contentColor: colors.onPrimaryContainer,
              )
            : null,
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: current
                  ? Icon(Icons.check, size: 18, color: colors.primary)
                  : null,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MiuixText(
                    lane,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  const SizedBox(height: 2),
                  MiuixText(
                    p?.detail == null || p!.detail!.isEmpty
                        ? subtitle
                        : '$subtitle · ${p.status ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    fontSize: 12,
                    color: current
                        ? colors.onPrimaryContainer
                        : colors.onSurfaceVariantSummary,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            MiuixText(
              delayText,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: p == null ? colors.onSurfaceVariantSummary : verdictColor,
            ),
            if (interactive)
              MiuixSwitch(value: exposed, onChanged: onToggleExpose),
          ],
        ),
      ),
    );
  }
}
