// 长按说话的一次录音会话：状态机与识别结果拼装，渲染层（Material /
// miuix 两版弹层）共用。
//
// 为什么单独一层：录音交互的时间细节很容易写岔，写两份必歪。这里收敛成
// 一个 Listenable：
// - begin()：按下了。申请权限 + 起引擎收音（长静音兜底 60s —— 用户按多久
//   由松手决定，不能让 pauseFor 计时器半路掐死；Windows SAPI 没有增量
//   事件，引擎自己的断句出 final，见 SpeechInputService 类注释）。
// - finish()：松手了。停引擎并等一拍「最后的定稿」（安卓引擎 stop 后会把
//   最后的增量转成 final 推回来；Windows 这时通常已经有 final 了），
//   拿到文本返回，拿不到返回 null（调用方给「没听清」提示）。
// - abort()：弹层被关掉 / 页面销毁，直接取消收音。
//
// 文本拼装规则：一条会话里的多个定稿用空格拼接（用户按住不放连说两段）；
// 增量只用于界面预览，不进结果。
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'local_asr_service.dart';
import 'speech_input_service.dart';

/// 会话状态。
enum VoiceRecordPhase {
  /// 还没按下（弹层刚开，提示「按住说话」）。
  idle,

  /// 按住收音中。
  holding,

  /// 已松手，等引擎推最后一版定稿。
  finishing,

  /// 出错（[errorMessage] 有原因）。
  error,
}

class VoiceRecordSession extends ChangeNotifier {
  VoiceRecordSession({this.localeTag});

  /// 识别语言（如 'zh_CN'）；null = 引擎默认。
  final String? localeTag;

  final SpeechInputService _speech = SpeechInputService();

  VoiceRecordPhase _phase = VoiceRecordPhase.idle;
  String? _errorMessage;

  /// 定稿片段（按住期间可能出多段，空格拼接）。
  final List<String> _finalParts = [];

  /// 最后一版增量（预览用，不进结果）。
  String _partialTail = '';

  /// 会话号：finish 的等待回调全部对号，abort / 重新 begin 作废旧的。
  int _epoch = 0;

  /// finish 的「新定稿到了」通知（松手后的宽限等待用）。
  Completer<void>? _finishWaiter;

  /// finish 的宽限计时器（abort 时要取消，别把 pending timer 泄给测试）。
  Timer? _graceTimer;

  VoiceRecordPhase get phase => _phase;

  String? get errorMessage => _errorMessage;

  /// 界面展示的实时文本：定稿 + 当前增量。
  String get liveText {
    final base = _finalParts.join(' ').trimRight();
    final tail = _partialTail.trim();
    if (base.isEmpty) return tail;
    if (tail.isEmpty) return base;
    return '$base $tail';
  }

  /// 已经拿到的定稿（finish 的兜底返回值）。
  String get confirmedText => _finalParts.join(' ').trim();

  /// 按下：开始收音。返回是否真的开起来了（false = 权限/服务不可用，
  /// [speechReady] 与 [errorMessage] 给原因）。
  Future<SpeechReady> begin() async {
    // 上一轮 finish 的宽限等待作废（别让它的计时器漏成 pending）。
    _cancelFinishWaiter();
    final epoch = ++_epoch;
    _finalParts.clear();
    _partialTail = '';
    _errorMessage = null;
    _phase = VoiceRecordPhase.holding;
    notifyListeners();

    final ready = await _speech.ensureReady();
    if (epoch != _epoch) return SpeechReady.busy;
    if (ready != SpeechReady.available) {
      // 渲染层按哨兵值挑文案：no-permission / preparing / unavailable。
      // preparing = 本地离线模型的首次下载还在跑（ROM 的系统识别服务不可
      // 用、正自动兜底），跟「设备不支持」是两回事，别吓用户。
      if (ready == SpeechReady.noPermission) {
        _errorMessage = 'no-permission';
      } else if (ready == SpeechReady.unavailable) {
        _errorMessage =
            LocalAsrService.instance.isDownloading ? 'preparing' : 'unavailable';
      }
      _phase = VoiceRecordPhase.error;
      notifyListeners();
      return ready;
    }
    final localeId = localeTag;
    try {
      await _speech.start(
        localeId: localeId,
        // 按多久由松手决定；引擎断句出的 final 照常实时回传。
        pauseFor: const Duration(seconds: 60),
        onResult: (text, isFinal) {
          if (epoch != _epoch) return;
          if (isFinal) {
            if (text.trim().isNotEmpty) _finalParts.add(text.trim());
            _partialTail = '';
            // finish 正在宽限等待：有新定稿就提前收工。
            _completeFinishWaiter();
          } else {
            _partialTail = text;
          }
          notifyListeners();
        },
        onError: (message) {
          if (epoch != _epoch) return;
          _errorMessage = message;
          _phase = VoiceRecordPhase.error;
          notifyListeners();
        },
      );
    } on Object catch (e) {
      if (epoch != _epoch) return SpeechReady.available;
      _errorMessage = '$e';
      _phase = VoiceRecordPhase.error;
      notifyListeners();
      return SpeechReady.unavailable;
    }
    if (epoch != _epoch) return SpeechReady.busy;
    return SpeechReady.available;
  }

  /// 松手：停收音并等「最后一版定稿」。
  ///
  /// 等待规则（事件驱动，**不用真实 Stopwatch 轮询** —— 那会在测试的
  /// FakeAsync 里跟 fake 定时器互相等死）：
  /// - 已经有定稿（引擎在按住期间就断句了）：再短等 [extra] 一拍（用户
  ///   松手前可能又说了一段、final 还在路上），有新定稿立刻收；
  /// - 还没有任何定稿：等满 [grace] —— 安卓引擎 stop 后会把最后的增量
  ///   转成 final 推回来（约 2s），Windows SAPI 则是「松得太快、引擎还没
  ///   断句」，等不到就只能放弃。
  ///
  /// 注意**不推进 [ _epoch]**：宽限期间要继续收老会话的定稿回调；
  /// abort / 新一轮 begin 推进 epoch 时，这里的等待会被叫醒并作废。
  ///
  /// 返回识别文本，什么都没听到返回 null。
  Future<String?> finish({
    Duration grace = const Duration(milliseconds: 2600),
    Duration extra = const Duration(milliseconds: 700),
  }) {
    _cancelFinishWaiter();
    final epoch = _epoch;
    _phase = VoiceRecordPhase.finishing;
    notifyListeners();
    final partsAtStart = _finalParts.length;
    final wait = _finalParts.isEmpty ? grace : extra;
    return _speech.stop().then<String?>((_) async {
      if (epoch != _epoch) return _resultOrNull();
      if (_finalParts.length > partsAtStart) {
        _settleIdle();
        return _resultOrNull();
      }
      final gotMore = Completer<void>();
      _finishWaiter = gotMore;
      _graceTimer = Timer(wait, _completeFinishWaiter);
      await gotMore.future;
      _graceTimer?.cancel();
      _graceTimer = null;
      _finishWaiter = null;
      if (epoch != _epoch) return _resultOrNull();
      _settleIdle();
      return _resultOrNull();
    });
  }

  void _completeFinishWaiter() {
    final w = _finishWaiter;
    if (w != null && !w.isCompleted) w.complete();
  }

  void _cancelFinishWaiter() {
    _graceTimer?.cancel();
    _graceTimer = null;
    _completeFinishWaiter();
    _finishWaiter = null;
  }

  void _settleIdle() {
    _phase = VoiceRecordPhase.idle;
    notifyListeners();
  }

  String? _resultOrNull() {
    final t = confirmedText;
    return t.isEmpty ? null : t;
  }

  /// 弹层被关掉：作废一切在途回调并取消收音。
  Future<void> abort() async {
    _epoch++;
    _cancelFinishWaiter();
    _phase = VoiceRecordPhase.idle;
    await _speech.cancel();
  }

  /// 打开系统设置（权限被永久拒时给用户的出口）。
  Future<void> openSettings() => _speech.openSettings();
}
