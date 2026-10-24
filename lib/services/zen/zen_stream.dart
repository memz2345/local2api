import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'zen_fingerprint.dart';
import 'zen_protocol.dart';

/// 入站转译：把 Responses / Messages 两条线的响应回译成 OpenAI chat 的形状，
/// 让只认 chat.completions 的客户端不必知道上游按模型换了线协议。
///
/// 四条入站路径都要覆盖：
/// - 客户端要流式 + 上游给 SSE：逐帧边解边写（这是主路径）。
/// - 客户端要流式 + 上游把流式请求答成一整份 JSON：网关确实会这样，
///   所以判形态看 body 而不是 Content-Type；攒完再一次性回灌成 SSE。
/// - 客户端要非流式：只累积，最后拼一份 chat.completion。
/// - 上游 4xx/5xx：换成 OpenAI 的错误形状，别把 Anthropic 的错误体原样丢给客户端。
///
/// 整份文档的形状和 SSE 末帧的形状不一样（Responses 是 `output` items，
/// Anthropic 是 `content` blocks），所以是两条独立解码路径，不复用状态机。
class ZenTranslator {
  ZenTranslator({
    required this.wire,
    required this.rename,
    required this.model,
    required this.stream,
    required this.id,
    required this.createdSeconds,
  });

  final ZenWire wire;

  /// 送出拼写 → 调用方拼写，用来还原被归一 / 提升过的工具名。
  final Map<String, String> rename;

  /// 回给客户端的模型名（对外名，不是上游车道名）。
  final String model;

  /// 客户端这次要不要流式。
  final bool stream;

  final String id;
  final int createdSeconds;

  final StringBuffer _text = StringBuffer();
  final StringBuffer _reasoning = StringBuffer();
  final List<_ToolAcc> _tools = <_ToolAcc>[];

  /// provider 侧块标识（messages 线的 content_block.index、responses 线的
  /// output_index）→ 我们这侧的块类型与工具下标。
  final Map<String, _Block> _blocks = <String, _Block>{};
  final Map<String, dynamic> _usage = <String, dynamic>{};

  /// 上游这次有没有提过缓存字段。没提过就别往客户端编「未命中」，
  /// 保持 usage 形状与上游一致（客户端可能对字段做严格校验）。
  bool _sawCacheTokens = false;
  final StringBuffer _jsonBuf = StringBuffer();

  String? _finishReason;
  bool _roleSent = false;
  bool _sawContent = false;
  bool _wrote = false;
  ZenFailure? _error;

  /// 非 null 表示正在边解边写 SSE；null 表示只累积不写。
  HttpResponse? _sseOut;

  static const String _done = 'data: [DONE]\n\n';

  // --------------------------------------------------------------- relay

  Future<void> relay(HttpClientResponse upstream, HttpResponse out) async {
    final status = upstream.statusCode;
    final lines = utf8.decoder.bind(upstream).transform(const LineSplitter());

    if (status >= 400) {
      _fail(
        zenClassify(
          status,
          await lines.join('\n'),
          retryAfterSec: _retryAfter(upstream),
        ),
      );
      await _writeError(out, status);
      return;
    }

    if (!stream) {
      _feedAny(await lines.join('\n'));
      await _writeJson(out);
      return;
    }

    // 流式：首行定形态。空行与注释帧不表态，等到真有内容为止。
    var shape = _Shape.unknown;
    await for (final line in lines) {
      if (shape == _Shape.unknown) {
        final trimmed = line.trimLeft();
        if (trimmed.isEmpty || trimmed.startsWith(':')) continue;
        shape = _isSseLine(trimmed) ? _Shape.sse : _Shape.json;
        if (shape == _Shape.sse) {
          _commitSse(out);
          _sseOut = out;
        }
      }
      if (shape == _Shape.json) {
        _jsonBuf.writeln(line);
        continue;
      }
      _handleSseLine(line);
      if (_wrote) {
        _wrote = false;
        await out.flush();
      }
    }

    if (shape == _Shape.unknown) {
      // 200 但一个字节都没给：按错误回，别让客户端对着空响应挂住。
      _fail(const ZenFailure(ZenFailureCode.empty, status: 200));
      await _writeError(out, HttpStatus.badGateway);
      return;
    }

    if (shape == _Shape.json) {
      // 上游用一整份 JSON 回答了流式请求：攒完再回灌成 SSE。
      _feedDoc(_decode(_jsonBuf.toString()));
      await _writeErrorOrReplay(out);
      return;
    }
    await _finishSse(out);
  }

  Future<void> _writeErrorOrReplay(HttpResponse out) async {
    if (_error != null && !_sawContent) {
      await _writeError(out, HttpStatus.badGateway);
      return;
    }
    _commitSse(out);
    final delta = <String, dynamic>{'role': 'assistant'};
    if (_reasoning.isNotEmpty) {
      delta['reasoning_content'] = _reasoning.toString();
    }
    if (_text.isNotEmpty) delta['content'] = _text.toString();
    if (_tools.isNotEmpty) {
      delta['tool_calls'] = [
        for (var i = 0; i < _tools.length; i++)
          {
            'index': i,
            'id': _tools[i].id,
            'type': 'function',
            'function': {
              'name': _tools[i].name,
              'arguments': _tools[i].arguments.toString(),
            },
          },
      ];
    }
    out.write(_frame(delta));
    await _finishSse(out, terminalOnly: true);
  }

  static bool _isSseLine(String trimmed) =>
      trimmed.startsWith('data:') ||
      trimmed.startsWith('event:') ||
      trimmed.startsWith('retry:') ||
      trimmed.startsWith('id:');

  void _commitSse(HttpResponse out) {
    out.statusCode = HttpStatus.ok;
    out.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    out.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    out.bufferOutput = false;
  }

  void _handleSseLine(String line) {
    final trimmed = line.trimRight();
    if (!trimmed.startsWith('data:')) return;
    final payload = trimmed.substring(5).trim();
    if (payload.isEmpty || payload == '[DONE]') return;
    final frame = _decode(payload);
    if (frame != null) _applyFrame(frame);
  }

  Map<String, dynamic>? _decode(String text) {
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  // ------------------------------------------------------------ SSE 帧

  void _applyFrame(Map<String, dynamic> frame) {
    _mergeUsage(frame);
    if (frame['error'] != null || frame['type'] == 'error') {
      _fail(zenClassify(null, jsonEncode(frame['error'] ?? frame)));
      return;
    }
    switch (wire) {
      case ZenWire.messages:
        _applyMessages(frame);
      case ZenWire.responses:
        _applyResponses(frame);
      case ZenWire.chat:
        _applyChat(frame);
      case ZenWire.systemone:
        // systemone 不接受聊天请求。
        break;
    }
  }

  /// OpenAI chat 的增量帧（`chat.completion.chunk`）。
  ///
  /// 上游被强制成流式（免费档指纹门只放行 stream:true），客户端要**非流式**
  /// 时走的就是这条路：一帧帧攒起来，最后由 [_writeJson] 拼成整份
  /// chat.completion。客户端自己也要流式时不进转译（代理原样透传）。
  void _applyChat(Map<String, dynamic> frame) {
    final choice = _firstChoice(frame);
    if (choice == null) return;
    final delta = choice['delta'];
    if (delta is Map<String, dynamic>) {
      _emitChatText(delta['content']);
      final reasoning = delta['reasoning_content'] ?? delta['reasoning'];
      if (reasoning is String) _emitReasoning(reasoning);
      final calls = delta['tool_calls'];
      if (calls is List) {
        for (final c in calls.whereType<Map<String, dynamic>>()) {
          _applyChatToolCall(c);
        }
      }
    }
    _setFinish(choice['finish_reason']);
  }

  void _emitChatText(Object? content) {
    if (content is String) {
      _emitText(content);
      return;
    }
    if (content is! List) return;
    for (final part in content.whereType<Map<String, dynamic>>()) {
      final text = part['text'];
      if (text is String) _emitText(text);
    }
  }

  /// 工具调用的增量帧：带 id / name 的是新开一个，只有 arguments 的是续写。
  void _applyChatToolCall(Map<String, dynamic> call) {
    final fn = call['function'];
    final fnMap = fn is Map<String, dynamic> ? fn : const <String, dynamic>{};
    final name = '${fnMap['name'] ?? call['name'] ?? ''}';
    final id = '${call['id'] ?? fnMap['id'] ?? ''}';
    final args = '${fnMap['arguments'] ?? call['arguments'] ?? ''}';
    final index = call['index'];
    if (name.isEmpty && id.isEmpty) {
      // 只有下标与参数：续写已经开过的那个。
      if (index is int && args.isNotEmpty) _appendToolArgs(index, args);
      return;
    }
    final block = _openTool(
      id.isEmpty ? 'call_${_hex(12)}' : id,
      name.isEmpty ? 'unknown' : name,
    );
    if (args.isNotEmpty) _appendToolArgs(block.toolIndex, args);
  }

  Map<String, dynamic>? _firstChoice(Map<String, dynamic> frame) {
    final choices = frame['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    return first is Map<String, dynamic> ? first : null;
  }

  void _applyMessages(Map<String, dynamic> frame) {
    final key = 'b${frame['index'] ?? 0}';
    switch (frame['type']) {
      case 'message_start':
        final message = frame['message'];
        if (message is Map<String, dynamic>) _mergeUsage(message);

      case 'content_block_start':
        final block = frame['content_block'];
        if (block is! Map<String, dynamic>) return;
        switch (block['type']) {
          case 'tool_use':
            _blocks[key] = _openTool(
              '${block['id'] ?? 'call_${_hex(12)}'}',
              '${block['name'] ?? ''}',
            );
          case 'thinking':
            _blocks[key] = _Block.reasoning();
          case 'text':
            _blocks[key] = _Block.text();
        }

      case 'content_block_delta':
        final block = _blocks[key];
        if (block == null) return;
        final delta = frame['delta'];
        if (delta is! Map<String, dynamic>) return;
        switch (delta['type']) {
          case 'text_delta':
            _emitText('${delta['text'] ?? ''}');
          case 'thinking_delta':
            _emitReasoning('${delta['thinking'] ?? ''}');
          case 'input_json_delta':
            _appendToolArgs(block.toolIndex, '${delta['partial_json'] ?? ''}');
        }

      case 'message_delta':
        final delta = frame['delta'];
        if (delta is Map<String, dynamic>) _setFinish(delta['stop_reason']);

      case 'message_stop':
        _setFinish('stop');
    }
  }

  void _applyResponses(Map<String, dynamic> frame) {
    final type = '${frame['type'] ?? ''}';
    final key = 'o${frame['output_index'] ?? 0}';

    if (type == 'response.output_item.added') {
      final item = frame['item'];
      if (item is! Map<String, dynamic>) return;
      switch (item['type']) {
        case 'function_call':
          _blocks[key] = _openTool(
            '${item['call_id'] ?? item['id'] ?? 'call_${_hex(12)}'}',
            '${item['name'] ?? ''}',
          );
        case 'reasoning':
          _blocks[key] = _Block.reasoning();
        case 'message':
          _blocks[key] = _Block.text();
      }
      return;
    }
    if (type == 'response.output_text.delta') {
      _emitText('${frame['delta'] ?? ''}');
      return;
    }
    if (type.startsWith('response.reasoning') && type.endsWith('.delta')) {
      _emitReasoning('${frame['delta'] ?? ''}');
      return;
    }
    if (type == 'response.function_call_arguments.delta') {
      _appendToolArgs(_blocks[key]?.toolIndex, '${frame['delta'] ?? ''}');
      return;
    }
    if (type == 'response.output_item.done') {
      _blocks.remove(key);
      return;
    }
    if (type == 'response.completed' || type == 'response.done') {
      final response = frame['response'];
      if (response is Map<String, dynamic>) _mergeUsage(response);
      _setFinish('stop');
      return;
    }
    if (type == 'response.incomplete') {
      final response = frame['response'];
      final details = response is Map<String, dynamic>
          ? response['incomplete_details']
          : null;
      final reason = details is Map<String, dynamic>
          ? '${details['reason'] ?? ''}'
          : '';
      _setFinish(reason == 'max_output_tokens' ? 'length' : 'stop');
      return;
    }
    if (type == 'response.failed') _setFinish('stop');
  }

  // ---------------------------------------------------------- 整份文档

  /// 一整份 JSON 文档或一串 SSE，两种形状都收：客户端与上游对「要不要流式」
  /// 不一致时（我们发了 stream:false 而上游仍回 SSE，或反过来），
  /// 不该因此把已经到手的回答丢掉。
  void _feedAny(String text) {
    final doc = _decode(text);
    if (doc != null) {
      _feedDoc(doc);
      return;
    }
    for (final line in const LineSplitter().convert(text)) {
      _handleSseLine(line);
    }
    if (!_sawContent && _error == null) {
      _fail(const ZenFailure(ZenFailureCode.empty, status: 200));
    }
  }

  void _feedDoc(Map<String, dynamic>? doc) {
    if (doc == null) {
      _fail(const ZenFailure(ZenFailureCode.empty, status: 200));
      return;
    }
    _mergeUsage(doc);
    if (doc['error'] != null) {
      _fail(zenClassify(null, jsonEncode(doc['error'])));
      return;
    }
    switch (wire) {
      case ZenWire.responses:
        _feedResponsesDoc(doc);
      case ZenWire.messages:
        _feedMessagesDoc(doc);
      case ZenWire.chat:
        _feedChatDoc(doc);
      case ZenWire.systemone:
        break;
    }
    _setFinish(
      doc['stop_reason'] ?? (doc['status'] == 'incomplete' ? 'length' : 'stop'),
    );
  }

  /// Responses 的正文包在 output 里 `message` 项的 `content` 数组内，
  /// 不是顶层块 —— 直接按块名匹配会把整段回答漏掉。
  void _feedResponsesDoc(Map<String, dynamic> doc) {
    final items = doc['output'];
    if (items is! List) return;
    for (final item in items.whereType<Map<String, dynamic>>()) {
      switch (item['type']) {
        case 'message':
          final parts = item['content'];
          if (parts is! List) continue;
          for (final part in parts.whereType<Map<String, dynamic>>()) {
            switch (part['type']) {
              case 'output_text':
              case 'text':
                _emitText('${part['text'] ?? ''}');
              case 'refusal':
                _emitText('${part['refusal'] ?? ''}');
            }
          }
        case 'reasoning':
          _emitReasoning(_reasoningOf(item));
        case 'function_call':
          _addTool(
            '${item['call_id'] ?? item['id'] ?? 'call_${_hex(12)}'}',
            '${item['name'] ?? ''}',
            '${item['arguments'] ?? '{}'}',
          );
      }
    }
  }

  /// Anthropic 的整份文档把块直接放在顶层 content 上。
  void _feedMessagesDoc(Map<String, dynamic> doc) {
    final blocks = doc['content'];
    if (blocks is! List) return;
    for (final block in blocks.whereType<Map<String, dynamic>>()) {
      switch (block['type']) {
        case 'text':
          _emitText('${block['text'] ?? ''}');
        case 'thinking':
          _emitReasoning(_reasoningOf(block));
        case 'tool_use':
          _addTool(
            '${block['id'] ?? 'call_${_hex(12)}'}',
            '${block['name'] ?? ''}',
            block['input'] == null ? '{}' : jsonEncode(block['input']),
          );
      }
    }
  }

  /// chat 的整份文档（`chat.completion`）：内容在 choices[0].message 里。
  /// 上游被强制成流式，但偶尔仍会用一整份 JSON 回答 —— 两种形状都得接住。
  void _feedChatDoc(Map<String, dynamic> doc) {
    final choice = _firstChoice(doc);
    if (choice == null) return;
    final message = choice['message'];
    if (message is Map<String, dynamic>) {
      _emitChatText(message['content']);
      final reasoning = message['reasoning_content'] ?? message['reasoning'];
      if (reasoning is String) _emitReasoning(reasoning);
      final calls = message['tool_calls'];
      if (calls is List) {
        for (final c in calls.whereType<Map<String, dynamic>>()) {
          final fn = c['function'];
          final fnMap = fn is Map<String, dynamic>
              ? fn
              : const <String, dynamic>{};
          _addTool(
            '${c['id'] ?? fnMap['id'] ?? 'call_${_hex(12)}'}',
            '${fnMap['name'] ?? c['name'] ?? ''}',
            '${fnMap['arguments'] ?? c['arguments'] ?? '{}'}',
          );
        }
      }
    }
    _setFinish(choice['finish_reason']);
  }

  String _reasoningOf(Map<String, dynamic> block) {
    // 流式帧带 thinking_delta，整份文档的思考块把文本放在 thinking，
    // Responses 线则放在 summary —— 三种都要认，不然思考内容会静默变空。
    final thinking = block['thinking'];
    if (thinking is String && thinking.isNotEmpty) return thinking;
    final summary = block['summary'];
    if (summary is List) {
      return summary
          .whereType<Map<String, dynamic>>()
          .map((s) => '${s['text'] ?? ''}')
          .join();
    }
    final content = block['content'];
    return content is String ? content : '';
  }

  // -------------------------------------------------------------- 出口

  void _emitText(String delta) {
    if (delta.isEmpty) return;
    _text.write(delta);
    _sawContent = true;
    _emitDelta({'content': delta});
  }

  void _emitReasoning(String delta) {
    if (delta.isEmpty) return;
    _reasoning.write(delta);
    _sawContent = true;
    _emitDelta({'reasoning_content': delta});
  }

  _Block _openTool(String id, String name) {
    _tools.add(_ToolAcc(id: id, name: zenRestoreToolName(name, rename)));
    _sawContent = true;
    final index = _tools.length - 1;
    _emitDelta({
      'tool_calls': [
        {
          'index': index,
          'id': id,
          'type': 'function',
          'function': {'name': _tools[index].name, 'arguments': ''},
        },
      ],
    });
    return _Block.tool(index);
  }

  void _appendToolArgs(int? toolIndex, String delta) {
    if (toolIndex == null || toolIndex >= _tools.length || delta.isEmpty) {
      return;
    }
    _tools[toolIndex].arguments.write(delta);
    _sawContent = true;
    _emitDelta({
      'tool_calls': [
        {
          'index': toolIndex,
          'function': {'arguments': delta},
        },
      ],
    });
  }

  /// 整份文档里的工具调用没有「开始 / 增量」两段，直接落一条完整的。
  void _addTool(String id, String name, String arguments) {
    _tools.add(_ToolAcc(id: id, name: zenRestoreToolName(name, rename)));
    _tools.last.arguments.write(arguments);
    _sawContent = true;
  }

  /// 只在流式路径真写出去；非流式（_sseOut == null）就只累积。
  void _emitDelta(Map<String, dynamic> delta) {
    final out = _sseOut;
    if (out == null) return;
    final full = <String, dynamic>{...delta};
    if (!_roleSent) {
      full['role'] = 'assistant';
      _roleSent = true;
    }
    out.write(_frame(full));
    _wrote = true;
  }

  /// 一帧 SSE：客户端的解析器只认带 data: 壳的行。
  String _frame(Map<String, dynamic> delta, {String? finishReason}) =>
      'data: ${_chunkJson(delta, finishReason: finishReason)}\n\n';

  String _chunkJson(Map<String, dynamic> delta, {String? finishReason}) =>
      jsonEncode({
        'id': id,
        'object': 'chat.completion.chunk',
        'created': createdSeconds,
        'model': model,
        'choices': [
          {'index': 0, 'delta': delta, 'finish_reason': finishReason},
        ],
      });

  Future<void> _finishSse(HttpResponse out, {bool terminalOnly = false}) async {
    if (!terminalOnly) {
      if (_error != null && !_sawContent) {
        await _writeError(out, HttpStatus.badGateway);
        return;
      }
    }
    out.write(
      _frame(
        const {},
        finishReason:
            _finishReason ?? (_tools.isNotEmpty ? 'tool_calls' : 'stop'),
      ),
    );
    out.write(_done);
    await out.flush();
  }

  Map<String, dynamic> _messageDoc() => {
    'role': 'assistant',
    'content': _text.isEmpty ? null : _text.toString(),
    if (_reasoning.isNotEmpty) 'reasoning_content': _reasoning.toString(),
    if (_tools.isNotEmpty)
      'tool_calls': [
        for (final t in _tools)
          {
            'id': t.id,
            'type': 'function',
            'function': {'name': t.name, 'arguments': t.arguments.toString()},
          },
      ],
  };

  Future<void> _writeJson(HttpResponse out) async {
    if (_error != null && !_sawContent) {
      await _writeError(out, HttpStatus.badGateway);
      return;
    }
    out.statusCode = HttpStatus.ok;
    out.headers.contentType = ContentType.json;
    out.write(
      jsonEncode({
        'id': id,
        'object': 'chat.completion',
        'created': createdSeconds,
        'model': model,
        'choices': [
          {
            'index': 0,
            'message': _messageDoc(),
            'finish_reason':
                _finishReason ?? (_tools.isNotEmpty ? 'tool_calls' : 'stop'),
          },
        ],
        if (_usage.isNotEmpty) 'usage': _openAiUsage(),
      }),
    );
    await out.flush();
  }

  Future<void> _writeError(HttpResponse out, int status) async {
    out.statusCode = status;
    out.headers.contentType = ContentType.json;
    final failure = _error ?? ZenFailure(ZenFailureCode.server, status: status);
    out.write(
      jsonEncode({
        'error': {
          'message': _errorMessage(failure),
          'type': switch (failure.code) {
            ZenFailureCode.throttled => 'rate_limit_error',
            ZenFailureCode.credential ||
            ZenFailureCode.restricted => 'authentication_error',
            ZenFailureCode.client => 'invalid_request_error',
            _ => 'api_error',
          },
        },
      }),
    );
    await out.flush();
  }

  String _errorMessage(ZenFailure failure) {
    final label = switch (failure.code) {
      ZenFailureCode.region => '该车道被上游按出口地区拦截（RegionError）',
      ZenFailureCode.throttled => '免费额度已达上限，稍后重试',
      ZenFailureCode.restricted => '该车道仅限官方客户端使用',
      ZenFailureCode.unavailable => '该模型当前不可用',
      // 4xx（除 408/425）：请求自己的问题，换道重试没有意义。
      ZenFailureCode.client => '请求被上游拒绝，重发同一份请求只会得到同一句拒绝',
      ZenFailureCode.empty => '上游没有返回任何内容',
      _ => '上游请求失败',
    };
    return failure.message.isEmpty ? label : '$label：${failure.message}';
  }

  void _fail(ZenFailure failure) => _error ??= failure;

  void _setFinish(Object? reason) {
    final mapped = zenFinishReason('${reason ?? ''}');
    if (mapped == null) return;
    // 更有信息量的终因不被后到的帧覆盖：tool_calls / length 优先于 stop。
    if (_finishReason == null || mapped == 'tool_calls' || mapped == 'length') {
      _finishReason = mapped;
    }
  }

  // --------------------------------------------------------------- usage

  /// 这次上游给的用量（归一成 OpenAI 形状）；上游一句都没给时返回 null。
  ///
  /// 代理用它记账（token 统计页），客户端拿到的 SSE 末帧 / 整份响应里
  /// 也带着同一份。
  Map<String, dynamic>? get usageDoc => _usage.isEmpty ? null : _openAiUsage();

  void _mergeUsage(Map<String, dynamic> frame) {
    final usage = frame['usage'];
    if (usage is! Map<String, dynamic>) return;
    _add('prompt_tokens', usage, ['prompt_tokens', 'input_tokens']);
    _add('completion_tokens', usage, ['completion_tokens', 'output_tokens']);
    _add('reasoning_tokens', usage, [
      'reasoning_tokens',
      'reasoning_output_tokens',
    ]);
    _add('total_tokens', usage, ['total_tokens']);
    // 缓存命中：Anthropic 线给 cache_read_input_tokens，其余用 OpenAI /
    // DeepSeek 两套字段名。**只有上游真提过缓存才往客户端输出**——
    // 否则不许自己编一个「未命中」出来（那会改变 usage 的形状）。
    _add('cache_hit_tokens', usage, [
      'prompt_cache_hit_tokens',
      'cache_read_input_tokens',
    ]);
    _add('cache_miss_tokens', usage, ['prompt_cache_miss_tokens']);
    if (_hasAnyKey(usage, const [
      'prompt_cache_hit_tokens',
      'prompt_cache_miss_tokens',
      'cache_read_input_tokens',
    ])) {
      _sawCacheTokens = true;
    }
    final promptDetails = usage['prompt_tokens_details'];
    if (promptDetails is Map<String, dynamic>) {
      _add('cache_hit_tokens', promptDetails, ['cached_tokens']);
      if (_hasAnyKey(promptDetails, const ['cached_tokens'])) {
        _sawCacheTokens = true;
      }
    }
  }

  static bool _hasAnyKey(Map<String, dynamic> src, List<String> names) {
    for (final n in names) {
      if (src[n] is num) return true;
    }
    return false;
  }

  void _add(String key, Map<String, dynamic> src, List<String> names) {
    for (final name in names) {
      final v = src[name];
      if (v is num) _usage[key] = (_usage[key] as int? ?? 0) + v.toInt();
    }
  }

  Map<String, dynamic> _openAiUsage() {
    final prompt = _usage['prompt_tokens'] as int? ?? 0;
    final completion = _usage['completion_tokens'] as int? ?? 0;
    final hit = _usage['cache_hit_tokens'] as int? ?? 0;
    var miss = _usage['cache_miss_tokens'] as int? ?? 0;
    if (miss == 0 && _sawCacheTokens && prompt > 0) {
      miss = prompt - hit < 0 ? 0 : prompt - hit;
    }
    return {
      'prompt_tokens': prompt,
      'completion_tokens': completion,
      'total_tokens': _usage['total_tokens'] as int? ?? prompt + completion,
      // 上游没提缓存就一个字都不加，保持原本的 usage 形状。
      if (_sawCacheTokens) 'prompt_tokens_details': {'cached_tokens': hit},
      if (_sawCacheTokens && hit > 0) 'prompt_cache_hit_tokens': hit,
      if (_sawCacheTokens && miss > 0) 'prompt_cache_miss_tokens': miss,
      if (_usage['reasoning_tokens'] != null)
        'completion_tokens_details': {
          'reasoning_tokens': _usage['reasoning_tokens'],
        },
    };
  }

  static int _retryAfter(HttpClientResponse res) {
    final raw = int.tryParse(res.headers.value('retry-after') ?? '') ?? 0;
    return raw > 0 && raw < 3600 ? raw : 0;
  }

  static final Random _rng = Random();

  static String _hex(int bytes) => List.generate(
    bytes,
    (_) => _rng.nextInt(256),
  ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

enum _Shape { unknown, sse, json }

/// finish_reason 的三家叫法归一到 OpenAI 的三种。
String? zenFinishReason(String token) {
  switch (token.trim().toLowerCase()) {
    case '':
      return null;
    case 'tool_calls':
    case 'tool_use':
    case 'function_call':
      return 'tool_calls';
    case 'length':
    case 'max_tokens':
    case 'max_output_tokens':
    case 'incomplete':
      return 'length';
    default:
      return 'stop';
  }
}

class _Block {
  _Block.text() : toolIndex = null;
  _Block.reasoning() : toolIndex = null;
  _Block.tool(int this.toolIndex);

  final int? toolIndex;
}

class _ToolAcc {
  _ToolAcc({required this.id, required this.name});

  final String id;
  final String name;
  final StringBuffer arguments = StringBuffer();
}
