import 'config_profile.dart';
import 'proxy_config.dart';

/// OpenCode Zen 的 OpenAI 兼容端点（实测：GET /v1/models 免鉴权可用）。
const String kOpenCodeZenBaseUrl = 'https://opencode.ai/zen/v1';

/// 内置档案装出来的上游 id。
///
/// 沿用「广场」时代的旧值、刻意不改名：老用户的 ProxyConfig 里已经存着这个
/// id 的上游，改名会让迁移认不出归属，把他们手调过的车道开关和回退顺序丢掉。
const String kZenUpstreamId = 'plaza-opencode-zen';

/// 内置档案 id，也是发现页上那张默认卡片。
const String kZenProfileId = 'opencodezen';

/// 容灾路由对外暴露的模型名：客户端把 model 填成它，一条车道被拒就自动换下一条。
const String kZenRouteName = 'zen-free';

/// Zen 免费车道目录（**本地兜底，不是契约**）。
///
/// OpenCode Zen 的免密车道会随上游上下架变动 —— 今天在的不代表明天还在，
/// 新上的也不会事先通知。所以这张表的定位是「冷启动与断网时的底」：
/// 顺序即路由的回退优先级（chat 线的车道在前，需要线协议转换的靠后，
/// 上游按出口地区限制的置末）。
///
/// 真正的可用集合以发现页「刷新可用模型列表」拉到的上游 `/zen/v1/models`
/// 为准：拉到就补新、摘掉已下架的（见 ProfileService.applyLiveLanes），
/// 别指望这份 const 能一直对得上。
///
/// 历史备注一：这份目录早先只有 space-bunny-free 能用，其余一律
/// 403 FreeTierError —— 根因不是上游不给用，而是请求缺 OpenCode 桌面客户端
/// 指纹（Bearer public + opencode UA + x-opencode-session/request/project 头，
/// 外加 body.tools 里的 bash/glob/grep/read 四件套）。代理层补齐指纹后
/// 见 lib/services/zen/zen_protocol.dart。
///
/// 历史备注二：指纹齐了以后仍然只有 space-bunny-free 能答 —— 这次的根因是
/// **免费档指纹门只放行 `body.stream == true` 的请求**（2026-10 实测：把
/// stream 换成 false，除 space-bunny-free 外条条 403；换回 true 条条 200）。
/// 代理现在的做法是上游一律流式、客户端要整份 JSON 时再攒成一份
/// （见 lib/services/zen/zen_convert.dart 的 [kZenUpstreamAlwaysStreams]）。
///
/// 2026-10-22 按上游 `/zen/v1/models` 实测清单整表刷新：带 free 后缀的
/// 共 10 条，其中 `jev-1.13-free` 是 systemone 判定模型（`zenWireFor`），
/// 不能接聊天请求，由 `zenFilterUsableLanes` 滤掉；实际可用的聊天车道 9 条。
/// space-bunny / muse-spark / mimo-v2.5 / ling-3.0-fin / nemotron-3-ultra
/// 等旧车道已经下架，摘掉；beam / big-pickle / flint-40b / glm-5.3 /
/// deepseek-v4.1-flash / minimax-m3.1-flash 等新车道补上。
/// 视觉仍是稀缺能力（当前全表只有 nemotron-3.5-super-vl-free 能读图），
/// 所以它继续打头；minimax 紧随其后（电脑操作 / 长任务的性价比主力）。
const List<String> kZenFreeLanes = [
  // 全表唯一能读图的免费车道（2026-10-22 真机截图 + 手绘图两次实测），
  // 走 chat 线（`/v1/chat/completions` + `image_url` data URI）。
  'nemotron-3.5-super-vl-free',
  // 综合能力与速度最均衡的一条，电脑操作模式实测用它跑通。
  'minimax-m3.1-flash-free',
  'mimo-v2.6-flash-free',
  'nemotron-3.5-lightning-free',
  'deepseek-v4.1-flash-free',
  'glm-5.3-flash-free',
  'flint-40b-free',
  'beam-free',
  // 不带 -free 后缀，但 2026-10-22 的上游清单确认它仍在免密车道里
  // （见 zen_protocol.dart 的 _alwaysFree）。
  'big-pickle',
];

/// 内置的 opencodezen 档案。
///
/// 每次调用都新建对象：[Upstream] / [ModelEntry] 是可变的，共享同一份实例
/// 会让「装进配置后被用户改动」反过来污染模板。
///
/// 模板同时声明容灾路由和 [kZenFreeLanes] 那些零散车道，等价于旧「广场」里
/// 两条预设都启用。迁移老用户时补进来的条目按 disabled 落（见
/// ProfileService.mergeUpstream），免得只启用过路由的人升级后凭空多出一批对外模型。
///
/// 上游 id 恒为 [kZenUpstreamId]（`plaza-opencode-zen`）：那是迁移认领归属用的
/// 键，改了会让老用户手调过的车道开关与回退顺序全部失效。车道表可以随上游
/// 换，这个 id 不能。
ConfigProfile builtinZenProfile() => ConfigProfile(
  schema: kProfileSchema,
  id: kZenProfileId,
  name: 'OpenCode Zen',
  // 说明留空：内置这份的文案要走 l10n（见发现页卡片的 profileBuiltinZenSummary
  // 与「清单随上游变动」提示），模型层不写死中文。
  source: const ProfileSource.builtin(),
  upstreams: [
    Upstream(
      id: kZenUpstreamId,
      name: 'OpenCode Zen',
      type: UpstreamType.openai,
      baseUrl: kOpenCodeZenBaseUrl,
      // 免密车道上上下下很勤（见 [kZenFreeLanes] 的历史备注），默认一周
      // 自动对一次上游清单；modelsRefreshedAtMs 留 0 → 首次进入应用就刷一次。
      autoRefreshHours: kAutoRefreshHoursBuiltin,
      models: [
        ModelEntry(
          publicName: kZenRouteName,
          target: kZenFreeLanes.first,
          fallbacks: kZenFreeLanes.skip(1).toList(),
        ),
        for (final lane in kZenFreeLanes)
          ModelEntry(publicName: lane, target: lane),
      ],
    ),
  ],
);

/// 全部内置档案。目前只收 OpenCode Zen 的免密车道。
List<ConfigProfile> builtinProfiles() => [builtinZenProfile()];

/// 内置 MiMo TTS 上游的 id（发现页默认装进配置的那张语音上游卡）。
const String kMimoTtsUpstreamId = 'builtin-mimo-tts';

/// MiMo 开放平台的 OpenAI 兼容端点（语音合成 v2.5 文档给出的 base_url）。
const String kMimoTtsBaseUrl = 'https://api.xiaomimimo.com/v1';

/// MiMo TTS 全家桶：预置音色 / 文本设计音色 / 样本克隆音色。
/// 顺序即「对话设置」里选模型时的展示顺序。
const List<String> kMimoTtsModels = [
  'mimo-v2.5-tts',
  'mimo-v2.5-tts-voicedesign',
  'mimo-v2.5-tts-voiceclone',
];

/// 内置的 MiMo TTS 上游（audio 模态）。
///
/// 每次调用都新建对象（[Upstream] 可变，共享实例会被用户改动污染模板）。
/// 三个 TTS 模型默认全勾；API Key 留空由用户自填（mimo.mi.com 申请），
/// 没填之前打过去是上游 401，不影响其它车道。
Upstream builtinMimoTtsUpstream() => Upstream(
  id: kMimoTtsUpstreamId,
  name: 'MiMo TTS',
  type: UpstreamType.openai,
  baseUrl: kMimoTtsBaseUrl,
  modality: UpstreamModality.audio,
  note: '语音合成上游：需自行填入 MiMo API Key（mimo.mi.com 获取）',
  enabled: true,
  // TTS 线也在迭代（v2.5 三件套之外随时可能加新音色），同样一周对一次。
  autoRefreshHours: kAutoRefreshHoursBuiltin,
  models: [
    for (final m in kMimoTtsModels) ModelEntry(publicName: m, target: m),
  ],
);
