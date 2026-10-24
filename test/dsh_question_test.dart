// test/dsh_question_test.dart
//
// watcher 产出的 question JSON：通知直接回复要用 callId / question id，
// 解析必须兼容旧版（只有 text/options）与新版的 items 批次。

import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/lab/dsh_question.dart';

void main() {
  test('解析 ask_user_question 的完整坐标', () {
    final q = DshQuestion.tryParse(<String, dynamic>{
      'text': '选哪个方案？',
      'options': ['A', 'B'],
      'id': 'q1',
      'callId': 'call-42',
      'items': [
        {
          'id': 'q1',
          'text': '选哪个方案？',
          'options': ['A', 'B'],
        },
        {'id': 'q2', 'text': '备注？', 'options': <String>[]},
      ],
    });

    expect(q, isNotNull);
    expect(q!.answerable, isTrue);
    expect(q.callId, 'call-42');
    expect(q.id, 'q1');
    expect(q.items, hasLength(2));
    expect(q.items.last.id, 'q2');
    expect(q.options, ['A', 'B']);
  });

  test('旧版只有 text/options 也能退化成单条问题', () {
    final q = DshQuestion.tryParse(<String, dynamic>{
      'text': '继续吗？',
      'options': ['继续'],
    });

    expect(q, isNotNull);
    expect(q!.answerable, isFalse, reason: '没有 callId 只能去 web 回答');
    expect(q.items, hasLength(1));
    expect(q.items.single.text, '继续吗？');
    expect(q.items.single.options, ['继续']);
  });

  test('审批类问题没有 callId：不可直接回复', () {
    final q = DshQuestion.tryParse(<String, dynamic>{
      'text': '需要你确认',
      'options': <String>[],
    });

    expect(q, isNotNull);
    expect(q!.answerable, isFalse);
  });
}
