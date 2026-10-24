// 实验室通知 / 任务模式的逻辑回归（非安卓宿主也能跑：通知桥在非安卓上
// 整条退化成空实现，所以这里断言的是「状态机 + 标记解析」这部分）。
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/android_notifications.dart';
import 'package:local2api/services/lab/dsh_config.dart';
import 'package:local2api/services/lab/dsh_task_center.dart';

void main() {
  group('L2A 标记解析', () {
    test('认得出四种标记', () {
      expect(parseTaskMarker('L2A-PLAN: 第一步 | 第二步'),
          ('PLAN', '第一步 | 第二步'));
      expect(parseTaskMarker('L2A-STEP: 装依赖'), ('STEP', '装依赖'));
      expect(parseTaskMarker('L2A-STEP-DONE: 装依赖'), ('STEP-DONE', '装依赖'));
      expect(parseTaskMarker('L2A-ASK: 用哪个分支？'), ('ASK', '用哪个分支？'));
      expect(parseTaskMarker('L2A-RESULT: 跑完了'), ('RESULT', '跑完了'));
      expect(parseTaskMarker('L2A-RESULT-END:'), ('RESULT-END', ''));
      // 提示词里的写法不带冒号，必须也能认出来
      expect(parseTaskMarker('L2A-RESULT-END'), ('RESULT-END', ''));
    });

    test('剥掉 ANSI 颜色码后仍能认', () {
      const line = '\x1B[36mL2A-STEP: 编译\x1B[0m';
      expect(parseTaskMarker(line), ('STEP', '编译'));
    });

    test('正文中提到这几个词不算标记（必须行首）', () {
      expect(parseTaskMarker('然后输出 L2A-STEP: xxx'), isNull);
      expect(parseTaskMarker('L2A_STEP: 下划线不算'), isNull);
      expect(parseTaskMarker('L2A-'), isNull);
    });
  });

  group('任务步进器', () {
    test('start → advance 的状态推进', () async {
      final center = DshTaskCenter.instance;
      await center.start(
        title: '测试任务',
        status: '开工',
        steps: const ['取代码', '装依赖', '跑测试'],
      );
      expect(center.hasTask, isTrue);
      expect(center.stepCount, 3);
      expect(center.doneCount, 0);
      expect(center.steps.first.state, DshTaskStepState.active);

      await center.advance();
      expect(center.doneCount, 1);
      expect(center.steps[1].state, DshTaskStepState.active);

      await center.advance();
      await center.advance();
      expect(center.doneCount, 3);
    });

    test('setSteps 保住已完成的进度', () async {
      final center = DshTaskCenter.instance;
      await center.start(title: '任务', steps: const ['A', 'B']);
      await center.advance();
      await center.setSteps(const ['A', 'B', 'C', 'D']);
      expect(center.stepCount, 4);
      expect(center.doneCount, 1);
      expect(center.steps[0].state, DshTaskStepState.done);
      expect(center.steps[1].state, DshTaskStepState.active);
    });

    test('finish / fail 落到终态', () async {
      final center = DshTaskCenter.instance;
      await center.start(title: '任务', steps: const ['A']);
      await center.finish(text: '好了');
      expect(center.outcome, DshTaskOutcome.succeeded);
      await center.start(title: '任务2', steps: const ['A']);
      await center.fail('炸了');
      expect(center.outcome, DshTaskOutcome.failed);
      expect(center.lastError, '炸了');
    });

    test('非安卓上 cancelTask 也能把状态收干净', () async {
      final center = DshTaskCenter.instance;
      await center.start(title: '任务', steps: const ['A']);
      await center.cancelTask();
      expect(center.outcome, DshTaskOutcome.cancelled);
    });
  });

  group('通知桥（非安卓退化）', () {
    test('不支持的平台一律空结果', () async {
      expect(AndroidNotifications.isSupported, isFalse);
      expect(await AndroidNotifications.hasPermission(), isFalse);
      expect(await AndroidNotifications.canPostPromoted(), isFalse);
      final result = await AndroidNotifications.show(
        const AndroidNotificationSpec(id: 1, title: 'x'),
      );
      expect(result.posted, isFalse);
      expect(await AndroidNotifications.drainPending(), isEmpty);
      expect(await AndroidNotifications.isIgnoringBatteryOptimizations(),
          isNull);
    });

    test('通知规格能编出原生要的字段', () {
      final map = AndroidNotificationSpec(
        id: 7200,
        title: '任务',
        text: '正在跑',
        ongoing: true,
        promoted: true,
        progress: 100,
        progressMax: 300,
        segments: const [
          AndroidProgressSegment(100, color: 0xFF34A853),
          AndroidProgressSegment(200),
        ],
        points: const [AndroidProgressPoint(100, color: 0xFF4C6FFF)],
        actions: const [
          AndroidNotificationAction(key: 'reply', title: '回复', reply: true),
        ],
      ).toMap();
      expect(map['id'], 7200);
      expect(map['ongoing'], isTrue);
      expect(map['promoted'], isTrue);
      expect(map['segments'], [
        {'length': 100, 'color': 0xFF34A853},
        {'length': 200},
      ]);
      expect(map['points'], [
        {'position': 100, 'color': 0xFF4C6FFF},
      ]);
      expect(map['actions'], [
        {'key': 'reply', 'title': '回复', 'reply': true},
      ]);
    });
  });
}
