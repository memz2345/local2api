// 用 llamadart 跑 Qwen3-TTS 的推理后端实现。
//
// 自 NaviFlash lib/services/tts_backend_llamadart.dart 移植，偏好来源从
// SettingsService 换成本仓库的 TtsSettings。
//
// llamadart 的 `TextToSpeechEngine` 已经把 Qwen3-TTS 的全套编排做好了：
// 文本分词 → talker 自回归出 codec 帧 → 音频解码 → 24kHz 单声道 float32 PCM，
// 声音克隆也能直接传参考音频文件。所以这里只负责「加载两个 GGUF + 转发请求」，
// 不需要自己碰 llama.cpp 的底层 API。
//
// 模型文件由 TtsModelService 下载，这里是本地路径加载（ModelSource.path），
// 不经过 llamadart 自带的 HuggingFace 下载通道——下载源要能被用户切镜像站。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:path/path.dart' as p;

import 'tts_backend_policy.dart';
import 'tts_engine.dart';
import 'tts_native_log.dart';
import 'tts_settings.dart';

/// Qwen3-TTS 的推理后端（llama.cpp，经 llamadart）。
class LlamadartTtsBackend implements TtsInferenceBackend {
  llama.LlamaEngine? _engine;
  llama.TextToSpeechEngine? _tts;

  /// 本次加载实际使用的后端（NPU 不支持回退 CPU 后与用户偏好不同）；
  /// 未加载时为 null。供设置页展示「实际运行在 CPU / GPU / NPU」。
  ResolvedTtsDevice? activeDevice;

  /// 主模型文件名；必须与 TtsModelService 清单里的名字一致。
  static const String modelFileName =
      'Qwen3-TTS-12Hz-1.7B-Base-Q4_K_M.gguf';

  /// 音频生成投影器（mmproj），Qwen3-TTS 必须加载。
  static const String projectorFileName =
      'mmproj-Qwen3-TTS-12Hz-1.7B-Base-Q8_0.gguf';

  @override
  Future<void> load(String modelDir) async {
    await dispose();

    // 必须在任何 ggml 初始化/模型加载前安装，才能抓到 Hexagon 后端注册、
    // HTP0 会话建立、层卸载等原生日志（判定真实运行后端）。
    TtsNativeLog.install();

    // 按「用户偏好 × SoC × 随包运行时」解析出实际后端：
    // 高通平台默认 NPU，运行时没编 Hexagon 或非高通设备时回退 CPU。
    await TtsSettings.instance.load();
    var resolved = await TtsBackendPolicy.resolve(
      TtsSettings.instance.device,
    );

    Object? npuLoadError;
    try {
      await _loadOnce(modelDir, resolved);
    } catch (e) {
      // NPU 意图明确但本次实际下发的就是 Hexagon：设备虽然枚举到了，
      // HTP session / FastRPC 共享内存 / buffer 分配仍可能失败（未签名
      // skel 被 CDSP 拒、机型差异等）。此时自动用纯 CPU 重试一次，
      // 兑现「不支持就回退 CPU」，不把错误甩给用户。
      final usedHexagon =
          resolved.gpuBackend == llama.GpuBackend.hexagon;
      if (!usedHexagon) rethrow;
      npuLoadError = e;
      debugPrint('[TtsBackend] NPU 加载失败，回退 CPU 重试：$e');
      await dispose();
      resolved = ResolvedTtsDevice.cpuFallbackFrom(resolved);
      await _loadOnce(modelDir, resolved);
    }

    activeDevice = resolved;
    final caps = await _tts!.capabilities;
    final fallbackNote = resolved.fellBackFromNpu
        ? '（期望 NPU 不可用，已回退 '
            '${resolved.effective == TtsInferenceDevicePreference.gpu ? 'GPU' : 'CPU'}：'
            '${resolved.fallbackReason?.name}'
            '${npuLoadError != null ? '，NPU 报错：$npuLoadError' : ''}）'
        : '';
    debugPrint('[TtsBackend] 就绪：${caps.backendName} @ ${caps.sampleRateHz}Hz'
        ' · 克隆=${caps.supportsSpeakerReference} · '
        '偏好=${resolved.preference.name} 实际=${resolved.effective.name}'
        '$fallbackNote');
  }

  /// 按给定后端完整加载一次主模型 + mmproj + TTS 引擎；失败时自行清理并抛出。
  Future<void> _loadOnce(String modelDir, ResolvedTtsDevice resolved) async {
    final engine = llama.LlamaEngine(llama.LlamaBackend());
    // LlamaBackend 构造会把 ggml 日志回调替换成写 stderr 的版本；加载模型
    // 前把回调（debug 级别）挂回来，才能在 logcat 看到 HTP offload 明细。
    TtsNativeLog.rearm();
    try {
      await engine.loadModelSource(
        llama.ModelSource.path(p.join(modelDir, modelFileName)),
        modelParams: llama.ModelParams(
          preferredBackend: resolved.gpuBackend,
          gpuLayers: resolved.gpuLayers,
        ),
      );
      await engine.loadMultimodalProjectorSource(
        llama.ModelSource.path(p.join(modelDir, projectorFileName)),
      );

      final tts = llama.TextToSpeechEngine(
        engine,
        modelProfile: llama.TextToSpeechModelProfile.qwen3Tts,
      );
      // 加载成功不代表能合成：原生库可能没导出 TTS ABI，或 mmproj 与模型不匹配
      final caps = await tts.capabilities;
      if (!caps.isSupported) {
        throw TtsEngineException(
            caps.unsupportedReason ?? '当前运行时不支持 Qwen3-TTS 合成');
      }

      _engine = engine;
      _tts = tts;
    } catch (e) {
      await engine.dispose().catchError((_) {});
      if (e is TtsEngineException) rethrow;
      throw TtsEngineException('加载朗读引擎失败：$e');
    }
  }

  @override
  Future<TtsResult> synthesize(TtsRequest request) async {
    final tts = _tts;
    if (tts == null) {
      throw TtsEngineException('引擎未加载');
    }

    final task = await tts.synthesize(
      llama.TextToSpeechRequest(
        text: request.text,
        language: request.language,
        speakerReference: request.voicePath == null
            ? null
            : llama.SpeechAudioFileInput(request.voicePath!),
      ),
    );

    llama.TextToSpeechResult? result;
    await for (final event in task.events) {
      if (event is llama.TextToSpeechFinalEvent) {
        result = event.result;
        break;
      }
    }
    final done = result;
    if (done == null) {
      throw TtsEngineException('合成未返回结果');
    }
    return TtsResult(done.samples, done.sampleRateHz);
  }

  @override
  Future<void> dispose() async {
    final engine = _engine;
    _engine = null;
    _tts = null;
    activeDevice = null;
    if (engine != null) {
      await engine.dispose().catchError((_) {});
    }
  }
}
