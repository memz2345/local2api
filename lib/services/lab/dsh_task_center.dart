// lib/services/lab/dsh_task_center.dart
//
// 实验室任务的「通知前台」：把一个任务的执行过程映射到 Android 16 的
// 「以进度为中心的通知」上（分段 = 步骤、里程碑点 = 步骤起点），并在模型
// 需要人做决定时把通知切成带输入框的形态（用户直接在通知里打字回复）。
//
// 只管通知，不管进程：谁在跑任务谁调用这里（`dsh_task_runner.dart` 是其中
// 一个调用方）。非 Android 平台全部退化成内存里的状态（UI 照样能读）。

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../android_notifications.dart';
import 'dsh_question.dart';
import 'dsh_web_answer_bridge.dart';
import 'dsh_web_rpc.dart';
import 'dsh_windows_toast.dart';

/// 一个步骤的状态。
enum DshTaskStepState { pending, active, done, failed }

/// 任务里的一个步骤（对应通知进度条上的一个分段）。
class DshTaskStep {
  DshTaskStep(this.label, {this.weight = 1});

  final String label;

  /// 相对长度（通知上就是这一段的像素占比）。
  final int weight;

  DshTaskStepState state = DshTaskStepState.pending;

  int get color => switch (state) {
    DshTaskStepState.pending => AndroidProgressColors.pending,
    DshTaskStepState.active => AndroidProgressColors.active,
    DshTaskStepState.done => AndroidProgressColors.done,
    DshTaskStepState.failed => AndroidProgressColors.failed,
  };
}

/// 任务的终态。
enum DshTaskOutcome { running, succeeded, failed, cancelled }

/// 把任务状态投到 Android 通知上的管家（单例）。
class DshTaskCenter extends ChangeNotifier {
  DshTaskCenter._();

  static final DshTaskCenter instance = DshTaskCenter._();

  /// 任务通知固定用这个 id：反复更新同一条，不叠通知。
  static const int taskNotificationId = 7200;

  /// Windows 的进度 Toast 用同一组 tag+group 原地替换。
  static const String windowsGroup = 'dsh';
  static const String windowsTaskTag = 'dsh-task';
  static const String windowsQuestionTag = 'dsh-question';

  final List<DshTaskStep> _steps = <DshTaskStep>[];
  String _title = '';
  String _subtitle = '';
  String _status = '';
  String? _question;
  int _activeIndex = -1;
  bool _indeterminate = false;
  DshTaskOutcome _outcome = DshTaskOutcome.running;
  String? _lastError;
  int _resultNotificationId = taskNotificationId + 1;

  Completer<String?>? _replyCompleter;
  String? _replyLabel;
  String? _cancelLabel;
  String? _openLabel;
  String _inputPlaceholder = '';
  String _optionsHint = '';
  String _answerHint = '';
  String Function(int done, int total)? _stepsLabel;
  String? _askTag;
  List<String> _askOptions = const <String>[];
  int _windowsResultSeq = 0;
  int _windowsTaskSeq = 0;
  String _windowsTaskTag = windowsTaskTag;
  String _lastWindowsSignature = '';
  bool _attached = false;

  /// 用户把某条 web 提问的通知划掉/取消后，不要每 1.2 秒轮询又弹回来。
  String? _dismissedQuestionCallId;

  /// 测试/日志用：真正会响铃或弹横幅的次数（静默进度更新不算）。
  int debugAlertCount = 0;

  /// 测试用：模拟用户在通知输入框里敲了 [text] 并提交。
  @visibleForTesting
  bool debugSubmitReply(String text) {
    if (_replyCompleter == null) return false;
    _finishWindowsAsk(text);
    return true;
  }

  /// UI 层注入的「打开 dsh web」动作（web 会话的提问只能回浏览器答）。
  void Function()? onOpenWeb;

  // ---- 只读状态 ----

  bool get supported =>
      AndroidNotifications.isSupported || DshWindowsToast.isSupported;
  bool get isWindows => DshWindowsToast.isSupported;
  bool get hasTask => _outcome == DshTaskOutcome.running && _title.isNotEmpty;
  bool get waitingForReply => _replyCompleter != null;
  String get title => _title;
  String get subtitle => _subtitle;
  String get status => _status;
  String? get question => _question;
  List<DshTaskStep> get steps => List.unmodifiable(_steps);
  DshTaskOutcome get outcome => _outcome;
  String? get lastError => _lastError;

  /// 已完成 / 总步骤数（给 UI 显示「2/4」）。
  int get doneCount =>
      _steps.where((s) => s.state == DshTaskStepState.done).length;
  int get stepCount => _steps.length;

  // ---- 生命周期 ----

  /// 挂上通知事件回调。重复调用安全。
  ///
  /// [stepsLabel] / [optionsHint] / [inputPlaceholder] 由页面按当前语言注入；
  /// Android 只用到 reply/cancel，Windows 还会用到后面几个。
  Future<void> attach({
    String? replyLabel,
    String? cancelLabel,
    String? openLabel,
    String? inputPlaceholder,
    String? optionsHint,
    String? answerHint,
    String? agentDoneLabel,
    String Function(int done, int total)? stepsLabel,
  }) async {
    if (replyLabel != null) _replyLabel = replyLabel;
    if (cancelLabel != null) _cancelLabel = cancelLabel;
    if (openLabel != null) _openLabel = openLabel;
    if (inputPlaceholder != null) _inputPlaceholder = inputPlaceholder;
    if (optionsHint != null) _optionsHint = optionsHint;
    if (answerHint != null) _answerHint = answerHint;
    if (stepsLabel != null) _stepsLabel = stepsLabel;

    if (DshWindowsToast.isSupported) {
      await DshWindowsToast.instance.init();
      DshWindowsToast.instance.onEvent = _onWindowsToastEvent;
      _attached = true;
      return;
    }
    if (_attached) return;
    _attached = true;
    await AndroidNotifications.attach(_onEvent);
  }

  void _onEvent(AndroidNotificationEvent event) {
    if (event.id != taskNotificationId) return;
    final completer = _replyCompleter;
    if (event.isReply && completer != null && !completer.isCompleted) {
      final text = event.text?.trim() ?? '';
      _replyCompleter = null;
      _question = null;
      completer.complete(text.isEmpty ? null : text);
      notifyListeners();
      return;
    }
    if (event.key == 'cancel' && !_isFinished) {
      _outcome = DshTaskOutcome.cancelled;
      _replyCompleter?.complete(null);
      _replyCompleter = null;
      _question = null;
      unawaited(AndroidNotifications.cancel(taskNotificationId));
      notifyListeners();
    }
  }

  /// Windows Toast 的按钮 / 输入框 / 关闭事件。
  ///
  /// 只处理当前这一轮提问（tag 必须对得上）；进度通知的按钮点击不改变
  /// 任务状态。
  void _onWindowsToastEvent(DshWindowsToastEvent event) {
    if (event.key == 'open') {
      onOpenWeb?.call();
      return;
    }
    final askTag = _askTag;
    final completer = _replyCompleter;
    if (askTag == null || event.tag != askTag) return;
    if (completer == null || completer.isCompleted) return;

    if (event.isDismissed) {
      // 横幅超时只是淡出，通知还在操作中心里，不能当成取消。
      if (event.reason == 'timeout' || event.reason == 'app') return;
      _finishWindowsAsk(null);
      return;
    }
    if (event.key == 'skip') {
      _finishWindowsAsk(null);
      return;
    }
    String? reply;
    final text = event.text?.trim() ?? '';
    if (text.isNotEmpty) {
      reply = resolveOptionReply(text, _askOptions);
    } else if (event.key == 'option' && event.value != null) {
      reply = resolveOptionReply(event.value!, _askOptions);
    } else if (event.isReply) {
      reply = text;
    }
    if (reply == null) return;
    _finishWindowsAsk(reply);
  }

  /// 原生 Toast 的按钮动作（进程不在时经单实例转发回来的那条路）。
  ///
  /// 这条路上拿不到输入框文字，只能处理选项 / 跳过；自由文本回答依赖
  /// ToastNotification.Activated 的进程内回调（见 dsh_toast.cpp）。
  void handleToastAction({
    required String tag,
    required String key,
    String? value,
  }) {
    if (tag == windowsQuestionTag && key == 'open') {
      onOpenWeb?.call();
      return;
    }
    if (tag != _askTag || _replyCompleter == null) {
      if (key == 'open') onOpenWeb?.call();
      return;
    }
    if (key == 'skip') {
      _finishWindowsAsk(null);
      return;
    }
    if (key == 'option' && value != null) {
      final reply = resolveOptionReply(value, _askOptions);
      if (reply != null) _finishWindowsAsk(reply);
    }
  }

  void _finishWindowsAsk(String? reply) {
    final completer = _replyCompleter;
    final tag = _askTag;
    _replyCompleter = null;
    _askTag = null;
    _askOptions = const <String>[];
    _question = null;
    if (tag != null) {
      unawaited(DshWindowsToast.instance.cancel(tag: tag));
    }
    if (completer != null && !completer.isCompleted) {
      completer.complete(reply);
    }
    notifyListeners();
  }

  bool get _isFinished =>
      _outcome == DshTaskOutcome.succeeded ||
      _outcome == DshTaskOutcome.failed ||
      _outcome == DshTaskOutcome.cancelled;

  // ---- 任务过程 ----

  /// 开一个任务：先发一条常驻的进度通知。
  ///
  /// [steps] 是先规划好的步骤；没有就只发一条「不确定进度」的通知，之后
  /// 用 [setSteps] 补上（模型自己拆步骤的场景）。
  Future<NotificationPostResult> start({
    required String title,
    String subtitle = '',
    String status = '',
    List<String> steps = const <String>[],
    bool indeterminate = false,
  }) async {
    // web 会话的 watcher 每个事件（一次工具调用 / 一次思考）都会调
    // start()：已经有一个同名任务在跑时，这只是「刷新状态」，不能再当成
    // 新任务弹一次横幅（否则模型每调一次工具就弹一条 Toast）。真正的
    // 新任务（上一次已结束）仍然会 alert。
    final alreadyRunning =
        _outcome == DshTaskOutcome.running && _title.isNotEmpty;
    _title = title;
    _subtitle = subtitle;
    _status = status;
    _question = null;
    _lastError = null;
    _outcome = DshTaskOutcome.running;
    _indeterminate = steps.isEmpty || indeterminate;
    _steps
      ..clear()
      ..addAll([for (final label in steps) DshTaskStep(label)]);
    _activeIndex = _steps.isEmpty ? -1 : 0;
    if (_activeIndex >= 0) _steps[_activeIndex].state = DshTaskStepState.active;
    if (!alreadyRunning) {
      final oldTag = _windowsTaskTag;
      _lastWindowsSignature = '';
      _windowsTaskSeq++;
      _windowsTaskTag = 'dsh-task-$_windowsTaskSeq';
      if (oldTag != _windowsTaskTag) {
        unawaited(DshWindowsToast.instance.cancel(tag: oldTag));
      }
    }
    notifyListeners();
    return _publish(
      promoted: true,
      windowsAlert: !alreadyRunning,
      silent: alreadyRunning,
    );
  }

  /// 用一份「计划」整体刷新通知：web 会话的 todo 列表走这条路。
  ///
  /// 跟 [setSteps] 的区别：这里每条步骤自带状态（完成 / 进行中 / 待处理），
  /// 因为 dsh 的 `todo/write` 每次都会给出**整份**列表的最新状态，
  /// 不是增量。所以直接覆盖，不做"保住已完成"的处理。
  Future<void> applySteps(
    List<DshTaskStep> steps, {
    String? title,
    String? status,
    bool alert = false,
  }) async {
    if (steps.isEmpty) return;
    if (title != null && title.isNotEmpty) _title = title;
    if (status != null) _status = status;
    _steps
      ..clear()
      ..addAll(steps);
    _activeIndex = _steps.indexWhere((s) => s.state == DshTaskStepState.active);
    _indeterminate = false;
    _outcome = DshTaskOutcome.running;
    _lastError = null;
    if (alert) {
      _lastWindowsSignature = '';
      _windowsTaskSeq++;
      _windowsTaskTag = 'dsh-task-$_windowsTaskSeq';
    }
    notifyListeners();
    await _publish(promoted: true, windowsAlert: alert, silent: !alert);
  }

  /// 中途补上步骤（模型自己拆的步骤），已有进度不丢。
  Future<void> setSteps(List<String> steps) async {
    if (steps.isEmpty) return;
    final done = doneCount;
    _steps
      ..clear()
      ..addAll([for (final label in steps) DshTaskStep(label)]);
    for (var i = 0; i < done && i < _steps.length; i++) {
      _steps[i].state = DshTaskStepState.done;
    }
    _activeIndex = done < _steps.length ? done : -1;
    if (_activeIndex >= 0) _steps[_activeIndex].state = DshTaskStepState.active;
    _indeterminate = false;
    await _publish(promoted: true, silent: true);
    notifyListeners();
  }

  /// 更新当前状态文案。
  Future<void> setStatus(String status) async {
    _status = status;
    await _publish(promoted: true, silent: true);
    notifyListeners();
  }

  /// 完成当前步骤并进入下一步。
  Future<void> advance([String? status]) async {
    if (_activeIndex >= 0 && _activeIndex < _steps.length) {
      _steps[_activeIndex].state = DshTaskStepState.done;
    }
    _activeIndex++;
    if (_activeIndex < _steps.length) {
      _steps[_activeIndex].state = DshTaskStepState.active;
    } else {
      _activeIndex = -1;
    }
    if (status != null) _status = status;
    await _publish(promoted: true, silent: true);
    notifyListeners();
  }

  /// 当前步骤失败。
  Future<void> failStep(String message) async {
    if (_activeIndex >= 0 && _activeIndex < _steps.length) {
      _steps[_activeIndex].state = DshTaskStepState.failed;
    }
    _status = message;
    await _publish(promoted: true, silent: true);
    notifyListeners();
  }

  /// 把通知切成「等你回复」的形态；返回用户在通知里输入的文字
  /// （取消 / 通知被清除 = null）。
  ///
  /// 同一时刻只允许一个提问。
  Future<String?> ask({
    required String question,
    String? status,
    String? replyLabel,
    String? cancelLabel,
    List<String> options = const <String>[],
  }) async {
    if (!supported) return null;
    if (_replyCompleter != null) return null;
    _title = _title.isEmpty ? 'DeepSeek Harness' : _title;
    _outcome = DshTaskOutcome.running;
    _question = question;
    if (status != null) _status = status;
    final completer = Completer<String?>();
    _replyCompleter = completer;
    if (replyLabel != null) _replyLabel = replyLabel;
    if (cancelLabel != null) _cancelLabel = cancelLabel;

    if (DshWindowsToast.isSupported) {
      // 提问时只留一条需要用户看的通知：进度 Toast 先收掉。
      await DshWindowsToast.instance.cancel(tag: _windowsTaskTag);
      _askOptions = List<String>.unmodifiable(options);
      _askTag = 'dsh-ask-${DateTime.now().microsecondsSinceEpoch}';
      debugAlertCount++;
      final shown = await DshWindowsToast.instance.showAsk(
        tag: _askTag!,
        title: _title,
        question: question,
        options: _askOptions,
        inputPlaceholder: _inputPlaceholder.isNotEmpty
            ? _inputPlaceholder
            : (_replyLabel ?? ''),
        submitLabel: _replyLabel ?? 'Reply',
        skipLabel: _cancelLabel ?? '',
        optionsHint: _optionsHint,
      );
      if (!shown) {
        _finishWindowsAsk(null);
        return null;
      }
      notifyListeners();
      return completer.future;
    }

    await _publish(promoted: true, alertOnce: false, silent: false);
    notifyListeners();
    return completer.future;
  }

  /// 回答 dsh **web 会话**里的提问：弹带输入框的通知，用户提交后走
  /// `userQuestions/answer` RPC 把回答送回会话。
  ///
  /// 失败 / 用户取消时不再重复弹（同一条 callId 记入 dismissed），并在失败
  /// 时留一条结果通知 + 打开 web 的兜底动作。
  Future<void> askWeb({
    required String sessionId,
    required DshQuestion question,
    String title = '',
    String status = '',
    List<DshTaskStep> steps = const <DshTaskStep>[],
  }) async {
    if (!supported) return;
    if (question.callId.isEmpty || question.items.isEmpty) return;
    if (_replyCompleter != null) return;
    if (_dismissedQuestionCallId == question.callId) return;

    if (title.isNotEmpty) _title = title;
    _title = _title.isEmpty ? 'DeepSeek Harness' : _title;
    _outcome = DshTaskOutcome.running;
    if (steps.isNotEmpty) {
      _steps
        ..clear()
        ..addAll(steps);
      _activeIndex = _steps.indexWhere(
        (s) => s.state == DshTaskStepState.active,
      );
      _indeterminate = false;
    }
    if (status.isNotEmpty) _status = status;

    final reply = await ask(question: question.text, options: question.options);
    if (reply == null || reply.trim().isEmpty) {
      _dismissedQuestionCallId = question.callId;
      return;
    }
    final effective =
        resolveOptionReply(reply, question.options) ?? reply.trim();
    // 回答已收到：安卓把「等你回复」的常驻通知收掉，等本轮结束再发结果
    // 通知；Windows 的询问 Toast 已由 _finishWindowsAsk 取消。
    if (AndroidNotifications.isSupported) {
      unawaited(AndroidNotifications.cancel(taskNotificationId));
    }
    // 阻塞式提问只能走页面里的 live waterfall：优先在开着的 dsh web 页面
    // 里把提问卡片填好并提交（等于用户手点）。RPC 只兜底 continued。
    if (await DshWebAnswerBridge.submit(effective)) {
      return;
    }
    final answers = <DshQuestionAnswer>[];
    for (var i = 0; i < question.items.length; i++) {
      final item = question.items[i];
      if (i == 0) {
        final isOption = question.options.contains(effective);
        answers.add(
          DshQuestionAnswer(
            id: item.id,
            selected: isOption ? <String>[effective] : const <String>[],
            custom: isOption ? null : effective,
          ),
        );
      } else {
        // 通知只能收一条回答；其余问题按跳过落（dsh 允许空 selected）。
        answers.add(DshQuestionAnswer(id: item.id));
      }
    }
    final ok = await DshWebRpc.instance.answerQuestionFromDsh(
      sessionId: sessionId,
      callId: question.callId,
      answers: answers,
    );
    if (!ok) {
      _dismissedQuestionCallId = question.callId;
      await postMessage(
        title: _title,
        text: _answerHint.isEmpty ? 'Open dsh web to answer' : _answerHint,
      );
      onOpenWeb?.call();
    }
  }

  /// 提醒用户「dsh 在等你回答」。
  ///
  /// 跟 [ask] 的区别：**不建 replyCompleter**，也就是通知上不带输入框。
  /// 适用于没有 callId / question id 的权限审批类问题 —— 这类问题没有
  /// `userQuestions/answer` 的坐标，只能提醒用户去 web 处理。
  Future<void> notifyQuestion({
    required String title,
    required String question,
    List<String> options = const <String>[],
    List<DshTaskStep> steps = const [],
    String? hint,
  }) async {
    if (!supported) return;
    if (title.isNotEmpty) _title = title;
    if (steps.isNotEmpty) {
      _steps
        ..clear()
        ..addAll(steps);
      _activeIndex = _steps.indexWhere(
        (s) => s.state == DshTaskStepState.active,
      );
      _indeterminate = false;
    }
    _question = hint == null || hint.isEmpty ? question : '$question\n$hint';
    _outcome = DshTaskOutcome.running;

    if (DshWindowsToast.isSupported) {
      // web 会话的提问没有可写回去的 stdin：输入框留给「应用内任务」，
      // 这里只提醒 + 给一个打开 dsh web 的按钮（和安卓现状一致）。
      final detail = StringBuffer();
      for (var i = 0; i < options.length; i++) {
        detail.writeln('${i + 1}. ${options[i]}');
      }
      if (hint != null && hint.isNotEmpty) {
        if (detail.isNotEmpty) detail.writeln();
        detail.write(hint);
      }
      // 提问时把进度条撤掉：同一时刻只留一条需要用户看的通知。
      await DshWindowsToast.instance.cancel(tag: _windowsTaskTag);
      debugAlertCount++;
      await DshWindowsToast.instance.show(
        DshWindowsToastSpec(
          tag: windowsQuestionTag,
          title: _title.isEmpty ? 'DeepSeek Harness' : _title,
          body: question,
          detail: detail.toString().trimRight(),
          silent: false,
          launchKey: 'open',
          buttons: [
            DshWindowsToastButton(key: 'open', label: _openLabel ?? 'Open'),
          ],
        ),
      );
      notifyListeners();
      return;
    }

    notifyListeners();
    await _publish(promoted: true, alertOnce: false);
  }

  /// 任务成功结束：把常驻通知换成一条可清除的结果通知。
  Future<void> finish({
    String? title,
    required String text,
    String? bigText,
    String? subText,
    bool keepNotification = true,
  }) async {
    _outcome = DshTaskOutcome.succeeded;
    _question = null;
    _replyCompleter = null;
    _askTag = null;
    _askOptions = const <String>[];
    _status = text;
    _lastError = null;

    if (DshWindowsToast.isSupported) {
      await DshWindowsToast.instance.cancel(tag: _windowsTaskTag);
      await DshWindowsToast.instance.cancel(tag: windowsQuestionTag);
      _windowsTaskTag = windowsTaskTag;
      _windowsTaskSeq = 0;
      if (keepNotification) {
        debugAlertCount++;
        await DshWindowsToast.instance.showDone(
          tag: 'dsh-done-${++_windowsResultSeq}',
          title: title == null || title.isEmpty ? _title : title,
          text: text,
          detail: [
            if (subText != null && subText.isNotEmpty) subText,
            if (bigText != null && bigText.isNotEmpty) bigText,
          ].join('\n\n'),
          openLabel: _openLabel ?? 'Open',
        );
      }
      notifyListeners();
      return;
    }

    await AndroidNotifications.cancel(taskNotificationId);
    if (keepNotification) {
      debugAlertCount++;
      await _postResult(
        title: title ?? _title,
        text: text,
        bigText: bigText,
        subText: subText,
      );
    }
    notifyListeners();
  }

  /// 任务失败：同样换成结果通知，但标题带上失败。
  Future<void> fail(String message, {String? title}) async {
    _outcome = DshTaskOutcome.failed;
    _question = null;
    _replyCompleter = null;
    _askTag = null;
    _askOptions = const <String>[];
    _status = message;
    _lastError = message;

    if (DshWindowsToast.isSupported) {
      await DshWindowsToast.instance.cancel(tag: _windowsTaskTag);
      await DshWindowsToast.instance.cancel(tag: windowsQuestionTag);
      _windowsTaskTag = windowsTaskTag;
      _windowsTaskSeq = 0;
      debugAlertCount++;
      await DshWindowsToast.instance.showDone(
        tag: 'dsh-done-${++_windowsResultSeq}',
        title: title == null || title.isEmpty ? _title : title,
        text: message,
        failed: true,
        openLabel: _openLabel ?? 'Open',
      );
      notifyListeners();
      return;
    }

    await AndroidNotifications.cancel(taskNotificationId);
    debugAlertCount++;
    await _postResult(title: title ?? _title, text: message, bigText: message);
    notifyListeners();
  }

  /// 撤掉任务与它的通知。
  Future<void> cancelTask() async {
    _outcome = DshTaskOutcome.cancelled;
    _replyCompleter?.complete(null);
    _replyCompleter = null;
    _askTag = null;
    _askOptions = const <String>[];
    _question = null;
    if (DshWindowsToast.isSupported) {
      await DshWindowsToast.instance.cancel(tag: _windowsTaskTag);
      await DshWindowsToast.instance.cancelGroup(group: windowsGroup);
      _windowsTaskTag = windowsTaskTag;
      _windowsTaskSeq = 0;
      notifyListeners();
      return;
    }
    await AndroidNotifications.cancel(taskNotificationId);
    notifyListeners();
  }

  /// 单纯推一条结果通知（不属于任何任务时用，比如进程退出提醒）。
  Future<void> postMessage({
    required String title,
    required String text,
    String? bigText,
  }) async {
    debugAlertCount++;
    if (DshWindowsToast.isSupported) {
      await DshWindowsToast.instance.showDone(
        tag: 'dsh-done-${++_windowsResultSeq}',
        title: title,
        text: text,
        detail: bigText ?? '',
        openLabel: _openLabel ?? 'Open',
      );
      return;
    }
    await _postResult(title: title, text: text, bigText: bigText);
  }

  // ---- 通知组装 ----

  Future<void> _postResult({
    required String title,
    required String text,
    String? bigText,
    String? subText,
  }) async {
    if (!supported) return;
    _resultNotificationId++;
    await AndroidNotifications.show(
      AndroidNotificationSpec(
        id: _resultNotificationId,
        title: title,
        text: text,
        // 折叠态很多 ROM 不画 subText（vivo 就是），所以把副标题也塞进展开内容
        // 的首行 —— 用户一拉就能看到「agent 已完成此轮操作」。
        bigText: (subText != null && subText.isNotEmpty)
            ? '$subText\n\n${bigText ?? text}'
            : bigText,
        subText: subText,
        result: true,
        autoCancel: true,
        alertOnce: false,
      ),
    );
  }

  Future<NotificationPostResult> _publish({
    required bool promoted,
    bool alertOnce = true,
    bool windowsAlert = false,
    bool silent = false,
  }) async {
    if (!supported || _title.isEmpty) {
      return const NotificationPostResult(posted: false);
    }
    final willAlert = DshWindowsToast.isSupported ? windowsAlert : !silent;
    if (willAlert) debugAlertCount++;
    if (DshWindowsToast.isSupported) {
      return _publishWindows(alert: windowsAlert);
    }
    final segments = <AndroidProgressSegment>[
      for (final step in _steps)
        AndroidProgressSegment(step.weight * 100, color: step.color),
    ];
    final points = <AndroidProgressPoint>[];
    var cursor = 0;
    for (var i = 0; i < _steps.length; i++) {
      if (i > 0) {
        points.add(AndroidProgressPoint(cursor, color: _steps[i].color));
      }
      cursor += _steps[i].weight * 100;
    }
    final doneWeight = _steps
        .where((s) => s.state == DshTaskStepState.done)
        .fold<int>(0, (sum, s) => sum + s.weight);
    final totalWeight = _steps.fold<int>(0, (sum, s) => sum + s.weight);

    final actions = <AndroidNotificationAction>[
      if (_replyCompleter != null)
        AndroidNotificationAction(
          key: 'reply',
          title: _replyLabel ?? '回复',
          reply: true,
          replyLabel: _replyLabel,
        ),
      if (_replyCompleter != null)
        AndroidNotificationAction(key: 'cancel', title: _cancelLabel ?? '取消'),
    ];

    return AndroidNotifications.show(
      AndroidNotificationSpec(
        id: taskNotificationId,
        title: _title,
        text: _question ?? _status,
        subText: _subtitle.isEmpty ? null : _subtitle,
        bigText: _bigText(),
        ongoing: true,
        promoted: promoted,
        silent: silent,
        alertOnce: alertOnce,
        showWhen: true,
        route: 'lab/dsh',
        indeterminate: _indeterminate && segments.isEmpty,
        progress: doneWeight * 100,
        progressMax: totalWeight * 100,
        segments: segments,
        points: points,
        actions: actions,
        // 提问时要让用户看见文字而不是只有一根进度条
        styledByProgress: _replyCompleter == null,
      ),
    );
  }

  /// Windows 进度 / Stepper Toast。
  ///
  /// [alert] true 时这次更新会重新弹横幅（步骤完成、任务开始）；普通
  /// 状态刷新走静音更新，避免模型每吐一行就响一次。
  Future<NotificationPostResult> _publishWindows({required bool alert}) async {
    final done = doneCount;
    final total = stepCount;
    final stepText = total == 0
        ? ''
        : (_stepsLabel?.call(done, total) ?? '$done/$total');
    final body = _question ?? _status;
    final detail = _bigText();
    final signature = '$_title|$body|$detail|$done|$total';
    if (signature == _lastWindowsSignature && !alert) {
      return const NotificationPostResult(posted: true);
    }
    _lastWindowsSignature = signature;
    // 只有 start/首轮 applySteps 传 alert=true：任务开始弹一次横幅；
    // 中途步骤与正文更新一律静音原地替换，不再每步换 tag 重弹。
    final pushAlert = alert;
    final ok = await DshWindowsToast.instance.showProgress(
      tag: _windowsTaskTag,
      title: _title,
      body: body,
      detail: detail,
      progress: total == 0 ? 0 : done / total,
      progressText: stepText,
      silent: !pushAlert,
    );
    return NotificationPostResult(posted: ok);
  }

  String _bigText() {
    final buffer = StringBuffer();
    if (_status.isNotEmpty) buffer.writeln(_status);
    if (_steps.isNotEmpty) {
      for (var i = 0; i < _steps.length; i++) {
        final step = _steps[i];
        final mark = switch (step.state) {
          DshTaskStepState.done => '✓',
          DshTaskStepState.active => '▸',
          DshTaskStepState.failed => '✗',
          DshTaskStepState.pending => '·',
        };
        buffer.writeln('$mark ${step.label}');
      }
    }
    return buffer.toString().trimRight();
  }
}
