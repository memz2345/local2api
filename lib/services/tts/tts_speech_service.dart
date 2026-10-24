// 朗读的「播放」这一层：把 TtsResult 的 float32 PCM 编成 WAV 落文件，
// 交给 audioplayers 播放。引擎加载与合成由 TtsEngineManager 负责。
//
// 自 NaviFlash lib/services/tts_speech_service.dart 移植：那边走 media_kit
// （项目里已有的播放链路），本仓库没有媒体栈，为不引入一个上百 MB 的
// 依赖换成轻量的 audioplayers —— 只播本地 WAV 足够了。缓存层
// （TtsAudioCacheService）也一并去掉：本仓库的朗读只服务「设置页试听」
// 这一个场景，固定写一个 preview.wav 覆盖即可。
//
// 同时刻只允许一段朗读：点新的会先停掉旧的，避免两个声音叠在一起。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tts_engine.dart';
import 'tts_model_service.dart';

/// 朗读状态。
enum TtsSpeechStatus {
  /// 空闲
  idle,

  /// 正在加载引擎（首次合成会卡在这，1.4GB 模型）
  preparing,

  /// 引擎就绪，正在合成音频
  synthesizing,

  /// 播放中
  playing,
}

class TtsSpeechService extends ChangeNotifier {
  TtsSpeechService._();

  static final TtsSpeechService instance = TtsSpeechService._();

  TtsSpeechStatus _status = TtsSpeechStatus.idle;
  String? _errorMessage;

  /// 当前在播/在合成的条目标识（对话模拟里用消息 key）：UI 据此把
  /// 正在朗读的那条气泡按钮转成「停止」。null = 空闲。
  String? activeTag;

  AudioPlayer? _player;
  StreamSubscription<void>? _completedSub;

  /// 最近一次实际播放的 WAV 文件（调试用）。
  String? lastWavPath;

  TtsSpeechStatus get status => _status;

  String? get errorMessage => _errorMessage;

  bool get isIdle => _status == TtsSpeechStatus.idle;

  bool isActive(String tag) => activeTag == tag && !isIdle;

  /// 本地合成并播放（引擎加载与合成走 TtsEngineManager）。
  ///
  /// [voicePath] 是克隆音色样本（wav）；null/空 = 引擎默认音色。
  /// 再次调用同一个 [tag] 视为「停止」开关（同密钥页的开关语义）。
  Future<void> speak(
    String tag,
    String text, {
    String? voicePath,
  }) async {
    if (isActive(tag)) {
      await stop();
      return;
    }
    final cleaned = text.trim();
    if (cleaned.isEmpty) return;

    await _start(tag);
    try {
      _setStatus(TtsSpeechStatus.synthesizing);
      final wav = await synthesizeLocal(cleaned, voicePath: voicePath);
      final file = await _previewFile('local.wav');
      await file.writeAsBytes(wav, flush: true);
      await _play(file.path);
    } catch (e) {
      _fail(e);
      rethrow;
    }
  }

  /// 本地合成，**只返回** 16bit / 单声道 WAV 字节 —— 不落盘、不播放、
  /// 不碰 [activeTag] 与朗读状态。
  ///
  /// 播放（[speak]）与导出（`TtsMessageExport`）共用这一条合成路径，
  /// 免得两边的引擎/模型检查走岔。
  Future<Uint8List> synthesizeLocal(String text, {String? voicePath}) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) throw TtsModelException('没有可合成的文本');
    // 模型没下就别加载引擎了，直接给明确提示
    final state = await TtsModelService.state();
    if (state != TtsModelState.installed) {
      throw TtsModelException('模型未下载或下载不完整');
    }
    final result = await TtsEngineManager.instance.speak(
      cleaned,
      voicePath: (voicePath ?? '').isEmpty ? null : voicePath,
    );
    return encodeWav(result.samples, result.sampleRate);
  }

  /// 云端合成并播放：走本机代理的 `/v1/audio/speech`（OpenAI TTS 形态），
  /// 由代理按模型路由 —— audio 模态上游翻译成 chat.completions，
  /// localTts 上游回到本地引擎。回包是原始 WAV 字节。
  ///
  /// [voiceSamplePath] 是克隆样本（wav/mp3）：非空就转成 data URI 放进
  /// `voice_sample`（代理会塞给上游的 audio.voice）——是否该带样本由
  /// 路由层（ChatTts）按目标模型档位决定，这层只管照发。
  ///
  /// [instructions] 是风格指令 / 音色描述：代理会放进 `role: user` 的
  /// 消息。voicedesign 模型必填（就是音色描述），其余模型可选。
  Future<void> speakCloud(
    String tag,
    String text, {
    required String model,
    required String host,
    required int port,
    String? apiKey,
    String? voiceSamplePath,
    String? instructions,
  }) async {
    if (isActive(tag)) {
      await stop();
      return;
    }
    final cleaned = text.trim();
    if (cleaned.isEmpty) return;

    await _start(tag);
    try {
      _setStatus(TtsSpeechStatus.synthesizing);
      final bytes = await synthesizeCloud(
        cleaned,
        model: model,
        host: host,
        port: port,
        apiKey: apiKey,
        voiceSamplePath: voiceSamplePath,
        instructions: instructions,
      );
      final file = await _previewFile('cloud.wav');
      await file.writeAsBytes(bytes, flush: true);
      await _play(file.path);
    } catch (e) {
      _fail(e);
      rethrow;
    }
  }

  /// 云端合成，**只返回** WAV 字节 —— 不落盘、不播放、不碰朗读状态。
  /// 参数语义与 [speakCloud] 完全一致；播放那条路就是「这个 + 写文件 + 播」。
  Future<Uint8List> synthesizeCloud(
    String text, {
    required String model,
    required String host,
    required int port,
    String? apiKey,
    String? voiceSamplePath,
    String? instructions,
  }) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) throw TtsModelException('没有可合成的文本');
    final uri = Uri.parse('http://$host:$port/v1/audio/speech');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      if ((apiKey ?? '').isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      }
      final sample = (voiceSamplePath ?? '').trim();
      String? sampleDataUri;
      if (sample.isNotEmpty) {
        final bytes = await File(sample).readAsBytes();
        final mime =
            sample.toLowerCase().endsWith('.mp3') ? 'audio/mpeg' : 'audio/wav';
        sampleDataUri = 'data:$mime;base64,${base64Encode(bytes)}';
      }
      final instruction = (instructions ?? '').trim();
      req.write(
        jsonEncode({
          'model': model,
          'input': cleaned,
          'response_format': 'wav',
          'voice_sample': ?sampleDataUri,
          'instructions': ?instruction.isEmpty ? null : instruction,
        }),
      );
      final res = await req.close().timeout(const Duration(minutes: 5));
      final builder = BytesBuilder(copy: false);
      await for (final chunk in res) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (res.statusCode != 200) {
        final body = utf8.decode(bytes, allowMalformed: true);
        throw TtsModelException('TTS 请求失败 HTTP ${res.statusCode}: $body');
      }
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _start(String tag) async {
    _errorMessage = null;
    activeTag = tag;
    await stopPlaybackOnly();
    _setStatus(TtsSpeechStatus.preparing);
  }

  void _fail(Object e) {
    _errorMessage = e is TtsEngineException || e is TtsModelException
        ? e.toString()
        : '$e';
    activeTag = null;
    _setStatus(TtsSpeechStatus.idle);
  }

  Future<void> _play(String path) async {
    lastWavPath = path;
    final player = _player ??= AudioPlayer();
    _completedSub?.cancel();
    _completedSub = player.onPlayerComplete.listen((_) {
      _resetToIdle();
    });
    await player.stop().catchError((_) {});
    // 本地文件必须走 file:// URI（DeviceFileSource 内部处理）。
    await player.play(DeviceFileSource(path));
    _setStatus(TtsSpeechStatus.playing);
  }

  /// 试听一段文本（设置页用）：固定 tag，再次调用先停。
  Future<void> speakPreview(String text) =>
      speak('preview', text);

  /// 停止当前朗读。
  Future<void> stop() async {
    activeTag = null;
    _errorMessage = null;
    if (_status != TtsSpeechStatus.idle) {
      _setStatus(TtsSpeechStatus.idle);
    }
    await stopPlaybackOnly();
  }

  /// 只停播放器，不动状态标签（speak 开头切条时用）。
  Future<void> stopPlaybackOnly() async {
    final player = _player;
    if (player != null) {
      await player.stop().catchError((_) {});
    }
  }

  void _resetToIdle() {
    if (_status == TtsSpeechStatus.playing) {
      activeTag = null;
      _setStatus(TtsSpeechStatus.idle);
    }
  }

  void _setStatus(TtsSpeechStatus s) {
    if (_status == s) return;
    _status = s;
    notifyListeners();
  }

  /// 试听 / 朗读 WAV 的落盘位置：`getApplicationSupportDirectory()/tts/<name>`。
  static Future<File> _previewFile(String name) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'tts'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(p.join(dir.path, name));
  }

  /// float32 单声道 PCM → 16bit WAV。
  static Uint8List encodeWav(Float32List samples, int sampleRate) {
    const headerSize = 44;
    final dataSize = samples.length * 2;
    final bytes = Uint8List(headerSize + dataSize);
    final bd = ByteData.view(bytes.buffer);

    void writeAscii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        bytes[offset + i] = s.codeUnitAt(i);
      }
    }

    writeAscii(0, 'RIFF');
    bd.setUint32(4, 36 + dataSize, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    bd.setUint32(16, 16, Endian.little); // fmt chunk 长度
    bd.setUint16(20, 1, Endian.little); // PCM
    bd.setUint16(22, 1, Endian.little); // 单声道
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, sampleRate * 2, Endian.little); // byteRate
    bd.setUint16(32, 2, Endian.little); // blockAlign
    bd.setUint16(34, 16, Endian.little); // bitsPerSample
    writeAscii(36, 'data');
    bd.setUint32(40, dataSize, Endian.little);

    for (var i = 0; i < samples.length; i++) {
      final clamped = samples[i].clamp(-1.0, 1.0);
      bd.setInt16(headerSize + i * 2, (clamped * 32767).round(), Endian.little);
    }
    return bytes;
  }

  @override
  void dispose() {
    _completedSub?.cancel();
    _completedSub = null;
    _player?.dispose().catchError((_) {});
    _player = null;
    super.dispose();
  }
}
