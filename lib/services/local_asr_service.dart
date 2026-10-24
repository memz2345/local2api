// 本地离线语音识别（sherpa-onnx 流式 zipformer CTC，中英普通话）。
//
// 为什么要有这一层：speech_to_text 依赖系统 RecognitionService，而国产 ROM
// 经常「有服务、不干活」——vivo 的默认服务（Jovi Copilot）对三方应用一律
// 秒回 error_client，Google 服务没有 Play 认证/连不上服务器回
// error_too_many_requests。系统引擎靠不住时，这一层就是兜底：离线模型
// （约 25MB，首次使用时下载）、record 采麦克风流、sherpa 流式解码，
// 端点静音判定出定稿。接口形状对齐 [SpeechInputService] 的收音三件套
// （onResult / onError / onStatus），切换时页面无感。
//
// 模型：sherpa-onnx-streaming-zipformer-small-ctc-zh-int8-2025-04-01
//（CTC 单文件 + tokens，int8 量化）。下载源 hf-mirror 优先（国内直连），
// huggingface 官方兜底。
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// 模型仓与文件清单（换模型改这里）。
const String _kModelRepo =
    'sherpa-onnx-streaming-zipformer-small-ctc-zh-int8-2025-04-01';
const List<String> _kModelFiles = ['model.int8.onnx', 'tokens.txt'];
const List<String> _kMirrors = [
  'https://hf-mirror.com/csukuangfj/$_kModelRepo/resolve/main',
  'https://huggingface.co/csukuangfj/$_kModelRepo/resolve/main',
];

/// 采麦克风流的目标块长（16kHz 下约 100ms 一块）。
const int _kChunkSamples = 1600;

/// 端点前导静音（秒）：比系统引擎的 pauseFor 短——通话轮次要跟手。
const double _kEndpointTrailingSilence = 1.8;

/// 本地 ASR 引擎。**进程级单例**：模型与识别器都很重，全应用一份。
class LocalAsrService {
  LocalAsrService._();

  static final LocalAsrService instance = LocalAsrService._();

  sherpa.OnlineRecognizer? _recognizer;
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _micSub;

  bool _starting = false;
  bool _listenActive = false;

  /// 下载进度广播（0.0 ~ 1.0；没有下载任务时不发）。UI 想跟进度就听它。
  final ValueNotifier<double?> downloadProgress = ValueNotifier(null);

  String? _lastError;
  String? get lastError => _lastError;

  String? _modelDir;
  String? get modelDir => _modelDir;

  /// 收音回调（start 时挂上）。
  void Function(String text, bool isFinal)? _onResult;
  void Function(String message)? _onError;
  void Function(String status)? _onStatus;

  bool get isListening => _listenActive;

  bool get isDownloading => downloadProgress.value != null;

  /// 磁盘检查的兜底超时：dart:io 的 Future 在 widget 测试的 fake async 里
  /// 可能永远不完成（平台通道同款问题），不能让它堵死收音主流程。
  static Future<bool> _fileExists(File f) =>
      f.exists().timeout(
        const Duration(milliseconds: 250),
        onTimeout: () => false,
      );

  /// 模型文件是否齐了（下载完会写标记，避免每次 stat 大文件）。
  /// 任何一步出异常（测试环境没有平台通道、磁盘只读等）都按「没就绪」算。
  Future<bool> isModelReady() async {
    try {
      if (kDebugMode) debugPrint('[local-asr] isModelReady: begin');
      final prefs = await SharedPreferences.getInstance();
      if (kDebugMode) debugPrint('[local-asr] isModelReady: prefs done');
      if (prefs.getBool('asr.local.ready') ?? false) return true;
      if (kDebugMode) debugPrint('[local-asr] isModelReady: resolving dir');
      final dir = await _resolveModelDir();
      if (kDebugMode) debugPrint('[local-asr] isModelReady: dir=$dir');
      if (dir == null) return false;
      for (final f in _kModelFiles) {
        if (!await _fileExists(File(p.join(dir, f)))) return false;
      }
      // 文件都在：补个标记，下次不再逐个 stat。
      await prefs.setBool('asr.local.ready', true);
      return true;
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[local-asr] isModelReady: failed $e');
      return false;
    }
  }

  Future<String?> _resolveModelDir() async {
    if (_modelDir != null) return _modelDir;
    try {
      // 超时兜底：平台通道在某些环境（widget 测试的 fake async）里可能
      // 永远不回来，别让它堵死收音主流程。
      final support = await getApplicationSupportDirectory().timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw StateError('path_provider timeout'),
      );
      return _modelDir = p.join(support.path, 'asr', _kModelRepo);
    } on Object catch (e) {
      _lastError = '$e';
      return null;
    }
  }

  /// 下载模型（幂等：齐了直接返回）。同一时间只允许一个下载任务。
  Future<bool> ensureModelDownloaded() async {
    if (await isModelReady()) return true;
    if (isDownloading) return false; // 已有任务在跑
    final dir = await _resolveModelDir();
    if (dir == null) return false;
    try {
      await Directory(dir).create(recursive: true);
      // 已存在的文件（上次下了一半成功的那几个）不重复下。
      final pending = <String>[];
      for (final f in _kModelFiles) {
        final existing = File(p.join(dir, f));
        final size = await _fileExists(existing)
            ? await existing.length().timeout(
                const Duration(milliseconds: 250),
                onTimeout: () => 0,
              )
            : 0;
        if (size == 0) pending.add(f);
      }
      for (var i = 0; i < pending.length; i++) {
        await _downloadOne(
          pending[i],
          p.join(dir, pending[i]),
          base: i / pending.length,
          span: 1 / pending.length,
        );
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('asr.local.ready', true);
      return true;
    } on Object catch (e) {
      _lastError = '模型下载失败: $e';
      return false;
    } finally {
      downloadProgress.value = null;
    }
  }

  Future<void> _downloadOne(
    String name,
    String target, {
    required double base,
    required double span,
  }) async {
    final tmp = File('$target.part');
    Object? lastFailure;
    final client = http.Client();
    try {
      for (final mirror in _kMirrors) {
      try {
        final request = http.Request('GET', Uri.parse('$mirror/$name'));
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          lastFailure = 'HTTP ${response.statusCode} ($mirror)';
          continue;
        }
        final total = response.contentLength ?? 0;
        var received = 0;
        final sink = tmp.openWrite();
        try {
          await for (final chunk in response.stream) {
            sink.add(chunk);
            received += chunk.length;
            if (total > 0) {
              downloadProgress.value =
                  (base + span * received / total).clamp(0.0, 1.0).toDouble();
            }
          }
        } finally {
          await sink.flush();
          await sink.close();
        }
        // 大文件下载完校验一下尺寸（http 层截断不该当成功）。
        if (total > 0 && await tmp.length() != total) {
          lastFailure = '下载不完整 (${await tmp.length()}/$total)';
          continue;
        }
        await tmp.rename(target);
        return;
      } on Object catch (e) {
        lastFailure = e;
      }
      }
    } finally {
      client.close();
    }
    throw StateError('所有下载源都失败: $lastFailure');
  }

  /// 确保识别器加载完成（模型就位是前提）。
  Future<bool> _ensureRecognizer() async {
    if (_recognizer != null) return true;
    try {
      sherpa.initBindings();
    } on Object catch (e) {
      _lastError = 'sherpa-onnx 初始化失败: $e';
      return false;
    }
    final dir = await _resolveModelDir();
    if (dir == null) return false;
    try {
      _recognizer = sherpa.OnlineRecognizer(
        sherpa.OnlineRecognizerConfig(
          model: sherpa.OnlineModelConfig(
            zipformer2Ctc: sherpa.OnlineZipformer2CtcModelConfig(
              model: p.join(dir, 'model.int8.onnx'),
            ),
            tokens: p.join(dir, 'tokens.txt'),
            numThreads: 2,
            provider: 'cpu',
            debug: false,
          ),
          enableEndpoint: true,
          // rule1 = 无语音时的静音判停，收紧一点让轮次跟手；
          // rule2 = 有语音后的尾部静音；rule3 = 最长话语强制断。
          rule1MinTrailingSilence: _kEndpointTrailingSilence,
          rule2MinTrailingSilence: _kEndpointTrailingSilence,
          rule3MinUtteranceLength: 20,
        ),
      );
      return true;
    } on Object catch (e) {
      _lastError = '识别器加载失败: $e';
      _recognizer = null;
      return false;
    }
  }

  /// 开始收音（接口形状对齐 SpeechInputService.start）。
  ///
  /// [localeId] 被 CTC 中英模型忽略；[pauseFor]/[listenFor] 由端点检测
  /// （[_kEndpointTrailingSilence]）与用户 stop 决定，参数只为形状兼容。
  Future<void> start({
    required void Function(String text, bool isFinal) onResult,
    void Function(String message)? onError,
    void Function(String status)? onStatus,
    String? localeId,
    Duration listenFor = const Duration(minutes: 2),
    Duration pauseFor = const Duration(seconds: 30),
  }) async {
    if (_starting || _listenActive) return;
    _starting = true;
    _onResult = onResult;
    _onError = onError;
    _onStatus = onStatus;
    _listenActive = true;
    try {
      if (!await _ensureRecognizer()) {
        _listenActive = false;
        _starting = false;
        _onError?.call(_lastError ?? '本地语音引擎不可用');
        return;
      }
      _recorder ??= AudioRecorder();
      // Android 上 startStream 若上一次没停干净会抛「already started」，
      // 先查状态再停一遍，保证从干净状态起。
      if (await _recorder!.isRecording()) {
        await _recorder!.stop();
      }
      final mic = await _recorder!.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.voiceRecognition),
        ),
      );
      _pump(mic);
      _onStatus?.call('listening');
    } on Object catch (e) {
      _listenActive = false;
      _onError?.call('麦克风打开失败: $e');
    } finally {
      _starting = false;
    }
  }

  /// 麦克风流消费：PCM16 → Float32 喂给流式识别器，端点出定稿。
  void _pump(Stream<Uint8List> mic) {
    final recognizer = _recognizer!;
    final stream = recognizer.createStream();
    final buffer = BytesBuilder(copy: true);
    var buffered = 0;
    // PCM16 mono：每样本 2 字节，凑够 ~100ms 再喂。
    const step = _kChunkSamples * 2;
    void feedBlock(Uint8List block) {
      final samples = _pcm16ToFloat32(block);
      stream.acceptWaveform(samples: samples, sampleRate: 16000);
      _decodeTick(recognizer, stream);
    }

    _micSub = mic.listen(
      (chunk) {
        buffer.add(chunk);
        buffered += chunk.length;
        if (buffered < step) return;
        final all = buffer.takeBytes();
        final blocks = all.length ~/ step;
        for (var b = 0; b < blocks; b++) {
          feedBlock(Uint8List.sublistView(all, b * step, (b + 1) * step));
        }
        final rest = all.length % step;
        if (rest > 0) {
          buffer.add(Uint8List.sublistView(all, all.length - rest));
        }
        buffered = rest;
      },
      onError: (Object e) {
        if (_listenActive) _onError?.call('收音中断: $e');
        _listenActive = false;
      },
      onDone: () {
        // 麦克风被系统收走（通话打断等）：安静收场。
        if (_listenActive) {
          _listenActive = false;
          _onStatus?.call('notListening');
        }
      },
      cancelOnError: true,
    );
  }

  void _decodeTick(sherpa.OnlineRecognizer recognizer, sherpa.OnlineStream stream) {
    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
    }
    final text = recognizer.getResult(stream).text.trim();
    if (text.isNotEmpty) {
      _onResult?.call(text, false);
    }
    if (recognizer.isEndpoint(stream)) {
      // 端点：把当前段当定稿交出去，然后重置流开下一段。
      if (text.isNotEmpty) {
        _onResult?.call(text, true);
      }
      recognizer.reset(stream);
    }
  }

  /// PCM16LE → [-1, 1] Float32。
  static Float32List _pcm16ToFloat32(Uint8List bytes) {
    final n = bytes.length ~/ 2;
    final out = Float32List(n);
    final data = ByteData.sublistView(bytes, 0, n * 2);
    for (var i = 0; i < n; i++) {
      out[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  /// 停止收音（把已识别的内容以定稿形式交出去）。
  Future<void> stop() async {
    _listenActive = false;
    await _shutdownMic();
    _clearSinks();
  }

  /// 取消收音（丢弃结果）。
  Future<void> cancel() async {
    _listenActive = false;
    await _shutdownMic();
    _clearSinks();
  }

  Future<void> _shutdownMic() async {
    await _micSub?.cancel();
    _micSub = null;
    final rec = _recorder;
    if (rec != null) {
      try {
        if (await rec.isRecording()) await rec.stop();
      } on Object {
        // 已停/被系统收走都无所谓。
      }
    }
  }

  void _clearSinks() {
    _onResult = null;
    _onError = null;
    _onStatus = null;
  }
}
