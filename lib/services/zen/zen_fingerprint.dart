/// 免费档指纹门的出站改造：把 body.tools 补齐成网关认的样子。
///
/// 这道门只检查声明的工具名，不检查实现，所以缺的槽位优先让真能顶替的工具
/// 顶上（`pwsh` → `bash`），实在没得顶才补一个自废诱饵。参考实现踩过坑：
/// 只有 `pwsh` 在场上时硬塞 `bash` 诱饵，模型一轮调了 24 次 bash，每次都是
/// unknown tool。提升真工具代价相同，调用还能落地。
library;

import 'zen_protocol.dart';

/// tools 的三种形状：OpenAI chat 嵌套、Responses 扁平、Anthropic 的 input_schema。
enum ZenToolStyle { chat, flat, claude }

ZenToolStyle zenStyleFor(Object? wire) => switch (wire) {
  ZenWire.responses => ZenToolStyle.flat,
  ZenWire.messages => ZenToolStyle.claude,
  _ => ZenToolStyle.chat,
};

/// 某个必需槽位可以由哪些真工具顶替，键是网关要求的拼写。
const Map<String, List<String>> _quartetDonors = {
  'bash': ['pwsh'],
};

String _toolName(Map<String, dynamic>? tool) {
  if (tool == null) return '';
  final direct = tool['name'];
  if (direct is String && direct.trim().isNotEmpty) return direct.trim();
  final fn = tool['function'];
  if (fn is Map<String, dynamic>) {
    final nested = fn['name'];
    if (nested is String && nested.trim().isNotEmpty) return nested.trim();
  }
  return '';
}

Map<String, dynamic>? _functionOf(Map<String, dynamic> tool) {
  final fn = tool['function'];
  return fn is Map<String, dynamic> ? fn : null;
}

String _quartetKey(String name) {
  final lower = name.trim().toLowerCase();
  return kZenFingerprintTools.contains(lower) ? lower : '';
}

Map<String, dynamic> _renamed(Map<String, dynamic> tool, String name) {
  final fn = _functionOf(tool);
  if (fn != null) {
    // 整层浅拷贝，只替换 function.name：未知字段（strict 之类）原样带过去。
    final nested = Map<String, dynamic>.of(fn)..['name'] = name;
    return Map<String, dynamic>.of(tool)..['function'] = nested;
  }
  return Map<String, dynamic>.of(tool)..['name'] = name;
}

/// 凑齐四件套，原地改写 body。
///
/// 返回「送出拼写 → 调用方拼写」的改名表：上游只会认出 `bash`，而调用方的
/// 工具可能叫 `Bash` 或 `pwsh`，响应侧要按这张表还原回去，否则回来的
/// tool_calls 名字对不上调用方的注册表。
Map<String, String> zenApplyFingerprint(
  Map<String, dynamic> body,
  ZenToolStyle style,
) {
  final rename = <String, String>{};
  final raw = body['tools'];
  final tools = <Object?>[if (raw is List) ...raw];
  final hadClientTools = tools.isNotEmpty;
  final seen = <String>{};
  final out = <Object?>[];

  for (final tool in tools) {
    if (tool is! Map<String, dynamic>) {
      out.add(tool);
      continue;
    }
    final current = _toolName(tool);
    final key = _quartetKey(current);
    if (key.isEmpty) {
      out.add(tool);
      continue;
    }
    // 上游把 Bash + bash 当重复拒绝，所以是归一而不是并存。
    if (!seen.add(key)) continue;
    out.add(current == key ? tool : _renamed(tool, key));
    if (current != key) rename[key] = current;
  }

  final promoted = <String>{};
  for (final name in kZenFingerprintTools) {
    if (seen.contains(name)) continue;
    final donors = _quartetDonors[name] ?? const <String>[];
    var index = -1;
    for (var i = 0; i < out.length; i++) {
      final candidate = out[i];
      if (candidate is! Map<String, dynamic>) continue;
      final original = _toolName(candidate);
      if (original.isEmpty || _quartetKey(original).isNotEmpty) continue;
      final lower = original.toLowerCase();
      if (promoted.contains(lower) || !donors.contains(lower)) continue;
      index = i;
      break;
    }
    if (index == -1) continue;
    final tool = out[index] as Map<String, dynamic>;
    final original = _toolName(tool);
    promoted.add(original.toLowerCase());
    rename[name] = original;
    out[index] = _renamed(tool, name);
    seen.add(name);
  }

  for (final name in kZenFingerprintTools) {
    if (seen.contains(name)) continue;
    const desc = 'This tool is currently unavailable and must not be used.';
    const emptyParams = <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{},
    };
    out.add(switch (style) {
      ZenToolStyle.claude => {
        'name': name,
        'description': desc,
        'input_schema': emptyParams,
      },
      ZenToolStyle.flat => {
        'type': 'function',
        'name': name,
        'description': desc,
        'parameters': emptyParams,
      },
      ZenToolStyle.chat => {
        'type': 'function',
        'function': {
          'name': name,
          'description': desc,
          'parameters': emptyParams,
        },
      },
    });
  }

  body['tools'] = out;
  if (!body.containsKey('tool_choice')) {
    switch (style) {
      case ZenToolStyle.flat:
        body['tool_choice'] = 'auto';
      case ZenToolStyle.claude:
        if (!hadClientTools) body['tool_choice'] = {'type': 'none'};
      case ZenToolStyle.chat:
        if (!hadClientTools) body['tool_choice'] = 'none';
    }
  }
  return rename;
}

/// 把送出的拼写还原成调用方的拼写。
String zenRestoreToolName(String name, Map<String, String> rename) =>
    rename[name] ?? name;
