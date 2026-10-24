// lib/services/lab/dsh_task_runner.dart
//
// 任务模式：把用户的一句话交给 dsh 的 **headless** profile 跑，整个过程
// 投到通知上（见 `dsh_task_center.dart`）。
//
// 为什么是 headless 而不是复用一直在跑的 web 服务：
//   · `dsh headless "<task>"` 是官方的一次性任务入口 —— 提交一条用户消息、
//     等 agent 停稳、把最后一条 assistant 文本打到 stdout、然后退出。它不占
//     端口、不挂 UI，跑完就干净退出，天然适合「发个任务去做别的事」。
//   · web 服务是长会话，模型在里面的行为我们插不进手。
//
// 步骤 / 提问 / 结果的信号走 **模型输出里的标记行**（`L2A-PLAN:` `L2A-STEP:`
// `L2A-ASK:` `L2A-RESULT:`），提示词由 [kDshTaskPreamble] 注入。这是唯一
// 不需要改 dsh 内部就能拿到「做到哪一步」的办法：headless 只保证最后一条
// 文本打到 stdout，过程信号一概没有。
//
// 「等你回复」怎么闭环：headless 没有交互式后续输入，所以模型问完就结束
// 这一轮；用户回复后我们**带着上下文再跑一轮**（原始任务 + 上一轮的问答），
// 而不是往已经退出的进程里塞 stdin。

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'dsh_config.dart';
import 'dsh_service.dart';
import 'dsh_task_center.dart';
import 'lab_process.dart';
import 'node_runtime_service.dart';

/// 一轮任务的产出。
class DshTaskRun {
  const DshTaskRun({required this.ok, this.result = '', this.error});

  final bool ok;

  /// 模型给的最终答复（`L2A-RESULT:` 那一段；没标记就取最后一条非空文本）。
  final String result;

  final String? error;
}

class DshTaskRunner {
  DshTaskRunner._();

  static final DshTaskRunner instance = DshTaskRunner._();

  /// headless 任务最多来回问几轮（防止模型反复追问把用户耗死）。
  static const int maxAskRounds = 3;

  bool _running = false;

  bool get running => _running;

  /// 跑一个任务。返回最终答复（失败时 [DshTaskRun.error] 有原因）。
  ///
  /// [onLog] 会把 dsh 的原始输出行吐给调用方（日志页用）。
  Future<DshTaskRun> run(
    String task, {
    void Function(String line)? onLog,
    String? replyLabel,
    String? cancelLabel,
  }) async {
    if (_running) {
      return const DshTaskRun(ok: false, error: 'busy');
    }
    final dsh = DshService.instance;
    final center = DshTaskCenter.instance;
    final prompt = task.trim();
    if (prompt.isEmpty) {
      return const DshTaskRun(ok: false, error: 'emptyTask');
    }
    if (dsh.installDir == null) {
      return const DshTaskRun(ok: false, error: 'notInstalled');
    }
    await dsh.refreshNodeStatus();
    if (!dsh.canRun) {
      return const DshTaskRun(ok: false, error: 'missingNode');
    }

    _running = true;
    var rounds = 0;
    var question = '';
    var answer = '';
    // 先占住通知：不然任务失败时 `center.fail()` 会沿用上一条通知的标题
    // （用户会看到「发一条测试通知 · dsh 退出码 1」这种鬼东西）。
    final taskTitle = _titleFor(prompt);
    await center.start(
      title: taskTitle,
      status: '正在启动 dsh…',
      steps: const ['启动', '执行'],
    );
    try {
      while (true) {
        final text = _composePrompt(dsh, prompt, question, answer);
        final outcome = await _runOnce(
          dsh: dsh,
          center: center,
          prompt: text,
          onLog: onLog,
        );
        if (outcome.error != null) {
          await center.fail('${outcome.error}', title: taskTitle);
          return DshTaskRun(ok: false, error: outcome.error);
        }
        if (outcome.question.isEmpty) {
          // 任务结束：把结果发成一条可清除的通知
          final result = outcome.result;
          await center.finish(
            title: taskTitle,
            text: _oneLine(result),
            bigText: result,
          );
          return DshTaskRun(ok: true, result: result);
        }
        // 模型在等人拍板
        if (rounds >= maxAskRounds) {
          await center.fail(
            '提问轮次超过上限（$maxAskRounds），已停止',
            title: taskTitle,
          );
          return DshTaskRun(
            ok: false,
            result: outcome.result,
            error: 'tooManyAsks',
          );
        }
        rounds++;
        final reply = await center.ask(
          question: outcome.question,
          options: outcome.questionOptions,
          replyLabel: replyLabel,
          cancelLabel: cancelLabel,
        );
        if (reply == null || reply.trim().isEmpty) {
          // 用户取消（或清掉了通知）
          await center.cancelTask();
          return DshTaskRun(ok: false, error: 'cancelled', result: outcome.result);
        }
        question = outcome.question;
        answer = reply.trim();
      }
    } finally {
      _running = false;
    }
  }

  /// 把「原始任务 + 上一轮问答」拼成下一轮的提示词。
  String _composePrompt(
    DshService dsh,
    String task,
    String question,
    String answer,
  ) {
    final buffer = StringBuffer();
    if (dsh.taskHintEnabled) {
      buffer.writeln(kDshTaskPreamble);
      if (Platform.isWindows) buffer.writeln(kDshTaskWindowsOptionsPreamble);
      buffer.writeln();
    }
    buffer.writeln('任务：$task');
    if (question.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('上一轮你问：$question');
      buffer.writeln('用户回答：$answer');
      buffer.writeln('请继续完成上面的原始任务，并同样用 L2A-* 标记汇报进度。');
    }
    return buffer.toString();
  }

  /// 单轮 headless 执行 + 输出解析。
  Future<_RoundOutcome> _runOnce({
    required DshService dsh,
    required DshTaskCenter center,
    required String prompt,
    required void Function(String line)? onLog,
  }) async {
    final dir = dsh.installDir!;
    String? patchPath;
    try {
      patchPath = await _writeHeadlessPatch(dsh, dir);
      final env = await dsh.buildProcessEnv();
      await dsh.prepareRuntimeDirs();
      final executable = Platform.isAndroid
          ? await NodeRuntimeService.instance.nodeBinPath()
          : 'node';
      final process = await startLabProcess(
        executable: executable,
        args: [
          '--expose-internals',
          dsh.binPath,
          '--profile',
          'headless',
          '--patch',
          patchPath,
          prompt,
        ],
        workingDirectory: dir,
        environment: env,
        // Windows 的 `cmd /c` 会把多行 prompt 拆成多条命令，dsh 只收到
        // 第一行（实测：第二轮只剩任务模板，用户回答丢失）。直接
        // CreateProcess 才能把换行 / 竖线 / 中文作为单个 argv 传进去。
        runInShell: !Platform.isAndroid && !Platform.isWindows,
      );

      final result = await _consume(
        process: process,
        center: center,
        onLog: onLog,
      );
      final code = await process.exitCode.timeout(
        const Duration(minutes: 30),
        onTimeout: () {
          unawaited(process.kill());
          return -1;
        },
      );
      if (code != 0 && result.result.isEmpty && result.question.isEmpty) {
        // 只报「退出码 1」等于没说：dsh 把真正的原因写在 stderr
        // （MISSING_CREDENTIAL / TRANSPORT: Connection error…）。
        final reason = _pickError(result.stderr);
        return _RoundOutcome(
          result: '',
          question: '',
          error: reason ?? 'dsh 退出码 $code',
          stderr: result.stderr,
        );
      }
      return result;
    } catch (e) {
      return _RoundOutcome(result: '', question: '', error: '$e');
    }
  }

  /// 把 headless 要用的模型配置写成一份临时 patch。
  Future<String> _writeHeadlessPatch(DshService dsh, String dir) async {
    final file = File(p.join(dir, '.l2a.headless.yml'));
    await file.writeAsString(await dsh.buildHeadlessPatch(), flush: true);
    if (Platform.isAndroid) {
      // shell 身份要读得到（应用建的文件默认 0600）
      await NodeRuntimeService.instance.makeLabReadable(sub: 'dsh');
    }
    return file.path;
  }

  /// 边读 stdout 边把标记翻译成通知状态。
  Future<_RoundOutcome> _consume({
    required LabProcessHandle process,
    required DshTaskCenter center,
    required void Function(String line)? onLog,
  }) async {
    final resultBuffer = StringBuffer();
    var inResult = false;
    var question = '';
    var questionOptions = const <String>[];
    var lastText = '';
    var stepsDeclared = false;

    Future<void> handle(String raw) async {
      final line = stripAnsi(raw).trimRight();
      if (line.isEmpty) return;
      // release 包里 debugPrint 仍会进 logcat（标签 flutter），排查 headless
      // 启动失败时这是唯一能看到 dsh 原始输出的地方。
      debugPrint('[dsh-task] $line');
      onLog?.call(line);
      final marker = parseTaskMarker(line);
      if (marker != null) {
        final (name, value) = marker;
        switch (name) {
          case 'PLAN':
            if (!stepsDeclared && value.isNotEmpty) {
              stepsDeclared = true;
              await center.setSteps(_splitSteps(value));
            }
          case 'STEP':
            if (value.isNotEmpty) {
              if (!stepsDeclared) {
                stepsDeclared = true;
                await center.setSteps([value]);
              } else {
                await center.setSteps(_appendStep(center.steps, value));
              }
              await center.setStatus('正在：$value');
            }
          case 'STEP-DONE':
            await center.advance(value.isEmpty ? null : '完成：$value');
          case 'ASK':
            {
              // `问题 | 选项一 | 选项二`：只有 Windows 提示词会这么要求；
              // 安卓输出不带竖线时行为和以前完全一致。
              final parsed = parseAskValue(value);
              question = parsed.question;
              questionOptions = parsed.options;
            }
          case 'RESULT':
            inResult = true;
            if (value.isNotEmpty) resultBuffer.writeln(value);
          case 'RESULT-END':
            inResult = false;
          default:
            break;
        }
        return;
      }
      if (inResult) {
        resultBuffer.writeln(line);
        return;
      }
      lastText = line;
      // 没有标记也没关系：至少让通知上的文字跟着动
      await center.setStatus(_shorten(line));
    }

    await for (final line in process.stdout) {
      await handle(line);
    }
    final errBuffer = StringBuffer();
    await for (final line in process.stderr) {
      final text = stripAnsi(line).trimRight();
      if (text.isEmpty) continue;
      debugPrint('[dsh-task:err] $text');
      errBuffer.writeln(text);
      onLog?.call(text);
    }

    final result = resultBuffer.toString().trim();
    return _RoundOutcome(
      result: result.isEmpty ? lastText : result,
      question: question,
      questionOptions: questionOptions,
      error: null,
      stderr: errBuffer.toString().trim(),
    );
  }

  List<String> _splitSteps(String value) => [
    for (final part in value.split(RegExp(r'[|｜]')))
      if (part.trim().isNotEmpty) part.trim(),
  ];

  List<String> _appendStep(List<DshTaskStep> current, String next) => [
    for (final step in current) step.label,
    next,
  ];

  /// 从 stderr 里挑出最像「原因」的一行（dsh 的报错都是 `dsh: XXX: ...`）。
  String? _pickError(String stderr) {
    final lines = [
      for (final line in stderr.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    if (lines.isEmpty) return null;
    final marked = lines.lastWhere(
      (line) => line.startsWith('dsh:'),
      orElse: () => lines.last,
    );
    return marked.length <= 140 ? marked : '${marked.substring(0, 139)}…';
  }

  /// 任务标题：取任务文本前 24 个字，换行压成空格。
  String _titleFor(String task) {
    final flat = task.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 24 ? flat : '${flat.substring(0, 23)}…';
  }

  String _shorten(String text) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 80 ? flat : '${flat.substring(0, 79)}…';
  }

  String _oneLine(String text) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 100 ? flat : '${flat.substring(0, 99)}…';
  }
}

class _RoundOutcome {
  const _RoundOutcome({
    required this.result,
    required this.question,
    this.questionOptions = const <String>[],
    this.error,
    this.stderr = '',
  });

  final String result;
  final String question;

  /// `L2A-ASK: 问题 | 选项1 | 选项2` 里拆出来的选项（Windows Toast 用）。
  final List<String> questionOptions;
  final String? error;

  /// dsh 的 stderr 原文：退出码非 0 时用它给出人能看懂的原因。
  final String stderr;
}
