// TTS 模型的「档位」识别：basic / voicedesign / voiceclone。
//
// MiMo 的三种 TTS 模型对请求形态的要求不同（user 消息必不必填、audio.voice
// 放什么），代理翻译层（proxy_server）与客户端路由层（tts_chat_speak）都
// 要按档位分叉，识别逻辑收敛在这一个文件里，别处只认结果。
//
// 判定靠名字包含关系：对 MiMo 官方模型名（mimo-v2.5-tts[-voicedesign /
// -voiceclone]）直接命中；用户把 target 起了别名时也能按 target 名认出。
// 完全对不上的名字按 basic 处理 —— 请求形态与旧行为一致。

/// TTS 模型档位。
enum TtsModelKind {
  /// 预置音色合成（如 mimo-v2.5-tts）：user 消息可选。
  basic,

  /// 文本设计音色（如 mimo-v2.5-tts-voicedesign）：
  /// user 消息必填且不能为空（内容即音色描述）。
  voiceDesign,

  /// 样本克隆音色（如 mimo-v2.5-tts-voiceclone）：
  /// user 消息要存在（可为空串），音色靠 audio.voice 携带样本 data URI。
  voiceClone,
}

/// 按上游模型名识别档位。
TtsModelKind ttsModelKindOf(String modelName) {
  final lower = modelName.toLowerCase();
  if (lower.contains('voicedesign') || lower.contains('voice-design')) {
    return TtsModelKind.voiceDesign;
  }
  if (lower.contains('voiceclone') || lower.contains('voice-clone')) {
    return TtsModelKind.voiceClone;
  }
  return TtsModelKind.basic;
}
