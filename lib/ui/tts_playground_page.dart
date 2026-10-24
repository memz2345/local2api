import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/character_voice.dart';
import 'package:local2api/services/chat_simulation.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/tts/tts_chat_speak.dart';
import 'package:local2api/services/tts/tts_model_kind.dart';
import 'package:local2api/services/tts/tts_settings.dart';
import 'package:local2api/services/tts/tts_speech_service.dart';
import 'package:local2api/widgets/app_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widgets/common.dart' show SectionCard;

/// TTS 调试台（Material 版，对应 miuix 版 `MiuixTtsPlaygroundPage`）。
///
/// 换样本 / 文本反复试听排查克隆与设计效果；请求与对话模拟的朗读同链路
/// （本地引擎直合成，云端走本机代理 /v1/audio/speech）。状态落
/// SharedPreferences，重开页面接着调。
class TtsPlaygroundPage extends StatefulWidget {
  const TtsPlaygroundPage({super.key, required this.controller});

  final ServerController controller;

  @override
  State<TtsPlaygroundPage> createState() => _TtsPlaygroundPageState();
}

class _TtsPlaygroundPageState extends State<TtsPlaygroundPage> {
  static const String _kModel = 'tts.playground.model';
  static const String _kSample = 'tts.playground.sample';
  static const String _kText = 'tts.playground.text';
  static const String _kInstructions = 'tts.playground.instructions';

  final TextEditingController _textController = TextEditingController();
  final TextEditingController _instructionsController = TextEditingController();

  String _model = TtsSettings.providerLocal;
  String _samplePath = '';
  Timer? _saveTimer;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _textController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

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

  String _speechStatusLabel(AppLocalizations l10n, TtsSpeechStatus s) =>
      switch (s) {
        TtsSpeechStatus.idle => l10n.localTtsStatusIdle,
        TtsSpeechStatus.preparing => l10n.localTtsStatusPreparing,
        TtsSpeechStatus.synthesizing => l10n.localTtsStatusSynthesizing,
        TtsSpeechStatus.playing => l10n.localTtsStatusPlaying,
      };

  Future<void> _pickModel() async {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cloud = ChatTts.cloudModelNames(widget.controller.config);
    final options = <(String, String)>[
      (TtsSettings.providerLocal, l10n.ttsProviderLocal),
      for (final name in cloud) (name, name),
    ];
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.ttsPlaygroundModel),
        children: [
          for (final (value, label) in options)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(value),
              child: Row(
                children: [
                  Icon(
                    value == _model
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: value == _model
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(label)),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null || picked == _model) return;
    setState(() => _model = picked);
    unawaited(_save());
  }

  Future<void> _pickSample() async {
    try {
      final path = await CharacterVoice.pickAndStore(
        existingPath: _samplePath,
      );
      if (path == null || !mounted) return;
      setState(() => _samplePath = path);
      unawaited(_save());
    } catch (e) {
      if (!mounted) return;
      showAppToast(
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
    unawaited(_save());
  }

  Future<void> _togglePlay() async {
    final l10n = AppLocalizations.of(context);
    final speech = TtsSpeechService.instance;
    if (!speech.isIdle) {
      await speech.stop();
      return;
    }
    final text = _textController.text.trim();
    if (text.isEmpty) {
      showAppToast(context, l10n.ttsPlaygroundEmptyText);
      return;
    }
    // 克隆模型没样本：上游必然 400（audio.voice must not be empty），
    // 前置拦下给明确提示，别让用户以为是「克隆不像」。
    if (_samplePath.isEmpty &&
        _model != TtsSettings.providerLocal &&
        ttsModelKindOf(ChatTts.targetOf(widget.controller.config, _model)) ==
            TtsModelKind.voiceClone) {
      showAppToast(context, l10n.ttsPlaygroundCloneNeedsSample);
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
      showAppToast(
        context,
        '$e'.replaceFirst(RegExp(r'^(Exception:\s*)+'), ''),
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!_loaded) {
      return const Scaffold(body: SizedBox.shrink());
    }
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: Text(l10n.ttsPlaygroundTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            l10n.ttsPlaygroundHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.surround_sound_outlined),
                  title: Text(l10n.ttsPlaygroundModel),
                  subtitle: Text(_modelLabel(l10n, _model)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickModel,
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.mic_none),
                  title: Text(l10n.characterVoiceLabel),
                  subtitle: Text(
                    _samplePath.isEmpty
                        ? l10n.characterVoicePick
                        : CharacterVoice.displayName(_samplePath),
                  ),
                  onTap: _pickSample,
                ),
                if (_samplePath.isNotEmpty) ...[
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.delete_outline),
                    title: Text(l10n.characterVoiceRemove),
                    subtitle: Text(CharacterVoice.displayName(_samplePath)),
                    onTap: _removeSample,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _textController,
                  maxLines: 4,
                  minLines: 2,
                  decoration: InputDecoration(
                    labelText: l10n.ttsPlaygroundText,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => _persist(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _instructionsController,
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(
                    labelText: l10n.ttsPlaygroundInstructions,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => _persist(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            child: AnimatedBuilder(
              animation: TtsSpeechService.instance,
              builder: (context, _) {
                final s = TtsSpeechService.instance;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.play_arrow_outlined),
                  title: Text(
                    s.status == TtsSpeechStatus.idle
                        ? l10n.ttsPlaygroundPlay
                        : l10n.localTtsTestStop,
                  ),
                  subtitle: Text(
                    s.errorMessage != null
                        ? '${l10n.localTtsStatusError}：${s.errorMessage}'
                        : _speechStatusLabel(l10n, s.status),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: s.status == TtsSpeechStatus.idle
                      ? null
                      : const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                  onTap: _togglePlay,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
