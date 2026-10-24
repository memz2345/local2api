// lib/services/lab/windows_process_guard.dart
//
// Windows 进程护栏：把实验室拉起的子进程（node / npm 经 shell）挂进一个
// Job Object（JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE）。
//
// 为什么需要：Dart 的 Process.start 不会建立父子生死绑定 —— 应用无论怎么
// 退（正常退出 / 任务管理器杀 / 崩溃），Node 服务都会变成孤儿继续活着。
// Job Object 的语义正合适：Job 句柄由本进程持有，本进程一死句柄全关，
// 系统按 KILL_ON_JOB_CLOSE 把作业里的所有进程（含 node 再生的子进程，
// 作业成员自动继承）一起带走。
//
// 纯 dart:ffi 调 kernel32，不引插件；失败一律吞掉 —— 护栏挂了不能影响
// 服务本身启动，最多退化成老行为（应用正常退出时 stop() 兜底）。

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart' show Utf16, calloc;

class WindowsProcessGuard {
  WindowsProcessGuard._();

  static const int _killOnJobClose = 0x00002000;

  /// JobObjectExtendedLimitInformation，LimitsFlags 在结构体偏移 16
  /// （两个 LARGE_INTEGER 之后）。
  static const int _jobObjectExtendedLimitInformation = 9;
  static const int _extendedLimitInfoSize = 144;

  static Pointer<Void>? _job;

  /// 把 [pid] 挂进进程作业。只在 Windows 生效，其它平台直接返回。
  static void attach(int pid) {
    if (!Platform.isWindows) return;
    try {
      final job = _ensureJob();
      if (job == null) return;
      final k32 = DynamicLibrary.open('kernel32.dll');
      final openProcess = k32.lookupFunction<
          Pointer<Void> Function(Uint32, Int32, Uint32),
          Pointer<Void> Function(int, int, int)>('OpenProcess');
      final assign = k32.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Void>),
          int Function(Pointer<Void>, Pointer<Void>)>(
        'AssignProcessToJobObject',
      );
      final closeHandle = k32.lookupFunction<
          Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)>('CloseHandle');
      // PROCESS_SET_QUOTA(0x0100) | PROCESS_TERMINATE(0x0001)
      final process = openProcess(0x0101, 0, pid);
      if (process == nullptr) return;
      try {
        assign(job, process);
      } finally {
        closeHandle(process);
      }
    } catch (_) {
      // 没挂上就算了：正常退出路径还有 stop() 兜底。
    }
  }

  /// 惰性创建全进程共用的 Job（npm install / node 服务都挂同一个）。
  static Pointer<Void>? _ensureJob() {
    final cached = _job;
    if (cached != null) return cached;
    final k32 = DynamicLibrary.open('kernel32.dll');
    final createJob = k32.lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf16>),
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf16>)>(
      'CreateJobObjectW',
    );
    final setInfo = k32.lookupFunction<
        Int32 Function(Pointer<Void>, Int32, Pointer<Uint8>, Uint32),
        int Function(Pointer<Void>, int, Pointer<Uint8>, int)>(
      'SetInformationJobObject',
    );
    final job = createJob(nullptr, nullptr);
    if (job == nullptr) return null;
    final info = calloc<Uint8>(_extendedLimitInfoSize);
    try {
      // calloc 已清零，只需写 LimitFlags = KILL_ON_JOB_CLOSE。
      info.asTypedList(_extendedLimitInfoSize)[16] = _killOnJobClose & 0xff;
      info.asTypedList(_extendedLimitInfoSize)[17] =
          (_killOnJobClose >> 8) & 0xff;
      final ok = setInfo(
        job,
        _jobObjectExtendedLimitInformation,
        info,
        _extendedLimitInfoSize,
      );
      if (ok == 0) return null;
    } finally {
      calloc.free(info);
    }
    _job = job;
    return job;
  }
}
