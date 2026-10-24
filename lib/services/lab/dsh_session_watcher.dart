// lib/services/lab/dsh_session_watcher.dart
//
// 把 **dsh web 会话**的状态映射到安卓通知。
//
// 背景：`dsh_task_runner.dart` 那条链路只覆盖「应用内发起的一次性任务」——
// 它 spawn 一个 headless 进程，解析 stdout 里的 `L2A-*` 标记。用户在浏览器里
// （应用内浏览器或桌面 Chrome）跟 dsh 聊天时，输出走的是 dsh web 进程，
// 那边没有任何东西在听。
//
// 做法：dsh 会把会话落盘成 `$DSH_HOME/sessions/<ws>/session-<uuid>/session.v4.jsonl.zstd`
// （zstd 压缩的 jsonl），里面 `todo/write` 事件就是 web 底部那个「任务」面板的
// 数据源。Dart 没有可靠的 zstd 库，于是：
//
//   node 侧（assets/lab/dsh_session_watch.mjs，node 22+ 自带 zstdDecompressSync）
//     → 轮询最新的 session 文件，解压，抽成一份小 JSON 原子写盘
//   Dart 侧（本文件）
//     → 每 1.2 秒读那个 JSON，变了就刷通知
//
// 好处：不需要模型输出任何特殊标记，也不依赖 dsh 的内部 HTTP/SSE 接口
// （dsh 升级不会把它弄坏）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'dsh_question.dart';
import 'dsh_service.dart';
import 'dsh_task_center.dart';
import 'dsh_task_runner.dart';
import 'lab_process.dart';
import 'node_runtime_service.dart';

/// 一条 todo（对应 dsh web 里的任务项）。
class DshTodoItem {
  const DshTodoItem({required this.content, required this.status});

  final String content;

  /// `pending` | `in_progress` | `completed`
  final String status;

  DshTaskStepState get stepState => switch (status) {
    'completed' => DshTaskStepState.done,
    'in_progress' => DshTaskStepState.active,
    _ => DshTaskStepState.pending,
  };
}

/// 通知文案（由 UI 层注入 l10n，service 自己拿不到 context）。
class DshWatchLabels {
  const DshWatchLabels({
    required this.agentDone,
    required this.needAnswer,
    required this.answerHint,
    this.thinking = '思考中…',
  });

  final String agentDone;
  final String needAnswer;
  final String answerHint;

  /// 第一轮“开始思考”的通知正文（会话里还没有正文时用）。
  final String thinking;
}

/// watcher 产出的会话快照。
class DshSessionState {
  const DshSessionState({
    required this.session,
    required this.title,
    required this.running,
    required this.step,
    required this.todos,
    required this.text,
    required this.updatedAt,
    this.errorCode,
    this.errorMessage,
    this.question,
  });

  final String session;
  final String title;
  final bool running;
  final int step;
  final List<DshTodoItem> todos;
  final String text;
  final int updatedAt;
  final String? errorCode;
  final String? errorMessage;

  /// 非空 = dsh 正在等用户回答 / 确认。
  final DshQuestion? question;

  /// 用作去重签名：同一份状态不重复刷通知。
  String get signature => '$session|$updatedAt|$running|${todos.length}';

  static DshSessionState? tryParse(String raw) {
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final todos = <DshTodoItem>[];
      final list = map['todos'];
      if (list is List) {
        for (final item in list) {
          if (item is! Map) continue;
          final content = '${item['content'] ?? ''}'.trim();
          if (content.isEmpty) continue;
          todos.add(
            DshTodoItem(
              content: content,
              status: '${item['status'] ?? 'pending'}',
            ),
          );
        }
      }
      final error = map['error'];
      return DshSessionState(
        session: '${map['session'] ?? ''}',
        title: '${map['title'] ?? ''}'.trim(),
        running: map['running'] == true,
        step: (map['step'] as num?)?.toInt() ?? 0,
        todos: todos,
        text: '${map['text'] ?? ''}'.trim(),
        updatedAt: (map['updatedAt'] as num?)?.toInt() ?? 0,
        errorCode: error is Map ? '${error['code'] ?? ''}' : null,
        errorMessage: error is Map ? '${error['message'] ?? ''}' : null,
        question: DshQuestion.tryParse(map['question']),
      );
    } catch (_) {
      return null;
    }
  }
}

class DshSessionWatcher extends ChangeNotifier {
  DshSessionWatcher._();

  static final DshSessionWatcher instance = DshSessionWatcher._();

  LabProcessHandle? _proc;
  Timer? _timer;
  String _lastSignature = '';
  bool _wasRunning = false;

  /// 同一个提问只弹一次（轮询每 1.2 秒会重复看到它）。
  String _lastQuestionKey = '';
  DshSessionState? _state;

  DshSessionState? get state => _state;

  /// UI 层进来时把 l10n 文案塞进来（service 没有 BuildContext）。
  DshWatchLabels _labels = const DshWatchLabels(
    agentDone: 'agent 已完成此轮操作',
    needAnswer: 'dsh 在等你回答',
    answerHint: '打开 dsh web 回答',
  );

  void setLabels(DshWatchLabels labels) => _labels = labels;

  /// 安卓与 Windows 都有系统通知实现（Windows 见 dsh_windows_toast.dart）。
  bool get supported => Platform.isAndroid || Platform.isWindows;

  /// 启动 watcher（dsh web 起来之后调）。
  ///
  /// 失败一律静默：这只是"锦上添花"的能力，不能影响 dsh 本身能不能用。
  Future<void> start(DshService dsh) async {
    if (!supported) return;
    await stop();
    try {
      final home = await dsh.resolveDshHome();
      final root = p.dirname(home);

      late final String outPath;
      late final List<String> args;
      if (Platform.isWindows) {
        // 桌面把脚本落成 .cjs 再跑：base64 内联会顶到 cmd 的 8191 字符
        // 命令行上限；`.cjs` 则不受上层 package.json 的 "type":"module" 影响。
        final support = await getApplicationSupportDirectory();
        await support.create(recursive: true);
        outPath = p.join(support.path, 'dsh-session-watch.json');
        final scriptPath = p.join(support.path, 'dsh_session_watch.cjs');
        final script = await rootBundle.loadString(
          'assets/lab/dsh_session_watch.mjs',
        );
        await File(scriptPath).writeAsString(script, flush: true);
        args = <String>[scriptPath];
      } else {
        // 脚本**不落盘**：/sdcard 是 FUSE，应用写出来的文件是 app 私有 0660，
        // Shizuku 的 shell 子进程读不了（chmod 也会被 FUSE 挡成 EPERM）。
        // 所以 base64 内联进 `node -e` —— Shizuku 是直接 exec(argv)，
        // 不经过 shell，没有转义问题。
        outPath = p.join(root, 'l2a-session.json');
        final script = await rootBundle.loadString(
          'assets/lab/dsh_session_watch.mjs',
        );
        final encoded = base64Encode(utf8.encode(script));
        args = <String>[
          '-e',
          "eval(Buffer.from('$encoded','base64').toString('utf8'))",
        ];
      }
      // 清掉上一轮的残留，免得一启动就复读旧状态。
      final out = File(outPath);
      if (await out.exists()) await out.delete();

      final env = await dsh.buildProcessEnv();
      // 桌面 Dart 侧也要显式注入：脚本只认 process.env.DSH_HOME。
      env['DSH_HOME'] = home;
      env['DSH_AGENTS_HOME'] = await dsh.resolveAgentsHome();
      env['L2A_WATCH_OUT'] = outPath;
      env['L2A_WATCH_POLL'] = '1200';
      final node = Platform.isAndroid
          ? await NodeRuntimeService.instance.nodeBinPath()
          : 'node';
      final proc = await startLabProcess(
        executable: node,
        args: args,
        workingDirectory: root,
        environment: env,
        runInShell: !Platform.isAndroid,
      );
      _proc = proc;
      proc.stdout.listen((line) => debugPrint('[session-watch] $line'));
      proc.stderr.listen((line) => debugPrint('[session-watch:err] $line'));
      unawaited(
        proc.exitCode.then((code) {
          debugPrint('[session-watch] 退出（$code）');
          _proc = null;
        }),
      );
      _timer = Timer.periodic(
        const Duration(milliseconds: 1200),
        (_) => unawaited(_poll(outPath)),
      );
      debugPrint('[session-watch] started, out=$outPath');
    } catch (e) {
      debugPrint('[session-watch] 启动失败：$e');
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final proc = _proc;
    _proc = null;
    if (proc != null) {
      try {
        await proc.kill();
      } catch (_) {
        // 已经退了
      }
    }
    _wasRunning = false;
    _lastSignature = '';
    _lastQuestionKey = '';
    _state = null;
  }

  Future<void> _poll(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return;
      final raw = await file.readAsString();
      if (raw.isEmpty) return;
      final next = DshSessionState.tryParse(raw);
      if (next == null || next.signature == _lastSignature) return;
      _lastSignature = next.signature;
      _state = next;
      notifyListeners();
      await _apply(next);
    } catch (e) {
      debugPrint('[session-watch] 读状态失败：$e');
    }
  }

  /// 把会话快照映射成通知。
  ///
  /// 优先级：应用内发起的 headless 任务 > web 会话（headless 跑着时不动通知，
  /// 否则两条链路会互相覆盖）。
  Future<void> _apply(DshSessionState s) async {
    if (DshTaskRunner.instance.running) {
      _wasRunning = s.running;
      return;
    }
    final center = DshTaskCenter.instance;
    // 标题优先用「当前正在执行的那条 todo」——用户在通知栏一眼看到在做啥，
    // 而不是笼统的会话标题。
    final active = s.todos.where((t) => t.status == 'in_progress').toList();
    final title = active.isNotEmpty
        ? active.first.content
        : (s.title.isEmpty ? 'DeepSeek Harness' : s.title);
    if (s.todos.isEmpty && !s.running) {
      // 会话里没 todo、也没在跑：没有可展示的进度
      if (_wasRunning && center.hasTask) {
        await _finishSession(center, s, title);
      }
      _wasRunning = s.running;
      return;
    }
    final steps = [
      for (final todo in s.todos)
        DshTaskStep(todo.content)..state = todo.stepState,
    ];

    // 在等用户回答：能直接回复的（有 callId / 问题 id）弹带输入框的通知，
    // 回复经 dsh 的 userQuestions/answer RPC 送回会话；审批类问题没有
    // callId，仍只提醒去 web。
    final question = s.question;
    if (question != null && question.text.isNotEmpty) {
      final key = '${s.session}|${question.callId}|${question.text}';
      if (key != _lastQuestionKey) {
        _lastQuestionKey = key;
        if (question.answerable) {
          unawaited(
            center.askWeb(
              sessionId: s.session,
              question: question,
              title: title,
              status: s.text,
              steps: steps,
            ),
          );
        } else {
          // Windows 的 notifyQuestion 会把 options 单独列成 1/2/3，这里只给
          // 「打开 dsh web 回答」；安卓仍沿用原来把选项拼进 hint 的文案。
          final hint = Platform.isWindows || question.options.isEmpty
              ? _labels.answerHint
              : '${question.options.join(' / ')}\n${_labels.answerHint}';
          await center.notifyQuestion(
            title: title,
            question: question.text,
            options: question.options,
            steps: steps,
            hint: hint,
          );
        }
      }
      _wasRunning = s.running;
      return;
    }
    _lastQuestionKey = '';

    if (s.running) {
      // 只在「这一轮刚开跑」时弹一次；中途的思考 / 工具调用 / todo 更新
      // 一律不碰通知，避免模型每想一步就弹一条。
      if (!_wasRunning) {
        final status = s.text.isEmpty ? _labels.thinking : s.text;
        if (s.todos.isEmpty) {
          await center.start(title: title, status: status);
        } else {
          await center.applySteps(
            steps,
            title: title,
            status: s.errorMessage == null || s.errorMessage!.isEmpty
                ? status
                : '${s.errorCode ?? ''}：${s.errorMessage}'.trim(),
            alert: true,
          );
        }
      }
    } else if (_wasRunning && center.hasTask) {
      await _finishSession(center, s, title);
    }
    _wasRunning = s.running;
  }

  /// 会话结束：Windows 的结果 Toast 标题用 dsh 的会话标题，正文用
  /// agent 最后一轮输出；安卓保持原来的「结果通知」文案。
  Future<void> _finishSession(
    DshTaskCenter center,
    DshSessionState s,
    String fallbackTitle,
  ) {
    final output = s.text.isEmpty ? s.title : s.text;
    final text = output.isEmpty ? fallbackTitle : output;
    if (Platform.isWindows) {
      return center.finish(
        title: s.title.isEmpty ? fallbackTitle : s.title,
        text: text,
        subText: _labels.agentDone,
      );
    }
    return center.finish(text: text, subText: _labels.agentDone);
  }
}
