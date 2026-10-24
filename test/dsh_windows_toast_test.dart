// Windows dsh Toast 的纯 Dart 语义：
//   · 选项输入 1/2/3 映射到预置项，其他内容原样作为自定义回答；
//   · 事件 / 规格到原生 Map 的字段形状；
//   · 进度与完成 Toast 的标题/正文分工。
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/lab/dsh_windows_toast.dart';

void main() {
  group('resolveOptionReply', () {
    const options = ['准备', '执行', '收尾'];

    test('输入 1/2/3 取预置选项', () {
      expect(resolveOptionReply('1', options), '准备');
      expect(resolveOptionReply(' 2 ', options), '执行');
      expect(resolveOptionReply('3', options), '收尾');
    });

    test('越界数字和自定义文字原样保留', () {
      expect(resolveOptionReply('4', options), '4');
      expect(resolveOptionReply('0', options), '0');
      expect(resolveOptionReply('先看看日志', options), '先看看日志');
      expect(resolveOptionReply('  hello  ', options), 'hello');
    });

    test('空输入返回 null', () {
      expect(resolveOptionReply('', options), isNull);
      expect(resolveOptionReply('   ', options), isNull);
    });

    test('没有选项时数字也当自定义回答', () {
      expect(resolveOptionReply('2', const []), '2');
    });
  });

  group('parseToastAction', () {
    test('解析按钮参数（含单实例转发的 --l2a-action 前缀）', () {
      final parsed = parseToastAction(
        '--l2a-action=dsh_toast;k=option;tag=dsh-ask-9;group=dsh;v=2',
      );
      expect(parsed.key, 'option');
      expect(parsed.tag, 'dsh-ask-9');
      expect(parsed.group, 'dsh');
      expect(parsed.value, '2');
    });

    test('缺字段时给默认值', () {
      final parsed = parseToastAction('k=skip');
      expect(parsed.key, 'skip');
      expect(parsed.tag, isEmpty);
      expect(parsed.group, 'dsh');
      expect(parsed.value, isEmpty);
    });
  });

  group('DshWindowsToastEvent', () {
    test('解析原生回传的回复', () {
      final event = DshWindowsToastEvent.fromMap({
        'type': 'reply',
        'tag': 'dsh-ask-1',
        'group': 'dsh',
        'key': 'reply',
        'value': '2',
        'text': '2',
      })!;
      expect(event.isReply, isTrue);
      expect(event.tag, 'dsh-ask-1');
      expect(event.value, '2');
      expect(event.text, '2');
    });

    test('解析关闭原因', () {
      final event = DshWindowsToastEvent.fromMap({
        'type': 'dismissed',
        'tag': 'dsh-ask-1',
        'reason': 'timeout',
      })!;
      expect(event.isDismissed, isTrue);
      expect(event.reason, 'timeout');
    });

    test('坏数据返回 null', () {
      expect(DshWindowsToastEvent.fromMap(null), isNull);
      expect(DshWindowsToastEvent.fromMap('x'), isNull);
      expect(DshWindowsToastEvent.fromMap({'tag': 'x'}), isNull);
    });
  });

  group('DshWindowsToastSpec', () {
    test('按钮与进度字段按原生桥的命名下发', () {
      final spec = DshWindowsToastSpec(
        tag: 'dsh-task',
        title: '执行',
        body: '正在执行',
        detail: '✓ 准备',
        hasProgress: true,
        progress: 0.5,
        progressText: '1/2',
        input: true,
        inputPlaceholder: '输入回答',
        buttons: const [
          DshWindowsToastButton(
            key: 'reply',
            label: '发送',
            submit: true,
          ),
          DshWindowsToastButton(key: 'skip', label: '跳过'),
        ],
      );
      final map = spec.toMap();
      expect(map['tag'], 'dsh-task');
      expect(map['group'], 'dsh');
      expect(map['progress'], isTrue);
      expect(map['progressValue'], 0.5);
      expect(map['input'], isTrue);
      final buttons = map['buttons']! as List<Object?>;
      expect(buttons.length, 2);
      expect((buttons.first! as Map)['submit'], isTrue);
      expect((buttons.last! as Map)['key'], 'skip');
    });
  });
}
