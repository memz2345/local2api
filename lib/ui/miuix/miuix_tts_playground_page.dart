import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField;
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/character_voice.dart';
import 'package:local2api/services/chat_simulation.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/tts/tts_chat_speak.dart';
import 'package:local2api/services/tts/tts_model_kind.dart';
import 'package:local2api/services/tts/tts_settings.dart';
import 'package:local2api/services/tts/tts_speech_service.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/widgets/miuix/miuix_dialog.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_info_card.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';
import 'package:local2api/widgets/miuix/miuix_text_field.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// TTS 调试台（miuix 版，挂在「对话设置 → 本地 TTS」卡片）。
///
/// 专门用来排查「克隆不像 / 设计不对味」这类音质问题：换一段样本、改一句
/// 文本就能立刻重放，不用来回改角色卡。请求与对话模拟的朗读完全同链路
/// （本地引擎直合成，云端走本机代理 /v1/audio/speech），所以这里听到的
/// 就是对话模拟会听到的。
///
/// 状态（模型 / 样本 / 文本 / 指令）落 SharedPreferences，重开页面接着调。
class MiuixTtsPlaygroundPage extends StatefulWidget {
  const MiuixTtsPlaygroundPage({super.key, required this.controller});

  final ServerController controller;

  @override
  State<MiuixTtsPlaygroundPage> createState() =>
      _MiuixTtsPlaygroundPageState();
}

class _MiuixTtsPlaygroundPageState extends State<MiuixTtsPlaygroundPage> {
  static const String _kModel = 'tts.playground.model';
  static const String _kSample = 'tts.playground.sample';
  static const String _kText = 'tts.playground.text';
  static const String _kInstructions = 'tts.playground.instructions';

  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _instructionsController = TextEditingController();

  String _model = TtsSettings.providerLocal;
  String _samplePath = '';
  Timer? _saveTimer;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _textController.dispose();
    _instructionsController.dispose();
    _behavior.state.dispose();
    super.dispose();
  }

  /// 恢复上次的调试现场；模型没存过时按「克隆模型 > 服务商 > 本地」挑默认。
  Future<void> _restore() async {
    await TtsSettings.instance.load();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _model = prefs.getString(_kModel) ?? '';
      if (_model.isEmpty) {
        final s = TtsSettings.instance;
        _model = s.cloneModel != TtsSettings.providerOff
            ? s.cloneModel
            : (s.provider != TtsSettings.providerOff
                  ? s.provider
                  : TtsSettings.providerLocal);
      }
      _samplePath = prefs.getString(_kSample) ?? '';
      _textController.text = prefs.getString(_kText) ?? '';
      _instructionsController.text = prefs.getString(_kInstructions) ?? '';
      _loaded = true;
    });
  }

  void _persist() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_save());
    });
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kModel, _model);
      if (_samplePath.isEmpty) {
        await prefs.remove(_kSample);
      } else {
        await prefs.setString(_kSample, _samplePath);
      }
      if (_textController.text.isEmpty) {
        await prefs.remove(_kText);
      } else {
        await prefs.setString(_kText, _textController.text);
      }
      if (_instructionsController.text.isEmpty) {
        await prefs.remove(_kInstructions);
      } else {
        await prefs.setString(_kInstructions, _instructionsController.text);
      }
    } catch (_) {}
  }

  String _modelLabel(AppLocalizations l10n, String model) =>
      model == TtsSettings.providerLocal
          ? l10n.ttsProviderLocal
          : (model.isEmpty ? l10n.ttsProviderOff : model);

  /// 选模型：本地引擎 + 配置里能发声的云端模型（原样发请求，不做路由）。
  Future<void> _pickModel() async {
    final l10n = AppLocalizations.of(context);
    final cloud = ChatTts.cloudModelNames(widget.controller.config);
    final options = <(String, String)>[
      (TtsSettings.providerLocal, l10n.ttsProviderLocal),
      for (final name in cloud) (name, name),
    ];
    final picked = await showMiuixDialog<String>(
      context: context,
      title: l10n.ttsPlaygroundModel,
      content: _PlaygroundModelDialogBody(current: _model, options: options),
      actions: [
        MiuixDialogAction(
          label: l10n.cancel,
          onPressed: (ctx) => Navigator.of(ctx).pop(),
        ),
      ],
    );
    if (picked == null || picked == _model) return;
    setState(() => _model = picked);
    _persist();
  }

  Future<void> _pickSample() async {
    try {
      final path = await CharacterVoice.pickAndStore(
        existingPath: _samplePath,
      );
      if (path == null || !mounted) return;
      setState(() => _samplePath = path);
      _persist();
    } catch (e) {
      if (!mounted) return;
      showMiuixToast(
        context,
        '$e'.replaceFirst(RegExp(r'^(Exception:\s*)+'), ''),
        error: true,
      );
    }
  }

  Future<void> _removeSample() async {
    await CharacterVoice.deleteStored(_samplePath);
    if (!mounted) return;
    setState(() => _samplePath = '');
    _persist();
  }

  /// 播放 / 停止。请求与对话模拟同链路：本地引擎直合成，云端走代理。
  Future<void> _togglePlay() async {
    final l10n = AppLocalizations.of(context);
    final speech = TtsSpeechService.instance;
    if (!speech.isIdle) {
      await speech.stop();
      return;
    }
    final text = _textController.text.trim();
    if (text.isEmpty) {
      showMiuixToast(context, l10n.ttsPlaygroundEmptyText);
      return;
    }
    // 克隆模型没样本：上游必然 400（audio.voice must not be empty），
    // 前置拦下给明确提示，别让用户以为是「克隆不像」。
    if (_samplePath.isEmpty &&
        _model != TtsSettings.providerLocal &&
        ttsModelKindOf(ChatTts.targetOf(widget.controller.config, _model)) ==
            TtsModelKind.voiceClone) {
      showMiuixToast(context, l10n.ttsPlaygroundCloneNeedsSample);
      return;
    }
    try {
      if (_model == TtsSettings.providerLocal) {
        await speech.speak(
          'playground',
          text,
          voicePath: _samplePath.isEmpty ? null : _samplePath,
        );
        return;
      }
      final config = widget.controller.config;
      final host = config.listenHost == '0.0.0.0'
          ? '127.0.0.1'
          : config.listenHost;
      await speech.speakCloud(
        'playground',
        text,
        model: _model,
        host: host,
        port: config.listenPort,
        apiKey: ChatSimulator.apiKeyOf(config),
        voiceSamplePath: _samplePath.isEmpty ? null : _samplePath,
        instructions: _instructionsController.text.trim().isEmpty
            ? null
            : _instructionsController.text.trim(),
      );
    } catch (e) {
      if (!mounted) return;
      showMiuixToast(
        context,
        '$e'.replaceFirst(RegExp(r'^(Exception:\s*)+'), ''),
        error: true,
      );
    }
  }

  String _speechStatusLabel(AppLocalizations l10n, TtsSpeechStatus s) =>
      switch (s) {
        TtsSpeechStatus.idle => l10n.localTtsStatusIdle,
        TtsSpeechStatus.preparing => l10n.localTtsStatusPreparing,
        TtsSpeechStatus.synthesizing => l10n.localTtsStatusSynthesizing,
        TtsSpeechStatus.playing => l10n.localTtsStatusPlaying,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    if (!_loaded) {
      return const SizedBox.shrink();
    }
    return Material(
      type: MaterialType.transparency,
      child: MiuixScaffold(
        containerColor: colors.surface,
        topBar: MiuixBlurTopBar(
          title: l10n.ttsPlaygroundTitle,
          scrollBehavior: _behavior,
          navigationIcon: MiuixIconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const MiuixAppIcon(
              AppIconNames.back,
              fallback: Icons.arrow_back,
            ),
          ),
        ),
        content: (padding) => MiuixScrollBehaviorListener(
          behavior: _behavior,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(16, padding.top + 8, 16, 40),
            children: [
              MiuixInfoCard(text: l10n.ttsPlaygroundHint),
              const SizedBox(height: 12),
              // 模型 / 样本
              MiuixGroupCard(
                insideMargin: EdgeInsets.zero,
                child: Column(
                  children: [
                    MiuixBasicComponent(
                      title: l10n.ttsPlaygroundModel,
                      summary: _modelLabel(l10n, _model),
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
                      onClick: _pickModel,
                    ),
                    const MiuixHorizontalDivider(),
                    MiuixBasicComponent(
                      title: l10n.characterVoiceLabel,
                      summary: _samplePath.isEmpty
                          ? l10n.characterVoicePick
                          : CharacterVoice.displayName(_samplePath),
                      startAction: const MiuixAppIcon(
                        'recording',
                        fallback: Icons.mic_none,
                        size: 24,
                      ),
                      onClick: _pickSample,
                    ),
                    if (_samplePath.isNotEmpty) ...[
                      const MiuixHorizontalDivider(),
                      MiuixBasicComponent(
                        title: l10n.characterVoiceRemove,
                        summary: CharacterVoice.displayName(_samplePath),
                        startAction: const MiuixAppIcon(
                          'delete',
                          fallback: Icons.delete_outline,
                          size: 24,
                        ),
                        onClick: _removeSample,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 文本 / 指令输入
              MiuixGroupCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MiuixTextField(
                      controller: _textController,
                      label: l10n.ttsPlaygroundText,
                      maxLines: 4,
                      minLines: 2,
                      onChanged: (_) => _persist(),
                    ),
                    const SizedBox(height: 12),
                    MiuixTextField(
                      controller: _instructionsController,
                      label: l10n.ttsPlaygroundInstructions,
                      maxLines: 3,
                      minLines: 1,
                      onChanged: (_) => _persist(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 播放 / 停止
              AnimatedBuilder(
                animation: TtsSpeechService.instance,
                builder: (context, _) {
                  final speech = TtsSpeechService.instance;
                  return MiuixGroupCard(
                    insideMargin: EdgeInsets.zero,
                    child: MiuixBasicComponent(
                      title: speech.status == TtsSpeechStatus.idle
                          ? l10n.ttsPlaygroundPlay
                          : l10n.localTtsTestStop,
                      summary: speech.errorMessage != null
                          ? '${l10n.localTtsStatusError}：${speech.errorMessage}'
                          : _speechStatusLabel(l10n, speech.status),
                      startAction: const MiuixAppIcon(
                        'play',
                        fallback: Icons.play_arrow_outlined,
                        size: 24,
                      ),
                      endActions: [
                        if (speech.status != TtsSpeechStatus.idle)
                          const MiuixCircularProgressIndicator(
                            size: 20,
                            strokeWidth: 2,
                          ),
                      ],
                      onClick: _togglePlay,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 模型单选对话框体：本地引擎 + 云端模型名。
class _PlaygroundModelDialogBody extends StatelessWidget {
  const _PlaygroundModelDialogBody({
    required this.current,
    required this.options,
  });

  final String current;
  final List<(String, String)> options;

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
      ],
    );
  }
}
