import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一条请求的 token 用量。
///
/// 来源是上游响应里的 `usage`：OpenAI 兼容端点（含 Zen）在非流式响应里给，
/// 流式则在最后一帧给；有的网关（DeepSeek 系）用 `prompt_cache_hit_tokens`，
/// 有的（OpenAI 系）藏在 `prompt_tokens_details.cached_tokens`，两种都收。
class TokenUsage {
  const TokenUsage({
    required this.timeMs,
    required this.model,
    required this.upstream,
    required this.lane,
    required this.input,
    required this.output,
    this.cacheHit = 0,
    this.cacheMiss = 0,
    this.reasoning = 0,
    this.stream = false,
    this.status = 200,
    this.apiKeyId = '',
    this.apiKeyName = '',
    this.apiKeyLabel = '',
  });

  /// 记录时间（毫秒时间戳）。
  final int timeMs;

  /// 客户端请求的对外模型名（路由名或车道名）。
  final String model;

  /// 上游名（配置里的那一层）。
  final String upstream;

  /// 真正接住这次请求的车道（回退后的那一条）。
  final String lane;

  /// 输入 token（prompt_tokens）。
  final int input;

  /// 输出 token（completion_tokens）。
  final int output;

  /// 命中缓存的输入 token。
  final int cacheHit;

  /// 未命中缓存的输入 token。上游没单独给就用 input - cacheHit 推。
  final int cacheMiss;

  /// 思考 token（reasoning_tokens），包含在 output 里，单独留一份给统计。
  final int reasoning;

  final bool stream;
  final int status;

  /// 这次调用拿的是哪一把本机 API Key（`ApiKeyEntry.id`）。
  ///
  /// 空串 = 请求没带密钥（本机直连、或压根没配鉴权），统计上算「未鉴权」那一档。
  /// **只存 id 与脱敏后的样子，完整密钥不进账本。**
  final String apiKeyId;

  /// 那把 Key 的备注名（可能为空）。
  final String apiKeyName;

  /// 那把 Key 脱敏后的样子（`sk-abcd**1234`），页面上按它认人。
  final String apiKeyLabel;

  /// 这次调用有没有认出具体某把 Key。
  bool get hasApiKey => apiKeyId.isNotEmpty;

  int get total => input + output;

  /// 命中率（0~1）。输入为 0 时给 0，免得除零。
  double get hitRate => input <= 0 ? 0 : cacheHit / input;

  Map<String, dynamic> toJson() => {
    'timeMs': timeMs,
    'model': model,
    'upstream': upstream,
    'lane': lane,
    'input': input,
    'output': output,
    'cacheHit': cacheHit,
    'cacheMiss': cacheMiss,
    'reasoning': reasoning,
    'stream': stream,
    'status': status,
    'apiKeyId': apiKeyId,
    'apiKeyName': apiKeyName,
    'apiKeyLabel': apiKeyLabel,
  };

  factory TokenUsage.fromJson(Map<String, dynamic> j) => TokenUsage(
    timeMs: (j['timeMs'] as num?)?.toInt() ?? 0,
    model: (j['model'] as String?) ?? '-',
    upstream: (j['upstream'] as String?) ?? '-',
    lane: (j['lane'] as String?) ?? '',
    input: (j['input'] as num?)?.toInt() ?? 0,
    output: (j['output'] as num?)?.toInt() ?? 0,
    cacheHit: (j['cacheHit'] as num?)?.toInt() ?? 0,
    cacheMiss: (j['cacheMiss'] as num?)?.toInt() ?? 0,
    reasoning: (j['reasoning'] as num?)?.toInt() ?? 0,
    stream: (j['stream'] as bool?) ?? false,
    status: (j['status'] as num?)?.toInt() ?? 200,
    // 老账本里没有这三个字段：照旧按「未鉴权」归，不补写假 key。
    apiKeyId: (j['apiKeyId'] as String?) ?? '',
    apiKeyName: (j['apiKeyName'] as String?) ?? '',
    apiKeyLabel: (j['apiKeyLabel'] as String?) ?? '',
  );
}

/// 一段范围内 / 一组记录的汇总。
class UsageSummary {
  const UsageSummary({
    this.input = 0,
    this.output = 0,
    this.cacheHit = 0,
    this.cacheMiss = 0,
    this.reasoning = 0,
    this.requests = 0,
  });

  final int input;
  final int output;
  final int cacheHit;
  final int cacheMiss;
  final int reasoning;
  final int requests;

  int get total => input + output;

  double get hitRate => input <= 0 ? 0 : cacheHit / input;

  static UsageSummary of(Iterable<TokenUsage> records) {
    var input = 0;
    var output = 0;
    var hit = 0;
    var miss = 0;
    var reasoning = 0;
    var count = 0;
    for (final r in records) {
      input += r.input;
      output += r.output;
      hit += r.cacheHit;
      miss += r.cacheMiss;
      reasoning += r.reasoning;
      count++;
    }
    return UsageSummary(
      input: input,
      output: output,
      cacheHit: hit,
      cacheMiss: miss,
      reasoning: reasoning,
      requests: count,
    );
  }

  UsageSummary operator +(UsageSummary other) => UsageSummary(
    input: input + other.input,
    output: output + other.output,
    cacheHit: cacheHit + other.cacheHit,
    cacheMiss: cacheMiss + other.cacheMiss,
    reasoning: reasoning + other.reasoning,
    requests: requests + other.requests,
  );
}

/// 按天的汇总（图表与「哪天才用的」用）。
class UsageDay {
  const UsageDay({required this.day, required this.summary});

  /// 当天 00:00（本地时区）。
  final DateTime day;
  final UsageSummary summary;
}

/// 账本里出现过的某一把本机 API Key。
///
/// 拿着它去筛选「这把 key 打了多少量」。**完整密钥不在这里**，只有 id、
/// 备注名和脱敏后的那串样子 —— 账本落盘的内容本身就不该能还原密钥。
class UsageKeyRef {
  const UsageKeyRef({required this.id, required this.name, required this.label});

  /// `ApiKeyEntry.id`；空串 = 没带密钥的调用（未鉴权那一档）。
  final String id;

  /// 备注名（用户自己起的，可能是空串）。
  final String name;

  /// 脱敏后的样子，如 `sk-abcd**1234`；未鉴权时是空串。
  final String label;

  /// 下拉里显示的那句话：有名字叫名字，没名字用脱敏串，都没有就是「未鉴权」。
  String display(String anonymousLabel) {
    if (name.isNotEmpty) return name;
    if (label.isNotEmpty) return label;
    return anonymousLabel;
  }

  @override
  bool operator ==(Object other) =>
      other is UsageKeyRef && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);
}

/// 某个模型在某一筛选下的用量（「各模型用量」表格的一行）。
///
/// 只统计**真打过的**模型：表里不会出现零调用的行。
class UsageModelUsage {
  const UsageModelUsage({required this.model, required this.summary});

  final String model;
  final UsageSummary summary;
}

/// 某天里某个模型的汇总（日历页「当天活动」的一张卡片）。
class UsageModelDay {
  const UsageModelDay({
    required this.model,
    required this.summary,
    required this.firstMs,
    required this.lastMs,
  });

  final String model;

  /// 这一整天、这一个模型的汇总。
  final UsageSummary summary;

  /// 当天第一次 / 最后一次调用的毫秒时间戳。
  final int firstMs;
  final int lastMs;
}

/// 日历页选完某天（+ 某个模型）后带回统计页的焦点。
///
/// 统计页拿到它就把模型与时间范围一起切过去：看那一天的、那个模型的账。
class TokenStatsFocus {
  const TokenStatsFocus({required this.day, this.model});

  /// 选中的那天（只需年月日，时分秒忽略）。
  final DateTime day;

  /// null = 全部模型。
  final String? model;
}

/// token 用量的落地与聚合。
///
/// 采在代理的响应路径上（见 ProxyServer），只存**汇总过的数字**：
/// 一条记录就是「某时某模型进了多少 / 出了多少 / 命中多少」，
/// 不存任何请求或响应正文 —— 这不是抓包，是本机自己的账本。
class UsageStats extends ChangeNotifier {
  static const String _key = 'local2api.usage.v1';

  /// 环形上限。2000 条足够看一个月（按每天几十次请求算），
  /// 再多也是把 SharedPreferences 撑肥。
  static const int maxRecords = 2000;

  final List<TokenUsage> _records = [];

  bool _loaded = false;
  Timer? _saveTimer;

  bool get loaded => _loaded;

  /// 时间倒序（新的在前）。
  List<TokenUsage> get records => List.unmodifiable(_records);

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        final list = decoded is Map<String, dynamic>
            ? decoded['records']
            : null;
        if (list is List) {
          for (final e in list) {
            if (e is Map<String, dynamic>) {
              _records.add(TokenUsage.fromJson(e));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('UsageStats load failed: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  /// 记一条。usage 全为零的（上游没给 usage 的流式响应）也记：
  /// 「这次请求没有 token 数据」本身是有信息量的，页面上会标出来。
  void add(TokenUsage usage) {
    _records.insert(0, usage);
    if (_records.length > maxRecords) {
      _records.removeRange(maxRecords, _records.length);
    }
    notifyListeners();
    _scheduleSave();
  }

  void clear() {
    _records.clear();
    notifyListeners();
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_save());
    });
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'records': [for (final r in _records) r.toJson()],
        }),
      );
    } catch (e) {
      debugPrint('UsageStats save failed: $e');
    }
  }

  /// 立即落盘（退出前调用）。
  Future<void> flush() async {
    _saveTimer?.cancel();
    await _save();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  /// 密钥脱敏：留头部 8 位 + 尾部 4 位，中间打星（DeepSeek 账单页那副样子）。
  ///
  /// 落在账本里、显示在下拉里的都是这个形状；完整密钥既不存也不传。
  static String maskKey(String key) {
    final k = key.trim();
    if (k.isEmpty) return '';
    if (k.length <= 12) {
      // 短到打星没意义的（多半不是真密钥）：留一头一尾意思一下。
      return '${k.substring(0, 1)}**${k.substring(k.length - 1)}';
    }
    return '${k.substring(0, 8)}**${k.substring(k.length - 4)}';
  }

  // ------------------------------------------------------------ 查询

  /// 出现过的模型名（对外名），按字母序。
  List<String> get models {
    final set = <String>{for (final r in _records) r.model};
    final list = set.toList()..sort();
    return list;
  }

  /// 出过账的 API Key，`null` 传进来表示不过滤。
  ///
  /// 排序：认得出的 key 在前（按备注名/脱敏串），未鉴权那一档垫底。
  List<UsageKeyRef> keysWithin({
    String? model,
    DateTime? from,
    DateTime? to,
  }) {
    final seen = <String, UsageKeyRef>{};
    UsageKeyRef? anon;
    for (final r in query(model: model, from: from, to: to)) {
      if (!r.hasApiKey) {
        anon ??= const UsageKeyRef(id: '', name: '', label: '');
        continue;
      }
      seen.putIfAbsent(
        r.apiKeyId,
        () => UsageKeyRef(
          id: r.apiKeyId,
          name: r.apiKeyName,
          label: r.apiKeyLabel,
        ),
      );
    }
    final out = seen.values.toList()
      ..sort((a, b) {
        final ta = a.name.isNotEmpty ? a.name : a.label;
        final tb = b.name.isNotEmpty ? b.name : b.label;
        return ta.compareTo(tb);
      });
    if (anon != null) out.add(anon);
    return out;
  }

  /// 出过账的上游（不同的 OpenAI 兼容端点），按字母序。
  ///
  /// 传了 [from] / [to] 就只看这段时间；不传就全量。
  List<String> upstreamsWithin({
    String? apiKeyId,
    DateTime? from,
    DateTime? to,
  }) {
    final set = <String>{
      for (final r in query(apiKeyId: apiKeyId, from: from, to: to))
        r.upstream,
    };
    final list = set.toList()..sort();
    return list;
  }

  /// 一定范围内、可选按上游 / 模型 / 按 key 过滤的记录（时间倒序）。
  ///
  /// [apiKeyId] 为 `null` 表示不过滤；传**空串**特指「没带密钥的那些调用」。
  List<TokenUsage> query({
    String? upstream,
    String? model,
    String? apiKeyId,
    DateTime? from,
    DateTime? to,
  }) {
    final fromMs = from?.millisecondsSinceEpoch;
    final toMs = to?.millisecondsSinceEpoch;
    return [
      for (final r in _records)
        if ((upstream == null || r.upstream == upstream) &&
            (model == null || r.model == model) &&
            (apiKeyId == null || r.apiKeyId == apiKeyId) &&
            (fromMs == null || r.timeMs >= fromMs) &&
            (toMs == null || r.timeMs <= toMs))
          r,
    ];
  }

  UsageSummary summarize({
    String? upstream,
    String? model,
    String? apiKeyId,
    DateTime? from,
    DateTime? to,
  }) => UsageSummary.of(
    query(
      upstream: upstream,
      model: model,
      apiKeyId: apiKeyId,
      from: from,
      to: to,
    ),
  );

  /// 按天分桶（时间正序，空天不补 —— 图表自己按范围对齐）。
  List<UsageDay> byDay({
    String? upstream,
    String? model,
    String? apiKeyId,
    required DateTime from,
    DateTime? to,
  }) {
    final end = to ?? DateTime.now();
    final buckets = <DateTime, List<TokenUsage>>{};
    for (final r in query(
      upstream: upstream,
      model: model,
      apiKeyId: apiKeyId,
      from: from,
      to: end,
    )) {
      final at = DateTime.fromMillisecondsSinceEpoch(r.timeMs);
      final day = DateTime(at.year, at.month, at.day);
      buckets.putIfAbsent(day, () => []).add(r);
    }
    final days = buckets.keys.toList()..sort();
    return [
      for (final d in days)
        UsageDay(day: d, summary: UsageSummary.of(buckets[d]!)),
    ];
  }

  /// 按模型归堆（DeepSeek 账单页下面那张「各模型用量」表）。
  ///
  /// **只返回这段时间里真调用过的模型**，没打过的模型一行都不占。
  /// 排序默认按合计 token 从多到少。
  List<UsageModelUsage> byModel({
    String? upstream,
    String? apiKeyId,
    DateTime? from,
    DateTime? to,
  }) {
    final buckets = <String, List<TokenUsage>>{};
    for (final r in query(
      upstream: upstream,
      apiKeyId: apiKeyId,
      from: from,
      to: to,
    )) {
      buckets.putIfAbsent(r.model, () => []).add(r);
    }
    final out = <UsageModelUsage>[
      for (final e in buckets.entries)
        UsageModelUsage(model: e.key, summary: UsageSummary.of(e.value)),
    ];
    out.sort((a, b) => b.summary.total.compareTo(a.summary.total));
    return out;
  }

  /// 某把 key（+ 某个上游、某段时间）打过的模型名，按字母序。
  ///
  /// **只返回真打过的**：没调用过的模型不占下拉/表格的选项。
  /// [apiKeyId] 传 `null` = 不挑 key；传空串特指「没带密钥的那些调用」。
  List<String> modelsOfKey(
    String? apiKeyId, {
    String? upstream,
    DateTime? from,
    DateTime? to,
  }) {
    final set = <String>{
      for (final r in query(
        apiKeyId: apiKeyId,
        upstream: upstream,
        from: from,
        to: to,
      ))
        r.model,
    };
    final list = set.toList()..sort();
    return list;
  }

  // ---------------------------------------------------------- 日历

  /// 某一天（本地时区）的 00:00。
  static DateTime startOfDay(DateTime day) =>
      DateTime(day.year, day.month, day.day);

  /// 某个月的 1 号 00:00（日历页翻月用，比较只看年月）。
  static DateTime startOfMonth(DateTime month) =>
      DateTime(month.year, month.month);

  /// 这个月是不是「当月的日历」（回今天的按钮只在不看当月时出现）。
  static bool isCurrentMonth(DateTime month, {DateTime? now}) {
    final n = now ?? DateTime.now();
    return month.year == n.year && month.month == n.month;
  }

  /// 某一天的记录：[from, to) 左闭右开，避免把次日 00:00 算进来。
  List<TokenUsage> ofDay(DateTime day) {
    final from = startOfDay(day);
    // 减一毫秒：query 的 to 是闭区间，不减会把次日 00:00:00.000 那一条算进来。
    return query(
      from: from,
      to: from
          .add(const Duration(days: 1))
          .subtract(const Duration(milliseconds: 1)),
    );
  }

  /// 某天按模型分桶：用量多的排前面（日历页当天活动的卡片就是它）。
  List<UsageModelDay> modelsOfDay(DateTime day) {
    final buckets = <String, List<TokenUsage>>{};
    for (final r in ofDay(day)) {
      buckets.putIfAbsent(r.model, () => []).add(r);
    }
    final out = <UsageModelDay>[
      for (final e in buckets.entries)
        UsageModelDay(
          model: e.key,
          summary: UsageSummary.of(e.value),
          firstMs: e.value.last.timeMs,
          lastMs: e.value.first.timeMs,
        ),
    ];
    out.sort((a, b) => b.summary.total.compareTo(a.summary.total));
    return out;
  }

  /// 某个月的「天 → 汇总」表（日历打点用，没记录的天不进表）。
  Map<DateTime, UsageSummary> monthMap(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 1);
    return {for (final d in byDay(from: first, to: last)) d.day: d.summary};
  }
}

final UsageStats usageStats = UsageStats();

/// 从一段响应文本里把 `usage` 抠出来。
///
/// 流式响应里 `usage` 出现在最后一帧（有的网关每帧都给，取到的最新的那份
/// 就是累计值），非流式就是顶层对象。这里用「找最后一个 "usage" 键 + 配平
/// 花括号」的笨办法，避免把整个 SSE 流当 JSON 解析。
class UsageExtractor {
  UsageExtractor();

  /// 扫描缓冲区上限：usage 只可能在尾部，留 256KB 足够覆盖一帧里的它，
  /// 又不会因为长回答把内存撑起来。
  static const int _maxScan = 256 * 1024;

  final StringBuffer _tail = StringBuffer();
  int _scanned = 0;

  void addText(String chunk) {
    if (chunk.isEmpty) return;
    _tail.write(chunk);
    _scanned += chunk.length;
    if (_tail.length > _maxScan) {
      final keep = _tail.toString().substring(_tail.length - _maxScan);
      _tail
        ..clear()
        ..write(keep);
    }
  }

  void addBytes(List<int> bytes) =>
      addText(utf8.decode(bytes, allowMalformed: true));

  bool get hasData => _scanned > 0;

  /// 抠出来的用量；没找到返回 null。
  UsageTotals? extract() {
    final text = _tail.toString();
    final idx = text.lastIndexOf('"usage"');
    if (idx < 0) return null;
    final brace = text.indexOf('{', idx);
    if (brace < 0) return null;

    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = brace; i < text.length; i++) {
      final c = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
        continue;
      }
      if (c == '{') depth++;
      if (c == '}') {
        depth--;
        if (depth == 0) {
          final slice = text.substring(brace, i + 1);
          try {
            final decoded = jsonDecode(slice);
            if (decoded is Map<String, dynamic>) {
              return UsageTotals.fromUsage(decoded);
            }
          } catch (_) {
            return null;
          }
          return null;
        }
      }
    }
    return null;
  }
}

/// 从 `usage` 对象里读出来的四个数字（各家字段名统一到这里）。
class UsageTotals {
  const UsageTotals({
    required this.input,
    required this.output,
    required this.cacheHit,
    required this.cacheMiss,
    required this.reasoning,
  });

  final int input;
  final int output;
  final int cacheHit;
  final int cacheMiss;
  final int reasoning;

  bool get isEmpty =>
      input == 0 && output == 0 && cacheHit == 0 && cacheMiss == 0;

  static UsageTotals fromUsage(Map<String, dynamic> usage) {
    int num_(String key) {
      final v = usage[key];
      return v is num ? v.toInt() : 0;
    }

    final input = num_('prompt_tokens') + num_('input_tokens');
    final output = num_('completion_tokens') + num_('output_tokens');

    // 命中：DeepSeek 系的 prompt_cache_hit_tokens，OpenAI 系的
    // prompt_tokens_details.cached_tokens（Anthropic 侧由转译器归一过）。
    var hit = num_('prompt_cache_hit_tokens');
    if (hit == 0) {
      final details = usage['prompt_tokens_details'];
      if (details is Map<String, dynamic>) {
        final cached = details['cached_tokens'];
        if (cached is num) hit = cached.toInt();
      }
    }
    var miss = num_('prompt_cache_miss_tokens');
    if (miss == 0 && input > 0) {
      // 上游只给了命中数：未命中 = 输入 - 命中（不小于 0）。
      miss = input - hit < 0 ? 0 : input - hit;
    }

    var reasoning = num_('reasoning_tokens');
    if (reasoning == 0) {
      final details = usage['completion_tokens_details'];
      if (details is Map<String, dynamic>) {
        final r = details['reasoning_tokens'];
        if (r is num) reasoning = r.toInt();
      }
    }

    return UsageTotals(
      input: input,
      output: output,
      cacheHit: hit,
      cacheMiss: miss,
      reasoning: reasoning,
    );
  }
}
