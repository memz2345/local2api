import 'dart:async';

import 'package:flutter/material.dart';
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
import 'package:local2api/ui/tts_playground_page.dart';
import 'package:local2api/widgets/app_toast.dart';

import 'widgets/common.dart' show SectionCard, pushPage;

/// 本地 TTS（Qwen3-TTS）：模型下载 / 一键建上游 / 推理后端 / 试听。
///
/// 对应 miuix 版 `MiuixTtsSection`，信息架构一致，渲染走 Material 组件。
/// 挂在「TTS 设置」页；新建上游页的模式列表刻意不含本地 TTS，
/// 入口收敛在「创建本地 TTS 上游」这一行。
class TtsSection extends StatefulWidget {
  const TtsSection({super.key, required this.controller});

  final ServerController controller;

  @override
  State<TtsSection> createState() => _TtsSectionState();
}

class _TtsSectionState extends State<TtsSection> {
  TtsModelState _modelState = TtsModelState.notInstalled;
  bool _wasDownloading = false;

  @override
  void initState() {
    super.initState();
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
    final theme = Theme.of(context);
    final cloud = ChatTts.cloudModelNames(widget.controller.config);
    final options = <(String, String)>[
      (TtsSettings.providerOff, l10n.ttsProviderOff),
      (TtsSettings.providerLocal, l10n.ttsProviderLocal),
      for (final name in cloud) (name, name),
    ];
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: [
          for (final (value, label) in options)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(value),
              child: Row(
                children: [
                  Icon(
                    value == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: value == current
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(label)),
                ],
              ),
            ),
          if (cloud.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
              child: Text(
                l10n.ttsProviderNoneHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
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
    final controller = TextEditingController(
      text: TtsSettings.instance.designPrompt,
    );
    final picked = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l10n.ttsDesignPromptLabel),
        content: TextField(
          controller: controller,
          maxLines: 6,
          minLines: 3,
          decoration: InputDecoration(
            hintText: TtsSettings.defaultDesignPrompt,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, controller.text),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    controller.dispose();
    if (picked == null) return;
    await TtsSettings.instance.setDesignPrompt(picked);
  }

  /// 选默认 TTS 服务商：关闭 / 本地 / 配置里能发声的云端模型。
  Future<void> _pickProvider() async {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cloud = ChatTts.cloudModelNames(widget.controller.config);
    final options = <(String, String)>[
      (TtsSettings.providerOff, l10n.ttsProviderOff),
      (TtsSettings.providerLocal, l10n.ttsProviderLocal),
      for (final name in cloud) (name, name),
    ];
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.ttsProviderLabel),
        children: [
          for (final (value, label) in options)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(value),
              child: Row(
                children: [
                  Icon(
                    value == TtsSettings.instance.provider
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: value == TtsSettings.instance.provider
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(label)),
                ],
              ),
            ),
          if (cloud.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
              child: Text(
                l10n.ttsProviderNoneHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await TtsSettings.instance.setProvider(picked);
  }

  /// 一键创建「本地 TTS」上游（幂等：已存在只提示，不重复建）。
  Future<void> _createUpstream() async {
    final l10n = AppLocalizations.of(context);
    final config = widget.controller.config;
    if (config.upstreams.any((u) => u.type == UpstreamType.localTts)) {
      showAppToast(context, l10n.localTtsUpstreamExists);
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
    showAppToast(context, l10n.localTtsUpstreamCreated);
  }

  Future<void> _pickDevice() async {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final picked = await showDialog<TtsInferenceDevicePreference>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.localTtsDevicePreference),
        children: [
          for (final p in TtsInferenceDevicePreference.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(p),
              child: Row(
                children: [
                  Icon(
                    p == TtsSettings.instance.device
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: p == TtsSettings.instance.device
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_deviceLabel(l10n, p))),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await TtsSettings.instance.setDevice(picked);
    await TtsEngineManager.instance.release();
  }

  Future<void> _startDownload() async {
    await TtsDownloadService.instance.start();
    await _refreshState();
  }

  Future<void> _deleteModel() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l10n.localTtsDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(l10n.deleteBtn),
          ),
        ],
      ),
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
        showAppToast(
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
        final device = TtsSettings.instance.device;

        return SectionCard(
          title: l10n.localTtsSectionTitle,
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.graphic_eq),
                title: Text(TtsModelService.variant.label),
                subtitle: Text(_stateLabel(l10n, download)),
              ),
              if (download.isRunning && download.progress != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: LinearProgressIndicator(value: download.progress),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  download.isRunning
                      ? Icons.stop_circle_outlined
                      : Icons.download_outlined,
                ),
                title: Text(
                  download.isRunning
                      ? l10n.localTtsTestStop
                      : l10n.localTtsDownload,
                ),
                subtitle: Text(
                  download.isRunning
                      ? download.currentFile
                      : (download.error ?? l10n.localTtsServeHint),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: download.isRunning
                    ? download.cancel
                    : (installed ? null : _startDownload),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_outline),
                title: Text(l10n.deleteBtn),
                subtitle: Text(l10n.localTtsDeleteConfirm),
                onTap: download.isRunning ||
                        _modelState == TtsModelState.notInstalled
                    ? null
                    : _deleteModel,
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.memory_outlined),
                title: Text(l10n.localTtsDevicePreference),
                subtitle: Text(_deviceLabel(l10n, device)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickDevice,
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.surround_sound_outlined),
                title: Text(l10n.ttsProviderLabel),
                subtitle: Text(_providerLabel(l10n)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickProvider,
              ),
              const Divider(),
              // 默认语音设计模型（角色卡没样本时走它，提示词即音色描述）
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tune),
                title: Text(l10n.ttsDesignModelLabel),
                subtitle: Text(
                  _routeModelLabel(l10n, TtsSettings.instance.designModel),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickDesignModel,
              ),
              const Divider(),
              // 音色设计提示词（voicedesign 的 user 消息，可编辑）
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit_note),
                title: Text(l10n.ttsDesignPromptLabel),
                subtitle: Text(
                  TtsSettings.instance.designPrompt.trim().isEmpty
                      ? '${l10n.ttsDesignPromptDefault}：${TtsSettings.defaultDesignPrompt}'
                      : TtsSettings.instance.designPrompt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: _editDesignPrompt,
              ),
              const Divider(),
              // 默认克隆模型（角色卡有样本时走它）
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.graphic_eq),
                title: Text(l10n.ttsCloneModelLabel),
                subtitle: Text(
                  _routeModelLabel(l10n, TtsSettings.instance.cloneModel),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickCloneModel,
              ),
              const Divider(),
              // 一键创建本地 TTS 上游（入口收敛在这，新建上游页不放它）
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add_circle_outline),
                title: Text(l10n.localTtsCreateUpstream),
                subtitle: Text(l10n.localTtsCreateUpstreamDesc),
                onTap: _createUpstream,
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.record_voice_over_outlined),
                title: Text(
                  speech.status == TtsSpeechStatus.idle
                      ? l10n.localTtsTestSpeak
                      : l10n.localTtsTestStop,
                ),
                subtitle: Text(
                  speech.errorMessage != null
                      ? '${l10n.localTtsStatusError}：${speech.errorMessage}'
                      : _speechStatusLabel(l10n, speech.status),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: speech.status == TtsSpeechStatus.idle
                    ? null
                    : const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                onTap: installed ? _togglePreview : null,
              ),
              const Divider(),
              // TTS 调试台：换样本 / 文本反复试听，排查克隆与设计效果
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.play_circle_outline),
                title: Text(l10n.ttsPlaygroundTitle),
                subtitle: Text(l10n.ttsPlaygroundDesc),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => pushPage(
                  context,
                  TtsPlaygroundPage(controller: widget.controller),
                ),
              ),
              if (engine.isReady && engine.activeDevice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${l10n.localTtsDevicePreference}: '
                      '${engine.activeDevice!.effective.name.toUpperCase()}'
                      '${engine.activeDevice!.fellBackFromNpu ? ' (${engine.activeDevice!.fallbackReason?.name})' : ''}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
