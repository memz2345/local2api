import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField;
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/network_utils.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/tts/tts_backend_policy.dart';
import 'package:local2api/services/tts/tts_chat_speak.dart';
import 'package:local2api/services/tts/tts_download_service.dart';
import 'package:local2api/services/tts/tts_engine.dart';
import 'package:local2api/services/tts/tts_model_service.dart';
import 'package:local2api/services/tts/tts_speech_service.dart';
import 'package:local2api/services/tts/tts_settings.dart';
import 'package:local2api/ui/miuix/miuix_tts_playground_page.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_dialog.dart';
import 'package:local2api/widgets/miuix/miuix_field_editor.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';

/// 「本地 TTS（Qwen3-TTS）」卡片（miuix 版，挂在「TTS 设置」页）。
///
/// 承担四件事：
/// 1. 模型管理：下载（断点续传 + 进度条）/ 删除；
/// 2. 一键创建「本地 TTS」上游（新建上游页的模式列表不含它，入口在这）；
/// 3. 推理后端偏好：自动（高通优先 NPU）/ NPU / GPU / CPU；
/// 4. 试听：引擎加载 → 合成 → 播放一条样例文本。
///
/// 下载进度与引擎状态都是全局单例的 ChangeNotifier，离开本页任务照跑，
/// 回来即见。模型安装状态是文件系统事实（异步），由本 State 拉着刷新：
/// 进页 / 下载状态变化 / 删除后各刷一次。
class MiuixTtsSection extends StatefulWidget {
  const MiuixTtsSection({super.key, required this.controller});

  final ServerController controller;

  @override
  State<MiuixTtsSection> createState() => _MiuixTtsSectionState();
}

class _MiuixTtsSectionState extends State<MiuixTtsSection> {
  TtsModelState _modelState = TtsModelState.notInstalled;

  /// 上一次的下载运行态，用来察觉「下载结束」那一拍去刷新安装状态。
  bool _wasDownloading = false;

  @override
  void initState() {
    super.initState();
    // 偏好与下载服务的初始化都是幂等的：设置页每次进来调一下，
    // 应用启动时没人调也没关系（首进设置页兜底）。
    unawaited(TtsSettings.instance.load());
    unawaited(TtsDownloadService.instance.initialize());
    unawaited(_refreshState());
  }

  Future<void> _refreshState() async {
    final state = await TtsModelService.state();
    if (!mounted) return;
    setState(() => _modelState = state);
  }

  String _deviceLabel(AppLocalizations l10n, TtsInferenceDevicePreference p) =>
      switch (p) {
        TtsInferenceDevicePreference.auto => l10n.ttsDeviceAuto,
        TtsInferenceDevicePreference.npu => l10n.ttsDeviceNpu,
        TtsInferenceDevicePreference.gpu => l10n.ttsDeviceGpu,
        TtsInferenceDevicePreference.cpu => l10n.ttsDeviceCpu,
      };

  String _stateLabel(AppLocalizations l10n, TtsDownloadService download) {
    if (download.isRunning) {
      final received = (download.received / 1024 / 1024).round();
      final total = (download.total / 1024 / 1024).round();
      return l10n.localTtsDownloadProgress('$received', '$total');
    }
    return switch (_modelState) {
      TtsModelState.installed => l10n.localTtsStateInstalled,
      TtsModelState.partial => l10n.localTtsStatePartial,
      TtsModelState.notInstalled => l10n.localTtsStateNotInstalled,
    };
  }

  String _speechStatusLabel(AppLocalizations l10n, TtsSpeechStatus s) =>
      switch (s) {
        TtsSpeechStatus.idle => l10n.localTtsStatusIdle,
        TtsSpeechStatus.preparing => l10n.localTtsStatusPreparing,
        TtsSpeechStatus.synthesizing => l10n.localTtsStatusSynthesizing,
        TtsSpeechStatus.playing => l10n.localTtsStatusPlaying,
      };

  String _providerLabel(AppLocalizations l10n) {
    final p = TtsSettings.instance.provider;
    return switch (p) {
      TtsSettings.providerOff => l10n.ttsProviderOff,
      TtsSettings.providerLocal => l10n.ttsProviderLocal,
      _ => p,
    };
  }

  /// 设计 / 克隆模型的行摘要：没配就「关闭」。
  String _routeModelLabel(AppLocalizations l10n, String model) =>
      model == TtsSettings.providerOff ? l10n.ttsProviderOff : model;

  /// 设计 / 克隆模型共用选择器：关闭 / 本地 Qwen3-TTS / 能发声的云端模型。
  /// 本地引擎克隆走 speakerReference；本地没有「文本设计音色」能力，
  /// 设计路线选它就退化为默认音色。
  Future<void> _pickRouteModel({
    required String title,
    required String current,
    required Future<void> Function(String) onPicked,
  }) async {
    final l10n = AppLocalizations.of(context);
    final cloud = ChatTts.cloudModelNames(widget.controller.config);
    final options = <(String, String)>[
      (TtsSettings.providerOff, l10n.ttsProviderOff),
      (TtsSettings.providerLocal, l10n.ttsProviderLocal),
      for (final name in cloud) (name, name),
    ];
    final picked = await showMiuixDialog<String>(
      context: context,
      title: title,
      content: _MiuixProviderDialogBody(
        current: current,
        options: options,
        emptyHint: cloud.isEmpty ? l10n.ttsProviderNoneHint : null,
      ),
      actions: [
        MiuixDialogAction(
          label: l10n.cancel,
          onPressed: (ctx) => Navigator.of(ctx).pop(),
        ),
      ],
    );
    if (picked == null) return;
    await onPicked(picked);
  }

  /// 选默认语音设计模型（角色卡没样本时的合成路线）。
  Future<void> _pickDesignModel() async {
    final l10n = AppLocalizations.of(context);
    await _pickRouteModel(
      title: l10n.ttsDesignModelLabel,
      current: TtsSettings.instance.designModel,
      onPicked: TtsSettings.instance.setDesignModel,
    );
  }

  /// 选默认克隆模型（角色卡有样本时的合成路线）。
  Future<void> _pickCloneModel() async {
    final l10n = AppLocalizations.of(context);
    await _pickRouteModel(
      title: l10n.ttsCloneModelLabel,
      current: TtsSettings.instance.cloneModel,
      onPicked: TtsSettings.instance.setCloneModel,
    );
  }

  /// 编辑音色设计提示词（voicedesign 的 user 消息；留空用默认文案）。
  Future<void> _editDesignPrompt() async {
    final l10n = AppLocalizations.of(context);
    final current = TtsSettings.instance.designPrompt;
    final picked = await showMiuixFieldEditor(
      context,
      label: l10n.ttsDesignPromptLabel,
      initial: current,
      hint: TtsSettings.defaultDesignPrompt,
      maxLines: 6,
    );
    if (picked == null) return;
    await TtsSettings.instance.setDesignPrompt(picked);
  }

  /// 选默认 TTS 服务商：关闭 / 本地 / 配置里能发声的云端模型。
  Future<void> _pickProvider() async {
    final l10n = AppLocalizations.of(context);
    final cloud = ChatTts.cloudModelNames(widget.controller.config);
    final options = <(String, String)>[
      (TtsSettings.providerOff, l10n.ttsProviderOff),
      (TtsSettings.providerLocal, l10n.ttsProviderLocal),
      for (final name in cloud) (name, name),
    ];
    final picked = await showMiuixDialog<String>(
      context: context,
      title: l10n.ttsProviderLabel,
      content: _MiuixProviderDialogBody(
        current: TtsSettings.instance.provider,
        options: options,
        emptyHint: cloud.isEmpty ? l10n.ttsProviderNoneHint : null,
      ),
      actions: [
        MiuixDialogAction(
          label: l10n.cancel,
          onPressed: (ctx) => Navigator.of(ctx).pop(),
        ),
      ],
    );
    if (picked == null) return;
    await TtsSettings.instance.setProvider(picked);
  }

  Future<void> _pickDevice() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showMiuixDialog<TtsInferenceDevicePreference>(
      context: context,
      title: l10n.localTtsDevicePreference,
      content: _MiuixDeviceDialogBody(
        current: TtsSettings.instance.device,
        labelOf: (p) => _deviceLabel(l10n, p),
      ),
      actions: [
        MiuixDialogAction(
          label: l10n.cancel,
          onPressed: (ctx) => Navigator.of(ctx).pop(),
        ),
      ],
    );
    if (picked == null) return;
    await TtsSettings.instance.setDevice(picked);
    // 偏好变了要让引擎按新后端重载：已加载的就先卸掉（下次合成重新加载）。
    await TtsEngineManager.instance.release();
  }

  Future<void> _startDownload() async {
    await TtsDownloadService.instance.start();
    await _refreshState();
  }

  /// 一键创建「本地 TTS」上游（幂等：已存在只提示，不重复建）。
  ///
  /// 新建上游页的「模式」列表刻意不放本地 TTS（那是聊天上游的档位），
  /// 本地 TTS 的入口收敛在这里：模型名固定 qwen3-tts，建好即用。
  Future<void> _createUpstream() async {
    final l10n = AppLocalizations.of(context);
    final config = widget.controller.config;
    if (config.upstreams.any((u) => u.type == UpstreamType.localTts)) {
      showMiuixToast(context, l10n.localTtsUpstreamExists);
      return;
    }
    config.upstreams.add(
      Upstream(
        id: NetworkUtils.newId(),
        name: l10n.localTtsUpstreamName,
        type: UpstreamType.localTts,
        baseUrl: '',
        note: l10n.localTtsCreateUpstreamDesc,
        models: [ModelEntry(publicName: 'qwen3-tts')],
      ),
    );
    widget.controller.store.update(config);
    if (!mounted) return;
    showMiuixToast(context, l10n.localTtsUpstreamCreated);
  }

  Future<void> _deleteModel() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showMiuixDialog<bool>(
      context: context,
      title: l10n.localTtsDeleteConfirm,
      actions: [
        MiuixDialogAction(
          label: l10n.cancel,
          onPressed: (ctx) => Navigator.of(ctx).pop(false),
        ),
        MiuixDialogAction(
          label: l10n.deleteBtn,
          destructive: true,
          onPressed: (ctx) => Navigator.of(ctx).pop(true),
        ),
      ],
    );
    if (ok != true) return;
    TtsDownloadService.instance.cancel();
    await TtsEngineManager.instance.release();
    await TtsModelService.uninstall();
    await _refreshState();
  }

  Future<void> _togglePreview() async {
    final speech = TtsSpeechService.instance;
    if (speech.status == TtsSpeechStatus.idle) {
      try {
        await speech.speakPreview('你好，这是本地 Qwen3-TTS 的试听语音。');
      } catch (e) {
        if (!mounted) return;
        showMiuixToast(
          context,
          '$e'.replaceFirst(RegExp(r'^(Exception:\s*)+'), ''),
        );
      }
      return;
    }
    await speech.stop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([
        TtsDownloadService.instance,
        TtsEngineManager.instance,
        TtsSpeechService.instance,
        TtsSettings.instance,
      ]),
      builder: (context, _) {
        final colors = MiuixTheme.of(context).colors;
        final download = TtsDownloadService.instance;
        final speech = TtsSpeechService.instance;
        final engine = TtsEngineManager.instance;

        // 下载刚结束（含取消/失败）：文件落盘状态可能变了，刷一次
        if (_wasDownloading && !download.isRunning) {
          _wasDownloading = false;
          scheduleMicrotask(_refreshState);
        } else if (download.isRunning) {
          _wasDownloading = true;
        }

        final installed = _modelState == TtsModelState.installed;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MiuixGroupCard(
              insideMargin: EdgeInsets.zero,
              child: Column(
                children: [
                  // 状态行：模型装没装 / 下载进度
                  MiuixBasicComponent(
                    title: TtsModelService.variant.label,
                    summary: _stateLabel(l10n, download),
                    startAction: const MiuixAppIcon(
                      'graph',
                      fallback: Icons.graphic_eq,
                      size: 24,
                    ),
                  ),
                  // 下载进度条（下载中才出现）
                  if (download.isRunning && download.progress != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: download.progress,
                          minHeight: 4,
                        ),
                      ),
                    ),
                  const MiuixHorizontalDivider(),
                  // 动作行：下载 / 停止
                  MiuixBasicComponent(
                    title: download.isRunning
                        ? l10n.localTtsTestStop
                        : l10n.localTtsDownload,
                    summary: download.isRunning
                        ? download.currentFile
                        : (download.error ?? l10n.localTtsServeHint),
                    startAction: MiuixAppIcon(
                      download.isRunning ? 'stopCircle' : 'download',
                      fallback: download.isRunning
                          ? Icons.stop_circle_outlined
                          : Icons.download_outlined,
                      size: 24,
                    ),
                    onClick: download.isRunning
                        ? download.cancel
                        : (installed ? null : _startDownload),
                  ),
                  const MiuixHorizontalDivider(),
                  MiuixBasicComponent(
                    title: l10n.deleteBtn,
                    summary: l10n.localTtsDeleteConfirm,
                    startAction: const MiuixAppIcon(
                      'delete',
                      fallback: Icons.delete_outline,
                      size: 24,
                    ),
                    onClick: download.isRunning || _modelState == TtsModelState.notInstalled
                        ? null
                        : _deleteModel,
                  ),
                  const MiuixHorizontalDivider(),
                  // 推理后端偏好
                  MiuixBasicComponent(
                    title: l10n.localTtsDevicePreference,
                    summary: _deviceLabel(l10n, TtsSettings.instance.device),
                    startAction: const MiuixAppIcon(
                      'memory',
                      fallback: Icons.memory_outlined,
                      size: 24,
                    ),
                    endActions: [
                      MiuixAppIcon(
                        'chevronRight',
                        fallback: Icons.chevron_right,
                        size: 20,
                        color: colors.onSurfaceVariantActions,
                      ),
                    ],
                    onClick: _pickDevice,
                  ),
                  const MiuixHorizontalDivider(),
                  // 默认 TTS 服务商（对话模拟朗读走它：本地或云端模型）
                  MiuixBasicComponent(
                    title: l10n.ttsProviderLabel,
                    summary: _providerLabel(l10n),
                    startAction: const MiuixAppIcon(
                      'voice',
                      fallback: Icons.surround_sound_outlined,
                      size: 24,
                    ),
                    endActions: [
                      MiuixAppIcon(
                        'chevronRight',
                        fallback: Icons.chevron_right,
                        size: 20,
                        color: colors.onSurfaceVariantActions,
                      ),
                    ],
                    onClick: _pickProvider,
                  ),
                  const MiuixHorizontalDivider(),
                  // 默认语音设计模型（角色卡没样本时走它，提示词即音色描述）
                  MiuixBasicComponent(
                    title: l10n.ttsDesignModelLabel,
                    summary: _routeModelLabel(
                      l10n,
                      TtsSettings.instance.designModel,
                    ),
                    startAction: const MiuixAppIcon(
                      'edit',
                      fallback: Icons.tune,
                      size: 24,
                    ),
                    endActions: [
                      MiuixAppIcon(
                        'chevronRight',
                        fallback: Icons.chevron_right,
                        size: 20,
                        color: colors.onSurfaceVariantActions,
                      ),
                    ],
                    onClick: _pickDesignModel,
                  ),
                  const MiuixHorizontalDivider(),
                  // 音色设计提示词（voicedesign 的 user 消息，可编辑）
                  MiuixBasicComponent(
                    title: l10n.ttsDesignPromptLabel,
                    summary: TtsSettings.instance.designPrompt.trim().isEmpty
                        ? '${l10n.ttsDesignPromptDefault}：${TtsSettings.defaultDesignPrompt}'
                        : TtsSettings.instance.designPrompt,
                    startAction: const MiuixAppIcon(
                      'edit',
                      fallback: Icons.edit_note,
                      size: 24,
                    ),
                    onClick: _editDesignPrompt,
                  ),
                  const MiuixHorizontalDivider(),
                  // 默认克隆模型（角色卡有样本时走它）
                  MiuixBasicComponent(
                    title: l10n.ttsCloneModelLabel,
                    summary: _routeModelLabel(
                      l10n,
                      TtsSettings.instance.cloneModel,
                    ),
                    startAction: const MiuixAppIcon(
                      'copy',
                      fallback: Icons.graphic_eq,
                      size: 24,
                    ),
                    endActions: [
                      MiuixAppIcon(
                        'chevronRight',
                        fallback: Icons.chevron_right,
                        size: 20,
                        color: colors.onSurfaceVariantActions,
                      ),
                    ],
                    onClick: _pickCloneModel,
                  ),
                  const MiuixHorizontalDivider(),
                  // 一键创建本地 TTS 上游（入口收敛在这，新建上游页不放它）
                  MiuixBasicComponent(
                    title: l10n.localTtsCreateUpstream,
                    summary: l10n.localTtsCreateUpstreamDesc,
                    startAction: const MiuixAppIcon(
                      'addCircle',
                      fallback: Icons.add_circle_outline,
                      size: 24,
                    ),
                    onClick: _createUpstream,
                  ),
                  const MiuixHorizontalDivider(),
                  // 试听
                  MiuixBasicComponent(
                    title: speech.status == TtsSpeechStatus.idle
                        ? l10n.localTtsTestSpeak
                        : l10n.localTtsTestStop,
                    summary: speech.errorMessage != null
                        ? '${l10n.localTtsStatusError}：${speech.errorMessage}'
                        : _speechStatusLabel(l10n, speech.status),
                    startAction: const MiuixAppIcon(
                      'voice',
                      fallback: Icons.record_voice_over_outlined,
                      size: 24,
                    ),
                    endActions: [
                      if (speech.status != TtsSpeechStatus.idle)
                        const MiuixCircularProgressIndicator(
                          size: 20,
                          strokeWidth: 2,
                        ),
                    ],
                    onClick: installed ? _togglePreview : null,
                  ),
                  const MiuixHorizontalDivider(),
                  // TTS 调试台：换样本 / 文本反复试听，排查克隆与设计效果
                  MiuixBasicComponent(
                    title: l10n.ttsPlaygroundTitle,
                    summary: l10n.ttsPlaygroundDesc,
                    startAction: const MiuixAppIcon(
                      'play',
                      fallback: Icons.play_circle_outline,
                      size: 24,
                    ),
                    endActions: [
                      MiuixAppIcon(
                        'chevronRight',
                        fallback: Icons.chevron_right,
                        size: 20,
                        color: colors.onSurfaceVariantActions,
                      ),
                    ],
                    onClick: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            MiuixTtsPlaygroundPage(controller: widget.controller),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 引擎已加载时补一行实际后端（NPU 回退一目了然）
            if (engine.isReady && engine.activeDevice != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 6, 20, 0),
                child: MiuixText(
                  '${l10n.localTtsDevicePreference}: '
                  '${engine.activeDevice!.effective.name.toUpperCase()}'
                  '${engine.activeDevice!.fellBackFromNpu ? ' (${engine.activeDevice!.fallbackReason?.name})' : ''}',
                  fontSize: 12,
                  color: colors.onSurfaceVariantSummary,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 设备偏好单选对话框体。
class _MiuixDeviceDialogBody extends StatelessWidget {
  const _MiuixDeviceDialogBody({required this.current, required this.labelOf});

  final TtsInferenceDevicePreference current;
  final String Function(TtsInferenceDevicePreference) labelOf;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in TtsInferenceDevicePreference.values)
          MiuixRadioButtonPreference(
            title: labelOf(p),
            selected: p == current,
            insideMargin: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            onClick: () => Navigator.of(context).pop(p),
          ),
      ],
    );
  }
}

/// 服务商单选对话框体：关闭 / 本地 / 云端模型名（可附空态提示）。
class _MiuixProviderDialogBody extends StatelessWidget {
  const _MiuixProviderDialogBody({
    required this.current,
    required this.options,
    this.emptyHint,
  });

  final String current;
  final List<(String, String)> options;
  final String? emptyHint;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (value, label) in options)
          MiuixRadioButtonPreference(
            title: label,
            selected: value == current,
            insideMargin: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            onClick: () => Navigator.of(context).pop(value),
          ),
        if (emptyHint != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: MiuixText(
              emptyHint!,
              fontSize: 12,
              color: MiuixTheme.of(context).colors.onSurfaceVariantSummary,
            ),
          ),
      ],
    );
  }
}
