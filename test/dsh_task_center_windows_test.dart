// Windows dsh 通知链路的闭环回归：
//   · 进度 Toast 只在任务开始时弹一次，后续步骤静音原地更新（不换 tag）；
//   · 询问 Toast 带输入框 / 选项 / 发送 / 跳过；
//   · 输入 2 → 映射到第二个预置选项；
//   · 完成 Toast 的标题用会话标题，正文用 agent 输出。
//
// 平台通道用 mock；不依赖真实 Windows Shell。
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/lab/dsh_task_center.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isWindows) {
    test('Windows only', () {}, skip: 'Windows only');
    return;
  }

  test('Windows 进度 / 询问 / 完成 Toast 的完整状态机', () async {
    const channel = MethodChannel('com.memz2345.local2api/dsh_toast');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final shows = <Map<Object?, Object?>>[];

    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'ping':
          return true;
        case 'setting':
          return 'enabled';
        case 'show':
          final map = (call.arguments! as Map).cast<Object?, Object?>();
          shows.add(map);
          return true;
        default:
          return null;
      }
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    final center = DshTaskCenter.instance;
    await center.attach(
      replyLabel: '发送',
      cancelLabel: '跳过',
      openLabel: '打开',
      inputPlaceholder: '输入回答',
      optionsHint: '输入 1/2/3 选择预置项',
      stepsLabel: (done, total) => '$done/$total',
    );

    await center.start(
      title: '测试会话',
      status: '正在执行',
      steps: const ['准备', '执行', '收尾'],
    );
    await center.advance();
    // 进度通知只在 start 时弹一次；advance 是静默更新，tag 也不换。
    final progressShows = shows.where((m) => m['progress'] == true).toList();
    expect(progressShows, hasLength(2));
    expect(progressShows.first['silent'], isFalse, reason: '第一次思考要弹');
    expect(progressShows.last['silent'], isTrue, reason: '后续步骤静音');
    expect(
      progressShows.map((m) => m['tag']).toSet().length,
      1,
      reason: '中途不换 tag',
    );

    final answerFuture = center.ask(
      question: '选哪个方案？',
      options: const ['准备', '执行', '收尾'],
    );
    Map<Object?, Object?>? askShow;
    for (var i = 0; i < 20 && askShow == null; i++) {
      await Future<void>.delayed(Duration.zero);
      askShow = shows
          .where((m) => m['input'] == true)
          .cast<Map<Object?, Object?>?>()
          .lastWhere((m) => m != null, orElse: () => null);
    }
    expect(askShow, isNotNull);
    expect(askShow!['body'], '选哪个方案？');
    final detail = askShow['detail']! as String;
    expect(detail, contains('1. 准备'));
    expect(detail, contains('3. 收尾'));
    expect(detail, contains('输入 1/2/3'));
    final buttons = askShow['buttons']! as List<Object?>;
    expect(buttons.length, 5);
    final tag = askShow['tag']! as String;

    // 模拟原生 Toast 的输入框回传：输入 2 + 点发送。
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
    expect(await answerFuture, '执行');

    await center.finish(
      title: '测试会话',
      text: 'agent 输出内容',
      subText: 'agent 已完成此轮操作',
    );
    final doneShow = shows.lastWhere(
      (m) => '${m['tag']}'.startsWith('dsh-done-'),
    );
    expect(doneShow['title'], '测试会话');
    expect(doneShow['body'], 'agent 输出内容');
    expect(doneShow['detail'], contains('agent 已完成此轮操作'));
    expect(doneShow['input'], isFalse);

    await center.cancelTask();
  });
}
