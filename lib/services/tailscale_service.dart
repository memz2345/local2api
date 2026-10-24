// lib/services/tailscale_service.dart
//
// Tailscale 的「装没装 / 打不打得开」。
//
// 原来网络页那张卡片永远只是打开下载页 —— 机器上早就装好了也一样。
// 这里补上探测：桌面端按平台找可执行文件（PATH → 常见安装目录），
// Android 走 `tailscale://` 的 scheme 探测（原生侧没有现成通道，加一条
// MethodChannel 不划算，scheme 命中不了就当没装）。
//
// `open()` 只负责把客户端拉起来（桌面端起 GUI，Android 走 scheme），
// 拉不起来就回退下载页 —— 返回 false 让 UI 决定要不要提示。

import 'dart:io' show Directory, File, Platform, Process;

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class TailscaleService {
  TailscaleService._();

  static final TailscaleService instance = TailscaleService._();

  /// 测试注入口：钉住探测结果，省得真去 fork 进程。
  static Future<bool> Function()? detectOverride;

  /// 下载页：探测不到 / 拉不起来时的兜底。
  static final Uri _downloadUri = Uri.parse('https://tailscale.com/download');

  /// Android 客户端的 scheme。
  static final Uri _androidUri = Uri.parse('tailscale://');

  /// 这台机器上装了 Tailscale 没有。
  Future<bool> isInstalled() async {
    final override = detectOverride;
    if (override != null) return override();
    if (kIsWeb) return false;
    if (Platform.isAndroid) {
      try {
        return await canLaunchUrl(_androidUri);
      } catch (_) {
        return false;
      }
    }
    return (await _desktopLaunchPlan()) != null;
  }

  /// 打开 Tailscale：桌面端起它的 GUI，Android 走 scheme。
  ///
  /// 返回 false = 没打开（已回退到下载页，或连下载页都拉不起来）。
  Future<bool> open() async {
    if (kIsWeb) return _openDownload();
    if (Platform.isAndroid) {
      try {
        if (await launchUrl(_androidUri)) return true;
      } catch (_) {}
      return _openDownload();
    }
    final plan = await _desktopLaunchPlan();
    if (plan == null) return _openDownload();
    final (:executable, :arguments) = plan;
    try {
      await Process.start(
        executable,
        arguments,
        runInShell: Platform.isWindows,
      );
      return true;
    } catch (_) {
      return _openDownload();
    }
  }

  Future<bool> _openDownload() async {
    try {
      return await launchUrl(
        _downloadUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  /// 桌面端怎么把客户端拉起来：找到可执行文件就给 (exe, args)，没有给 null。
  Future<({String executable, List<String> arguments})?>
  _desktopLaunchPlan() async {
    if (Platform.isWindows) {
      // PATH 上优先（命令行版 / 自定义安装）。
      final fromPath =
          await _which('tailscale-ipn.exe') ?? await _which('tailscale.exe');
      if (fromPath != null) {
        return (executable: fromPath, arguments: const <String>[]);
      }
      for (final dir in _windowsDirs) {
        final candidate = '$dir\\tailscale-ipn.exe';
        if (File(candidate).existsSync()) {
          return (executable: candidate, arguments: const <String>[]);
        }
      }
      return null;
    }
    if (Platform.isMacOS) {
      if (Directory('/Applications/Tailscale.app').existsSync()) {
        return (executable: 'open', arguments: const ['-a', 'Tailscale']);
      }
      final fromPath = await _which('tailscale');
      if (fromPath != null) {
        return (executable: fromPath, arguments: const ['up']);
      }
      return null;
    }
    // Linux：有 GUI 就起 GUI（跟 Windows 一样只负责把窗口打开），
    // 只有命令行版时给它 `up`（会弹登录链接）。
    final gui = await _which('tailscale-gui');
    if (gui != null) return (executable: gui, arguments: const <String>[]);
    final fromPath = await _which('tailscale');
    if (fromPath != null) {
      return (executable: fromPath, arguments: const ['up']);
    }
    return null;
  }

  /// Windows 的常见安装目录（32 位程序装在 Program Files (x86)）。
  static List<String> get _windowsDirs => [
    'C:\\Program Files\\Tailscale',
    'C:\\Program Files (x86)\\Tailscale',
  ];

  /// PATH 查找：Windows 用 `where`，其余用 `which`。
  Future<String?> _which(String name) async {
    try {
      final result = Platform.isWindows
          ? await Process.run('where', [name])
          : await Process.run('which', [name]);
      if (result.exitCode != 0) return null;
      final line = (result.stdout as String)
          .trim()
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      return line.isEmpty ? null : line.first;
    } catch (_) {
      return null;
    }
  }
}
