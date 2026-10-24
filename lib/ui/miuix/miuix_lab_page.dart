// lib/ui/miuix/miuix_lab_page.dart
//
// 实验室（miuix 版，对应 Material 版 `ui/lab_page.dart`）。
//
// 信息架构按「设置页」那一套来：一行一个服务开关，下一行是同卡片的
// 「更多设置」箭头行（`MiuixArrowPreference`，箭头右对齐、和设置页完全一致）。
// 早期自绘的 `_LabNavRow` 已撤掉 —— 它的箭头和标题挤在一起，和设置页不齐。
//
// 当前内容：
//   · Node.js 运行时（Android）—— 先装运行时，下面的服务才跑得起来；
//   · SillyTavern —— Node.js，zip 安装；
//   · DeepSeek Harness（dsh）—— Node.js，npm 安装，模型由本应用写入配置。
//
// 安装位置 / Node 检测 / 卸载 / API 配置这些细节都在各自的「更多设置」页；
// 业务状态在 [NodeRuntimeService] / [SillyTavernService] / [DshService]
// 单例里，本页只负责渲染。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../l10n/app_localizations.dart';
import '../../services/lab/dsh_service.dart';
import '../../services/lab/node_runtime_service.dart';
import '../../services/lab/shizuku_service.dart';
import '../../services/lab/silly_tavern_service.dart';
import '../../services/server_controller.dart';
import '../../widgets/miuix/miuix_app_icon.dart';
import '../../widgets/miuix/miuix_blur_top_bar.dart';
import '../../widgets/miuix/miuix_bottom_sheet.dart';
import '../../widgets/miuix/miuix_dialog.dart';
import '../../widgets/miuix/miuix_group_card.dart';
import '../../widgets/miuix/miuix_scroll_behavior.dart';
import '../../widgets/miuix/miuix_toast.dart';
import '../widgets/common.dart' show pushPage;
import '../widgets/lab_status.dart';

import 'miuix_dsh_page.dart';
import 'miuix_lab_sillytavern_page.dart';

class MiuixLabPage extends StatefulWidget {
  const MiuixLabPage({super.key, this.controller});

  /// 代理服务总控：API 配置要把端口 / 密钥读出来。测试里可以不给。
  final ServerController? controller;

  @override
  State<MiuixLabPage> createState() => _MiuixLabPageState();
}

class _MiuixLabPageState extends State<MiuixLabPage> {
  final SillyTavernService _st = SillyTavernService.instance;
  final DshService _dsh = DshService.instance;
  final NodeRuntimeService _node = NodeRuntimeService.instance;
  final ShizukuService _shizuku = ShizukuService.instance;

  bool? _shizukuOk;
  bool? _shizukuGranted;

  /// 二级页统一的可折叠大标题行为（内容不满一屏也要能上拉折叠，
  /// 见 [MiuixShortPageScrollBehavior] 的说明）。
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();

  @override
  void initState() {
    super.initState();
    _st.init();
    _dsh.init();
    _node.init();
    _refreshShizuku();
  }

  Future<void> _refreshShizuku() async {
    if (!_shizuku.isAndroid) return;
    final ok = await _shizuku.ping();
    final granted = ok ? await _shizuku.isGranted() : false;
    if (!mounted) return;
    setState(() {
      _shizukuOk = ok;
      _shizukuGranted = granted;
    });
  }

  Future<void> _requestShizuku() async {
    final l10n = AppLocalizations.of(context);
    final granted = await _shizuku.requestPermission();
    if (!mounted) return;
    showMiuixToast(
      context,
      granted ? l10n.labShizukuGranted : l10n.labShizukuNotGranted,
      error: !granted,
    );
    await _refreshShizuku();
  }

  Future<void> _pickRunnerMode() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showMiuixBottomSheet<NodeRunnerMode>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in NodeRunnerMode.values)
              MiuixRadioButtonPreference(
                title: mode == NodeRunnerMode.direct
                    ? l10n.labRunnerDirect
                    : l10n.labRunnerShizuku,
                summary: mode == NodeRunnerMode.direct
                    ? l10n.labRunnerDirectDesc
                    : l10n.labRunnerShizukuDesc,
                selected: mode == _node.runnerMode,
                radioButtonLocation: MiuixRadioButtonLocation.end,
                onClick: () => Navigator.of(sheetContext).pop(mode),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _node.setRunnerMode(picked);
    await _refreshShizuku();
  }

  /// 下载镜像选择（apt 源 + npm registry）。
  Future<void> _pickMirror() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showMiuixBottomSheet<NodeDownloadMirror>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mirror in NodeDownloadMirror.values)
              MiuixRadioButtonPreference(
                title: mirror == NodeDownloadMirror.official
                    ? l10n.labMirrorOfficial
                    : l10n.labMirrorCn,
                summary: mirror == NodeDownloadMirror.official
                    ? l10n.labMirrorOfficialDesc
                    : l10n.labMirrorCnDesc,
                selected: mirror == _node.mirror,
                radioButtonLocation: MiuixRadioButtonLocation.end,
                onClick: () => Navigator.of(sheetContext).pop(mirror),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _node.setMirror(picked);
  }

  @override
  void dispose() {
    _behavior.state.dispose();
    super.dispose();
  }

  Future<void> _openStSettings() =>
      pushPage(context, MiuixLabSillyTavernPage(controller: widget.controller));

  Future<void> _openDshSettings() =>
      pushPage(context, MiuixDshPage(controller: widget.controller));

  Future<void> _onToggleSt(bool value) async {
    final l10n = AppLocalizations.of(context);
    if (value && !_st.installed) {
      // 没装就拨开关：别假装成功，直接引到「更多设置」里安装。
      final go = await showMiuixDialog<bool>(
        context: context,
        title: l10n.labInstallFirstTitle,
        message: l10n.labInstallFirstBody,
        actions: [
          MiuixDialogAction(
            label: l10n.labCancel,
            onPressed: (dialogContext) =>
                Navigator.of(dialogContext).pop(false),
          ),
          MiuixDialogAction(
            label: l10n.labGoSettings,
            primary: true,
            onPressed: (dialogContext) => Navigator.of(dialogContext).pop(true),
          ),
        ],
      );
      if (go == true && mounted) await _openStSettings();
      return;
    }
    final ok = await _st.setEnabled(value);
    if (!mounted || ok == value) return;
    showMiuixToast(
      context,
      _st.error == 'missingNode' ? l10n.labNodeMissing : l10n.labStartFailed,
      error: true,
    );
  }

  Future<void> _onToggleDsh(bool value) async {
    final l10n = AppLocalizations.of(context);
    if (value && !_dsh.installed) {
      final go = await showMiuixDialog<bool>(
        context: context,
        title: l10n.labDshInstallFirstTitle,
        message: l10n.labDshInstallFirstBody,
        actions: [
          MiuixDialogAction(
            label: l10n.labCancel,
            onPressed: (dialogContext) =>
                Navigator.of(dialogContext).pop(false),
          ),
          MiuixDialogAction(
            label: l10n.labGoSettings,
            primary: true,
            onPressed: (dialogContext) => Navigator.of(dialogContext).pop(true),
          ),
        ],
      );
      if (go == true && mounted) await _openDshSettings();
      return;
    }
    final ok = await _dsh.setEnabled(value);
    if (!mounted || ok == value) return;
    showMiuixToast(
      context,
      _dsh.error == 'missingNode' ? l10n.labNodeMissing : l10n.labStartFailed,
      error: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    return AnimatedBuilder(
      animation: Listenable.merge([_st, _dsh, _node]),
      builder: (context, _) => Material(
        type: MaterialType.transparency,
        child: MiuixScaffold(
          containerColor: colors.surface,
          topBar: MiuixBlurTopBar(
            title: l10n.labTitle,
            scrollBehavior: _behavior,
            navigationIcon: MiuixIconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const MiuixAppIcon(
                AppIconNames.back,
                fallback: Icons.arrow_back,
              ),
            ),
          ),
          content: (padding) => MiuixShortPageScrollListener(
            behavior: _behavior,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(16, padding.top + 8, 16, 40),
              children: [
                MiuixSmallTitle(l10n.labLocalServices),
                const SizedBox(height: 10),
                if (Platform.isAndroid) ...[
                  _buildNodeRuntimeCard(l10n, colors),
                  const SizedBox(height: 22),
                ],
                _buildStCard(l10n, colors),
                const SizedBox(height: 22),
                _buildDshCard(l10n, colors),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Node 状态副标题见 `widgets/lab_status.dart`（两套 UI 共用）。

  Widget _buildNodeRuntimeCard(AppLocalizations l10n, MiuixColors colors) {
    final node = _node;
    final shizukuMode = node.runnerMode == NodeRunnerMode.shizuku;
    final shizukuSummary = _shizukuOk == null || _shizukuOk == false
        ? l10n.labShizukuNotDetected
        : _shizukuGranted == true
        ? l10n.labShizukuGranted
        : l10n.labShizukuNotGranted;
    return MiuixGroupCard(
      insideMargin: EdgeInsets.zero,
      child: Column(
        children: [
          MiuixBasicComponent(
            title: l10n.labNodeRuntimeTitle,
            summary: l10n.labNodeRuntimeDesc,
            startAction: const MiuixAppIcon(
              AppIconNames.update,
              fallback: Icons.code,
              size: 24,
            ),
            endActions: const [],
          ),
          if (node.busy)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: MiuixLinearProgressIndicator(
                progress: node.phase == LabServicePhase.downloading
                    ? node.progress
                    : null,
                height: 4,
              ),
            ),
          const MiuixHorizontalDivider(),
          MiuixBasicComponent(
            title: l10n.labNodeStatus,
            summary: labNodeStatusLine(l10n, node),
            startAction: const MiuixAppIcon(
              AppIconNames.info,
              fallback: Icons.memory,
              size: 24,
            ),
            endActions: const [],
          ),
          const MiuixHorizontalDivider(),
          MiuixArrowPreference(
            title: l10n.labNodeRunnerMode,
            summary: shizukuMode ? l10n.labRunnerShizuku : l10n.labRunnerDirect,
            startAction: const MiuixAppIcon(
              AppIconNames.tune,
              fallback: Icons.tune,
              size: 24,
            ),
            onClick: node.busy ? null : _pickRunnerMode,
          ),
          const MiuixHorizontalDivider(),
          MiuixArrowPreference(
            title: l10n.labNodeMirror,
            summary: node.mirror == NodeDownloadMirror.cn
                ? l10n.labMirrorCn
                : l10n.labMirrorOfficial,
            startAction: const MiuixAppIcon(
              AppIconNames.download,
              fallback: Icons.cloud_download_outlined,
              size: 24,
            ),
            onClick: node.busy ? null : _pickMirror,
          ),
          if (shizukuMode) ...[
            const MiuixHorizontalDivider(),
            MiuixArrowPreference(
              title: l10n.labShizukuStatus,
              summary: shizukuSummary,
              startAction: const MiuixAppIcon(
                AppIconNames.lock,
                fallback: Icons.key_outlined,
                size: 24,
              ),
              onClick: (_shizukuOk == true && _shizukuGranted != true)
                  ? _requestShizuku
                  : null,
            ),
          ],
          if (node.error != null) ...[
            const MiuixHorizontalDivider(),
            MiuixBasicComponent(
              title: l10n.labError,
              summary: node.error,
              titleColor: MiuixBasicComponentColors(
                color: colors.error,
                disabledColor: colors.disabledOnSecondaryVariant,
              ),
              summaryColor: MiuixBasicComponentColors(
                color: colors.error,
                disabledColor: colors.disabledOnSecondaryVariant,
              ),
              startAction: MiuixAppIcon(
                AppIconNames.report,
                fallback: Icons.error_outline,
                size: 24,
                color: colors.error,
              ),
              endActions: const [],
            ),
          ],
          const MiuixHorizontalDivider(),
          if (!node.installed)
            MiuixArrowPreference(
              title: l10n.labNodeRuntimeInstall,
              startAction: const MiuixAppIcon(
                AppIconNames.download,
                fallback: Icons.download_outlined,
                size: 24,
              ),
              onClick: node.busy ? null : () => _node.install(),
            )
          else
            MiuixArrowPreference(
              title: l10n.labNodeRuntimeRemove,
              startAction: MiuixAppIcon(
                AppIconNames.delete,
                fallback: Icons.delete_outline,
                size: 24,
                color: colors.error,
              ),
              onClick: node.busy ? null : () => _node.uninstall(),
            ),
        ],
      ),
    );
  }

  Widget _buildStCard(AppLocalizations l10n, MiuixColors colors) {
    final st = _st;
    return MiuixGroupCard(
      insideMargin: EdgeInsets.zero,
      child: Column(
        children: [
          MiuixSwitchPreference(
            title: 'SillyTavern',
            summary: st.running ? st.url : null,
            value: st.enabled,
            enabled: !st.busy || st.running,
            onChanged: _onToggleSt,
            startAction: const MiuixAppIcon(
              AppIconNames.community,
              fallback: Icons.theater_comedy_outlined,
              size: 24,
            ),
            bottomAction: st.busy
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: MiuixLinearProgressIndicator(
                      progress: st.phase == LabServicePhase.downloading
                          ? st.progress
                          : null,
                      height: 4,
                    ),
                  )
                : null,
          ),
          const MiuixHorizontalDivider(),
          MiuixArrowPreference(
            title: l10n.labMoreSettings,
            startAction: const MiuixAppIcon(
              AppIconNames.tune,
              fallback: Icons.tune,
              size: 24,
            ),
            onClick: _openStSettings,
          ),
          if (st.error != null && st.error != 'missingNode') ...[
            const MiuixHorizontalDivider(),
            MiuixBasicComponent(
              title: l10n.labError,
              summary: st.error,
              titleColor: MiuixBasicComponentColors(
                color: colors.error,
                disabledColor: colors.disabledOnSecondaryVariant,
              ),
              summaryColor: MiuixBasicComponentColors(
                color: colors.error,
                disabledColor: colors.disabledOnSecondaryVariant,
              ),
              startAction: MiuixAppIcon(
                AppIconNames.report,
                fallback: Icons.error_outline,
                size: 24,
                color: colors.error,
              ),
              endActions: const [],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDshCard(AppLocalizations l10n, MiuixColors colors) {
    final dsh = _dsh;
    return MiuixGroupCard(
      insideMargin: EdgeInsets.zero,
      child: Column(
        children: [
          MiuixSwitchPreference(
            title: l10n.labDshTitle,
            summary: dsh.running ? dsh.url : null,
            value: dsh.enabled,
            enabled: !dsh.busy || dsh.running,
            onChanged: _onToggleDsh,
            startAction: const MiuixAppIcon(
              AppIconNames.layers,
              fallback: Icons.hub_outlined,
              size: 24,
            ),
            bottomAction: dsh.busy
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: MiuixLinearProgressIndicator(
                      progress: dsh.phase == LabServicePhase.downloading
                          ? dsh.progress
                          : null,
                      height: 4,
                    ),
                  )
                : null,
          ),
          const MiuixHorizontalDivider(),
          MiuixArrowPreference(
            title: l10n.labMoreSettings,
            startAction: const MiuixAppIcon(
              AppIconNames.tune,
              fallback: Icons.tune,
              size: 24,
            ),
            onClick: _openDshSettings,
          ),
          if (dsh.error != null && dsh.error != 'missingNode') ...[
            const MiuixHorizontalDivider(),
            MiuixBasicComponent(
              title: l10n.labError,
              summary: dsh.error,
              titleColor: MiuixBasicComponentColors(
                color: colors.error,
                disabledColor: colors.disabledOnSecondaryVariant,
              ),
              summaryColor: MiuixBasicComponentColors(
                color: colors.error,
                disabledColor: colors.disabledOnSecondaryVariant,
              ),
              startAction: MiuixAppIcon(
                AppIconNames.report,
                fallback: Icons.error_outline,
                size: 24,
                color: colors.error,
              ),
              endActions: const [],
            ),
          ],
        ],
      ),
    );
  }
}
