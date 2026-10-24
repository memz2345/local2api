/// 出站体转换：客户端只会说 OpenAI chat 形状，但 Zen 按模型把请求分流到
/// Responses / Anthropic Messages 两条线上，所以要按线协议重新编码。
///
/// 字段表刻意保持最小 —— 只带参考实现在这两条线上验证过的字段，
/// 多余的（temperature、presence_penalty 之类）不带：这两条网关对未知
/// 字段的容忍度没测过，少带一个字段比多带一个稳。
///
/// 同一条原则也管住 `stream_options`：真实 opencode 客户端从不发它，所以
/// 三条线一律不发，客户端自己带进来的也在 chat 线上被摘掉（见 zenBuildBody）。
library;

import 'dart:convert';

import '../../models/thinking_level.dart';
import 'zen_protocol.dart';

/// 客户端没给 max_tokens 时的输出预算。Messages 线把 max_tokens 当必填，
/// 不能不带；数值沿用参考实现的默认档。
const int kZenDefaultMaxTokens = 32768;

/// 上游**永远**走流式 —— 免费档指纹门只放行 `body.stream == true` 的请求。
///
/// 2026-10 实测：同一组指纹头（Bearer public + opencode UA + x-opencode-*
/// 三件套 + tools 四件套）下，把 stream 改成 false，除 space-bunny-free
/// 之外的每一条免费车道都是 403 FreeTierError「free tier can only be used
/// from within OpenCode」；换回 true 立刻 200（big-pickle、
/// mimo-v2.6-flash-free、longcat-2.5-preview-free、step-5-preview-free、
/// ling-3.1-flash-free、nemotron-3-ultra-free、nemotron-3.5-lightning-free
/// 都验过；其中几条后来已不在兜底目录里，见 builtin_profiles.dart 的
/// [kZenFreeLanes]，但「必须流式」这条结论对整条车道都成立）。所以「非流式」
/// 只能是我们对客户端的**呈现**：上游照旧吐 SSE，由转译器攒完再回灌成一份
/// chat.completion（见 zen_stream.dart）。
const bool kZenUpstreamAlwaysStreams = true;

const String kZenAnthropicVersion = '2023-06-01';

String _textOf(Object? content) {
  if (content == null) return '';
  if (content is String) return content;
  if (content is List) {
    return content
        .whereType<Map<String, dynamic>>()
        .map((p) => p['text'] is String ? p['text'] as String : '')
        .join();
  }
  return '$content';
}

Map<String, dynamic>? _functionOfTool(Map<String, dynamic> tool) {
  final fn = tool['function'];
  return fn is Map<String, dynamic> ? fn : null;
}

/// chat 的嵌套 tools → 目标线协议的 tools。
List<Map<String, dynamic>> _convertTools(Object? raw, ZenWire wire) =>
    switch (raw) {
      List list => [
        for (final t in list.whereType<Map<String, dynamic>>())
          ..._oneTool(t, wire),
      ],
      _ => const [],
    };

List<Map<String, dynamic>> _oneTool(Map<String, dynamic> tool, ZenWire wire) {
  final fn = _functionOfTool(tool);
  final name = (fn?['name'] ?? tool['name']) as String? ?? '';
  if (name.isEmpty) return const [];
  final description = (fn?['description'] ?? tool['description']) as String?;
  final parameters =
      fn?['parameters'] ?? tool['parameters'] ?? tool['input_schema'];
  final schema = parameters is Map<String, dynamic>
      ? parameters
      : const <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{},
        };
  final base = <String, dynamic>{'name': name, 'description': ?description};
  return [
    switch (wire) {
      ZenWire.responses => {...base, 'type': 'function', 'parameters': schema},
      ZenWire.messages => {...base, 'input_schema': schema},
      _ => {
        'type': 'function',
        'function': {...base, 'parameters': schema},
      },
    },
  ];
}

/// chat 的 content 数组 → Responses 的 input items。返回可生长列表。
List<Map<String, dynamic>> _responsesParts(Object? content) {
  if (content is! List) {
    final text = _textOf(content);
    return text.isEmpty
        ? <Map<String, dynamic>>[]
        : [
            {'type': 'input_text', 'text': text},
          ];
  }
  return [
    for (final part in content.whereType<Map<String, dynamic>>())
      ..._responsesPart(part),
  ];
}

List<Map<String, dynamic>> _responsesPart(Map<String, dynamic> part) {
  if (part['type'] == 'image_url' && part['image_url'] is Map) {
    final url = (part['image_url'] as Map)['url'];
    return url == null || '$url'.isEmpty
        ? const []
        : [
            {'type': 'input_image', 'image_url': url},
          ];
  }
  final text = part['text'] is String ? part['text'] as String : '';
  return text.isEmpty
      ? const []
      : [
          {'type': 'input_text', 'text': text},
        ];
}

/// chat 的 content → Anthropic 的 content blocks。
/// 返回可生长列表：调用方要在后面追加 tool_use 块。
List<Map<String, dynamic>> _claudeParts(Object? content) {
  if (content is! List) {
    final text = _textOf(content);
    return text.isEmpty
        ? <Map<String, dynamic>>[]
        : [
            {'type': 'text', 'text': text},
          ];
  }
  return [
    for (final part in content.whereType<Map<String, dynamic>>())
      ..._claudePart(part),
  ];
}

/// Anthropic 的 tool_use.input 是对象，OpenAI 的 function.arguments 是 JSON
/// 字符串；解不开就当空对象发，不拿字符串顶上去（上游会当类型错误拒）。
Map<String, dynamic> _claudeToolInput(Object? arguments) {
  if (arguments is Map<String, dynamic>) return arguments;
  final text = '${arguments ?? ''}'.trim();
  if (text.isEmpty) return const <String, dynamic>{};
  try {
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic>
        ? decoded
        : const <String, dynamic>{};
  } on FormatException {
    return const <String, dynamic>{};
  }
}

List<Map<String, dynamic>> _claudePart(Map<String, dynamic> part) {
  if (part['type'] == 'image_url' && part['image_url'] is Map) {
    final url = '${(part['image_url'] as Map)['url'] ?? ''}';
    if (url.isEmpty) return const [];
    // data: URL 拆成 base64 source，其余按 url source 交给上游自己取。
    if (url.startsWith('data:')) {
      final rest = url.substring(5);
      final semi = rest.indexOf(';base64,');
      if (semi >= 0) {
        return [
          {
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': rest.substring(0, semi),
              'data': rest.substring(semi + 8),
            },
          },
        ];
      }
    }
    return [
      {
        'type': 'image',
        'source': {'type': 'url', 'url': url},
      },
    ];
  }
  final text = part['text'] is String ? part['text'] as String : '';
  return text.isEmpty
      ? const []
      : [
          {'type': 'text', 'text': text},
        ];
}

/// 客户端显式给的输出预算（0 = 没给）。
int _clientMaxTokens(Map<String, dynamic> clientJson) {
  final v = clientJson['max_tokens'] ?? clientJson['max_output_tokens'];
  return v is num && v > 0 ? v.toInt() : 0;
}

/// 这一跳实际带多少 `max_tokens`。
///
/// 有思考档位时按档位给预算（精简/均衡**硬钳制**，连客户端显式预算一起压；
/// 深思尊重客户端/模型上限）；没有档位才完全听客户端的（见
/// [thinking_level.dart] 的实测结论与 zen-gate 同款语义）。
int _maxTokensOf(
  Map<String, dynamic> clientJson, {
  ThinkingLevel? level,
  int capacity = 0,
}) {
  final asked = _clientMaxTokens(clientJson);
  if (level == null) return asked > 0 ? asked : kZenDefaultMaxTokens;
  return thinkingBudget(
    level,
    capacity: capacity,
    fallback: kZenDefaultMaxTokens,
    requested: asked,
  );
}

/// 把一份 OpenAI chat 请求体改成这条车道实际要发的样子。
/// chat 线改写 model、强制 stream，并摘掉 stream_options；其余字段原样透传。
Map<String, dynamic> zenBuildBody({
  required ZenWire wire,
  required String lane,
  required Map<String, dynamic> clientJson,
  ThinkingLevel? level,
  int capacity = 0,
}) {
  // 调用方没算就自己从请求体里读（reasoning_effort / thinking / 模型名后缀）。
  final effectiveLevel = level ?? thinkingLevelOf(clientJson);
  final maxTokens = _maxTokensOf(
    clientJson,
    level: effectiveLevel,
    capacity: capacity,
  );
  final messages = [
    if (clientJson['messages'] is List) ...clientJson['messages'] as List,
  ].whereType<Map<String, dynamic>>();

  switch (wire) {
    case ZenWire.chat:
      final body = Map<String, dynamic>.of(clientJson)
        ..['model'] = lane
        // 指纹门只认流式：客户端要什么都改不成 false（见
        // [kZenUpstreamAlwaysStreams]），非流式由转译器回灌成整份 JSON。
        ..['stream'] = true;
      // 这里**刻意不写 `stream_options: {include_usage: true}`**。
      //
      // zen-gate 的 zen 车道 body 只有 `{"model": base, "stream": true, …}`：
      // `internal/lane/client.go` 的 buildBody 全函数与 `internal/lane/probe.go`
      // 都不带这个字段，只有 WorkBuddy 那条**带账号凭据**的渠道带
      // （`internal/lane/workbuddy.go:217`）。多带一个官方客户端不会发的字段，
      // 等于给指纹门多递一个「这不是 opencode」的把柄 —— 这是我方与真实客户端
      // 之间唯一确定的 body 形状偏差，也是 403 最可能的触发点。
      //
      // 代价是上游可能一帧 usage 都不回。这条路径**优雅降级**：usage 只从 SSE
      // 帧里取（zen_stream.dart 的 _mergeUsage），一帧都没给时 usageDoc 返回
      // null、整份 JSON 里不带 `usage` 键、代理跳过记账，全程不抛异常。
      body.remove('stream_options');
      // 思考档位在这条线上只能靠输出预算落地（上游忽略 reasoning_effort）。
      // 只在「客户端给了档位或自己给了预算」时才写 —— 一律写死会替上游
      // 定一个它本来没有的上限。
      if (effectiveLevel != null || _clientMaxTokens(clientJson) > 0) {
        body['max_tokens'] = maxTokens;
      }
      return body;

    case ZenWire.responses:
      final input = <Map<String, dynamic>>[];
      final system = <String>[];
      for (final m in messages) {
        switch (m['role']) {
          case 'system':
          case 'developer':
            final text = _textOf(m['content']);
            if (text.isNotEmpty) system.add(text);
          case 'assistant':
            final text = _textOf(m['content']);
            if (text.trim().isNotEmpty) {
              input.add({
                'role': 'assistant',
                'content': [
                  {'type': 'output_text', 'text': text},
                ],
              });
            }
            final calls = m['tool_calls'];
            if (calls is List) {
              for (final c in calls.whereType<Map<String, dynamic>>()) {
                final fn = _functionOfTool(c) ?? c;
                input.add({
                  'type': 'function_call',
                  'call_id': c['id'] ?? fn['id'],
                  'name': fn['name'],
                  'arguments': '${fn['arguments'] ?? '{}'}',
                });
              }
            }
          case 'tool':
            input.add({
              'type': 'function_call_output',
              'call_id': m['tool_call_id'],
              'output': _textOf(m['content']),
            });
          default:
            final parts = _responsesParts(m['content']);
            if (parts.isNotEmpty) {
              input.add({'role': m['role'] ?? 'user', 'content': parts});
            }
        }
      }
      final tools = _convertTools(clientJson['tools'], wire);
      return {
        'model': lane,
        // 这两条线同样只对流式请求放行。stream_options 是 OpenAI chat 独有的
        // 字段，Responses / Anthropic 根本不认（它们的 usage 本来就随帧给），
        // 而 chat 线现在也不带了 —— 三条线的 body 形状统一向真实客户端看齐。
        'stream': true,
        'input': input,
        'max_output_tokens': maxTokens,
        'store': false,
        if (system.isNotEmpty) 'instructions': system.join('\n\n'),
        if (tools.isNotEmpty) 'tools': tools,
      };

    case ZenWire.messages:
    case ZenWire.systemone:
      // systemone 是判定模型，不接受聊天请求；当成 messages 线只是不让
      // 调用方拿到一个未处理的分支，真实车道目录已在 zenFilterUsableLanes 里剔除它。
      final system = <String>[];
      final blocks = <List<Map<String, dynamic>>>[];
      final roles = <String>[];
      void push(String role, List<Map<String, dynamic>> parts) {
        if (parts.isEmpty) return;
        if (roles.isNotEmpty && roles.last == role) {
          blocks[blocks.length - 1].addAll(parts);
        } else {
          roles.add(role);
          blocks.add(List.of(parts));
        }
      }

      for (final m in messages) {
        final role = m['role'];
        if (role == 'system' || role == 'developer') {
          final text = _textOf(m['content']);
          if (text.isNotEmpty) system.add(text);
          continue;
        }
        if (role == 'assistant') {
          final parts = _claudeParts(m['content']);
          final calls = m['tool_calls'];
          if (calls is List) {
            for (final c in calls.whereType<Map<String, dynamic>>()) {
              final fn = _functionOfTool(c) ?? c;
              parts.add({
                'type': 'tool_use',
                'id': c['id'] ?? fn['id'],
                'name': fn['name'],
                'input': _claudeToolInput(fn['arguments']),
              });
            }
          }
          push('assistant', parts);
          continue;
        }
        if (role == 'tool') {
          push('user', [
            {
              'type': 'tool_result',
              'tool_use_id': m['tool_call_id'],
              'content': _textOf(m['content']),
            },
          ]);
          continue;
        }
        push('user', _claudeParts(m['content']));
      }
      final tools = _convertTools(clientJson['tools'], wire);
      final converted = [
        for (var i = 0; i < blocks.length; i++)
          {'role': roles[i], 'content': blocks[i]},
      ];
      return {
        'model': lane,
        'stream': true,
        'messages': converted,
        'max_tokens': maxTokens,
        'anthropic_version': kZenAnthropicVersion,
        if (system.isNotEmpty) 'system': system.join('\n\n'),
        if (tools.isNotEmpty) 'tools': tools,
      };
  }
}
