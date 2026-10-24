// lib/services/lab/shizuku_service.dart
//
// Shizuku 平台桥（Android 专用，其它平台是空实现）。
//
// Shizuku（https://shizuku.rikka.app/）让应用借 shell 身份执行操作。
// 对实验室的意义：targetSdk 29+ 禁止应用直接 exec 数据目录里的二进制
// （W^X），release 构建上 node 必须经 Shizuku 以 shell 域拉起。
//
// 协议（与 ShizukuHost.kt 对应）：
//   MethodChannel  com.memz2345.local2api/shizuku
//     ping()               -> bool（binder 在且 API >= 11）
//     permission()         -> bool（已授权？）
//     requestPermission()  -> bool（弹授权框并等待结果）
//     start {cmd, env, cwd}-> int pid
//     kill {pid}           -> void
//   EventChannel   com.memz2345.local2api/shizuku/proc/<pid>
//     {'stream':'out'|'err', 'line': String}
//     {'event':'exit', 'code': int}

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// 一条来自 Shizuku 子进程的事件（输出行 / 退出）。
@immutable
class ShizukuProcEvent {
  const ShizukuProcEvent.out(this.line)
      : isExit = false,
        isError = false,
        exitCode = null;
  const ShizukuProcEvent.err(this.line)
      : isExit = false,
        isError = true,
        exitCode = null;
  const ShizukuProcEvent.exit(this.exitCode)
      : isExit = true,
        isError = false,
        line = null;

  final String? line;
  final bool isExit;
  final bool isError;
  final int? exitCode;
}

class ShizukuService {
  ShizukuService._();

  static final ShizukuService instance = ShizukuService._();

  static const MethodChannel _channel = MethodChannel(
    'com.memz2345.local2api/shizuku',
  );

  /// 原生侧权限请求结果回推（invokeMethod('permissionResult', granted)）。
  final StreamController<bool> _permissionResults = StreamController<bool>()
    ..add(false);

  final Map<int, StreamController<ShizukuProcEvent>> _procs = {};
  final Map<int, StreamSubscription<dynamic>> _subs = {};
  bool _handlerInstalled = false;

  bool get isAndroid =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android;

  void _installHandler() {
    if (_handlerInstalled || !isAndroid) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'permissionResult') {
        final granted = call.arguments == true;
        _permissionResults.add(granted);
      }
      return null;
    });
  }

  /// Shizuku binder 是否可用（装了 Shizuku 且在运行）。
  Future<bool> ping() async {
    if (!isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('ping') ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 是否已授权。
  Future<bool> isGranted() async {
    if (!isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('permission') ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 拉起 Shizuku 的授权框并等待结果。
  ///
  /// 原生会经 invokeMethod('permissionResult') 回推授权结果；个别机型上
  /// 回推会丢（授权框由 Shizuku 管理器进程关闭），所以再用轮询兜底。
  Future<bool> requestPermission() async {
    if (!isAndroid) return false;
    _installHandler();
    var viaCallback = false;
    final wait = _permissionResults.stream
        .firstWhere((v) => v, orElse: () => false)
        .then((v) {
      viaCallback = true;
      return v;
    }).timeout(const Duration(seconds: 30), onTimeout: () => false);
    try {
      final granted =
          await _channel.invokeMethod<bool>('requestPermission') ?? false;
      if (granted) return true;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
    // 轮询兜底：最多 15s，每 750ms 查一次。
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 750));
      if (await isGranted()) return true;
      if (viaCallback) break;
    }
    return await wait;
  }

  /// 以 shell 身份启动一个进程，返回 pid；失败抛异常（调用方决定兜底）。
  Future<int> start({
    required List<String> command,
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (!isAndroid) {
      throw StateError('Shizuku 只在 Android 上可用');
    }
    _installHandler();
    final pid = await _channel.invokeMethod<int>('start', {
      'cmd': command,
      'env': environment ?? const <String, String>{},
      'cwd': workingDirectory ?? '',
    });
    if (pid == null) {
      throw StateError('Shizuku start 未返回进程句柄');
    }
    return pid;
  }

  /// 订阅某个 pid 的输出 / 退出事件（重复订阅同一 pid 返回同一流）。
  Stream<ShizukuProcEvent> events(int pid) {
    _installHandler();
    return (_procs[pid] ??= _openProcStream(pid)).stream;
  }

  StreamController<ShizukuProcEvent> _openProcStream(int pid) {
    final controller = StreamController<ShizukuProcEvent>.broadcast();
    final stream = EventChannel('com.memz2345.local2api/shizuku/proc/$pid');
    late StreamSubscription<dynamic> sub;
    var closed = false;
    void maybeClose() {
      if (closed) return;
      closed = true;
      unawaited(sub.cancel());
      _procs.remove(pid);
      _subs.remove(pid);
    }

    controller.onListen = () {};
    controller.onCancel = () {};
    sub = stream.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          if (event['event'] == 'exit') {
            controller.add(ShizukuProcEvent.exit(event['code'] as int? ?? 0));
            maybeClose();
          } else if (event['line'] is String) {
            controller.add(
              (event['stream'] == 'err')
                  ? ShizukuProcEvent.err(event['line'] as String)
                  : ShizukuProcEvent.out(event['line'] as String),
            );
          }
        }
      },
      onError: (Object e) {
        controller.add(ShizukuProcEvent.exit(-1));
        maybeClose();
      },
      onDone: maybeClose,
    );
    _subs[pid] = sub;
    return controller;
  }

  Future<void> kill(int pid) async {
    if (!isAndroid) return;
    try {
      await _channel
          .invokeMethod<void>('kill', {'pid': pid})
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // kill 只是兜底清理，失败不能拖死调用方。
    }
    _procs.remove(pid)?.close();
    await _subs.remove(pid)?.cancel();
  }
}
