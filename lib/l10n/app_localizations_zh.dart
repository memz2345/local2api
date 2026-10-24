// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Local2API';

  @override
  String get navServer => '服务';

  @override
  String get navModels => '模型';

  @override
  String get navKeys => '密钥';

  @override
  String get navSettings => '设置';

  @override
  String get serverTitle => '服务';

  @override
  String get serverRunning => '运行中';

  @override
  String get serverStopped => '已停止';

  @override
  String get serverStarting => '启动中…';

  @override
  String get homeStatusDescRunning => '服务已启动，客户端可以直接调用了';

  @override
  String get homeStatusDescStopped => '服务未启动，点一下卡片启动';

  @override
  String get homeStatusDescStarting => '正在启动服务…';

  @override
  String get homeStatusDescError => '启动失败，点一下卡片重试';

  @override
  String get startServer => '启动服务';

  @override
  String get stopServer => '停止服务';

  @override
  String get restartServer => '重启服务';

  @override
  String get endpointTitle => '接入地址';

  @override
  String get listenAddress => '监听地址';

  @override
  String get listenPort => '监听端口';

  @override
  String get copy => '复制';

  @override
  String get copied => '已复制';

  @override
  String get allInterfaces => '所有网卡 (0.0.0.0)';

  @override
  String get loopbackOnly => '仅本机 (127.0.0.1)';

  @override
  String get lanIpsLabel => '局域网/VPN 地址';

  @override
  String get statsTitle => '请求统计';

  @override
  String get statTotalRequests => '累计请求';

  @override
  String get statErrors => '失败';

  @override
  String get statActive => '活跃连接';

  @override
  String get recentLogs => '最近请求';

  @override
  String get viewAll => '查看全部';

  @override
  String get noLogsYet => '暂无请求日志';

  @override
  String get noKeysWarningTitle => '未配置密钥';

  @override
  String get noKeysWarningBody => '任何客户端都可以直接调用此服务，建议在仪表盘「密钥」分区添加至少一个密钥。';

  @override
  String get noCidrWarningTitle => '对所有来源开放';

  @override
  String get noCidrWarningBody => '未配置任何 IP 规则，所有网段均可访问。';

  @override
  String get serverErrorTitle => '服务异常';

  @override
  String portInUse(String port) {
    return '端口 $port 被占用';
  }

  @override
  String get autoStart => '启动时自动开启服务';

  @override
  String get modelsTitle => '模型';

  @override
  String get upstreams => '上游服务';

  @override
  String get addUpstream => '添加上游';

  @override
  String get noUpstreams => '还没有上游，先添加一个';

  @override
  String get upstreamTypeLabel => '类型';

  @override
  String get typeOpenai => 'OpenAI 兼容';

  @override
  String get typeLlamacpp => 'llama.cpp';

  @override
  String get typeOllama => 'Ollama';

  @override
  String get typeLocalTts => '本地 TTS (Qwen3)';

  @override
  String get modalityLabel => '模态';

  @override
  String get modalityChat => '对话 (chat)';

  @override
  String get modalityAudio => '语音 (audio)';

  @override
  String get modalityAudioHint =>
      '开启后 /v1/audio/speech 会把 OpenAI TTS 请求翻译成该上游的 chat.completions 语音请求（MiMo TTS 等），再把回包音频解给客户端';

  @override
  String get localTtsSectionTitle => '本地 TTS（Qwen3-TTS）';

  @override
  String get ttsSettingsTitle => 'TTS 设置';

  @override
  String get ttsSettingsDesc => '本地模型、服务商与试听';

  @override
  String get ttsAutoPlayTitle => '自动播放 TTS';

  @override
  String localTtsModelSize(String size) {
    return '共约 $size GB';
  }

  @override
  String get localTtsStateInstalled => '已安装';

  @override
  String get localTtsStatePartial => '未下完（可续传）';

  @override
  String get localTtsStateNotInstalled => '未下载';

  @override
  String get localTtsDownload => '下载模型';

  @override
  String localTtsDownloadProgress(String received, String total) {
    return '下载中 $received/$total MB';
  }

  @override
  String get localTtsDeleteConfirm => '删除本地 TTS 模型文件？';

  @override
  String get localTtsDevicePreference => '推理后端';

  @override
  String get ttsDeviceAuto => '自动（高通优先 NPU）';

  @override
  String get ttsDeviceNpu => 'NPU (Hexagon)';

  @override
  String get ttsDeviceGpu => 'GPU (Vulkan)';

  @override
  String get ttsDeviceCpu => 'CPU';

  @override
  String get localTtsTestSpeak => '试听';

  @override
  String get localTtsTestStop => '停止';

  @override
  String get localTtsStatusPreparing => '正在加载模型…';

  @override
  String get localTtsStatusSynthesizing => '正在合成语音…';

  @override
  String get localTtsStatusPlaying => '播放中';

  @override
  String get localTtsStatusIdle => '空闲';

  @override
  String get localTtsStatusError => '出错';

  @override
  String get localTtsNotReady => '模型未下载或下载不完整';

  @override
  String get localTtsServeHint =>
      '下载完成后，点下方「创建本地 TTS 上游」一键配置；客户端通过 /v1/audio/speech 调用（模型名 qwen3-tts）';

  @override
  String get localTtsUpstreamName => '本地 TTS';

  @override
  String get localTtsCreateUpstream => '创建本地 TTS 上游';

  @override
  String get localTtsCreateUpstreamDesc =>
      '自动在模型页添加「本地 TTS」上游（模型 qwen3-tts），客户端即可调 /v1/audio/speech';

  @override
  String get localTtsUpstreamCreated => '已创建「本地 TTS」上游';

  @override
  String get localTtsUpstreamExists => '已存在「本地 TTS」上游';

  @override
  String get settingsFeaturesSection => '服务与功能';

  @override
  String get networkSettingsTitle => '网络设置';

  @override
  String get networkSettingsDesc => '端口与监听、临时 WebUI、IP 访问规则';

  @override
  String get chatSettingsTitle => '对话设置';

  @override
  String get chatSettingsDesc => 'TTS 设置、自动播放与角色卡';

  @override
  String get ipRulesEmpty => '暂无规则，默认放行所有来源';

  @override
  String ipRulesCount(String count) {
    return '$count 条规则';
  }

  @override
  String ruleDeletedCount(String count) {
    return '已删除 $count 条规则';
  }

  @override
  String ruleRestored(String count) {
    return '已恢复 $count 条规则';
  }

  @override
  String get characterEntryDesc => '管理对话模拟的角色卡与默认场景';

  @override
  String get ttsProviderLabel => '默认 TTS 服务商';

  @override
  String get ttsProviderOff => '关闭';

  @override
  String get ttsProviderLocal => '本地 Qwen3-TTS';

  @override
  String get ttsProviderNoneHint => '还没有能发声的模型：给语音上游加个模型，或先下载本地模型';

  @override
  String get ttsDesignModelLabel => '默认语音设计模型';

  @override
  String get ttsDesignModelDesc => '角色卡没配音色样本时用它合成，提示词即音色描述';

  @override
  String get ttsDesignPromptLabel => '音色设计提示词';

  @override
  String get ttsDesignPromptDesc => '设计模型的音色描述（user 消息），留空用默认';

  @override
  String get ttsCloneModelLabel => '默认克隆模型';

  @override
  String get ttsCloneModelDesc => '角色卡配了音色样本时用它克隆合成';

  @override
  String get ttsDesignPromptDefault => '默认';

  @override
  String get ttsPlaygroundTitle => 'TTS 调试台';

  @override
  String get ttsPlaygroundDesc => '换样本 / 文本反复试听，排查克隆与设计效果';

  @override
  String get ttsPlaygroundHint =>
      '选模型、配音色样本、输入文本后播放。克隆不像时优先换样本：一段干净的单人声（5–10 秒、无背景音乐、无混响）比长音频效果好得多。';

  @override
  String get ttsPlaygroundModel => '模型';

  @override
  String get ttsPlaygroundText => '合成文本';

  @override
  String get ttsPlaygroundInstructions => '风格指令 / 音色描述（可选）';

  @override
  String get ttsPlaygroundPlay => '播放';

  @override
  String get ttsPlaygroundEmptyText => '先输入要合成的文本';

  @override
  String get ttsPlaygroundCloneNeedsSample => '克隆模型需要音色样本：先在上方配一段音频';

  @override
  String get ttsSpeak => '朗读';

  @override
  String get characterVoiceLabel => '音色样本';

  @override
  String get characterVoiceHint =>
      '选一段清晰人声（wav/mp3，≤7MB）用于克隆音色。推荐配云端克隆（快，几秒出声）；本地克隆要等 1.4GB 模型加载，首次可能要几分钟。';

  @override
  String get characterVoicePick => '选择音频';

  @override
  String get characterVoiceRemove => '移除';

  @override
  String get characterVoiceTooBig => '音频样本太大，请压缩到 7MB 以内';

  @override
  String get characterVoiceBadType => '仅支持 wav / mp3 音频';

  @override
  String get characterOverrideReset => '已恢复内置原文';

  @override
  String get upstreamNameLabel => '名称';

  @override
  String get baseUrlLabel => '接口地址 (Base URL)';

  @override
  String get baseUrlHint => 'http://192.168.1.10:11434/v1';

  @override
  String get upstreamKeyLabel => '上游密钥（可选）';

  @override
  String get upstreamNoteLabel => '备注';

  @override
  String get upstreamNoteHint => '这个上游是干什么的、有什么注意事项（可留空）';

  @override
  String get upstreamJsonTitle => '上游 JSON';

  @override
  String get fetchModelsBtn => '拉取模型';

  @override
  String get testBtn => '测试';

  @override
  String get testOk => '连接成功';

  @override
  String testFailed(String error) {
    return '连接失败：$error';
  }

  @override
  String fetchFailed(String error) {
    return '拉取失败：$error';
  }

  @override
  String fetchedModels(String count) {
    return '获取到 $count 个模型';
  }

  @override
  String get saveBtn => '保存';

  @override
  String get deleteBtn => '删除';

  @override
  String deleteUpstreamConfirm(String name) {
    return '删除上游「$name」？';
  }

  @override
  String get cancel => '取消';

  @override
  String get confirm => '确定';

  @override
  String get exposedModelsTitle => '对外模型';

  @override
  String get noExposedModels => '没有对外暴露的模型';

  @override
  String get modelAliasLabel => '对外名称';

  @override
  String get modelTargetLabel => '上游模型';

  @override
  String get enabledLabel => '启用';

  @override
  String get exposedLabel => '暴露';

  @override
  String get baseUrlInvalid => '地址无效，需要 http(s):// 开头';

  @override
  String get fetchingModels => '正在获取模型…';

  @override
  String get testing => '正在测试…';

  @override
  String get editUpstream => '编辑上游';

  @override
  String get newUpstream => '新建上游';

  @override
  String get upstreamNameRequired => '名称不能为空';

  @override
  String modelCountLabel(String count) {
    return '$count 个模型';
  }

  @override
  String get upstreamEditHint => '一个上游就是一个 OpenAI 兼容端点，改完点右上角保存。';

  @override
  String get upstreamModeLabel => '模式';

  @override
  String get pickModeTitle => '选择模式';

  @override
  String get notFilled => '未填写';

  @override
  String get testConnectionTitle => '测试连接';

  @override
  String get testConnectionDesc => '用当前地址和密钥试一次';

  @override
  String get addModelBtn => '添加模型';

  @override
  String get modelsPageHint => '点右上角下载图标从上游拉取模型，再勾要暴露的；加号可以手动填一个。';

  @override
  String get modelsSortTitle => '排序方式';

  @override
  String get modelsSortNatural => '默认顺序';

  @override
  String get modelsSortAlphabet => '首字母正序';

  @override
  String get keysTitle => '密钥';

  @override
  String get addKey => '添加密钥';

  @override
  String get keyNameLabel => '备注';

  @override
  String get keyNameHint => '例如：我的手机';

  @override
  String get keyValueLabel => '密钥';

  @override
  String get generate => '随机生成';

  @override
  String get noKeysHint => '尚无密钥，任何客户端都能直接调用';

  @override
  String deleteKeyConfirm(String name) {
    return '删除密钥「$name」？';
  }

  @override
  String get keyExists => '该密钥已存在';

  @override
  String get keyRequired => '密钥不能为空';

  @override
  String get settingsTitle => '设置';

  @override
  String get networkSection => '网络与访问';

  @override
  String get accessRules => 'IP 访问规则';

  @override
  String get accessRuleDesc => '按顺序匹配，先命中先生效；为空则全部放行';

  @override
  String get addRule => '添加规则';

  @override
  String get ruleAllow => '放行';

  @override
  String get ruleDeny => '拒绝';

  @override
  String get cidrHint => '例如 192.168.0.0/16';

  @override
  String get cidrInvalid => 'CIDR 格式不正确';

  @override
  String get corsToggle => '允许跨域（CORS）';

  @override
  String get corsDesc => '允许网页前端直接调用本服务';

  @override
  String get autoStartToggle => '启动时自动运行服务';

  @override
  String get appearanceSection => '外观';

  @override
  String get themeLabel => '主题';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get languageLabel => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageNote => 'Android 13+ 可在系统「应用语言」中设置';

  @override
  String get aboutSection => '关于';

  @override
  String get aboutDesc =>
      '将局域网/VPN 内的 llama.cpp、Ollama 或任意 OpenAI 兼容接口，转发为带鉴权与模型白名单的一层新 API。';

  @override
  String get versionLabel => '版本';

  @override
  String get aboutEntryDesc => '版本、组件与效果背景';

  @override
  String get aboutTapLogoHint => '点一点上面的图标试试';

  @override
  String get aboutOpenLicenses => '开源许可';

  @override
  String get ossTitle => '开源许可';

  @override
  String get ossSearchHint => '搜索依赖包或许可标识';

  @override
  String get ossClearSearch => '清除搜索';

  @override
  String ossPackagesCount(String count, String licenses) {
    return '共 $count 个依赖包 · $licenses 份许可';
  }

  @override
  String ossLicensesCount(String count) {
    return '$count 份许可';
  }

  @override
  String get ossEmptySearch => '没有匹配的依赖包';

  @override
  String get ossLoadFailed => '许可清单加载失败';

  @override
  String get ossRetry => '重试';

  @override
  String get ossLoading => '正在收集许可清单…';

  @override
  String get ossCopyFullText => '复制全部许可';

  @override
  String get ossLicenseCopied => '已复制到剪贴板';

  @override
  String ossLicenseIndex(String index, String count) {
    return '第 $index / $count 份';
  }

  @override
  String get aboutComponents => '构建组件';

  @override
  String get aboutComponentsDesc => 'Flutter · flutter_miuix（HyperOS 风格）';

  @override
  String get textureSetTitle => '纹理集';

  @override
  String get textureSetEffectVariant => '效果变体';

  @override
  String get textureSetOs2 => 'OS2';

  @override
  String get textureSetOs3 => 'OS3';

  @override
  String get textureSetEffectBg => '效果背景';

  @override
  String get textureSetDynamicBg => '动态背景';

  @override
  String get textureSetBlurEnable => '模糊';

  @override
  String get textureSetBlurRadius => '模糊半径';

  @override
  String get textureSetNoise => '噪点';

  @override
  String get textureSetBrightness => '亮度';

  @override
  String get textureSetContrast => '对比度';

  @override
  String get textureSetSaturation => '饱和度';

  @override
  String get textureSetBlendMode => '混合模式';

  @override
  String get textureSetReset => '恢复默认';

  @override
  String get blendModeDefault => '默认';

  @override
  String get blendModeOverlay => '叠加';

  @override
  String get blendModeScreen => '滤色';

  @override
  String get blendModeMultiply => '正片叠底';

  @override
  String get blendModePlusLighter => '加亮';

  @override
  String get blendModePlusDarker => '加深';

  @override
  String get blendModeLinearLight => '线性光';

  @override
  String get blendModeDifference => '差值';

  @override
  String get unsavedChangesTitle => '未保存的更改';

  @override
  String get unsavedChangesMessage => '你对这个上游的修改还没有保存，要现在保存吗？';

  @override
  String get unsavedSave => '保存';

  @override
  String get unsavedDiscard => '不保存';

  @override
  String get chatSimModelPicker => '模拟模型';

  @override
  String get chatSimModelAll => '全部（整组共享）';

  @override
  String get chatSimModelAllDesc => '组内任意模型被调用都带上这段上下文';

  @override
  String get chatSimModelSpecificDesc => '仅此模型带上这段上下文';

  @override
  String get editMenuUndo => '撤消(U)';

  @override
  String get editMenuCut => '剪切(T)';

  @override
  String get editMenuCopy => '复制(C)';

  @override
  String get editMenuPaste => '粘贴(P)';

  @override
  String get editMenuDelete => '删除(D)';

  @override
  String get editMenuSelectAll => '全选(A)';

  @override
  String get portRangeInvalid => '端口范围 1024-65535';

  @override
  String get logsTitle => '请求日志';

  @override
  String get clearLogs => '清空';

  @override
  String get logsCleared => '已清空';

  @override
  String get stopServerConfirm => '停止服务？';

  @override
  String get clientLabel => '客户端';

  @override
  String get modelLabel => '模型';

  @override
  String get statusLabel => '状态';

  @override
  String get durationLabel => '耗时';

  @override
  String get colorAmber => '琥珀色';

  @override
  String get colorBlue => '蓝色';

  @override
  String get colorBlueGrey => '蓝灰色';

  @override
  String get colorBrown => '棕色';

  @override
  String get colorCyan => '青色';

  @override
  String get colorDeepPurple => '深紫色';

  @override
  String get colorDefaultGreen => '默认绿';

  @override
  String get colorGreen => '绿色';

  @override
  String get colorGrey => '灰色';

  @override
  String get colorIndigo => '靛蓝色';

  @override
  String get colorLightBlue => '浅蓝色';

  @override
  String get colorLightGreen => '浅绿色';

  @override
  String get colorLime => '酸橙色';

  @override
  String get colorOrange => '橙色';

  @override
  String get colorPink => '粉红色';

  @override
  String get colorPurple => '紫色';

  @override
  String get colorRed => '红色';

  @override
  String get colorTeal => '蓝绿色';

  @override
  String get colorYellow => '黄色';

  @override
  String get commonBackTooltip => '转到上一层级';

  @override
  String get commonCancel => '取消';

  @override
  String get commonCreate => '创建';

  @override
  String get commonDelete => '删除';

  @override
  String get commonSave => '保存';

  @override
  String get displayFollowSystemColor => '跟随系统配色';

  @override
  String get displayFontWeight => '文字粗细';

  @override
  String get displayOff => '已关闭';

  @override
  String get displayPureBlack => '纯黑深色模式';

  @override
  String get displayPureBlackOn => '深色模式（已黑化）';

  @override
  String get displayScaleCompact => '紧凑模式 · 显示更多内容';

  @override
  String get displayScaleCompactBig => '紧凑 · 适合大屏';

  @override
  String get displayScaleDefault => '默认';

  @override
  String get displayScaleFineTune => '精细调节';

  @override
  String get displayScaleHuge => '超大 · 辅助功能';

  @override
  String get displayModeTitle => '屏幕帧率';

  @override
  String get displayModeAuto => '自动';

  @override
  String get displayModeSystemTag => '[系统]';

  @override
  String get displayModeHint => '没有生效？重启应用试试';

  @override
  String get displayModeUnsupported => '当前平台不支持设置屏幕帧率（仅 Android）';

  @override
  String get displayModeLoading => '正在获取屏幕帧率...';

  @override
  String get displayModeEmpty => '未获取到可用的屏幕帧率';

  @override
  String get displayScaleLarge => '略大 · 更易阅读';

  @override
  String get displayScaleLargeFont => '大字体 · 无障碍友好';

  @override
  String get displayScaleLargeFontShort => '大字体 · 无障碍';

  @override
  String get displayScaleMin => '最小 · 信息密度最高';

  @override
  String get displayScaleNote =>
      '缩放比例会全局应用于文字与部分布局尺寸。设为 100% 可恢复默认。修改即时生效，无需重启。';

  @override
  String get displayScalePresets => '快捷预设';

  @override
  String get displayScaleReset => '重置为 100%';

  @override
  String get displayScaleSmall => '略小 · 适合大屏';

  @override
  String get displayScaleSystemDefault => '系统默认';

  @override
  String get displayScaleTitle => '显示缩放';

  @override
  String get displaySectionAppearance => '外观';

  @override
  String get displaySectionPersonalize => '个性化';

  @override
  String get displaySeedAmber => '琥珀色';

  @override
  String get displaySeedBlue => '蓝色';

  @override
  String get displaySeedBlueGrey => '蓝灰色';

  @override
  String get displaySeedBrown => '棕色';

  @override
  String get displaySeedCustom => '自定义';

  @override
  String get displaySeedCyan => '青色';

  @override
  String get displaySeedDeepPurple => '深紫色';

  @override
  String get displaySeedDefaultGreen => '默认绿';

  @override
  String get displaySeedGreen => '绿色';

  @override
  String get displaySeedGrey => '灰色';

  @override
  String get displaySeedIndigo => '靛蓝色';

  @override
  String get displaySeedLightBlue => '浅蓝色';

  @override
  String get displaySeedLightGreen => '浅绿色';

  @override
  String get displaySeedLime => '酸橙色';

  @override
  String get displaySeedOrange => '橙色';

  @override
  String get displaySeedPink => '粉红色';

  @override
  String get displaySeedPurple => '紫色';

  @override
  String get displaySeedRed => '红色';

  @override
  String get displaySeedTeal => '蓝绿色';

  @override
  String get displaySeedYellow => '黄色';

  @override
  String get displaySettingsTitle => '显示';

  @override
  String get displayThemeColor => '主题配色';

  @override
  String get displayThemeDark => '深色';

  @override
  String get displayThemeLight => '浅色';

  @override
  String get displayThemeMode => '主题模式';

  @override
  String displayWeightBlack(int weight) {
    return '极粗 ($weight)';
  }

  @override
  String displayWeightBold(int weight) {
    return '粗 ($weight)';
  }

  @override
  String displayWeightCustom(int weight) {
    return '自定义 ($weight)';
  }

  @override
  String displayWeightLight(int weight) {
    return '细 ($weight)';
  }

  @override
  String displayWeightMedium(int weight) {
    return '中等 ($weight)';
  }

  @override
  String displayWeightRegular(int weight) {
    return '常规 ($weight)';
  }

  @override
  String displayWeightThin(int weight) {
    return '极细 ($weight)';
  }

  @override
  String get drawerSystemMode => '跟随系统';

  @override
  String get fontWeightBlack => '极粗';

  @override
  String get fontWeightBold => '粗';

  @override
  String get fontWeightLight => '细';

  @override
  String get fontWeightMedium => '中等';

  @override
  String get fontWeightRegular => '常规';

  @override
  String get fontWeightSampleText =>
      'The quick brown fox jumps over the lazy dog.\n敏捷的棕色狐狸跳过懒惰的狗。';

  @override
  String get fontWeightSaveApply => '保存并应用';

  @override
  String get fontWeightUnsavedTitle => '有未保存的调整';

  @override
  String fontWeightUnsavedBody(int weight) {
    return '文字粗细改成了 $weight，还没确认。';
  }

  @override
  String get fontWeightUnsavedSave => '保存';

  @override
  String get fontWeightUnsavedDiscard => '不保存';

  @override
  String get fontWeightThin => '极细';

  @override
  String get playlistMenuMore => '更多操作';

  @override
  String get searchPureBlack => '纯黑深色模式';

  @override
  String get searchThemeMode => '主题模式';

  @override
  String get startScreenGoBack => '转到上一层级';

  @override
  String get themeAppearance => '外观';

  @override
  String themeColorCopied(String hex) {
    return '已复制色号: $hex';
  }

  @override
  String get themeColorExtracted => '已从图片提取主题色';

  @override
  String themeColorFailed(String error) {
    return '取色失败: $error';
  }

  @override
  String get themeColorsSection => '配色';

  @override
  String get themeCopyColor => '复制色号';

  @override
  String get themeCreateTitle => '创建自定义主题';

  @override
  String themeCreated(String name) {
    return '主题 \"$name\" 已创建并保存';
  }

  @override
  String get themeDarkBlackened => '深色模式（已黑化）';

  @override
  String themeDeleteConfirm(String name) {
    return '确定要删除自定义主题 \"$name\" 吗？';
  }

  @override
  String get themeDeleteTitle => '删除主题';

  @override
  String themeDeleted(String name) {
    return '已删除 \"$name\"';
  }

  @override
  String get themeDropHint => '松开以从图片提取主题色';

  @override
  String get themeEnabled => '已启用';

  @override
  String get themeFollowSystem => '跟随系统配色';

  @override
  String get themeHexHint => '例如 #FF0000 或 255,0,0';

  @override
  String get themeHexLabel => '十六进制/RGB';

  @override
  String get themeImageOnly => '仅支持图片格式';

  @override
  String get themeNameHint => '请输入文本';

  @override
  String get themeNameLabel => '主题名称';

  @override
  String get themeNewTheme => '新建主题';

  @override
  String get themeOff => '已关闭';

  @override
  String get themePaletteStyle => '调色板风格';

  @override
  String get themePickColor => '选择颜色';

  @override
  String get settingsBlurTitle => '启用模糊';

  @override
  String get settingsBlurDesc => '为应用启用模糊效果';

  @override
  String get settingsCustomColorsTitle => '自定义颜色';

  @override
  String get settingsCustomColorsDesc => '在 Miuix 主题风格下自定义主题颜色';

  @override
  String get themeCustomColorsNeeded => '需要启用自定义颜色';

  @override
  String get themePickFromImage => '从图片取色';

  @override
  String themeSwitched(String name) {
    return '已切换至 $name 主题';
  }

  @override
  String get themeTitle => '主题';

  @override
  String get settingsDisplaySection => '外观';

  @override
  String get settingsDisplayEntry => '显示设置';

  @override
  String get drawerDarkMode => '深色模式';

  @override
  String get drawerLightMode => '浅色模式';

  @override
  String get sideBarCollapse => '收起侧边栏';

  @override
  String get sideBarExpand => '展开侧边栏';

  @override
  String get navDiscover => '发现';

  @override
  String get laneProbing => '探测中…';

  @override
  String get laneUsable => '可用';

  @override
  String get laneRestricted => '仅限官方客户端';

  @override
  String get laneThrottled => '额度已达上限';

  @override
  String get laneRegionBlocked => '出口地区受限';

  @override
  String get laneUnavailable => '模型当前不可用';

  @override
  String get laneFailed => '不可用';

  @override
  String get laneNetUnreachable => '连不上端点';

  @override
  String get navDashboard => '仪表盘';

  @override
  String get dashboardTitle => '仪表盘';

  @override
  String get fabRefresh => '刷新';

  @override
  String get fabAppearance => '外观';

  @override
  String get appearancePanelTitle => '外观快速设置';

  @override
  String get fabDelayTest => '测试连接';

  @override
  String get laneUntested => '尚未测试';

  @override
  String get laneHintRoute => '点选一条车道作为链首，其余按顺序自动回退。';

  @override
  String get discoverTitle => '发现';

  @override
  String get discoverIntro => '这里列出全部上游：开关管启用/停用，闪电测速，点卡片改配置；下拉刷新可用模型列表。';

  @override
  String get fabNewUpstream => '新建上游';

  @override
  String get createConfigTitle => '创建配置';

  @override
  String get createConfigFileTitle => '文件';

  @override
  String get createConfigFileDesc => '从文件、订阅链接或粘贴 JSON 导入';

  @override
  String get createConfigUpstreamDesc => '手动创建一组上游配置';

  @override
  String get profileNewUpstreamTitle => '新建上游';

  @override
  String get profileGroupNameLabel => '名称';

  @override
  String get profileGroupNameHint => '给这个模型组起个名字（留空就用档案自带的）';

  @override
  String get profileGroupDescLabel => '说明';

  @override
  String get profileGroupDescHint => '这一组是什么、从哪来（可留空）';

  @override
  String get profileSpeedTest => '测速';

  @override
  String get profileRefreshModels => '刷新可用模型';

  @override
  String get profileLanesDynamic => '模型清单随上游变动';

  @override
  String profileModelsRefreshed(int count) {
    return '已刷新 $count 个组的可用模型';
  }

  @override
  String get profileModelsRefreshFailed => '一个组都没刷出来，看看网络或端点地址';

  @override
  String keyDeletedCount(int count) {
    return '已删除 $count 个密钥';
  }

  @override
  String get keyRestore => '恢复';

  @override
  String keyRestored(int count) {
    return '已恢复 $count 个密钥';
  }

  @override
  String get keysManage => '管理密钥';

  @override
  String get keysIntro => '密钥是这一层的门禁：只有带着密钥的客户端才允许调用。左滑一行可以删除。';

  @override
  String get keysEmptyPage => '还没有密钥，点右下角加号添加一个。';

  @override
  String get usageTitle => 'Token 统计';

  @override
  String get usageIntro => '本机代理接住的每一次请求都在这里记账：输入 / 输出 / 缓存命中，按模型与时间查。';

  @override
  String get usageAllModels => '全部模型';

  @override
  String get usageRangeToday => '今天';

  @override
  String get usageRange7 => '近 7 天';

  @override
  String get usageRange30 => '近 30 天';

  @override
  String get usageRangeAll => '全部';

  @override
  String get usageTotal => '合计';

  @override
  String get usageInput => '输入';

  @override
  String get usageOutput => '输出';

  @override
  String get usageCacheHit => '缓存命中';

  @override
  String get usageCacheMiss => '缓存未命中';

  @override
  String get usageHitRate => '命中率';

  @override
  String get usageRequests => '请求数';

  @override
  String get usageReasoning => '思考';

  @override
  String get usageByDay => '按天';

  @override
  String get usageRecent => '最近记录';

  @override
  String get usageEmpty => '这段时间还没有记录，跑一轮模型后这里就有数了。';

  @override
  String get usageNoUsageData => '上游未给用量';

  @override
  String get usageClear => '清空用量';

  @override
  String get usageClearConfirm => '清空全部 token 用量记录？';

  @override
  String get usageCleared => '用量记录已清空';

  @override
  String get usageOpen => '查看 Token 统计';

  @override
  String get usageCalendar => '用量日历';

  @override
  String get usageCalendarOpen => '日历';

  @override
  String get usageCalendarIntro => '点日期看当天调用了哪些模型，点卡片就带着那一天回到统计页。';

  @override
  String get usageCalendarPrevMonth => '上个月';

  @override
  String get usageCalendarNextMonth => '下个月';

  @override
  String get usageCalendarEmptyDay => '这天没有调用记录';

  @override
  String usageCalendarDayModels(String date) {
    return '$date 的活动';
  }

  @override
  String get chatSimTitle => '对话模拟';

  @override
  String get chatSimAutoSaved => '对话默认保存在本机（按模型组分开放），下次进来接着聊。';

  @override
  String get chatSimVoiceInput => '语音输入';

  @override
  String get chatSimVoiceStop => '停止语音输入';

  @override
  String get chatSimVoicePreparing => '离线语音模型准备中，稍等再试';

  @override
  String get chatSimVoiceUnavailable => '当前设备不支持语音输入';

  @override
  String get chatSimAttach => '添加附件';

  @override
  String get chatSimAttachImage => '图片';

  @override
  String get chatSimAttachFile => '文件';

  @override
  String get chatSimAttachUserOnly => '附件只加在用户消息上';

  @override
  String get chatSimRemoved => '已删除';

  @override
  String get chatSimIntro =>
      '把这里的对话当成下游客户端发的一条请求，走本机代理的真实链路（路由 / 回退 / 指纹 / 请求日志）。前面的消息会一起带出去。图片会随消息发给模型（纯文本车道可切「仅发文字」），文件只在界面上展示；长按消息可直接删除。';

  @override
  String get chatSimServerOff => '服务没在运行，先启动它再发。';

  @override
  String get chatSimStartServer => '启动服务';

  @override
  String get chatSimNoModel => '这一组还没有对外暴露的模型，先在发现页启用它。';

  @override
  String get chatSimSend => '发送';

  @override
  String get chatSimSendOnly => '仅发送';

  @override
  String get chatSimSendOnlyDesc => '只把请求发出去，不等模型回复';

  @override
  String get chatSimSentOnly => '已发送（未等待回复）';

  @override
  String get chatSimSendModeOnly => '发送（模型不响应）';

  @override
  String get chatSimSendModeHint => '长按切换';

  @override
  String get chatSimSending => '生成中…';

  @override
  String get chatSimClear => '清空对话';

  @override
  String get chatSimClearConfirm => '清空这次对话？';

  @override
  String get chatSimMore => '更多';

  @override
  String get chatSimAvatarTitle => '头像设置';

  @override
  String get chatSimAvatarUser => '用户头像';

  @override
  String get chatSimAvatarAssistant => '助手头像';

  @override
  String get chatSimAvatarPick => '从相册选择';

  @override
  String get chatSimAvatarCamera => '拍照';

  @override
  String get chatSimAvatarReset => '恢复默认';

  @override
  String get chatSimAvatarUpdated => '头像已更新';

  @override
  String chatSimAvatarFailed(String error) {
    return '头像更新失败：$error';
  }

  @override
  String get callTitleAction => '通话';

  @override
  String get callTitleVoice => '语音通话';

  @override
  String get callTitleVideo => '视频通话';

  @override
  String get callStatusCalling => '正在接通…';

  @override
  String get callStatusEnded => '通话已结束';

  @override
  String get callRecords => '对话记录';

  @override
  String get callStatusListening => '在听…';

  @override
  String get callStatusThinking => '思考中…';

  @override
  String get callStatusSpeaking => '说话中…';

  @override
  String get callMic => '麦克风';

  @override
  String get callMicDone => '说完了';

  @override
  String get callInterrupt => '打断';

  @override
  String get callVideoNeedOmni => '视频通话需要 Omni 模型';

  @override
  String get callAsrUnavailable => '语音识别不可用，检查麦克风权限';

  @override
  String get callMute => '静音';

  @override
  String get callUnmute => '取消静音';

  @override
  String get callSpeakerOn => '免提';

  @override
  String get callSpeakerOff => '关闭免提';

  @override
  String get callSwitchToVideo => '切换到视频通话';

  @override
  String get callSwitchToVoice => '切换到语音通话';

  @override
  String get callHangUp => '挂断';

  @override
  String get callSettingsTitle => '通话设置';

  @override
  String get callSettingsOmniHint =>
      '当前模型不是 Omni 模型：基础语音通话照常可用；「允许打断」和「允许调用摄像头」需要 Omni 模型。';

  @override
  String get callAllowInterrupt => '允许打断';

  @override
  String get callAllowInterruptDesc => '模型说话时可以随时插话（需要 Omni 模型）';

  @override
  String get callAllowCamera => '允许调用摄像头';

  @override
  String get callAllowCameraDesc => '视频通话时把摄像头画面发送给模型（需要 Omni 模型）';

  @override
  String get callCameraBlocked => '已禁止调用摄像头';

  @override
  String get callVideoStagePlaceholder => '摄像头画面 · 暂未接入';

  @override
  String get chatSimRegenerate => '重新生成';

  @override
  String get chatSimEditTitle => '编辑消息';

  @override
  String get chatSimSave => '保存';

  @override
  String get chatSimSaveAndSend => '保存并发送';

  @override
  String get chatSimAddMessage => '添加消息';

  @override
  String get chatSimRoleLabel => '角色';

  @override
  String get chatSimRoleSystem => '系统';

  @override
  String get chatSimRoleUser => '用户';

  @override
  String get chatSimRoleAssistant => '助手';

  @override
  String get chatSimHintInput => '输入一条消息（默认按用户发）';

  @override
  String chatSimModelLabel(String model) {
    return '请求模型 $model';
  }

  @override
  String chatSimMeta(int words, String time) {
    return '字数 $words · 耗时 $time';
  }

  @override
  String chatSimServedModel(String model) {
    return '响应模型 $model';
  }

  @override
  String chatSimServedModelVia(String lane, String model) {
    return '响应模型 $lane（请求 $model）';
  }

  @override
  String get characterTitle => '角色卡';

  @override
  String get characterIntro => '给对话模拟换个场景：应用角色卡会替换系统提示词，并按顺序铺上预制问答。';

  @override
  String get characterDefault => '默认场景';

  @override
  String get characterDefaultDesc => '通用助手（You are a helpful assistant）';

  @override
  String characterPresetCount(int count) {
    return '$count 条预制对话';
  }

  @override
  String characterApplied(String name) {
    return '已应用角色：$name';
  }

  @override
  String get characterResetDone => '已回到默认场景';

  @override
  String get characterCreate => '创建角色';

  @override
  String get characterNewTitle => '新建角色';

  @override
  String get characterEditTitle => '编辑角色';

  @override
  String get characterNameLabel => '角色名';

  @override
  String get characterNameHint => '例如：希儿';

  @override
  String get characterPromptLabel => '人设提示词';

  @override
  String get characterPromptHint => '会作为 system 提示词发给模型：写清楚身份、语气与习惯';

  @override
  String get characterPresetsLabel => '预制对话';

  @override
  String get characterPresetsHint => '应用后按顺序铺进对话，让开场就带着上下文';

  @override
  String get characterPresetUser => '用户';

  @override
  String get characterPresetAssistant => '助手';

  @override
  String get characterAddPreset => '添加一组问答';

  @override
  String get characterBuiltin => '内置';

  @override
  String characterDeleteConfirm(String name) {
    return '删除角色「$name」？';
  }

  @override
  String get characterNeedName => '先给角色起个名字';

  @override
  String get characterActions => '更多操作';

  @override
  String get profileViewJson => '查看 JSON';

  @override
  String get profileJsonTitle => '组的 JSON';

  @override
  String get profileJsonBuiltin => '这一组由代码生成，下面是它当前的有效内容。';

  @override
  String get profileJsonCopy => '复制';

  @override
  String get profileJsonExport => '导出文件';

  @override
  String get profileJsonCopied => '已复制 JSON';

  @override
  String profileJsonExported(String path) {
    return '已导出到 $path';
  }

  @override
  String profileJsonExportFailed(String error) {
    return '导出失败：$error';
  }

  @override
  String get fabAdd => '添加';

  @override
  String get moreAction => '更多操作';

  @override
  String get profileSourceBuiltin => '内置';

  @override
  String get profileSourceUrl => '订阅';

  @override
  String get profileSourceFile => '文件';

  @override
  String get profileSourceInline => '粘贴';

  @override
  String get profileUpdateAvailable => '有更新';

  @override
  String get profileCustomizedTag => '已手动改过';

  @override
  String get profileLanesAction => '查看车道';

  @override
  String get profileUpdateAction => '立即更新';

  @override
  String get profileDeleteAction => '删除档案';

  @override
  String profileDeleteConfirm(String name) {
    return '删除「$name」？它装进来的上游会一并摘掉。';
  }

  @override
  String profileDeleted(String name) {
    return '已删除「$name」';
  }

  @override
  String profileStats(int upstreams, int lanes) {
    return '$upstreams 个上游 · $lanes 条车道';
  }

  @override
  String get profileNeverUpdated => '尚未更新';

  @override
  String profileLastUpdated(String time) {
    return '上次更新 $time';
  }

  @override
  String get profilePullHint => '下拉刷新可用模型列表';

  @override
  String get profileIdConflict => '上游 id 已被占用，这份档案没有装入';

  @override
  String get profileBuiltinZenSummary =>
      '免登录接入 OpenCode Zen 的免费模型车道；对外名 zen-free 自带顺序回退。';

  @override
  String get profileImportTitle => '添加配置文件';

  @override
  String get profileImportTabUrl => '订阅地址';

  @override
  String get profileImportTabFile => '本地文件';

  @override
  String get profileImportTabPaste => '粘贴 JSON';

  @override
  String get profileImportUrlHint => 'https://example.com/profile.json';

  @override
  String get profileImportPickFile => '选择 JSON 文件';

  @override
  String get profileImportPasteHint => '把档案 JSON 粘到这里';

  @override
  String get profileImportNote => '档案只描述模型从哪来，不会改监听端口、密钥和访问规则。';

  @override
  String get profileImportSubmit => '导入';

  @override
  String profileImported(String name) {
    return '已导入「$name」';
  }

  @override
  String get profileFormatEmpty => '内容是空的';

  @override
  String get profileFormatNotJson => '不是合法 JSON（Clash 订阅是 YAML，这里不吃）';

  @override
  String get profileFormatNotObject => '顶层得是一个 JSON 对象';

  @override
  String get profileFormatUnsupportedSchema => '档案格式版本不支持';

  @override
  String get profileFormatMissingId => '档案缺 id（也没写 name 可以推）';

  @override
  String get profileFormatNoUpstreams => '档案里一个上游都没有';

  @override
  String get profileFormatDuplicateId => '已经有一份同 id 的档案了';

  @override
  String get laneHintNotInstalled => '这份档案还没启用，先在发现页点一下卡片装上它。';

  @override
  String laneFallbackHint(String name) {
    return '客户端把 model 填成 $name 即可走容灾。';
  }

  @override
  String get uiStyleLabel => '界面风格';

  @override
  String get uiStyleNote => '切换后整个应用改用另一套页面实现';

  @override
  String get uiStyleMaterial => 'Material 3 Expressive';

  @override
  String get uiStyleMiuix => '小米 HyperOS';

  @override
  String get miuixPullToRefresh => '下拉刷新';

  @override
  String get miuixReleaseToRefresh => '松开立即刷新';

  @override
  String get miuixRefreshing => '正在刷新…';

  @override
  String get miuixRefreshDone => '刷新完成';

  @override
  String get navBarStyleLabel => '底部導航欄';

  @override
  String get navBarStyleNote => '液態玻璃走原生渲染，普通檔用系統導航欄';

  @override
  String get navBarStyleGlass => '液態玻璃';

  @override
  String get navBarStylePlain => '普通';

  @override
  String get displayIosPushTransitionCorner => '轉場圓角';

  @override
  String get displayIosPushTransitionCornerAuto => '跟隨裝置螢幕圓角';

  @override
  String get displayIosPushTransitionCornerUnsupported =>
      '目前裝置讀不到螢幕圓角，改用下面這個手動值';

  @override
  String get edgeHapticLabel => '滑動觸感回饋';

  @override
  String get edgeHapticNote => '快速滑動到頂部/底部時輕震一下';

  @override
  String get shortcutStartService => '啟動服務';

  @override
  String get shortcutStopService => '關閉服務';

  @override
  String get shortcutTokenStats => '查看 Token 用量';

  @override
  String get tasksDialogTitle => '任务';

  @override
  String get taskPauseServer => '暂停服务';

  @override
  String taskListenOn(String address) {
    return '监听 $address';
  }

  @override
  String get taskStopListening => '停止监听';

  @override
  String get tasksRecentSection => '最近';

  @override
  String tasksModelCount(int count) {
    return '$count 个模型';
  }

  @override
  String get createConfigScanTitle => '扫描二维码';

  @override
  String get createConfigScanDesc => '扫码或从相册识别来添加配置';

  @override
  String get qrScannerTitle => '扫描二维码';

  @override
  String get qrScannerHint => '对准屏幕任意位置，识别到二维码自动跳转';

  @override
  String get qrScannerPermissionTitle => '需要相机权限';

  @override
  String get qrScannerPermissionDesc => '扫码需要使用相机，请在系统设置中允许本应用访问相机。';

  @override
  String get qrScannerOpenSettings => '去设置';

  @override
  String get qrScannerRetry => '重试';

  @override
  String get qrScannerUnsupported => '当前平台不支持扫码，请在 Android / iOS 设备上使用';

  @override
  String get qrScannerSwitchCamera => '切换前后摄像头';

  @override
  String get qrScannerGallery => '从相册识别';

  @override
  String get qrScannerGalleryEmpty => '图片里没有识别到二维码';

  @override
  String get qrResultTitle => '扫码结果';

  @override
  String get qrResultKindProfile => '配置档案 JSON';

  @override
  String get qrResultKindUpstream => '上游 JSON';

  @override
  String get qrResultKindUrl => '网页链接';

  @override
  String get qrResultKindText => '纯文本';

  @override
  String get qrResultImportProfile => '导入配置文件';

  @override
  String get qrResultAddUpstream => '添加为上游';

  @override
  String get qrResultImportUrl => '导入订阅';

  @override
  String qrResultUpstreamAdded(String name) {
    return '已添加上游「$name」';
  }

  @override
  String get upstreamQrTitle => '上游二维码';

  @override
  String get upstreamQrHint => '用另一台装了本应用的设备扫一扫，即可把这个上游导入到它的规则里。';

  @override
  String get upstreamQrTooLong => '内容过长，生成不了二维码';

  @override
  String get progressiveTopBarTitle => '渐变模糊顶栏';

  @override
  String get progressiveTopBarDesc => '顶栏透明化，顶部渐进模糊随内容滚入淡入';

  @override
  String get navBarStyleFloating => '悬浮';

  @override
  String get biometricLockTitle => '生物识别锁';

  @override
  String get biometricLockDesc => '打开应用时需要验证指纹 / 人脸（Android）';

  @override
  String get biometricLockUnavailable => '此设备没有可用的生物识别或屏幕锁凭据';

  @override
  String get biometricGateTitle => 'Local2API 已锁定';

  @override
  String get biometricGateHint => '验证生物识别以继续';

  @override
  String get biometricUnlock => '解锁';

  @override
  String get networkTitle => '网络';

  @override
  String get networkEntryDesc => 'Cloudflare Tunnel / Tailscale';

  @override
  String get cfTitle => 'Cloudflare Tunnel';

  @override
  String get cfDesc => '通过 trycloudflare 临时隧道，把本服务公开到互联网';

  @override
  String get cfEnableSwitch => '启用 trycloudflare';

  @override
  String get cfTermsTitle => 'Cloudflare 许可协议';

  @override
  String get cfTermsAgree => '同意并启用';

  @override
  String get cfTermsDecline => '不同意';

  @override
  String get cfTermsFetchFailed => '许可协议拉取失败，请检查网络后重试';

  @override
  String get cfTermsNote => '启用前需要同意 Cloudflare 的服务条款（trycloudflare.com）。';

  @override
  String get cfStarting => '正在启动隧道…';

  @override
  String get cfRunning => '隧道运行中';

  @override
  String get cfStopped => '未运行';

  @override
  String get cfPublicUrl => '公开地址';

  @override
  String get cfBinaryMissing =>
      '没有找到 cloudflared。内建隧道目前只在桌面端可用（PATH 里装好 cloudflared 后重试）。';

  @override
  String get cfRetry => '重试';

  @override
  String get cfStop => '停止';

  @override
  String get tsTitle => 'Tailscale';

  @override
  String get tsDesc => '在 Tailscale 网络内访问本服务（100.64.0.0/10 网段）';

  @override
  String get tsAllowSwitch => '放行 Tailscale 网段';

  @override
  String tsDetected(String ip) {
    return '检测到 Tailscale IP：$ip';
  }

  @override
  String get tsNotDetected => '未检测到 Tailscale 接口（本机没装或没连）';

  @override
  String get tsDownloadTitle => '获取 Tailscale';

  @override
  String get tsDownloadDesc => '在手机 / 电脑上安装 Tailscale，随时随地访问本服务';

  @override
  String get tsOpenDownload => '打开下载页';

  @override
  String get securitySection => '安全';

  @override
  String get webUiTitle => '临时 WebUI';

  @override
  String get webUiDesc => '和 API 转发分开的端口，用来临时在浏览器里试模型';

  @override
  String get webUiEnable => '启用临时 WebUI';

  @override
  String get webUiToggleHint => '关掉就停掉网页服务，不影响 API 转发';

  @override
  String get webUiPort => 'WebUI 端口';

  @override
  String get webUiHost => 'WebUI 监听地址';

  @override
  String get webUiRunning => '网页已启动';

  @override
  String get webUiStopped => '网页未启动';

  @override
  String get webUiFailed => '网页启动失败';

  @override
  String get webUiOpen => '在浏览器打开';

  @override
  String get webUiCopyUrl => '复制地址';

  @override
  String get webUiEntryDesc => '端口、开关、浏览器入口';

  @override
  String get webUiNote => '页面上的请求仍然打 API 端口，两个端口互不干扰';

  @override
  String get scheduleTitle => '峰谷时段';

  @override
  String get scheduleEntryDesc => '按星期和时间段限制模型 / 模型组';

  @override
  String get scheduleDesc => '正向：只有选中的时间段能用。反向：选中的时间段禁用。对话模拟不受影响。';

  @override
  String get scheduleEmpty => '还没有策略：不加就是全天可用';

  @override
  String get scheduleAdd => '添加策略';

  @override
  String get scheduleTarget => '作用对象';

  @override
  String get scheduleTargetModel => '单个模型';

  @override
  String get scheduleTargetGroup => '模型组';

  @override
  String get scheduleModel => '模型';

  @override
  String get scheduleGroup => '模型组';

  @override
  String get scheduleMode => '策略方向';

  @override
  String get scheduleModeAllow => '正向（选中时段才能用）';

  @override
  String get scheduleModeDeny => '反向（选中时段禁止用）';

  @override
  String get scheduleWeekdays => '星期';

  @override
  String get scheduleSelectAll => '全选';

  @override
  String get scheduleUpstreamHint => '只作用于这个上游的模型；全选就等于给整个上游套窗口。改动即时生效，不用点保存。';

  @override
  String get scheduleUpstreamNoModel => '这个上游还没有对外模型，先在「对外模型」里加几个。';

  @override
  String get schedulePickWeekday => '选择星期';

  @override
  String get scheduleHours => '时间段';

  @override
  String scheduleHourRange(String start, String end) {
    return '$start:00 - $end:00';
  }

  @override
  String get scheduleEnabled => '启用这条策略';

  @override
  String get scheduleDelete => '删除策略';

  @override
  String get scheduleSaved => '策略已保存';

  @override
  String get scheduleDeleted => '策略已删除';

  @override
  String get scheduleSimNote => '对话模拟永远可用，不受这些策略限制';

  @override
  String get schedulePickTarget => '选一个模型或模型组';

  @override
  String get schedulePickHour => '选择小时';

  @override
  String get scheduleStartHour => '起始';

  @override
  String get scheduleEndHour => '结束';

  @override
  String get scheduleAllDay => '全天';

  @override
  String scheduleStatus(String count) {
    return '$count 条策略';
  }

  @override
  String get modelContextLabel => '最大上下文数';

  @override
  String get modelContextHelper => '对外声明给客户端的上下文 token 数；留空按默认 1M，拉取模型列表时也会自动补';

  @override
  String modelContextShort(String value) {
    return '上下文 $value';
  }

  @override
  String contextAutoFilled(String count) {
    return '已从上游获取 $count 个模型的上下文长度';
  }

  @override
  String get modelOutputLabel => '最大输出数';

  @override
  String get modelOutputHelper => '对外声明的最大输出 token 数；留空不声明';

  @override
  String contextRingInfo(String percent, String used, String total) {
    return '上下文占用 $percent%（$used / $total tokens）';
  }

  @override
  String get contextRingEstimated => '，按字数估算';

  @override
  String get contextRingTap => '点击查看上下文详情';

  @override
  String get contextDetailTitle => '上下文占用';

  @override
  String contextDetailPercent(String percent) {
    return '占上下文 $percent%';
  }

  @override
  String contextDetailUsed(String used, String total) {
    return '$used / $total tokens';
  }

  @override
  String get contextDetailFromUsage => '取自上一轮响应的 usage（精确值）';

  @override
  String get contextDetailEstimated => '按字数与图片粗估（上游没回 usage）';

  @override
  String contextDetailOutput(String limit) {
    return '最大输出 $limit tokens';
  }

  @override
  String get contextDetailOutputNone => '最大输出未声明';

  @override
  String contextDetailModel(String model) {
    return '请求模型 $model';
  }

  @override
  String contextDetailMessages(String count, String images) {
    return '$count 条消息 · $images 张图片';
  }

  @override
  String get contextDetailClose => '知道了';

  @override
  String get chatSimSendImages => '发送图片';

  @override
  String get chatSimSendTextOnly => '仅发文字';

  @override
  String get chatSimSendImagesTip =>
      '图片会作为多模态内容一起发给模型；纯文本车道报错时切到「仅发文字」，图就只留在界面上。';

  @override
  String get chatSimImagesOn => '图片会随消息发出';

  @override
  String get chatSimImagesOff => '图片只在本地展示，不发给模型';

  @override
  String get chatSimAttachCamera => '拍照';

  @override
  String chatSimAttachFailed(String error) {
    return '读取附件失败：$error';
  }

  @override
  String get chatSimVoiceNoPermission => '没有麦克风权限，无法语音输入';

  @override
  String get chatSimVoiceOpenSettings => '去设置';

  @override
  String chatSimVoiceFailed(String error) {
    return '语音输入失败：$error';
  }

  @override
  String get voiceHoldToTalk => '按住说话';

  @override
  String get voiceReleaseToSend => '松开结束';

  @override
  String get voiceListeningHint => '正在聆听…';

  @override
  String get voiceRecognizing => '识别中…';

  @override
  String get voiceNothingHeard => '没听清，再按住说一次';

  @override
  String chatSimCallPeer(String name) {
    return '和 $name 通话';
  }

  @override
  String get chatSimMsgMenuTitle => '消息操作';

  @override
  String get chatSimMsgSpeak => '朗读';

  @override
  String get chatSimMsgStopSpeak => '停止朗读';

  @override
  String get chatSimMsgRegenerate => '重新回答';

  @override
  String get chatSimMsgDownload => '下载音频';

  @override
  String get chatSimDownloadTitle => '下载音频';

  @override
  String get chatSimDownloadFormat => '格式';

  @override
  String get chatSimDownloadMp3Desc => '通用音频，兼容性最好';

  @override
  String get chatSimDownloadSilkDesc => 'SILK v3，微信 / QQ 的语音格式';

  @override
  String get chatSimDownloadSlkDesc => '与 SILK 字节相同，只是扩展名不同';

  @override
  String get chatSimDownloadTencent => '腾讯兼容（-tencent）';

  @override
  String get chatSimDownloadTencentDesc => '文件头加 0x02、结尾不写哨兵包，微信 / QQ 才认';

  @override
  String get chatSimDownloadAction => '下载';

  @override
  String get chatSimDownloadBusy => '正在合成音频…';

  @override
  String get chatSimDownloadCanceled => '已取消保存';

  @override
  String chatSimDownloadSaved(String path) {
    return '已保存：$path';
  }

  @override
  String chatSimDownloadFailed(String error) {
    return '导出失败：$error';
  }

  @override
  String get balanceTitle => '余额';

  @override
  String get balanceEntryDesc => '查询这个上游的账户余额';

  @override
  String get balancePullHint => '下拉刷新余额';

  @override
  String get balanceRefreshing => '查询中…';

  @override
  String get balanceNoKey => '先填密钥再查余额';

  @override
  String get balanceUnsupported => '该上游不支持余额查询';

  @override
  String get balanceNoData => '没有返回余额';

  @override
  String get balanceAvailableLabel => '可用余额';

  @override
  String get balanceGrantedLabel => '赠送余额';

  @override
  String get balanceToppedUpLabel => '充值余额';

  @override
  String get balanceUsedLabel => '已用额度';

  @override
  String get balanceRequestsLabel => '累计请求';

  @override
  String get balanceGroupLabel => '分组';

  @override
  String get balanceSourceLabel => '查询接口';

  @override
  String get balanceStatusOk => '账号可正常调用';

  @override
  String get balanceStatusBad => '账号不可用（欠费或受限）';

  @override
  String get balanceQuotaNote => '按 1 美元 = 500000 额度换算';

  @override
  String balanceFailed(String error) {
    return '查询失败：$error';
  }

  @override
  String balanceUpdatedAt(String time) {
    return '上次更新 $time';
  }

  @override
  String get balanceDetailsTitle => '余额明细';

  @override
  String get balanceLimitLabel => '额度上限';

  @override
  String get balanceUnauthorized => '密钥无效或无权读取账户';

  @override
  String get balanceBadResponse => '余额接口返回的内容读不懂';

  @override
  String get balanceNoKeyHint => '填好密钥后再刷新';

  @override
  String get balanceUnauthorizedHint => '确认密钥有效，且允许读取账户信息';

  @override
  String get balanceUnsupportedHint => '不是所有上游都有余额接口';

  @override
  String get balanceNetworkHint => '检查本机能否访问该地址，稍后重试';

  @override
  String get thinkingDefaultLabel => '默认思考档位';

  @override
  String get thinkingDefaultOff => '不干预';

  @override
  String get thinkingLevelLow => '精简';

  @override
  String get thinkingLevelMedium => '均衡';

  @override
  String get thinkingLevelHigh => '深思';

  @override
  String get thinkingWireLabel => '档位下发格式';

  @override
  String get thinkingWireBudget => '只压输出预算';

  @override
  String get thinkingWireEffort => 'reasoning_effort';

  @override
  String get thinkingWireThinking => 'thinking 开关';

  @override
  String get thinkingWireBoth => '两者都发';

  @override
  String get logsFilterAll => '全部';

  @override
  String get logsFilterPassed => '通过';

  @override
  String get logsFilterFailed => '失败';

  @override
  String get logsEmptyFiltered => '当前筛选下没有请求';

  @override
  String get activeConnectionsTitle => '活跃连接';

  @override
  String get activeConnectionsEmpty => '当前没有活跃连接';

  @override
  String get activeConnDuration => '已持续';

  @override
  String get activeConnStarted => '开始于';

  @override
  String get activeConnPath => '路径';

  @override
  String get tsOpenApp => '打开 Tailscale';

  @override
  String get tsInstalledDesc => '已安装 Tailscale，点一下打开客户端';

  @override
  String get tsOpenFailed => '没能打开 Tailscale，已改为打开下载页';

  @override
  String get usageCalendarBackToday => '返回今天';

  @override
  String get thinkingLevelNone => '关闭思考';

  @override
  String get thinkingLevelMinimal => '极轻';

  @override
  String get thinkingLevelXhigh => '极深';

  @override
  String get thinkingLevelMax => '最重';

  @override
  String get winCloseSection => '桌面窗口';

  @override
  String get winCloseBehaviorTitle => '关闭按钮行为';

  @override
  String get winCloseAsk => '每次询问';

  @override
  String get winCloseTray => '收进托盘';

  @override
  String get winCloseExit => '退出程序';

  @override
  String get winCloseAskSummary => '每次都问一句（可以勾选「下次也是这样」）';

  @override
  String get winCloseTraySummary => '窗口收进托盘，转发服务继续跑';

  @override
  String get winCloseExitSummary => '程序整体退出，服务随之停止';

  @override
  String get winCloseDialogTitle => 'Local2API';

  @override
  String get winCloseDialogHeading => '您点击了关闭按钮，您希望？';

  @override
  String get winCloseDialogContent => '收进托盘后程序在后台继续转发，可以从托盘图标随时叫回来。';

  @override
  String get winCloseLinkTray => '收进托盘';

  @override
  String get winCloseLinkTraySubtitle => '窗口藏起来，服务照常运行';

  @override
  String get winCloseLinkExit => '退出程序';

  @override
  String get winCloseLinkExitSubtitle => '连转发服务一起停掉';

  @override
  String get winCloseRemember => '下次也是这样';

  @override
  String get winTrayShow => '显示主窗口';

  @override
  String get winTrayQuit => '退出 Local2API';

  @override
  String get thinkingWireHint => '上游不认这一档时会自动逐级下调（max → xhigh → … → 不下发）';

  @override
  String get typeAnthropic => 'Anthropic Messages';

  @override
  String get trayHintBody => '嘿嘿，我在这里哦';

  @override
  String get trayHintDismiss => '不再提示';

  @override
  String get trayHintSettings => '设置';

  @override
  String get winTrayHintTitle => '收进托盘时显示提示';

  @override
  String get winTrayHintSummary => '弹一条系统通知：「嘿嘿，我在这里哦」，带「不再提示 / 设置」两个按钮';

  @override
  String get settingsLabTitle => '实验室';

  @override
  String get settingsLabDesc => '把 SillyTavern 装到本地、内置浏览器等实验功能';

  @override
  String get labTitle => '实验室';

  @override
  String get labSubtitle => '本地服务与实验性功能';

  @override
  String get labLocalServices => '本地服务';

  @override
  String get labSillyTavernDesc => '本地 AI 角色扮演前端（Node.js），装好后在应用内打开';

  @override
  String get labInstall => '安装';

  @override
  String get labInstalled => '已安装';

  @override
  String get labNotInstalled => '未安装';

  @override
  String get labRunning => '运行中';

  @override
  String get labStart => '启动';

  @override
  String get labStop => '停止';

  @override
  String get labOpen => '打开';

  @override
  String get labOpenFolder => '打开目录';

  @override
  String get labUninstall => '卸载';

  @override
  String get labUninstallTitle => '卸载 SillyTavern？';

  @override
  String get labUninstallBody => '会删除已下载的程序文件（含 data 目录里的角色卡与聊天记录），且不可恢复。';

  @override
  String get labInstallLocation => '安装位置';

  @override
  String get labChooseLocation => '选择位置';

  @override
  String get labDefaultLocation => '默认位置';

  @override
  String get labNodeStatus => 'Node.js';

  @override
  String get labNodeMissing => '未检测到 Node.js';

  @override
  String get labNodeMissingHint => '装好 Node.js 18+ 后点「重新检测」即可启动；文件可以先装着。';

  @override
  String get labNodeDownload => '下载 Node.js';

  @override
  String get labRecheck => '重新检测';

  @override
  String get labInstallDeps => '安装依赖';

  @override
  String get labMobileNoRun =>
      '移动端不能直接运行 Node.js 服务；文件已装到应用目录，可用 Termux 等环境运行。';

  @override
  String get labNodeRuntimeTitle => 'Node.js 运行时';

  @override
  String get labNodeRuntimeDesc =>
      '从 Termux 软件源安装 Android 版 Node.js（含 npm），实验室的本地服务在本机运行必备。';

  @override
  String get labNodeRuntimeInstall => '安装 Node.js';

  @override
  String get labNodeRuntimeReinstall => '重新安装';

  @override
  String get labNodeRuntimeRemove => '卸载 Node.js';

  @override
  String get labNodeRuntimeNotInstalled => '未安装';

  @override
  String get labNodeRunnerMode => '运行模式';

  @override
  String get labRunnerDirect => '直接运行';

  @override
  String get labRunnerDirectDesc => '以应用身份启动进程（debug 构建可用；release 会被系统拦截）';

  @override
  String get labRunnerShizuku => 'Shizuku';

  @override
  String get labRunnerShizukuDesc =>
      '经 Shizuku 以 shell 身份启动进程（release 推荐，需安装并授权 Shizuku）';

  @override
  String get labNodeMirror => '下载镜像';

  @override
  String get labMirrorOfficial => '官方源';

  @override
  String get labMirrorOfficialDesc =>
      'packages.termux.dev · registry.npmjs.org（境内直连很慢，适合已有代理的网络）';

  @override
  String get labMirrorCn => '中国大陆镜像';

  @override
  String get labMirrorCnDesc => '清华 TUNA termux 源 · npmmirror（境内直连快，实测数 MB/s）';

  @override
  String get labShizukuStatus => 'Shizuku 状态';

  @override
  String get labShizukuNotDetected => '未检测到 Shizuku（未安装或未启动）';

  @override
  String get labShizukuGranted => '已授权';

  @override
  String get labShizukuNotGranted => '未授权';

  @override
  String get labShizukuRequest => '授权 Shizuku';

  @override
  String get labExecBlocked => '系统禁止应用直接执行 Node，请切换到 Shizuku 模式';

  @override
  String get labVisibleDesc => '手动开启后，这里才会显示实验室入口';

  @override
  String get labOpenLab => '进入实验室';

  @override
  String get labDownloading => '下载中';

  @override
  String get labExtracting => '解压中';

  @override
  String get labInstallingDeps => '安装依赖中';

  @override
  String get labStarting => '启动中';

  @override
  String get labLogs => '日志';

  @override
  String get labClearLogs => '清空';

  @override
  String get labVersion => '版本';

  @override
  String get labPhaseIdle => '就绪';

  @override
  String get labBrowserTools => '内置工具';

  @override
  String get labBrowserTitle => '内置浏览器';

  @override
  String get labBrowserDesc => '在应用内打开本地 WebUI、SillyTavern 或任意网址';

  @override
  String get labOpenBrowser => '打开浏览器';

  @override
  String get labManualUrl => '输入网址，例如 127.0.0.1:8000';

  @override
  String get labGo => '前往';

  @override
  String get labError => '出错了';

  @override
  String get labCancel => '取消';

  @override
  String get browserTitle => '浏览器';

  @override
  String get browserEditUrl => '编辑地址';

  @override
  String get browserUrlHint => 'https://example.com';

  @override
  String get browserGo => '前往';

  @override
  String get browserBack => '后退';

  @override
  String get browserForward => '前进';

  @override
  String get browserReload => '刷新';

  @override
  String get browserStop => '停止';

  @override
  String get browserMenu => '更多';

  @override
  String get browserCopyLink => '复制链接';

  @override
  String get browserCopyCookie => '复制 Cookie';

  @override
  String get browserCookieEmpty => '当前页面没有可复制的 Cookie';

  @override
  String get browserCookieCopied => 'Cookie 已复制';

  @override
  String get browserUaLabel => '浏览器标识';

  @override
  String get browserUaAuto => '自动';

  @override
  String get browserUaDesktop => '电脑端';

  @override
  String get browserUaMobile => '手机端';

  @override
  String get browserOpenExternal => '在系统浏览器打开';

  @override
  String browserInitFailed(String error) {
    return '网页加载失败：$error';
  }

  @override
  String get browserUnsupported => '当前平台不支持内置浏览器，请用系统浏览器打开';

  @override
  String get browserRetry => '重试';

  @override
  String get commonBack => '返回';

  @override
  String get close => '关闭';

  @override
  String get labMoreSettings => '更多设置';

  @override
  String get labInstallFirstTitle => '还没有安装 SillyTavern';

  @override
  String get labInstallFirstBody => '先在「更多设置」里装好，再回来打开这个开关。';

  @override
  String get labGoSettings => '去设置';

  @override
  String get labStartFailed => '启动失败';

  @override
  String get labStopped => '已停止';

  @override
  String get labSectionStatus => '运行状态';

  @override
  String get labSectionInstall => '安装';

  @override
  String get labApiConfig => 'API 配置';

  @override
  String get labApiGroup => '模型组';

  @override
  String get labApiGroupNone => '未选择';

  @override
  String get labApiModel => '模型';

  @override
  String get labApiBaseUrl => '接口地址';

  @override
  String get labApiKey => 'API Key';

  @override
  String get labApiNoKey => '还没有启用的 API Key（先去「密钥」页建一个）';

  @override
  String get labApiWrite => '写入 SillyTavern';

  @override
  String get labApiWriteOk => '已写入，刷新 SillyTavern 页面即生效';

  @override
  String labApiWriteFailed(String error) {
    return '写入失败：$error';
  }

  @override
  String get labApiNeedGroup => '先在「发现」页启用一个模型组';

  @override
  String get labApiNeedService => '没连上本机服务，先在仪表盘启动服务';

  @override
  String get labApiNoUserData => 'SillyTavern 还没启动过，先启动一次再写入';

  @override
  String get labApiPickGroup => '选择模型组';

  @override
  String get labApiPickModel => '选择模型';

  @override
  String labApiModelCount(String count) {
    return '$count 个模型';
  }

  @override
  String get labLogsEmpty => '还没有日志';

  @override
  String get labCopyLogs => '复制日志';

  @override
  String get labLogsCopied => '日志已复制';

  @override
  String get browserClosePage => '关闭页面';

  @override
  String get browserShareQr => '分享二维码';

  @override
  String get browserQrTitle => '扫码在手机上打开';

  @override
  String get browserViewCookies => '查看 Cookie';

  @override
  String get browserCopyAll => '全部复制';

  @override
  String get browserClipboardAccess => '允许网页写剪贴板';

  @override
  String get browserClipboardAllowed => '已允许剪贴板访问';

  @override
  String get browserClipboardBlocked => '已阻止剪贴板访问';

  @override
  String get browserSetUa => '自定义浏览器标识';

  @override
  String get browserUaEmptyHint => '留空恢复默认；改完会刷新页面';

  @override
  String get browserApplyAndReload => '应用并刷新';

  @override
  String get browserUaUpdated => '浏览器标识已更新';

  @override
  String get browserTroubleshootNetwork => '网络疑难解答';

  @override
  String get browserTroubleshootFailed => '打不开系统疑难解答';

  @override
  String get browserAndroidErrorTitle => '系统 WebView 挂了';

  @override
  String get browserAndroidErrorCause => '可能原因';

  @override
  String get browserAndroidErrorDetail => '系统 WebView 版本过旧或被禁用，内置浏览器起不来。';

  @override
  String get browserUpdateWebview => '更新 Android System WebView';

  @override
  String get browserOpenDevOptions => '查看 WebView 实现（开发者选项）';

  @override
  String get browserAppleErrorTitle => '内置浏览器无法启动';

  @override
  String get browserAppleErrorReport => '错误报告';

  @override
  String get browserAppleErrorDetail => 'WKWebView 初始化失败，通常是系统版本过低或受企业策略限制。';

  @override
  String get browserBsodMessage => '你的内置浏览器遇到了问题，需要重新启动。';

  @override
  String get browserBsodNoRestart => '我们只收集某些错误信息，然后为你重新启动。';

  @override
  String get browserBsodComplete => '0% 完成';

  @override
  String get browserBsodSolutions => '可以试试这些：';

  @override
  String get browserBsodDownload => '下载 Microsoft Edge WebView2 Runtime';

  @override
  String get browserBsodWinUpdate => '打开 Windows 更新';

  @override
  String get browserBsodScanQr => '手机扫码打开 WebView2 下载页';

  @override
  String get browserBsodStopCode => '停止代码：WEBVIEW2_NOT_INSTALLED';

  @override
  String get labStatus => '状态';

  @override
  String get browserUaHint => '粘贴或输入完整的 UA 字符串';

  @override
  String get labApiStopFirst => '先停止 SillyTavern 再写入（运行中的配置会被它自己覆盖）';

  @override
  String get labAutoOpenBrowser => '启动后自动打开浏览器';

  @override
  String get labAutoOpenBrowserDesc => '关掉后 SillyTavern 不再自己拉起系统浏览器；用「打开」手动进入';

  @override
  String get labDshTitle => 'DeepSeek Harness';

  @override
  String get labDshInstallFirstTitle => '还没有安装 DeepSeek Harness';

  @override
  String get labDshInstallFirstBody => '先在「更多设置」里装好，再回来打开这个开关。';

  @override
  String get labDshUninstallTitle => '卸载 DeepSeek Harness？';

  @override
  String get labDshUninstallBody => '会删除 npm 安装的 dsh 程序文件，模型配置与聊天记录保留在 ~/.dsh。';

  @override
  String get labDshPickModels => '选择要加入 dsh 的模型';

  @override
  String get labDshDefaultModel => '默认模型';

  @override
  String get labDshPickDefault => '选择默认模型';

  @override
  String get labDshWrite => '写入 dsh 配置';

  @override
  String get labDshWriteOk => '已写入 dsh 配置';

  @override
  String get labDshNeedModels => '先选模型组并勾选至少一个模型';

  @override
  String get labDshWriteHint => '写入后 dsh 的模型列表会热加载；正在运行时应用会自动重启它，让新密钥生效';

  @override
  String get labDshConfigPath => '配置文件';

  @override
  String get labDshOpenInApp => '应用内打开';

  @override
  String get labDshCompat => 'Android 兼容层';

  @override
  String get labDshCompatDesc => '关掉安卓上起不来的沙箱与 pwsh';

  @override
  String get browserSelectTitle => '选择';

  @override
  String get browserOpenCustomTab => '用 Custom Tabs 打开';

  @override
  String get browserCustomTabPick => '用哪个浏览器打开';

  @override
  String get browserCustomTabAuto => '自动（系统默认）';

  @override
  String get browserCustomTabNone => '没装支持 Custom Tabs 的浏览器';

  @override
  String get browserCustomTabFailed => '打不开这个链接';

  @override
  String get reply => '回复';

  @override
  String get labNotifySection => '通知';

  @override
  String get labNotifyPermission => '通知权限';

  @override
  String get labNotifyPermissionDesc => '任务进度、提问与结果都走通知';

  @override
  String get labNotifyLiveUpdate => '实时更新';

  @override
  String get labNotifyLiveUpdateDesc => 'Android 16+ 把任务进度置顶在通知栏、锁屏与状态栏';

  @override
  String get labNotifyPromoted => '系统已放行实时更新';

  @override
  String get labNotifyNotPromoted => '当前不会升级为实时更新';

  @override
  String get labNotifyBattery => '忽略电池优化';

  @override
  String get labNotifyBatteryDesc => '让 node / dsh 能在后台长时间跑';

  @override
  String get labNotifyBatteryIgnored => '已忽略电池优化';

  @override
  String get labNotifyOpenSettings => '系统通知设置';

  @override
  String get labNotifyTest => '发一条测试通知';

  @override
  String get labNotifyTestSent => '测试通知已发出';

  @override
  String get labNotifyTestFailed => '通知没发出去（检查权限）';

  @override
  String get labDshTaskHint => '任务提示词';

  @override
  String get labDshTaskHintDesc => '让模型按步骤汇报进度、需要拍板时停下来问你';

  @override
  String get labDshPlugins => '插件';

  @override
  String get labDshPluginMessageEdit => '编辑消息';

  @override
  String get labDshPluginMessageEditDesc =>
      '在用户消息旁加铅笔按钮，改完可从上一轮分叉重发（dsh-message-edit）';

  @override
  String get labDshPluginComputerUse => '电脑操作模式';

  @override
  String get labDshPluginComputerUseDesc =>
      '截屏 + 鼠标键盘控制，新任务可选「电脑操作模式」（dsh-computer-use-mode）';

  @override
  String get labDshPluginAndroid => '手机操作';

  @override
  String get labDshPluginAndroidDesc =>
      '手机操作：截屏、点按、滑动、UI 树、OCR、logcat（@zseven-w/dsh-android）';

  @override
  String get labDshPluginInstalling => '正在安装…';

  @override
  String get labDshPluginFailed => '插件操作失败';

  @override
  String get labDshPluginRestartHint => '开关后会自动重启 DSH 让插件生效';

  @override
  String get labDshRunTask => '运行任务';

  @override
  String get labDshRunTaskDesc => '把一句话交给 dsh 跑，进度与结果走通知';

  @override
  String get labDshTaskPrompt => '要 dsh 做什么？';

  @override
  String get labDshTaskBusy => '已经有一个任务在跑';

  @override
  String get labDshTaskStarted => '任务已开始，进度看通知';

  @override
  String get labDshTaskDone => '任务完成';

  @override
  String get labDshTaskFailed => '任务失败';

  @override
  String get labDshTaskCancelled => '任务已取消';

  @override
  String labDshTaskSteps(String done, String total) {
    return '$done/$total 步';
  }

  @override
  String get labDshAgentDone => 'agent 已完成此轮操作';

  @override
  String get labDshNeedAnswer => 'dsh 在等你回答';

  @override
  String get labDshAnswerHint => '打开 dsh web 回答';

  @override
  String get labDshToastReplyHint => '输入回答';

  @override
  String get labDshToastOptionsHint => '输入 1-3 选择，其他内容作为自定义回答';

  @override
  String get labDshToastSkip => '跳过';

  @override
  String get autoRefreshTitle => '自动更新模型';

  @override
  String get autoRefreshOff => '关闭';

  @override
  String get autoRefreshEvery1d => '每天';

  @override
  String get autoRefreshEvery3d => '每 3 天';

  @override
  String get autoRefreshEvery7d => '每 7 天';

  @override
  String get autoRefreshEvery30d => '每 30 天';

  @override
  String get autoRefreshDesc => '按设定的间隔去上游拉一次模型清单，新上的补进来、下架的删掉';

  @override
  String get autoRefreshNever => '还没刷新过';

  @override
  String get autoRefreshJustNow => '刚刚刷新过';

  @override
  String autoRefreshNextIn(String when) {
    return '下次 $when';
  }

  @override
  String get autoRefreshRefreshing => '正在刷新…';

  @override
  String autoRefreshDone(String added, String removed) {
    return '模型列表已更新：新增 $added 个，移除 $removed 个';
  }

  @override
  String get autoRefreshNoChange => '模型列表已是最新';

  @override
  String get autoRefreshRefreshNow => '立即刷新';

  @override
  String get autoRefreshFailed => '刷新失败';

  @override
  String get pluginManagerTitle => 'dsh 插件';

  @override
  String get pluginManagerRefresh => '重新扫描';

  @override
  String get pluginManagerSubtitle => '安装、开关与卸载 dsh 插件';

  @override
  String get pluginManagerSearch => '搜索插件';

  @override
  String get pluginManagerInstall => '安装';

  @override
  String get pluginManagerInstallTitle => '安装第三方插件';

  @override
  String get pluginManagerPackageHint => 'npm 包名，如 @scope/dsh-plugin-xxx';

  @override
  String get pluginManagerPackageEmpty => '请先填包名';

  @override
  String get pluginManagerInstalling => '安装中…';

  @override
  String get pluginManagerUninstall => '卸载';

  @override
  String pluginManagerUninstallConfirm(String name) {
    return '卸载 $name？这个包会从 dsh 里移除。';
  }

  @override
  String pluginManagerExitConfirm(String name) {
    return '停用 $name？已下载的包会保留，下次启用不用重装。';
  }

  @override
  String get pluginManagerRestartHint => '插件改动在 dsh 重启后生效';

  @override
  String get pluginManagerDescTitle => '第三方插件';

  @override
  String get pluginManagerEmpty => '还没装过插件';

  @override
  String get pluginManagerNotReady => 'dsh 还没装好，先装 dsh 再来管插件';

  @override
  String pluginManagerInstalledCount(String count) {
    return '$count 个已启用';
  }

  @override
  String get pluginManagerInstalledBadge => '已安装';

  @override
  String get pluginManagerCustom => '第三方';

  @override
  String get pluginManagerOfficial => '内置';

  @override
  String get pluginManagerLocal => '本地目录';

  @override
  String get pluginManagerAddLocal => '从本地目录安装';

  @override
  String get pluginManagerNoMatch => '没有匹配的插件';

  @override
  String get pluginManagerSearchClear => '清除搜索';

  @override
  String get pluginManagerExpand => '展开';

  @override
  String get pluginManagerCollapse => '收起';

  @override
  String pluginManagerOnlyOn(String platform) {
    return '仅支持 $platform';
  }

  @override
  String get pluginManagerNotInstalled => '未安装';

  @override
  String get pluginManagerDisabled => '未启用';

  @override
  String get pluginManagerEnabledState => '已启用';

  @override
  String pluginManagerOverview(String enabled, String total) {
    return '$enabled 个已启用 · 共 $total 个';
  }

  @override
  String get usageApiKeyFilter => 'API Key';

  @override
  String get usageAllApiKeys => '全部';

  @override
  String get usageModelFilter => '模型';

  @override
  String get usageAllModelsShort => '全部模型';

  @override
  String get usageRequestsShort => '请求';

  @override
  String get usageByModel => '各模型用量';

  @override
  String get usageModelCalls => 'API 请求次数';

  @override
  String get usageNoModelCalls => '这段时间没有调用记录';

  @override
  String get usageChartByModel => '按模型';

  @override
  String get usageChartByKey => '按 API Key';

  @override
  String get usageKeyName => '密钥';

  @override
  String get usageKeyAnonymous => '未鉴权调用';

  @override
  String get usageTotalRow => '合计';

  @override
  String get usageCallsUnit => '次';
}

/// The translations for Chinese, as used in China (`zh_CN`).
class AppLocalizationsZhCn extends AppLocalizationsZh {
  AppLocalizationsZhCn() : super('zh_CN');

  @override
  String get appTitle => 'Local2API';

  @override
  String get navServer => '服务';

  @override
  String get navModels => '模型';

  @override
  String get navKeys => '密钥';

  @override
  String get navSettings => '设置';

  @override
  String get serverTitle => '服务';

  @override
  String get serverRunning => '运行中';

  @override
  String get serverStopped => '已停止';

  @override
  String get serverStarting => '启动中…';

  @override
  String get homeStatusDescRunning => '服务已启动，客户端可以直接调用了';

  @override
  String get homeStatusDescStopped => '服务未启动，点一下卡片启动';

  @override
  String get homeStatusDescStarting => '正在启动服务…';

  @override
  String get homeStatusDescError => '启动失败，点一下卡片重试';

  @override
  String get startServer => '启动服务';

  @override
  String get stopServer => '停止服务';

  @override
  String get restartServer => '重启服务';

  @override
  String get endpointTitle => '接入地址';

  @override
  String get listenAddress => '监听地址';

  @override
  String get listenPort => '监听端口';

  @override
  String get copy => '复制';

  @override
  String get copied => '已复制';

  @override
  String get allInterfaces => '所有网卡 (0.0.0.0)';

  @override
  String get loopbackOnly => '仅本机 (127.0.0.1)';

  @override
  String get lanIpsLabel => '局域网/VPN 地址';

  @override
  String get statsTitle => '请求统计';

  @override
  String get statTotalRequests => '累计请求';

  @override
  String get statErrors => '失败';

  @override
  String get statActive => '活跃连接';

  @override
  String get recentLogs => '最近请求';

  @override
  String get viewAll => '查看全部';

  @override
  String get noLogsYet => '暂无请求日志';

  @override
  String get noKeysWarningTitle => '未配置密钥';

  @override
  String get noKeysWarningBody => '任何客户端都可以直接调用此服务，建议在仪表盘「密钥」分区添加至少一个密钥。';

  @override
  String get noCidrWarningTitle => '对所有来源开放';

  @override
  String get noCidrWarningBody => '未配置任何 IP 规则，所有网段均可访问。';

  @override
  String get serverErrorTitle => '服务异常';

  @override
  String portInUse(String port) {
    return '端口 $port 被占用';
  }

  @override
  String get autoStart => '启动时自动开启服务';

  @override
  String get modelsTitle => '模型';

  @override
  String get upstreams => '上游服务';

  @override
  String get addUpstream => '添加上游';

  @override
  String get noUpstreams => '还没有上游，先添加一个';

  @override
  String get upstreamTypeLabel => '类型';

  @override
  String get typeOpenai => 'OpenAI 兼容';

  @override
  String get typeLlamacpp => 'llama.cpp';

  @override
  String get typeOllama => 'Ollama';

  @override
  String get typeLocalTts => '本地 TTS (Qwen3)';

  @override
  String get modalityLabel => '模态';

  @override
  String get modalityChat => '对话 (chat)';

  @override
  String get modalityAudio => '语音 (audio)';

  @override
  String get modalityAudioHint =>
      '开启后 /v1/audio/speech 会把 OpenAI TTS 请求翻译成该上游的 chat.completions 语音请求（MiMo TTS 等），再把回包音频解给客户端';

  @override
  String get localTtsSectionTitle => '本地 TTS（Qwen3-TTS）';

  @override
  String get ttsSettingsTitle => 'TTS 设置';

  @override
  String get ttsSettingsDesc => '本地模型、服务商与试听';

  @override
  String get ttsAutoPlayTitle => '自动播放 TTS';

  @override
  String localTtsModelSize(String size) {
    return '共约 $size GB';
  }

  @override
  String get localTtsStateInstalled => '已安装';

  @override
  String get localTtsStatePartial => '未下完（可续传）';

  @override
  String get localTtsStateNotInstalled => '未下载';

  @override
  String get localTtsDownload => '下载模型';

  @override
  String localTtsDownloadProgress(String received, String total) {
    return '下载中 $received/$total MB';
  }

  @override
  String get localTtsDeleteConfirm => '删除本地 TTS 模型文件？';

  @override
  String get localTtsDevicePreference => '推理后端';

  @override
  String get ttsDeviceAuto => '自动（高通优先 NPU）';

  @override
  String get ttsDeviceNpu => 'NPU (Hexagon)';

  @override
  String get ttsDeviceGpu => 'GPU (Vulkan)';

  @override
  String get ttsDeviceCpu => 'CPU';

  @override
  String get localTtsTestSpeak => '试听';

  @override
  String get localTtsTestStop => '停止';

  @override
  String get localTtsStatusPreparing => '正在加载模型…';

  @override
  String get localTtsStatusSynthesizing => '正在合成语音…';

  @override
  String get localTtsStatusPlaying => '播放中';

  @override
  String get localTtsStatusIdle => '空闲';

  @override
  String get localTtsStatusError => '出错';

  @override
  String get localTtsNotReady => '模型未下载或下载不完整';

  @override
  String get localTtsServeHint =>
      '下载完成后，点下方「创建本地 TTS 上游」一键配置；客户端通过 /v1/audio/speech 调用（模型名 qwen3-tts）';

  @override
  String get localTtsUpstreamName => '本地 TTS';

  @override
  String get localTtsCreateUpstream => '创建本地 TTS 上游';

  @override
  String get localTtsCreateUpstreamDesc =>
      '自动在模型页添加「本地 TTS」上游（模型 qwen3-tts），客户端即可调 /v1/audio/speech';

  @override
  String get localTtsUpstreamCreated => '已创建「本地 TTS」上游';

  @override
  String get localTtsUpstreamExists => '已存在「本地 TTS」上游';

  @override
  String get settingsFeaturesSection => '服务与功能';

  @override
  String get networkSettingsTitle => '网络设置';

  @override
  String get networkSettingsDesc => '端口与监听、临时 WebUI、IP 访问规则';

  @override
  String get chatSettingsTitle => '对话设置';

  @override
  String get chatSettingsDesc => 'TTS 设置、自动播放与角色卡';

  @override
  String get ipRulesEmpty => '暂无规则，默认放行所有来源';

  @override
  String ipRulesCount(String count) {
    return '$count 条规则';
  }

  @override
  String ruleDeletedCount(String count) {
    return '已删除 $count 条规则';
  }

  @override
  String ruleRestored(String count) {
    return '已恢复 $count 条规则';
  }

  @override
  String get characterEntryDesc => '管理对话模拟的角色卡与默认场景';

  @override
  String get ttsProviderLabel => '默认 TTS 服务商';

  @override
  String get ttsProviderOff => '关闭';

  @override
  String get ttsProviderLocal => '本地 Qwen3-TTS';

  @override
  String get ttsProviderNoneHint => '还没有能发声的模型：给语音上游加个模型，或先下载本地模型';

  @override
  String get ttsDesignModelLabel => '默认语音设计模型';

  @override
  String get ttsDesignModelDesc => '角色卡没配音色样本时用它合成，提示词即音色描述';

  @override
  String get ttsDesignPromptLabel => '音色设计提示词';

  @override
  String get ttsDesignPromptDesc => '设计模型的音色描述（user 消息），留空用默认';

  @override
  String get ttsCloneModelLabel => '默认克隆模型';

  @override
  String get ttsCloneModelDesc => '角色卡配了音色样本时用它克隆合成';

  @override
  String get ttsDesignPromptDefault => '默认';

  @override
  String get ttsPlaygroundTitle => 'TTS 调试台';

  @override
  String get ttsPlaygroundDesc => '换样本 / 文本反复试听，排查克隆与设计效果';

  @override
  String get ttsPlaygroundHint =>
      '选模型、配音色样本、输入文本后播放。克隆不像时优先换样本：一段干净的单人声（5–10 秒、无背景音乐、无混响）比长音频效果好得多。';

  @override
  String get ttsPlaygroundModel => '模型';

  @override
  String get ttsPlaygroundText => '合成文本';

  @override
  String get ttsPlaygroundInstructions => '风格指令 / 音色描述（可选）';

  @override
  String get ttsPlaygroundPlay => '播放';

  @override
  String get ttsPlaygroundEmptyText => '先输入要合成的文本';

  @override
  String get ttsPlaygroundCloneNeedsSample => '克隆模型需要音色样本：先在上方配一段音频';

  @override
  String get ttsSpeak => '朗读';

  @override
  String get characterVoiceLabel => '音色样本';

  @override
  String get characterVoiceHint =>
      '选一段清晰人声（wav/mp3，≤7MB）用于克隆音色。推荐配云端克隆（快，几秒出声）；本地克隆要等 1.4GB 模型加载，首次可能要几分钟。';

  @override
  String get characterVoicePick => '选择音频';

  @override
  String get characterVoiceRemove => '移除';

  @override
  String get characterVoiceTooBig => '音频样本太大，请压缩到 7MB 以内';

  @override
  String get characterVoiceBadType => '仅支持 wav / mp3 音频';

  @override
  String get characterOverrideReset => '已恢复内置原文';

  @override
  String get upstreamNameLabel => '名称';

  @override
  String get baseUrlLabel => '接口地址 (Base URL)';

  @override
  String get baseUrlHint => 'http://192.168.1.10:11434/v1';

  @override
  String get upstreamKeyLabel => '上游密钥（可选）';

  @override
  String get upstreamNoteLabel => '备注';

  @override
  String get upstreamNoteHint => '这个上游是干什么的、有什么注意事项（可留空）';

  @override
  String get upstreamJsonTitle => '上游 JSON';

  @override
  String get fetchModelsBtn => '拉取模型';

  @override
  String get testBtn => '测试';

  @override
  String get testOk => '连接成功';

  @override
  String testFailed(String error) {
    return '连接失败：$error';
  }

  @override
  String fetchFailed(String error) {
    return '拉取失败：$error';
  }

  @override
  String fetchedModels(String count) {
    return '获取到 $count 个模型';
  }

  @override
  String get saveBtn => '保存';

  @override
  String get deleteBtn => '删除';

  @override
  String deleteUpstreamConfirm(String name) {
    return '删除上游「$name」？';
  }

  @override
  String get cancel => '取消';

  @override
  String get confirm => '确定';

  @override
  String get exposedModelsTitle => '对外模型';

  @override
  String get noExposedModels => '没有对外暴露的模型';

  @override
  String get modelAliasLabel => '对外名称';

  @override
  String get modelTargetLabel => '上游模型';

  @override
  String get enabledLabel => '启用';

  @override
  String get exposedLabel => '暴露';

  @override
  String get baseUrlInvalid => '地址无效，需要 http(s):// 开头';

  @override
  String get fetchingModels => '正在获取模型…';

  @override
  String get testing => '正在测试…';

  @override
  String get editUpstream => '编辑上游';

  @override
  String get newUpstream => '新建上游';

  @override
  String get upstreamNameRequired => '名称不能为空';

  @override
  String modelCountLabel(String count) {
    return '$count 个模型';
  }

  @override
  String get upstreamEditHint => '一个上游就是一个 OpenAI 兼容端点，改完点右上角保存。';

  @override
  String get upstreamModeLabel => '模式';

  @override
  String get pickModeTitle => '选择模式';

  @override
  String get notFilled => '未填写';

  @override
  String get testConnectionTitle => '测试连接';

  @override
  String get testConnectionDesc => '用当前地址和密钥试一次';

  @override
  String get addModelBtn => '添加模型';

  @override
  String get modelsPageHint => '点右上角下载图标从上游拉取模型，再勾要暴露的；加号可以手动填一个。';

  @override
  String get modelsSortTitle => '排序方式';

  @override
  String get modelsSortNatural => '默认顺序';

  @override
  String get modelsSortAlphabet => '首字母正序';

  @override
  String get keysTitle => '密钥';

  @override
  String get addKey => '添加密钥';

  @override
  String get keyNameLabel => '备注';

  @override
  String get keyNameHint => '例如：我的手机';

  @override
  String get keyValueLabel => '密钥';

  @override
  String get generate => '随机生成';

  @override
  String get noKeysHint => '尚无密钥，任何客户端都能直接调用';

  @override
  String deleteKeyConfirm(String name) {
    return '删除密钥「$name」？';
  }

  @override
  String get keyExists => '该密钥已存在';

  @override
  String get keyRequired => '密钥不能为空';

  @override
  String get settingsTitle => '设置';

  @override
  String get networkSection => '网络与访问';

  @override
  String get accessRules => 'IP 访问规则';

  @override
  String get accessRuleDesc => '按顺序匹配，先命中先生效；为空则全部放行';

  @override
  String get addRule => '添加规则';

  @override
  String get ruleAllow => '放行';

  @override
  String get ruleDeny => '拒绝';

  @override
  String get cidrHint => '例如 192.168.0.0/16';

  @override
  String get cidrInvalid => 'CIDR 格式不正确';

  @override
  String get corsToggle => '允许跨域（CORS）';

  @override
  String get corsDesc => '允许网页前端直接调用本服务';

  @override
  String get autoStartToggle => '启动时自动运行服务';

  @override
  String get appearanceSection => '外观';

  @override
  String get themeLabel => '主题';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get languageLabel => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageNote => 'Android 13+ 可在系统「应用语言」中设置';

  @override
  String get aboutSection => '关于';

  @override
  String get aboutDesc =>
      '将局域网/VPN 内的 llama.cpp、Ollama 或任意 OpenAI 兼容接口，转发为带鉴权与模型白名单的一层新 API。';

  @override
  String get versionLabel => '版本';

  @override
  String get aboutEntryDesc => '版本、组件与效果背景';

  @override
  String get aboutTapLogoHint => '点一点上面的图标试试';

  @override
  String get aboutOpenLicenses => '开源许可';

  @override
  String get ossTitle => '开源许可';

  @override
  String get ossSearchHint => '搜索依赖包或许可标识';

  @override
  String get ossClearSearch => '清除搜索';

  @override
  String ossPackagesCount(String count, String licenses) {
    return '共 $count 个依赖包 · $licenses 份许可';
  }

  @override
  String ossLicensesCount(String count) {
    return '$count 份许可';
  }

  @override
  String get ossEmptySearch => '没有匹配的依赖包';

  @override
  String get ossLoadFailed => '许可清单加载失败';

  @override
  String get ossRetry => '重试';

  @override
  String get ossLoading => '正在收集许可清单…';

  @override
  String get ossCopyFullText => '复制全部许可';

  @override
  String get ossLicenseCopied => '已复制到剪贴板';

  @override
  String ossLicenseIndex(String index, String count) {
    return '第 $index / $count 份';
  }

  @override
  String get aboutComponents => '构建组件';

  @override
  String get aboutComponentsDesc => 'Flutter · flutter_miuix（HyperOS 风格）';

  @override
  String get textureSetTitle => '纹理集';

  @override
  String get textureSetEffectVariant => '效果变体';

  @override
  String get textureSetOs2 => 'OS2';

  @override
  String get textureSetOs3 => 'OS3';

  @override
  String get textureSetEffectBg => '效果背景';

  @override
  String get textureSetDynamicBg => '动态背景';

  @override
  String get textureSetBlurEnable => '模糊';

  @override
  String get textureSetBlurRadius => '模糊半径';

  @override
  String get textureSetNoise => '噪点';

  @override
  String get textureSetBrightness => '亮度';

  @override
  String get textureSetContrast => '对比度';

  @override
  String get textureSetSaturation => '饱和度';

  @override
  String get textureSetBlendMode => '混合模式';

  @override
  String get textureSetReset => '恢复默认';

  @override
  String get blendModeDefault => '默认';

  @override
  String get blendModeOverlay => '叠加';

  @override
  String get blendModeScreen => '滤色';

  @override
  String get blendModeMultiply => '正片叠底';

  @override
  String get blendModePlusLighter => '加亮';

  @override
  String get blendModePlusDarker => '加深';

  @override
  String get blendModeLinearLight => '线性光';

  @override
  String get blendModeDifference => '差值';

  @override
  String get unsavedChangesTitle => '未保存的更改';

  @override
  String get unsavedChangesMessage => '你对这个上游的修改还没有保存，要现在保存吗？';

  @override
  String get unsavedSave => '保存';

  @override
  String get unsavedDiscard => '不保存';

  @override
  String get chatSimModelPicker => '模拟模型';

  @override
  String get chatSimModelAll => '全部（整组共享）';

  @override
  String get chatSimModelAllDesc => '组内任意模型被调用都带上这段上下文';

  @override
  String get chatSimModelSpecificDesc => '仅此模型带上这段上下文';

  @override
  String get editMenuUndo => '撤消(U)';

  @override
  String get editMenuCut => '剪切(T)';

  @override
  String get editMenuCopy => '复制(C)';

  @override
  String get editMenuPaste => '粘贴(P)';

  @override
  String get editMenuDelete => '删除(D)';

  @override
  String get editMenuSelectAll => '全选(A)';

  @override
  String get portRangeInvalid => '端口范围 1024-65535';

  @override
  String get logsTitle => '请求日志';

  @override
  String get clearLogs => '清空';

  @override
  String get logsCleared => '已清空';

  @override
  String get stopServerConfirm => '停止服务？';

  @override
  String get clientLabel => '客户端';

  @override
  String get modelLabel => '模型';

  @override
  String get statusLabel => '状态';

  @override
  String get durationLabel => '耗时';

  @override
  String get colorAmber => '琥珀色';

  @override
  String get colorBlue => '蓝色';

  @override
  String get colorBlueGrey => '蓝灰色';

  @override
  String get colorBrown => '棕色';

  @override
  String get colorCyan => '青色';

  @override
  String get colorDeepPurple => '深紫色';

  @override
  String get colorDefaultGreen => '默认绿';

  @override
  String get colorGreen => '绿色';

  @override
  String get colorGrey => '灰色';

  @override
  String get colorIndigo => '靛蓝色';

  @override
  String get colorLightBlue => '浅蓝色';

  @override
  String get colorLightGreen => '浅绿色';

  @override
  String get colorLime => '酸橙色';

  @override
  String get colorOrange => '橙色';

  @override
  String get colorPink => '粉红色';

  @override
  String get colorPurple => '紫色';

  @override
  String get colorRed => '红色';

  @override
  String get colorTeal => '蓝绿色';

  @override
  String get colorYellow => '黄色';

  @override
  String get commonBackTooltip => '转到上一层级';

  @override
  String get commonCancel => '取消';

  @override
  String get commonCreate => '创建';

  @override
  String get commonDelete => '删除';

  @override
  String get commonSave => '保存';

  @override
  String get displayFollowSystemColor => '跟随系统配色';

  @override
  String get displayFontWeight => '文字粗细';

  @override
  String get displayOff => '已关闭';

  @override
  String get displayPureBlack => '纯黑深色模式';

  @override
  String get displayPureBlackOn => '深色模式（已黑化）';

  @override
  String get displayScaleCompact => '紧凑模式 · 显示更多内容';

  @override
  String get displayScaleCompactBig => '紧凑 · 适合大屏';

  @override
  String get displayScaleDefault => '默认';

  @override
  String get displayScaleFineTune => '精细调节';

  @override
  String get displayScaleHuge => '超大 · 辅助功能';

  @override
  String get displayModeTitle => '屏幕帧率';

  @override
  String get displayModeAuto => '自动';

  @override
  String get displayModeSystemTag => '[系统]';

  @override
  String get displayModeHint => '没有生效？重启应用试试';

  @override
  String get displayModeUnsupported => '当前平台不支持设置屏幕帧率（仅 Android）';

  @override
  String get displayModeLoading => '正在获取屏幕帧率...';

  @override
  String get displayModeEmpty => '未获取到可用的屏幕帧率';

  @override
  String get displayScaleLarge => '略大 · 更易阅读';

  @override
  String get displayScaleLargeFont => '大字体 · 无障碍友好';

  @override
  String get displayScaleLargeFontShort => '大字体 · 无障碍';

  @override
  String get displayScaleMin => '最小 · 信息密度最高';

  @override
  String get displayScaleNote =>
      '缩放比例会全局应用于文字与部分布局尺寸。设为 100% 可恢复默认。修改即时生效，无需重启。';

  @override
  String get displayScalePresets => '快捷预设';

  @override
  String get displayScaleReset => '重置为 100%';

  @override
  String get displayScaleSmall => '略小 · 适合大屏';

  @override
  String get displayScaleSystemDefault => '系统默认';

  @override
  String get displayScaleTitle => '显示缩放';

  @override
  String get displaySectionAppearance => '外观';

  @override
  String get displaySectionPersonalize => '个性化';

  @override
  String get displaySeedAmber => '琥珀色';

  @override
  String get displaySeedBlue => '蓝色';

  @override
  String get displaySeedBlueGrey => '蓝灰色';

  @override
  String get displaySeedBrown => '棕色';

  @override
  String get displaySeedCustom => '自定义';

  @override
  String get displaySeedCyan => '青色';

  @override
  String get displaySeedDeepPurple => '深紫色';

  @override
  String get displaySeedDefaultGreen => '默认绿';

  @override
  String get displaySeedGreen => '绿色';

  @override
  String get displaySeedGrey => '灰色';

  @override
  String get displaySeedIndigo => '靛蓝色';

  @override
  String get displaySeedLightBlue => '浅蓝色';

  @override
  String get displaySeedLightGreen => '浅绿色';

  @override
  String get displaySeedLime => '酸橙色';

  @override
  String get displaySeedOrange => '橙色';

  @override
  String get displaySeedPink => '粉红色';

  @override
  String get displaySeedPurple => '紫色';

  @override
  String get displaySeedRed => '红色';

  @override
  String get displaySeedTeal => '蓝绿色';

  @override
  String get displaySeedYellow => '黄色';

  @override
  String get displaySettingsTitle => '显示';

  @override
  String get displayThemeColor => '主题配色';

  @override
  String get displayThemeDark => '深色';

  @override
  String get displayThemeLight => '浅色';

  @override
  String get displayThemeMode => '主题模式';

  @override
  String displayWeightBlack(int weight) {
    return '极粗 ($weight)';
  }

  @override
  String displayWeightBold(int weight) {
    return '粗 ($weight)';
  }

  @override
  String displayWeightCustom(int weight) {
    return '自定义 ($weight)';
  }

  @override
  String displayWeightLight(int weight) {
    return '细 ($weight)';
  }

  @override
  String displayWeightMedium(int weight) {
    return '中等 ($weight)';
  }

  @override
  String displayWeightRegular(int weight) {
    return '常规 ($weight)';
  }

  @override
  String displayWeightThin(int weight) {
    return '极细 ($weight)';
  }

  @override
  String get drawerSystemMode => '跟随系统';

  @override
  String get fontWeightBlack => '极粗';

  @override
  String get fontWeightBold => '粗';

  @override
  String get fontWeightLight => '细';

  @override
  String get fontWeightMedium => '中等';

  @override
  String get fontWeightRegular => '常规';

  @override
  String get fontWeightSampleText =>
      'The quick brown fox jumps over the lazy dog.\n敏捷的棕色狐狸跳过懒惰的狗。';

  @override
  String get fontWeightSaveApply => '保存并应用';

  @override
  String get fontWeightUnsavedTitle => '有未保存的调整';

  @override
  String fontWeightUnsavedBody(int weight) {
    return '文字粗细改成了 $weight，还没确认。';
  }

  @override
  String get fontWeightUnsavedSave => '保存';

  @override
  String get fontWeightUnsavedDiscard => '不保存';

  @override
  String get fontWeightThin => '极细';

  @override
  String get playlistMenuMore => '更多操作';

  @override
  String get searchPureBlack => '纯黑深色模式';

  @override
  String get searchThemeMode => '主题模式';

  @override
  String get startScreenGoBack => '转到上一层级';

  @override
  String get themeAppearance => '外观';

  @override
  String themeColorCopied(String hex) {
    return '已复制色号: $hex';
  }

  @override
  String get themeColorExtracted => '已从图片提取主题色';

  @override
  String themeColorFailed(String error) {
    return '取色失败: $error';
  }

  @override
  String get themeColorsSection => '配色';

  @override
  String get themeCopyColor => '复制色号';

  @override
  String get themeCreateTitle => '创建自定义主题';

  @override
  String themeCreated(String name) {
    return '主题 \"$name\" 已创建并保存';
  }

  @override
  String get themeDarkBlackened => '深色模式（已黑化）';

  @override
  String themeDeleteConfirm(String name) {
    return '确定要删除自定义主题 \"$name\" 吗？';
  }

  @override
  String get themeDeleteTitle => '删除主题';

  @override
  String themeDeleted(String name) {
    return '已删除 \"$name\"';
  }

  @override
  String get themeDropHint => '松开以从图片提取主题色';

  @override
  String get themeEnabled => '已启用';

  @override
  String get themeFollowSystem => '跟随系统配色';

  @override
  String get themeHexHint => '例如 #FF0000 或 255,0,0';

  @override
  String get themeHexLabel => '十六进制/RGB';

  @override
  String get themeImageOnly => '仅支持图片格式';

  @override
  String get themeNameHint => '请输入文本';

  @override
  String get themeNameLabel => '主题名称';

  @override
  String get themeNewTheme => '新建主题';

  @override
  String get themeOff => '已关闭';

  @override
  String get themePaletteStyle => '调色板风格';

  @override
  String get themePickColor => '选择颜色';

  @override
  String get settingsBlurTitle => '启用模糊';

  @override
  String get settingsBlurDesc => '为应用启用模糊效果';

  @override
  String get settingsCustomColorsTitle => '自定义颜色';

  @override
  String get settingsCustomColorsDesc => '在 Miuix 主题风格下自定义主题颜色';

  @override
  String get themeCustomColorsNeeded => '需要启用自定义颜色';

  @override
  String get themePickFromImage => '从图片取色';

  @override
  String themeSwitched(String name) {
    return '已切换至 $name 主题';
  }

  @override
  String get themeTitle => '主题';

  @override
  String get settingsDisplaySection => '外观';

  @override
  String get settingsDisplayEntry => '显示设置';

  @override
  String get drawerDarkMode => '深色模式';

  @override
  String get drawerLightMode => '浅色模式';

  @override
  String get sideBarCollapse => '收起侧边栏';

  @override
  String get sideBarExpand => '展开侧边栏';

  @override
  String get navDiscover => '发现';

  @override
  String get laneProbing => '探测中…';

  @override
  String get laneUsable => '可用';

  @override
  String get laneRestricted => '仅限官方客户端';

  @override
  String get laneThrottled => '额度已达上限';

  @override
  String get laneRegionBlocked => '出口地区受限';

  @override
  String get laneUnavailable => '模型当前不可用';

  @override
  String get laneFailed => '不可用';

  @override
  String get laneNetUnreachable => '连不上端点';

  @override
  String get navDashboard => '仪表盘';

  @override
  String get dashboardTitle => '仪表盘';

  @override
  String get fabRefresh => '刷新';

  @override
  String get fabAppearance => '外观';

  @override
  String get appearancePanelTitle => '外观快速设置';

  @override
  String get fabDelayTest => '测试连接';

  @override
  String get laneUntested => '尚未测试';

  @override
  String get laneHintRoute => '点选一条车道作为链首，其余按顺序自动回退。';

  @override
  String get discoverTitle => '发现';

  @override
  String get discoverIntro => '这里列出全部上游：开关管启用/停用，闪电测速，点卡片改配置；下拉刷新可用模型列表。';

  @override
  String get fabNewUpstream => '新建上游';

  @override
  String get createConfigTitle => '创建配置';

  @override
  String get createConfigFileTitle => '文件';

  @override
  String get createConfigFileDesc => '从文件、订阅链接或粘贴 JSON 导入';

  @override
  String get createConfigUpstreamDesc => '手动创建一组上游配置';

  @override
  String get profileNewUpstreamTitle => '新建上游';

  @override
  String get profileGroupNameLabel => '名称';

  @override
  String get profileGroupNameHint => '给这个模型组起个名字（留空就用档案自带的）';

  @override
  String get profileGroupDescLabel => '说明';

  @override
  String get profileGroupDescHint => '这一组是什么、从哪来（可留空）';

  @override
  String get profileSpeedTest => '测速';

  @override
  String get profileRefreshModels => '刷新可用模型';

  @override
  String get profileLanesDynamic => '模型清单随上游变动';

  @override
  String profileModelsRefreshed(int count) {
    return '已刷新 $count 个组的可用模型';
  }

  @override
  String get profileModelsRefreshFailed => '一个组都没刷出来，看看网络或端点地址';

  @override
  String keyDeletedCount(int count) {
    return '已删除 $count 个密钥';
  }

  @override
  String get keyRestore => '恢复';

  @override
  String keyRestored(int count) {
    return '已恢复 $count 个密钥';
  }

  @override
  String get keysManage => '管理密钥';

  @override
  String get keysIntro => '密钥是这一层的门禁：只有带着密钥的客户端才允许调用。左滑一行可以删除。';

  @override
  String get keysEmptyPage => '还没有密钥，点右下角加号添加一个。';

  @override
  String get usageTitle => 'Token 统计';

  @override
  String get usageIntro => '本机代理接住的每一次请求都在这里记账：输入 / 输出 / 缓存命中，按模型与时间查。';

  @override
  String get usageAllModels => '全部模型';

  @override
  String get usageRangeToday => '今天';

  @override
  String get usageRange7 => '近 7 天';

  @override
  String get usageRange30 => '近 30 天';

  @override
  String get usageRangeAll => '全部';

  @override
  String get usageTotal => '合计';

  @override
  String get usageInput => '输入';

  @override
  String get usageOutput => '输出';

  @override
  String get usageCacheHit => '缓存命中';

  @override
  String get usageCacheMiss => '缓存未命中';

  @override
  String get usageHitRate => '命中率';

  @override
  String get usageRequests => '请求数';

  @override
  String get usageReasoning => '思考';

  @override
  String get usageByDay => '按天';

  @override
  String get usageRecent => '最近记录';

  @override
  String get usageEmpty => '这段时间还没有记录，跑一轮模型后这里就有数了。';

  @override
  String get usageNoUsageData => '上游未给用量';

  @override
  String get usageClear => '清空用量';

  @override
  String get usageClearConfirm => '清空全部 token 用量记录？';

  @override
  String get usageCleared => '用量记录已清空';

  @override
  String get usageOpen => '查看 Token 统计';

  @override
  String get usageCalendar => '用量日历';

  @override
  String get usageCalendarOpen => '日历';

  @override
  String get usageCalendarIntro => '点日期看当天调用了哪些模型，点卡片就带着那一天回到统计页。';

  @override
  String get usageCalendarPrevMonth => '上个月';

  @override
  String get usageCalendarNextMonth => '下个月';

  @override
  String get usageCalendarEmptyDay => '这天没有调用记录';

  @override
  String usageCalendarDayModels(String date) {
    return '$date 的活动';
  }

  @override
  String get chatSimTitle => '对话模拟';

  @override
  String get chatSimAutoSaved => '对话默认保存在本机（按模型组分开放），下次进来接着聊。';

  @override
  String get chatSimVoiceInput => '语音输入';

  @override
  String get chatSimVoiceStop => '停止语音输入';

  @override
  String get chatSimVoicePreparing => '离线语音模型准备中，稍等再试';

  @override
  String get chatSimVoiceUnavailable => '当前设备不支持语音输入';

  @override
  String get chatSimAttach => '添加附件';

  @override
  String get chatSimAttachImage => '图片';

  @override
  String get chatSimAttachFile => '文件';

  @override
  String get chatSimAttachUserOnly => '附件只加在用户消息上';

  @override
  String get chatSimRemoved => '已删除';

  @override
  String get chatSimIntro =>
      '把这里的对话当成下游客户端发的一条请求，走本机代理的真实链路（路由 / 回退 / 指纹 / 请求日志）。前面的消息会一起带出去。图片会随消息发给模型（纯文本车道可切「仅发文字」），文件只在界面上展示；长按消息可直接删除。';

  @override
  String get chatSimServerOff => '服务没在运行，先启动它再发。';

  @override
  String get chatSimStartServer => '启动服务';

  @override
  String get chatSimNoModel => '这一组还没有对外暴露的模型，先在发现页启用它。';

  @override
  String get chatSimSend => '发送';

  @override
  String get chatSimSendOnly => '仅发送';

  @override
  String get chatSimSendOnlyDesc => '只把请求发出去，不等模型回复';

  @override
  String get chatSimSentOnly => '已发送（未等待回复）';

  @override
  String get chatSimSendModeOnly => '发送（模型不响应）';

  @override
  String get chatSimSendModeHint => '长按切换';

  @override
  String get chatSimSending => '生成中…';

  @override
  String get chatSimClear => '清空对话';

  @override
  String get chatSimClearConfirm => '清空这次对话？';

  @override
  String get chatSimMore => '更多';

  @override
  String get chatSimAvatarTitle => '头像设置';

  @override
  String get chatSimAvatarUser => '用户头像';

  @override
  String get chatSimAvatarAssistant => '助手头像';

  @override
  String get chatSimAvatarPick => '从相册选择';

  @override
  String get chatSimAvatarCamera => '拍照';

  @override
  String get chatSimAvatarReset => '恢复默认';

  @override
  String get chatSimAvatarUpdated => '头像已更新';

  @override
  String chatSimAvatarFailed(String error) {
    return '头像更新失败：$error';
  }

  @override
  String get callTitleAction => '通话';

  @override
  String get callTitleVoice => '语音通话';

  @override
  String get callTitleVideo => '视频通话';

  @override
  String get callStatusCalling => '正在接通…';

  @override
  String get callStatusEnded => '通话已结束';

  @override
  String get callRecords => '对话记录';

  @override
  String get callStatusListening => '在听…';

  @override
  String get callStatusThinking => '思考中…';

  @override
  String get callStatusSpeaking => '说话中…';

  @override
  String get callMic => '麦克风';

  @override
  String get callMicDone => '说完了';

  @override
  String get callInterrupt => '打断';

  @override
  String get callVideoNeedOmni => '视频通话需要 Omni 模型';

  @override
  String get callAsrUnavailable => '语音识别不可用，检查麦克风权限';

  @override
  String get callMute => '静音';

  @override
  String get callUnmute => '取消静音';

  @override
  String get callSpeakerOn => '免提';

  @override
  String get callSpeakerOff => '关闭免提';

  @override
  String get callSwitchToVideo => '切换到视频通话';

  @override
  String get callSwitchToVoice => '切换到语音通话';

  @override
  String get callHangUp => '挂断';

  @override
  String get callSettingsTitle => '通话设置';

  @override
  String get callSettingsOmniHint =>
      '当前模型不是 Omni 模型：基础语音通话照常可用；「允许打断」和「允许调用摄像头」需要 Omni 模型。';

  @override
  String get callAllowInterrupt => '允许打断';

  @override
  String get callAllowInterruptDesc => '模型说话时可以随时插话（需要 Omni 模型）';

  @override
  String get callAllowCamera => '允许调用摄像头';

  @override
  String get callAllowCameraDesc => '视频通话时把摄像头画面发送给模型（需要 Omni 模型）';

  @override
  String get callCameraBlocked => '已禁止调用摄像头';

  @override
  String get callVideoStagePlaceholder => '摄像头画面 · 暂未接入';

  @override
  String get chatSimRegenerate => '重新生成';

  @override
  String get chatSimEditTitle => '编辑消息';

  @override
  String get chatSimSave => '保存';

  @override
  String get chatSimSaveAndSend => '保存并发送';

  @override
  String get chatSimAddMessage => '添加消息';

  @override
  String get chatSimRoleLabel => '角色';

  @override
  String get chatSimRoleSystem => '系统';

  @override
  String get chatSimRoleUser => '用户';

  @override
  String get chatSimRoleAssistant => '助手';

  @override
  String get chatSimHintInput => '输入一条消息（默认按用户发）';

  @override
  String chatSimModelLabel(String model) {
    return '请求模型 $model';
  }

  @override
  String chatSimMeta(int words, String time) {
    return '字数 $words · 耗时 $time';
  }

  @override
  String chatSimServedModel(String model) {
    return '响应模型 $model';
  }

  @override
  String chatSimServedModelVia(String lane, String model) {
    return '响应模型 $lane（请求 $model）';
  }

  @override
  String get characterTitle => '角色卡';

  @override
  String get characterIntro => '给对话模拟换个场景：应用角色卡会替换系统提示词，并按顺序铺上预制问答。';

  @override
  String get characterDefault => '默认场景';

  @override
  String get characterDefaultDesc => '通用助手（You are a helpful assistant）';

  @override
  String characterPresetCount(int count) {
    return '$count 条预制对话';
  }

  @override
  String characterApplied(String name) {
    return '已应用角色：$name';
  }

  @override
  String get characterResetDone => '已回到默认场景';

  @override
  String get characterCreate => '创建角色';

  @override
  String get characterNewTitle => '新建角色';

  @override
  String get characterEditTitle => '编辑角色';

  @override
  String get characterNameLabel => '角色名';

  @override
  String get characterNameHint => '例如：希儿';

  @override
  String get characterPromptLabel => '人设提示词';

  @override
  String get characterPromptHint => '会作为 system 提示词发给模型：写清楚身份、语气与习惯';

  @override
  String get characterPresetsLabel => '预制对话';

  @override
  String get characterPresetsHint => '应用后按顺序铺进对话，让开场就带着上下文';

  @override
  String get characterPresetUser => '用户';

  @override
  String get characterPresetAssistant => '助手';

  @override
  String get characterAddPreset => '添加一组问答';

  @override
  String get characterBuiltin => '内置';

  @override
  String characterDeleteConfirm(String name) {
    return '删除角色「$name」？';
  }

  @override
  String get characterNeedName => '先给角色起个名字';

  @override
  String get characterActions => '更多操作';

  @override
  String get profileViewJson => '查看 JSON';

  @override
  String get profileJsonTitle => '组的 JSON';

  @override
  String get profileJsonBuiltin => '这一组由代码生成，下面是它当前的有效内容。';

  @override
  String get profileJsonCopy => '复制';

  @override
  String get profileJsonExport => '导出文件';

  @override
  String get profileJsonCopied => '已复制 JSON';

  @override
  String profileJsonExported(String path) {
    return '已导出到 $path';
  }

  @override
  String profileJsonExportFailed(String error) {
    return '导出失败：$error';
  }

  @override
  String get fabAdd => '添加';

  @override
  String get moreAction => '更多操作';

  @override
  String get profileSourceBuiltin => '内置';

  @override
  String get profileSourceUrl => '订阅';

  @override
  String get profileSourceFile => '文件';

  @override
  String get profileSourceInline => '粘贴';

  @override
  String get profileUpdateAvailable => '有更新';

  @override
  String get profileCustomizedTag => '已手动改过';

  @override
  String get profileLanesAction => '查看车道';

  @override
  String get profileUpdateAction => '立即更新';

  @override
  String get profileDeleteAction => '删除档案';

  @override
  String profileDeleteConfirm(String name) {
    return '删除「$name」？它装进来的上游会一并摘掉。';
  }

  @override
  String profileDeleted(String name) {
    return '已删除「$name」';
  }

  @override
  String profileStats(int upstreams, int lanes) {
    return '$upstreams 个上游 · $lanes 条车道';
  }

  @override
  String get profileNeverUpdated => '尚未更新';

  @override
  String profileLastUpdated(String time) {
    return '上次更新 $time';
  }

  @override
  String get profilePullHint => '下拉刷新可用模型列表';

  @override
  String get profileIdConflict => '上游 id 已被占用，这份档案没有装入';

  @override
  String get profileBuiltinZenSummary =>
      '免登录接入 OpenCode Zen 的免费模型车道；对外名 zen-free 自带顺序回退。';

  @override
  String get profileImportTitle => '添加配置文件';

  @override
  String get profileImportTabUrl => '订阅地址';

  @override
  String get profileImportTabFile => '本地文件';

  @override
  String get profileImportTabPaste => '粘贴 JSON';

  @override
  String get profileImportUrlHint => 'https://example.com/profile.json';

  @override
  String get profileImportPickFile => '选择 JSON 文件';

  @override
  String get profileImportPasteHint => '把档案 JSON 粘到这里';

  @override
  String get profileImportNote => '档案只描述模型从哪来，不会改监听端口、密钥和访问规则。';

  @override
  String get profileImportSubmit => '导入';

  @override
  String profileImported(String name) {
    return '已导入「$name」';
  }

  @override
  String get profileFormatEmpty => '内容是空的';

  @override
  String get profileFormatNotJson => '不是合法 JSON（Clash 订阅是 YAML，这里不吃）';

  @override
  String get profileFormatNotObject => '顶层得是一个 JSON 对象';

  @override
  String get profileFormatUnsupportedSchema => '档案格式版本不支持';

  @override
  String get profileFormatMissingId => '档案缺 id（也没写 name 可以推）';

  @override
  String get profileFormatNoUpstreams => '档案里一个上游都没有';

  @override
  String get profileFormatDuplicateId => '已经有一份同 id 的档案了';

  @override
  String get laneHintNotInstalled => '这份档案还没启用，先在发现页点一下卡片装上它。';

  @override
  String laneFallbackHint(String name) {
    return '客户端把 model 填成 $name 即可走容灾。';
  }

  @override
  String get uiStyleLabel => '界面风格';

  @override
  String get uiStyleNote => '切换后整个应用改用另一套页面实现';

  @override
  String get uiStyleMaterial => 'Material 3 Expressive';

  @override
  String get uiStyleMiuix => '小米 HyperOS';

  @override
  String get miuixPullToRefresh => '下拉刷新';

  @override
  String get miuixReleaseToRefresh => '松开立即刷新';

  @override
  String get miuixRefreshing => '正在刷新…';

  @override
  String get miuixRefreshDone => '刷新完成';

  @override
  String get navBarStyleLabel => '底部导航栏';

  @override
  String get navBarStyleNote => '液态玻璃走原生渲染，普通档用系统导航栏';

  @override
  String get navBarStyleGlass => '液态玻璃';

  @override
  String get navBarStylePlain => '普通';

  @override
  String get displayIosPushTransitionCorner => '转场圆角';

  @override
  String get displayIosPushTransitionCornerAuto => '跟随设备屏幕圆角';

  @override
  String get displayIosPushTransitionCornerUnsupported =>
      '当前设备读不到屏幕圆角，改用下面这个手动值';

  @override
  String get edgeHapticLabel => '滑动触感反馈';

  @override
  String get edgeHapticNote => '快速滑动到顶部/底部时轻震一下';

  @override
  String get shortcutStartService => '启动服务';

  @override
  String get shortcutStopService => '关闭服务';

  @override
  String get shortcutTokenStats => '查看 Token 用量';

  @override
  String get tasksDialogTitle => '任务';

  @override
  String get taskPauseServer => '暂停服务';

  @override
  String taskListenOn(String address) {
    return '监听 $address';
  }

  @override
  String get taskStopListening => '停止监听';

  @override
  String get tasksRecentSection => '最近';

  @override
  String tasksModelCount(int count) {
    return '$count 个模型';
  }

  @override
  String get createConfigScanTitle => '扫描二维码';

  @override
  String get createConfigScanDesc => '扫码或从相册识别来添加配置';

  @override
  String get qrScannerTitle => '扫描二维码';

  @override
  String get qrScannerHint => '对准屏幕任意位置，识别到二维码自动跳转';

  @override
  String get qrScannerPermissionTitle => '需要相机权限';

  @override
  String get qrScannerPermissionDesc => '扫码需要使用相机，请在系统设置中允许本应用访问相机。';

  @override
  String get qrScannerOpenSettings => '去设置';

  @override
  String get qrScannerRetry => '重试';

  @override
  String get qrScannerUnsupported => '当前平台不支持扫码，请在 Android / iOS 设备上使用';

  @override
  String get qrScannerSwitchCamera => '切换前后摄像头';

  @override
  String get qrScannerGallery => '从相册识别';

  @override
  String get qrScannerGalleryEmpty => '图片里没有识别到二维码';

  @override
  String get qrResultTitle => '扫码结果';

  @override
  String get qrResultKindProfile => '配置档案 JSON';

  @override
  String get qrResultKindUpstream => '上游 JSON';

  @override
  String get qrResultKindUrl => '网页链接';

  @override
  String get qrResultKindText => '纯文本';

  @override
  String get qrResultImportProfile => '导入配置文件';

  @override
  String get qrResultAddUpstream => '添加为上游';

  @override
  String get qrResultImportUrl => '导入订阅';

  @override
  String qrResultUpstreamAdded(String name) {
    return '已添加上游「$name」';
  }

  @override
  String get upstreamQrTitle => '上游二维码';

  @override
  String get upstreamQrHint => '用另一台装了本应用的设备扫一扫，即可把这个上游导入到它的规则里。';

  @override
  String get upstreamQrTooLong => '内容过长，生成不了二维码';

  @override
  String get progressiveTopBarTitle => '渐变模糊顶栏';

  @override
  String get progressiveTopBarDesc => '顶栏透明化，顶部渐进模糊随内容滚入淡入';

  @override
  String get navBarStyleFloating => '悬浮';

  @override
  String get biometricLockTitle => '生物识别锁';

  @override
  String get biometricLockDesc => '打开应用时需要验证指纹 / 人脸（Android）';

  @override
  String get biometricLockUnavailable => '此设备没有可用的生物识别或屏幕锁凭据';

  @override
  String get biometricGateTitle => 'Local2API 已锁定';

  @override
  String get biometricGateHint => '验证生物识别以继续';

  @override
  String get biometricUnlock => '解锁';

  @override
  String get networkTitle => '网络';

  @override
  String get networkEntryDesc => 'Cloudflare Tunnel / Tailscale';

  @override
  String get cfTitle => 'Cloudflare Tunnel';

  @override
  String get cfDesc => '通过 trycloudflare 临时隧道，把本服务公开到互联网';

  @override
  String get cfEnableSwitch => '启用 trycloudflare';

  @override
  String get cfTermsTitle => 'Cloudflare 许可协议';

  @override
  String get cfTermsAgree => '同意并启用';

  @override
  String get cfTermsDecline => '不同意';

  @override
  String get cfTermsFetchFailed => '许可协议拉取失败，请检查网络后重试';

  @override
  String get cfTermsNote => '启用前需要同意 Cloudflare 的服务条款（trycloudflare.com）。';

  @override
  String get cfStarting => '正在启动隧道…';

  @override
  String get cfRunning => '隧道运行中';

  @override
  String get cfStopped => '未运行';

  @override
  String get cfPublicUrl => '公开地址';

  @override
  String get cfBinaryMissing =>
      '没有找到 cloudflared。内建隧道目前只在桌面端可用（PATH 里装好 cloudflared 后重试）。';

  @override
  String get cfRetry => '重试';

  @override
  String get cfStop => '停止';

  @override
  String get tsTitle => 'Tailscale';

  @override
  String get tsDesc => '在 Tailscale 网络内访问本服务（100.64.0.0/10 网段）';

  @override
  String get tsAllowSwitch => '放行 Tailscale 网段';

  @override
  String tsDetected(String ip) {
    return '检测到 Tailscale IP：$ip';
  }

  @override
  String get tsNotDetected => '未检测到 Tailscale 接口（本机没装或没连）';

  @override
  String get tsDownloadTitle => '获取 Tailscale';

  @override
  String get tsDownloadDesc => '在手机 / 电脑上安装 Tailscale，随时随地访问本服务';

  @override
  String get tsOpenDownload => '打开下载页';

  @override
  String get securitySection => '安全';

  @override
  String get webUiTitle => '临时 WebUI';

  @override
  String get webUiDesc => '和 API 转发分开的端口，用来临时在浏览器里试模型';

  @override
  String get webUiEnable => '启用临时 WebUI';

  @override
  String get webUiToggleHint => '关掉就停掉网页服务，不影响 API 转发';

  @override
  String get webUiPort => 'WebUI 端口';

  @override
  String get webUiHost => 'WebUI 监听地址';

  @override
  String get webUiRunning => '网页已启动';

  @override
  String get webUiStopped => '网页未启动';

  @override
  String get webUiFailed => '网页启动失败';

  @override
  String get webUiOpen => '在浏览器打开';

  @override
  String get webUiCopyUrl => '复制地址';

  @override
  String get webUiEntryDesc => '端口、开关、浏览器入口';

  @override
  String get webUiNote => '页面上的请求仍然打 API 端口，两个端口互不干扰';

  @override
  String get scheduleTitle => '峰谷时段';

  @override
  String get scheduleEntryDesc => '按星期和时间段限制模型 / 模型组';

  @override
  String get scheduleDesc => '正向：只有选中的时间段能用。反向：选中的时间段禁用。对话模拟不受影响。';

  @override
  String get scheduleEmpty => '还没有策略：不加就是全天可用';

  @override
  String get scheduleAdd => '添加策略';

  @override
  String get scheduleTarget => '作用对象';

  @override
  String get scheduleTargetModel => '单个模型';

  @override
  String get scheduleTargetGroup => '模型组';

  @override
  String get scheduleModel => '模型';

  @override
  String get scheduleGroup => '模型组';

  @override
  String get scheduleMode => '策略方向';

  @override
  String get scheduleModeAllow => '正向（选中时段才能用）';

  @override
  String get scheduleModeDeny => '反向（选中时段禁止用）';

  @override
  String get scheduleWeekdays => '星期';

  @override
  String get scheduleSelectAll => '全选';

  @override
  String get scheduleUpstreamHint => '只作用于这个上游的模型；全选就等于给整个上游套窗口。改动即时生效，不用点保存。';

  @override
  String get scheduleUpstreamNoModel => '这个上游还没有对外模型，先在「对外模型」里加几个。';

  @override
  String get schedulePickWeekday => '选择星期';

  @override
  String get scheduleHours => '时间段';

  @override
  String scheduleHourRange(String start, String end) {
    return '$start:00 - $end:00';
  }

  @override
  String get scheduleEnabled => '启用这条策略';

  @override
  String get scheduleDelete => '删除策略';

  @override
  String get scheduleSaved => '策略已保存';

  @override
  String get scheduleDeleted => '策略已删除';

  @override
  String get scheduleSimNote => '对话模拟永远可用，不受这些策略限制';

  @override
  String get schedulePickTarget => '选一个模型或模型组';

  @override
  String get schedulePickHour => '选择小时';

  @override
  String get scheduleStartHour => '起始';

  @override
  String get scheduleEndHour => '结束';

  @override
  String get scheduleAllDay => '全天';

  @override
  String scheduleStatus(String count) {
    return '$count 条策略';
  }

  @override
  String get modelContextLabel => '最大上下文数';

  @override
  String get modelContextHelper => '对外声明给客户端的上下文 token 数；留空按默认 1M，拉取模型列表时也会自动补';

  @override
  String modelContextShort(String value) {
    return '上下文 $value';
  }

  @override
  String contextAutoFilled(String count) {
    return '已从上游获取 $count 个模型的上下文长度';
  }

  @override
  String get modelOutputLabel => '最大输出数';

  @override
  String get modelOutputHelper => '对外声明的最大输出 token 数；留空不声明';

  @override
  String contextRingInfo(String percent, String used, String total) {
    return '上下文占用 $percent%（$used / $total tokens）';
  }

  @override
  String get contextRingEstimated => '，按字数估算';

  @override
  String get contextRingTap => '点击查看上下文详情';

  @override
  String get contextDetailTitle => '上下文占用';

  @override
  String contextDetailPercent(String percent) {
    return '占上下文 $percent%';
  }

  @override
  String contextDetailUsed(String used, String total) {
    return '$used / $total tokens';
  }

  @override
  String get contextDetailFromUsage => '取自上一轮响应的 usage（精确值）';

  @override
  String get contextDetailEstimated => '按字数与图片粗估（上游没回 usage）';

  @override
  String contextDetailOutput(String limit) {
    return '最大输出 $limit tokens';
  }

  @override
  String get contextDetailOutputNone => '最大输出未声明';

  @override
  String contextDetailModel(String model) {
    return '请求模型 $model';
  }

  @override
  String contextDetailMessages(String count, String images) {
    return '$count 条消息 · $images 张图片';
  }

  @override
  String get contextDetailClose => '知道了';

  @override
  String get chatSimSendImages => '发送图片';

  @override
  String get chatSimSendTextOnly => '仅发文字';

  @override
  String get chatSimSendImagesTip =>
      '图片会作为多模态内容一起发给模型；纯文本车道报错时切到「仅发文字」，图就只留在界面上。';

  @override
  String get chatSimImagesOn => '图片会随消息发出';

  @override
  String get chatSimImagesOff => '图片只在本地展示，不发给模型';

  @override
  String get chatSimAttachCamera => '拍照';

  @override
  String chatSimAttachFailed(String error) {
    return '读取附件失败：$error';
  }

  @override
  String get chatSimVoiceNoPermission => '没有麦克风权限，无法语音输入';

  @override
  String get chatSimVoiceOpenSettings => '去设置';

  @override
  String chatSimVoiceFailed(String error) {
    return '语音输入失败：$error';
  }

  @override
  String get voiceHoldToTalk => '按住说话';

  @override
  String get voiceReleaseToSend => '松开结束';

  @override
  String get voiceListeningHint => '正在聆听…';

  @override
  String get voiceRecognizing => '识别中…';

  @override
  String get voiceNothingHeard => '没听清，再按住说一次';

  @override
  String chatSimCallPeer(String name) {
    return '和 $name 通话';
  }

  @override
  String get chatSimMsgMenuTitle => '消息操作';

  @override
  String get chatSimMsgSpeak => '朗读';

  @override
  String get chatSimMsgStopSpeak => '停止朗读';

  @override
  String get chatSimMsgRegenerate => '重新回答';

  @override
  String get chatSimMsgDownload => '下载音频';

  @override
  String get chatSimDownloadTitle => '下载音频';

  @override
  String get chatSimDownloadFormat => '格式';

  @override
  String get chatSimDownloadMp3Desc => '通用音频，兼容性最好';

  @override
  String get chatSimDownloadSilkDesc => 'SILK v3，微信 / QQ 的语音格式';

  @override
  String get chatSimDownloadSlkDesc => '与 SILK 字节相同，只是扩展名不同';

  @override
  String get chatSimDownloadTencent => '腾讯兼容（-tencent）';

  @override
  String get chatSimDownloadTencentDesc => '文件头加 0x02、结尾不写哨兵包，微信 / QQ 才认';

  @override
  String get chatSimDownloadAction => '下载';

  @override
  String get chatSimDownloadBusy => '正在合成音频…';

  @override
  String get chatSimDownloadCanceled => '已取消保存';

  @override
  String chatSimDownloadSaved(String path) {
    return '已保存：$path';
  }

  @override
  String chatSimDownloadFailed(String error) {
    return '导出失败：$error';
  }

  @override
  String get balanceTitle => '余额';

  @override
  String get balanceEntryDesc => '查询这个上游的账户余额';

  @override
  String get balancePullHint => '下拉刷新余额';

  @override
  String get balanceRefreshing => '查询中…';

  @override
  String get balanceNoKey => '先填密钥再查余额';

  @override
  String get balanceUnsupported => '该上游不支持余额查询';

  @override
  String get balanceNoData => '没有返回余额';

  @override
  String get balanceAvailableLabel => '可用余额';

  @override
  String get balanceGrantedLabel => '赠送余额';

  @override
  String get balanceToppedUpLabel => '充值余额';

  @override
  String get balanceUsedLabel => '已用额度';

  @override
  String get balanceRequestsLabel => '累计请求';

  @override
  String get balanceGroupLabel => '分组';

  @override
  String get balanceSourceLabel => '查询接口';

  @override
  String get balanceStatusOk => '账号可正常调用';

  @override
  String get balanceStatusBad => '账号不可用（欠费或受限）';

  @override
  String get balanceQuotaNote => '按 1 美元 = 500000 额度换算';

  @override
  String balanceFailed(String error) {
    return '查询失败：$error';
  }

  @override
  String balanceUpdatedAt(String time) {
    return '上次更新 $time';
  }

  @override
  String get balanceDetailsTitle => '余额明细';

  @override
  String get balanceLimitLabel => '额度上限';

  @override
  String get balanceUnauthorized => '密钥无效或无权读取账户';

  @override
  String get balanceBadResponse => '余额接口返回的内容读不懂';

  @override
  String get balanceNoKeyHint => '填好密钥后再刷新';

  @override
  String get balanceUnauthorizedHint => '确认密钥有效，且允许读取账户信息';

  @override
  String get balanceUnsupportedHint => '不是所有上游都有余额接口';

  @override
  String get balanceNetworkHint => '检查本机能否访问该地址，稍后重试';

  @override
  String get thinkingDefaultLabel => '默认思考档位';

  @override
  String get thinkingDefaultOff => '不干预';

  @override
  String get thinkingLevelLow => '精简';

  @override
  String get thinkingLevelMedium => '均衡';

  @override
  String get thinkingLevelHigh => '深思';

  @override
  String get thinkingWireLabel => '档位下发格式';

  @override
  String get thinkingWireBudget => '只压输出预算';

  @override
  String get thinkingWireEffort => 'reasoning_effort';

  @override
  String get thinkingWireThinking => 'thinking 开关';

  @override
  String get thinkingWireBoth => '两者都发';

  @override
  String get logsFilterAll => '全部';

  @override
  String get logsFilterPassed => '通过';

  @override
  String get logsFilterFailed => '失败';

  @override
  String get logsEmptyFiltered => '当前筛选下没有请求';

  @override
  String get activeConnectionsTitle => '活跃连接';

  @override
  String get activeConnectionsEmpty => '当前没有活跃连接';

  @override
  String get activeConnDuration => '已持续';

  @override
  String get activeConnStarted => '开始于';

  @override
  String get activeConnPath => '路径';

  @override
  String get tsOpenApp => '打开 Tailscale';

  @override
  String get tsInstalledDesc => '已安装 Tailscale，点一下打开客户端';

  @override
  String get tsOpenFailed => '没能打开 Tailscale，已改为打开下载页';

  @override
  String get usageCalendarBackToday => '返回今天';

  @override
  String get thinkingLevelNone => '关闭思考';

  @override
  String get thinkingLevelMinimal => '极轻';

  @override
  String get thinkingLevelXhigh => '极深';

  @override
  String get thinkingLevelMax => '最重';

  @override
  String get winCloseSection => '桌面窗口';

  @override
  String get winCloseBehaviorTitle => '关闭按钮行为';

  @override
  String get winCloseAsk => '每次询问';

  @override
  String get winCloseTray => '收进托盘';

  @override
  String get winCloseExit => '退出程序';

  @override
  String get winCloseAskSummary => '每次都问一句（可以勾选「下次也是这样」）';

  @override
  String get winCloseTraySummary => '窗口收进托盘，转发服务继续跑';

  @override
  String get winCloseExitSummary => '程序整体退出，服务随之停止';

  @override
  String get winCloseDialogTitle => 'Local2API';

  @override
  String get winCloseDialogHeading => '您点击了关闭按钮，您希望？';

  @override
  String get winCloseDialogContent => '收进托盘后程序在后台继续转发，可以从托盘图标随时叫回来。';

  @override
  String get winCloseLinkTray => '收进托盘';

  @override
  String get winCloseLinkTraySubtitle => '窗口藏起来，服务照常运行';

  @override
  String get winCloseLinkExit => '退出程序';

  @override
  String get winCloseLinkExitSubtitle => '连转发服务一起停掉';

  @override
  String get winCloseRemember => '下次也是这样';

  @override
  String get winTrayShow => '显示主窗口';

  @override
  String get winTrayQuit => '退出 Local2API';

  @override
  String get thinkingWireHint => '上游不认这一档时会自动逐级下调（max → xhigh → … → 不下发）';

  @override
  String get typeAnthropic => 'Anthropic Messages';

  @override
  String get trayHintBody => '嘿嘿，我在这里哦';

  @override
  String get trayHintDismiss => '不再提示';

  @override
  String get trayHintSettings => '设置';

  @override
  String get winTrayHintTitle => '收进托盘时显示提示';

  @override
  String get winTrayHintSummary => '弹一条系统通知：「嘿嘿，我在这里哦」，带「不再提示 / 设置」两个按钮';

  @override
  String get settingsLabTitle => '实验室';

  @override
  String get settingsLabDesc => '把 SillyTavern 装到本地、内置浏览器等实验功能';

  @override
  String get labTitle => '实验室';

  @override
  String get labSubtitle => '本地服务与实验性功能';

  @override
  String get labLocalServices => '本地服务';

  @override
  String get labSillyTavernDesc => '本地 AI 角色扮演前端（Node.js），装好后在应用内打开';

  @override
  String get labInstall => '安装';

  @override
  String get labInstalled => '已安装';

  @override
  String get labNotInstalled => '未安装';

  @override
  String get labRunning => '运行中';

  @override
  String get labStart => '启动';

  @override
  String get labStop => '停止';

  @override
  String get labOpen => '打开';

  @override
  String get labOpenFolder => '打开目录';

  @override
  String get labUninstall => '卸载';

  @override
  String get labUninstallTitle => '卸载 SillyTavern？';

  @override
  String get labUninstallBody => '会删除已下载的程序文件（含 data 目录里的角色卡与聊天记录），且不可恢复。';

  @override
  String get labInstallLocation => '安装位置';

  @override
  String get labChooseLocation => '选择位置';

  @override
  String get labDefaultLocation => '默认位置';

  @override
  String get labNodeStatus => 'Node.js';

  @override
  String get labNodeMissing => '未检测到 Node.js';

  @override
  String get labNodeMissingHint => '装好 Node.js 18+ 后点「重新检测」即可启动；文件可以先装着。';

  @override
  String get labNodeDownload => '下载 Node.js';

  @override
  String get labRecheck => '重新检测';

  @override
  String get labInstallDeps => '安装依赖';

  @override
  String get labMobileNoRun =>
      '移动端不能直接运行 Node.js 服务；文件已装到应用目录，可用 Termux 等环境运行。';

  @override
  String get labNodeRuntimeTitle => 'Node.js 运行时';

  @override
  String get labNodeRuntimeDesc =>
      '从 Termux 软件源安装 Android 版 Node.js（含 npm），实验室的本地服务在本机运行必备。';

  @override
  String get labNodeRuntimeInstall => '安装 Node.js';

  @override
  String get labNodeRuntimeReinstall => '重新安装';

  @override
  String get labNodeRuntimeRemove => '卸载 Node.js';

  @override
  String get labNodeRuntimeNotInstalled => '未安装';

  @override
  String get labNodeRunnerMode => '运行模式';

  @override
  String get labRunnerDirect => '直接运行';

  @override
  String get labRunnerDirectDesc => '以应用身份启动进程（debug 构建可用；release 会被系统拦截）';

  @override
  String get labRunnerShizuku => 'Shizuku';

  @override
  String get labRunnerShizukuDesc =>
      '经 Shizuku 以 shell 身份启动进程（release 推荐，需安装并授权 Shizuku）';

  @override
  String get labNodeMirror => '下载镜像';

  @override
  String get labMirrorOfficial => '官方源';

  @override
  String get labMirrorOfficialDesc =>
      'packages.termux.dev · registry.npmjs.org（境内直连很慢，适合已有代理的网络）';

  @override
  String get labMirrorCn => '中国大陆镜像';

  @override
  String get labMirrorCnDesc => '清华 TUNA termux 源 · npmmirror（境内直连快，实测数 MB/s）';

  @override
  String get labShizukuStatus => 'Shizuku 状态';

  @override
  String get labShizukuNotDetected => '未检测到 Shizuku（未安装或未启动）';

  @override
  String get labShizukuGranted => '已授权';

  @override
  String get labShizukuNotGranted => '未授权';

  @override
  String get labShizukuRequest => '授权 Shizuku';

  @override
  String get labExecBlocked => '系统禁止应用直接执行 Node，请切换到 Shizuku 模式';

  @override
  String get labVisibleDesc => '手动开启后，这里才会显示实验室入口';

  @override
  String get labOpenLab => '进入实验室';

  @override
  String get labDownloading => '下载中';

  @override
  String get labExtracting => '解压中';

  @override
  String get labInstallingDeps => '安装依赖中';

  @override
  String get labStarting => '启动中';

  @override
  String get labLogs => '日志';

  @override
  String get labClearLogs => '清空';

  @override
  String get labVersion => '版本';

  @override
  String get labPhaseIdle => '就绪';

  @override
  String get labBrowserTools => '内置工具';

  @override
  String get labBrowserTitle => '内置浏览器';

  @override
  String get labBrowserDesc => '在应用内打开本地 WebUI、SillyTavern 或任意网址';

  @override
  String get labOpenBrowser => '打开浏览器';

  @override
  String get labManualUrl => '输入网址，例如 127.0.0.1:8000';

  @override
  String get labGo => '前往';

  @override
  String get labError => '出错了';

  @override
  String get labCancel => '取消';

  @override
  String get browserTitle => '浏览器';

  @override
  String get browserEditUrl => '编辑地址';

  @override
  String get browserUrlHint => 'https://example.com';

  @override
  String get browserGo => '前往';

  @override
  String get browserBack => '后退';

  @override
  String get browserForward => '前进';

  @override
  String get browserReload => '刷新';

  @override
  String get browserStop => '停止';

  @override
  String get browserMenu => '更多';

  @override
  String get browserCopyLink => '复制链接';

  @override
  String get browserCopyCookie => '复制 Cookie';

  @override
  String get browserCookieEmpty => '当前页面没有可复制的 Cookie';

  @override
  String get browserCookieCopied => 'Cookie 已复制';

  @override
  String get browserUaLabel => '浏览器标识';

  @override
  String get browserUaAuto => '自动';

  @override
  String get browserUaDesktop => '电脑端';

  @override
  String get browserUaMobile => '手机端';

  @override
  String get browserOpenExternal => '在系统浏览器打开';

  @override
  String browserInitFailed(String error) {
    return '网页加载失败：$error';
  }

  @override
  String get browserUnsupported => '当前平台不支持内置浏览器，请用系统浏览器打开';

  @override
  String get browserRetry => '重试';

  @override
  String get commonBack => '返回';

  @override
  String get close => '关闭';

  @override
  String get labMoreSettings => '更多设置';

  @override
  String get labInstallFirstTitle => '还没有安装 SillyTavern';

  @override
  String get labInstallFirstBody => '先在「更多设置」里装好，再回来打开这个开关。';

  @override
  String get labGoSettings => '去设置';

  @override
  String get labStartFailed => '启动失败';

  @override
  String get labStopped => '已停止';

  @override
  String get labSectionStatus => '运行状态';

  @override
  String get labSectionInstall => '安装';

  @override
  String get labApiConfig => 'API 配置';

  @override
  String get labApiGroup => '模型组';

  @override
  String get labApiGroupNone => '未选择';

  @override
  String get labApiModel => '模型';

  @override
  String get labApiBaseUrl => '接口地址';

  @override
  String get labApiKey => 'API Key';

  @override
  String get labApiNoKey => '还没有启用的 API Key（先去「密钥」页建一个）';

  @override
  String get labApiWrite => '写入 SillyTavern';

  @override
  String get labApiWriteOk => '已写入，刷新 SillyTavern 页面即生效';

  @override
  String labApiWriteFailed(String error) {
    return '写入失败：$error';
  }

  @override
  String get labApiNeedGroup => '先在「发现」页启用一个模型组';

  @override
  String get labApiNeedService => '没连上本机服务，先在仪表盘启动服务';

  @override
  String get labApiNoUserData => 'SillyTavern 还没启动过，先启动一次再写入';

  @override
  String get labApiPickGroup => '选择模型组';

  @override
  String get labApiPickModel => '选择模型';

  @override
  String labApiModelCount(String count) {
    return '$count 个模型';
  }

  @override
  String get labLogsEmpty => '还没有日志';

  @override
  String get labCopyLogs => '复制日志';

  @override
  String get labLogsCopied => '日志已复制';

  @override
  String get browserClosePage => '关闭页面';

  @override
  String get browserShareQr => '分享二维码';

  @override
  String get browserQrTitle => '扫码在手机上打开';

  @override
  String get browserViewCookies => '查看 Cookie';

  @override
  String get browserCopyAll => '全部复制';

  @override
  String get browserClipboardAccess => '允许网页写剪贴板';

  @override
  String get browserClipboardAllowed => '已允许剪贴板访问';

  @override
  String get browserClipboardBlocked => '已阻止剪贴板访问';

  @override
  String get browserSetUa => '自定义浏览器标识';

  @override
  String get browserUaEmptyHint => '留空恢复默认；改完会刷新页面';

  @override
  String get browserApplyAndReload => '应用并刷新';

  @override
  String get browserUaUpdated => '浏览器标识已更新';

  @override
  String get browserTroubleshootNetwork => '网络疑难解答';

  @override
  String get browserTroubleshootFailed => '打不开系统疑难解答';

  @override
  String get browserAndroidErrorTitle => '系统 WebView 挂了';

  @override
  String get browserAndroidErrorCause => '可能原因';

  @override
  String get browserAndroidErrorDetail => '系统 WebView 版本过旧或被禁用，内置浏览器起不来。';

  @override
  String get browserUpdateWebview => '更新 Android System WebView';

  @override
  String get browserOpenDevOptions => '查看 WebView 实现（开发者选项）';

  @override
  String get browserAppleErrorTitle => '内置浏览器无法启动';

  @override
  String get browserAppleErrorReport => '错误报告';

  @override
  String get browserAppleErrorDetail => 'WKWebView 初始化失败，通常是系统版本过低或受企业策略限制。';

  @override
  String get browserBsodMessage => '你的内置浏览器遇到了问题，需要重新启动。';

  @override
  String get browserBsodNoRestart => '我们只收集某些错误信息，然后为你重新启动。';

  @override
  String get browserBsodComplete => '0% 完成';

  @override
  String get browserBsodSolutions => '可以试试这些：';

  @override
  String get browserBsodDownload => '下载 Microsoft Edge WebView2 Runtime';

  @override
  String get browserBsodWinUpdate => '打开 Windows 更新';

  @override
  String get browserBsodScanQr => '手机扫码打开 WebView2 下载页';

  @override
  String get browserBsodStopCode => '停止代码：WEBVIEW2_NOT_INSTALLED';

  @override
  String get labStatus => '状态';

  @override
  String get browserUaHint => '粘贴或输入完整的 UA 字符串';

  @override
  String get labApiStopFirst => '先停止 SillyTavern 再写入（运行中的配置会被它自己覆盖）';

  @override
  String get labAutoOpenBrowser => '启动后自动打开浏览器';

  @override
  String get labAutoOpenBrowserDesc => '关掉后 SillyTavern 不再自己拉起系统浏览器；用「打开」手动进入';

  @override
  String get labDshTitle => 'DeepSeek Harness';

  @override
  String get labDshInstallFirstTitle => '还没有安装 DeepSeek Harness';

  @override
  String get labDshInstallFirstBody => '先在「更多设置」里装好，再回来打开这个开关。';

  @override
  String get labDshUninstallTitle => '卸载 DeepSeek Harness？';

  @override
  String get labDshUninstallBody => '会删除 npm 安装的 dsh 程序文件，模型配置与聊天记录保留在 ~/.dsh。';

  @override
  String get labDshPickModels => '选择要加入 dsh 的模型';

  @override
  String get labDshDefaultModel => '默认模型';

  @override
  String get labDshPickDefault => '选择默认模型';

  @override
  String get labDshWrite => '写入 dsh 配置';

  @override
  String get labDshWriteOk => '已写入 dsh 配置';

  @override
  String get labDshNeedModels => '先选模型组并勾选至少一个模型';

  @override
  String get labDshWriteHint => '写入后 dsh 的模型列表会热加载；正在运行时应用会自动重启它，让新密钥生效';

  @override
  String get labDshConfigPath => '配置文件';

  @override
  String get labDshOpenInApp => '应用内打开';

  @override
  String get labDshCompat => 'Android 兼容层';

  @override
  String get labDshCompatDesc => '关掉安卓上起不来的沙箱与 pwsh';

  @override
  String get browserSelectTitle => '选择';

  @override
  String get browserOpenCustomTab => '用 Custom Tabs 打开';

  @override
  String get browserCustomTabPick => '用哪个浏览器打开';

  @override
  String get browserCustomTabAuto => '自动（系统默认）';

  @override
  String get browserCustomTabNone => '没装支持 Custom Tabs 的浏览器';

  @override
  String get browserCustomTabFailed => '打不开这个链接';

  @override
  String get reply => '回复';

  @override
  String get labNotifySection => '通知';

  @override
  String get labNotifyPermission => '通知权限';

  @override
  String get labNotifyPermissionDesc => '任务进度、提问与结果都走通知';

  @override
  String get labNotifyLiveUpdate => '实时更新';

  @override
  String get labNotifyLiveUpdateDesc => 'Android 16+ 把任务进度置顶在通知栏、锁屏与状态栏';

  @override
  String get labNotifyPromoted => '系统已放行实时更新';

  @override
  String get labNotifyNotPromoted => '当前不会升级为实时更新';

  @override
  String get labNotifyBattery => '忽略电池优化';

  @override
  String get labNotifyBatteryDesc => '让 node / dsh 能在后台长时间跑';

  @override
  String get labNotifyBatteryIgnored => '已忽略电池优化';

  @override
  String get labNotifyOpenSettings => '系统通知设置';

  @override
  String get labNotifyTest => '发一条测试通知';

  @override
  String get labNotifyTestSent => '测试通知已发出';

  @override
  String get labNotifyTestFailed => '通知没发出去（检查权限）';

  @override
  String get labDshTaskHint => '任务提示词';

  @override
  String get labDshTaskHintDesc => '让模型按步骤汇报进度、需要拍板时停下来问你';

  @override
  String get labDshPlugins => '插件';

  @override
  String get labDshPluginMessageEdit => '编辑消息';

  @override
  String get labDshPluginMessageEditDesc =>
      '在用户消息旁加铅笔按钮，改完可从上一轮分叉重发（dsh-message-edit）';

  @override
  String get labDshPluginComputerUse => '电脑操作模式';

  @override
  String get labDshPluginComputerUseDesc =>
      '截屏 + 鼠标键盘控制，新任务可选「电脑操作模式」（dsh-computer-use-mode）';

  @override
  String get labDshPluginAndroid => '手机操作';

  @override
  String get labDshPluginAndroidDesc =>
      '手机操作：截屏、点按、滑动、UI 树、OCR、logcat（@zseven-w/dsh-android）';

  @override
  String get labDshPluginInstalling => '正在安装…';

  @override
  String get labDshPluginFailed => '插件操作失败';

  @override
  String get labDshPluginRestartHint => '开关后会自动重启 DSH 让插件生效';

  @override
  String get labDshRunTask => '运行任务';

  @override
  String get labDshRunTaskDesc => '把一句话交给 dsh 跑，进度与结果走通知';

  @override
  String get labDshTaskPrompt => '要 dsh 做什么？';

  @override
  String get labDshTaskBusy => '已经有一个任务在跑';

  @override
  String get labDshTaskStarted => '任务已开始，进度看通知';

  @override
  String get labDshTaskDone => '任务完成';

  @override
  String get labDshTaskFailed => '任务失败';

  @override
  String get labDshTaskCancelled => '任务已取消';

  @override
  String labDshTaskSteps(String done, String total) {
    return '$done/$total 步';
  }

  @override
  String get labDshAgentDone => 'agent 已完成此轮操作';

  @override
  String get labDshNeedAnswer => 'dsh 在等你回答';

  @override
  String get labDshAnswerHint => '打开 dsh web 回答';

  @override
  String get labDshToastReplyHint => '输入回答';

  @override
  String get labDshToastOptionsHint => '输入 1-3 选择，其他内容作为自定义回答';

  @override
  String get labDshToastSkip => '跳过';

  @override
  String get autoRefreshTitle => '自动更新模型';

  @override
  String get autoRefreshOff => '关闭';

  @override
  String get autoRefreshEvery1d => '每天';

  @override
  String get autoRefreshEvery3d => '每 3 天';

  @override
  String get autoRefreshEvery7d => '每 7 天';

  @override
  String get autoRefreshEvery30d => '每 30 天';

  @override
  String get autoRefreshDesc => '按设定的间隔去上游拉一次模型清单，新上的补进来、下架的删掉';

  @override
  String get autoRefreshNever => '还没刷新过';

  @override
  String get autoRefreshJustNow => '刚刚刷新过';

  @override
  String autoRefreshNextIn(String when) {
    return '下次 $when';
  }

  @override
  String get autoRefreshRefreshing => '正在刷新…';

  @override
  String autoRefreshDone(String added, String removed) {
    return '模型列表已更新：新增 $added 个，移除 $removed 个';
  }

  @override
  String get autoRefreshNoChange => '模型列表已是最新';

  @override
  String get autoRefreshRefreshNow => '立即刷新';

  @override
  String get autoRefreshFailed => '刷新失败';

  @override
  String get pluginManagerTitle => 'dsh 插件';

  @override
  String get pluginManagerRefresh => '重新扫描';

  @override
  String get pluginManagerSubtitle => '安装、开关与卸载 dsh 插件';

  @override
  String get pluginManagerSearch => '搜索插件';

  @override
  String get pluginManagerInstall => '安装';

  @override
  String get pluginManagerInstallTitle => '安装第三方插件';

  @override
  String get pluginManagerPackageHint => 'npm 包名，如 @scope/dsh-plugin-xxx';

  @override
  String get pluginManagerPackageEmpty => '请先填包名';

  @override
  String get pluginManagerInstalling => '安装中…';

  @override
  String get pluginManagerUninstall => '卸载';

  @override
  String pluginManagerUninstallConfirm(String name) {
    return '卸载 $name？这个包会从 dsh 里移除。';
  }

  @override
  String pluginManagerExitConfirm(String name) {
    return '停用 $name？已下载的包会保留，下次启用不用重装。';
  }

  @override
  String get pluginManagerRestartHint => '插件改动在 dsh 重启后生效';

  @override
  String get pluginManagerDescTitle => '第三方插件';

  @override
  String get pluginManagerEmpty => '还没装过插件';

  @override
  String get pluginManagerNotReady => 'dsh 还没装好，先装 dsh 再来管插件';

  @override
  String pluginManagerInstalledCount(String count) {
    return '$count 个已启用';
  }

  @override
  String get pluginManagerInstalledBadge => '已安装';

  @override
  String get pluginManagerCustom => '第三方';

  @override
  String get pluginManagerOfficial => '内置';

  @override
  String get pluginManagerLocal => '本地目录';

  @override
  String get pluginManagerAddLocal => '从本地目录安装';

  @override
  String get pluginManagerNoMatch => '没有匹配的插件';

  @override
  String get pluginManagerSearchClear => '清除搜索';

  @override
  String get pluginManagerExpand => '展开';

  @override
  String get pluginManagerCollapse => '收起';

  @override
  String pluginManagerOnlyOn(String platform) {
    return '仅支持 $platform';
  }

  @override
  String get pluginManagerNotInstalled => '未安装';

  @override
  String get pluginManagerDisabled => '未启用';

  @override
  String get pluginManagerEnabledState => '已启用';

  @override
  String pluginManagerOverview(String enabled, String total) {
    return '$enabled 个已启用 · 共 $total 个';
  }

  @override
  String get usageApiKeyFilter => 'API Key';

  @override
  String get usageAllApiKeys => '全部';

  @override
  String get usageModelFilter => '模型';

  @override
  String get usageAllModelsShort => '全部模型';

  @override
  String get usageRequestsShort => '请求';

  @override
  String get usageByModel => '各模型用量';

  @override
  String get usageModelCalls => 'API 请求次数';

  @override
  String get usageNoModelCalls => '这段时间没有调用记录';

  @override
  String get usageChartByModel => '按模型';

  @override
  String get usageChartByKey => '按 API Key';

  @override
  String get usageKeyName => '密钥';

  @override
  String get usageKeyAnonymous => '未鉴权调用';

  @override
  String get usageTotalRow => '合计';

  @override
  String get usageCallsUnit => '次';
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class AppLocalizationsZhTw extends AppLocalizationsZh {
  AppLocalizationsZhTw() : super('zh_TW');

  @override
  String get appTitle => 'Local2API';

  @override
  String get navServer => '服務';

  @override
  String get navModels => '模型';

  @override
  String get navKeys => '金鑰';

  @override
  String get navSettings => '設定';

  @override
  String get serverTitle => '服務';

  @override
  String get serverRunning => '執行中';

  @override
  String get serverStopped => '已停止';

  @override
  String get serverStarting => '啟動中…';

  @override
  String get homeStatusDescRunning => '服務已啟動，用戶端可以直接呼叫了';

  @override
  String get homeStatusDescStopped => '服務未啟動，點一下卡片啟動';

  @override
  String get homeStatusDescStarting => '正在啟動服務…';

  @override
  String get homeStatusDescError => '啟動失敗，點一下卡片重試';

  @override
  String get startServer => '啟動服務';

  @override
  String get stopServer => '停止服務';

  @override
  String get restartServer => '重新啟動服務';

  @override
  String get endpointTitle => '接入位址';

  @override
  String get listenAddress => '監聽位址';

  @override
  String get listenPort => '監聽連接埠';

  @override
  String get copy => '複製';

  @override
  String get copied => '已複製';

  @override
  String get allInterfaces => '所有網卡 (0.0.0.0)';

  @override
  String get loopbackOnly => '僅本機 (127.0.0.1)';

  @override
  String get lanIpsLabel => '區網/VPN 位址';

  @override
  String get statsTitle => '請求統計';

  @override
  String get statTotalRequests => '累計請求';

  @override
  String get statErrors => '失敗';

  @override
  String get statActive => '活躍連線';

  @override
  String get recentLogs => '最近請求';

  @override
  String get viewAll => '查看全部';

  @override
  String get noLogsYet => '暫無請求日誌';

  @override
  String get noKeysWarningTitle => '未設定金鑰';

  @override
  String get noKeysWarningBody => '任何用戶端都可以直接呼叫此服務，建議在儀表盤「金鑰」分區新增至少一個金鑰。';

  @override
  String get noCidrWarningTitle => '對所有來源開放';

  @override
  String get noCidrWarningBody => '未設定任何 IP 規則，所有網段均可存取。';

  @override
  String get serverErrorTitle => '服務異常';

  @override
  String portInUse(String port) {
    return '連接埠 $port 被佔用';
  }

  @override
  String get autoStart => '啟動時自動開啟服務';

  @override
  String get modelsTitle => '模型';

  @override
  String get upstreams => '上游服務';

  @override
  String get addUpstream => '新增上游';

  @override
  String get noUpstreams => '還沒有上游，先新增一個';

  @override
  String get upstreamTypeLabel => '類型';

  @override
  String get typeOpenai => 'OpenAI 相容';

  @override
  String get typeLlamacpp => 'llama.cpp';

  @override
  String get typeOllama => 'Ollama';

  @override
  String get typeLocalTts => '本地 TTS (Qwen3)';

  @override
  String get modalityLabel => '模態';

  @override
  String get modalityChat => '對話 (chat)';

  @override
  String get modalityAudio => '語音 (audio)';

  @override
  String get modalityAudioHint =>
      '開啟後 /v1/audio/speech 會把 OpenAI TTS 請求翻譯成該上游的 chat.completions 語音請求（MiMo TTS 等），再把回包音訊解給客戶端';

  @override
  String get localTtsSectionTitle => '本地 TTS（Qwen3-TTS）';

  @override
  String get ttsSettingsTitle => 'TTS settings';

  @override
  String get ttsSettingsDesc => 'Local model, provider and preview';

  @override
  String get ttsAutoPlayTitle => 'Auto-play TTS';

  @override
  String localTtsModelSize(String size) {
    return '共約 $size GB';
  }

  @override
  String get localTtsStateInstalled => '已安裝';

  @override
  String get localTtsStatePartial => '未下完（可續傳）';

  @override
  String get localTtsStateNotInstalled => '未下載';

  @override
  String get localTtsDownload => '下載模型';

  @override
  String localTtsDownloadProgress(String received, String total) {
    return '下載中 $received/$total MB';
  }

  @override
  String get localTtsDeleteConfirm => '刪除本地 TTS 模型檔案？';

  @override
  String get localTtsDevicePreference => '推理後端';

  @override
  String get ttsDeviceAuto => '自動（高通優先 NPU）';

  @override
  String get ttsDeviceNpu => 'NPU (Hexagon)';

  @override
  String get ttsDeviceGpu => 'GPU (Vulkan)';

  @override
  String get ttsDeviceCpu => 'CPU';

  @override
  String get localTtsTestSpeak => '試聽';

  @override
  String get localTtsTestStop => '停止';

  @override
  String get localTtsStatusPreparing => '正在載入模型…';

  @override
  String get localTtsStatusSynthesizing => '正在合成語音…';

  @override
  String get localTtsStatusPlaying => '播放中';

  @override
  String get localTtsStatusIdle => '空閒';

  @override
  String get localTtsStatusError => '出錯';

  @override
  String get localTtsNotReady => '模型未下載或下載不完整';

  @override
  String get localTtsServeHint =>
      '下載完成後，點下方「建立本地 TTS 上游」一鍵配置；客戶端透過 /v1/audio/speech 調用（模型名 qwen3-tts）';

  @override
  String get localTtsUpstreamName => '本地 TTS';

  @override
  String get localTtsCreateUpstream => '建立本地 TTS 上游';

  @override
  String get localTtsCreateUpstreamDesc =>
      '自動在模型頁添加「本地 TTS」上游（模型 qwen3-tts），客戶端即可調 /v1/audio/speech';

  @override
  String get localTtsUpstreamCreated => '已建立「本地 TTS」上游';

  @override
  String get localTtsUpstreamExists => '已存在「本地 TTS」上游';

  @override
  String get settingsFeaturesSection => '服務與功能';

  @override
  String get networkSettingsTitle => '網路設定';

  @override
  String get networkSettingsDesc => '連接埠與監聽、臨時 WebUI、IP 存取規則';

  @override
  String get chatSettingsTitle => '對話設定';

  @override
  String get chatSettingsDesc => 'TTS settings, auto-play and character cards';

  @override
  String get ipRulesEmpty => '暫無規則，預設放行所有來源';

  @override
  String ipRulesCount(String count) {
    return '$count 條規則';
  }

  @override
  String ruleDeletedCount(String count) {
    return '已刪除 $count 條規則';
  }

  @override
  String ruleRestored(String count) {
    return '已復原 $count 條規則';
  }

  @override
  String get characterEntryDesc => '管理對話模擬的角色卡與預設場景';

  @override
  String get ttsProviderLabel => '預設 TTS 服務商';

  @override
  String get ttsProviderOff => '關閉';

  @override
  String get ttsProviderLocal => '本地 Qwen3-TTS';

  @override
  String get ttsProviderNoneHint => '還沒有能發聲的模型：給語音上游加個模型，或先下載本地模型';

  @override
  String get ttsDesignModelLabel => '預設語音設計模型';

  @override
  String get ttsDesignModelDesc => '角色卡沒配音色樣本時用它合成，提示詞即音色描述';

  @override
  String get ttsDesignPromptLabel => '音色設計提示詞';

  @override
  String get ttsDesignPromptDesc => '設計模型的音色描述（user 訊息），留空用預設';

  @override
  String get ttsCloneModelLabel => '預設克隆模型';

  @override
  String get ttsCloneModelDesc => '角色卡配了音色樣本時用它克隆合成';

  @override
  String get ttsDesignPromptDefault => '預設';

  @override
  String get ttsPlaygroundTitle => 'TTS 測試台';

  @override
  String get ttsPlaygroundDesc => '換樣本 / 文字反覆試聽，排查克隆與設計效果';

  @override
  String get ttsPlaygroundHint =>
      '選模型、配音色樣本、輸入文字後播放。克隆不像時優先換樣本：一段乾淨的單人聲（5–10 秒、無背景音樂、無混響）比長音訊效果好得多。';

  @override
  String get ttsPlaygroundModel => '模型';

  @override
  String get ttsPlaygroundText => '合成文字';

  @override
  String get ttsPlaygroundInstructions => '風格指令 / 音色描述（可選）';

  @override
  String get ttsPlaygroundPlay => '播放';

  @override
  String get ttsPlaygroundEmptyText => '先輸入要合成的文字';

  @override
  String get ttsPlaygroundCloneNeedsSample => '克隆模型需要音色樣本：先在上方配一段音訊';

  @override
  String get ttsSpeak => '朗讀';

  @override
  String get characterVoiceLabel => '音色樣本';

  @override
  String get characterVoiceHint =>
      '選一段清晰人聲（wav/mp3，≤7MB）用於克隆音色。推薦配雲端克隆（快，幾秒出聲）；本地克隆要等 1.4GB 模型載入，首次可能要幾分鐘。';

  @override
  String get characterVoicePick => '選擇音訊';

  @override
  String get characterVoiceRemove => '移除';

  @override
  String get characterVoiceTooBig => '音訊樣本太大，請壓縮到 7MB 以內';

  @override
  String get characterVoiceBadType => '僅支援 wav / mp3 音訊';

  @override
  String get characterOverrideReset => '已恢復內建原文';

  @override
  String get upstreamNameLabel => '名稱';

  @override
  String get baseUrlLabel => '介面位址 (Base URL)';

  @override
  String get baseUrlHint => 'http://192.168.1.10:11434/v1';

  @override
  String get upstreamKeyLabel => '上游金鑰（可選）';

  @override
  String get upstreamNoteLabel => '備註';

  @override
  String get upstreamNoteHint => '這個上游是幹什麼的、有什麼注意事項（可留空）';

  @override
  String get upstreamJsonTitle => '上游 JSON';

  @override
  String get fetchModelsBtn => '擷取模型';

  @override
  String get testBtn => '測試';

  @override
  String get testOk => '連線成功';

  @override
  String testFailed(String error) {
    return '連線失敗：$error';
  }

  @override
  String fetchFailed(String error) {
    return '擷取失敗：$error';
  }

  @override
  String fetchedModels(String count) {
    return '取得 $count 個模型';
  }

  @override
  String get saveBtn => '儲存';

  @override
  String get deleteBtn => '刪除';

  @override
  String deleteUpstreamConfirm(String name) {
    return '刪除上游「$name」？';
  }

  @override
  String get cancel => '取消';

  @override
  String get confirm => '确定';

  @override
  String get exposedModelsTitle => '對外模型';

  @override
  String get noExposedModels => '沒有對外暴露的模型';

  @override
  String get modelAliasLabel => '對外名稱';

  @override
  String get modelTargetLabel => '上游模型';

  @override
  String get enabledLabel => '啟用';

  @override
  String get exposedLabel => '暴露';

  @override
  String get baseUrlInvalid => '位址無效，需要 http(s):// 開頭';

  @override
  String get fetchingModels => '正在擷取模型…';

  @override
  String get testing => '正在測試…';

  @override
  String get editUpstream => '編輯上游';

  @override
  String get newUpstream => '新建上游';

  @override
  String get upstreamNameRequired => '名稱不能為空';

  @override
  String modelCountLabel(String count) {
    return '$count 個模型';
  }

  @override
  String get upstreamEditHint => '一個上游就是一個 OpenAI 相容端點，改完點右上角儲存。';

  @override
  String get upstreamModeLabel => '模式';

  @override
  String get pickModeTitle => '選擇模式';

  @override
  String get notFilled => '未填寫';

  @override
  String get testConnectionTitle => '測試連線';

  @override
  String get testConnectionDesc => '用目前位址與金鑰試一次';

  @override
  String get addModelBtn => '新增模型';

  @override
  String get modelsPageHint => '點右上角下載圖示從上游拉取模型，再勾選要暴露的；加號可以手動填一個。';

  @override
  String get modelsSortTitle => '排序方式';

  @override
  String get modelsSortNatural => '預設順序';

  @override
  String get modelsSortAlphabet => '首字母正序';

  @override
  String get keysTitle => '金鑰';

  @override
  String get addKey => '新增金鑰';

  @override
  String get keyNameLabel => '備註';

  @override
  String get keyNameHint => '例如：我的手機';

  @override
  String get keyValueLabel => '金鑰';

  @override
  String get generate => '隨機產生';

  @override
  String get noKeysHint => '尚無金鑰，任何用戶端都能直接呼叫';

  @override
  String deleteKeyConfirm(String name) {
    return '刪除金鑰「$name」？';
  }

  @override
  String get keyExists => '該金鑰已存在';

  @override
  String get keyRequired => '金鑰不能為空';

  @override
  String get settingsTitle => '設定';

  @override
  String get networkSection => '網路與存取';

  @override
  String get accessRules => 'IP 存取規則';

  @override
  String get accessRuleDesc => '按順序比對，先命中先生效；為空則全部放行';

  @override
  String get addRule => '新增規則';

  @override
  String get ruleAllow => '放行';

  @override
  String get ruleDeny => '拒絕';

  @override
  String get cidrHint => '例如 192.168.0.0/16';

  @override
  String get cidrInvalid => 'CIDR 格式不正確';

  @override
  String get corsToggle => '允許跨域（CORS）';

  @override
  String get corsDesc => '允許網頁前端直接呼叫本服務';

  @override
  String get autoStartToggle => '啟動時自動執行服務';

  @override
  String get appearanceSection => '外觀';

  @override
  String get themeLabel => '主題';

  @override
  String get themeSystem => '跟隨系統';

  @override
  String get themeLight => '淺色';

  @override
  String get themeDark => '深色';

  @override
  String get languageLabel => '語言';

  @override
  String get languageSystem => '跟隨系統';

  @override
  String get languageNote => 'Android 13+ 可在系統「應用程式語言」中設定';

  @override
  String get aboutSection => '關於';

  @override
  String get aboutDesc =>
      '將區網/VPN 內的 llama.cpp、Ollama 或任意 OpenAI 相容介面，轉發為帶驗證與模型白名單的一層新 API。';

  @override
  String get versionLabel => '版本';

  @override
  String get aboutEntryDesc => '版本、元件與效果背景';

  @override
  String get aboutTapLogoHint => '點一點上面的圖示試試';

  @override
  String get aboutOpenLicenses => '開源授權';

  @override
  String get ossTitle => '開源授權';

  @override
  String get ossSearchHint => '搜尋依賴套件或授權標識';

  @override
  String get ossClearSearch => '清除搜尋';

  @override
  String ossPackagesCount(String count, String licenses) {
    return '共 $count 個依賴套件 · $licenses 份授權';
  }

  @override
  String ossLicensesCount(String count) {
    return '$count 份授權';
  }

  @override
  String get ossEmptySearch => '沒有符合的依賴套件';

  @override
  String get ossLoadFailed => '授權清單載入失敗';

  @override
  String get ossRetry => '重試';

  @override
  String get ossLoading => '正在收集授權清單…';

  @override
  String get ossCopyFullText => '複製全部授權';

  @override
  String get ossLicenseCopied => '已複製到剪貼簿';

  @override
  String ossLicenseIndex(String index, String count) {
    return '第 $index / $count 份';
  }

  @override
  String get aboutComponents => '建構元件';

  @override
  String get aboutComponentsDesc => 'Flutter · flutter_miuix（HyperOS 風格）';

  @override
  String get textureSetTitle => '紋理集';

  @override
  String get textureSetEffectVariant => '效果變體';

  @override
  String get textureSetOs2 => 'OS2';

  @override
  String get textureSetOs3 => 'OS3';

  @override
  String get textureSetEffectBg => '效果背景';

  @override
  String get textureSetDynamicBg => '動態背景';

  @override
  String get textureSetBlurEnable => '模糊';

  @override
  String get textureSetBlurRadius => '模糊半徑';

  @override
  String get textureSetNoise => '噪點';

  @override
  String get textureSetBrightness => '亮度';

  @override
  String get textureSetContrast => '對比';

  @override
  String get textureSetSaturation => '飽和度';

  @override
  String get textureSetBlendMode => '混合模式';

  @override
  String get textureSetReset => '恢復預設';

  @override
  String get blendModeDefault => '預設';

  @override
  String get blendModeOverlay => '疊加';

  @override
  String get blendModeScreen => '濾色';

  @override
  String get blendModeMultiply => '色彩增值';

  @override
  String get blendModePlusLighter => '加亮';

  @override
  String get blendModePlusDarker => '加深';

  @override
  String get blendModeLinearLight => '線性光';

  @override
  String get blendModeDifference => '差值';

  @override
  String get unsavedChangesTitle => '未儲存的變更';

  @override
  String get unsavedChangesMessage => '你對這個上游的修改還沒有儲存，要現在儲存嗎？';

  @override
  String get unsavedSave => '儲存';

  @override
  String get unsavedDiscard => '不儲存';

  @override
  String get chatSimModelPicker => '模擬模型';

  @override
  String get chatSimModelAll => '全部（整組共享）';

  @override
  String get chatSimModelAllDesc => '組內任意模型被呼叫都帶上這段上下文';

  @override
  String get chatSimModelSpecificDesc => '僅此模型帶上這段上下文';

  @override
  String get editMenuUndo => '復原(U)';

  @override
  String get editMenuCut => '剪下(T)';

  @override
  String get editMenuCopy => '複製(C)';

  @override
  String get editMenuPaste => '貼上(P)';

  @override
  String get editMenuDelete => '刪除(D)';

  @override
  String get editMenuSelectAll => '全選(A)';

  @override
  String get portRangeInvalid => '連接埠範圍 1024-65535';

  @override
  String get logsTitle => '請求日誌';

  @override
  String get clearLogs => '清空';

  @override
  String get logsCleared => '已清空';

  @override
  String get stopServerConfirm => '停止服務？';

  @override
  String get clientLabel => '用戶端';

  @override
  String get modelLabel => '模型';

  @override
  String get statusLabel => '狀態';

  @override
  String get durationLabel => '耗時';

  @override
  String get colorAmber => '琥珀色';

  @override
  String get colorBlue => '藍色';

  @override
  String get colorBlueGrey => '藍灰色';

  @override
  String get colorBrown => '棕色';

  @override
  String get colorCyan => '青色';

  @override
  String get colorDeepPurple => '深紫色';

  @override
  String get colorDefaultGreen => '預設綠';

  @override
  String get colorGreen => '綠色';

  @override
  String get colorGrey => '灰色';

  @override
  String get colorIndigo => '靛藍色';

  @override
  String get colorLightBlue => '淺藍色';

  @override
  String get colorLightGreen => '淺綠色';

  @override
  String get colorLime => '酸橙色';

  @override
  String get colorOrange => '橙色';

  @override
  String get colorPink => '粉紅色';

  @override
  String get colorPurple => '紫色';

  @override
  String get colorRed => '紅色';

  @override
  String get colorTeal => '藍綠色';

  @override
  String get colorYellow => '黃色';

  @override
  String get commonBackTooltip => '向上瀏覽';

  @override
  String get commonCancel => '取消';

  @override
  String get commonCreate => '建立';

  @override
  String get commonDelete => '刪除';

  @override
  String get commonSave => '儲存';

  @override
  String get displayFollowSystemColor => '跟隨系統配色';

  @override
  String get displayFontWeight => '文字粗細';

  @override
  String get displayOff => '已關閉';

  @override
  String get displayPureBlack => '純黑深色模式';

  @override
  String get displayPureBlackOn => '深色模式（已黑化）';

  @override
  String get displayScaleCompact => '緊湊模式 · 顯示更多內容';

  @override
  String get displayScaleCompactBig => '緊湊 · 適合大螢幕';

  @override
  String get displayScaleDefault => '預設';

  @override
  String get displayScaleFineTune => '精細調整';

  @override
  String get displayScaleHuge => '超大 · 輔助功能';

  @override
  String get displayModeTitle => '螢幕更新率';

  @override
  String get displayModeAuto => '自動';

  @override
  String get displayModeSystemTag => '[系統]';

  @override
  String get displayModeHint => '沒有生效？重新啟動應用程式試試';

  @override
  String get displayModeUnsupported => '目前平台不支援設定螢幕更新率（僅 Android）';

  @override
  String get displayModeLoading => '正在取得螢幕更新率...';

  @override
  String get displayModeEmpty => '未取得可用的螢幕更新率';

  @override
  String get displayScaleLarge => '略大 · 更容易閱讀';

  @override
  String get displayScaleLargeFont => '大字體 · 無障礙友善';

  @override
  String get displayScaleLargeFontShort => '大字體 · 無障礙';

  @override
  String get displayScaleMin => '最小 · 資訊密度最高';

  @override
  String get displayScaleNote =>
      '縮放比例會全域套用於文字與部分版面尺寸。設為 100% 可恢復預設。修改立即生效，無需重新啟動。';

  @override
  String get displayScalePresets => '快捷預設';

  @override
  String get displayScaleReset => '重設為 100%';

  @override
  String get displayScaleSmall => '略小 · 適合大螢幕';

  @override
  String get displayScaleSystemDefault => '系統預設';

  @override
  String get displayScaleTitle => '顯示縮放';

  @override
  String get displaySectionAppearance => '外觀';

  @override
  String get displaySectionPersonalize => '個人化';

  @override
  String get displaySeedAmber => '琥珀色';

  @override
  String get displaySeedBlue => '藍色';

  @override
  String get displaySeedBlueGrey => '藍灰色';

  @override
  String get displaySeedBrown => '棕色';

  @override
  String get displaySeedCustom => '自訂';

  @override
  String get displaySeedCyan => '青色';

  @override
  String get displaySeedDeepPurple => '深紫色';

  @override
  String get displaySeedDefaultGreen => '預設綠';

  @override
  String get displaySeedGreen => '綠色';

  @override
  String get displaySeedGrey => '灰色';

  @override
  String get displaySeedIndigo => '靛藍色';

  @override
  String get displaySeedLightBlue => '淺藍色';

  @override
  String get displaySeedLightGreen => '淺綠色';

  @override
  String get displaySeedLime => '酸橙色';

  @override
  String get displaySeedOrange => '橙色';

  @override
  String get displaySeedPink => '粉紅色';

  @override
  String get displaySeedPurple => '紫色';

  @override
  String get displaySeedRed => '紅色';

  @override
  String get displaySeedTeal => '藍綠色';

  @override
  String get displaySeedYellow => '黃色';

  @override
  String get displaySettingsTitle => '顯示';

  @override
  String get displayThemeColor => '主題配色';

  @override
  String get displayThemeDark => '深色';

  @override
  String get displayThemeLight => '淺色';

  @override
  String get displayThemeMode => '主題模式';

  @override
  String displayWeightBlack(int weight) {
    return '極粗 ($weight)';
  }

  @override
  String displayWeightBold(int weight) {
    return '粗 ($weight)';
  }

  @override
  String displayWeightCustom(int weight) {
    return '自訂 ($weight)';
  }

  @override
  String displayWeightLight(int weight) {
    return '細 ($weight)';
  }

  @override
  String displayWeightMedium(int weight) {
    return '中等 ($weight)';
  }

  @override
  String displayWeightRegular(int weight) {
    return '標準 ($weight)';
  }

  @override
  String displayWeightThin(int weight) {
    return '極細 ($weight)';
  }

  @override
  String get drawerSystemMode => '跟隨系統';

  @override
  String get fontWeightBlack => '極粗';

  @override
  String get fontWeightBold => '粗';

  @override
  String get fontWeightLight => '細';

  @override
  String get fontWeightMedium => '中等';

  @override
  String get fontWeightRegular => '標準';

  @override
  String get fontWeightSampleText =>
      'The quick brown fox jumps over the lazy dog.\n敏捷的棕色狐狸跳過懶惰的狗。';

  @override
  String get fontWeightSaveApply => '儲存並套用';

  @override
  String get fontWeightUnsavedTitle => '有未儲存的調整';

  @override
  String fontWeightUnsavedBody(int weight) {
    return '文字粗細改成了 $weight，還沒確認。';
  }

  @override
  String get fontWeightUnsavedSave => '儲存';

  @override
  String get fontWeightUnsavedDiscard => '不儲存';

  @override
  String get fontWeightThin => '極細';

  @override
  String get playlistMenuMore => '更多操作';

  @override
  String get searchPureBlack => '純黑深色模式';

  @override
  String get searchThemeMode => '主題模式';

  @override
  String get startScreenGoBack => '向上瀏覽';

  @override
  String get themeAppearance => '外觀';

  @override
  String themeColorCopied(String hex) {
    return '已複製色號: $hex';
  }

  @override
  String get themeColorExtracted => '已從圖片提取主題色';

  @override
  String themeColorFailed(String error) {
    return '取色失敗: $error';
  }

  @override
  String get themeColorsSection => '配色';

  @override
  String get themeCopyColor => '複製色號';

  @override
  String get themeCreateTitle => '建立自訂主題';

  @override
  String themeCreated(String name) {
    return '主題「$name」已建立並儲存';
  }

  @override
  String get themeDarkBlackened => '深色模式（已黑化）';

  @override
  String themeDeleteConfirm(String name) {
    return '確定要刪除自訂主題「$name」嗎？';
  }

  @override
  String get themeDeleteTitle => '刪除主題';

  @override
  String themeDeleted(String name) {
    return '已刪除「$name」';
  }

  @override
  String get themeDropHint => '放開以從圖片提取主題色';

  @override
  String get themeEnabled => '已啟用';

  @override
  String get themeFollowSystem => '跟隨系統配色';

  @override
  String get themeHexHint => '例如 #FF0000 或 255,0,0';

  @override
  String get themeHexLabel => '十六進位/RGB';

  @override
  String get themeImageOnly => '僅支援圖片格式';

  @override
  String get themeNameHint => '請輸入文字';

  @override
  String get themeNameLabel => '主題名稱';

  @override
  String get themeNewTheme => '新增主題';

  @override
  String get themeOff => '已關閉';

  @override
  String get themePaletteStyle => '調色板風格';

  @override
  String get themePickColor => '選擇顏色';

  @override
  String get settingsBlurTitle => '啟用模糊';

  @override
  String get settingsBlurDesc => '為應用啟用模糊效果';

  @override
  String get settingsCustomColorsTitle => '自定義顏色';

  @override
  String get settingsCustomColorsDesc => '在 Miuix 主題風格下自定義主題顏色';

  @override
  String get themeCustomColorsNeeded => '需要啟用自定義顏色';

  @override
  String get themePickFromImage => '從圖片取色';

  @override
  String themeSwitched(String name) {
    return '已切換至 $name 主題';
  }

  @override
  String get themeTitle => '主題';

  @override
  String get settingsDisplaySection => '外觀';

  @override
  String get settingsDisplayEntry => '顯示設定';

  @override
  String get drawerDarkMode => '深色模式';

  @override
  String get drawerLightMode => '淺色模式';

  @override
  String get sideBarCollapse => '收起侧边栏';

  @override
  String get sideBarExpand => '展开侧边栏';

  @override
  String get navDiscover => '發現';

  @override
  String get laneProbing => '探測中…';

  @override
  String get laneUsable => '可用';

  @override
  String get laneRestricted => '僅限官方用戶端';

  @override
  String get laneThrottled => '額度已達上限';

  @override
  String get laneRegionBlocked => '出口地區受限';

  @override
  String get laneUnavailable => '模型目前無法使用';

  @override
  String get laneFailed => '不可用';

  @override
  String get laneNetUnreachable => '連不上端點';

  @override
  String get navDashboard => '儀表盤';

  @override
  String get dashboardTitle => '儀表盤';

  @override
  String get fabRefresh => '重新整理';

  @override
  String get fabAppearance => '外觀';

  @override
  String get appearancePanelTitle => '外觀快速設定';

  @override
  String get fabDelayTest => '測試連線';

  @override
  String get laneUntested => '尚未測試';

  @override
  String get laneHintRoute => '點選一條車道作為鏈首，其餘依序自動回退。';

  @override
  String get discoverTitle => '發現';

  @override
  String get discoverIntro => '這裡列出全部上游：開關管啟用/停用，閃電測速，點卡片改設定；下拉刷新可用模型清單。';

  @override
  String get fabNewUpstream => '新建上游';

  @override
  String get createConfigTitle => '新增設定';

  @override
  String get createConfigFileTitle => '檔案';

  @override
  String get createConfigFileDesc => '從檔案、訂閱連結或貼上 JSON 匯入';

  @override
  String get createConfigUpstreamDesc => '手動建立一組上游設定';

  @override
  String get profileNewUpstreamTitle => '新建上游';

  @override
  String get profileGroupNameLabel => '名稱';

  @override
  String get profileGroupNameHint => '給這個模型組起個名字（留空就用檔案自帶的）';

  @override
  String get profileGroupDescLabel => '說明';

  @override
  String get profileGroupDescHint => '這一組是什麼、從哪來（可留空）';

  @override
  String get profileSpeedTest => '測速';

  @override
  String get profileRefreshModels => '刷新可用模型';

  @override
  String get profileLanesDynamic => '模型清單隨上游變動';

  @override
  String profileModelsRefreshed(int count) {
    return '已刷新 $count 個組的可用模型';
  }

  @override
  String get profileModelsRefreshFailed => '一個組都沒刷出來，看看網路或端點地址';

  @override
  String keyDeletedCount(int count) {
    return '已刪除 $count 個密鑰';
  }

  @override
  String get keyRestore => '復原';

  @override
  String keyRestored(int count) {
    return '已復原 $count 個密鑰';
  }

  @override
  String get keysManage => '管理密鑰';

  @override
  String get keysIntro => '密鑰是這一層的門禁：只有帶著密鑰的客戶端才允許呼叫。左滑一行可以刪除。';

  @override
  String get keysEmptyPage => '還沒有密鑰，點右下角加號新增一個。';

  @override
  String get usageTitle => 'Token 統計';

  @override
  String get usageIntro => '本機代理接住的每一次請求都在這裡記帳：輸入 / 輸出 / 快取命中，按模型與時間查。';

  @override
  String get usageAllModels => '全部模型';

  @override
  String get usageRangeToday => '今天';

  @override
  String get usageRange7 => '近 7 天';

  @override
  String get usageRange30 => '近 30 天';

  @override
  String get usageRangeAll => '全部';

  @override
  String get usageTotal => '合計';

  @override
  String get usageInput => '輸入';

  @override
  String get usageOutput => '輸出';

  @override
  String get usageCacheHit => '快取命中';

  @override
  String get usageCacheMiss => '快取未命中';

  @override
  String get usageHitRate => '命中率';

  @override
  String get usageRequests => '請求數';

  @override
  String get usageReasoning => '思考';

  @override
  String get usageByDay => '按天';

  @override
  String get usageRecent => '最近記錄';

  @override
  String get usageEmpty => '這段時間還沒有記錄，跑一輪模型後這裡就有數了。';

  @override
  String get usageNoUsageData => '上游未給用量';

  @override
  String get usageClear => '清空用量';

  @override
  String get usageClearConfirm => '清空全部 token 用量記錄？';

  @override
  String get usageCleared => '用量記錄已清空';

  @override
  String get usageOpen => '檢視 Token 統計';

  @override
  String get usageCalendar => '用量日曆';

  @override
  String get usageCalendarOpen => '日曆';

  @override
  String get usageCalendarIntro => '點日期看當天呼叫了哪些模型，點卡片就帶著那一天回到統計頁。';

  @override
  String get usageCalendarPrevMonth => '上個月';

  @override
  String get usageCalendarNextMonth => '下個月';

  @override
  String get usageCalendarEmptyDay => '這天沒有呼叫紀錄';

  @override
  String usageCalendarDayModels(String date) {
    return '$date 的活動';
  }

  @override
  String get chatSimTitle => '對話模擬';

  @override
  String get chatSimAutoSaved => '對話預設保存在本機（按模型組分開放），下次進來接著聊。';

  @override
  String get chatSimVoiceInput => '語音輸入';

  @override
  String get chatSimVoiceStop => '停止語音輸入';

  @override
  String get chatSimVoicePreparing => '離線語音模型準備中，稍等再試';

  @override
  String get chatSimVoiceUnavailable => '目前裝置不支援語音輸入';

  @override
  String get chatSimAttach => '新增附件';

  @override
  String get chatSimAttachImage => '圖片';

  @override
  String get chatSimAttachFile => '檔案';

  @override
  String get chatSimAttachUserOnly => '附件只能加在使用者訊息上';

  @override
  String get chatSimRemoved => '已刪除';

  @override
  String get chatSimIntro =>
      '把這裡的對話當成下游客戶端發的一條請求，走本機代理的真實鏈路（路由 / 回退 / 指紋 / 請求日誌）。前面的訊息會一起帶出去。圖片會隨訊息發給模型（純文字車道可切「僅發文字」），檔案只在介面上展示；長按訊息可直接刪除。';

  @override
  String get chatSimServerOff => '服務沒在運行，先啟動它再發。';

  @override
  String get chatSimStartServer => '啟動服務';

  @override
  String get chatSimNoModel => '這一組還沒有對外暴露的模型，先在發現頁啟用它。';

  @override
  String get chatSimSend => '發送';

  @override
  String get chatSimSendOnly => '僅發送';

  @override
  String get chatSimSendOnlyDesc => '只把請求發出去，不等模型回覆';

  @override
  String get chatSimSentOnly => '已發送（未等待回覆）';

  @override
  String get chatSimSendModeOnly => '傳送（模型不回應）';

  @override
  String get chatSimSendModeHint => '長按切換';

  @override
  String get chatSimSending => '生成中…';

  @override
  String get chatSimClear => '清空對話';

  @override
  String get chatSimClearConfirm => '清空這次對話？';

  @override
  String get chatSimMore => '更多';

  @override
  String get chatSimAvatarTitle => '頭像設定';

  @override
  String get chatSimAvatarUser => '使用者頭像';

  @override
  String get chatSimAvatarAssistant => '助手頭像';

  @override
  String get chatSimAvatarPick => '從相簿選擇';

  @override
  String get chatSimAvatarCamera => '拍照';

  @override
  String get chatSimAvatarReset => '恢復預設';

  @override
  String get chatSimAvatarUpdated => '頭像已更新';

  @override
  String chatSimAvatarFailed(String error) {
    return '頭像更新失敗：$error';
  }

  @override
  String get callTitleAction => '通話';

  @override
  String get callTitleVoice => '語音通話';

  @override
  String get callTitleVideo => '視訊通話';

  @override
  String get callStatusCalling => '正在接通…';

  @override
  String get callStatusEnded => '通話已結束';

  @override
  String get callRecords => '對話記錄';

  @override
  String get callStatusListening => '在聽…';

  @override
  String get callStatusThinking => '思考中…';

  @override
  String get callStatusSpeaking => '說話中…';

  @override
  String get callMic => '麥克風';

  @override
  String get callMicDone => '說完了';

  @override
  String get callInterrupt => '打斷';

  @override
  String get callVideoNeedOmni => '視訊通話需要 Omni 模型';

  @override
  String get callAsrUnavailable => '語音識別無法使用，檢查麥克風權限';

  @override
  String get callMute => '靜音';

  @override
  String get callUnmute => '取消靜音';

  @override
  String get callSpeakerOn => '擴音';

  @override
  String get callSpeakerOff => '關閉擴音';

  @override
  String get callSwitchToVideo => '切換到視訊通話';

  @override
  String get callSwitchToVoice => '切換到語音通話';

  @override
  String get callHangUp => '掛斷';

  @override
  String get callSettingsTitle => '通話設定';

  @override
  String get callSettingsOmniHint =>
      '當前模型不是 Omni 模型：基礎語音通話照常可用；「允許打斷」和「允許調用攝像頭」需要 Omni 模型。';

  @override
  String get callAllowInterrupt => '允許打斷';

  @override
  String get callAllowInterruptDesc => '模型說話時可以隨時插話（需要 Omni 模型）';

  @override
  String get callAllowCamera => '允許調用攝像頭';

  @override
  String get callAllowCameraDesc => '視訊通話時把攝像頭畫面傳送給模型（需要 Omni 模型）';

  @override
  String get callCameraBlocked => '已禁止調用攝像頭';

  @override
  String get callVideoStagePlaceholder => '攝像頭畫面 · 尚未接入';

  @override
  String get chatSimRegenerate => '重新生成';

  @override
  String get chatSimEditTitle => '編輯訊息';

  @override
  String get chatSimSave => '儲存';

  @override
  String get chatSimSaveAndSend => '儲存並發送';

  @override
  String get chatSimAddMessage => '新增訊息';

  @override
  String get chatSimRoleLabel => '角色';

  @override
  String get chatSimRoleSystem => '系統';

  @override
  String get chatSimRoleUser => '使用者';

  @override
  String get chatSimRoleAssistant => '助手';

  @override
  String get chatSimHintInput => '輸入一則訊息（預設以使用者身分發送）';

  @override
  String chatSimModelLabel(String model) {
    return '請求模型 $model';
  }

  @override
  String chatSimMeta(int words, String time) {
    return '字數 $words · 耗時 $time';
  }

  @override
  String chatSimServedModel(String model) {
    return '回應模型 $model';
  }

  @override
  String chatSimServedModelVia(String lane, String model) {
    return '回應模型 $lane（請求 $model）';
  }

  @override
  String get characterTitle => '角色卡';

  @override
  String get characterIntro => '給對話模擬換個場景：套用角色卡會替換系統提示詞，並按順序鋪上預製問答。';

  @override
  String get characterDefault => '預設場景';

  @override
  String get characterDefaultDesc => '通用助手（You are a helpful assistant）';

  @override
  String characterPresetCount(int count) {
    return '$count 條預製對話';
  }

  @override
  String characterApplied(String name) {
    return '已套用角色：$name';
  }

  @override
  String get characterResetDone => '已回到預設場景';

  @override
  String get characterCreate => '建立角色';

  @override
  String get characterNewTitle => '新建角色';

  @override
  String get characterEditTitle => '編輯角色';

  @override
  String get characterNameLabel => '角色名';

  @override
  String get characterNameHint => '例如：希兒';

  @override
  String get characterPromptLabel => '人設提示詞';

  @override
  String get characterPromptHint => '會作為 system 提示詞發給模型：寫清楚身份、語氣與習慣';

  @override
  String get characterPresetsLabel => '預製對話';

  @override
  String get characterPresetsHint => '套用後按順序鋪進對話，讓開場就帶著上下文';

  @override
  String get characterPresetUser => '使用者';

  @override
  String get characterPresetAssistant => '助手';

  @override
  String get characterAddPreset => '新增一組問答';

  @override
  String get characterBuiltin => '內建';

  @override
  String characterDeleteConfirm(String name) {
    return '刪除角色「$name」？';
  }

  @override
  String get characterNeedName => '先給角色起個名字';

  @override
  String get characterActions => '更多操作';

  @override
  String get profileViewJson => '檢視 JSON';

  @override
  String get profileJsonTitle => '組的 JSON';

  @override
  String get profileJsonBuiltin => '這一組由程式碼生成，下面是它目前的有效內容。';

  @override
  String get profileJsonCopy => '複製';

  @override
  String get profileJsonExport => '匯出檔案';

  @override
  String get profileJsonCopied => '已複製 JSON';

  @override
  String profileJsonExported(String path) {
    return '已匯出至 $path';
  }

  @override
  String profileJsonExportFailed(String error) {
    return '匯出失敗：$error';
  }

  @override
  String get fabAdd => '新增';

  @override
  String get moreAction => '更多操作';

  @override
  String get profileSourceBuiltin => '內建';

  @override
  String get profileSourceUrl => '訂閱';

  @override
  String get profileSourceFile => '檔案';

  @override
  String get profileSourceInline => '貼上';

  @override
  String get profileUpdateAvailable => '有更新';

  @override
  String get profileCustomizedTag => '已手動改過';

  @override
  String get profileLanesAction => '檢視車道';

  @override
  String get profileUpdateAction => '立即更新';

  @override
  String get profileDeleteAction => '刪除檔案';

  @override
  String profileDeleteConfirm(String name) {
    return '刪除「$name」？它裝進來的上游會一併摘掉。';
  }

  @override
  String profileDeleted(String name) {
    return '已刪除「$name」';
  }

  @override
  String profileStats(int upstreams, int lanes) {
    return '$upstreams 個上游 · $lanes 條車道';
  }

  @override
  String get profileNeverUpdated => '尚未更新';

  @override
  String profileLastUpdated(String time) {
    return '上次更新 $time';
  }

  @override
  String get profilePullHint => '下拉刷新可用模型清單';

  @override
  String get profileIdConflict => '上游 id 已被佔用，這份檔案沒有裝入';

  @override
  String get profileBuiltinZenSummary =>
      '免登入接入 OpenCode Zen 的免費模型車道；對外名 zen-free 自帶順序回退。';

  @override
  String get profileImportTitle => '新增設定檔';

  @override
  String get profileImportTabUrl => '訂閱網址';

  @override
  String get profileImportTabFile => '本機檔案';

  @override
  String get profileImportTabPaste => '貼上 JSON';

  @override
  String get profileImportUrlHint => 'https://example.com/profile.json';

  @override
  String get profileImportPickFile => '選擇 JSON 檔案';

  @override
  String get profileImportPasteHint => '把檔案 JSON 貼到這裡';

  @override
  String get profileImportNote => '檔案只描述模型從哪來，不會改監聽埠、金鑰和存取規則。';

  @override
  String get profileImportSubmit => '匯入';

  @override
  String profileImported(String name) {
    return '已匯入「$name」';
  }

  @override
  String get profileFormatEmpty => '內容是空的';

  @override
  String get profileFormatNotJson => '不是合法 JSON（Clash 訂閱是 YAML，這裡不吃）';

  @override
  String get profileFormatNotObject => '頂層得是一個 JSON 物件';

  @override
  String get profileFormatUnsupportedSchema => '檔案格式版本不支援';

  @override
  String get profileFormatMissingId => '檔案缺 id（也沒寫 name 可以推）';

  @override
  String get profileFormatNoUpstreams => '檔案裡一個上游都沒有';

  @override
  String get profileFormatDuplicateId => '已經有一份同 id 的檔案了';

  @override
  String get laneHintNotInstalled => '這份檔案還沒啟用，先在發現頁點一下卡片裝上它。';

  @override
  String laneFallbackHint(String name) {
    return '用戶端把 model 填成 $name 即可走容災。';
  }

  @override
  String get uiStyleLabel => '介面風格';

  @override
  String get uiStyleNote => '切換後整個應用程式改用另一套頁面實作';

  @override
  String get uiStyleMaterial => 'Material 3 Expressive';

  @override
  String get uiStyleMiuix => '小米 HyperOS';

  @override
  String get miuixPullToRefresh => '下拉重新整理';

  @override
  String get miuixReleaseToRefresh => '放開立即重新整理';

  @override
  String get miuixRefreshing => '正在重新整理…';

  @override
  String get miuixRefreshDone => '重新整理完成';

  @override
  String get navBarStyleLabel => '底部導航欄';

  @override
  String get navBarStyleNote => '液態玻璃走原生渲染，普通檔用系統導航欄';

  @override
  String get navBarStyleGlass => '液態玻璃';

  @override
  String get navBarStylePlain => '普通';

  @override
  String get displayIosPushTransitionCorner => '轉場圓角';

  @override
  String get displayIosPushTransitionCornerAuto => '跟隨裝置螢幕圓角';

  @override
  String get displayIosPushTransitionCornerUnsupported =>
      '目前裝置讀不到螢幕圓角，改用下面這個手動值';

  @override
  String get edgeHapticLabel => '滑動觸感回饋';

  @override
  String get edgeHapticNote => '快速滑動到頂部/底部時輕震一下';

  @override
  String get shortcutStartService => '啟動服務';

  @override
  String get shortcutStopService => '關閉服務';

  @override
  String get shortcutTokenStats => '查看 Token 用量';

  @override
  String get tasksDialogTitle => '任務';

  @override
  String get taskPauseServer => '暫停服務';

  @override
  String taskListenOn(String address) {
    return '監聽 $address';
  }

  @override
  String get taskStopListening => '停止監聽';

  @override
  String get tasksRecentSection => '最近';

  @override
  String tasksModelCount(int count) {
    return '$count 個模型';
  }

  @override
  String get createConfigScanTitle => '掃描 QR Code';

  @override
  String get createConfigScanDesc => '掃描或從相簿辨識來新增設定';

  @override
  String get qrScannerTitle => '掃描 QR Code';

  @override
  String get qrScannerHint => '對準螢幕任意位置，辨識到 QR Code 自動跳轉';

  @override
  String get qrScannerPermissionTitle => '需要相機權限';

  @override
  String get qrScannerPermissionDesc => '掃描需要使用相機，請在系統設定中允許本應用程式存取相機。';

  @override
  String get qrScannerOpenSettings => '前往設定';

  @override
  String get qrScannerRetry => '重試';

  @override
  String get qrScannerUnsupported => '目前平台不支援掃描，請在 Android / iOS 裝置上使用';

  @override
  String get qrScannerSwitchCamera => '切換前後鏡頭';

  @override
  String get qrScannerGallery => '從相簿辨識';

  @override
  String get qrScannerGalleryEmpty => '圖片中沒有辨識到 QR Code';

  @override
  String get qrResultTitle => '掃描結果';

  @override
  String get qrResultKindProfile => '設定檔 JSON';

  @override
  String get qrResultKindUpstream => '上游 JSON';

  @override
  String get qrResultKindUrl => '網頁連結';

  @override
  String get qrResultKindText => '純文字';

  @override
  String get qrResultImportProfile => '匯入設定檔';

  @override
  String get qrResultAddUpstream => '新增為上游';

  @override
  String get qrResultImportUrl => '匯入訂閱';

  @override
  String qrResultUpstreamAdded(String name) {
    return '已新增上游「$name」';
  }

  @override
  String get upstreamQrTitle => '上游 QR Code';

  @override
  String get upstreamQrHint => '用另一台安裝了本應用程式的裝置掃描，即可把這個上游匯入到它的規則裡。';

  @override
  String get upstreamQrTooLong => '內容過長，無法產生 QR Code';

  @override
  String get progressiveTopBarTitle => '漸變模糊頂欄';

  @override
  String get progressiveTopBarDesc => '頂欄透明化，頂部漸進模糊隨內容捲入淡入';

  @override
  String get navBarStyleFloating => '懸浮';

  @override
  String get biometricLockTitle => '生物辨識鎖';

  @override
  String get biometricLockDesc => '開啟應用程式時需要驗證指紋 / 人臉（Android）';

  @override
  String get biometricLockUnavailable => '此裝置沒有可用的生物辨識或螢幕鎖憑證';

  @override
  String get biometricGateTitle => 'Local2API 已鎖定';

  @override
  String get biometricGateHint => '驗證生物辨識以繼續';

  @override
  String get biometricUnlock => '解鎖';

  @override
  String get networkTitle => '網路';

  @override
  String get networkEntryDesc => 'Cloudflare Tunnel / Tailscale';

  @override
  String get cfTitle => 'Cloudflare Tunnel';

  @override
  String get cfDesc => '透過 trycloudflare 臨時通道，把本服務公開到網際網路';

  @override
  String get cfEnableSwitch => '啟用 trycloudflare';

  @override
  String get cfTermsTitle => 'Cloudflare 授權條款';

  @override
  String get cfTermsAgree => '同意並啟用';

  @override
  String get cfTermsDecline => '不同意';

  @override
  String get cfTermsFetchFailed => '授權條款擷取失敗，請檢查網路後重試';

  @override
  String get cfTermsNote => '啟用前需要同意 Cloudflare 的服務條款（trycloudflare.com）。';

  @override
  String get cfStarting => '正在啟動通道…';

  @override
  String get cfRunning => '通道執行中';

  @override
  String get cfStopped => '未執行';

  @override
  String get cfPublicUrl => '公開位址';

  @override
  String get cfBinaryMissing =>
      '找不到 cloudflared。內建通道目前只在桌面端可用（PATH 裝好 cloudflared 後重試）。';

  @override
  String get cfRetry => '重試';

  @override
  String get cfStop => '停止';

  @override
  String get tsTitle => 'Tailscale';

  @override
  String get tsDesc => '在 Tailscale 網路內存取本服務（100.64.0.0/10 網段）';

  @override
  String get tsAllowSwitch => '放行 Tailscale 網段';

  @override
  String tsDetected(String ip) {
    return '偵測到 Tailscale IP：$ip';
  }

  @override
  String get tsNotDetected => '未偵測到 Tailscale 介面（本機沒裝或沒連）';

  @override
  String get tsDownloadTitle => '取得 Tailscale';

  @override
  String get tsDownloadDesc => '在手機 / 電腦上安裝 Tailscale，隨時隨地存取本服務';

  @override
  String get tsOpenDownload => '開啟下載頁';

  @override
  String get securitySection => '安全性';

  @override
  String get webUiTitle => '臨時 WebUI';

  @override
  String get webUiDesc => '與 API 轉發分開的連接埠，用來臨時在瀏覽器裡試模型';

  @override
  String get webUiEnable => '啟用臨時 WebUI';

  @override
  String get webUiToggleHint => '關掉就停掉網頁服務，不影響 API 轉發';

  @override
  String get webUiPort => 'WebUI 連接埠';

  @override
  String get webUiHost => 'WebUI 監聽位址';

  @override
  String get webUiRunning => '網頁已啟動';

  @override
  String get webUiStopped => '網頁未啟動';

  @override
  String get webUiFailed => '網頁啟動失敗';

  @override
  String get webUiOpen => '在瀏覽器開啟';

  @override
  String get webUiCopyUrl => '複製位址';

  @override
  String get webUiEntryDesc => '連接埠、開關、瀏覽器入口';

  @override
  String get webUiNote => '頁面上的請求仍然打 API 連接埠，兩個連接埠互不干擾';

  @override
  String get scheduleTitle => '尖離峰時段';

  @override
  String get scheduleEntryDesc => '依星期與時段限制模型 / 模型組';

  @override
  String get scheduleDesc => '正向：只有選取的時段能用。反向：選取的時段禁用。對話模擬不受影響。';

  @override
  String get scheduleEmpty => '還沒有策略：不加就是全天可用';

  @override
  String get scheduleAdd => '新增策略';

  @override
  String get scheduleTarget => '作用對象';

  @override
  String get scheduleTargetModel => '單一模型';

  @override
  String get scheduleTargetGroup => '模型組';

  @override
  String get scheduleModel => '模型';

  @override
  String get scheduleGroup => '模型組';

  @override
  String get scheduleMode => '策略方向';

  @override
  String get scheduleModeAllow => '正向（選取時段才能用）';

  @override
  String get scheduleModeDeny => '反向（選取時段禁用）';

  @override
  String get scheduleWeekdays => '星期';

  @override
  String get scheduleSelectAll => '全選';

  @override
  String get scheduleUpstreamHint => '只作用於這個上游的模型；全選就等於給整個上游套視窗。改動即時生效，不用點儲存。';

  @override
  String get scheduleUpstreamNoModel => '這個上游還沒有對外模型，先在「對外模型」裡加幾個。';

  @override
  String get schedulePickWeekday => '選擇星期';

  @override
  String get scheduleHours => '時段';

  @override
  String scheduleHourRange(String start, String end) {
    return '$start:00 - $end:00';
  }

  @override
  String get scheduleEnabled => '啟用這條策略';

  @override
  String get scheduleDelete => '刪除策略';

  @override
  String get scheduleSaved => '策略已儲存';

  @override
  String get scheduleDeleted => '策略已刪除';

  @override
  String get scheduleSimNote => '對話模擬永遠可用，不受這些策略限制';

  @override
  String get schedulePickTarget => '選一個模型或模型組';

  @override
  String get schedulePickHour => '選取小時';

  @override
  String get scheduleStartHour => '起始';

  @override
  String get scheduleEndHour => '結束';

  @override
  String get scheduleAllDay => '全天';

  @override
  String scheduleStatus(String count) {
    return '$count 條策略';
  }

  @override
  String get modelContextLabel => '最大上下文數';

  @override
  String get modelContextHelper => '對外宣告給客戶端的上下文 token 數；留空按預設 1M，拉取模型清單時也會自動補';

  @override
  String modelContextShort(String value) {
    return '上下文 $value';
  }

  @override
  String contextAutoFilled(String count) {
    return '已從上游取得 $count 個模型的上下文長度';
  }

  @override
  String get modelOutputLabel => '最大輸出數';

  @override
  String get modelOutputHelper => '對外宣告給客戶端的最大輸出 token 數；留空不宣告';

  @override
  String contextRingInfo(String percent, String used, String total) {
    return '上下文佔用 $percent%（$used / $total tokens）';
  }

  @override
  String get contextRingEstimated => '，按字數估算';

  @override
  String get contextRingTap => '點擊查看上下文詳情';

  @override
  String get contextDetailTitle => '上下文佔用';

  @override
  String contextDetailPercent(String percent) {
    return '佔上下文 $percent%';
  }

  @override
  String contextDetailUsed(String used, String total) {
    return '$used / $total tokens';
  }

  @override
  String get contextDetailFromUsage => '取自上一輪回應的 usage（精確值）';

  @override
  String get contextDetailEstimated => '按字數與圖片粗估（上游沒回 usage）';

  @override
  String contextDetailOutput(String limit) {
    return '最大輸出 $limit tokens';
  }

  @override
  String get contextDetailOutputNone => '最大輸出未宣告';

  @override
  String contextDetailModel(String model) {
    return '請求模型 $model';
  }

  @override
  String contextDetailMessages(String count, String images) {
    return '$count 則訊息 · $images 張圖片';
  }

  @override
  String get contextDetailClose => '知道了';

  @override
  String get chatSimSendImages => '發送圖片';

  @override
  String get chatSimSendTextOnly => '僅發文字';

  @override
  String get chatSimSendImagesTip =>
      '圖片會作為多模態內容一起發給模型；純文字車道報錯時切到「僅發文字」，圖就只留在介面上。';

  @override
  String get chatSimImagesOn => '圖片會隨訊息發出';

  @override
  String get chatSimImagesOff => '圖片只在本地展示，不發給模型';

  @override
  String get chatSimAttachCamera => '拍照';

  @override
  String chatSimAttachFailed(String error) {
    return '讀取附件失敗：$error';
  }

  @override
  String get chatSimVoiceNoPermission => '沒有麥克風權限，無法語音輸入';

  @override
  String get chatSimVoiceOpenSettings => '去設定';

  @override
  String chatSimVoiceFailed(String error) {
    return '語音輸入失敗：$error';
  }

  @override
  String get voiceHoldToTalk => '按住說話';

  @override
  String get voiceReleaseToSend => '放開結束';

  @override
  String get voiceListeningHint => '正在聆聽…';

  @override
  String get voiceRecognizing => '辨識中…';

  @override
  String get voiceNothingHeard => '沒聽清楚，再按住說一次';

  @override
  String chatSimCallPeer(String name) {
    return '和 $name 通話';
  }

  @override
  String get chatSimMsgMenuTitle => '訊息操作';

  @override
  String get chatSimMsgSpeak => '朗讀';

  @override
  String get chatSimMsgStopSpeak => '停止朗讀';

  @override
  String get chatSimMsgRegenerate => '重新回答';

  @override
  String get chatSimMsgDownload => '下載音訊';

  @override
  String get chatSimDownloadTitle => '下載音訊';

  @override
  String get chatSimDownloadFormat => '格式';

  @override
  String get chatSimDownloadMp3Desc => '通用音訊，相容性最好';

  @override
  String get chatSimDownloadSilkDesc => 'SILK v3，微信 / QQ 的語音格式';

  @override
  String get chatSimDownloadSlkDesc => '與 SILK 位元組相同，只是副檔名不同';

  @override
  String get chatSimDownloadTencent => '騰訊相容（-tencent）';

  @override
  String get chatSimDownloadTencentDesc => '檔案頭加 0x02、結尾不寫哨兵包，微信 / QQ 才認';

  @override
  String get chatSimDownloadAction => '下載';

  @override
  String get chatSimDownloadBusy => '正在合成音訊…';

  @override
  String get chatSimDownloadCanceled => '已取消儲存';

  @override
  String chatSimDownloadSaved(String path) {
    return '已儲存：$path';
  }

  @override
  String chatSimDownloadFailed(String error) {
    return '匯出失敗：$error';
  }

  @override
  String get balanceTitle => 'Balance';

  @override
  String get balanceEntryDesc => 'Query this upstream\'s account balance';

  @override
  String get balancePullHint => '下拉重新整理餘額';

  @override
  String get balanceRefreshing => 'Querying…';

  @override
  String get balanceNoKey => 'Add an API key before querying';

  @override
  String get balanceUnsupported => 'No balance API on this upstream';

  @override
  String get balanceNoData => 'No balance returned';

  @override
  String get balanceAvailableLabel => 'Available';

  @override
  String get balanceGrantedLabel => 'Granted';

  @override
  String get balanceToppedUpLabel => 'Topped up';

  @override
  String get balanceUsedLabel => 'Used';

  @override
  String get balanceRequestsLabel => 'Requests';

  @override
  String get balanceGroupLabel => 'Group';

  @override
  String get balanceSourceLabel => 'Endpoint';

  @override
  String get balanceStatusOk => 'Account usable';

  @override
  String get balanceStatusBad => 'Account unavailable (unpaid or limited)';

  @override
  String get balanceQuotaNote => 'Converted at \$1 = 500000 quota';

  @override
  String balanceFailed(String error) {
    return 'Query failed: $error';
  }

  @override
  String balanceUpdatedAt(String time) {
    return 'Updated $time';
  }

  @override
  String get balanceDetailsTitle => 'Details';

  @override
  String get balanceLimitLabel => 'Limit';

  @override
  String get balanceUnauthorized => 'Key is invalid or can\'t read the account';

  @override
  String get balanceBadResponse => 'Unreadable response from the balance API';

  @override
  String get balanceNoKeyHint => 'Fill in the API key, then refresh';

  @override
  String get balanceUnauthorizedHint =>
      'Check that the key is valid and allowed to read account info';

  @override
  String get balanceUnsupportedHint =>
      'Not every upstream exposes a balance API';

  @override
  String get balanceNetworkHint =>
      'Make sure this device can reach that address, then retry';

  @override
  String get thinkingDefaultLabel => 'Default thinking level';

  @override
  String get thinkingDefaultOff => 'Don\'t interfere';

  @override
  String get thinkingLevelLow => 'Low';

  @override
  String get thinkingLevelMedium => 'Medium';

  @override
  String get thinkingLevelHigh => 'High';

  @override
  String get thinkingWireLabel => 'Thinking wire format';

  @override
  String get thinkingWireBudget => 'Output budget only';

  @override
  String get thinkingWireEffort => 'reasoning_effort';

  @override
  String get thinkingWireThinking => 'thinking switch';

  @override
  String get thinkingWireBoth => 'Both fields';

  @override
  String get logsFilterAll => '全部';

  @override
  String get logsFilterPassed => '通過';

  @override
  String get logsFilterFailed => '失敗';

  @override
  String get logsEmptyFiltered => '目前篩選下沒有請求';

  @override
  String get activeConnectionsTitle => '活躍連線';

  @override
  String get activeConnectionsEmpty => '目前沒有活躍連線';

  @override
  String get activeConnDuration => '已持續';

  @override
  String get activeConnStarted => '開始於';

  @override
  String get activeConnPath => '路徑';

  @override
  String get tsOpenApp => '開啟 Tailscale';

  @override
  String get tsInstalledDesc => '已安裝 Tailscale，點一下開啟用戶端';

  @override
  String get tsOpenFailed => '無法開啟 Tailscale，已改為開啟下載頁';

  @override
  String get usageCalendarBackToday => '回到今天';

  @override
  String get thinkingLevelNone => '關閉思考';

  @override
  String get thinkingLevelMinimal => '極輕';

  @override
  String get thinkingLevelXhigh => '極深';

  @override
  String get thinkingLevelMax => '最重';

  @override
  String get winCloseSection => '桌面視窗';

  @override
  String get winCloseBehaviorTitle => '關閉按鈕行為';

  @override
  String get winCloseAsk => '每次詢問';

  @override
  String get winCloseTray => '收進匣';

  @override
  String get winCloseExit => '退出程式';

  @override
  String get winCloseAskSummary => '每次都問一次（可勾選「下次也是這樣」）';

  @override
  String get winCloseTraySummary => '視窗收進匣，轉發服務繼續跑';

  @override
  String get winCloseExitSummary => '程式整體退出，服務隨之停止';

  @override
  String get winCloseDialogTitle => 'Local2API';

  @override
  String get winCloseDialogHeading => '您點擊了關閉按鈕，您希望？';

  @override
  String get winCloseDialogContent => '收進匣後程式在背景繼續轉發，可以從匣圖示隨時叫回來。';

  @override
  String get winCloseLinkTray => '收進匣';

  @override
  String get winCloseLinkTraySubtitle => '視窗藏起來，服務照常運行';

  @override
  String get winCloseLinkExit => '退出程式';

  @override
  String get winCloseLinkExitSubtitle => '連轉發服務一起停掉';

  @override
  String get winCloseRemember => '下次也是這樣';

  @override
  String get winTrayShow => '顯示主視窗';

  @override
  String get winTrayQuit => '退出 Local2API';

  @override
  String get thinkingWireHint => '上游不認這一檔時會自動逐級下調（max → xhigh → … → 不下發）';

  @override
  String get typeAnthropic => 'Anthropic Messages';

  @override
  String get trayHintBody => '嘿嘿，我在這裡哦';

  @override
  String get trayHintDismiss => '不再提示';

  @override
  String get trayHintSettings => '設定';

  @override
  String get winTrayHintTitle => '收進托盤時顯示提示';

  @override
  String get winTrayHintSummary => '彈一則系統通知：「嘿嘿，我在這裡哦」，附「不再提示 / 設定」兩個按鈕';

  @override
  String get settingsLabTitle => '實驗室';

  @override
  String get settingsLabDesc => '把 SillyTavern 裝到本機、內建瀏覽器等實驗功能';

  @override
  String get labTitle => '實驗室';

  @override
  String get labSubtitle => '本機服務與實驗性功能';

  @override
  String get labLocalServices => '本機服務';

  @override
  String get labSillyTavernDesc => '本機 AI 角色扮演前端（Node.js），裝好後在應用程式內開啟';

  @override
  String get labInstall => '安裝';

  @override
  String get labInstalled => '已安裝';

  @override
  String get labNotInstalled => '未安裝';

  @override
  String get labRunning => '執行中';

  @override
  String get labStart => '啟動';

  @override
  String get labStop => '停止';

  @override
  String get labOpen => '開啟';

  @override
  String get labOpenFolder => '開啟資料夾';

  @override
  String get labUninstall => '解除安裝';

  @override
  String get labUninstallTitle => '解除安裝 SillyTavern？';

  @override
  String get labUninstallBody => '會刪除已下載的程式檔案（含 data 目錄中的角色卡與聊天記錄），且無法復原。';

  @override
  String get labInstallLocation => '安裝位置';

  @override
  String get labChooseLocation => '選擇位置';

  @override
  String get labDefaultLocation => '預設位置';

  @override
  String get labNodeStatus => 'Node.js';

  @override
  String get labNodeMissing => '未偵測到 Node.js';

  @override
  String get labNodeMissingHint => '裝好 Node.js 18+ 後點「重新偵測」即可啟動；檔案可以先裝著。';

  @override
  String get labNodeDownload => '下載 Node.js';

  @override
  String get labRecheck => '重新偵測';

  @override
  String get labInstallDeps => '安裝相依套件';

  @override
  String get labMobileNoRun =>
      '行動端不能直接執行 Node.js 服務；檔案已裝到應用程式目錄，可用 Termux 等環境執行。';

  @override
  String get labNodeRuntimeTitle => 'Node.js 執行環境';

  @override
  String get labNodeRuntimeDesc =>
      '從 Termux 軟體源安裝 Android 版 Node.js（含 npm），實驗室的本機服務執行必備。';

  @override
  String get labNodeRuntimeInstall => '安裝 Node.js';

  @override
  String get labNodeRuntimeReinstall => '重新安裝';

  @override
  String get labNodeRuntimeRemove => '解除安裝 Node.js';

  @override
  String get labNodeRuntimeNotInstalled => '未安裝';

  @override
  String get labNodeRunnerMode => '執行模式';

  @override
  String get labRunnerDirect => '直接執行';

  @override
  String get labRunnerDirectDesc => '以應用程式身分啟動處理程序（debug 建置可用；release 會被系統攔截）';

  @override
  String get labRunnerShizuku => 'Shizuku';

  @override
  String get labRunnerShizukuDesc =>
      '經 Shizuku 以 shell 身分啟動處理程序（release 推薦，需安裝並授權 Shizuku）';

  @override
  String get labNodeMirror => '下載鏡像';

  @override
  String get labMirrorOfficial => '官方源';

  @override
  String get labMirrorOfficialDesc =>
      'packages.termux.dev · registry.npmjs.org（境內直連很慢，適合已有代理的網路）';

  @override
  String get labMirrorCn => '中國大陸鏡像';

  @override
  String get labMirrorCnDesc => '清華 TUNA termux 源 · npmmirror（境內直連快，實測數 MB/s）';

  @override
  String get labShizukuStatus => 'Shizuku 狀態';

  @override
  String get labShizukuNotDetected => '未偵測到 Shizuku（未安裝或未啟動）';

  @override
  String get labShizukuGranted => '已授權';

  @override
  String get labShizukuNotGranted => '未授權';

  @override
  String get labShizukuRequest => '授權 Shizuku';

  @override
  String get labExecBlocked => '系統禁止應用程式直接執行 Node，請切換到 Shizuku 模式';

  @override
  String get labVisibleDesc => '手動開啟後，這裡才會顯示實驗室入口';

  @override
  String get labOpenLab => '進入實驗室';

  @override
  String get labDownloading => '下載中';

  @override
  String get labExtracting => '解壓中';

  @override
  String get labInstallingDeps => '安裝相依套件中';

  @override
  String get labStarting => '啟動中';

  @override
  String get labLogs => '日誌';

  @override
  String get labClearLogs => '清空';

  @override
  String get labVersion => '版本';

  @override
  String get labPhaseIdle => '就緒';

  @override
  String get labBrowserTools => '內建工具';

  @override
  String get labBrowserTitle => '內建瀏覽器';

  @override
  String get labBrowserDesc => '在應用程式內開啟本機 WebUI、SillyTavern 或任意網址';

  @override
  String get labOpenBrowser => '開啟瀏覽器';

  @override
  String get labManualUrl => '輸入網址，例如 127.0.0.1:8000';

  @override
  String get labGo => '前往';

  @override
  String get labError => '出錯了';

  @override
  String get labCancel => '取消';

  @override
  String get browserTitle => '瀏覽器';

  @override
  String get browserEditUrl => '編輯網址';

  @override
  String get browserUrlHint => 'https://example.com';

  @override
  String get browserGo => '前往';

  @override
  String get browserBack => '上一頁';

  @override
  String get browserForward => '下一頁';

  @override
  String get browserReload => '重新載入';

  @override
  String get browserStop => '停止';

  @override
  String get browserMenu => '更多';

  @override
  String get browserCopyLink => '複製連結';

  @override
  String get browserCopyCookie => '複製 Cookie';

  @override
  String get browserCookieEmpty => '目前頁面沒有可複製的 Cookie';

  @override
  String get browserCookieCopied => 'Cookie 已複製';

  @override
  String get browserUaLabel => '瀏覽器識別';

  @override
  String get browserUaAuto => '自動';

  @override
  String get browserUaDesktop => '電腦端';

  @override
  String get browserUaMobile => '手機端';

  @override
  String get browserOpenExternal => '在系統瀏覽器開啟';

  @override
  String browserInitFailed(String error) {
    return '網頁載入失敗：$error';
  }

  @override
  String get browserUnsupported => '目前平台不支援內建瀏覽器，請用系統瀏覽器開啟';

  @override
  String get browserRetry => '重試';

  @override
  String get commonBack => '返回';

  @override
  String get close => '關閉';

  @override
  String get labMoreSettings => '更多設定';

  @override
  String get labInstallFirstTitle => '還沒安裝 SillyTavern';

  @override
  String get labInstallFirstBody => '先在「更多設定」裡裝好，再回來打開這個開關。';

  @override
  String get labGoSettings => '去設定';

  @override
  String get labStartFailed => '啟動失敗';

  @override
  String get labStopped => '已停止';

  @override
  String get labSectionStatus => '執行狀態';

  @override
  String get labSectionInstall => '安裝';

  @override
  String get labApiConfig => 'API 設定';

  @override
  String get labApiGroup => '模型組';

  @override
  String get labApiGroupNone => '未選擇';

  @override
  String get labApiModel => '模型';

  @override
  String get labApiBaseUrl => '介面位址';

  @override
  String get labApiKey => 'API Key';

  @override
  String get labApiNoKey => '還沒有啟用的 API Key（先去「金鑰」頁建一個）';

  @override
  String get labApiWrite => '寫入 SillyTavern';

  @override
  String get labApiWriteOk => '已寫入，重新整理 SillyTavern 頁面即生效';

  @override
  String labApiWriteFailed(String error) {
    return '寫入失敗：$error';
  }

  @override
  String get labApiNeedGroup => '先在「發現」頁啟用一個模型組';

  @override
  String get labApiNeedService => '沒連上本機服務，先在儀表板啟動服務';

  @override
  String get labApiNoUserData => 'SillyTavern 還沒啟動過，先啟動一次再寫入';

  @override
  String get labApiPickGroup => '選擇模型組';

  @override
  String get labApiPickModel => '選擇模型';

  @override
  String labApiModelCount(String count) {
    return '$count 個模型';
  }

  @override
  String get labLogsEmpty => '還沒有日誌';

  @override
  String get labCopyLogs => '複製日誌';

  @override
  String get labLogsCopied => '日誌已複製';

  @override
  String get browserClosePage => '關閉頁面';

  @override
  String get browserShareQr => '分享 QR Code';

  @override
  String get browserQrTitle => '掃碼在手機上開啟';

  @override
  String get browserViewCookies => '檢視 Cookie';

  @override
  String get browserCopyAll => '全部複製';

  @override
  String get browserClipboardAccess => '允許網頁寫入剪貼簿';

  @override
  String get browserClipboardAllowed => '已允許剪貼簿存取';

  @override
  String get browserClipboardBlocked => '已封鎖剪貼簿存取';

  @override
  String get browserSetUa => '自訂瀏覽器識別';

  @override
  String get browserUaEmptyHint => '留空恢復預設；改完會重新整理頁面';

  @override
  String get browserApplyAndReload => '套用並重新整理';

  @override
  String get browserUaUpdated => '瀏覽器識別已更新';

  @override
  String get browserTroubleshootNetwork => '網路疑難排解';

  @override
  String get browserTroubleshootFailed => '打不開系統疑難排解';

  @override
  String get browserAndroidErrorTitle => '系統 WebView 掛了';

  @override
  String get browserAndroidErrorCause => '可能原因';

  @override
  String get browserAndroidErrorDetail => '系統 WebView 版本過舊或被停用，內建瀏覽器起不來。';

  @override
  String get browserUpdateWebview => '更新 Android System WebView';

  @override
  String get browserOpenDevOptions => '檢視 WebView 實作（開發人員選項）';

  @override
  String get browserAppleErrorTitle => '內建瀏覽器無法啟動';

  @override
  String get browserAppleErrorReport => '錯誤報告';

  @override
  String get browserAppleErrorDetail => 'WKWebView 初始化失敗，通常是系統版本過舊或受企業原則限制。';

  @override
  String get browserBsodMessage => '你的內建瀏覽器發生問題，需要重新啟動。';

  @override
  String get browserBsodNoRestart => '我們只收集某些錯誤資訊，然後為你重新啟動。';

  @override
  String get browserBsodComplete => '0% 完成';

  @override
  String get browserBsodSolutions => '可以試試這些：';

  @override
  String get browserBsodDownload => '下載 Microsoft Edge WebView2 Runtime';

  @override
  String get browserBsodWinUpdate => '開啟 Windows 更新';

  @override
  String get browserBsodScanQr => '手機掃碼開啟 WebView2 下載頁';

  @override
  String get browserBsodStopCode => '停止代碼：WEBVIEW2_NOT_INSTALLED';

  @override
  String get labStatus => '狀態';

  @override
  String get browserUaHint => '貼上或輸入完整的 UA 字串';

  @override
  String get labApiStopFirst => '先停止 SillyTavern 再寫入（執行中的設定會被它自己覆蓋）';

  @override
  String get labAutoOpenBrowser => '啟動後自動開啟瀏覽器';

  @override
  String get labAutoOpenBrowserDesc => '關閉後 SillyTavern 不會自己拉起系統瀏覽器；用「開啟」手動進入';

  @override
  String get labDshTitle => 'DeepSeek Harness';

  @override
  String get labDshInstallFirstTitle => '還沒安裝 DeepSeek Harness';

  @override
  String get labDshInstallFirstBody => '先在「更多設定」裡裝好，再回來開啟這個開關。';

  @override
  String get labDshUninstallTitle => '卸載 DeepSeek Harness？';

  @override
  String get labDshUninstallBody => '會刪除 npm 安裝的 dsh 程式檔案，模型設定與聊天記錄保留在 ~/.dsh。';

  @override
  String get labDshPickModels => '選擇要加入 dsh 的模型';

  @override
  String get labDshDefaultModel => '預設模型';

  @override
  String get labDshPickDefault => '選擇預設模型';

  @override
  String get labDshWrite => '寫入 dsh 設定';

  @override
  String get labDshWriteOk => '已寫入 dsh 設定';

  @override
  String get labDshNeedModels => '先選模型組並勾選至少一個模型';

  @override
  String get labDshWriteHint => '寫入後 dsh 的模型清單會熱載入；執行中時應用會自動重啟它，讓新金鑰生效';

  @override
  String get labDshConfigPath => '設定檔';

  @override
  String get labDshOpenInApp => '在應用內開啟';

  @override
  String get labDshCompat => 'Android 相容層';

  @override
  String get labDshCompatDesc => '關閉 Android 上無法啟動的沙箱與 pwsh';

  @override
  String get browserSelectTitle => '選擇';

  @override
  String get browserOpenCustomTab => '用 Custom Tabs 開啟';

  @override
  String get browserCustomTabPick => '用哪個瀏覽器開啟';

  @override
  String get browserCustomTabAuto => '自動（系統預設）';

  @override
  String get browserCustomTabNone => '沒安裝支援 Custom Tabs 的瀏覽器';

  @override
  String get browserCustomTabFailed => '無法開啟這個連結';

  @override
  String get reply => '回覆';

  @override
  String get labNotifySection => '通知';

  @override
  String get labNotifyPermission => '通知權限';

  @override
  String get labNotifyPermissionDesc => '任務進度、提問與結果都走通知';

  @override
  String get labNotifyLiveUpdate => '即時更新';

  @override
  String get labNotifyLiveUpdateDesc => 'Android 16+ 把任務進度置頂在通知欄、鎖屏與狀態欄';

  @override
  String get labNotifyPromoted => '系統已放行即時更新';

  @override
  String get labNotifyNotPromoted => '目前不會升級為即時更新';

  @override
  String get labNotifyBattery => '忽略電池最佳化';

  @override
  String get labNotifyBatteryDesc => '讓 node / dsh 能在背景長時間執行';

  @override
  String get labNotifyBatteryIgnored => '已忽略電池最佳化';

  @override
  String get labNotifyOpenSettings => '系統通知設定';

  @override
  String get labNotifyTest => '發一則測試通知';

  @override
  String get labNotifyTestSent => '測試通知已發出';

  @override
  String get labNotifyTestFailed => '通知沒發出去（檢查權限）';

  @override
  String get labDshTaskHint => '任務提示詞';

  @override
  String get labDshTaskHintDesc => '讓模型按步驟回報進度、需要拍板時停下來問你';

  @override
  String get labDshPlugins => '外掛';

  @override
  String get labDshPluginMessageEdit => '編輯訊息';

  @override
  String get labDshPluginMessageEditDesc =>
      '在使用者訊息旁加鉛筆按鈕，改完可從上一輪分叉重送（dsh-message-edit）';

  @override
  String get labDshPluginComputerUse => '電腦操作模式';

  @override
  String get labDshPluginComputerUseDesc =>
      '截圖 + 滑鼠鍵盤控制，新任務可選「電腦操作模式」（dsh-computer-use-mode）';

  @override
  String get labDshPluginAndroid => '手机操作';

  @override
  String get labDshPluginAndroidDesc =>
      '手機操作：截圖、點按、滑動、UI 樹、OCR、logcat（@zseven-w/dsh-android）';

  @override
  String get labDshPluginInstalling => '正在安裝…';

  @override
  String get labDshPluginFailed => '外掛操作失敗';

  @override
  String get labDshPluginRestartHint => '切換後會自動重啟 DSH 讓外掛生效';

  @override
  String get labDshRunTask => '執行任務';

  @override
  String get labDshRunTaskDesc => '把一句話交給 dsh 執行，進度與結果走通知';

  @override
  String get labDshTaskPrompt => '要 dsh 做什麼？';

  @override
  String get labDshTaskBusy => '已經有一個任務在執行';

  @override
  String get labDshTaskStarted => '任務已開始，進度看通知';

  @override
  String get labDshTaskDone => '任務完成';

  @override
  String get labDshTaskFailed => '任務失敗';

  @override
  String get labDshTaskCancelled => '任務已取消';

  @override
  String labDshTaskSteps(String done, String total) {
    return '$done/$total 步';
  }

  @override
  String get labDshAgentDone => 'agent 已完成本輪操作';

  @override
  String get labDshNeedAnswer => 'dsh 正在等你回答';

  @override
  String get labDshAnswerHint => '開啟 dsh web 回答';

  @override
  String get labDshToastReplyHint => '輸入回答';

  @override
  String get labDshToastOptionsHint => '輸入 1-3 選擇，其他內容作為自訂回答';

  @override
  String get labDshToastSkip => '跳過';

  @override
  String get autoRefreshTitle => '自動更新模型';

  @override
  String get autoRefreshOff => '關閉';

  @override
  String get autoRefreshEvery1d => '每天';

  @override
  String get autoRefreshEvery3d => '每 3 天';

  @override
  String get autoRefreshEvery7d => '每 7 天';

  @override
  String get autoRefreshEvery30d => '每 30 天';

  @override
  String get autoRefreshDesc => '按設定的間隔去上游拉一次模型清單，新上的補進來、下架的刪掉';

  @override
  String get autoRefreshNever => '還沒重新整理過';

  @override
  String get autoRefreshJustNow => '剛剛重新整理過';

  @override
  String autoRefreshNextIn(String when) {
    return '下次 $when';
  }

  @override
  String get autoRefreshRefreshing => '正在重新整理…';

  @override
  String autoRefreshDone(String added, String removed) {
    return '模型清單已更新：新增 $added 個，移除 $removed 個';
  }

  @override
  String get autoRefreshNoChange => '模型清單已是最新';

  @override
  String get autoRefreshRefreshNow => '立即重新整理';

  @override
  String get autoRefreshFailed => '重新整理失敗';

  @override
  String get pluginManagerTitle => 'dsh 外掛';

  @override
  String get pluginManagerRefresh => '重新掃描';

  @override
  String get pluginManagerSubtitle => '安裝、開關與解除安裝 dsh 插件';

  @override
  String get pluginManagerSearch => '搜尋外掛';

  @override
  String get pluginManagerInstall => '安裝';

  @override
  String get pluginManagerInstallTitle => '安裝第三方外掛';

  @override
  String get pluginManagerPackageHint => 'npm 套件名，如 @scope/dsh-plugin-xxx';

  @override
  String get pluginManagerPackageEmpty => '請先填套件名';

  @override
  String get pluginManagerInstalling => '安裝中…';

  @override
  String get pluginManagerUninstall => '解除安裝';

  @override
  String pluginManagerUninstallConfirm(String name) {
    return '解除安裝 $name？這個套件會從 dsh 移除。';
  }

  @override
  String pluginManagerExitConfirm(String name) {
    return '停用 $name？已下載的套件會保留，下次啟用不用重裝。';
  }

  @override
  String get pluginManagerRestartHint => '外掛變更在 dsh 重新啟動後生效';

  @override
  String get pluginManagerDescTitle => '第三方外掛';

  @override
  String get pluginManagerEmpty => '還沒裝過外掛';

  @override
  String get pluginManagerNotReady => 'dsh 還沒裝好，先裝 dsh 再來管外掛';

  @override
  String pluginManagerInstalledCount(String count) {
    return '$count 個已啟用';
  }

  @override
  String get pluginManagerInstalledBadge => '已安裝';

  @override
  String get pluginManagerCustom => '第三方';

  @override
  String get pluginManagerOfficial => '內建';

  @override
  String get pluginManagerLocal => '本機目錄';

  @override
  String get pluginManagerAddLocal => '從本機目錄安裝';

  @override
  String get pluginManagerNoMatch => '沒有符合的外掛';

  @override
  String get pluginManagerSearchClear => '清除搜尋';

  @override
  String get pluginManagerExpand => '展開';

  @override
  String get pluginManagerCollapse => '收合';

  @override
  String pluginManagerOnlyOn(String platform) {
    return '僅支援 $platform';
  }

  @override
  String get pluginManagerNotInstalled => '未安裝';

  @override
  String get pluginManagerDisabled => '未啟用';

  @override
  String get pluginManagerEnabledState => '已啟用';

  @override
  String pluginManagerOverview(String enabled, String total) {
    return '$enabled 個已啟用 · 共 $total 個';
  }

  @override
  String get usageApiKeyFilter => 'API Key';

  @override
  String get usageAllApiKeys => '全部';

  @override
  String get usageModelFilter => '模型';

  @override
  String get usageAllModelsShort => '全部模型';

  @override
  String get usageRequestsShort => '請求';

  @override
  String get usageByModel => '各模型用量';

  @override
  String get usageModelCalls => 'API 請求次數';

  @override
  String get usageNoModelCalls => '這段時間沒有呼叫記錄';

  @override
  String get usageChartByModel => '按模型';

  @override
  String get usageChartByKey => '按 API Key';

  @override
  String get usageKeyName => '金鑰';

  @override
  String get usageKeyAnonymous => '未鑒權呼叫';

  @override
  String get usageTotalRow => '合計';

  @override
  String get usageCallsUnit => '次';
}
