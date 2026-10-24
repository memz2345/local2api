// lib/services/lab/lab_process.dart
//
// 实验室本地服务的统一进程入口 —— 桌面直接 dart:io Process；Android 上
// 分「直连」与「Shizuku」两条通道：
//   · direct：debug 构建可以直接 exec 数据目录里的 node（untrusted_app_25
//     域不受 W^X 限制）；release 构建会被系统拒绝（EACCES）。
//   · shizuku：经 Shizuku 以 shell 身份拉起，绕开 W^X（release 必备）。
//
// 调用方只面对 [LabProcessHandle]（行流 + exitCode + kill），不感知通道。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'node_runtime_service.dart';
import 'shizuku_service.dart';
import 'windows_process_guard.dart';

class LabProcessHandle {
  LabProcessHandle({
    required this.pid,
    required Stream<String> stdout,
    required Stream<String> stderr,
    required Future<int> exitCode,
    required Future<void> Function() kill,
  })  : _killImpl = kill {
    _stdout = stdout.asBroadcastStream();
    _stderr = stderr.asBroadcastStream();
    _exitCode = exitCode;
  }

  final int pid;
  final Future<void> Function() _killImpl;

  late final Stream<String> _stdout;
  late final Stream<String> _stderr;
  late final Future<int> _exitCode;

  Stream<String> get stdout => _stdout;
  Stream<String> get stderr => _stderr;
  Future<int> get exitCode => _exitCode;

  Future<void> kill() => _killImpl();
}

/// 当前 Android 端选择的执行通道（跟随 Node 运行时的设置）。
NodeRunnerMode get _androidRunner =>
    NodeRuntimeService.instance.runnerMode;

/// 启动实验室子进程。
///
/// [runInShell] 只对桌面有意义（Windows 上走 cmd / sh）。Android 一律
/// 直接 exec（node 二进制绝对路径），shell 参数会传给 Shizuku 的 sh。
Future<LabProcessHandle> startLabProcess({
  required String executable,
  required List<String> args,
  String? workingDirectory,
  Map<String, String>? environment,
  bool runInShell = false,
}) async {
  if (!kIsWeb && Platform.isAndroid) {
    return _startOnAndroid(
      executable: executable,
      args: args,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }
  return _startDirect(
    executable: executable,
    args: args,
    workingDirectory: workingDirectory,
    environment: environment,
    runInShell: runInShell,
  );
}

Future<LabProcessHandle> _startDirect({
  required String executable,
  required List<String> args,
  String? workingDirectory,
  Map<String, String>? environment,
  bool runInShell = false,
}) async {
  final process = await Process.start(
    executable,
    args,
    workingDirectory: workingDirectory,
    environment: environment,
    runInShell: runInShell,
  );
  // Windows：挂 Job Object，应用一退全家带走（其它平台是 no-op）。
  WindowsProcessGuard.attach(process.pid);
  final completer = Completer<int>();
  unawaited(
    process.exitCode.then((code) {
      if (!completer.isCompleted) completer.complete(code);
    }),
  );
  return LabProcessHandle(
    pid: process.pid,
    stdout: process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter()),
    stderr: process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter()),
    exitCode: completer.future,
    kill: () async {
      try {
        if (Platform.isWindows) {
          await Process.run('taskkill', [
            '/PID',
            '${process.pid}',
            '/T',
            '/F',
          ], runInShell: true);
        } else {
          process.kill(ProcessSignal.sigterm);
        }
      } catch (_) {}
      // 给进程一点时间走完 exit 回调，避免 UI 状态卡在 running。
      try {
        await process.exitCode.timeout(const Duration(seconds: 3));
      } catch (_) {
        try {
          process.kill(ProcessSignal.sigkill);
        } catch (_) {}
      }
    },
  );
}

Future<LabProcessHandle> _startOnAndroid({
  required String executable,
  required List<String> args,
  String? workingDirectory,
  Map<String, String>? environment,
}) async {
  final shizuku = ShizukuService.instance;
  final useShizuku = _androidRunner == NodeRunnerMode.shizuku;
  if (useShizuku) {
    try {
      final pid = await shizuku.start(
        command: [executable, ...args],
        workingDirectory: workingDirectory,
        environment: environment,
      );
      return _handleFromShizuku(shizuku, pid);
    } catch (e) {
      // Android 11+ 的 user build 上 shell 摸不到 /sdcard/Android/data，
      // chdir 进实验室目录就是 EACCES（Java 报成 `Cannot run program ...
      // (in directory ...): error=13`）。换「不指定 cwd」再试一次：
      // npm 靠 --prefix 定位，dsh 靠绝对路径与 DSH_WORKSPACE。
      final blocked = NodeRuntimeService.instance.labCwdBlocked ||
          NodeRuntimeService.isPermissionDeniedError(e);
      if (workingDirectory == null || workingDirectory.isEmpty || !blocked) {
        rethrow;
      }
      final pid = await shizuku.start(
        command: [executable, ...args],
        environment: environment,
      );
      NodeRuntimeService.instance.noteLabCwdBlocked();
      return _handleFromShizuku(shizuku, pid);
    }
  }
  return _startDirect(
    executable: executable,
    args: args,
    workingDirectory: workingDirectory,
    environment: environment,
  );
}

LabProcessHandle _handleFromShizuku(ShizukuService shizuku, int pid) {
  final outController = StreamController<String>.broadcast();
  final errController = StreamController<String>.broadcast();
  final completer = Completer<int>();
  final sub = shizuku.events(pid).listen(
    (event) {
      if (event.isExit) {
        if (!completer.isCompleted) completer.complete(event.exitCode ?? 0);
        unawaited(outController.close());
        unawaited(errController.close());
      } else if (event.isError) {
        errController.add(event.line ?? '');
      } else {
        outController.add(event.line ?? '');
      }
    },
    onDone: () {
      if (!completer.isCompleted) completer.complete(-1);
      unawaited(outController.close());
      unawaited(errController.close());
    },
    onError: (Object e) {
      if (!completer.isCompleted) completer.complete(-1);
      unawaited(outController.close());
      unawaited(errController.close());
    },
  );
  return LabProcessHandle(
    pid: pid,
    stdout: outController.stream,
    stderr: errController.stream,
    exitCode: completer.future,
    kill: () async {
      await sub.cancel();
      await shizuku.kill(pid);
    },
  );
}

/// 结束一个已知的实验室进程（不持有 handle 时用，比如跨页面 stop）。
Future<void> killLabProcess(
  int pid, {
  NodeRunnerMode? runnerMode,
}) async {
  if (!kIsWeb && Platform.isAndroid) {
    if ((runnerMode ?? _androidRunner) == NodeRunnerMode.shizuku) {
      await ShizukuService.instance.kill(pid);
      return;
    }
  }
  if (!kIsWeb && Platform.isWindows) {
    try {
      await Process.run('taskkill', [
        '/PID',
        '$pid',
        '/T',
        '/F',
      ], runInShell: true);
      return;
    } catch (_) {}
  }
  // posix 直连：给不了 Process 对象，只能靠 pid 信号（POSIX kill 命令）。
  if (!kIsWeb && (Platform.isLinux || Platform.isMacOS)) {
    try {
      await Process.run('kill', ['$pid'], runInShell: false);
    } catch (_) {}
  }
}
