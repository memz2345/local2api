// lib/services/lab/dsh_config.dart
//
// DeepSeek Harness（dsh）用户配置的读写工具。
//
// dsh 的配置是「层层叠加」的 YAML：profile 自己的 `cordis.patch.yml` 里放一个
// 顶层数组，每个元素按 `id` 覆盖某个插件行。模型 provider 属于 `llm-pi-ai`
// 这一行的 `config.providers.<route>`，所以本文件只做两件事：
//
//   1. 从现有文件里读出 `llm-pi-ai` 那一行的 providers（保留用户已有的
//      deepseek / lol 等路由，别一键写死把人家配置冲掉）；
//   2. 把 `llm-pi-ai`（或 `agent-default-model`）那一行整体替换成新的块，
//      其余行原样保留 —— 注释、`!!js` 表达式都不碰。
//
// 配置块手写 YAML（而不是 JSON）：`reasoningEfforts` 里的 `off:` 必须是
// 「有键无值」，JSON 的 `"off": null` 会被 dsh 的 schemastery 拒掉。

import 'package:yaml/yaml.dart';

/// 本应用在 dsh 里注册的 provider 路由名。
const String kDshProviderId = 'local2api';

/// 传给 dsh 进程的环境变量名：密钥由应用启动时注入，不落进配置文件。
const String kDshApiKeyEnv = 'LOCAL2API_API_KEY';

/// Android 兼容层的首行标记：靠它认出「这段是本应用写的」，重写时只换自己那段。
const String kDshAndroidPatchMarker = 'local2api-android-patch: v1';

/// Android 上 dsh 需要的兼容性调整，写在 **home 级** `$DSH_HOME/cordis.patch.yml`
/// （profile-boot 的 homePatches 层，比 profile 自己的 `cordis.patch.yml` 先加载，
/// 两份都会被读到，所以不要再往命令行塞 `--patch` —— 同一块应用两次会撞
/// duplicate loader entry）。
///
/// 取舍（依据 deepseek-harness-android-app v1.x 的安卓实测记录，MIT）：
///   · `sandbox` **不能禁**：0.1.7 起 ptc-runtime 注入它，禁了 `workflow-ptc`
///     拿不到 ptcRuntime，所有 preset 会话创建都失败。它只惰性解析平台原生包，
///     在没有 `.node` 的依赖树里也能干净加载。
///   · `llm-pi-ai` **不能禁**：pi-ai 是纯 JS，模型 provider 目录就挂在这行上；
///     禁了「添加提供方」会一直置灰。
///   · `bash-sandbox` / `pwsh-sandbox` 要禁：前者要原生沙箱内核特性，后者要 pwsh。
///     `pwsh-sandbox` 不禁会一直等 sandbox 服务 → 启动 pending → node 反复崩。
///   · `permission`（档位预设）跟着禁：它拒绝挂在「不 confinement 的 bash 执行器」
///     上（`no sandboxMode`），而 `sandboxMode` 是上游给 `bash-local` 打的安卓补丁，
///     我们从 npm 装的干净树没有它 —— 不禁就是一行 `1 entry did not activate` 警告。
///   · `bash-local` 补进来：它用 child_process 提供 `ctx.shell`，不需要 node-pty。
///
///   · `terminal-bash` 补进来：dsh 的「终端」（行程持久的那张 terminal 卡/
///     `tool-bash-persistent`）走 `ctx.terminals`，而唯一的后端要 node-pty ——
///     Android 上由 `dsh_android_patches.dart` 换成管道实现（见 `_nodePtyShim`）。
///     这一行默认不挂载（所有 cordis.yml / bundle 补丁里都没有 `terminal-bash`），
///     不补进来 `ctx.terminals` 就没有后端 → 界面报「终端不可用」。
///     `shellPath` 必须显式写：上游默认是 `/bin/bash`，Android 只有
///     `/system/bin/sh`；`shellArgs` 同理要去掉
///     `--noprofile --norc`（mksh 不认，带上去 shell 起不来）。
const String kDshAndroidCompatBlock = '''
# $kDshAndroidPatchMarker
- id: bash-sandbox
  disabled: true
- id: pwsh-sandbox
  disabled: true
- id: permission
  disabled: true
- id: session-log-download
  disabled: true
- id: session-telemetry-otel
  disabled: true
- insert:
    - id: bash-local
      name: '@deepseek-ai/dsh-bash-local'
      config:
        cwd: !!js (process.env.DSH_WORKSPACE || process.cwd())
        timeoutMs: 60000
    - id: terminal-bash
      name: '@deepseek-ai/dsh-terminal-bash'
      config:
        shellDialect: bash
        shellPath: /system/bin/sh
        shellArgs: ['-i']
        rows: 40
        cols: 160
''';

/// 这份 home 级配置里有没有本应用的 Android 兼容层。
bool hasAndroidCompatPatch(String source) =>
    source.contains(kDshAndroidPatchMarker);

/// 把 Android 兼容层并进 home 级配置，保留用户写在它前面的其它条目。
///
/// 约定兼容层**始终在文件末尾**：已存在（按 [kDshAndroidPatchMarker] 认）就把
/// 那一段截掉重新追加，等于就地升级；没有就直接追加。
String upsertAndroidCompatPatch(String source) {
  final normalized = source.replaceAll('\r\n', '\n');
  final at = normalized.indexOf('# $kDshAndroidPatchMarker');
  var head = (at < 0 ? normalized : normalized.substring(0, at)).trimRight();
  // 空文档就是一个 `[]`（dsh 自带的模板，或我们撤掉兼容层后留下的），
  // 它和后面的列表块不能混排 —— 混在一起 dsh 解析直接报错、引擎起不来。
  head = head
      .split('\n')
      .where((line) => line.trim() != '[]')
      .join('\n')
      .trimRight();
  if (head.isEmpty) return kDshAndroidCompatBlock;
  return '$head\n$kDshAndroidCompatBlock';
}

/// 撤掉本应用写的 Android 兼容层，保留用户写在它前面的条目。
String removeAndroidCompatPatch(String source) {
  final normalized = source.replaceAll('\r\n', '\n');
  final at = normalized.indexOf('# $kDshAndroidPatchMarker');
  if (at < 0) return source;
  return normalized.substring(0, at).trimRight();
}

/// 模型能力兜底：不确定时按 256K 上下文（dsh 自己的默认值）。
const int kDshContextWindow = 262144;

/// 对外声明的输入模态（`llm-pi-ai` 的字段名是 **`input`**，不是
/// `inputModalities` —— 后者是 deepseek 官方 provider 的字段名，写到这里
/// schemastery 会当成未知键）。
///
/// **必须显式写**：pi-ai 的模型 schema 里 `input` 缺省 → 回落到 provider 的
/// `defaultInput`（默认 `["text"]`），等于告诉 dsh「这个模型只吃文本」——
/// 于是会话里贴一张图就被拦在
/// `session/attachment-invalid: Model "xxx" does not support image input.`，
/// computer use 的截图也送不进去（模型被当成纯文本，图会被投影成文字说明）。
///
/// 本应用自己的聊天模拟是不管模型都能发图的，所以这里保持一致：一律声明
/// 支持图片。上游真不支持的话，请求会在上游那边报错，用户看得见。
const List<String> kDshInputModalities = ['text', 'image'];

/// 思考档位。key 是选择器里出现的档位，value 是线上发的字面量；
/// `off` 留空（null）= 不发字段，这是 dsh 官方语义。
///
/// 只列 dsh 0.1.x 接受的 7 档（没有 `none`：那个是 local2api 自己的叫法，
/// 写进去会直接让 plugin tree 加载失败）。
const Map<String, String?> kDshReasoningEfforts = {
  'off': null,
  'minimal': 'minimal',
  'low': 'low',
  'medium': 'medium',
  'high': 'high',
  'xhigh': 'xhigh',
  'max': 'max',
};

/// 安卓「任务模式」提示词。
///
/// 让模型按「发任务」的方式干活：先报步骤、逐步推进、需要人拍板时停下来问、
/// 结束给出简明结论。标记行是给本应用解析用的（见 `dsh_task_runner.dart`），
/// 每一步都会变成通知进度条上的一个分段 —— 所以模型不报步骤的话，通知上
/// 就只有一根转圈的不确定进度条。
const String kDshTaskPreamble = '''【任务模式 · 输出会被手机通知栏逐步展示】
1. 先用一行报出计划：`L2A-PLAN: 步骤一 | 步骤二 | 步骤三`（3-6 步，只报一次）。
2. 每开始一步输出 `L2A-STEP: <步骤名>`；每完成一步输出 `L2A-STEP-DONE: <步骤名>`。
3. 需要用户确认、选择或补充信息时，输出 `L2A-ASK: <一句话问题>` 并结束本轮，等用户回复。
4. 全部完成后输出最终结果：以 `L2A-RESULT:` 开头，最后单独一行 `L2A-RESULT-END`。结果简明，不超过 8 行。
除上述标记外照常输出你的工作过程。''';

/// Windows 额外的一句：提问有明确选项时带上选项，通知上会显示 1/2/3。
///
/// 只在 Windows 拼接，安卓提示词保持原样。
const String kDshTaskWindowsOptionsPreamble = '''
5. 如果问题存在 2-3 个明确候选方案，把选项附在问题后面：`L2A-ASK: 问题 | 选项一 | 选项二 | 选项三`。
除上述标记外照常输出你的工作过程。''';

/// 从 dsh 的一行输出里捞出一个 `L2A-xxx` 标记（返回标记名与内容）。
///
/// 标记必须是行首（允许 ANSI / 日志前缀后紧跟），否则模型正文里提到这几个
/// 词也会被误判。
(String, String)? parseTaskMarker(String line) {
  // 先剥掉 ANSI 颜色码（dsh 的日志有），再严格按行首匹配 —— 否则模型正文里
  // 提到这几个词也会被误判成标记。
  //
  // 冒号可选：提示词里 `L2A-RESULT-END` 是单独一行不带冒号的写法，要求必须有
  // 冒号的话它就当普通正文漏进结果里了。
  final cleaned = stripAnsi(line).trim();
  final match = RegExp(r'^L2A-([A-Z-]+):?\s*(.*)$').firstMatch(cleaned);
  if (match == null) return null;
  return (match.group(1)!, match.group(2)!.trim());
}

/// 去掉一行里的 ANSI 转义序列（日志展示与标记解析共用）。
String stripAnsi(String line) =>
    line.replaceAll(RegExp(r'\x1B\[[0-9;]*[A-Za-z]'), '');

/// 解析 `L2A-ASK` 的文本：`问题 | 选项一 | 选项二`。
///
/// 只有 Windows 的额外提示词会要求带选项；安卓输出不带竖线时，
/// question 就是整行原样。
({String question, List<String> options}) parseAskValue(String value) {
  final parts = [
    for (final part in value.split(RegExp(r'[|｜]')))
      if (part.trim().isNotEmpty) part.trim(),
  ];
  if (parts.isEmpty) return (question: value.trim(), options: const <String>[]);
  return (question: parts.first, options: parts.skip(1).toList(growable: false));
}

/// 从 dsh 的一行输出里捞出带一次性令牌的界面地址。
///
/// dsh web 启动只往 stdout 打这一行：
/// `dsh web: http://127.0.0.1:3080/?token=xxxx`。不带令牌访问 `/` 与 `/api`
/// 一律 401，所以这一行丢了就等于开不开界面。
String? extractDshTokenUrl(String line) {
  final match = RegExp(
    r'''https?://[^\s"'<>]+[?&]token=[A-Za-z0-9_\-]{8,}''',
  ).firstMatch(line);
  return match?.group(0);
}

/// 读出现有配置里 `llm-pi-ai` 的 providers 字典（读不到就是空）。
Map<String, dynamic> readDshProviders(String source) {
  final block = findEntryBlock(source, 'llm-pi-ai');
  if (block == null) return <String, dynamic>{};
  try {
    final doc = loadYaml(block);
    if (doc is YamlList && doc.isNotEmpty) {
      final first = doc.first;
      if (first is YamlMap) {
        final config = first['config'];
        if (config is YamlMap) {
          final providers = config['providers'];
          if (providers is YamlMap) return _plainMap(providers);
        }
      }
    }
  } catch (_) {
    // 用户手写坏了的 YAML：当作没有 provider，别把整个写入也搞崩。
  }
  return <String, dynamic>{};
}

/// 生成 `llm-pi-ai` 行的完整文本块。
String buildLlmpiAiEntry(Map<String, dynamic> providers) {
  final body = providers.isEmpty
      ? '    providers: {}\n'
      : '    providers:\n${_emitMap(providers, 6)}';
  return '- id: llm-pi-ai\n'
      '  name: "@deepseek-ai/dsh-llm-pi-ai"\n'
      '  config:\n'
      '$body';
}

/// 生成 `agent-default-model` 行：让新会话默认用本应用的模型。
String buildDefaultModelEntry({
  required String provider,
  required String model,
  String? reasoningEffort,
}) {
  final config = <String, dynamic>{'provider': provider, 'model': model};
  if (reasoningEffort != null && reasoningEffort.isNotEmpty) {
    config['reasoningEffort'] = reasoningEffort;
  }
  return '- id: agent-default-model\n'
      '  name: "@deepseek-ai/dsh-agent-default-model"\n'
      '  config: ${_emitFlowMap(config)}\n';
}

/// 构造本应用的 provider 路由配置。
Map<String, dynamic> buildLocal2ApiProvider({
  required String baseUrl,
  required List<String> models,
  String displayName = 'Local2API',
}) {
  return <String, dynamic>{
    'displayName': displayName,
    'apiKeyEnv': kDshApiKeyEnv,
    'api': 'openai-completions',
    'baseURL': baseUrl,
    // 没列进 models 的模型（比如 dsh 从 /v1/models 拉到的）也按这个兜底。
    'defaultInput': kDshInputModalities,
    'models': [
      for (final model in models)
        if (model.trim().isNotEmpty)
          <String, dynamic>{
            'id': model.trim(),
            'name': model.trim(),
            'contextWindow': kDshContextWindow,
            'input': kDshInputModalities,
            'reasoningEfforts': kDshReasoningEfforts,
          },
    ],
  };
}

/// 找到某个入口块（`- id: xxx` 起、到下一个顶层 `- ` 之前）。
String? findEntryBlock(String source, String id) {
  final lines = source.split('\n');
  final start = _entryStart(lines, id);
  if (start < 0) return null;
  var end = lines.length;
  for (var i = start + 1; i < lines.length; i++) {
    if (_isTopLevelEntry(lines[i])) {
      end = i;
      break;
    }
  }
  return lines.sublist(start, end).join('\n');
}

/// 用 [block] 替换 `- id: <id>` 那一块；文件里没有就追加。
///
/// 文件是空文档（`[]` 或只有注释）时把 `[]` 摘掉，避免出现 `[]` + 列表混排。
String upsertEntry(String source, String id, String block) {
  final normalized = source.replaceAll('\r\n', '\n');
  final lines = normalized.split('\n');
  final start = _entryStart(lines, id);
  final body = block.trimRight();

  if (start < 0) {
    final kept = <String>[];
    for (final line in lines) {
      if (line.trim() == '[]') continue;
      kept.add(line);
    }
    final head = kept.join('\n').trimRight();
    if (head.isEmpty) return '$body\n';
    return '$head\n$body\n';
  }

  var end = lines.length;
  for (var i = start + 1; i < lines.length; i++) {
    if (_isTopLevelEntry(lines[i])) {
      end = i;
      break;
    }
  }
  final out = <String>[
    ...lines.sublist(0, start),
    ...body.split('\n'),
    ...lines.sublist(end),
  ];
  return '${out.join('\n').trimRight()}\n';
}

int _entryStart(List<String> lines, String id) {
  final pattern = RegExp('^-\\s+id:\\s*["\']?${RegExp.escape(id)}["\']?\\s*\$');
  for (var i = 0; i < lines.length; i++) {
    if (pattern.hasMatch(lines[i].trimRight())) return i;
  }
  return -1;
}

bool _isTopLevelEntry(String line) =>
    line.startsWith('- ') || line.trimRight() == '-';

Map<String, dynamic> _plainMap(YamlMap map) {
  final out = <String, dynamic>{};
  for (final entry in map.entries) {
    out['${entry.key}'] = _plainValue(entry.value);
  }
  return out;
}

Object? _plainValue(Object? value) {
  if (value is YamlMap) return _plainMap(value);
  if (value is YamlList) return [for (final item in value) _plainValue(item)];
  return value;
}

// ---- 极简 YAML 块输出（只覆盖 dsh 配置里出现的类型） ----

String _emitMap(Map<dynamic, dynamic> map, int indent) {
  final pad = ' ' * indent;
  final buffer = StringBuffer();
  map.forEach((key, value) {
    final name = _key('$key');
    if (_isBlock(value)) {
      buffer.writeln('$pad$name:');
      buffer.write(_emitBlock(value, indent + 2));
    } else if (value == null) {
      buffer.writeln('$pad$name:');
    } else {
      buffer.writeln('$pad$name: ${_inline(value)}');
    }
  });
  return buffer.toString();
}

String _emitBlock(Object value, int indent) {
  if (value is Map) return _emitMap(value, indent);
  if (value is List) {
    final pad = ' ' * indent;
    final buffer = StringBuffer();
    for (final item in value) {
      if (_isBlock(item)) {
        buffer.writeln('$pad-');
        buffer.write(_emitBlock(item, indent + 2));
      } else if (item == null) {
        buffer.writeln('$pad- null');
      } else {
        buffer.writeln('$pad- ${_inline(item)}');
      }
    }
    return buffer.toString();
  }
  return '${' ' * indent}${_inline(value)}\n';
}

bool _isBlock(Object? value) =>
    (value is Map && value.isNotEmpty) || (value is List && value.isNotEmpty);

String _inline(Object? value) {
  if (value is Map) return _emitFlowMap(value);
  if (value is List) {
    return '[${value.map(_inline).join(', ')}]';
  }
  return _scalar(value);
}

/// 单行 flow map：只用于 `agent-default-model` 这种两三个键的小配置。
String _emitFlowMap(Map<dynamic, dynamic> map) {
  final parts = <String>[];
  map.forEach((key, value) {
    parts.add('${_key('$key')}: ${_inline(value)}');
  });
  return '{${parts.join(', ')}}';
}

String _key(String key) {
  if (RegExp(r'^[A-Za-z_][A-Za-z0-9_.-]*$').hasMatch(key)) return key;
  return _quote(key);
}

String _scalar(Object? value) {
  if (value == null) return 'null';
  if (value is num || value is bool) return '$value';
  final text = '$value';
  final looksLikeScalar = RegExp(
    r'^(true|false|yes|no|null|~|[-+]?[0-9.]+([eE][-+]?[0-9]+)?)$',
    caseSensitive: false,
  ).hasMatch(text);
  final needsQuote =
      text.isEmpty ||
      looksLikeScalar ||
      RegExp(r'^[\s]|[\s]$').hasMatch(text) ||
      RegExp(r'''[:#{}\[\],&*?|<>=!%@`"'\ ]''').hasMatch(text);
  return needsQuote ? _quote(text) : text;
}

String _quote(String text) {
  final escaped = text
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', '\\n');
  return '"$escaped"';
}
