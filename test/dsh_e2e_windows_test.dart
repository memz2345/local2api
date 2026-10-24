// Windows dsh 端到端实测（真 dsh + 真 headless + 假 OpenAI 上游）：
//   第一轮 dsh 输出计划并提问 -> 原生 Toast 输入框回 "2"
//   -> DshTaskRunner 把「用户回答：方案 B」带回第二轮
//   -> dsh 输出 L2A-RESULT，完成 Toast 带上结果。
//
// 假上游用独立的 node 进程（和手工实测同一份 SSE 逻辑）。
//
// 跑法（需要先装好 build/dsh-e2e 与 Node）：
//   L2A_DSH_E2E_ROOT=G:\192\local2api\build\dsh-e2e \
//   DSH_HOME=G:\192\local2api\build\dsh-e2e\home \
//   L2A_KEY=test \
//   flutter test test/dsh_e2e_windows_test.dart
//
// 没有这些环境变量时测试会 skip，不拖慢普通测试。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/lab/dsh_service.dart';
import 'package:local2api/services/lab/dsh_task_center.dart';
import 'package:local2api/services/lab/dsh_task_runner.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _mockScript = r'''
const http = require('node:http');
const fs = require('node:fs');
const port = Number(process.argv[2]);
const logPath = process.argv[3];

const server = http.createServer(async (req, res) => {
  if (req.method === 'GET' && req.url.startsWith('/v1/models')) {
    res.writeHead(200, {'content-type': 'application/json'});
    res.end(JSON.stringify({
      object: 'list',
      data: [{id: 'mock-model', object: 'model', created: 0, owned_by: 'mock'}],
    }));
    return;
  }

  let raw = '';
  for await (const chunk of req) raw += chunk;
  let body = {};
  try { body = JSON.parse(raw || '{}'); } catch (e) {}
  const messages = body.messages || [];
  const texts = [];
  for (const m of messages) {
    if (!m) continue;
    if (typeof m.content === 'string') texts.push(m.content);
    else if (Array.isArray(m.content)) {
      for (const p of m.content) {
        if (p && typeof p.text === 'string') texts.push(p.text);
      }
    }
  }
  const all = texts.join('\n');
  fs.appendFileSync(logPath, all + '\n---REQ---\n');

  const isTitle = all.includes('Create a concise title');
  const hasAnswer = all.includes('用户回答：');
  let text;
  if (isTitle) {
    text = 'E2E 测试会话';
  } else if (hasAnswer) {
    text = 'L2A-STEP: 执行\nL2A-STEP-DONE: 执行\n'
      + 'L2A-RESULT:\n已按方案 B 完成，收到回答。\nL2A-RESULT-END\n';
  } else {
    text = 'L2A-PLAN: 准备 | 执行 | 收尾\n'
      + 'L2A-STEP: 准备\nL2A-STEP-DONE: 准备\n'
      + 'L2A-STEP: 执行\n'
      + 'L2A-ASK: 选哪个方案？ | 方案 A | 方案 B\n';
  }

  console.error('REQ stream=' + body.stream + ' title=' + isTitle
    + ' answer=' + hasAnswer);

  const base = {
    id: 'chatcmpl-e2e',
    object: 'chat.completion.chunk',
    created: 0,
    model: 'mock-model',
  };
  if (body.stream === true) {
    res.writeHead(200, {
      'content-type': 'text/event-stream',
      'cache-control': 'no-cache',
      'connection': 'keep-alive',
    });
    const send = (o) => res.write('data: ' + JSON.stringify(o) + '\n\n');
    send({...base, choices: [{index: 0, delta: {role: 'assistant'}, finish_reason: null}]});
    for (let i = 0; i < text.length; i += 100) {
      send({...base, choices: [{index: 0, delta: {content: text.slice(i, i + 100)}, finish_reason: null}]});
    }
    send({...base, choices: [{index: 0, delta: {}, finish_reason: 'stop'}],
      usage: {prompt_tokens: 10, completion_tokens: 20, total_tokens: 30}});
    res.end('data: [DONE]\n\n');
  } else {
    res.writeHead(200, {'content-type': 'application/json'});
    res.end(JSON.stringify({
      id: 'chatcmpl-e2e',
      object: 'chat.completion',
      created: 0,
      model: 'mock-model',
      choices: [{index: 0, message: {role: 'assistant', content: text}, finish_reason: 'stop'}],
      usage: {prompt_tokens: 10, completion_tokens: 20, total_tokens: 30},
    }));
  }
});

server.listen(port, '127.0.0.1', () => {
  console.error('mock ready ' + port);
});
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final root = Platform.environment['L2A_DSH_E2E_ROOT'];
  final dshHome = Platform.environment['DSH_HOME'];
  final enabled = Platform.isWindows &&
      root != null &&
      root.isNotEmpty &&
      dshHome != null &&
      dshHome.isNotEmpty;
  if (!enabled) {
    test('Windows dsh e2e', () {}, skip: 'needs L2A_DSH_E2E_ROOT + DSH_HOME');
    return;
  }

  test('dsh 提问 -> Toast 输入 2 -> 第二轮按方案 B 完成', () async {
    final mockFile = File('$root/e2e-mock.cjs');
    final requestLog = File('$root/e2e-requests.log');
    await mockFile.writeAsString(_mockScript);
    await requestLog.writeAsString('');

    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();

    final mock = await Process.start(
      'node',
      [mockFile.path, '$port', requestLog.path],
      workingDirectory: root,
      runInShell: true,
    );
    final ready = Completer<void>();
    mock.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          // ignore: avoid_print
          print('[e2e-mock] $line');
          if (line.contains('mock ready') && !ready.isCompleted) {
            ready.complete();
          }
        });
    await ready.future.timeout(const Duration(seconds: 15));

    const channel = MethodChannel('com.memz2345.local2api/dsh_toast');
    final messenger = TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger;
    final shows = <Map<Object?, Object?>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'ping':
          return true;
        case 'show':
          final map = (call.arguments! as Map).cast<Object?, Object?>();
          shows.add(map);
          if (map['input'] == true) {
            final tag = '${map['tag']}';
            // ignore: avoid_print
            print('[e2e-toast] ask shown tag=$tag');
            Future<void>.delayed(const Duration(milliseconds: 150), () async {
              await messenger.handlePlatformMessage(
                channel.name,
                const StandardMethodCodec().encodeMethodCall(
                  MethodCall('onEvent', <String, Object?>{
                    'type': 'reply',
                    'tag': tag,
                    'group': 'dsh',
                    'key': 'reply',
                    'text': '2',
                  }),
                ),
                (_) {},
              );
            });
          }
          return true;
        default:
          return null;
      }
    });

    final center = DshTaskCenter.instance;
    try {
      final config = File('$dshHome/profiles/web/cordis.patch.yml');
      await config.parent.create(recursive: true);
      await config.writeAsString('''
- id: llm-pi-ai
  name: "@deepseek-ai/dsh-llm-pi-ai"
  config:
    providers:
      local2api:
        displayName: Local2API
        apiKeyEnv: L2A_KEY
        api: openai-completions
        baseURL: "http://127.0.0.1:$port/v1"
        models:
          - id: mock-model
            name: mock-model
            contextWindow: 262144
- id: agent-default-model
  name: "@deepseek-ai/dsh-agent-default-model"
  config: {provider: local2api, model: mock-model}
''');

      SharedPreferences.setMockInitialValues({
        'lab.dsh.root': root,
        'lab.dsh.dir': root,
        'lab.dsh.enabled': false,
        'lab.dsh.task.hint': true,
      });
      final dsh = DshService.instance;
      dsh.debugForceNodeAvailable = true;
      await dsh.init();

      await center.attach(
        replyLabel: '发送',
        cancelLabel: '跳过',
        openLabel: '打开',
        inputPlaceholder: '输入回答',
        optionsHint: '输入 1/2/3 选择预置项',
        stepsLabel: (done, total) => '$done/$total',
      );

      final run = await DshTaskRunner.instance
          .run(
            '做点事并告诉我结果',
            replyLabel: '发送',
            cancelLabel: '跳过',
            // ignore: avoid_print
            onLog: (line) => print('[e2e-dsh] $line'),
          )
          .timeout(const Duration(seconds: 120));

      expect(run.ok, isTrue, reason: run.error ?? '');
      expect(run.result, contains('方案 B'));

      final asks = shows.where((m) => m['input'] == true).toList();
      expect(asks, isNotEmpty);
      expect('${asks.first['body']}', contains('选哪个方案'));
      final detail = '${asks.first['detail']}';
      expect(detail, contains('1. 方案 A'));
      expect(detail, contains('2. 方案 B'));

      final done = shows
          .where((m) => '${m['tag']}'.startsWith('dsh-done-'))
          .toList();
      expect(done, isNotEmpty);
      expect('${done.last['body']}', contains('方案 B'));

      final log = await requestLog.readAsString();
      expect(log, contains('用户回答：方案 B'));
    } finally {
      await center.cancelTask();
      messenger.setMockMethodCallHandler(channel, null);
      // runInShell 起的是 cmd，/T 连 node 子进程一起收掉。
      await Process.run('taskkill', ['/PID', '${mock.pid}', '/T', '/F']);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
