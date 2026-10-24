// lib/ui/miuix/miuix_lab_sillytavern_page.dart
//
// SillyTavern 的「更多设置」（miuix 版）：从实验室首页那一行点进来。
//
// 信息架构：
//   1. 运行状态与启停（首页那个开关的详细版）
//   2. 安装：位置 / Node 检测 / 依赖 / 目录 / 卸载
//   3. API 配置：把本机代理的某个模型组接给 SillyTavern，
//      底部弹窗选组（再选模型），一键写进 ST 的 settings.json + secrets.json
//
// 卡片设计与「编辑上游」页同一套（参考 CMFA）：`MiuixGroupCard` +
// `insideMargin: EdgeInsets.zero`，一行一个字段（图标 + 字段名 + 当前值），
// 行间用 `MiuixHorizontalDivider`；不再自绘 `_InfoRow`/`_ActionRow`。
// 顶栏接 [MiuixShortPageScrollBehavior]，滚动可折叠大标题（含桌面滚轮）。
//
// 业务全在 [SillyTavernService]；端口与密钥从 [ServerController] 的配置里读。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../models/config_profile.dart';
import '../../models/proxy_config.dart';
import '../../services/lab/silly_tavern_service.dart';
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

class MiuixLabSillyTavernPage extends StatefulWidget {
  const MiuixLabSillyTavernPage({super.key, this.controller});

  final ServerController? controller;

  @override
  State<MiuixLabSillyTavernPage> createState() =>
      _MiuixLabSillyTavernPageState();
}

class _MiuixLabSillyTavernPageState extends State<MiuixLabSillyTavernPage> {
  final SillyTavernService _st = SillyTavernService.instance;

  /// 二级页统一的可折叠大标题行为；`MiuixBlurTopBar` 读它，
  /// `MiuixShortPageScrollListener` 在外层把滚动/滚轮事件喂给它。
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();

  @override
  void initState() {
    super.initState();
    _st.init();
  }

  @override
  void dispose() {
    _behavior.state.dispose();
    super.dispose();
  }

  /// 只在 Provider 树里真给了 ProfileStore 时才用（测试/独立预览可能没有）。
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
                              '${_st.modelsOfGroup(config, g.id).length}',
                            ),
                            selected: g.id == _st.apiGroupId,
                            enabled: _st.modelsOfGroup(config, g.id).isNotEmpty,
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
    // 换组就清掉旧模型：那个模型可能不在新组里。
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
      showMiuixToast(context, l10n.labApiNeedGroup, error: true);
      return;
    }
    final resolved = _resolved();
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
                  l10n.labApiPickModel,
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
                            selected: m == resolved?.model,
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
    await _st.setApiSelection(groupId: gid, model: picked);
  }

  Future<void> _applyApi() async {
    final l10n = AppLocalizations.of(context);
    final cfg = _resolved();
    if (cfg == null) {
      showMiuixToast(context, l10n.labApiNeedGroup, error: true);
      return;
    }
    if (!cfg.hasKey) {
      showMiuixToast(context, l10n.labApiNoKey, error: true);
      return;
    }
    final result = await _st.applyApiConfig(cfg);
    if (!mounted) return;
    if (result.ok) {
      showMiuixToast(context, l10n.labApiWriteOk);
    } else {
      final reason = switch (result.error) {
        'notInstalled' => l10n.labNotInstalled,
        'noUserData' => l10n.labApiNoUserData,
        'running' => l10n.labApiStopFirst,
        _ => result.error ?? '',
      };
      showMiuixToast(context, l10n.labApiWriteFailed(reason), error: true);
    }
  }

  Future<void> _copy(String text, String okMessage) async {
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showMiuixToast(context, okMessage);
  }

  Future<void> _openInBrowser() async {
    // ST 是重前端页面：有 Custom Tabs 就交给 Chromium 系浏览器
    await openExternalUrl(context, _st.url, useMiuix: true);
  }

  Future<void> _confirmUninstall() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showMiuixDialog<bool>(
      context: context,
      title: l10n.labUninstallTitle,
      message: l10n.labUninstallBody,
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
    final colors = MiuixTheme.of(context).colors;
    return AnimatedBuilder(
      animation: _st,
      builder: (context, _) => Material(
        type: MaterialType.transparency,
        child: MiuixScaffold(
          containerColor: colors.surface,
          topBar: MiuixBlurTopBar(
            title: 'SillyTavern',
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- 运行状态 ----

  Widget _buildStatusCard(AppLocalizations l10n, MiuixColors colors) {
    final st = _st;
    final status = st.running
        ? '${l10n.labRunning} · ${st.url}'
        : st.busy
        ? _phaseLabel(l10n, st)
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
            value: st.version == null ? '—' : 'v${st.version}',
          ),
          const MiuixHorizontalDivider(),
          // 启停开关：跟「编辑上游」页的「启用」行同一套。
          MiuixSwitchPreference(
            title: st.running ? l10n.labStop : l10n.labStart,
            startAction: MiuixAppIcon(
              st.running ? AppIconNames.closeCircle : AppIconNames.play,
              fallback: st.running
                  ? Icons.power_settings_new
                  : Icons.play_arrow,
              size: 24,
            ),
            value: st.enabled,
            onChanged: (v) {
              if (st.busy && !st.running) return;
              st.setEnabled(!st.running);
            },
          ),
          if (st.running) ...[
            const MiuixHorizontalDivider(),
            _actionRow(
              iconName: AppIconNames.share,
              fallback: Icons.open_in_browser,
              title: l10n.labOpen,
              summary: st.url,
              onTap: _openInBrowser,
            ),
          ],
          const MiuixHorizontalDivider(),
          // 启动后是否让 ST 自己拉起系统浏览器：默认关，避免一开服务就弹窗。
          MiuixSwitchPreference(
            title: l10n.labAutoOpenBrowser,
            summary: l10n.labAutoOpenBrowserDesc,
            startAction: const MiuixAppIcon(
              AppIconNames.link,
              fallback: Icons.public,
              size: 24,
            ),
            value: st.autoOpenBrowser,
            onChanged: st.setAutoOpenBrowser,
          ),
          if (st.error != null) ...[
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

  // ---- 安装 ----

  Widget _buildInstallCard(AppLocalizations l10n, MiuixColors colors) {
    final st = _st;
    return MiuixGroupCard(
      insideMargin: EdgeInsets.zero,
      child: Column(
        children: [
          MiuixFieldRow(
            iconName: AppIconNames.folder,
            fallbackIcon: Icons.folder_outlined,
            title: l10n.labInstallLocation,
            value: st.installed ? st.installDir! : st.displayRoot,
            endActions: st.canChooseLocation && !st.busy
                ? [
                    MiuixTextButton(
                      l10n.labChooseLocation,
                      onPressed: st.chooseLocation,
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
              isDesktop: st.isDesktop,
              isAndroid: Platform.isAndroid,
              nodeAvailable: st.nodeAvailable,
              nodeVersion: st.nodeVersion,
              npmVersion: st.npmVersion,
            ),
            endActions: st.isDesktop || Platform.isAndroid
                ? [
                    MiuixTextButton(
                      l10n.labRecheck,
                      onPressed: () async {
                        await st.refreshNodeStatus();
                        if (!mounted) return;
                        showMiuixToast(
                          context,
                          st.nodeAvailable
                              ? st.nodeVersion ?? ''
                              : l10n.labNodeMissing,
                          error: !st.nodeAvailable,
                        );
                      },
                    ),
                  ]
                : const [],
          ),
          if (st.isDesktop && !st.nodeAvailable) ...[
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
          if (st.installed) ...[
            if (!st.depsInstalled) ...[
              const MiuixHorizontalDivider(),
              _actionRow(
                iconName: AppIconNames.layers,
                fallback: Icons.inventory_2_outlined,
                title: l10n.labInstallDeps,
                enabled: !st.busy,
                onTap: st.installDependencies,
              ),
            ],
            if (st.isDesktop) ...[
              const MiuixHorizontalDivider(),
              _actionRow(
                iconName: AppIconNames.folder,
                fallback: Icons.folder_open_outlined,
                title: l10n.labOpenFolder,
                onTap: st.openInstallFolder,
              ),
            ],
            const MiuixHorizontalDivider(),
            _actionRow(
              iconName: AppIconNames.delete,
              fallback: Icons.delete_outline,
              title: l10n.labUninstall,
              destructive: true,
              enabled: !st.busy,
              onTap: _confirmUninstall,
            ),
          ] else ...[
            const MiuixHorizontalDivider(),
            _actionRow(
              iconName: AppIconNames.download,
              fallback: Icons.downloading,
              title: l10n.labInstall,
              enabled: !st.busy,
              onTap: st.install,
            ),
          ],
        ],
      ),
    );
  }

  // ---- API 配置 ----

  Widget _buildApiCard(AppLocalizations l10n, MiuixColors colors) {
    final cfg = _resolved();
    final config = _config;
    final hasService = config != null;
    final baseUrl = config == null ? '—' : _st.baseUrlOf(config);
    final key = config == null ? null : _st.apiKeyOf(config);
    final canWrite = cfg != null && cfg.hasKey && _st.installed;
    return MiuixGroupCard(
      insideMargin: EdgeInsets.zero,
      child: Column(
        children: [
          MiuixFieldRow(
            iconName: AppIconNames.store,
            fallbackIcon: Icons.category_outlined,
            title: l10n.labApiGroup,
            value: _st.apiGroupId == null
                ? l10n.labApiGroupNone
                : _groupName(_st.apiGroupId),
            endActions: hasService ? const [_ForwardChevron()] : const [],
            onTap: hasService ? _pickGroup : null,
          ),
          const MiuixHorizontalDivider(),
          MiuixFieldRow(
            iconName: AppIconNames.layers,
            fallbackIcon: Icons.view_in_ar_outlined,
            title: l10n.labApiModel,
            value: cfg?.model ?? '—',
            endActions: hasService ? const [_ForwardChevron()] : const [],
            onTap: hasService ? _pickModel : null,
          ),
          const MiuixHorizontalDivider(),
          MiuixFieldRow(
            iconName: AppIconNames.link,
            fallbackIcon: Icons.link,
            title: l10n.labApiBaseUrl,
            value: baseUrl,
            endActions: config == null ? const [] : const [_CopyGlyph()],
            onTap: config == null ? null : () => _copy(baseUrl, l10n.copied),
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
              onTap: () => _copy(key, l10n.copied),
            ),
          const MiuixHorizontalDivider(),
          MiuixBasicComponent(
            title: l10n.labApiWrite,
            summary: cfg?.model,
            startAction: const MiuixAppIcon(
              AppIconNames.check,
              fallback: Icons.check_circle_outline,
              size: 24,
            ),
            enabled: canWrite,
            onClick: canWrite ? _applyApi : null,
            endActions: const [],
          ),
        ],
      ),
    );
  }

  // ---- 行构造（编辑上游页同款） ----

  /// 只读信息行：图标 + 字段名 + 当前值，行尾不带任何动作。
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

  /// 动作行：整行可点（可选禁用 / 红色破坏性）。
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

/// 行尾的「下一级」箭头（选组 / 选模型这类跳转行用）。
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

/// 行尾的「复制」小图标（接口地址 / API Key 行用）。
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
