// lib/ui/lab_sillytavern_page.dart
//
// SillyTavern「更多设置」（Material 版）：从实验室首页那一行点进来。
// miuix 版是 `ui/miuix/miuix_lab_sillytavern_page.dart`，两套共用同一份
// [SillyTavernService] 与同一套 l10n。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/config_profile.dart';
import '../models/proxy_config.dart';
import '../services/lab/silly_tavern_service.dart';
import '../services/profile_store.dart';
import '../services/server_controller.dart';
import '../widgets/app_toast.dart';
import '../widgets/custom_tabs_picker.dart';
import '../widgets/frosted_page_bar.dart';
import 'widgets/lab_status.dart';

class LabSillyTavernPage extends StatefulWidget {
  const LabSillyTavernPage({super.key, this.controller});

  final ServerController? controller;

  @override
  State<LabSillyTavernPage> createState() => _LabSillyTavernPageState();
}

class _LabSillyTavernPageState extends State<LabSillyTavernPage> {
  final SillyTavernService _st = SillyTavernService.instance;

  @override
  void initState() {
    super.initState();
    _st.init();
  }

  ProfileStore? get _profiles {
    try {
      return context.read<ProfileStore>();
    } catch (_) {
      return null;
    }
  }

  ProxyConfig? get _config => widget.controller?.config;

  List<ConfigProfile> _groups() => _profiles?.profiles ?? const [];

  String _groupName(String? id) {
    if (id == null || id.isEmpty) return '';
    return _profiles?.profileOf(id)?.name ?? id;
  }

  StApiConfig? _resolved() {
    final config = _config;
    if (config == null) return null;
    return _st.resolveApiConfig(config, groupName: _groupName(_st.apiGroupId));
  }

  Future<void> _pickGroup() async {
    final l10n = AppLocalizations.of(context);
    final config = _config;
    if (config == null) {
      showAppToast(context, l10n.labApiNeedService, error: true);
      return;
    }
    final groups = _groups();
    if (groups.isEmpty) {
      showAppToast(context, l10n.labApiNeedGroup, error: true);
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                l10n.labApiPickGroup,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final g in groups)
              ListTile(
                title: Text(g.name),
                subtitle: Text(
                  l10n.labApiModelCount(
                    '${_st.modelsOfGroup(config, g.id).length}',
                  ),
                ),
                enabled: _st.modelsOfGroup(config, g.id).isNotEmpty,
                trailing: g.id == _st.apiGroupId
                    ? Icon(
                        Icons.check,
                        color: Theme.of(sheetContext).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(g.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _st.setApiSelection(groupId: picked);
  }

  Future<void> _pickModel() async {
    final l10n = AppLocalizations.of(context);
    final config = _config;
    final gid = _st.apiGroupId;
    if (config == null || gid == null) {
      await _pickGroup();
      return;
    }
    final models = _st.modelsOfGroup(config, gid);
    if (models.isEmpty) {
      showAppToast(context, l10n.labApiNeedGroup, error: true);
      return;
    }
    final current = _resolved()?.model;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                l10n.labApiPickModel,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final m in models)
              ListTile(
                title: Text(m),
                trailing: m == current
                    ? Icon(
                        Icons.check,
                        color: Theme.of(sheetContext).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(m),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _st.setApiSelection(groupId: gid, model: picked);
  }

  Future<void> _applyApi() async {
    final l10n = AppLocalizations.of(context);
    final cfg = _resolved();
    if (cfg == null) {
      showAppToast(context, l10n.labApiNeedGroup, error: true);
      return;
    }
    if (!cfg.hasKey) {
      showAppToast(context, l10n.labApiNoKey, error: true);
      return;
    }
    final result = await _st.applyApiConfig(cfg);
    if (!mounted) return;
    if (result.ok) {
      showAppToast(context, l10n.labApiWriteOk);
      return;
    }
    final reason = switch (result.error) {
      'notInstalled' => l10n.labNotInstalled,
      'noUserData' => l10n.labApiNoUserData,
      'running' => l10n.labApiStopFirst,
      _ => result.error ?? '',
    };
    showAppToast(context, l10n.labApiWriteFailed(reason), error: true);
  }

  Future<void> _copy(String text) async {
    if (text.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showAppToast(context, l10n.copied);
  }

  Future<void> _confirmUninstall() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.labUninstallTitle),
        content: Text(l10n.labUninstallBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.labCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.labUninstall),
          ),
        ],
      ),
    );
    if (ok == true) await _st.uninstall();
  }

  String _phaseLabel(AppLocalizations l10n, SillyTavernService st) {
    return switch (st.phase) {
      LabServicePhase.downloading => l10n.labDownloading,
      LabServicePhase.extracting => l10n.labExtracting,
      LabServicePhase.installing => l10n.labInstallingDeps,
      LabServicePhase.starting => l10n.labStarting,
      LabServicePhase.idle => l10n.labPhaseIdle,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AnimatedBuilder(
      animation: _st,
      builder: (context, _) {
        final st = _st;
        final cfg = _resolved();
        final config = _config;
        final baseUrl = config == null ? '—' : st.baseUrlOf(config);
        final key = config == null ? null : st.apiKeyOf(config);
        return FrostedBarPage(
          title: 'SillyTavern',
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
              Text(l10n.labSectionStatus, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    ListTile(
                      title: Text(l10n.labStatus),
                      subtitle: Text(
                        st.running
                            ? '${l10n.labRunning} · ${st.url}'
                            : st.busy
                            ? _phaseLabel(l10n, st)
                            : l10n.labStopped,
                      ),
                    ),
                    ListTile(
                      title: Text(l10n.labVersion),
                      subtitle: Text(
                        st.version == null ? '—' : 'v${st.version}',
                      ),
                    ),
                    ListTile(
                      leading: Icon(
                        st.running
                            ? Icons.power_settings_new
                            : Icons.play_arrow,
                      ),
                      title: Text(st.running ? l10n.labStop : l10n.labStart),
                      enabled: !st.busy,
                      onTap: () => st.setEnabled(!st.running),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.public),
                      title: Text(l10n.labAutoOpenBrowser),
                      subtitle: Text(l10n.labAutoOpenBrowserDesc),
                      value: st.autoOpenBrowser,
                      onChanged: st.setAutoOpenBrowser,
                    ),
                    if (st.running)
                      ListTile(
                        leading: const Icon(Icons.open_in_browser),
                        title: Text(l10n.labOpen),
                        subtitle: Text(st.url),
                        onTap: () => openExternalUrl(
                          context,
                          st.url,
                          useMiuix: false,
                        ),
                      ),
                    if (st.error != null)
                      ListTile(
                        title: Text(
                          '${l10n.labError}：${st.error}',
                          style: TextStyle(color: cs.error, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(l10n.labSectionInstall, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    ListTile(
                      title: Text(l10n.labInstallLocation),
                      subtitle: Text(
                        st.installed ? st.installDir! : st.displayRoot,
                      ),
                      trailing: st.canChooseLocation && !st.busy
                          ? TextButton(
                              onPressed: st.chooseLocation,
                              child: Text(l10n.labChooseLocation),
                            )
                          : null,
                    ),
                    ListTile(
                      title: Text(l10n.labNodeStatus),
                      subtitle: Text(
                        labNodeLineForService(
                          l10n,
                          isDesktop: st.isDesktop,
                          isAndroid: Platform.isAndroid,
                          nodeAvailable: st.nodeAvailable,
                          nodeVersion: st.nodeVersion,
                          npmVersion: st.npmVersion,
                        ),
                      ),
                      trailing: st.isDesktop || Platform.isAndroid
                          ? TextButton(
                              onPressed: () async {
                                await st.refreshNodeStatus();
                                if (!context.mounted) return;
                                showAppToast(
                                  context,
                                  st.nodeAvailable
                                      ? st.nodeVersion ?? ''
                                      : l10n.labNodeMissing,
                                  error: !st.nodeAvailable,
                                );
                              },
                              child: Text(l10n.labRecheck),
                            )
                          : null,
                    ),
                    if (st.isDesktop && !st.nodeAvailable)
                      ListTile(
                        leading: const Icon(Icons.download_outlined),
                        title: Text(l10n.labNodeDownload),
                        onTap: () => launchUrl(
                          Uri.parse('https://nodejs.org/zh-cn/download'),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    if (!st.installed)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: FilledButton(
                          onPressed: st.busy ? null : st.install,
                          child: Text(l10n.labInstall),
                        ),
                      )
                    else ...[
                      if (!st.depsInstalled)
                        ListTile(
                          leading: const Icon(Icons.inventory_2_outlined),
                          title: Text(l10n.labInstallDeps),
                          enabled: !st.busy,
                          onTap: st.installDependencies,
                        ),
                      if (st.isDesktop)
                        ListTile(
                          leading: const Icon(Icons.folder_open_outlined),
                          title: Text(l10n.labOpenFolder),
                          onTap: st.openInstallFolder,
                        ),
                      ListTile(
                        leading: Icon(Icons.delete_outline, color: cs.error),
                        title: Text(
                          l10n.labUninstall,
                          style: TextStyle(color: cs.error),
                        ),
                        enabled: !st.busy,
                        onTap: _confirmUninstall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(l10n.labApiConfig, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    ListTile(
                      title: Text(l10n.labApiGroup),
                      subtitle: Text(
                        st.apiGroupId == null
                            ? l10n.labApiGroupNone
                            : _groupName(st.apiGroupId),
                      ),
                      onTap: _config == null ? null : _pickGroup,
                    ),
                    ListTile(
                      title: Text(l10n.labApiModel),
                      subtitle: Text(cfg?.model ?? '—'),
                      onTap: _config == null ? null : _pickModel,
                    ),
                    ListTile(
                      title: Text(l10n.labApiBaseUrl),
                      subtitle: Text(baseUrl),
                      trailing: const Icon(Icons.copy, size: 18),
                      onTap: config == null ? null : () => _copy(baseUrl),
                    ),
                    ListTile(
                      title: Text(l10n.labApiKey),
                      subtitle: Text(
                        key == null ? l10n.labApiNoKey : _maskKey(key),
                        style: key == null ? TextStyle(color: cs.error) : null,
                      ),
                      trailing: const Icon(Icons.copy, size: 18),
                      onTap: key == null ? null : () => _copy(key),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: cfg == null || !cfg.hasKey || !st.installed
                              ? null
                              : _applyApi,
                          child: Text(l10n.labApiWrite),
                        ),
                      ),
                    ),
                    if (_config == null) _Hint(text: l10n.labApiNeedService),
                    if (_config != null && cfg == null)
                      _Hint(text: l10n.labApiNeedGroup),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _maskKey(String key) {
    if (key.length <= 12) return key;
    return '${key.substring(0, 8)}…${key.substring(key.length - 4)}';
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
