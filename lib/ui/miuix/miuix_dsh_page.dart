// lib/ui/miuix/miuix_dsh_page.dart
//
// DeepSeek Harness（dsh）的「更多设置」（miuix 版）。
//
// 卡片结构与「编辑上游」/ SillyTavern 设置页一致：
//   `MiuixGroupCard(insideMargin: EdgeInsets.zero)` + 一行一个字段，
//   行间 `MiuixHorizontalDivider`；没有自绘行。
//
// 与 Material 版共用 [DshService] 与同一套 l10n。

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../models/config_profile.dart';
import '../../models/proxy_config.dart';
import '../../services/android_notifications.dart';
import '../../services/lab/dsh_service.dart';
import '../../services/lab/dsh_plugins.dart';
import '../../services/lab/dsh_session_watcher.dart';
import '../../services/lab/dsh_task_center.dart';
import '../../services/lab/dsh_task_runner.dart';
import '../../services/lab/lab_notification_settings.dart';
import '../../services/lab/node_runtime_service.dart';
import '../../services/lab/shizuku_service.dart';
import '../../services/lab/silly_tavern_service.dart' show LabServicePhase;
import '../../services/profile_store.dart';
import '../../services/server_controller.dart';
import '../../widgets/custom_tabs_picker.dart';
import '../../widgets/miuix/miuix_app_icon.dart';
import '../../widgets/miuix/miuix_blur_top_bar.dart';
import '../../widgets/miuix/miuix_bottom_sheet.dart';
import '../../widgets/miuix/miuix_dialog.dart';
import '../../widgets/miuix/miuix_field_row.dart';
import '../../widgets/miuix/miuix_group_card.dart';
import '../../widgets/miuix/miuix_scroll_behavior.dart';
import '../../widgets/miuix/miuix_toast.dart';
import '../widgets/lab_status.dart';

import 'miuix_browser_page.dart';
import 'miuix_dsh_logs_page.dart';
import 'miuix_dsh_plugins_page.dart';

class MiuixDshPage extends StatefulWidget {
  const MiuixDshPage({super.key, this.controller});

  final ServerController? controller;

  @override
  State<MiuixDshPage> createState() => _MiuixDshPageState();
}

class _MiuixDshPageState extends State<MiuixDshPage> {
  final DshService _dsh = DshService.instance;
  final NodeRuntimeService _node = NodeRuntimeService.instance;
  final ShizukuService _shizuku = ShizukuService.instance;
  final LabNotificationSettings _notify = LabNotificationSettings.instance;
  final DshPluginsService _plugins = DshPluginsService.instance;
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();

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
    if (Platform.isWindows && !_notifyWired) {
      _notifyWired = true;
      DshTaskCenter.instance.onOpenWeb ??= () {
        if (mounted && _dsh.running) {
          unawaited(openExternalUrl(context, _dsh.openUrl, useMiuix: true));
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
      cancelLabel: Platform.isWindows ? l10n.labDshToastSkip : l10n.cancel,
      openLabel: l10n.labOpen,
      inputPlaceholder: l10n.labDshToastReplyHint,
      optionsHint: l10n.labDshToastOptionsHint,
      answerHint: l10n.labDshAnswerHint,
      stepsLabel: (done, total) => l10n.labDshTaskSteps('$done', '$total'),
      onOpenWeb: () {
        if (mounted) {
          unawaited(openExternalUrl(context, _dsh.openUrl, useMiuix: true));
        }
      },
    );
    await _notify.refresh();
  }

  @override
  void dispose() {
    _behavior.state.dispose();
    super.dispose();
  }

  // ---- Android：应用内 Node 运行时 / Shizuku ----

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
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: MiuixText(
                  l10n.labNodeRunnerMode,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: MiuixGroupCard(
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
                            insideMargin: const EdgeInsets.fromLTRB(
                              16,
                              12,
                              16,
                              12,
                            ),
                            onClick: () => Navigator.of(sheetContext).pop(mode),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
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
      showMiuixToast(context, l10n.labApiNeedService, error: true);
      return;
    }
    final groups = _groups();
    if (groups.isEmpty) {
      showMiuixToast(context, l10n.labApiNeedGroup, error: true);
      return;
    }
    final picked = await showMiuixBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: MiuixText(
                  l10n.labApiPickGroup,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: MiuixGroupCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final g in groups)
                          MiuixRadioButtonPreference(
                            title: g.name,
                            summary: l10n.labApiModelCount(
                              '${_dsh.modelsOfGroup(config, g.id).length}',
                            ),
                            selected: g.id == _dsh.apiGroupId,
                            enabled: _dsh
                                .modelsOfGroup(config, g.id)
                                .isNotEmpty,
                            insideMargin: const EdgeInsets.fromLTRB(
                              16,
                              12,
                              16,
                              12,
                            ),
                            onClick: () => Navigator.of(sheetContext).pop(g.id),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
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
      showMiuixToast(context, l10n.labApiNeedGroup, error: true);
      return;
    }
    final selected = Set<String>.from(_dsh.models);
    final picked = await showMiuixBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 10),
                  child: MiuixText(
                    l10n.labDshPickModels,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: MiuixGroupCard(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final m in models)
                            MiuixCheckboxPreference(
                              title: m,
                              value: selected.contains(m),
                              insideMargin: const EdgeInsets.fromLTRB(
                                16,
                                10,
                                16,
                                10,
                              ),
                              onChanged: (v) => setSheetState(() {
                                if (v) {
                                  selected.add(m);
                                } else {
                                  selected.remove(m);
                                }
                              }),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                MiuixTextButton(
                  l10n.commonSave,
                  onPressed: () =>
                      Navigator.of(sheetContext).pop(selected.toList()),
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
    final picked = await showMiuixBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: MiuixText(
                  l10n.labDshPickDefault,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: MiuixGroupCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final m in models)
                          MiuixRadioButtonPreference(
                            title: m,
                            selected: m == _dsh.defaultModel,
                            insideMargin: const EdgeInsets.fromLTRB(
                              16,
                              12,
                              16,
                              12,
                            ),
                            onClick: () => Navigator.of(sheetContext).pop(m),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
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
      showMiuixToast(context, l10n.labApiNeedService, error: true);
      return;
    }
    final result = await _dsh.applyApiConfig(config);
    if (!mounted) return;
    if (result.ok) {
      showMiuixToast(context, l10n.labDshWriteOk);
      // 模型列表由 HMR 热加载，密钥不会：正在跑就重启一次让它吃到新 key。
      await _dsh.restartIfRunning();
      return;
    }
    final reason = switch (result.error) {
      'noModels' => l10n.labDshNeedModels,
      'noKey' => l10n.labApiNoKey,
      _ => result.error ?? '',
    };
    showMiuixToast(context, l10n.labApiWriteFailed(reason), error: true);
  }

  Future<void> _copy(String text) async {
    if (text.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showMiuixToast(context, l10n.copied);
  }

  Future<void> _openInBrowser() async {
    // dsh web 的一次性令牌只在启动日志里，裸地址打开是 401。
    // 有 Custom Tabs 走 Chromium 系浏览器，没有才回退系统浏览器。
    await openExternalUrl(context, _dsh.openUrl, useMiuix: true);
  }

  void _openInApp() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MiuixBrowserPage(
          initialUrl: _dsh.openUrl,
          title: AppLocalizations.of(context).labDshTitle,
        ),
      ),
    );
  }

  Future<void> _confirmUninstall() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showMiuixDialog<bool>(
      context: context,
      title: l10n.labDshUninstallTitle,
      message: l10n.labDshUninstallBody,
      actions: [
        MiuixDialogAction(
          label: l10n.labCancel,
          onPressed: (dialogContext) => Navigator.of(dialogContext).pop(false),
        ),
        MiuixDialogAction(
          label: l10n.labUninstall,
          destructive: true,
          onPressed: (dialogContext) => Navigator.of(dialogContext).pop(true),
        ),
      ],
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
    final colors = MiuixTheme.of(context).colors;
    return AnimatedBuilder(
      animation: Listenable.merge([_dsh, _node, _notify, _plugins]),
      builder: (context, _) => Material(
        type: MaterialType.transparency,
        child: MiuixScaffold(
          containerColor: colors.surface,
          topBar: MiuixBlurTopBar(
            title: l10n.labDshTitle,
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
                MiuixSmallTitle(l10n.labSectionStatus),
                const SizedBox(height: 10),
                _buildStatusCard(l10n, colors),
                const SizedBox(height: 22),
                MiuixSmallTitle(l10n.labSectionInstall),
                const SizedBox(height: 10),
                _buildInstallCard(l10n, colors),
                const SizedBox(height: 22),
                MiuixSmallTitle(l10n.labApiConfig),
                const SizedBox(height: 10),
                _buildApiCard(l10n, colors),
                if (_dsh.installed) ...[
                  const SizedBox(height: 22),
                  MiuixSmallTitle(l10n.labDshPlugins),
                  const SizedBox(height: 10),
                  _buildPluginsCard(l10n, colors),
                ],
                if (Platform.isAndroid || Platform.isWindows) ...[
                  const SizedBox(height: 22),
                  MiuixSmallTitle(l10n.labNotifySection),
                  const SizedBox(height: 10),
                  _buildNotificationCard(l10n, colors),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- 运行状态 ----

  Widget _buildStatusCard(AppLocalizations l10n, MiuixColors colors) {
    final dsh = _dsh;
    final status = dsh.running
        ? '${l10n.labRunning} · ${dsh.url}'
        : dsh.busy
        ? _phaseLabel(l10n, dsh)
        : l10n.labStopped;
    return MiuixGroupCard(
      insideMargin: EdgeInsets.zero,
      child: Column(
        children: [
          _infoRow(
            iconName: AppIconNames.info,
            fallback: Icons.info_outline,
            title: l10n.labStatus,
            value: status,
          ),
          const MiuixHorizontalDivider(),
          _infoRow(
            iconName: AppIconNames.update,
            fallback: Icons.tag,
            title: l10n.labVersion,
            value: dsh.version == null ? '—' : 'v${dsh.version}',
          ),
          const MiuixHorizontalDivider(),
          MiuixSwitchPreference(
            title: dsh.running ? l10n.labStop : l10n.labStart,
            startAction: MiuixAppIcon(
              dsh.running ? AppIconNames.closeCircle : AppIconNames.play,
              fallback: dsh.running
                  ? Icons.power_settings_new
                  : Icons.play_arrow,
              size: 24,
            ),
            value: dsh.enabled,
            onChanged: (v) {
              if (dsh.busy && !dsh.running) return;
              dsh.setEnabled(!dsh.running);
            },
          ),
          if (dsh.running) ...[
            const MiuixHorizontalDivider(),
            _actionRow(
              iconName: AppIconNames.share,
              fallback: Icons.open_in_browser,
              title: l10n.labOpen,
              summary: dsh.openUrl,
              onTap: _openInBrowser,
            ),
            const MiuixHorizontalDivider(),
            _actionRow(
              iconName: AppIconNames.link,
              fallback: Icons.language,
              title: l10n.labDshOpenInApp,
              onTap: _openInApp,
            ),
          ],
          const MiuixHorizontalDivider(),
          _actionRow(
            iconName: AppIconNames.note,
            fallback: Icons.article_outlined,
            title: l10n.labLogs,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const MiuixDshLogsPage()),
            ),
          ),
          if (dsh.error != null) ...[
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

  // ---- 安装 ----

  Widget _buildInstallCard(AppLocalizations l10n, MiuixColors colors) {
    final dsh = _dsh;
    final shizukuMode = _node.runnerMode == NodeRunnerMode.shizuku;
    return MiuixGroupCard(
      insideMargin: EdgeInsets.zero,
      child: Column(
        children: [
          MiuixFieldRow(
            iconName: AppIconNames.folder,
            fallbackIcon: Icons.folder_outlined,
            title: l10n.labInstallLocation,
            value: dsh.installed ? dsh.installDir! : dsh.displayRoot,
            endActions: dsh.canChooseLocation && !dsh.busy
                ? [
                    MiuixTextButton(
                      l10n.labChooseLocation,
                      onPressed: dsh.chooseLocation,
                    ),
                  ]
                : const [],
          ),
          const MiuixHorizontalDivider(),
          MiuixFieldRow(
            iconName: AppIconNames.layers,
            fallbackIcon: Icons.memory_outlined,
            title: l10n.labNodeStatus,
            value: labNodeLineForService(
              l10n,
              isDesktop: dsh.isDesktop,
              isAndroid: Platform.isAndroid,
              nodeAvailable: dsh.nodeAvailable,
              nodeVersion: dsh.nodeVersion,
              npmVersion: dsh.npmVersion,
            ),
            endActions: dsh.isDesktop || Platform.isAndroid
                ? [
                    MiuixTextButton(
                      l10n.labRecheck,
                      onPressed: () async {
                        await dsh.refreshNodeStatus();
                        if (!mounted) return;
                        showMiuixToast(
                          context,
                          dsh.nodeAvailable
                              ? dsh.nodeVersion ?? ''
                              : l10n.labNodeMissing,
                          error: !dsh.nodeAvailable,
                        );
                      },
                    ),
                  ]
                : const [],
          ),
          if (dsh.isDesktop && !dsh.nodeAvailable) ...[
            const MiuixHorizontalDivider(),
            _actionRow(
              iconName: AppIconNames.download,
              fallback: Icons.download_outlined,
              title: l10n.labNodeDownload,
              onTap: () => launchUrl(
                Uri.parse('https://nodejs.org/zh-cn/download'),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ],
          // Android：系统里没有 Node，运行时与执行通道都在这页装/切。
          if (Platform.isAndroid) ...[
            if (_node.busy) ...[
              const MiuixHorizontalDivider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: LinearProgressIndicator(
                  value: _node.phase == LabServicePhase.downloading
                      ? _node.progress
                      : null,
                  minHeight: 3,
                ),
              ),
            ],
            if (!_node.installed) ...[
              const MiuixHorizontalDivider(),
              _actionRow(
                iconName: AppIconNames.download,
                fallback: Icons.download_outlined,
                title: l10n.labNodeRuntimeInstall,
                enabled: !_node.busy,
                onTap: _node.install,
              ),
            ] else ...[
              const MiuixHorizontalDivider(),
              MiuixFieldRow(
                iconName: AppIconNames.layers,
                fallbackIcon: Icons.sensors_outlined,
                title: l10n.labNodeRunnerMode,
                value: shizukuMode
                    ? l10n.labRunnerShizuku
                    : l10n.labRunnerDirect,
                endActions: const [_ForwardChevron()],
                onTap: _pickRunnerMode,
              ),
              if (shizukuMode) ...[
                const MiuixHorizontalDivider(),
                MiuixFieldRow(
                  iconName: AppIconNames.lock,
                  fallbackIcon: Icons.admin_panel_settings_outlined,
                  title: l10n.labShizukuStatus,
                  value: _shizukuOk != true
                      ? l10n.labShizukuNotDetected
                      : _shizukuGranted == true
                      ? l10n.labShizukuGranted
                      : l10n.labShizukuNotGranted,
                  endActions: _shizukuOk == true && _shizukuGranted != true
                      ? [
                          MiuixTextButton(
                            l10n.labShizukuRequest,
                            onPressed: _requestShizuku,
                          ),
                        ]
                      : const [],
                ),
              ],
            ],
            if (_node.error != null) ...[
              const MiuixHorizontalDivider(),
              MiuixBasicComponent(
                title: l10n.labError,
                summary: _node.error,
                titleColor: MiuixBasicComponentColors(
                  color: colors.error,
                  disabledColor: colors.disabledOnSecondaryVariant,
                ),
                summaryColor: MiuixBasicComponentColors(
                  color: colors.error,
                  disabledColor: colors.disabledOnSecondaryVariant,
                ),
                startAction: const MiuixAppIcon(
                  AppIconNames.report,
                  fallback: Icons.error_outline,
                  size: 24,
                ),
                endActions: const [],
              ),
            ],
          ],
          if (dsh.installed) ...[
            if (!dsh.nodeAvailable) ...[
              const MiuixHorizontalDivider(),
              _actionRow(
                iconName: AppIconNames.layers,
                fallback: Icons.inventory_2_outlined,
                title: l10n.labInstallDeps,
                enabled: !dsh.busy,
                onTap: dsh.installDependencies,
              ),
            ],
            if (dsh.isDesktop) ...[
              const MiuixHorizontalDivider(),
              _actionRow(
                iconName: AppIconNames.folder,
                fallback: Icons.folder_open_outlined,
                title: l10n.labOpenFolder,
                onTap: dsh.openInstallFolder,
              ),
            ],
            const MiuixHorizontalDivider(),
            _actionRow(
              iconName: AppIconNames.delete,
              fallback: Icons.delete_outline,
              title: l10n.labUninstall,
              destructive: true,
              enabled: !dsh.busy,
              onTap: _confirmUninstall,
            ),
          ] else ...[
            const MiuixHorizontalDivider(),
            _actionRow(
              iconName: AppIconNames.download,
              fallback: Icons.downloading,
              title: l10n.labInstall,
              enabled: !dsh.busy,
              onTap: dsh.install,
            ),
          ],
        ],
      ),
    );
  }

  // ---- 模型配置 ----

  Widget _buildApiCard(AppLocalizations l10n, MiuixColors colors) {
    final dsh = _dsh;
    final config = _config;
    final baseUrl = config == null ? '—' : dsh.baseUrlOf(config);
    final key = config == null ? null : dsh.apiKeyOf(config);
    final canWrite =
        config != null && key != null && dsh.installed && dsh.models.isNotEmpty;
    return MiuixGroupCard(
      insideMargin: EdgeInsets.zero,
      child: Column(
        children: [
          MiuixFieldRow(
            iconName: AppIconNames.store,
            fallbackIcon: Icons.category_outlined,
            title: l10n.labApiGroup,
            value: dsh.apiGroupId == null
                ? l10n.labApiGroupNone
                : _groupName(dsh.apiGroupId),
            endActions: config == null ? const [] : const [_ForwardChevron()],
            onTap: config == null ? null : _pickGroup,
          ),
          const MiuixHorizontalDivider(),
          MiuixFieldRow(
            iconName: AppIconNames.layers,
            fallbackIcon: Icons.view_in_ar_outlined,
            title: l10n.labApiModel,
            value: dsh.models.isEmpty
                ? '—'
                : l10n.labApiModelCount('${dsh.models.length}'),
            endActions: config == null ? const [] : const [_ForwardChevron()],
            onTap: config == null ? null : _pickModels,
          ),
          const MiuixHorizontalDivider(),
          MiuixFieldRow(
            iconName: AppIconNames.check,
            fallbackIcon: Icons.star_outline,
            title: l10n.labDshDefaultModel,
            value: dsh.defaultModel ?? '—',
            endActions: dsh.models.isEmpty
                ? const []
                : const [_ForwardChevron()],
            onTap: dsh.models.isEmpty ? null : _pickDefaultModel,
          ),
          const MiuixHorizontalDivider(),
          MiuixFieldRow(
            iconName: AppIconNames.link,
            fallbackIcon: Icons.link,
            title: l10n.labApiBaseUrl,
            value: baseUrl,
            endActions: config == null ? const [] : const [_CopyGlyph()],
            onTap: config == null ? null : () => _copy(baseUrl),
          ),
          const MiuixHorizontalDivider(),
          if (key == null)
            MiuixBasicComponent(
              title: l10n.labApiKey,
              summary: l10n.labApiNoKey,
              summaryColor: MiuixBasicComponentColors(
                color: colors.error,
                disabledColor: colors.disabledOnSecondaryVariant,
              ),
              startAction: const MiuixAppIcon(
                AppIconNames.lock,
                fallback: Icons.key_outlined,
                size: 24,
              ),
              endActions: const [],
            )
          else
            MiuixFieldRow(
              iconName: AppIconNames.lock,
              fallbackIcon: Icons.key_outlined,
              title: l10n.labApiKey,
              value: _maskKey(key),
              endActions: const [_CopyGlyph()],
              onTap: () => _copy(key),
            ),
          const MiuixHorizontalDivider(),
          MiuixFieldRow(
            iconName: AppIconNames.file,
            fallbackIcon: Icons.description_outlined,
            title: l10n.labDshConfigPath,
            value: dsh.configPath,
            endActions: const [_CopyGlyph()],
            onTap: () => _copy(dsh.configPath),
          ),
          if (Platform.isAndroid) ...[
            const MiuixHorizontalDivider(),
            MiuixSwitchPreference(
              title: l10n.labDshCompat,
              summary: l10n.labDshCompatDesc,
              value: dsh.androidCompatEnabled,
              onChanged: (v) async {
                await dsh.setAndroidCompat(v);
                await dsh.restartIfRunning();
              },
            ),
          ],
          const MiuixHorizontalDivider(),
          MiuixBasicComponent(
            title: l10n.labDshWrite,
            summary: dsh.models.isEmpty ? l10n.labDshNeedModels : null,
            startAction: const MiuixAppIcon(
              AppIconNames.check,
              fallback: Icons.check_circle_outline,
              size: 24,
            ),
            enabled: canWrite,
            onClick: canWrite ? _applyApi : null,
            endActions: const [],
          ),
          if (dsh.installed) ...[
            const MiuixHorizontalDivider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: MiuixText(
                l10n.labDshWriteHint,
                fontSize: 12,
                color: colors.onSurfaceVariantSummary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---- 插件 ----

  Widget _buildPluginsCard(AppLocalizations l10n, MiuixColors colors) {
    final rows = <Widget>[];
    rows.add(
      MiuixArrowPreference(
        title: l10n.pluginManagerTitle,
        summary: l10n.pluginManagerSubtitle,
        onClick: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const MiuixDshPluginsPage(),
          ),
        ),
      ),
    );
    if (_plugins.supportedIds().isNotEmpty) {
      rows.add(const MiuixHorizontalDivider());
    }
    for (final spec in kDshPlugins) {
      if (!_plugins.supported(spec.id)) continue;
      if (rows.isNotEmpty) rows.add(const MiuixHorizontalDivider());
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
      rows.add(
        MiuixSwitchPreference(
          title: title,
          summary: state.busy
              ? l10n.labDshPluginInstalling
              : (state.error ?? desc),
          value: state.enabled,
          enabled: !state.busy,
          onChanged: (value) => _togglePlugin(spec, value),
        ),
      );
    }
    if (rows.isNotEmpty) rows.add(const MiuixHorizontalDivider());
    rows.add(
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: MiuixText(
          l10n.labDshPluginRestartHint,
          fontSize: 12,
          color: colors.onSurfaceVariantSummary,
        ),
      ),
    );
    return MiuixGroupCard(
      insideMargin: EdgeInsets.zero,
      child: Column(children: rows),
    );
  }

  Future<void> _togglePlugin(DshPluginSpec spec, bool value) async {
    final l10n = AppLocalizations.of(context);
    final ok = await _plugins.setEnabled(spec.id, value);
    if (!mounted || ok) return;
    showMiuixToast(
      context,
      '${l10n.labDshPluginFailed}：${_plugins.stateOf(spec.id).error ?? ''}',
      error: true,
    );
  }

  // ---- 通知 / 任务模式 ----

  Widget _buildNotificationCard(AppLocalizations l10n, MiuixColors colors) {
    final permission = _notify.permission;
    final promoted = _notify.promoted;
    final battery = _notify.batteryIgnored;
    return MiuixGroupCard(
      insideMargin: EdgeInsets.zero,
      child: Column(
        children: [
          // 权限 / 实时更新 / 电池优化是安卓系统门槛；Windows 没有这一套。
          if (Platform.isAndroid) ...[
            MiuixSwitchPreference(
              title: l10n.labNotifyPermission,
              summary: l10n.labNotifyPermissionDesc,
              value: permission ?? false,
              onChanged: (v) async {
                if (v && permission != true) {
                  await _notify.requestPermission();
                  return;
                }
                await _notify.openNotificationSettings();
              },
            ),
            const MiuixHorizontalDivider(),
            _infoRow(
              iconName: AppIconNames.update,
              fallback: Icons.notifications_active_outlined,
              title: l10n.labNotifyLiveUpdate,
              value: promoted == true
                  ? l10n.labNotifyPromoted
                  : l10n.labNotifyNotPromoted,
            ),
            const MiuixHorizontalDivider(),
            MiuixSwitchPreference(
              title: l10n.labNotifyBattery,
              summary: l10n.labNotifyBatteryDesc,
              value: battery ?? false,
              onChanged: (v) async {
                if (v && battery != true) {
                  await _notify.requestIgnoreBattery();
                  return;
                }
                await AndroidNotifications.openBatteryOptimizationSettings();
              },
            ),
            const MiuixHorizontalDivider(),
          ],
          _actionRow(
            iconName: AppIconNames.share,
            fallback: Icons.send_outlined,
            title: l10n.labNotifyTest,
            onTap: _sendTestNotification,
          ),
          const MiuixHorizontalDivider(),
          MiuixSwitchPreference(
            title: l10n.labDshTaskHint,
            summary: l10n.labDshTaskHintDesc,
            value: _dsh.taskHintEnabled,
            onChanged: (v) => _dsh.setTaskHint(v),
          ),
          const MiuixHorizontalDivider(),
          _actionRow(
            iconName: AppIconNames.play,
            fallback: Icons.play_arrow,
            title: l10n.labDshRunTask,
            summary: l10n.labDshRunTaskDesc,
            onTap: _dsh.installed && _dsh.canRun ? _runTask : null,
          ),
          if (Platform.isAndroid) ...[
            const MiuixHorizontalDivider(),
            _actionRow(
              iconName: AppIconNames.settings,
              fallback: Icons.settings_outlined,
              title: l10n.labNotifyOpenSettings,
              onTap: () => _notify.openNotificationSettings(),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _sendTestNotification() async {
    final l10n = AppLocalizations.of(context);
    final result = await _notify.sendTestNotification(
      title: l10n.labNotifyTest,
      text: l10n.labNotifySection,
      steps: const ['准备', '执行', '收尾'],
    );
    if (!mounted) return;
    showMiuixToast(
      context,
      result.posted ? l10n.labNotifyTestSent : l10n.labNotifyTestFailed,
      error: !result.posted,
    );
  }

  Future<void> _runTask() async {
    final l10n = AppLocalizations.of(context);
    if (DshTaskRunner.instance.running) {
      showMiuixToast(context, l10n.labDshTaskBusy, error: true);
      return;
    }
    final controller = TextEditingController();
    final task = await showMiuixDialog<String>(
      context: context,
      title: l10n.labDshTaskPrompt,
      content: MiuixTextField(
        controller: controller,
        label: l10n.labDshRunTaskDesc,
        useLabelAsPlaceholder: true,
        autofocus: true,
        maxLines: 4,
        textInputAction: TextInputAction.done,
      ),
      actions: [
        MiuixDialogAction(
          label: l10n.cancel,
          onPressed: (dialogContext) => Navigator.of(dialogContext).pop(),
        ),
        MiuixDialogAction(
          label: l10n.labDshRunTask,
          onPressed: (dialogContext) =>
              Navigator.of(dialogContext).pop(controller.text),
        ),
      ],
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
    showMiuixToast(context, l10n.labDshTaskStarted);
  }

  // ---- 行构造 ----

  Widget _infoRow({
    required String iconName,
    required IconData fallback,
    required String title,
    required String value,
  }) {
    return MiuixFieldRow(
      iconName: iconName,
      fallbackIcon: fallback,
      title: title,
      value: value,
      endActions: const [],
    );
  }

  Widget _actionRow({
    required String iconName,
    required IconData fallback,
    required String title,
    String? summary,
    required VoidCallback? onTap,
    bool enabled = true,
    bool destructive = false,
  }) {
    final colors = MiuixTheme.of(context).colors;
    final tint = destructive
        ? colors.error
        : enabled
        ? colors.onSurface
        : colors.disabledOnSecondaryVariant;
    return MiuixBasicComponent(
      title: title,
      summary: summary,
      titleColor: MiuixBasicComponentColors(
        color: destructive ? colors.error : colors.onSurface,
        disabledColor: colors.disabledOnSecondaryVariant,
      ),
      startAction: MiuixAppIcon(
        iconName,
        fallback: fallback,
        size: 24,
        color: tint,
      ),
      enabled: enabled,
      onClick: onTap,
      endActions: const [],
    );
  }

  String _maskKey(String key) {
    if (key.length <= 12) return key;
    return '${key.substring(0, 8)}…${key.substring(key.length - 4)}';
  }
}

class _ForwardChevron extends StatelessWidget {
  const _ForwardChevron();

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixAppIcon(
      AppIconNames.forward,
      fallback: Icons.chevron_right,
      size: 18,
      color: colors.onSurfaceVariantActions,
    );
  }
}

class _CopyGlyph extends StatelessWidget {
  const _CopyGlyph();

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixAppIcon(
      AppIconNames.copy,
      fallback: Icons.copy_outlined,
      size: 20,
      color: colors.onSurfaceVariantActions,
    );
  }
}
