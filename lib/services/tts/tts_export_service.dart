// lib/services/tts/tts_export_service.dart
//
// 把 16bit / 单声道 WAV 转成 MP3 或 SILK v3（.silk/.slk，内容相同仅扩展名
// 不同）。自 NaviFlash lib/services/tts_export_service.dart 移植，原生编码器
// 在 android/app/src/main/cpp/（libttsexport.so）。
//
// 两个入口：TTS 游乐场从磁盘上的缓存 WAV 转（[encodeWavFile]），对话模拟的
// 「下载」直接把合成结果字节转（[encodeWavBytes]），不经过那个固定覆盖的
// preview 文件。
//
// 编码在独立 isolate 跑（长文本 PCM 可能几十 MB，避免卡 UI）。
// SILK 的 tencent 模式对应 silk-v3-decoder 编码器的 -tencent
// （微信/QQ 兼容：0x02 文件头、无 0xFFFF 尾包），默认开启。
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tts_export_native.dart';

/// 导出容器格式。SILK 与 SLK 字节完全一致，只是扩展名不同。
enum TtsExportFormat {
  mp3('MP3', 'mp3', 'audio/mpeg'),
  silk('SILK', 'silk', 'audio/silk'),
  slk('SLK', 'slk', 'audio/silk');

  final String label;
  final String ext;
  final String mime;

  const TtsExportFormat(this.label, this.ext, this.mime);

  bool get isSilk => this != TtsExportFormat.mp3;
}

class TtsExportException implements Exception {
  final String message;
  TtsExportException(this.message);

  @override
  String toString() => message;
}

/// 解析后的 PCM（s16le 单声道）。
class TtsPcmData {
  final Int16List samples;
  final int sampleRate;

  const TtsPcmData(this.samples, this.sampleRate);

  int get durationMillis =>
      (samples.length / sampleRate * 1000).round();
}

class TtsExportService {
  TtsExportService._();

  /// SILK 编码器接受的 API 采样率（8/12/16/24/48k）。缓存 WAV 恒为 24k，
  /// 这里只是防御性校验。
  static const List<int> _silkRates = [8000, 12000, 16000, 24000, 48000];

  static bool get isSupported => TtsExportNative.instance.isSupported;

  /// 读 WAV 文件并编码为目标格式。在 isolate 中执行。
  static Future<Uint8List> encodeWavFile({
    required File wav,
    required TtsExportFormat format,
    required bool tencent,
  }) async {
    if (!isSupported) throw TtsExportUnsupportedException();
    if (!wav.existsSync()) {
      throw TtsExportException('音频文件不存在（可能已被缓存淘汰），请重新朗读');
    }
    return encodeWavBytes(
      await wav.readAsBytes(),
      format: format,
      tencent: tencent,
    );
  }

  /// 把 WAV **字节**编码为目标格式。在 isolate 中执行。
  ///
  /// 对话模拟的「下载」走这条：合成结果直接在内存里，不必先落成那个会被
  /// 下一次朗读覆盖的 preview 文件。
  static Future<Uint8List> encodeWavBytes(
    Uint8List wav, {
    required TtsExportFormat format,
    required bool tencent,
  }) {
    if (!isSupported) throw TtsExportUnsupportedException();

    // Isolate.run 可直接传 Uint8List / enum。
    return Isolate.run(() {
      final pcm = parseWav(wav);
      final native = TtsExportNative.instance;
      switch (format) {
        case TtsExportFormat.mp3:
          return native.encodeMp3(pcm.samples, pcm.sampleRate);
        case TtsExportFormat.silk:
        case TtsExportFormat.slk:
          if (!_silkRates.contains(pcm.sampleRate)) {
            throw TtsExportException(
              'SILK 不支持 ${pcm.sampleRate}Hz 采样率（需 8/12/16/24/48k）',
            );
          }
          return native.encodeSilk(
            pcm.samples,
            pcm.sampleRate,
            tencent: tencent,
          );
      }
    });
  }

  /// 默认文件名：`<label>_yyyyMMdd_HHmmss.<ext>`。
  ///
  /// [label] 会被清成文件名安全的形态（对话模拟那边传角色名）；空则用
  /// 「朗读」。
  static String fileNameFor(
    TtsExportFormat format, {
    DateTime? at,
    String label = '',
  }) {
    final t = at ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${t.year}${two(t.month)}${two(t.day)}_'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
    final safe =
        label
            .trim()
            .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
            .replaceAll(RegExp(r'_+'), '_')
            .replaceAll(RegExp(r'^_+|_+$'), '');
    final base = safe.isEmpty ? '朗读' : safe;
    // 太长的角色名会把时间戳挤出某些文件系统的 255 字节上限。
    final stem = base.length > 48 ? base.substring(0, 48) : base;
    return '${stem}_$stamp.${format.ext}';
  }

  /// 写一份临时文件供系统分享（缓存目录，可被 FileProvider 读取）。
  static Future<File> stageForShare(
    Uint8List bytes,
    String fileName,
  ) async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory(p.join(tmp.path, 'tts_export'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final f = File(p.join(dir.path, fileName));
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  /// 解析 16bit PCM WAV。遍历 RIFF chunk，不假定头恰好 44 字节
  ///（可能有 LIST/fact 等附加块）。只接受单声道、16bit、PCM(format=1)。
  static TtsPcmData parseWav(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    bool asciiAt(int off, String s) {
      if (off + s.length > bytes.length) return false;
      for (var i = 0; i < s.length; i++) {
        if (bytes[off + i] != s.codeUnitAt(i)) return false;
      }
      return true;
    }

    if (bytes.length < 12 ||
        !asciiAt(0, 'RIFF') ||
        !asciiAt(8, 'WAVE')) {
      throw TtsExportException('不是有效的 WAV 文件（缺 RIFF/WAVE 标识）');
    }

    int? audioFormat;
    int? channels;
    int? sampleRate;
    int? bitsPerSample;
    Uint8List? pcmBytes;

    var pos = 12;
    while (pos + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final size = bd.getUint32(pos + 4, Endian.little);
      final body = pos + 8;
      if (body + size > bytes.length) {
        // 可能是 data 之后的填充/杂散字节；fmt+data 已齐就不再往后走。
        if (pcmBytes != null && audioFormat != null) break;
        throw TtsExportException('WAV chunk 越界：$id');
      }
      if (id == 'fmt ' && size >= 16) {
        audioFormat = bd.getUint16(body, Endian.little);
        channels = bd.getUint16(body + 2, Endian.little);
        sampleRate = bd.getUint32(body + 4, Endian.little);
        bitsPerSample = bd.getUint16(body + 14, Endian.little);
      } else if (id == 'data') {
        pcmBytes = Uint8List.sublistView(bytes, body, body + size);
      }
      // 标准 WAV fmt 一定在 data 前；两者齐活即可停止。
      if (pcmBytes != null && audioFormat != null) break;
      pos = body + size + (size.isOdd ? 1 : 0); // chunk 字对齐
    }

    if (audioFormat == null ||
        channels == null ||
        sampleRate == null ||
        bitsPerSample == null) {
      throw TtsExportException('WAV 缺少 fmt 块');
    }
    if (audioFormat != 1) {
      throw TtsExportException('仅支持 PCM WAV（format=$audioFormat）');
    }
    if (channels != 1) {
      throw TtsExportException('仅支持单声道 WAV（channels=$channels）');
    }
    if (bitsPerSample != 16) {
      throw TtsExportException('仅支持 16bit WAV（bits=$bitsPerSample）');
    }
    if (pcmBytes == null || pcmBytes.isEmpty) {
      throw TtsExportException('WAV 没有音频数据');
    }
    // 长度按 2 字节对齐，末尾多半字节丢弃。
    final sampleCount = pcmBytes.length ~/ 2;
    final view = ByteData.sublistView(
      pcmBytes,
      0,
      sampleCount * 2,
    );
    final samples = Int16List(sampleCount);
    for (var i = 0; i < sampleCount; i++) {
      samples[i] = view.getInt16(i * 2, Endian.little);
    }
    return TtsPcmData(samples, sampleRate);
  }
}
