// integration_test/tts_export_probe_test.dart
//
// 原生 SILK / MP3 编码器探针（手动跑，真机/模拟器）。
//
// 对话模拟的「下载」把朗读音频转成 mp3 / silk / slk，编码器是从 NaviFlash
// 移植来的 android/app/src/main/cpp（libttsexport.so：SILK 定点 SDK +
// LAME）。host 侧单测只能覆盖 WAV 解析（test/tts_export_wav_test.dart），
// .so 能不能 dlopen、字节对不对只能在 Android 上实测。
//
// 这里不依赖 TTS 模型：自己在 Dart 里合成一段 24kHz 正弦写成 WAV，直接喂给
// 编码器，验四件事：
//   1. libttsexport.so 打得开、三个符号查得到；
//   2. SILK 容器头对：-tencent 先 0x02 再 "#!SILK_V3"，非 tencent 直接
//      "#!SILK_V3" 且结尾带 int16 -1（0xFFFF）哨兵包；
//   3. 包体是「int16 LE 长度 + payload」，能整除还原、没有半截包；
//   4. MP3 出得来且不是空壳。
//
// 跑法（设备/模拟器连着）：
//   flutter test integration_test/tts_export_probe_test.dart -d <deviceId>
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local2api/services/tts/tts_export_native.dart';
import 'package:local2api/services/tts/tts_export_service.dart';
import 'package:local2api/services/tts/tts_speech_service.dart';

/// 24kHz 单声道正弦（440Hz，2 秒），float32 → 16bit WAV 字节。
/// 采样率取 24000 是因为本地 Qwen3-TTS 就是 24kHz，顺带验这条真实档位。
Uint8List sineWav({int sampleRate = 24000, double seconds = 2.0}) {
  final n = (sampleRate * seconds).round();
  final samples = Float32List(n);
  for (var i = 0; i < n; i++) {
    // 0.3 幅度：留足余量，别让 LAME 削顶。
    samples[i] = 0.3 * math.sin(2 * math.pi * 440 * i / sampleRate);
  }
  return TtsSpeechService.encodeWav(samples, sampleRate);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const silkMagic = '#!SILK_V3';

  List<int> ascii(String s) => s.codeUnits;

  testWidgets('原生 SILK / MP3 编码器探针', (tester) async {
    // 1. 库能打开吗（构造函数里 dlopen + lookup，抛异常就是没链进去）
    expect(TtsExportNative.instance.isSupported, isTrue);
    expect(TtsExportService.isSupported, isTrue);

    final wav = sineWav();
    // ignore: avoid_print
    print('PROBE wav=${wav.length}B (24kHz mono s16, 2s)');

    // 2a. SILK + tencent：0x02 打头，紧跟 #!SILK_V3，结尾不写哨兵包
    final tencent = await TtsExportService.encodeWavBytes(
      wav,
      format: TtsExportFormat.silk,
      tencent: true,
    );
    expect(tencent, isNotEmpty);
    expect(tencent[0], 0x02, reason: '-tencent 容器要先一个 0x02 前缀字节');
    expect(
      ascii(silkMagic),
      equals(tencent.sublist(1, 1 + silkMagic.length)),
      reason: '0x02 之后必须紧跟 #!SILK_V3',
    );
    expect(
      tencent.sublist(tencent.length - 2),
      isNot(equals(<int>[0xFF, 0xFF])),
      reason: 'tencent 模式不写 0xFFFF 尾哨兵（微信/QQ 不认）',
    );

    // 2b. SILK 不带 tencent：直接 #!SILK_V3 打头，结尾带 int16 -1 哨兵
    final plain = await TtsExportService.encodeWavBytes(
      wav,
      format: TtsExportFormat.silk,
      tencent: false,
    );
    expect(
      ascii(silkMagic),
      equals(plain.sublist(0, silkMagic.length)),
      reason: '非 tencent 容器直接以 #!SILK_V3 开头',
    );
    expect(
      plain.sublist(plain.length - 2),
      equals(<int>[0xFF, 0xFF]),
      reason: '非 tencent 结尾要有 int16 -1 哨兵包（否则文件以 0 长度包结束）',
    );

    // 3. 包体是「int16 LE 长度 + payload」，逐包走一遍必须正好落在末尾
    //    （tencent 版从 1 + 9 开始；末尾不留哨兵）。
    void walkPackets(Uint8List bytes, int from, int to, String tag) {
      final bd = ByteData.sublistView(bytes);
      var pos = from;
      var count = 0;
      while (pos + 2 <= to) {
        final len = bd.getInt16(pos, Endian.little);
        expect(len, greaterThan(0), reason: '$tag 第 $count 包长度为 0，容器坏了');
        expect(
          pos + 2 + len,
          lessThanOrEqualTo(to),
          reason: '$tag 第 $count 包越界（len=$len 剩 ${to - pos - 2}）',
        );
        pos += 2 + len;
        count++;
      }
      expect(pos, equals(to), reason: '$tag 包边界没对齐到末尾（差 $to-$pos）');
      // 2 秒音频 / 20ms 一包 ≈ 100 包
      expect(count, greaterThan(50), reason: '$tag 只有 $count 包，不像 2 秒');
      // ignore: avoid_print
      print('PROBE $tag packets=$count');
    }

    walkPackets(tencent, 1 + silkMagic.length, tencent.length, 'silk-tencent');
    walkPackets(
      plain,
      silkMagic.length,
      plain.length - 2,
      'silk-plain',
    ); // 减掉 2 字节尾哨兵

    // silk 与 slk 只是扩展名不同，字节必须完全一致
    final slk = await TtsExportService.encodeWavBytes(
      wav,
      format: TtsExportFormat.slk,
      tencent: true,
    );
    expect(slk.length, equals(tencent.length));
    var firstDiff = -1;
    for (var i = 0; i < slk.length; i++) {
      if (slk[i] != tencent[i]) {
        firstDiff = i;
        break;
      }
    }
    expect(firstDiff, -1, reason: 'SLK 与 SILK 应当字节完全相同，$firstDiff 处不同');

    // 4. MP3
    final mp3 = await TtsExportService.encodeWavBytes(
      wav,
      format: TtsExportFormat.mp3,
      tencent: false,
    );
    expect(mp3.length, greaterThan(1024), reason: '2 秒 64kbps ABR 不可能这么小');
    // 无 ID3：直接是帧同步头 0xFF Ex/0xFx
    expect(mp3[0], 0xFF, reason: 'MP3 首字节应是帧同步 0xFF（没写 ID3）');
    expect(
      mp3[1] & 0xE0,
      0xE0,
      reason: 'MP3 第二字节高 3 位也要是 1（帧同步）',
    );

    // ignore: avoid_print
    print(
      'PROBE OK silk-tencent=${tencent.length}B silk-plain=${plain.length}B '
      'slk=${slk.length}B mp3=${mp3.length}B',
    );
  });
}
