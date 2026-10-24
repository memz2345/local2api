// lib/ui/lab_page.dart
//
// 实验室（Material 版）：本地服务一览（Node 运行时 / SillyTavern / dsh）。
//
// 首页一眼一个开关：服务名 + Switch，安装/卸载/Node/API 配置这些细节在
// 「更多设置」页；「打开」「日志」两行与状态说明已按需求撤掉（状态看开关
// 本身，打开入口在「更多设置」里）。业务状态全在 [SillyTavernService]
// 单例里，本页只负责渲染；miuix 版是 `ui/miuix/miuix_lab_page.dart`。
//
// Android：顶部多一张「Node.js 运行时」卡（[NodeRuntimeService]）——
// 系统没有 Node，先在这里装运行时，再跑下面的服务；运行模式（直连 /
// Shizuku）也在这张卡里切。

import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/lab/dsh_service.dart';
import '../services/lab/node_runtime_service.dart';
import '../services/lab/shizuku_service.dart';
import '../services/lab/silly_tavern_service.dart';
import '../services/server_controller.dart';
import '../widgets/app_toast.dart';
import '../widgets/frosted_page_bar.dart';
import 'widgets/lab_status.dart';
import 'dsh_page.dart';
import 'lab_sillytavern_page.dart';
import 'widgets/common.dart' show pushPage;

class LabPage extends StatefulWidget {
  const LabPage({super.key, this.controller});

  /// 代理服务总控：API 配置要读端口 / 密钥。测试里可以不给。
  final ServerController? controller;

  @override
  State<LabPage> createState() => _LabPageState();
}

class _LabPageState extends State<LabPage> {
  final SillyTavernService _st = SillyTavernService.instance;
  final DshService _dsh = DshService.instance;
  final NodeRuntimeService _node = NodeRuntimeService.instance;
  final ShizukuService _shizuku = ShizukuService.instance;

  bool? _shizukuOk;
  bool? _shizukuGranted;

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
    showAppToast(
      context,
      granted ? l10n.labShizukuGranted : l10n.labShizukuNotGranted,
      error: !granted,
    );
    await _refreshShizuku();
  }

  Future<void> _pickRunnerMode() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<NodeRunnerMode>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                l10n.labNodeRunnerMode,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final mode in NodeRunnerMode.values)
              ListTile(
                title: Text(
                  mode == NodeRunnerMode.direct
                      ? l10n.labRunnerDirect
                      : l10n.labRunnerShizuku,
                ),
                subtitle: Text(
                  mode == NodeRunnerMode.direct
                      ? l10n.labRunnerDirectDesc
                      : l10n.labRunnerShizukuDesc,
                ),
                trailing: mode == _node.runnerMode
                    ? Icon(
                        Icons.check,
                        color: Theme.of(sheetContext).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(mode),
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
    final picked = await showModalBottomSheet<NodeDownloadMirror>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                l10n.labNodeMirror,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final mirror in NodeDownloadMirror.values)
              ListTile(
                title: Text(
                  mirror == NodeDownloadMirror.official
                      ? l10n.labMirrorOfficial
                      : l10n.labMirrorCn,
                ),
                subtitle: Text(
                  mirror == NodeDownloadMirror.official
                      ? l10n.labMirrorOfficialDesc
                      : l10n.labMirrorCnDesc,
                ),
                trailing: mirror == _node.mirror
                    ? Icon(
                        Icons.check,
                        color: Theme.of(sheetContext).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(mirror),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _node.setMirror(picked);
  }

  Future<void> _openSettings() =>
      pushPage(context, LabSillyTavernPage(controller: widget.controller));

  Future<void> _openDshSettings() =>
      pushPage(context, DshPage(controller: widget.controller));

  Future<void> _onToggle(bool value) async {
    final l10n = AppLocalizations.of(context);
    if (value && !_st.installed) {
      final go = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.labInstallFirstTitle),
          content: Text(l10n.labInstallFirstBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.labCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.labGoSettings),
            ),
          ],
        ),
      );
      if (go == true && mounted) await _openSettings();
      return;
    }
    final ok = await _st.setEnabled(value);
    if (!mounted || ok == value) return;
    showAppToast(
      context,
      _st.error == 'missingNode' ? l10n.labNodeMissing : l10n.labStartFailed,
      error: true,
    );
  }

  Future<void> _onToggleDsh(bool value) async {
    final l10n = AppLocalizations.of(context);
    if (value && !_dsh.installed) {
      final go = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.labDshInstallFirstTitle),
          content: Text(l10n.labDshInstallFirstBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.labCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.labGoSettings),
            ),
          ],
        ),
      );
      if (go == true && mounted) await _openDshSettings();
      return;
    }
    final ok = await _dsh.setEnabled(value);
    if (!mounted || ok == value) return;
    showAppToast(
      context,
      _dsh.error == 'missingNode' ? l10n.labNodeMissing : l10n.labStartFailed,
      error: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AnimatedBuilder(
      animation: Listenable.merge([_st, _dsh, _node]),
      builder: (context, _) => FrostedBarPage(
        title: l10n.labTitle,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          padding: EdgeInsets.fromLTRB(
            16,
            frostedPageBarInset(context) + 8,
            16,
            120,
          ),
          children: [
            Text(l10n.labLocalServices, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (Platform.isAndroid) ...[
              _buildNodeRuntimeCard(l10n, cs),
              const SizedBox(height: 12),
            ],
            _buildSillyTavernCard(l10n, cs),
            const SizedBox(height: 12),
            _buildDshCard(l10n, cs),
          ],
        ),
      ),
    );
  }

  /// Node 状态副标题见 `widgets/lab_status.dart`（两套 UI 共用）。

  Widget _buildNodeRuntimeCard(AppLocalizations l10n, ColorScheme cs) {
    final theme = Theme.of(context);
    final node = _node;
    final shizukuMode = node.runnerMode == NodeRunnerMode.shizuku;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.labNodeRuntimeTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        l10n.labNodeRuntimeDesc,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (node.busy)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: LinearProgressIndicator(
                value: node.phase == LabServicePhase.downloading
                    ? node.progress
                    : null,
                minHeight: 3,
              ),
            ),
          if (node.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '${l10n.labError}：${node.error}',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ),
          ListTile(
            title: Text(l10n.labNodeStatus),
            subtitle: Text(labNodeStatusLine(l10n, node)),
          ),
          ListTile(
            title: Text(l10n.labNodeRunnerMode),
            subtitle: Text(
              shizukuMode ? l10n.labRunnerShizuku : l10n.labRunnerDirect,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: node.busy ? null : _pickRunnerMode,
          ),
          ListTile(
            title: Text(l10n.labNodeMirror),
            subtitle: Text(
              node.mirror == NodeDownloadMirror.cn
                  ? l10n.labMirrorCn
                  : l10n.labMirrorOfficial,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: node.busy ? null : _pickMirror,
          ),
          if (shizukuMode)
            ListTile(
              title: Text(l10n.labShizukuStatus),
              subtitle: Text(
                _shizukuOk == null
                    ? l10n.labShizukuNotDetected
                    : _shizukuOk == false
                    ? l10n.labShizukuNotDetected
                    : _shizukuGranted == true
                    ? l10n.labShizukuGranted
                    : l10n.labShizukuNotGranted,
              ),
              trailing: _shizukuOk == true && _shizukuGranted != true
                  ? TextButton(
                      onPressed: _requestShizuku,
                      child: Text(l10n.labShizukuRequest),
                    )
                  : null,
            ),
          const Divider(height: 1),
          if (!node.installed)
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton(
                onPressed: node.busy ? null : _node.install,
                child: Text(l10n.labNodeRuntimeInstall),
              ),
            )
          else
            ListTile(
              leading: Icon(Icons.delete_outline, color: cs.error),
              title: Text(
                l10n.labNodeRuntimeRemove,
                style: TextStyle(color: cs.error),
              ),
              enabled: !node.busy,
              onTap: _node.uninstall,
            ),
        ],
      ),
    );
  }

  Widget _buildDshCard(AppLocalizations l10n, ColorScheme cs) {
    final theme = Theme.of(context);
    final dsh = _dsh;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.labDshTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (dsh.running)
                        Text(
                          dsh.url,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Switch(
                  value: dsh.enabled,
                  onChanged: (!dsh.busy || dsh.running) ? _onToggleDsh : null,
                ),
              ],
            ),
          ),
          if (dsh.busy)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: LinearProgressIndicator(
                value: dsh.phase == LabServicePhase.downloading
                    ? dsh.progress
                    : null,
                minHeight: 3,
              ),
            ),
          if (dsh.error != null && dsh.error != 'missingNode')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '${l10n.labError}：${dsh.error}',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.tune),
            title: Text(l10n.labMoreSettings),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openDshSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildSillyTavernCard(AppLocalizations l10n, ColorScheme cs) {
    final theme = Theme.of(context);
    final st = _st;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'SillyTavern',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Switch(
                  value: st.enabled,
                  onChanged: (!st.busy || st.running) ? _onToggle : null,
                ),
              ],
            ),
          ),
          if (st.busy)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: LinearProgressIndicator(
                value: st.phase == LabServicePhase.downloading
                    ? st.progress
                    : null,
                minHeight: 3,
              ),
            ),
          if (st.error != null && st.error != 'missingNode')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '${l10n.labError}：${st.error}',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.tune),
            title: Text(l10n.labMoreSettings),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openSettings,
          ),
        ],
      ),
    );
  }
}
