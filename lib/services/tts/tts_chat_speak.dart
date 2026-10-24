// 对话模拟「朗读」的路由层：按 TtsSettings 里的默认服务商把一段文本
// 送到本地引擎或本机代理的 /v1/audio/speech（云端由代理再翻译）。
//
// 路线决策收敛在 [ChatTts.decideRoute]（纯函数，可单测）：
// - 角色卡带了音色样本 + 配了「默认克隆模型」→ 走克隆（样本随请求带）；
//   克隆模型可以是云端模型，也可以是本地 Qwen3-TTS（引擎原生支持
//   speakerReference 克隆）；
// - 没样本 + 配了「默认语音设计模型」→ 走设计（提示词即音色描述）；
//   本地引擎没有音色设计概念，选它就按默认音色合成；
// - 其余情况回退「默认 TTS 服务商」本身（预置音色）；服务商本身落在
//   设计/克隆档时补齐对应请求形态，不然上游 400。
//
// 为什么绕一圈 HTTP 而不是直接调上游：路由 / 回退 / 日志 / 用量统计全在
// 代理里，模拟器自己也是这么发聊天请求的（本机自己调自己，密钥取第一个
// 启用的即可）。
import '../../models/proxy_config.dart';
import '../chat_simulation.dart';
import 'tts_model_kind.dart';
import 'tts_settings.dart';
import 'tts_speech_service.dart';

/// 没选服务商 / 所选服务商已失效时抛给 UI 提示。
class TtsNotConfiguredException implements Exception {
  final String message;
  const TtsNotConfiguredException(this.message);

  @override
  String toString() => message;
}

/// 一条朗读路线的决策结果。
///
/// [local] = 本地引擎直合成（[voicePath] 是克隆样本，可空）；
/// 否则走云端代理（[model] 是对外模型名，[voicePath] 作 voice_sample，
/// [instructions] 随请求发送）。
class TtsRouteDecision {
  const TtsRouteDecision({
    required this.local,
    required this.model,
    this.voicePath,
    this.instructions,
  });

  final bool local;
  final String model;
  final String? voicePath;
  final String? instructions;
}

class ChatTts {
  ChatTts._();

  /// 「自动播放」该读哪条回复（纯函数，可单测）。
  ///
  /// 条件：开关开着 + 确实选了服务商 + 最后一条是**成功的**、有内容的助手
  /// 消息。失败气泡不读 —— 那通常是「连不上 / 没配额」的提示文本，念出来
  /// 只会把一次失败的发送变成一段更难听的语音。
  static ChatMsg? autoPlayTarget(
    List<ChatMsg> messages,
    TtsSettings settings,
  ) {
    if (!settings.autoPlay || !settings.providerEnabled) return null;
    if (messages.isEmpty) return null;
    final last = messages.last;
    if (last.role != ChatRole.assistant || last.error) return null;
    if (last.content.trim().isEmpty) return null;
    return last;
  }

  /// 云端可选项：audio 模态上游（含 localTts 类型）暴露的对外模型名，
  /// 去重保序。空 = 配置里还没有能发声的模型。
  static List<String> cloudModelNames(ProxyConfig config) => <String>{
    for (final u in config.upstreams)
      if (u.enabled &&
          (u.type == UpstreamType.localTts ||
              u.modality == UpstreamModality.audio))
        for (final m in u.models)
          if (m.enabled && m.publicName.trim().isNotEmpty) m.publicName.trim(),
  }.toList();

  /// 当前选的服务商是否仍可用：'local' 恒可用；模型名必须在配置里。
  static bool providerAvailable(ProxyConfig config, String provider) {
    if (provider == TtsSettings.providerOff) return true;
    if (provider == TtsSettings.providerLocal) return true;
    return cloudModelNames(config).contains(provider);
  }

  /// 对外模型名对应的上游真实模型（target）：别名映射后才知道它到底是
  /// 哪一档（basic / voicedesign / voiceclone）。找不到按原名返回。
  static String targetOf(ProxyConfig config, String publicName) {
    final wanted = publicName.trim();
    for (final u in config.upstreams) {
      if (!u.enabled) continue;
      for (final m in u.models) {
        if (!m.enabled || m.publicName.trim() != wanted) continue;
        final t = m.target.trim();
        if (t.isNotEmpty) return t;
      }
    }
    return wanted;
  }

  /// 朗读路线决策（纯函数，不碰引擎/网络）。
  ///
  /// 返回 null 表示配置自相矛盾、没法读：目前只有一种情况——回退到的
  /// 默认服务商是克隆档但角色卡没样本（克隆没样本必然 400，提前拦下来
  /// 给用户明确提示）。
  ///
  /// 路线优先级：样本 + 克隆模型 > 无样本 + 设计模型 > 默认服务商本身。
  /// 克隆/设计模型配置了但已在配置里失效（被删/被改名）时跳过该路线，
  /// 照旧回退默认服务商 —— 不至于因为一个失效配置整个朗读哑掉。
  static TtsRouteDecision? decideRoute(
    ProxyConfig config,
    String? voiceSamplePath,
    TtsSettings settings,
  ) {
    final sample = (voiceSamplePath ?? '').trim();
    final cloud = cloudModelNames(config);
    final cloneModel = settings.cloneModel;
    final designModel = settings.designModel;

    // 克隆路线：样本 + 配了克隆模型（本地引擎或云端模型）。
    if (sample.isNotEmpty && cloneModel != TtsSettings.providerOff) {
      if (cloneModel == TtsSettings.providerLocal) {
        return TtsRouteDecision(local: true, model: '', voicePath: sample);
      }
      if (cloud.contains(cloneModel)) {
        return TtsRouteDecision(local: false, model: cloneModel, voicePath: sample);
      }
    }

    // 设计路线：没样本 + 配了设计模型。本地引擎没有「文本描述音色」
    // 的能力，选它就退化为默认音色合成。
    if (sample.isEmpty && designModel != TtsSettings.providerOff) {
      if (designModel == TtsSettings.providerLocal) {
        return const TtsRouteDecision(local: true, model: '');
      }
      if (cloud.contains(designModel)) {
        return TtsRouteDecision(
          local: false,
          model: designModel,
          instructions: settings.effectiveDesignPrompt,
        );
      }
    }

    // 回退默认服务商本身。服务商是本地引擎时直合成（带样本即本地克隆）；
    // 云端服务商落在设计/克隆档时补齐对应请求形态，不然上游 400
    // （voicedesign 的 user 消息不能空 / clone 必须带样本）。
    if (settings.provider == TtsSettings.providerOff) return null;
    if (settings.provider == TtsSettings.providerLocal) {
      return TtsRouteDecision(
        local: true,
        model: '',
        voicePath: sample.isEmpty ? null : sample,
      );
    }
    switch (ttsModelKindOf(targetOf(config, settings.provider))) {
      case TtsModelKind.voiceDesign:
        return TtsRouteDecision(
          local: false,
          model: settings.provider,
          instructions: settings.effectiveDesignPrompt,
        );
      case TtsModelKind.voiceClone:
        if (sample.isEmpty) return null;
        return TtsRouteDecision(
          local: false,
          model: settings.provider,
          voicePath: sample,
        );
      case TtsModelKind.basic:
        return TtsRouteDecision(local: false, model: settings.provider);
    }
  }

  /// 朗读一段文本（再次调用同一 [tag] = 停止）。
  ///
  /// [voiceSamplePath] 是角色卡的音色样本；本地引擎拿它当克隆参考，
  /// 云端按 [decideRoute] 的三路线规则选模型。
  static Future<void> speakMessage({
    required String tag,
    required String text,
    required ProxyConfig config,
    String? voiceSamplePath,
  }) async {
    await TtsSettings.instance.load();
    final settings = TtsSettings.instance;
    if (settings.provider == TtsSettings.providerOff) {
      throw const TtsNotConfiguredException('未选择 TTS 服务商');
    }
    if (!providerAvailable(config, settings.provider)) {
      throw const TtsNotConfiguredException('所选 TTS 模型已不可用，请重新选择');
    }

    final decision = decideRoute(config, voiceSamplePath, settings);
    if (decision == null) {
      throw const TtsNotConfiguredException(
        '克隆模型需要音色样本：先给角色卡配一段音频，或改选其它 TTS 模型',
      );
    }

    if (decision.local) {
      await TtsSpeechService.instance.speak(
        tag,
        text,
        voicePath: decision.voicePath,
      );
      return;
    }

    final host = config.listenHost == '0.0.0.0'
        ? '127.0.0.1'
        : config.listenHost;
    await TtsSpeechService.instance.speakCloud(
      tag,
      text,
      model: decision.model,
      host: host,
      port: config.listenPort,
      apiKey: ChatSimulator.apiKeyOf(config),
      voiceSamplePath: decision.voicePath,
      instructions: decision.instructions,
    );
  }
}
