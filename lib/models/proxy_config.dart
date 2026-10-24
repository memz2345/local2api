import 'dart:math';

import '../l10n/app_localizations.dart';
import '../services/model_schedule.dart';
import 'thinking_level.dart';

/// 峰谷策略页能选的单个模型：所有启用上游里已暴露的对外名（去重保序）。
///
/// 放在模型文件里而不是服务里，是因为 `model_schedule.dart` 刻意只放纯逻辑，
/// 而 `proxy_config.dart` 已经单向依赖它 —— 反过来引就会成环。
List<String> scheduleModelNames(ProxyConfig config) => <String>{
  for (final u in config.upstreams)
    if (u.enabled)
      for (final m in u.models)
        if (m.enabled && m.publicName.trim().isNotEmpty) m.publicName.trim(),
}.toList();

/// 某个上游「自己那摊」的峰谷策略：目标命中它的任一对外模型，或命中它的
/// 配置档案 id（老数据里的组级规则）。
///
/// 上游编辑页的「峰谷时段」区块按这个筛，别的地方（总览页）看全量。
List<ScheduleRule> scheduleRulesOfUpstream(
  ProxyConfig config, {
  required List<String> modelNames,
  String? managedBy,
}) {
  final names = <String>{
    for (final m in modelNames)
      if (m.trim().isNotEmpty) m.trim(),
  };
  final gid = managedBy?.trim();
  return [
    for (final r in config.scheduleRules)
      if (r.targets.any(names.contains) ||
          (gid != null && gid.isNotEmpty && r.targets.contains(gid)))
        r,
  ];
}

/// 时段的展示文案：`9:00 - 18:00`，整天走「全天」。
String scheduleHourRangeLabel(AppLocalizations l10n, int start, int end) {
  if (end >= 24 && start == 0) return l10n.scheduleAllDay;
  return l10n.scheduleHourRange('$start', '$end');
}

/// 上游类型。
///
/// [openai] / [llamacpp] / [ollama] 走 OpenAI 兼容协议，区别只在默认端口与
/// 模型列表获取方式；[anthropic] 走 Anthropic Messages 协议（DeepSeek 的
/// `https://api.deepseek.com/anthropic`、Claude 官方 API 都是这一套），
/// 代理会替客户端做 OpenAI ⇄ Anthropic 的双向翻译。
enum UpstreamType { openai, llamacpp, ollama, anthropic, localTts }

extension UpstreamTypeX on UpstreamType {
  String get id => switch (this) {
    UpstreamType.openai => 'openai',
    UpstreamType.llamacpp => 'llamacpp',
    UpstreamType.ollama => 'ollama',
    UpstreamType.anthropic => 'anthropic',
    UpstreamType.localTts => 'localtts',
  };

  static UpstreamType fromId(String id) => switch (id) {
    'llamacpp' => UpstreamType.llamacpp,
    'ollama' => UpstreamType.ollama,
    'anthropic' => UpstreamType.anthropic,
    'localtts' => UpstreamType.localTts,
    _ => UpstreamType.openai,
  };

  /// 该类型常用的默认 Base URL（新建上游时填入表单）。
  String get defaultBaseUrl => switch (this) {
    UpstreamType.openai => 'https://api.openai.com/v1',
    UpstreamType.llamacpp => 'http://192.168.1.10:8080/v1',
    UpstreamType.ollama => 'http://192.168.1.10:11434/v1',
    // DeepSeek 的 Anthropic 兼容入口（官方文档 base_url 原样带 /anthropic）。
    UpstreamType.anthropic => 'https://api.deepseek.com/anthropic',
    UpstreamType.localTts => '',
  };

  /// 走 Anthropic Messages 协议的上游：请求要重新编码，回包要回译。
  bool get speaksAnthropic => this == UpstreamType.anthropic;

  /// 本地 TTS 上游没有远端：不出 URL / 密钥 / 连通性测试这些行。
  bool get isLocal => this == UpstreamType.localTts;
}

/// 上游模态：对外转发哪种请求。
///
/// - chat：普通 OpenAI 兼容聊天/补全（缺省，老配置没有该字段时也按它算）。
/// - audio：语音类上游（如 MiMo 的 mimo-v2.5-tts）——`/v1/audio/speech`
///   会把 OpenAI TTS 请求翻译成 chat.completions + audio 参数发过去，
///   再把回包里的 base64 音频解成原始字节给客户端。
enum UpstreamModality { chat, audio }

extension UpstreamModalityX on UpstreamModality {
  String get id => switch (this) {
    UpstreamModality.chat => 'chat',
    UpstreamModality.audio => 'audio',
  };

  static UpstreamModality fromId(String id) => switch (id) {
    'audio' => UpstreamModality.audio,
    _ => UpstreamModality.chat,
  };
}

/// 没配上下文长度时对外声明的默认值（1M）。
///
/// 客户端（opencode 这类 agent）靠 `/v1/models` 里的上下文长度决定
/// 何时自动压缩历史；不给值它就当"未知"，一路聊到撞墙才报错。默认写
/// 1M 是「宁可晚压缩」的保守选择，具体模型可在模型编辑里单独改。
const int kDefaultContextLength = 1000000;

/// 内置上游（Zen / MiMo）的默认自动更新间隔：7 天一次。
const int kAutoRefreshHoursBuiltin = 24 * 7;

/// 自动更新模型列表的间隔挡位（小时）。0 = 关闭。
///
/// 只留这几档：上游模型清单变动是「周」级别的，小时级刷新纯属浪费流量。
const List<int> kAutoRefreshHourChoices = [0, 24, 24 * 3, 24 * 7, 24 * 30];

/// 对外暴露的一个模型：publicName 是客户端看到的 model，
/// target 是转发到上游时实际写入 body 的 model（别名映射）。
class ModelEntry {
  String publicName;
  String target;
  bool enabled;

  /// 有序回退车道：target 失败（403 / 429 / 5xx / 连不上）时依次改试这些上游模型名。
  /// 空 = 不回退。广场的「免费车道容灾」预设会填它。
  List<String> fallbacks;

  /// 对外声明的上下文长度（token）。0 = 没配：
  /// - `/v1/models` 对外回退 [kDefaultContextLength]；
  /// - 「拉取模型列表」时上游顺带给了 context_length 之类的字段就自动补上。
  int contextLength;

  /// 对外声明的最大输出 token 数。0 = 没配：`/v1/models` 就不带
  /// `max_output_tokens` 字段（别替没配的模型瞎编输出上限）。
  /// 上下文占用环的 tooltip 会把它亮出来。
  int maxOutputTokens;

  ModelEntry({
    required this.publicName,
    String? target,
    this.enabled = true,
    List<String>? fallbacks,
    this.contextLength = 0,
    this.maxOutputTokens = 0,
  }) : target = target ?? publicName,
       fallbacks = fallbacks ?? [];

  /// 对外实际声明的上下文长度（没配就是默认 1M）。
  int get effectiveContextLength =>
      contextLength > 0 ? contextLength : kDefaultContextLength;

  /// 行尾的紧凑显示（1M / 128K / 32768），没配返回空串。
  String get contextLabel {
    final n = contextLength;
    if (n <= 0) return '';
    if (n >= 1000000) {
      final v = n / 1000000;
      return v == v.roundToDouble() ? '${v.toInt()}M' : '${v}M';
    }
    if (n >= 1000) return '${(n / 1000).round()}K';
    return '$n';
  }

  /// 实际尝试顺序：target 打头，去掉空值与重复项。
  List<String> get attempts {
    final out = <String>[];
    for (final m in [target, ...fallbacks]) {
      final t = m.trim();
      if (t.isNotEmpty && !out.contains(t)) out.add(t);
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
    'publicName': publicName,
    'target': target,
    'enabled': enabled,
    'fallbacks': fallbacks,
    // 没配就不落盘：老配置读进来照样是 0，文件也保持干净。
    if (contextLength > 0) 'contextLength': contextLength,
    if (maxOutputTokens > 0) 'maxOutputTokens': maxOutputTokens,
  };

  factory ModelEntry.fromJson(Map<String, dynamic> j) => ModelEntry(
    publicName: (j['publicName'] as String?) ?? '',
    target: j['target'] as String?,
    enabled: (j['enabled'] as bool?) ?? true,
    fallbacks: [for (final f in (j['fallbacks'] as List? ?? const [])) '$f'],
    contextLength: (j['contextLength'] as num?)?.toInt() ?? 0,
    maxOutputTokens: (j['maxOutputTokens'] as num?)?.toInt() ?? 0,
  );
}

/// 一个上游服务（llama.cpp / Ollama / 任意 OpenAI 兼容端点）。
class Upstream {
  String id;
  String name;
  UpstreamType type;
  String baseUrl;
  String apiKey;

  /// 上游模态（audio = 语音类上游，/v1/audio/speech 走 TTS 翻译）。
  ///
  /// 缺省 chat：老配置 JSON 里没有该字段时反序列化直接给 chat，
  /// 行为与旧版本完全一致。
  UpstreamModality modality;

  /// 用户给这个上游写的备注（「这是干嘛的 / 有什么坑」）。
  ///
  /// 与 [name] 分开：名字是给它起的名，备注是自由文本说明。
  /// 空串表示没写。随配置 JSON 一起落盘。
  String note;

  bool enabled;
  List<ModelEntry> models;

  /// 装进这个上游的配置档案 id；null = 用户在「模型」页手加的。
  ///
  /// 档案激活/停用时只动归属自己的上游，绝不去碰用户自建的那些 ——
  /// 归属真相放在配置里而不是另立一本账，是因为用户在「模型」页
  /// 改名、删除上游时账本会悄悄漂移。
  String? managedBy;

  /// 默认思考档位（'' = 不干预；否则 none / minimal / low / medium / high /
  /// xhigh / max / off）。
  ///
  /// **只在客户端自己没发档位时生效** —— 第三方 agent（pi-ai 那类）对
  /// 自定义端点的模型往往一个思考字段都不发，档位全靠上游默认（各家默认值
  /// 还不一样）。这一行让网关把档位钉死。
  String thinkingDefault;

  /// 补档时往上游下发的形状，见 [ThinkingWireFormat]。
  ///
  /// 默认 [ThinkingWireFormat.effort]（写 `reasoning_effort`）：DeepSeek /
  /// OpenAI / OpenRouter 都认，且上游不认时会触发档位降级链兜底
  /// （见 `ProxyServer._attemptHop`）。
  ThinkingWireFormat thinkingWire;

  /// 自动更新模型列表的间隔（小时）。0 = 关闭。
  ///
  /// 开着时 [ModelAutoRefresh] 会在「距上次刷新超过这个间隔」时去上游拉一次
  /// `/models`，并按上游清单**增删**（新上的补进来、下架的删掉）。
  /// 内置的 Zen / MiMo 默认 [kAutoRefreshHoursBuiltin]（7 天一次）。
  int autoRefreshHours;

  /// 上次自动（或手动触发的那次）刷新模型列表的时间（毫秒时间戳）。
  /// 0 = 从来没刷新过 —— 首次进入应用时就会刷一次。
  int modelsRefreshedAtMs;

  Upstream({
    required this.id,
    required this.name,
    this.type = UpstreamType.openai,
    required this.baseUrl,
    this.apiKey = '',
    this.modality = UpstreamModality.chat,
    this.note = '',
    this.enabled = true,
    this.managedBy,
    this.thinkingDefault = '',
    this.thinkingWire = ThinkingWireFormat.effort,
    this.autoRefreshHours = 0,
    this.modelsRefreshedAtMs = 0,
    List<ModelEntry>? models,
  }) : models = models ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.id,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    // 只在 audio 时落盘：老配置文件保持干净，读进来缺字段即 chat。
    if (modality != UpstreamModality.chat) 'modality': modality.id,
    if (note.trim().isNotEmpty) 'note': note,
    // 思考档位同理：没配过就不写，老配置与别人的档案都不被我们撑肥。
    if (thinkingDefault.isNotEmpty) 'thinkingDefault': thinkingDefault,
    if (thinkingDefault.isNotEmpty) 'thinkingWire': thinkingWire.id,
    'enabled': enabled,
    'managedBy': managedBy,
    // 自动更新同理：只写非默认值，老配置与别人的档案不被撑肥。
    if (autoRefreshHours > 0) 'autoRefreshHours': autoRefreshHours,
    if (modelsRefreshedAtMs > 0) 'modelsRefreshedAtMs': modelsRefreshedAtMs,
    'models': [for (final m in models) m.toJson()],
  };

  factory Upstream.fromJson(Map<String, dynamic> j) => Upstream(
    id: (j['id'] as String?) ?? '',
    name: (j['name'] as String?) ?? '',
    type: UpstreamTypeX.fromId((j['type'] as String?) ?? 'openai'),
    baseUrl: (j['baseUrl'] as String?) ?? '',
    apiKey: (j['apiKey'] as String?) ?? '',
    modality: UpstreamModalityX.fromId((j['modality'] as String?) ?? 'chat'),
    note: (j['note'] as String?) ?? '',
    enabled: (j['enabled'] as bool?) ?? true,
    managedBy: j['managedBy'] as String?,
    thinkingDefault: (j['thinkingDefault'] as String?) ?? '',
    thinkingWire: ThinkingWireFormatX.fromId(j['thinkingWire'] as String?),
    autoRefreshHours: (j['autoRefreshHours'] as num?)?.toInt() ?? 0,
    modelsRefreshedAtMs: (j['modelsRefreshedAtMs'] as num?)?.toInt() ?? 0,
    models: [
      for (final m in (j['models'] as List? ?? []))
        if (m is Map<String, dynamic>) ModelEntry.fromJson(m),
    ],
  );
}

/// 发给客户端的一层 API 密钥。
class ApiKeyEntry {
  String id;
  String name;
  String key;
  bool enabled;
  int createdAtMs;

  ApiKeyEntry({
    required this.id,
    required this.name,
    required this.key,
    this.enabled = true,
    int? createdAtMs,
  }) : createdAtMs = createdAtMs ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'key': key,
    'enabled': enabled,
    'createdAtMs': createdAtMs,
  };

  factory ApiKeyEntry.fromJson(Map<String, dynamic> j) => ApiKeyEntry(
    id: (j['id'] as String?) ?? '',
    name: (j['name'] as String?) ?? '',
    key: (j['key'] as String?) ?? '',
    enabled: (j['enabled'] as bool?) ?? true,
    createdAtMs: j['createdAtMs'] as int?,
  );

  /// 生成 sk- 前缀的随机密钥。
  static String generate() {
    final rand = Random.secure();
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return 'sk-${List.generate(48, (_) => chars[rand.nextInt(chars.length)]).join()}';
  }
}

/// 一条 IP 访问规则（CIDR）。allow=true 放行，false 拒绝。
class CidrRule {
  String id;
  String cidr;
  bool allow;
  bool enabled;

  CidrRule({
    required this.id,
    required this.cidr,
    this.allow = true,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'cidr': cidr,
    'allow': allow,
    'enabled': enabled,
  };

  factory CidrRule.fromJson(Map<String, dynamic> j) => CidrRule(
    id: (j['id'] as String?) ?? '',
    cidr: (j['cidr'] as String?) ?? '',
    allow: (j['allow'] as bool?) ?? true,
    enabled: (j['enabled'] as bool?) ?? true,
  );
}

/// 整份可持久化配置。
class ProxyConfig {
  int listenPort;

  /// '0.0.0.0'（所有网卡）或 '127.0.0.1'（仅本机）。
  String listenHost;
  List<Upstream> upstreams;
  List<ApiKeyEntry> apiKeys;
  List<CidrRule> cidrRules;
  bool corsEnabled;
  bool autoStart;

  /// Cloudflare Tunnel（trycloudflare）：是否启用内建隧道。
  /// 启用前必须先同意 Cloudflare 服务条款（见 [cloudflaredAgreedMs]）。
  bool cloudflaredEnabled;

  /// 同意 Cloudflare 服务条款的时间戳（ms）；0 = 还没同意过。
  /// 同意一次永久有效，关掉隧道不撤回同意。
  int cloudflaredAgreedMs;

  /// 临时 WebUI：独立于 API 转发端口的本机网页控制台开关。
  ///
  /// 默认关 —— 它只是「临时拉起来看一眼」的旁路，不该常驻占端口。
  bool webUiEnabled;

  /// 临时 WebUI 的监听端口，与 [listenPort] 完全独立。
  /// 分开是因为转发口往往是客户端写死的地址，不该被调试页面挤占。
  int webUiPort;

  /// 临时 WebUI 的监听地址；同上，与 [listenHost] 独立。
  String webUiHost;

  /// 峰谷时段策略：给单个对外模型或整个模型组套「星期 + 小时」窗口。
  ///
  /// 放在这一层而不是档案里，是因为订阅类档案每次更新都会整份换掉文档，
  /// 写进去的策略会被下一次拉取覆盖（与 `ProfileStore._labels` 同理）。
  List<ScheduleRule> scheduleRules;

  ProxyConfig({
    this.listenPort = 9292,
    this.listenHost = '0.0.0.0',
    List<Upstream>? upstreams,
    List<ApiKeyEntry>? apiKeys,
    List<CidrRule>? cidrRules,
    this.corsEnabled = true,
    this.autoStart = false,
    this.cloudflaredEnabled = false,
    this.cloudflaredAgreedMs = 0,
    this.webUiEnabled = false,
    this.webUiPort = 9293,
    this.webUiHost = '127.0.0.1',
    List<ScheduleRule>? scheduleRules,
  }) : upstreams = upstreams ?? [],
       apiKeys = apiKeys ?? [],
       cidrRules = cidrRules ?? [],
       scheduleRules = scheduleRules ?? [];

  ProxyConfig copy() => ProxyConfig.fromJson(toJson());

  Map<String, dynamic> toJson() => {
    'listenPort': listenPort,
    'listenHost': listenHost,
    'upstreams': [for (final u in upstreams) u.toJson()],
    'apiKeys': [for (final k in apiKeys) k.toJson()],
    'cidrRules': [for (final r in cidrRules) r.toJson()],
    'corsEnabled': corsEnabled,
    'autoStart': autoStart,
    'cloudflaredEnabled': cloudflaredEnabled,
    'cloudflaredAgreedMs': cloudflaredAgreedMs,
    'webUiEnabled': webUiEnabled,
    'webUiPort': webUiPort,
    'webUiHost': webUiHost,
    // 策略为空时不写这个键：老配置不该被灌一堆空数组
    if (scheduleRules.isNotEmpty)
      'scheduleRules': [for (final r in scheduleRules) r.toJson()],
  };

  factory ProxyConfig.fromJson(Map<String, dynamic> j) => ProxyConfig(
    listenPort: (j['listenPort'] as num?)?.toInt() ?? 9292,
    listenHost: (j['listenHost'] as String?) ?? '0.0.0.0',
    upstreams: [
      for (final u in (j['upstreams'] as List? ?? []))
        if (u is Map<String, dynamic>) Upstream.fromJson(u),
    ],
    apiKeys: [
      for (final k in (j['apiKeys'] as List? ?? []))
        if (k is Map<String, dynamic>) ApiKeyEntry.fromJson(k),
    ],
    cidrRules: [
      for (final r in (j['cidrRules'] as List? ?? []))
        if (r is Map<String, dynamic>) CidrRule.fromJson(r),
    ],
    corsEnabled: (j['corsEnabled'] as bool?) ?? true,
    autoStart: (j['autoStart'] as bool?) ?? false,
    cloudflaredEnabled: (j['cloudflaredEnabled'] as bool?) ?? false,
    cloudflaredAgreedMs: (j['cloudflaredAgreedMs'] as num?)?.toInt() ?? 0,
    webUiEnabled: (j['webUiEnabled'] as bool?) ?? false,
    webUiPort: (j['webUiPort'] as num?)?.toInt() ?? 9293,
    webUiHost: (j['webUiHost'] as String?) ?? '127.0.0.1',
    scheduleRules: [
      for (final r in (j['scheduleRules'] as List? ?? const []))
        if (r is Map<String, dynamic>) ScheduleRule.fromJson(r),
    ],
  );
}
