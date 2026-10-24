// 本地 TTS 的用户偏好（推理后端选择、下载镜像、默认 TTS 服务商），
// shared_preferences 落盘。
//
// 自 NaviFlash 的 SettingsService 收敛而来：那边偏好挂在全局设置服务的
// 静态字段上，这边独立成一个小类 —— local2api 的设置项都各管各的，
// 不想为 TTS 再养一个大而全的 SettingsService。
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tts_backend_policy.dart';
import 'tts_model_service.dart';

class TtsSettings extends ChangeNotifier {
  TtsSettings._();

  static final TtsSettings instance = TtsSettings._();

  static const String _kDevice = 'tts.inferenceDevice';
  static const String _kMirror = 'tts.mirror';
  static const String _kMirrorCustom = 'tts.mirrorCustom';
  static const String _kProvider = 'tts.provider';
  static const String _kDesignModel = 'tts.designModel';
  static const String _kDesignPrompt = 'tts.designPrompt';
  static const String _kCloneModel = 'tts.cloneModel';
  static const String _kAutoPlay = 'tts.autoPlay';

  /// 默认 TTS 服务商的取值约定：
  ///  - [providerOff]：关闭（对话模拟不朗读）；
  ///  - [providerLocal]：本地 Qwen3-TTS 直接合成（不走 HTTP）；
  ///  - 其它值：对外模型名 —— 走本机代理 /v1/audio/speech 路由
  ///    （audio 模态上游翻译到云端，localTts 上游回到本地引擎）。
  static const String providerOff = '';
  static const String providerLocal = 'local';

  /// 音色设计提示词的兜底文案：用户没写（或清空）时随请求带上。
  ///
  /// MiMo 的 voicedesign 模型把 user 消息当音色描述，缺了直接 400
  /// （「user message content must not be empty」），所以这层必须有值。
  static const String defaultDesignPrompt =
      '自然亲切的年轻女性嗓音，音色清亮柔和，语速适中，吐字清晰，'
      '情绪平稳自然，适合日常对话与文章朗读。';

  TtsInferenceDevicePreference _device =
      TtsInferenceDevicePreference.auto;
  TtsMirror _mirror = TtsMirror.hfMirror;
  String _mirrorCustom = '';
  String _provider = providerOff;
  String _designModel = providerOff;
  String _designPrompt = '';
  String _cloneModel = providerOff;
  bool _autoPlay = false;
  bool _loaded = false;

  /// 推理后端偏好（auto / npu / gpu / cpu）。
  TtsInferenceDevicePreference get device => _device;

  /// 下载镜像（HF 官方 / hf-mirror / 自定义）。
  TtsMirror get mirror => _mirror;

  /// 自定义镜像根地址（仅 [TtsMirror.custom] 时生效）。
  String get mirrorCustom => _mirrorCustom;

  /// 默认 TTS 服务商（取值约定见 [providerOff] / [providerLocal]）。
  String get provider => _provider;

  /// 默认语音设计模型（voicedesign 类，对外模型名）；
  /// [providerOff] = 不启用设计路线。
  String get designModel => _designModel;

  /// 音色设计提示词（user 消息内容，随 voicedesign 请求发送）；
  /// 空 = 用 [defaultDesignPrompt] 兜底。
  String get designPrompt => _designPrompt;

  /// 音色设计提示词的生效值：用户没写就用默认文案。
  String get effectiveDesignPrompt =>
      _designPrompt.trim().isEmpty ? defaultDesignPrompt : _designPrompt.trim();

  /// 默认克隆模型（voiceclone 类，对外模型名）；
  /// [providerOff] = 不启用克隆路线。
  String get cloneModel => _cloneModel;

  /// 自动播放：对话模拟收到一条新回复后，不等用户点喇叭，直接朗读。
  /// 只在选了服务商时才会真的发声（见 [providerEnabled]），关掉就是纯手动。
  bool get autoPlay => _autoPlay;

  /// 是否选择了服务商（对话模拟的朗读按钮据此亮/灰）。
  bool get providerEnabled => _provider != providerOff;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _device = TtsInferenceDevicePreference.values.firstWhere(
      (v) => v.id == prefs.getString(_kDevice),
      orElse: () => TtsInferenceDevicePreference.auto,
    );
    _mirror = TtsMirror.values.firstWhere(
      (v) => v.id == prefs.getString(_kMirror),
      orElse: () => TtsMirror.hfMirror,
    );
    _mirrorCustom = prefs.getString(_kMirrorCustom) ?? '';
    _provider = prefs.getString(_kProvider) ?? providerOff;
    _designModel = prefs.getString(_kDesignModel) ?? providerOff;
    _designPrompt = prefs.getString(_kDesignPrompt) ?? '';
    _cloneModel = prefs.getString(_kCloneModel) ?? providerOff;
    _autoPlay = prefs.getBool(_kAutoPlay) ?? false;
    _loaded = true;
    // 镜像选择同步给模型服务（下载源由它拼）。
    TtsModelService.applyMirror(_mirror, _mirrorCustom);
  }

  Future<void> setDevice(TtsInferenceDevicePreference v) async {
    if (v == _device) return;
    _device = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDevice, v.id);
  }

  Future<void> setMirror(TtsMirror v, String customUrl) async {
    _mirror = v;
    _mirrorCustom = customUrl.trim();
    notifyListeners();
    TtsModelService.applyMirror(v, _mirrorCustom);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMirror, v.id);
    if (_mirrorCustom.isEmpty) {
      await prefs.remove(_kMirrorCustom);
    } else {
      await prefs.setString(_kMirrorCustom, _mirrorCustom);
    }
  }

  Future<void> setProvider(String v) async {
    if (v == _provider) return;
    _provider = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (v == providerOff) {
      await prefs.remove(_kProvider);
    } else {
      await prefs.setString(_kProvider, v);
    }
  }

  /// 设默认语音设计模型；[providerOff] 表示不启用设计路线。
  Future<void> setDesignModel(String v) async {
    if (v == _designModel) return;
    _designModel = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (v == providerOff) {
      await prefs.remove(_kDesignModel);
    } else {
      await prefs.setString(_kDesignModel, v);
    }
  }

  /// 设音色设计提示词；空串回退 [defaultDesignPrompt]。
  Future<void> setDesignPrompt(String v) async {
    final clean = v.trim();
    if (clean == _designPrompt.trim()) return;
    _designPrompt = clean;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (clean.isEmpty) {
      await prefs.remove(_kDesignPrompt);
    } else {
      await prefs.setString(_kDesignPrompt, clean);
    }
  }

  /// 设默认克隆模型；[providerOff] 表示不启用克隆路线。
  Future<void> setCloneModel(String v) async {
    if (v == _cloneModel) return;
    _cloneModel = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (v == providerOff) {
      await prefs.remove(_kCloneModel);
    } else {
      await prefs.setString(_kCloneModel, v);
    }
  }

  /// 设「自动播放 TTS」开关（对话设置里那一行）。
  Future<void> setAutoPlay(bool v) async {
    if (v == _autoPlay) return;
    _autoPlay = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (!v) {
      await prefs.remove(_kAutoPlay);
    } else {
      await prefs.setBool(_kAutoPlay, v);
    }
  }
}
