// test/tts_export_wav_test.dart
//
// TTS 导出 WAV 解析器的 host 侧单测（与 tts_speech_service._encodeWav
// 相同的容器布局，外加带附加 chunk 的变体）。原生 SILK/MP3 编码只能真机验证。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/tts/tts_export_service.dart';

Uint8List buildWav({
  required Int16List samples,
  int sampleRate = 24000,
  int channels = 1,
  int bits = 16,
  int audioFormat = 1,
  List<int>? suffix, // data 块之后的附加字节
}) {
  final dataSize = samples.length * 2;
  final headerSize = 44;
  final extra = suffix?.length ?? 0;
  final bytes = Uint8List(headerSize + dataSize + extra);
  final bd = ByteData.view(bytes.buffer);

  void ascii(int off, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes[off + i] = s.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  bd.setUint32(4, 36 + dataSize, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bd.setUint32(16, 16, Endian.little);
  bd.setUint16(20, audioFormat, Endian.little);
  bd.setUint16(22, channels, Endian.little);
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, sampleRate * channels * bits ~/ 8, Endian.little);
  bd.setUint16(32, channels * bits ~/ 8, Endian.little);
  bd.setUint16(34, bits, Endian.little);
  ascii(36, 'data');
  bd.setUint32(40, dataSize, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    bd.setInt16(headerSize + i * 2, samples[i], Endian.little);
  }
  if (suffix != null) bytes.setAll(headerSize + dataSize, suffix);
  return bytes;
}

void main() {
  test('parseWav 解析 24kHz mono s16 并逐采样一致', () {
    final n = 24000 * 3 ~/ 10; // 300ms
    final src = Int16List(n);
    for (var i = 0; i < n; i++) {
      src[i] = ((i % 200) - 100) * 200;
    }
    final wav = buildWav(samples: src);
    final pcm = TtsExportService.parseWav(wav);
    expect(pcm.sampleRate, 24000);
    expect(pcm.samples.length, n);
    expect(pcm.samples.first, src.first);
    expect(pcm.samples.last, src.last);
    expect(pcm.durationMillis, closeTo(300, 2));
  });

  test('parseWav 容忍 data 块后有杂散字节', () {
    final src = Int16List.fromList(List.generate(480, (i) => i - 240));
    final wav = buildWav(samples: src, suffix: List.filled(17, 0xAA));
    final pcm = TtsExportService.parseWav(wav);
    expect(pcm.samples.length, src.length);
  });

  test('parseWav 拒绝非 RIFF / 立体声 / 非 PCM', () {
    expect(
      () => TtsExportService.parseWav(Uint8List(64)),
      throwsA(isA<TtsExportException>()),
    );
    expect(
      () => TtsExportService.parseWav(
        buildWav(samples: Int16List(10), channels: 2),
      ),
      throwsA(isA<TtsExportException>()),
    );
    expect(
      () => TtsExportService.parseWav(
        buildWav(samples: Int16List(10), audioFormat: 3),
      ),
      throwsA(isA<TtsExportException>()),
    );
  });

  test('默认文件名带正确扩展名', () {
    final at = DateTime(2026, 9, 15, 19, 30, 7);
    expect(
      TtsExportService.fileNameFor(TtsExportFormat.mp3, at: at),
      '朗读_20260915_193007.mp3',
    );
    expect(
      TtsExportService.fileNameFor(TtsExportFormat.silk, at: at),
      '朗读_20260915_193007.silk',
    );
    expect(
      TtsExportService.fileNameFor(TtsExportFormat.slk, at: at),
      '朗读_20260915_193007.slk',
    );
  });
}
