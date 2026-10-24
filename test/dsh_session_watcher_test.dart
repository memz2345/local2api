// dsh web 会话 → 通知的映射逻辑（不依赖安卓，纯解析与状态机）。
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/lab/dsh_session_watcher.dart';
import 'package:local2api/services/lab/dsh_task_center.dart';

void main() {
  group('web 会话快照解析', () {
    test('解析 todo/write 派生出来的状态', () {
      const raw = '{"v":1,"session":"session-abc","title":"列出任务列表",'
          '"running":true,"step":2,'
          '"todos":[{"content":"A","status":"completed"},'
          '{"content":"B","status":"in_progress"},'
          '{"content":"C","status":"pending"}],'
          '"error":{"code":"TRANSPORT","message":"Connection error."},'
          '"text":"结果","updatedAt":123}';
      final s = DshSessionState.tryParse(raw)!;
      expect(s.session, 'session-abc');
      expect(s.title, '列出任务列表');
      expect(s.running, isTrue);
      expect(s.step, 2);
      expect(s.todos.length, 3);
      expect(s.errorCode, 'TRANSPORT');
      expect(s.updatedAt, 123);
    });

    test('todo 的 status 映射成三段色对应的步骤状态', () {
      const raw = '{"todos":[{"content":"A","status":"completed"},'
          '{"content":"B","status":"in_progress"},'
          '{"content":"C","status":"pending"},'
          '{"content":"D","status":"未知状态"}]}';
      final s = DshSessionState.tryParse(raw)!;
      expect(s.todos[0].stepState, DshTaskStepState.done);
      expect(s.todos[1].stepState, DshTaskStepState.active);
      expect(s.todos[2].stepState, DshTaskStepState.pending);
      // 认不出的状态一律按"未开始"，别让通知上出现脏颜色
      expect(s.todos[3].stepState, DshTaskStepState.pending);
    });

    test('坏数据不抛异常', () {
      expect(DshSessionState.tryParse('not json'), isNull);
      expect(DshSessionState.tryParse('[]'), isNull);
      expect(DshSessionState.tryParse('{}'), isNotNull);
    });

    test('解析 dsh 的提问（ask_user_question / 审批）', () {
      final ask = DshSessionState.tryParse(
        '{"question":{"text":"用哪个分支？","options":["main","dev"]}}',
      )!;
      expect(ask.question!.text, '用哪个分支？');
      expect(ask.question!.options, ['main', 'dev']);

      // 只有选项没正文也不算提问
      expect(
        DshSessionState.tryParse('{"question":{"text":"","options":[]}}')!.question,
        isNull,
      );
      // 没有 question 字段
      expect(DshSessionState.tryParse('{"todos":[]}')!.question, isNull);
    });

    test('空内容的 todo 被丢掉', () {
      const raw = '{"todos":[{"content":"   ","status":"pending"},'
          '{"content":"B","status":"pending"}]}';
      final s = DshSessionState.tryParse(raw)!;
      expect(s.todos.length, 1);
      expect(s.todos.single.content, 'B');
    });

    test('签名只跟会话/时间/运行态/条数有关，用来去重', () {
      const a = '{"session":"s1","running":true,"updatedAt":1,'
          '"todos":[{"content":"A","status":"pending"}]}';
      const b = '{"session":"s1","running":true,"updatedAt":2,'
          '"todos":[{"content":"A","status":"pending"}]}';
      expect(
        DshSessionState.tryParse(a)!.signature,
        isNot(DshSessionState.tryParse(b)!.signature),
      );
    });
  });

  group('整份计划刷新通知', () {
    test('applySteps 覆盖步骤并保留每条的完成状态', () async {
      final center = DshTaskCenter.instance;
      await center.applySteps(
        [
          DshTaskStep('列出任务列表')..state = DshTaskStepState.done,
          DshTaskStep('检查工作目录')..state = DshTaskStepState.active,
          DshTaskStep('演示状态切换')..state = DshTaskStepState.pending,
        ],
        title: '列出任务列表测试显示',
      );
      expect(center.title, '列出任务列表测试显示');
      expect(center.stepCount, 3);
      expect(center.doneCount, 1);
      expect(center.steps[1].state, DshTaskStepState.active);

      // 第二次 todo/write 把第一条也做完：整体覆盖，不留旧状态
      await center.applySteps(
        [
          DshTaskStep('列出任务列表')..state = DshTaskStepState.done,
          DshTaskStep('检查工作目录')..state = DshTaskStepState.done,
        ],
        title: '列出任务列表测试显示',
      );
      expect(center.stepCount, 2);
      expect(center.doneCount, 2);
    });

    test('空步骤不动通知', () async {
      final center = DshTaskCenter.instance;
      await center.applySteps([DshTaskStep('A')], title: 't');
      await center.applySteps(const []);
      expect(center.stepCount, 1);
    });
  });
}
