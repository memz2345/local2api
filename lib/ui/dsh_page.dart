// lib/ui/dsh_page.dart
//
// DeepSeek Harness（dsh）的「更多设置」（Material 版）。
//
// 信息架构和 SillyTavern 那一页一致：
//   1. 运行状态与启停；
//   2. 安装：位置 / Node / 依赖 / 目录 / 卸载；
//   3. 模型：把本机代理的模型组接给 dsh —— 选组、勾模型、选默认模型，
//      一键写进 `$DSH_HOME/profiles/web/cordis.patch.yml`。
//
// 「模型」是复数（dsh 一个 provider 下可以挂多个模型），所以这里是多选；
// 选中的模型同时落到本地 prefs，下次进页面还能看到。
//
// miuix 版是 `ui/miuix/miuix_dsh_page.dart`。

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/config_profile.dart';
import '../models/proxy_config.dart';
import '../services/android_notifications.dart';
import '../services/lab/dsh_service.dart';
import '../services/lab/dsh_plugins.dart';
import '../services/lab/dsh_session_watcher.dart';
import '../services/lab/dsh_task_center.dart';
import '../services/lab/dsh_task_runner.dart';
import '../services/lab/lab_notification_settings.dart';
import '../services/lab/node_runtime_service.dart';
import '../services/lab/shizuku_service.dart';
import '../services/lab/silly_tavern_service.dart' show LabServicePhase;
import '../services/profile_store.dart';
import '../services/server_controller.dart';
import '../widgets/app_toast.dart';
import '../widgets/custom_tabs_picker.dart';
import '../widgets/frosted_page_bar.dart';
import 'browser_page.dart';
import 'dsh_logs_page.dart';
import 'dsh_plugins_page.dart';
import 'widgets/lab_status.dart';

class DshPage extends StatefulWidget {
  const DshPage({super.key, this.controller});

  final ServerController? controller;

  @override
  State<DshPage> createState() => _DshPageState();
}

class _DshPageState extends State<DshPage> {
  final DshService _dsh = DshService.instance;
  final NodeRuntimeService _node = NodeRuntimeService.instance;
  final ShizukuService _shizuku = ShizukuService.instance;
  final LabNotificationSettings _notify = LabNotificationSettings.instance;
  final DshPluginsService _plugins = DshPluginsService.instance;

  bool? _shizukuOk;
  bool? _shizukuGranted;
  bool _notifyWired = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // service 拿不到 BuildContext，通知文案（「agent 已完成此轮操作」等）
    // 由页面在依赖就绪后注入一次。
    final l10n = AppLocalizations.of(context);
    DshSessionWatcher.instance.setLabels(
      DshWatchLabels(
        agentDone: l10n.labDshAgentDone,
        needAnswer: l10n.labDshNeedAnswer,
        answerHint: l10n.labDshAnswerHint,
        thinking: l10n.callStatusThinking,
      ),
    );
    // Windows：通知文案 / 输入框占位 / 选项提示都在这时才能拿到。
    if (Platform.isWindows && !_notifyWired) {
      _notifyWired = true;
      // 应用级默认动作（app.dart）已经在跑了；页面只做兜底，避免 pop
      // 之后留下一个 mounted=false 的死闭包。
      DshTaskCenter.instance.onOpenWeb ??= () {
        if (mounted && _dsh.running) {
          unawaited(openExternalUrl(context, _dsh.openUrl, useMiuix: false));
        }
      };
      unawaited(_refreshNotifications());
    }
  }

  @override
  void initState() {
    super.initState();
    _dsh.init();
    unawaited(_plugins.init(_dsh));
    if (Platform.isAndroid) {
      _node.init();
      _refreshShizuku();
      _refreshNotifications();
    }
  }

  Future<void> _refreshNotifications() async {
    final l10n = AppLocalizations.of(context);
    await _notify.attach(
      replyLabel: l10n.reply,
      // 安卓保持「取消」；Windows 的选项 Toast 用「跳过」更贴切。
      cancelLabel: Platform.isWindows ? l10n.labDshToastSkip : l10n.cancel,
      openLabel: l10n.labOpen,
      inputPlaceholder: l10n.labDshToastReplyHint,
      optionsHint: l10n.labDshToastOptionsHint,
      answerHint: l10n.labDshAnswerHint,
      stepsLabel: (done, total) => l10n.labDshTaskSteps('$done', '$total'),
      onOpenWeb: () {
        if (mounted) {
          unawaited(openExternalUrl(context, _dsh.openUrl, useMiuix: false));
        }
      },
    );
    await _notify.refresh();
  }

  // ---- Android：应用内 Node 运行时 / Shizuku（系统里没有 Node）----

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
                    '${_dsh.modelsOfGroup(config, g.id).length}',
                  ),
                ),
                enabled: _dsh.modelsOfGroup(config, g.id).isNotEmpty,
                trailing: g.id == _dsh.apiGroupId
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
    await _dsh.setGroup(picked);
  }

  Future<void> _pickModels() async {
    final l10n = AppLocalizations.of(context);
    final config = _config;
    final gid = _dsh.apiGroupId;
    if (config == null || gid == null) {
      await _pickGroup();
      return;
    }
    final models = _dsh.modelsOfGroup(config, gid);
    if (models.isEmpty) {
      showAppToast(context, l10n.labApiNeedGroup, error: true);
      return;
    }
    final selected = Set<String>.from(_dsh.models);
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    l10n.labDshPickModels,
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final m in models)
                        CheckboxListTile(
                          title: Text(m),
                          value: selected.contains(m),
                          onChanged: (v) => setSheetState(() {
                            if (v == true) {
                              selected.add(m);
                            } else {
                              selected.remove(m);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(sheetContext).pop(selected.toList()),
                  child: Text(l10n.commonSave),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _dsh.setModels(picked);
  }

  Future<void> _pickDefaultModel() async {
    final l10n = AppLocalizations.of(context);
    final models = _dsh.models;
    if (models.isEmpty) {
      await _pickModels();
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
                l10n.labDshPickDefault,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final m in models)
              ListTile(
                title: Text(m),
                trailing: m == _dsh.defaultModel
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
    await _dsh.setDefaultModel(picked);
  }

  Future<void> _applyApi() async {
    final l10n = AppLocalizations.of(context);
    final config = _config;
    if (config == null) {
      showAppToast(context, l10n.labApiNeedService, error: true);
      return;
    }
    final result = await _dsh.applyApiConfig(config);
    if (!mounted) return;
    if (result.ok) {
      showAppToast(context, l10n.labDshWriteOk);
      // 模型列表由 HMR 热加载，密钥不会：正在跑就重启一次让它吃到新 key。
      await _dsh.restartIfRunning();
      return;
    }
    final reason = switch (result.error) {
      'noModels' => l10n.labDshNeedModels,
      'noKey' => l10n.labApiNoKey,
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
        title: Text(l10n.labDshUninstallTitle),
        content: Text(l10n.labDshUninstallBody),
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
    if (ok == true) await _dsh.uninstall();
  }

  String _phaseLabel(AppLocalizations l10n, DshService dsh) {
    return switch (dsh.phase) {
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
      animation: Listenable.merge([_dsh, _node, _notify, _plugins]),
      builder: (context, _) {
        final dsh = _dsh;
        final config = _config;
        final baseUrl = config == null ? '—' : dsh.baseUrlOf(config);
        final key = config == null ? null : dsh.apiKeyOf(config);
        final shizukuMode = _node.runnerMode == NodeRunnerMode.shizuku;
        return FrostedBarPage(
          title: l10n.labDshTitle,
          actions: [
            IconButton(
              icon: const Icon(Icons.article_outlined),
              tooltip: l10n.labLogs,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const DshLogsPage()),
              ),
            ),
          ],
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
                        dsh.running
                            ? '${l10n.labRunning} · ${dsh.url}'
                            : dsh.busy
                            ? _phaseLabel(l10n, dsh)
                            : l10n.labStopped,
                      ),
                    ),
                    ListTile(
                      title: Text(l10n.labVersion),
                      subtitle: Text(
                        dsh.version == null ? '—' : 'v${dsh.version}',
                      ),
                    ),
                    ListTile(
                      leading: Icon(
                        dsh.running
                            ? Icons.power_settings_new
                            : Icons.play_arrow,
                      ),
                      title: Text(dsh.running ? l10n.labStop : l10n.labStart),
                      enabled: !dsh.busy,
                      onTap: () => dsh.setEnabled(!dsh.running),
                    ),
                    if (dsh.running) ...[
                      ListTile(
                        leading: const Icon(Icons.open_in_browser),
                        title: Text(l10n.labOpen),
                        // dsh web 的地址带一次性令牌，裸地址打开只会拿到 401。
                        subtitle: Text(dsh.openUrl),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          onPressed: () => _copy(dsh.openUrl),
                        ),
                        onTap: () => openExternalUrl(
                          context,
                          dsh.openUrl,
                          useMiuix: false,
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.language),
                        title: Text(l10n.labDshOpenInApp),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => BrowserPage(
                              initialUrl: dsh.openUrl,
                              title: l10n.labDshTitle,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (dsh.error != null)
                      ListTile(
                        title: Text(
                          '${l10n.labError}：${dsh.error}',
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
                        dsh.installed ? dsh.installDir! : dsh.displayRoot,
                      ),
                      trailing: dsh.canChooseLocation && !dsh.busy
                          ? TextButton(
                              onPressed: dsh.chooseLocation,
                              child: Text(l10n.labChooseLocation),
                            )
                          : null,
                    ),
                    ListTile(
                      title: Text(l10n.labNodeStatus),
                      subtitle: Text(
                        labNodeLineForService(
                          l10n,
                          isDesktop: dsh.isDesktop,
                          isAndroid: Platform.isAndroid,
                          nodeAvailable: dsh.nodeAvailable,
                          nodeVersion: dsh.nodeVersion,
                          npmVersion: dsh.npmVersion,
                        ),
                      ),
                      trailing: dsh.isDesktop || Platform.isAndroid
                          ? TextButton(
                              onPressed: () async {
                                await dsh.refreshNodeStatus();
                                if (!context.mounted) return;
                                showAppToast(
                                  context,
                                  dsh.nodeAvailable
                                      ? dsh.nodeVersion ?? ''
                                      : l10n.labNodeMissing,
                                  error: !dsh.nodeAvailable,
                                );
                              },
                              child: Text(l10n.labRecheck),
                            )
                          : null,
                    ),
                    if (dsh.isDesktop && !dsh.nodeAvailable)
                      ListTile(
                        leading: const Icon(Icons.download_outlined),
                        title: Text(l10n.labNodeDownload),
                        onTap: () => launchUrl(
                          Uri.parse('https://nodejs.org/zh-cn/download'),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    // Android：系统里没有 Node，运行时与执行通道都在这页装/切。
                    if (Platform.isAndroid) ...[
                      if (_node.busy)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          child: LinearProgressIndicator(
                            value: _node.phase == LabServicePhase.downloading
                                ? _node.progress
                                : null,
                            minHeight: 3,
                          ),
                        ),
                      if (!_node.installed)
                        ListTile(
                          leading: const Icon(Icons.download_outlined),
                          title: Text(l10n.labNodeRuntimeInstall),
                          enabled: !_node.busy,
                          onTap: _node.install,
                        )
                      else ...[
                        ListTile(
                          title: Text(l10n.labNodeRunnerMode),
                          subtitle: Text(
                            shizukuMode
                                ? l10n.labRunnerShizuku
                                : l10n.labRunnerDirect,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _pickRunnerMode,
                        ),
                        if (shizukuMode)
                          ListTile(
                            title: Text(l10n.labShizukuStatus),
                            subtitle: Text(
                              _shizukuOk != true
                                  ? l10n.labShizukuNotDetected
                                  : _shizukuGranted == true
                                  ? l10n.labShizukuGranted
                                  : l10n.labShizukuNotGranted,
                            ),
                            trailing:
                                _shizukuOk == true && _shizukuGranted != true
                                ? TextButton(
                                    onPressed: _requestShizuku,
                                    child: Text(l10n.labShizukuRequest),
                                  )
                                : null,
                          ),
                      ],
                      if (_node.error != null)
                        ListTile(
                          title: Text(
                            '${l10n.labError}：${_node.error}',
                            style: TextStyle(color: cs.error, fontSize: 12),
                          ),
                        ),
                    ],
                    if (!dsh.installed)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: FilledButton(
                          onPressed: dsh.busy ? null : dsh.install,
                          child: Text(l10n.labInstall),
                        ),
                      )
                    else ...[
                      if (!dsh.nodeAvailable)
                        ListTile(
                          leading: const Icon(Icons.inventory_2_outlined),
                          title: Text(l10n.labInstallDeps),
                          enabled: !dsh.busy,
                          onTap: dsh.installDependencies,
                        ),
                      if (dsh.isDesktop)
                        ListTile(
                          leading: const Icon(Icons.folder_open_outlined),
                          title: Text(l10n.labOpenFolder),
                          onTap: dsh.openInstallFolder,
                        ),
                      ListTile(
                        leading: Icon(Icons.delete_outline, color: cs.error),
                        title: Text(
                          l10n.labUninstall,
                          style: TextStyle(color: cs.error),
                        ),
                        enabled: !dsh.busy,
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
                        dsh.apiGroupId == null
                            ? l10n.labApiGroupNone
                            : _groupName(dsh.apiGroupId),
                      ),
                      onTap: config == null ? null : _pickGroup,
                    ),
                    ListTile(
                      title: Text(l10n.labApiModel),
                      subtitle: Text(
                        dsh.models.isEmpty
                            ? '—'
                            : l10n.labApiModelCount('${dsh.models.length}'),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: config == null ? null : _pickModels,
                    ),
                    ListTile(
                      title: Text(l10n.labDshDefaultModel),
                      subtitle: Text(dsh.defaultModel ?? '—'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: dsh.models.isEmpty ? null : _pickDefaultModel,
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
                    ListTile(
                      title: Text(l10n.labDshConfigPath),
                      subtitle: Text(dsh.configPath),
                      trailing: const Icon(Icons.copy, size: 18),
                      onTap: () => _copy(dsh.configPath),
                    ),
                    if (Platform.isAndroid) ...[
                      const Divider(height: 1),
                      SwitchListTile(
                        title: Text(l10n.labDshCompat),
                        subtitle: Text(l10n.labDshCompatDesc),
                        value: dsh.androidCompatEnabled,
                        onChanged: (v) async {
                          await dsh.setAndroidCompat(v);
                          await dsh.restartIfRunning();
                        },
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed:
                              config == null ||
                                  !dsh.installed ||
                                  dsh.models.isEmpty ||
                                  key == null
                              ? null
                              : _applyApi,
                          child: Text(l10n.labDshWrite),
                        ),
                      ),
                    ),
                    if (config == null) _Hint(text: l10n.labApiNeedService),
                    if (config != null && dsh.models.isEmpty)
                      _Hint(text: l10n.labDshNeedModels),
                    if (dsh.installed) _Hint(text: l10n.labDshWriteHint),
                  ],
                ),
              ),
              if (dsh.installed) ...[
                const SizedBox(height: 20),
                Text(l10n.labDshPlugins, style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.extension_outlined),
                        title: Text(l10n.pluginManagerTitle),
                        subtitle: Text(l10n.pluginManagerSubtitle),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const DshPluginsPage(),
                          ),
                        ),
                      ),
                      if (_plugins.supportedIds().isNotEmpty)
                        const Divider(height: 1),
                      for (final spec in kDshPlugins)
                        if (_plugins.supported(spec.id)) ...[
                          _pluginSwitch(context, l10n, spec),
                          const Divider(height: 1),
                        ],
                      _Hint(text: l10n.labDshPluginRestartHint),
                    ],
                  ),
                ),
              ],
              if (Platform.isAndroid || Platform.isWindows) ...[
                const SizedBox(height: 20),
                Text(l10n.labNotifySection, style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      // 权限 / 实时更新 / 电池优化是安卓系统门槛；
                      // Windows 的 Toast 没有运行时权限这一套。
                      if (Platform.isAndroid) ...[
                        SwitchListTile(
                          title: Text(l10n.labNotifyPermission),
                          subtitle: Text(l10n.labNotifyPermissionDesc),
                          value: _notify.permission ?? false,
                          onChanged: (v) async {
                            if (v && _notify.permission != true) {
                              await _notify.requestPermission();
                              return;
                            }
                            await _notify.openNotificationSettings();
                          },
                        ),
                        ListTile(
                          leading: const Icon(
                            Icons.notifications_active_outlined,
                          ),
                          title: Text(l10n.labNotifyLiveUpdate),
                          subtitle: Text(
                            _notify.promoted == true
                                ? l10n.labNotifyPromoted
                                : l10n.labNotifyNotPromoted,
                          ),
                        ),
                        SwitchListTile(
                          title: Text(l10n.labNotifyBattery),
                          subtitle: Text(l10n.labNotifyBatteryDesc),
                          value: _notify.batteryIgnored ?? false,
                          onChanged: (v) async {
                            if (v && _notify.batteryIgnored != true) {
                              await _notify.requestIgnoreBattery();
                              return;
                            }
                            await AndroidNotifications.openBatteryOptimizationSettings();
                          },
                        ),
                      ],
                      ListTile(
                        leading: const Icon(Icons.send_outlined),
                        title: Text(l10n.labNotifyTest),
                        onTap: _sendTestNotification,
                      ),
                      SwitchListTile(
                        title: Text(l10n.labDshTaskHint),
                        subtitle: Text(l10n.labDshTaskHintDesc),
                        value: dsh.taskHintEnabled,
                        onChanged: (v) => dsh.setTaskHint(v),
                      ),
                      ListTile(
                        leading: const Icon(Icons.play_arrow),
                        title: Text(l10n.labDshRunTask),
                        subtitle: Text(l10n.labDshRunTaskDesc),
                        enabled: dsh.installed && dsh.canRun,
                        onTap: _runTask,
                      ),
                      if (Platform.isAndroid)
                        ListTile(
                          leading: const Icon(Icons.settings_outlined),
                          title: Text(l10n.labNotifyOpenSettings),
                          onTap: () => _notify.openNotificationSettings(),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ---- 插件 ----

  Widget _pluginSwitch(
    BuildContext context,
    AppLocalizations l10n,
    DshPluginSpec spec,
  ) {
    final state = _plugins.stateOf(spec.id);
    final title = switch (spec.id) {
      DshPluginId.messageEdit => l10n.labDshPluginMessageEdit,
      DshPluginId.computerUse => l10n.labDshPluginComputerUse,
      DshPluginId.androidControl => l10n.labDshPluginAndroid,
    };
    final desc = switch (spec.id) {
      DshPluginId.messageEdit => l10n.labDshPluginMessageEditDesc,
      DshPluginId.computerUse => l10n.labDshPluginComputerUseDesc,
      DshPluginId.androidControl => l10n.labDshPluginAndroidDesc,
    };
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(
        state.busy ? l10n.labDshPluginInstalling : (state.error ?? desc),
        style: state.error == null
            ? null
            : TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      value: state.enabled,
      onChanged: state.busy ? null : (value) => _togglePlugin(spec, value),
    );
  }

  Future<void> _togglePlugin(DshPluginSpec spec, bool value) async {
    final l10n = AppLocalizations.of(context);
    final ok = await _plugins.setEnabled(spec.id, value);
    if (!mounted || ok) return;
    showAppToast(
      context,
      '${l10n.labDshPluginFailed}：${_plugins.stateOf(spec.id).error ?? ''}',
      error: true,
    );
  }

  // ---- 通知 / 任务模式 ----

  Future<void> _sendTestNotification() async {
    final l10n = AppLocalizations.of(context);
    final result = await _notify.sendTestNotification(
      title: l10n.labNotifyTest,
      text: l10n.labNotifySection,
      steps: const ['准备', '执行', '收尾'],
    );
    if (!mounted) return;
    showAppToast(
      context,
      result.posted ? l10n.labNotifyTestSent : l10n.labNotifyTestFailed,
      error: !result.posted,
    );
  }

  Future<void> _runTask() async {
    final l10n = AppLocalizations.of(context);
    if (DshTaskRunner.instance.running) {
      showAppToast(context, l10n.labDshTaskBusy, error: true);
      return;
    }
    final controller = TextEditingController();
    final task = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.labDshTaskPrompt),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: InputDecoration(hintText: l10n.labDshRunTaskDesc),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(l10n.labDshRunTask),
          ),
        ],
      ),
    );
    if (task == null || task.trim().isEmpty || !mounted) return;
    // 不 await：任务可能跑几分钟，进度与结果都在通知里。
    unawaited(
      DshTaskRunner.instance.run(
        task,
        replyLabel: l10n.reply,
        cancelLabel: Platform.isWindows ? l10n.labDshToastSkip : l10n.cancel,
      ),
    );
    showAppToast(context, l10n.labDshTaskStarted);
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
