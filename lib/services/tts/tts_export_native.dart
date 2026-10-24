// lib/services/tts/tts_export_native.dart
//
// libttsexport.so 的 Dart FFI 绑定（SILK v3 + MP3 编码，见
// android/app/src/main/cpp/ttsexport.c）。自 NaviFlash 移植；那边 ffi 是
// dev_dependency 所以顶部挂了 ignore，本仓库 ffi 是正式依赖，不需要。
//
// 只在 Android 上可用；其他平台 [isSupported] 为 false，调用编码方法会
// 抛出 [TtsExportUnsupportedException]。
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' show calloc, malloc;

/// 非 Android 平台调用编码时抛出。
class TtsExportUnsupportedException implements Exception {
  @override
  String toString() => 'MP3/SILK 导出目前仅支持 Android';
}

/// 原生编码失败（参数错误 / 编码器内部错误）。
class TtsNativeEncodeException implements Exception {
  final String message;
  TtsNativeEncodeException(this.message);

  @override
  String toString() => message;
}

// --- C 函数签名 ---

typedef _EncodeSilkC = Pointer<Uint8> Function(
  Pointer<Int16> pcm,
  Int32 nSamples,
  Int32 sampleRate,
  Int32 tencent,
  Int32 bitrateBps,
  Pointer<Int32> outSize,
  Pointer<Int8> err,
  Int32 errLen,
);
typedef _EncodeSilkDart = Pointer<Uint8> Function(
  Pointer<Int16> pcm,
  int nSamples,
  int sampleRate,
  int tencent,
  int bitrateBps,
  Pointer<Int32> outSize,
  Pointer<Int8> err,
  int errLen,
);

typedef _EncodeMp3C = Pointer<Uint8> Function(
  Pointer<Int16> pcm,
  Int32 nSamples,
  Int32 sampleRate,
  Pointer<Int32> outSize,
  Pointer<Int8> err,
  Int32 errLen,
);
typedef _EncodeMp3Dart = Pointer<Uint8> Function(
  Pointer<Int16> pcm,
  int nSamples,
  int sampleRate,
  Pointer<Int32> outSize,
  Pointer<Int8> err,
  int errLen,
);

typedef _FreeC = Void Function(Pointer<Void> p);
typedef _FreeDart = void Function(Pointer<Void> p);

class TtsExportNative {
  TtsExportNative._() {
    if (!Platform.isAndroid) return;
    final lib = DynamicLibrary.open('libttsexport.so');
    _encodeSilk = lib.lookupFunction<_EncodeSilkC, _EncodeSilkDart>(
      'tts_silk_encode',
    );
    _encodeMp3 = lib.lookupFunction<_EncodeMp3C, _EncodeMp3Dart>(
      'tts_mp3_encode',
    );
    _free = lib.lookupFunction<_FreeC, _FreeDart>('tts_free');
  }

  static final TtsExportNative instance = TtsExportNative._();

  bool get isSupported => Platform.isAndroid;

  late final _EncodeSilkDart _encodeSilk;
  late final _EncodeMp3Dart _encodeMp3;
  late final _FreeDart _free;

  static const int _errCap = 256;

  // C 侧错误文案是固定 ASCII（含错误码），读到第一个 0 即可。
  String _drainError(Pointer<Int8> err) {
    final bytes = err.cast<Uint8>();
    final raw = <int>[];
    for (var i = 0; i < _errCap; i++) {
      final b = bytes[i];
      if (b == 0) break;
      raw.add(b);
    }
    return raw.isEmpty ? 'native encoder failed' : String.fromCharCodes(raw);
  }

  /// PCM s16le 单声道 → SILK v3。
  ///
  /// [tencent] 即上游编码器的 -tencent（微信/QQ 兼容：0x02 头、无尾包）。
  Uint8List encodeSilk(
    Int16List pcm,
    int sampleRate, {
    required bool tencent,
    int bitrateBps = 25000,
  }) {
    if (!isSupported) throw TtsExportUnsupportedException();

    final pcmPtr = malloc<Int16>(pcm.length);
    final sizePtr = malloc<Int32>(1);
    final errPtr = calloc<Int8>(_errCap); // calloc 已清零
    Pointer<Uint8> outPtr = nullptr;
    try {
      pcmPtr.asTypedList(pcm.length).setAll(0, pcm);
      outPtr = _encodeSilk(
        pcmPtr,
        pcm.length,
        sampleRate,
        tencent ? 1 : 0,
        bitrateBps,
        sizePtr,
        errPtr,
        _errCap,
      );
      if (outPtr == nullptr) {
        throw TtsNativeEncodeException(_drainError(errPtr));
      }
      final size = sizePtr.value;
      if (size <= 0) throw TtsNativeEncodeException('empty silk payload');
      return Uint8List.fromList(outPtr.asTypedList(size));
    } finally {
      if (outPtr != nullptr) _free(outPtr.cast<Void>());
      malloc.free(pcmPtr);
      malloc.free(sizePtr);
      calloc.free(errPtr);
    }
  }

  /// PCM s16le 单声道 → MP3（LAME mono ABR 64kbps）。
  Uint8List encodeMp3(Int16List pcm, int sampleRate) {
    if (!isSupported) throw TtsExportUnsupportedException();

    final pcmPtr = malloc<Int16>(pcm.length);
    final sizePtr = malloc<Int32>(1);
    final errPtr = calloc<Int8>(_errCap);
    Pointer<Uint8> outPtr = nullptr;
    try {
      pcmPtr.asTypedList(pcm.length).setAll(0, pcm);
      outPtr = _encodeMp3(
        pcmPtr,
        pcm.length,
        sampleRate,
        sizePtr,
        errPtr,
        _errCap,
      );
      if (outPtr == nullptr) {
        throw TtsNativeEncodeException(_drainError(errPtr));
      }
      final size = sizePtr.value;
      if (size <= 0) throw TtsNativeEncodeException('empty mp3 payload');
      return Uint8List.fromList(outPtr.asTypedList(size));
    } finally {
      if (outPtr != nullptr) _free(outPtr.cast<Void>());
      malloc.free(pcmPtr);
      malloc.free(sizePtr);
      calloc.free(errPtr);
    }
  }
}
