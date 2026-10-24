import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/zen/zen_convert.dart';
import 'package:local2api/services/zen/zen_protocol.dart';

Map<String, dynamic> chat(
  List<Map<String, dynamic>> messages, {
  Map<String, dynamic>? extra,
}) => {
  'model': 'public-name',
  'messages': messages,
  ...?extra,
};

void main() {
  group('出站体：chat 线', () {
    test('只改写 model，其余字段原样带走', () {
      final body = zenBuildBody(
        wire: ZenWire.chat,
        lane: 'space-bunny-free',
        clientJson: chat(
          [
            {'role': 'user', 'content': 'hi'},
          ],
          extra: {'temperature': 0.3, 'stream': true, 'max_tokens': 64},
        ),
      );
      expect(body['model'], 'space-bunny-free');
      expect(body['temperature'], 0.3);
      expect(body['stream'], isTrue);
      expect(body['max_tokens'], 64);
    });

    test('客户端要非流式也强制上游流式 —— 指纹门只放行 stream:true', () {
      // 2026-10 实测：stream:false 时除 space-bunny-free 外，每条免费车道
      // 都是 403 FreeTierError；换回 true 全部 200。
      final body = zenBuildBody(
        wire: ZenWire.chat,
        lane: 'mimo-v2.6-flash-free',
        clientJson: chat([
          {'role': 'user', 'content': 'hi'},
        ], extra: {'stream': false}),
      );
      expect(body['stream'], isTrue);
    });

    test('chat 线绝不带 stream_options —— 官方客户端不发这个字段', () {
      // 回归守门：zen-gate 的 zen 车道 body 只有 {"model", "stream": true, …}
      // （internal/lane/client.go 的 buildBody 全函数、internal/lane/probe.go），
      // 只有带账号凭据的 WorkBuddy 渠道才写 stream_options
      // （internal/lane/workbuddy.go:217）。我方曾经强制写
      // stream_options:{include_usage:true}，这是与真实客户端唯一确定的
      // body 形状偏差，也是最可能的 403 触发点。
      final bare = zenBuildBody(
        wire: ZenWire.chat,
        lane: 'mimo-v2.6-flash-free',
        clientJson: chat([
          {'role': 'user', 'content': 'hi'},
        ], extra: {'stream': true}),
      );
      expect(bare.containsKey('stream_options'), isFalse);
      expect(bare['stream'], isTrue, reason: '删掉 stream_options 不能顺手删掉 stream');

      // 客户端自己带进来的也要摘掉：OpenAI SDK 传 stream_options 很常见，
      // 原样透传等于把刚修掉的形状偏差又还给上游。
      final fromClient = zenBuildBody(
        wire: ZenWire.chat,
        lane: 'space-bunny-free',
        clientJson: chat([
          {'role': 'user', 'content': 'hi'},
        ], extra: {
          'stream': true,
          'stream_options': {'include_usage': true},
        }),
      );
      expect(fromClient.containsKey('stream_options'), isFalse);
      // 其余字段仍然原样透传，摘的只有这一个。
      expect(fromClient['model'], 'space-bunny-free');
      expect(fromClient['stream'], isTrue);
    });

    test('另外两条线同样强制流式，也不带 chat 独有的 stream_options', () {
      final responses = zenBuildBody(
        wire: ZenWire.responses,
        lane: 'muse-spark-1.3-contributor-free',
        clientJson: chat([
          {'role': 'user', 'content': 'hi'},
        ]),
      );
      expect(responses['stream'], isTrue);
      expect(responses.containsKey('stream_options'), isFalse);

      final messages = zenBuildBody(
        wire: ZenWire.messages,
        lane: 'union-alpha',
        clientJson: chat([
          {'role': 'user', 'content': 'hi'},
        ]),
      );
      expect(messages['stream'], isTrue);
      expect(messages.containsKey('stream_options'), isFalse);
    });
  });

  group('出站体：Responses 线', () {
    test('system 变 instructions，user 变 input items，max_tokens 换名', () {
      final body = zenBuildBody(
        wire: ZenWire.responses,
        lane: 'muse-spark-1.3-contributor-free',
        clientJson: chat(
          [
            {'role': 'system', 'content': 'be nice'},
            {'role': 'user', 'content': 'hello'},
            {'role': 'assistant', 'content': 'hi'},
            {'role': 'user', 'content': 'again'},
          ],
          extra: {'max_tokens': 128},
        ),
      );
      expect(body['instructions'], 'be nice');
      expect(body['max_output_tokens'], 128);
      expect(body.containsKey('max_tokens'), isFalse);
      expect(body['store'], isFalse);
      expect(body['model'], 'muse-spark-1.3-contributor-free');

      final input = body['input'] as List;
      expect(input.length, 3);
      expect(
        (input[0] as Map<String, dynamic>)['content'],
        [{'type': 'input_text', 'text': 'hello'}],
      );
      expect(
        (input[1] as Map<String, dynamic>)['content'],
        [{'type': 'output_text', 'text': 'hi'}],
      );
    });

    test('工具从嵌套 function 形状改成扁平形状', () {
      final body = zenBuildBody(
        wire: ZenWire.responses,
        lane: 'muse-spark-1.2-contributor-free',
        clientJson: chat(
          [
            {'role': 'user', 'content': 'x'},
          ],
          extra: {
            'tools': [
              {
                'type': 'function',
                'function': {
                  'name': 'lookup',
                  'description': 'look it up',
                  'parameters': {'type': 'object'},
                },
              },
            ],
          },
        ),
      );
      final tool = (body['tools'] as List).single as Map<String, dynamic>;
      expect(tool['name'], 'lookup');
      expect(tool['description'], 'look it up');
      expect(tool['parameters'], {'type': 'object'});
      expect(tool['function'], isNull);
    });

    test('assistant 的 tool_calls 变成 function_call 项、tool 消息变成输出回填', () {
      final body = zenBuildBody(
        wire: ZenWire.responses,
        lane: 'muse-spark-1.3-contributor-free',
        clientJson: chat(
          [
            {'role': 'user', 'content': 'weather?'},
            {
              'role': 'assistant',
              'content': '',
              'tool_calls': [
                {
                  'id': 'call_1',
                  'type': 'function',
                  'function': {'name': 'get_weather', 'arguments': '{"city":"SF"}'},
                },
              ],
            },
            {'role': 'tool', 'tool_call_id': 'call_1', 'content': 'sunny'},
          ],
        ),
      );
      final input = body['input'] as List;
      final call = input[1] as Map<String, dynamic>;
      expect(call['type'], 'function_call');
      expect(call['call_id'], 'call_1');
      expect(call['arguments'], '{"city":"SF"}');
      final output = input[2] as Map<String, dynamic>;
      expect(output['type'], 'function_call_output');
      expect(output['output'], 'sunny');
    });
  });

  group('出站体：Messages 线', () {
    test('system 单独成字段，content 变 blocks，max_tokens 必填', () {
      final body = zenBuildBody(
        wire: ZenWire.messages,
        lane: 'union-alpha',
        clientJson: chat([
          {'role': 'system', 'content': 'be terse'},
          {'role': 'user', 'content': 'hi'},
        ]),
      );
      expect(body['system'], 'be terse');
      expect(body['anthropic_version'], '2023-06-01');
      // 客户端没给 max_tokens：Anthropic 线把它当必填，不能不带。
      expect(body['max_tokens'], kZenDefaultMaxTokens);
      final first = (body['messages'] as List).first as Map<String, dynamic>;
      expect(first['role'], 'user');
      expect(
        first['content'],
        [
          {'type': 'text', 'text': 'hi'},
        ],
      );
    });

    test('连续同角色的轮次合并，工具结果排在自己那条 user 轮里', () {
      final body = zenBuildBody(
        wire: ZenWire.messages,
        lane: 'union-alpha',
        clientJson: chat([
          {'role': 'user', 'content': 'a'},
          {'role': 'user', 'content': 'b'},
          {
            'role': 'assistant',
            'content': 'calling',
            'tool_calls': [
              {
                'id': 'c1',
                'function': {'name': 'f', 'arguments': '{"k":1}'},
              },
            ],
          },
          {'role': 'tool', 'tool_call_id': 'c1', 'content': 'done'},
        ]),
      );
      final messages = body['messages'] as List;
      expect(messages.length, 3);
      expect((messages[0] as Map)['content'].length, 2);

      final assistant = messages[1] as Map<String, dynamic>;
      final blocks = assistant['content'] as List;
      final toolUse = blocks[1] as Map<String, dynamic>;
      expect(toolUse['type'], 'tool_use');
      // Anthropic 的 input 是对象，不是 OpenAI 那个 JSON 字符串。
      expect(toolUse['input'], {'k': 1});

      final followUp = messages[2] as Map<String, dynamic>;
      expect(followUp['role'], 'user');
      final result = (followUp['content'] as List).first
          as Map<String, dynamic>;
      expect(result['type'], 'tool_result');
      expect(result['tool_use_id'], 'c1');
    });

    test('data: URL 的图片拆成 base64 source', () {
      final body = zenBuildBody(
        wire: ZenWire.messages,
        lane: 'union-alpha',
        clientJson: chat([
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'what is this'},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/png;base64,AAAA'},
              },
            ],
          },
        ]),
      );
      final blocks = ((body['messages'] as List).first
          as Map<String, dynamic>)['content'] as List;
      final image = blocks[1] as Map<String, dynamic>;
      expect(image['type'], 'image');
      expect(
        image['source'],
        {'type': 'base64', 'media_type': 'image/png', 'data': 'AAAA'},
      );
    });

    test('解不开的 arguments 落成空对象而不是字符串', () {
      final body = zenBuildBody(
        wire: ZenWire.messages,
        lane: 'union-alpha',
        clientJson: chat([
          {
            'role': 'assistant',
            'tool_calls': [
              {
                'id': 'c1',
                'function': {'name': 'f', 'arguments': 'not json'},
              },
            ],
          },
        ]),
      );
      final block = ((body['messages'] as List).first
          as Map<String, dynamic>)['content'][0] as Map<String, dynamic>;
      expect(block['input'], isEmpty);
    });
  });
}
