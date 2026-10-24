// ChatTts.decideRoute 的路线决策单测：克隆 / 设计 / 回退三条路线，
// 含本地引擎与别名 target 的分叉。另含 autoPlayTarget（自动播放该读哪条）
// 的门槛判定。都不碰引擎与网络。
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/chat_simulation.dart';
import 'package:local2api/services/tts/tts_chat_speak.dart';
import 'package:local2api/services/tts/tts_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await TtsSettings.instance.load();
    // 单例有 loaded 门闩，测试间用 setter 显式归零，别依赖初始值。
    await TtsSettings.instance.setProvider(TtsSettings.providerOff);
    await TtsSettings.instance.setDesignModel(TtsSettings.providerOff);
    await TtsSettings.instance.setCloneModel(TtsSettings.providerOff);
    await TtsSettings.instance.setDesignPrompt('');
    await TtsSettings.instance.setAutoPlay(false);
  });

  ProxyConfig config() => ProxyConfig(listenHost: '127.0.0.1', listenPort: 9292)
    ..upstreams.add(
      Upstream(
        id: 'mimo',
        name: 'MiMo TTS',
        type: UpstreamType.openai,
        baseUrl: 'https://api.xiaomimimo.com/v1',
        modality: UpstreamModality.audio,
        models: [
          ModelEntry(publicName: 'mimo-v2.5-tts'),
          ModelEntry(publicName: 'mimo-v2.5-tts-voicedesign'),
          ModelEntry(publicName: 'mimo-v2.5-tts-voiceclone'),
        ],
      ),
    )
    ..upstreams.add(
      Upstream(
        id: 'lt',
        name: '本地 TTS',
        type: UpstreamType.localTts,
        baseUrl: '',
        models: [ModelEntry(publicName: 'qwen3-tts')],
      ),
    );

  Future<TtsSettings> settings({
    required String provider,
    String designModel = TtsSettings.providerOff,
    String cloneModel = TtsSettings.providerOff,
    String designPrompt = '',
  }) async {
    await TtsSettings.instance.setProvider(provider);
    await TtsSettings.instance.setDesignModel(designModel);
    await TtsSettings.instance.setCloneModel(cloneModel);
    await TtsSettings.instance.setDesignPrompt(designPrompt);
    return TtsSettings.instance;
  }

  test('样本 + 云端克隆模型 → 克隆路线，样本随请求走', () async {
    final s = await settings(
      provider: 'mimo-v2.5-tts',
      cloneModel: 'mimo-v2.5-tts-voiceclone',
    );
    final d = ChatTts.decideRoute(config(), '/tmp/voice.mp3', s);
    expect(d, isNotNull);
    expect(d!.local, isFalse);
    expect(d.model, 'mimo-v2.5-tts-voiceclone');
    expect(d.voicePath, '/tmp/voice.mp3');
    expect(d.instructions, isNull);
  });

  test('样本 + 克隆模型选本地 Qwen3-TTS → 本地克隆', () async {
    final s = await settings(
      provider: 'mimo-v2.5-tts',
      cloneModel: TtsSettings.providerLocal,
    );
    final d = ChatTts.decideRoute(config(), '/tmp/voice.mp3', s);
    expect(d, isNotNull);
    expect(d!.local, isTrue);
    expect(d.voicePath, '/tmp/voice.mp3');
  });

  test('无样本 + 云端设计模型 → 设计路线，提示词兜底默认文案', () async {
    final s = await settings(
      provider: 'mimo-v2.5-tts',
      designModel: 'mimo-v2.5-tts-voicedesign',
    );
    final d = ChatTts.decideRoute(config(), '', s);
    expect(d, isNotNull);
    expect(d!.local, isFalse);
    expect(d.model, 'mimo-v2.5-tts-voicedesign');
    expect(d.voicePath, isNull);
    expect(d.instructions, TtsSettings.defaultDesignPrompt);
  });

  test('无样本 + 设计模型选本地 → 本地默认音色合成（本地无设计概念）', () async {
    final s = await settings(
      provider: 'mimo-v2.5-tts',
      designModel: TtsSettings.providerLocal,
    );
    final d = ChatTts.decideRoute(config(), '', s);
    expect(d, isNotNull);
    expect(d!.local, isTrue);
    expect(d.voicePath, isNull);
  });

  test('自定义提示词覆盖默认文案', () async {
    final s = await settings(
      provider: 'mimo-v2.5-tts',
      designModel: 'mimo-v2.5-tts-voicedesign',
      designPrompt: '低沉沙哑的中年男声',
    );
    final d = ChatTts.decideRoute(config(), '', s);
    expect(d!.instructions, '低沉沙哑的中年男声');
  });

  test('回退：没配克隆/设计 → 服务商本身（预置音色，不带样本）', () async {
    final s = await settings(provider: 'mimo-v2.5-tts');
    final d = ChatTts.decideRoute(config(), '/tmp/voice.mp3', s);
    expect(d, isNotNull);
    expect(d!.local, isFalse);
    expect(d.model, 'mimo-v2.5-tts');
    expect(d.voicePath, isNull);
  });

  test('回退：服务商是本地引擎 → 本地合成，带样本即本地克隆', () async {
    final s = await settings(provider: TtsSettings.providerLocal);
    final withSample = ChatTts.decideRoute(config(), '/tmp/voice.mp3', s);
    expect(withSample!.local, isTrue);
    expect(withSample.voicePath, '/tmp/voice.mp3');
    final noSample = ChatTts.decideRoute(config(), '', s);
    expect(noSample!.local, isTrue);
    expect(noSample.voicePath, isNull);
  });

  test('回退：服务商本身是设计档（样本在但克隆模型没配）→ 补齐提示词', () async {
    final s = await settings(provider: 'mimo-v2.5-tts-voicedesign');
    final d = ChatTts.decideRoute(config(), '/tmp/voice.mp3', s);
    expect(d, isNotNull);
    expect(d!.local, isFalse);
    expect(d.model, 'mimo-v2.5-tts-voicedesign');
    expect(d.instructions, TtsSettings.defaultDesignPrompt);
  });

  test('回退：服务商本身是克隆档但没样本 → null（提前拦下，给明确提示）', () async {
    final s = await settings(provider: 'mimo-v2.5-tts-voiceclone');
    expect(ChatTts.decideRoute(config(), '', s), isNull);
  });

  test('别名 target 也按真实模型档识别：对外名是别名、target 是克隆档', () async {
    final cfg = config();
    cfg.upstreams.first.models
      ..clear()
      ..add(
        ModelEntry(
          publicName: '我的声音',
          target: 'mimo-v2.5-tts-voiceclone',
        ),
      );
    final s = await settings(provider: '我的声音');
    expect(ChatTts.decideRoute(cfg, '', s), isNull);
  });

  test('克隆模型配置失效（被删）→ 回退服务商，不因失效配置哑掉', () async {
    final s = await settings(
      provider: 'mimo-v2.5-tts',
      cloneModel: 'gone-model',
    );
    final d = ChatTts.decideRoute(config(), '/tmp/voice.mp3', s);
    expect(d, isNotNull);
    expect(d!.model, 'mimo-v2.5-tts');
    expect(d.voicePath, isNull);
  });

  test('服务商标记为 localTts 上游的模型也能作为回退目标', () async {
    final s = await settings(provider: 'qwen3-tts');
    final d = ChatTts.decideRoute(config(), '', s);
    expect(d!.local, isFalse);
    expect(d.model, 'qwen3-tts');
  });

  group('autoPlayTarget（自动播放该读哪条）', () {
    ChatMsg assistant(String content, {bool error = false}) =>
        ChatMsg(ChatRole.assistant, content, error: error);

    test('开关关着 / 没选服务商都不读', () async {
      final noProvider = await settings(provider: TtsSettings.providerOff);
      await noProvider.setAutoPlay(true);
      expect(
        ChatTts.autoPlayTarget([assistant('你好')], noProvider),
        isNull,
      );

      final withProvider = await settings(provider: 'qwen3-tts');
      await withProvider.setAutoPlay(false);
      expect(
        ChatTts.autoPlayTarget([assistant('你好')], withProvider),
        isNull,
      );
    });

    test('开的且选了服务商：读最后一条助手回复', () async {
      final s = await settings(provider: 'qwen3-tts');
      await s.setAutoPlay(true);
      final msgs = [
        ChatMsg(ChatRole.user, '在吗'),
        assistant('在的'),
      ];
      expect(ChatTts.autoPlayTarget(msgs, s), same(msgs.last));
    });

    test('失败气泡与空回复不读；末尾不是助手也不读', () async {
      final s = await settings(provider: 'qwen3-tts');
      await s.setAutoPlay(true);

      expect(
        ChatTts.autoPlayTarget([assistant('连不上', error: true)], s),
        isNull,
      );
      expect(ChatTts.autoPlayTarget([assistant('   ')], s), isNull);
      expect(
        ChatTts.autoPlayTarget([
          assistant('上一轮的回答'),
          ChatMsg(ChatRole.user, '新一轮的提问'),
        ], s),
        isNull,
      );
      expect(ChatTts.autoPlayTarget(const [], s), isNull);
    });

    test('开关落盘：关掉是把键删掉', () async {
      final s = await settings(provider: 'qwen3-tts');
      await s.setAutoPlay(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('tts.autoPlay'), isTrue);
      await s.setAutoPlay(false);
      expect(prefs.containsKey('tts.autoPlay'), isFalse);
    });
  });
}
