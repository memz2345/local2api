/// 思考档位（thinking level / reasoning effort）。
///
/// ## 为什么是 7 档而不是 3 档
///
/// 早先这里只留 low / medium / high 三档，结果客户端要 `max`、`xhigh`
/// 这类档位时被**折叠成 high**，`none` 和 `minimal` 被折叠成 low —— 同一个
/// 请求换个客户端写法就换档，这就是「档位不稳定」的根因。现在按从轻到重
/// 保留全部七档，转发时原样下发，不再折叠。
///
/// ## 各家认的字段（转发时按 [ThinkingWireFormat] 选一种写）
///
/// | 上游 | 字段 | 认的字面量 |
/// |---|---|---|
/// | DeepSeek 官方 chat | `reasoning_effort` | none / low / high / max（minimal→low、medium·xhigh→high、ultra→max，默认 high） |
/// | DeepSeek 官方 chat（老写法） | `thinking:{type}` | enabled / disabled |
/// | DeepSeek Responses | `reasoning:{effort}` | none / low / high / max |
/// | OpenAI chat / OpenRouter | `reasoning_effort`、`reasoning:{effort}` | minimal / low / medium / high / xhigh |
/// | Anthropic | `thinking:{type, budget_tokens}` | enabled / disabled |
///
/// DeepSeek 官方**思考模式默认开、强度默认 high**，所以「不带字段」并不等于
/// 「不思考」—— 想表达就一定要写下发（见 [applyThinkingDefaults]）。
///
/// ## 档位降不下去怎么办
///
/// `xhigh` / `max` 是**按模型可选**的（pi-ai 的 `getSupportedThinkingLevels`
/// 就是干这个的）：上游不认就 400。所以有了 [downgradeThinkingLevel] ——
/// `max → xhigh → high → medium → low → minimal → none → off`，逐级退，
/// 退到 `off` 就是彻底不写字段（交给上游默认）。
library;

/// 一档思考强度。按从轻到重排列（枚举顺序即降级顺序的逆序）。
enum ThinkingLevel {
  /// 不下发：一个思考字段都不写，完全交给上游默认。
  ///
  /// 与 [none] 的区别：none 是**显式关**（写 `reasoning_effort: none`），
  /// off 是**不表达**。上游默认不开思考时这两者结果一样，默认开时不一样。
  off,

  /// 显式关思考（`reasoning_effort: "none"` / `thinking:{type:"disabled"}`）。
  none,

  /// 极轻。DeepSeek 认它（映射到 low），OpenAI Responses 也认。
  minimal,

  /// 轻。
  low,

  /// 中。OpenAI 认；DeepSeek 不认（会映射到 high）。
  medium,

  /// 重。绝大多数上游的默认档。
  high,

  /// 很重。OpenAI 认；DeepSeek **不认**（官方映射表里没有它）。
  xhigh,

  /// 最重。DeepSeek 与 OpenAI 都认。
  max,
}

/// 档位往上游下发时的**线上形状**。
///
/// 各家认的字段不一样，发错轻则被忽略、重则 400，所以做成上游可选：
/// - [effort]：写 OpenAI 的 `reasoning_effort`（DeepSeek / OpenRouter /
///   多数中转站认）；
/// - [thinking]：写 DeepSeek 官方的 `thinking: {type}`；
/// - [both]：两个都写（有些站要同时看到才开思考）；
/// - [budget]：不写思考字段，只把输出预算钳到档位值 —— 唯一「对任何
///   OpenAI 兼容端点都不会报错」的安全档，也是 OpenCode Zen 这种「收了
///   reasoning_effort 但忽略」的网关实际吃的控制。
///
/// 除 [budget] 外，任一形状都会**同时按档位钳一次输出预算**（见
/// [thinkingBudget]）：预算是唯一对任何上游都真实生效的那一路。
enum ThinkingWireFormat { effort, thinking, both, budget }

extension ThinkingWireFormatX on ThinkingWireFormat {
  String get id => name;

  static ThinkingWireFormat fromId(String? id) => switch (id) {
    'effort' => ThinkingWireFormat.effort,
    'thinking' => ThinkingWireFormat.thinking,
    'both' => ThinkingWireFormat.both,
    'budget' => ThinkingWireFormat.budget,
    _ => ThinkingWireFormat.effort,
  };

  /// 这一族会不会真的往请求体里写思考字段（写了才可能被上游 400 拒）。
  bool get sendsLevel => this != ThinkingWireFormat.budget;
}

/// 降级链：从 [level] 往下一档（已是最底返回 null）。
///
/// `max → xhigh → high → medium → low → minimal → none → off`。
/// `off` 是最后一步（彻底不写字段），再往下没有了。
ThinkingLevel? downgradeThinkingLevel(ThinkingLevel level) => switch (level) {
  ThinkingLevel.max => ThinkingLevel.xhigh,
  ThinkingLevel.xhigh => ThinkingLevel.high,
  ThinkingLevel.high => ThinkingLevel.medium,
  ThinkingLevel.medium => ThinkingLevel.low,
  ThinkingLevel.low => ThinkingLevel.minimal,
  ThinkingLevel.minimal => ThinkingLevel.none,
  ThinkingLevel.none => ThinkingLevel.off,
  ThinkingLevel.off => null,
};

/// 档位往上游写时的字面量（各家自己那套拼写）。
String thinkingWireValue(ThinkingLevel level) => switch (level) {
  ThinkingLevel.off => '',
  ThinkingLevel.none => 'none',
  ThinkingLevel.minimal => 'minimal',
  ThinkingLevel.low => 'low',
  ThinkingLevel.medium => 'medium',
  ThinkingLevel.high => 'high',
  ThinkingLevel.xhigh => 'xhigh',
  ThinkingLevel.max => 'max',
};

/// 把档位按 [wire] 指定的形状写进请求体（覆盖式，幂等）。
///
/// [capacity] 是这条对外模型声明的输出上限，用来按档位钳预算。
/// 返回实际写下去的档位（[ThinkingLevel.off] 表示把字段全删了）。
ThinkingLevel writeThinkingLevel(
  Map<String, dynamic> body,
  ThinkingLevel level, {
  required ThinkingWireFormat wire,
  int capacity = 0,
}) {
  switch (wire) {
    case ThinkingWireFormat.effort:
      if (level == ThinkingLevel.off) {
        body.remove('reasoning_effort');
      } else {
        body['reasoning_effort'] = thinkingWireValue(level);
      }
    case ThinkingWireFormat.thinking:
      if (level == ThinkingLevel.off) {
        body.remove('thinking');
      } else {
        body['thinking'] = {
          'type': level == ThinkingLevel.none ? 'disabled' : 'enabled',
        };
      }
    case ThinkingWireFormat.both:
      if (level == ThinkingLevel.off) {
        body.remove('reasoning_effort');
        body.remove('thinking');
      } else {
        body['reasoning_effort'] = thinkingWireValue(level);
        body['thinking'] = {
          'type': level == ThinkingLevel.none ? 'disabled' : 'enabled',
        };
      }
    case ThinkingWireFormat.budget:
      // 只动预算，不写思考字段。
      break;
  }
  _clampBudget(body, level, capacity: capacity);
  return level;
}

/// 按档位把输出预算钳到客户端正在用的那个键上。
void _clampBudget(
  Map<String, dynamic> body,
  ThinkingLevel level, {
  required int capacity,
}) {
  final budget = thinkingBudget(
    level,
    capacity: capacity,
    requested: _requestedBudget(body),
  );
  if (body['max_completion_tokens'] is num) {
    body['max_completion_tokens'] = budget;
  }
  if (body['max_tokens'] is num) {
    body['max_tokens'] = budget;
  }
  if (body['max_tokens'] is! num && body['max_completion_tokens'] is! num) {
    body['max_tokens'] = budget;
  }
}

/// 客户端没显式要档位时，按上游配置补一个默认档，并把它写成 [wire] 指定的形状。
///
/// 规矩很简单：**客户端发了就算数，我们一个字都不改**（[ThinkingLevel] 从请求体
/// 里读得到就直接返回）；读不到才用 [defaultLevelId]（'' = 不干预）补。
/// 返回最终生效的档位（null = 客户端没发、上游也没配）。
///
/// 无论哪种形状都会顺带按档位钳一次输出预算 —— 预算是唯一对所有上游都
/// 真实生效的控制（OpenCode Zen 那边档位只有这一条路）。
///
/// 为什么需要它：第三方 agent（如 pi-ai 系的 DeepSeek Harness）只有在自己的
/// 目录/profile 里认得这个模型时才发 `reasoning_effort`，自定义端点的模型
/// 多半什么都不发 —— 于是档位全靠上游默认，各家默认值还不一样。这一层让
/// 网关侧可以把档位钉死。
ThinkingLevel? applyThinkingDefaults(
  Map<String, dynamic> body, {
  required String defaultLevelId,
  ThinkingWireFormat wire = ThinkingWireFormat.effort,
  int capacity = 0,
}) {
  // 客户端自己表达了就听它的：任何一家写法（reasoning_effort / thinking /
  // 嵌套 reasoning / 模型名后缀）都算。
  final fromClient = thinkingLevelOf(body);
  if (fromClient != null) return fromClient;
  if (defaultLevelId.isEmpty) return null;
  final level = thinkingLevelFromName(defaultLevelId);
  if (level == null) return null;
  return writeThinkingLevel(body, level, wire: wire, capacity: capacity);
}

/// 客户端显式要的输出预算（0 = 没给）。两个键名都认。
int _requestedBudget(Map<String, dynamic> body) {
  final v = body['max_tokens'] ?? body['max_completion_tokens'];
  return v is num && v > 0 ? v.toInt() : 0;
}

/// 对外声明的档位 id（顺序 = 选择器里的展示顺序）。
///
/// `off` 不在其中：它表示「不表达」，不是一档强度。
const List<String> kThinkingLevelIds = [
  'none',
  'minimal',
  'low',
  'medium',
  'high',
  'xhigh',
  'max',
];

/// 上游「默认档位」下拉里可选的 id（含「不下发」）。
const List<String> kThinkingDefaultIds = ['off', ...kThinkingLevelIds];

/// 默认档：重思考（DeepSeek / OpenAI 的默认强度都是 high）。
const ThinkingLevel kDefaultThinkingLevel = ThinkingLevel.high;

/// 各档的输出预算（0 = 用模型自己的上限，不额外压）。
///
/// 沿用活体探测过的阶梯：2048 / 8192 / 不设限（中间档按相邻档插值）。
/// `off` 也要钳 —— 它只是不下发字段，预算仍然按「不表达」处理为不设限。
int thinkingCeiling(ThinkingLevel level) => switch (level) {
  ThinkingLevel.off => 0,
  ThinkingLevel.none => 1024,
  ThinkingLevel.minimal => 2048,
  ThinkingLevel.low => 4096,
  ThinkingLevel.medium => 8192,
  ThinkingLevel.high => 0,
  ThinkingLevel.xhigh => 0,
  ThinkingLevel.max => 0,
};

/// 预算下限：再轻的档也不至于把回答截断成几个字。
const int kThinkingMinBudget = 512;

/// 各家档位名 → 我们的档位。
///
/// 入站不折叠：`none` 与 `minimal` 是两回事（前者显式关、后者极轻），
/// `xhigh` 与 `max` 也是两回事 —— 折叠会让「换个客户端写法就换档」。
const Map<String, ThinkingLevel> _aliases = {
  'off': ThinkingLevel.off,
  'none': ThinkingLevel.none,
  'disable': ThinkingLevel.none,
  'disabled': ThinkingLevel.none,
  'minimal': ThinkingLevel.minimal,
  'low': ThinkingLevel.low,
  'light': ThinkingLevel.low,
  'medium': ThinkingLevel.medium,
  'balanced': ThinkingLevel.medium,
  'default': ThinkingLevel.high,
  'high': ThinkingLevel.high,
  'xhigh': ThinkingLevel.xhigh,
  'ultra': ThinkingLevel.max,
  'max': ThinkingLevel.max,
  'deep': ThinkingLevel.max,
};

/// 模型名尾部的 `(档位)` 后缀（opencode 的 variant 就是这么发的）。
final RegExp _suffixRe = RegExp(r'\(([^()]+)\)\s*$');

/// 单个档位名 → 档位（认不出返回 null）。
ThinkingLevel? thinkingLevelFromName(Object? value) {
  if (value is! String) return null;
  final s = value.trim().toLowerCase();
  return s.isEmpty ? null : _aliases[s];
}

/// 从模型名尾部剥出档位（`gpt-5 (high)` → high）。
ThinkingLevel? thinkingLevelFromModelName(Object? model) {
  if (model is! String) return null;
  final m = _suffixRe.firstMatch(model.trim());
  return m == null ? null : thinkingLevelFromName(m.group(1));
}

/// 从请求体里读出客户端要的档位。
///
/// 依次认：`reasoning_effort`、`reasoning.effort`（Anthropic）、
/// `thinking.type` / `thinking.effort`（DeepSeek）、`output_config.effort`
/// （Responses），最后是模型名后缀。
ThinkingLevel? thinkingLevelOf(Map<String, dynamic> body, {Object? model}) {
  ThinkingLevel? from(Object? v) => thinkingLevelFromName(v);

  final direct = from(body['reasoning_effort']);
  if (direct != null) return direct;

  final reasoning = body['reasoning'];
  if (reasoning is Map) {
    final l = from(reasoning['effort']);
    if (l != null) return l;
  }

  final thinking = body['thinking'];
  if (thinking is Map) {
    final byEffort = from(thinking['effort']);
    if (byEffort != null) return byEffort;
    // DeepSeek 的开关形态：enabled = 开思考（按默认档），disabled = 关。
    final type = thinking['type'];
    if (type is String) {
      final t = type.trim().toLowerCase();
      if (t == 'enabled') return kDefaultThinkingLevel;
      if (t == 'disabled') return ThinkingLevel.none;
    }
  }

  final outputConfig = body['output_config'];
  if (outputConfig is Map) {
    final l = from(outputConfig['effort']);
    if (l != null) return l;
  }

  return thinkingLevelFromModelName(model ?? body['model']);
}

/// 这一档实际给多少输出预算。
///
/// [capacity] 是模型声明的输出上限（没配用 [fallback]）；[requested] 是
/// 客户端显式给的 `max_tokens`。语义对齐 zen-gate（issue #23 / #27）：
/// **轻档是硬钳制** —— 档位上限压过一切，客户端要得再多也压到档位上；
/// **重档不额外设限** —— 用客户端要的数（有就优先）或模型上限，不再被
/// 「猜出来的默认值」压回去。
int thinkingBudget(
  ThinkingLevel level, {
  required int capacity,
  int fallback = 32768,
  int requested = 0,
}) {
  var cap = capacity > 0 ? capacity : fallback;
  if (requested > 0) cap = requested;
  final ceiling = thinkingCeiling(level);
  final want = ceiling <= 0 ? cap : (ceiling < cap ? ceiling : cap);
  return want < kThinkingMinBudget ? kThinkingMinBudget : want;
}
