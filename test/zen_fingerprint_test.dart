import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/zen/zen_fingerprint.dart';
import 'package:local2api/services/zen/zen_plan.dart';

List<String> namesOf(Map<String, dynamic> body) => [
  for (final t in (body['tools'] as List))
    t is Map<String, dynamic>
        ? '${(t['function'] as Map<String, dynamic>?)?['name'] ?? t['name']}'
        : '?',
];

void main() {
  group('免费档工具四件套', () {
    test('调用方没带工具时，按 chat 形状补齐四个自废诱饵', () {
      final body = <String, dynamic>{'model': 'x', 'messages': []};
      final rename = zenApplyFingerprint(body, ZenToolStyle.chat);

      expect(namesOf(body), ['bash', 'glob', 'grep', 'read']);
      expect(rename, isEmpty);
      expect(body['tool_choice'], 'none');
      final first = (body['tools'] as List).first as Map<String, dynamic>;
      expect(first['type'], 'function');
      expect(
        ((first['function'] as Map<String, dynamic>)['parameters']
            as Map<String, dynamic>)['type'],
        'object',
      );
    });

    test('Responses 线用扁平形状，tool_choice 是 auto', () {
      final body = <String, dynamic>{'model': 'x'};
      zenApplyFingerprint(body, ZenToolStyle.flat);
      expect(body['tool_choice'], 'auto');
      final first = (body['tools'] as List).first as Map<String, dynamic>;
      expect(first['name'], 'bash');
      expect(first['function'], isNull);
    });

    test('Messages 线用 input_schema，tool_choice 是 {type:none}', () {
      final body = <String, dynamic>{'model': 'x'};
      zenApplyFingerprint(body, ZenToolStyle.claude);
      expect(body['tool_choice'], {'type': 'none'});
      final first = (body['tools'] as List).first as Map<String, dynamic>;
      expect(first['input_schema'], isA<Map<String, dynamic>>());
    });

    test('大小写变体归一而不是并存：上游把 Bash + bash 当重复拒绝', () {
      final body = <String, dynamic>{
        'tools': [
          {
            'type': 'function',
            'function': {'name': 'Bash', 'parameters': {}},
          },
          {
            'type': 'function',
            'function': {'name': 'bash', 'parameters': {}},
          },
        ],
      };
      final rename = zenApplyFingerprint(body, ZenToolStyle.chat);

      expect(namesOf(body).where((n) => n == 'bash').length, 1);
      expect(rename, {'bash': 'Bash'});
    });

    test('有能顶替的真工具就提升它，不塞诱饵 —— 提升回来的调用才真能执行', () {
      final body = <String, dynamic>{
        'tools': [
          {
            'type': 'function',
            'function': {'name': 'pwsh', 'parameters': {}},
          },
        ],
      };
      final rename = zenApplyFingerprint(body, ZenToolStyle.chat);

      expect(namesOf(body), containsAll(['bash', 'glob', 'grep', 'read']));
      expect(namesOf(body), isNot(contains('pwsh')));
      expect(rename['bash'], 'pwsh');
      // 只有没得顶替的槽位才有诱饵：bash 被 pwsh 顶了，就只剩三个诱饵。
      expect((body['tools'] as List).length, 4);
    });

    test('调用方已经带齐四件套时原样不动', () {
      final body = <String, dynamic>{
        'tools': [
          {
            'type': 'function',
            'function': {'name': 'bash', 'parameters': {}},
          },
          {
            'type': 'function',
            'function': {'name': 'glob', 'parameters': {}},
          },
          {
            'type': 'function',
            'function': {'name': 'grep', 'parameters': {}},
          },
          {
            'type': 'function',
            'function': {'name': 'read', 'parameters': {}},
          },
          {
            'type': 'function',
            'function': {'name': 'my_tool', 'parameters': {}},
          },
        ],
        'tool_choice': 'required',
      };
      final before = namesOf(body);
      final rename = zenApplyFingerprint(body, ZenToolStyle.chat);

      expect(namesOf(body), before);
      expect(rename, isEmpty);
      expect(body['tool_choice'], 'required');
    });

    test('改名表用来把响应里的工具名还原回调用方的拼写', () {
      final rename = {'bash': 'RunShell'};
      expect(zenRestoreToolName('bash', rename), 'RunShell');
      expect(zenRestoreToolName('glob', rename), 'glob');
    });

    test('chat 流式透传遇到工具改名时必须过转译器，否则 unknown tool', () {
      final upstream = Upstream(
        id: 'zen',
        name: 'Zen',
        baseUrl: 'https://opencode.ai/zen/v1',
        models: [ModelEntry(publicName: 'zen-free', target: 'zen-free')],
      );
      Map<String, dynamic> body(List<Map<String, dynamic>> tools) => {
        'model': 'zen-free',
        'stream': true,
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
        'tools': tools,
      };

      final pwsh = zenPlan(
        upstream: upstream,
        lane: 'zen-free',
        publicName: 'zen-free',
        requestPath: '/v1/chat/completions',
        clientJson: body([
          {
            'type': 'function',
            'function': {'name': 'pwsh', 'parameters': {}},
          },
        ]),
      );
      // pwsh 被提升成 bash：回来的 tool_calls 必须能还原成 pwsh。
      expect(pwsh?.translator, isNotNull);

      final bash = zenPlan(
        upstream: upstream,
        lane: 'zen-free',
        publicName: 'zen-free',
        requestPath: '/v1/chat/completions',
        clientJson: body([
          {
            'type': 'function',
            'function': {'name': 'bash', 'parameters': {}},
          },
        ]),
      );
      // 没有改名时仍走字节透传（少一道转译，保持上游形状）。
      expect(bash?.translator, isNull);
    });

    test('未知字段跟着工具一起带过去，不因归一而被丢掉', () {
      final body = <String, dynamic>{
        'tools': [
          {
            'type': 'function',
            'strict': true,
            'function': {'name': 'Bash', 'parameters': {}},
          },
        ],
      };
      zenApplyFingerprint(body, ZenToolStyle.chat);
      final tool = (body['tools'] as List).first as Map<String, dynamic>;
      expect(tool['strict'], isTrue);
      expect((tool['function'] as Map<String, dynamic>)['name'], 'bash');
    });
  });
}
