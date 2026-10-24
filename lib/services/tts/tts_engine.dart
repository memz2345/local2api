// 本地 TTS 引擎的抽象层 + 懒加载管理。
//
// 自 NaviFlash lib/services/tts_engine.dart 移植，去掉那边特有的
// TtsLiveUpdate（实时更新通知）。
//
// 设计要点：
// 1. **启动不加载**：应用启动时这里什么都不做。模型是 1.2GB 量级，
//    常驻内存不划算，只有第一次合成（设置页试听 / 代理转发 TTS 请求）
//    才通过 [TtsEngineManager.ensureLoaded] 真正加载，长时间不用再自动
//    释放（默认 5 分钟空闲）。
// 2. **引擎与模型解耦**：[TtsEngine] 负责模型文件定位与生命周期，
//    真正的推理交给 [TtsInferenceBackend]，后端可以整体替换。
// 3. **失败不缓存**：加载失败后 [_loadFuture] 必须清空，否则一次网络/解码
//    失败会让引擎永久处于错误态。
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'tts_backend_llamadart.dart';
import 'tts_backend_policy.dart';
import 'tts_model_service.dart';

/// 引擎状态。
enum TtsEngineStatus {
  /// 未加载（初始状态，也是释放后的状态）
  idle,

  /// 加载中
  loading,

  /// 就绪
  ready,

  /// 加载失败
  error,
}

/// 一次合成请求。
class TtsRequest {
  /// 要朗读的文本。
  final String text;

  /// 克隆音色的音频文件绝对路径；null = 用引擎默认音色。
  final String? voicePath;

  /// 该音色对应的参考文本（部分引擎需要）；可为 null。
  final String? voiceTranscript;

  /// 语言代码（Qwen3-TTS 用 zh / en / ja / ko / de / fr / ru / pt / es / it）。
  final String language;

  /// 语速，1.0 为基准。
  final double speed;

  const TtsRequest({
    required this.text,
    this.voicePath,
    this.voiceTranscript,
    this.language = 'zh',
    this.speed = 1.0,
  });
}

/// 合成结果：单声道浮点 PCM。
class TtsResult {
  final Float32List samples;

  /// 采样率，Qwen3-TTS 为 24000。
  final int sampleRate;

  const TtsResult(this.samples, this.sampleRate);

  Duration get duration => Duration(
      microseconds: (samples.length / sampleRate * 1000000).round());
}

class TtsEngineException implements Exception {
  final String message;
  TtsEngineException(this.message);

  @override
  String toString() => message;
}

/// 推理后端：真正跑模型的一层。
abstract class TtsInferenceBackend {
  /// 打开模型目录并初始化会话；可重复调用（实现需自行幂等）。
  Future<void> load(String modelDir);

  /// 合成一段文本。
  Future<TtsResult> synthesize(TtsRequest request);

  /// 释放显存/内存与会话。
  Future<void> dispose();
}

/// 引擎：管模型路径 + 后端生命周期。
abstract class TtsEngine {
  TtsInferenceBackend get backend;

  Future<void> load();

  Future<TtsResult> synthesize(TtsRequest request);

  Future<void> unload();
}

/// Qwen3-TTS 引擎：校验模型目录里主模型 / mmproj 齐全，
/// 然后交给后端加载。
class Qwen3TtsEngine implements TtsEngine {
  Qwen3TtsEngine({TtsInferenceBackend? backend})
      : backend = backend ?? LlamadartTtsBackend();

  @override
  final TtsInferenceBackend backend;

  bool _loaded = false;

  @override
  Future<void> load() async {
    final dir = await TtsModelService.readyModelDir();
    if (dir == null) {
      throw TtsEngineException('模型未下载或下载不完整');
    }
    await backend.load(dir);
    _loaded = true;
  }

  @override
  Future<TtsResult> synthesize(TtsRequest request) async {
    if (!_loaded) {
      await load();
    }
    return backend.synthesize(request);
  }

  @override
  Future<void> unload() async {
    await backend.dispose();
    _loaded = false;
  }
}

/// 引擎管理器（单例）。
///
/// 应用启动时不加载任何东西；首次 [speak] 才触发加载。空闲
/// [idleTimeout] 后自动释放，避免 1.2GB 模型常驻。
class TtsEngineManager extends ChangeNotifier {
  TtsEngineManager._();

  static final TtsEngineManager instance = TtsEngineManager._();

  /// 空闲多久后自动释放；设为 Duration.zero 表示不自动释放。
  Duration idleTimeout = const Duration(minutes: 5);

  TtsEngineStatus _status = TtsEngineStatus.idle;
  String? _errorMessage;
  TtsEngine? _engine;

  Future<void>? _loadFuture;
  Timer? _idleTimer;

  TtsEngineStatus get status => _status;

  String? get errorMessage => _errorMessage;

  bool get isReady => _status == TtsEngineStatus.ready;

  bool get isLoading => _status == TtsEngineStatus.loading;

  /// 引擎就绪后本次实际运行在哪个后端（CPU/GPU/NPU 及 NPU 回退信息）；
  /// 未加载或后端非 llamadart 时为 null。
  ResolvedTtsDevice? get activeDevice {
    final backend = _engine?.backend;
    return backend is LlamadartTtsBackend ? backend.activeDevice : null;
  }

  /// 懒加载：就绪则直接返回，否则加载一次。并发调用共享同一个 Future。
  Future<void> ensureLoaded() {
    if (_status == TtsEngineStatus.ready && _engine != null) {
      _pokeIdleTimer();
      return Future<void>.value();
    }
    final pending = _loadFuture;
    if (pending != null) return pending;

    // 加载 1.4GB 模型可能要很久，这期间绝不能被空闲释放掐掉
    _pauseIdleTimer();
    _setStatus(TtsEngineStatus.loading);
    final future = _doLoad();
    _loadFuture = future;
    return future;
  }

  Future<void> _doLoad() async {
    try {
      // 每次新建后端时读取最新的推理后端偏好（设置页改完偏好会先释放引擎）。
      final engine = _engine ??= Qwen3TtsEngine();
      await engine.load();
      _errorMessage = null;
      _setStatus(TtsEngineStatus.ready);
      _pokeIdleTimer();
    } catch (e) {
      _errorMessage = e is TtsEngineException ? e.message : '$e';
      _setStatus(TtsEngineStatus.error);
      // 失败不缓存：清掉引用与 Future，下次还能重试
      final broken = _engine;
      _engine = null;
      if (broken != null) {
        unawaited(broken.unload().catchError((_) {}));
      }
      rethrow;
    } finally {
      _loadFuture = null;
    }
  }

  /// 合成一段文本；引擎未就绪时自动加载。
  ///
  /// 加载与合成期间会暂停空闲释放：1.7B 模型加载 + 长文本合成轻易超过
  /// [idleTimeout]，计时器从开始就跑会把引擎在合成中途卸掉。
  Future<TtsResult> speak(
    String text, {
    String? voicePath,
    String? voiceTranscript,
    String language = 'zh',
    double speed = 1.0,
  }) async {
    _pauseIdleTimer();
    try {
      await ensureLoaded();
      final engine = _engine;
      if (engine == null) {
        throw TtsEngineException('引擎未就绪');
      }
      return await engine.synthesize(
        TtsRequest(
          text: text,
          voicePath: voicePath,
          voiceTranscript: voiceTranscript,
          language: language,
          speed: speed,
        ),
      );
    } finally {
      // 合成结束后才重新开始空闲计时
      _pokeIdleTimer();
    }
  }

  /// 主动释放（用户在设置里点删除模型 / 切后端）。
  Future<void> release() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    final engine = _engine;
    _engine = null;
    _loadFuture = null;
    if (engine != null) {
      await engine.unload();
    }
    _setStatus(TtsEngineStatus.idle);
  }

  /// 暂停空闲释放（加载 / 合成期间用）。不会自动恢复，调用方负责
  /// 在结束时重新 [_pokeIdleTimer]。
  void _pauseIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  void _pokeIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (idleTimeout <= Duration.zero) return;
    _idleTimer = Timer(idleTimeout, () {
      if (_status == TtsEngineStatus.ready) {
        unawaited(release());
      }
    });
  }

  void _setStatus(TtsEngineStatus s) {
    if (_status == s) return;
    _status = s;
    notifyListeners();
  }
}
