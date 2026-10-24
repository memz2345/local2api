// TTS 模型下载的**全局后台任务**（单例 ChangeNotifier）。
//
// 自 NaviFlash lib/services/tts_download_service.dart 移植，去掉那边特有的
// Android 原生前台下载（ModelDownloadService）、系统通知（TtsLiveUpdate /
// NotificationService）。下载全程跑在 Dart 侧：
//   · 单例 → 离开设置页 / 切页，下载都不断；
//   · 进度是全局可订阅状态，任何页面回来都能立即显示当前进度；
//   · 底层是带断点续传的 [TtsModelService.install]：`.part` 留着，下次接着下；
//   · 应用被杀时 in-flight 标记还在 → 下次启动自动续传（主动取消 /
//     明确失败会清掉这个标记，不会阴魂不散）。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tts_model_service.dart';

class TtsDownloadService extends ChangeNotifier {
  TtsDownloadService._();

  static final TtsDownloadService instance = TtsDownloadService._();

  /// 上次是否处于「下载中」状态（进程被杀才会留在 true）。
  static const String _prefInFlight = 'ttsDownloadInFlight';

  bool _running = false;
  bool _cancelRequested = false;
  int _received = 0;
  int _total = 0;
  String _currentFile = '';
  String? _error;
  bool _justFinished = false;

  bool get isRunning => _running;

  /// 上一轮是否刚成功完成（UI 用来弹一次提示）。
  bool get justFinished => _justFinished;

  int get received => _received;
  int get total => _total;

  /// 当前正在下的文件名（空 = 还没开始）。
  String get currentFile => _currentFile;

  /// 上一次失败的原因（成功 / 取消后为 null）。
  String? get error => _error;

  /// 0..1；总大小未知时 null。
  double? get progress =>
      _total > 0 ? (_received / _total).clamp(0.0, 1.0) : null;

  /// 启动时调用：
  ///   · 上次是「下载中被杀」→ 自动接着下（断点已经在磁盘上）；
  ///   · 否则顺手扫一遍没用的零碎 `.part`（真断点会留着）。
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final inFlight = prefs.getBool(_prefInFlight) == true;
      if (inFlight && await TtsModelService.state() != TtsModelState.installed) {
        debugPrint('[TtsDownload] 检测到上次下载被中断，自动续传');
        unawaited(start());
        return;
      }
      if (inFlight) await prefs.setBool(_prefInFlight, false);
      // 没有要续的：清掉没用的零碎文件
      unawaited(TtsModelService.cleanupOrphans().then((freed) {
        if (freed > 0) {
          debugPrint(
            '[TtsDownload] 启动清理无用断点 ${(freed / 1024 / 1024).round()}MB',
          );
        }
      }));
    } catch (e) {
      debugPrint('[TtsDownload] 初始化失败: $e');
    }
  }

  /// 开始 / 继续下载。已在跑时直接返回（幂等）。
  Future<void> start() async {
    if (_running) return;
    if (await TtsModelService.state() == TtsModelState.installed) return;

    _running = true;
    _cancelRequested = false;
    _error = null;
    _justFinished = false;
    await _setInFlight(true);
    notifyListeners();

    try {
      await TtsModelService.install(
        onProgress: (received, total, name) {
          _received = received;
          _total = total;
          _currentFile = name;
          notifyListeners();
        },
        shouldCancel: () => _cancelRequested,
      );
      _justFinished = true;
      _received = _total;
      await _setInFlight(false);
    } on TtsModelCancelled {
      // 用户主动停：断点保留，但不再自动续
      await _setInFlight(false);
    } on TtsModelException catch (e) {
      _error = e.message;
      await _setInFlight(false);
    } catch (e) {
      _error = '$e';
      await _setInFlight(false);
    } finally {
      _running = false;
      _cancelRequested = false;
      notifyListeners();
    }
  }

  /// 请求停止（下一个数据块生效）。已下好的部分保留为断点，下次接着下。
  void cancel() {
    if (!_running || _cancelRequested) return;
    _cancelRequested = true;
    notifyListeners();
  }

  Future<void> _setInFlight(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefInFlight, value);
    } catch (_) {}
  }
}
