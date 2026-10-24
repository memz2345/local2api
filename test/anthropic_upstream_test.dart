// Anthropic 上游适配层回归：
//   - chat.completions 请求体 → Messages 请求体的字段映射（system / tools /
//     tool_result / stream / max_tokens）；
//   - 鉴权头用 x-api-key + anthropic-version，不能把 Bedrock 的
//     anthropic_version 塞进 body；
//   - 地址栏输入归一化（域名补 https、空 scheme 当搜索词）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/anthropic/anthropic_upstream.dart';
import 'package:local2api/services/browser_controller.dart';

Upstream _upstream() => Upstream(
  id: 'deepseek-anthropic',
  name: 'DeepSeek',
  baseUrl: 'https://api.deepseek.com/anthropic',
  apiKey: 'sk-test',
  type: UpstreamType.anthropic,
);

Map<String, dynamic> _bodyOf(List<int> bytes) =>
    jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

void main() {
  test('Anthropic 上游模式：id / 默认地址 / 协议标记都认', () {
    expect(UpstreamTypeX.fromId('anthropic'), UpstreamType.anthropic);
    expect(UpstreamType.anthropic.id, 'anthropic');
    expect(UpstreamType.anthropic.speaksAnthropic, isTrue);
    expect(
      UpstreamType.anthropic.defaultBaseUrl,
      'https://api.deepseek.com/anthropic',
    );
  });

  test('chat.completions → Messages：system / tools / tool 结果都重新编码', () {
    final hop = buildAnthropicHop(
      upstream: _upstream(),
      lane: 'deepseek-v4-pro',
      publicName: 'deepseek',
      clientJson: {
        'model': 'deepseek',
        'stream': true,
        'max_tokens': 1024,
        'temperature': 0.3,
        'stop': ['END'],
        'messages': [
          {'role': 'system', 'content': '你是助手'},
          {'role': 'user', 'content': '查一下天气'},
          {
            'role': 'assistant',
            'content': null,
            'tool_calls': [
              {
                'id': 'call_1',
                'type': 'function',
                'function': {
                  'name': 'get_weather',
                  'arguments': '{"city":"北京"}',
                },
              },
            ],
          },
          {'role': 'tool', 'tool_call_id': 'call_1', 'content': '晴，26 度'},
        ],
        'tools': [
          {
            'type': 'function',
            'function': {
              'name': 'get_weather',
              'description': '查天气',
              'parameters': {
                'type': 'object',
                'properties': {
                  'city': {'type': 'string'},
                },
              },
            },
          },
        ],
      },
    );

    expect(hop.path, '/v1/messages');
    expect(hop.headers['x-api-key'], 'sk-test');
    expect(hop.headers['anthropic-version'], kAnthropicVersion);
    expect(hop.translator.stream, isTrue);

    final decoded = _bodyOf(hop.body);
    expect(decoded['model'], 'deepseek-v4-pro');
    expect(decoded['stream'], isTrue);
    expect(decoded['max_tokens'], 1024);
    expect(decoded['system'], '你是助手');
    expect(decoded['temperature'], 0.3);
    expect(decoded['stop_sequences'], ['END']);
    // Bedrock 专用字段不能带给官方 / DeepSeek。
    expect(decoded.containsKey('anthropic_version'), isFalse);

    final messages = decoded['messages'] as List;
    expect(messages.first['role'], 'user');
    expect(messages.last['role'], 'user');
    final toolResult =
        (messages.last['content'] as List).first as Map<String, dynamic>;
    expect(toolResult['type'], 'tool_result');
    expect(toolResult['tool_use_id'], 'call_1');

    final tools = decoded['tools'] as List;
    expect((tools.first as Map)['input_schema'], isA<Map>());
  });

  test('客户端要非流式时，上游体也按非流式发', () {
    final hop = buildAnthropicHop(
      upstream: _upstream(),
      lane: 'deepseek-flash',
      publicName: 'deepseek',
      clientJson: {
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      },
    );
    final decoded = _bodyOf(hop.body);
    expect(decoded['stream'], isFalse);
    expect(decoded['max_tokens'], isA<int>());
    expect(hop.translator.stream, isFalse);
  });

  test('地址栏输入归一化', () {
    expect(normalizeBrowserInput('example.com'), 'https://example.com');
    expect(normalizeBrowserInput('http://a.b/c'), 'http://a.b/c');
    expect(normalizeBrowserInput('127.0.0.1:8000'), 'https://127.0.0.1:8000');
    expect(
      normalizeBrowserInput('silly tavern'),
      startsWith('https://www.bing.com/search?q='),
    );
    expect(normalizeBrowserInput('  '), '');
  });
}
