// 把 llama.cpp / ggml 的原生日志（GGML_LOG_*，包含 Hexagon 后端的
// "ggml-hex: ... HTP0 ... _dom=cdsp ..." 关键行）转发到 Flutter
// debugPrint。
//
// 自 NaviFlash lib/services/tts_native_log.dart 原样移植：llamadart 0.8.23
// 没有在 Dart 侧注册 ggml 日志回调，ggml 默认输出到 stderr，而 Android 14
// 很多 ROM 不把第三方应用的 stderr 收进 logcat。判定 NPU 是否真建会话
// 只能靠这些行。
// ignore_for_file: non_constant_identifier_names, library_private_types_in_public_api, unnecessary_library_name, depend_on_referenced_packages
@ffi.DefaultAsset('package:llamadart/llamadart')
library tts_native_log;

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

typedef _LogCbNative = ffi.Void Function(
  ffi.Int32 level,
  ffi.Pointer<ffi.Char> text,
  ffi.Pointer<ffi.Void> userData,
);
typedef _LogSetNative = ffi.Void Function(
  ffi.Pointer<ffi.NativeFunction<_LogCbNative>>,
  ffi.Pointer<ffi.Void>,
);

// ggml-hexagon 后端用 GGML_LOG_INFO，走 ggml 自己的 logger（不是 llama 的），
// 必须注册 ggml_log_set；llama_log_set 收不到 hexagon 的日志。
@ffi.Native<_LogSetNative>()
external void ggml_log_set(
  ffi.Pointer<ffi.NativeFunction<_LogCbNative>> logCallback,
  ffi.Pointer<ffi.Void> userData,
);

// llamadart 包装层日志级别开关（0 none/1 debug/2 info/3 warn/4 error），
// 同时会重设 ggml 回调——调用后必须再 ggml_log_set 挂回自己的回调。
typedef _SetLogLevelNative = ffi.Void Function(ffi.Int32);
@ffi.Native<_SetLogLevelNative>()
external void llama_dart_set_log_level(int level);

// llama.cpp 自己的 logger（load_tensors 的层 offload / buffer 统计走这条，
// 不是 ggml_log_set）；签名与 ggml_log_set 相同。
@ffi.Native<_LogSetNative>()
external void llama_log_set(
  ffi.Pointer<ffi.NativeFunction<_LogCbNative>> logCallback,
  ffi.Pointer<ffi.Void> userData,
);

/// 把 llama.cpp/ggml 原生日志桥接到 [debugPrint]。
class TtsNativeLog {
  TtsNativeLog._();

  static ffi.NativeCallable<_LogCbNative>? _callable;

  /// 原生回调被调用的总次数（验证回调链路是否真的接通）。
  static int totalCalls = 0;

  /// 最近捕获的原生日志。只保留与后端/设备/层卸载/错误相关的行，最多 200 行。
  static final List<String> recent = [];

  static bool _isRelevant(String m) {
    final s = m.toLowerCase();
    return s.contains('ggml-hex') ||
        s.contains('hexagon') ||
        s.contains('htp') ||
        s.contains('cdsp') ||
        s.contains('load_tensors') ||
        s.contains('using device') ||
        s.contains('assigned to device') ||
        s.contains('offload') ||
        s.contains('backend') ||
        s.contains('device buffer') ||
        s.contains('model buffer size') ||
        s.contains('rpcmem') ||
        s.contains('error') ||
        s.contains('abort') ||
        s.contains('failed');
  }

  static void _onLog(
    int level,
    ffi.Pointer<ffi.Char> text,
    ffi.Pointer<ffi.Void> userData,
  ) {
    if (text == ffi.nullptr) return;
    totalCalls++;
    final msg = text.cast<Utf8>().toDartString().trimRight();
    debugPrint('[ggml] $msg');
    if (_isRelevant(msg)) {
      recent.add(msg);
      if (recent.length > 200) recent.removeAt(0);
    }
  }

  /// 在任何模型加载前调用一次；幂等。
  static void install() {
    rearm();
  }

  /// 重新挂回我们的回调并把级别开到 debug。
  ///
  /// llamadart 原生层在后端初始化（LlamaBackend 构造）时会调用
  /// llama_dart_set_log_level，把 ggml 回调替换成写 stderr 的版本，而这台
  /// 国产 ROM 不把第三方 stderr 收入 logcat。因此引擎对象构造完成后、加载
  /// 模型前必须再 rearm 一次，才能在 logcat 看到 ggml-hex 的逐层日志。
  static void rearm() {
    try {
      _callable ??= ffi.NativeCallable<_LogCbNative>.listener(_onLog);
      // 枚举序 none/debug/info/warn/error = 0/1/2/3/4。debug 包开到 debug
      // 抓 HTP offload 明细；release 只留 warn，避免每帧日志跨 JNI 的开销。
      // set_log_level 内部会把 llama/ggml 回调换成 stderr sink，必须在它
      // 之后再挂回自己的回调。
      llama_dart_set_log_level(kReleaseMode ? 3 : 1);
      ggml_log_set(_callable!.nativeFunction, ffi.nullptr);
      llama_log_set(_callable!.nativeFunction, ffi.nullptr);
      debugPrint('[TtsNativeLog] ggml/llama 原生日志回调已注册');
    } catch (e) {
      debugPrint('[TtsNativeLog] 注册失败（不影响功能）：$e');
    }
  }
}
