// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Local2API';

  @override
  String get navServer => 'Server';

  @override
  String get navModels => 'Models';

  @override
  String get navKeys => 'Keys';

  @override
  String get navSettings => 'Settings';

  @override
  String get serverTitle => 'Server';

  @override
  String get serverRunning => 'Running';

  @override
  String get serverStopped => 'Stopped';

  @override
  String get serverStarting => 'Starting…';

  @override
  String get homeStatusDescRunning =>
      'Service is running. Clients can call it now.';

  @override
  String get homeStatusDescStopped =>
      'Service is not running. Tap the card to start.';

  @override
  String get homeStatusDescStarting => 'Starting service…';

  @override
  String get homeStatusDescError => 'Failed to start. Tap the card to retry.';

  @override
  String get startServer => 'Start server';

  @override
  String get stopServer => 'Stop server';

  @override
  String get restartServer => 'Restart server';

  @override
  String get endpointTitle => 'Endpoint';

  @override
  String get listenAddress => 'Listen address';

  @override
  String get listenPort => 'Listen port';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get allInterfaces => 'All interfaces (0.0.0.0)';

  @override
  String get loopbackOnly => 'Loopback only (127.0.0.1)';

  @override
  String get lanIpsLabel => 'LAN/VPN addresses';

  @override
  String get statsTitle => 'Request stats';

  @override
  String get statTotalRequests => 'Total requests';

  @override
  String get statErrors => 'Failed';

  @override
  String get statActive => 'Active connections';

  @override
  String get recentLogs => 'Recent requests';

  @override
  String get viewAll => 'View all';

  @override
  String get noLogsYet => 'No requests yet';

  @override
  String get noKeysWarningTitle => 'No API keys configured';

  @override
  String get noKeysWarningBody =>
      'Any client can call this server right now. Add at least one key in the Keys section on the Dashboard.';

  @override
  String get noCidrWarningTitle => 'Open to all sources';

  @override
  String get noCidrWarningBody =>
      'No IP rules configured, every network is allowed.';

  @override
  String get serverErrorTitle => 'Server error';

  @override
  String portInUse(String port) {
    return 'Port $port is already in use';
  }

  @override
  String get autoStart => 'Start server automatically on launch';

  @override
  String get modelsTitle => 'Models';

  @override
  String get upstreams => 'Upstreams';

  @override
  String get addUpstream => 'Add upstream';

  @override
  String get noUpstreams => 'No upstreams yet, add one first';

  @override
  String get upstreamTypeLabel => 'Type';

  @override
  String get typeOpenai => 'OpenAI compatible';

  @override
  String get typeLlamacpp => 'llama.cpp';

  @override
  String get typeOllama => 'Ollama';

  @override
  String get typeLocalTts => 'Local TTS (Qwen3)';

  @override
  String get modalityLabel => 'Modality';

  @override
  String get modalityChat => 'Chat';

  @override
  String get modalityAudio => 'Audio (TTS)';

  @override
  String get modalityAudioHint =>
      'When enabled, /v1/audio/speech translates OpenAI TTS requests into chat.completions audio calls (MiMo TTS etc.) and streams the decoded audio back to the client.';

  @override
  String get localTtsSectionTitle => 'Local TTS (Qwen3-TTS)';

  @override
  String get ttsSettingsTitle => 'TTS 設定';

  @override
  String get ttsSettingsDesc => '本地模型、服務商與試聽';

  @override
  String get ttsAutoPlayTitle => '自動播放 TTS';

  @override
  String localTtsModelSize(String size) {
    return 'About $size GB total';
  }

  @override
  String get localTtsStateInstalled => 'Installed';

  @override
  String get localTtsStatePartial => 'Incomplete (resumable)';

  @override
  String get localTtsStateNotInstalled => 'Not downloaded';

  @override
  String get localTtsDownload => 'Download model';

  @override
  String localTtsDownloadProgress(String received, String total) {
    return 'Downloading $received/$total MB';
  }

  @override
  String get localTtsDeleteConfirm => 'Delete local TTS model files?';

  @override
  String get localTtsDevicePreference => 'Inference backend';

  @override
  String get ttsDeviceAuto => 'Auto (NPU first on Qualcomm)';

  @override
  String get ttsDeviceNpu => 'NPU (Hexagon)';

  @override
  String get ttsDeviceGpu => 'GPU (Vulkan)';

  @override
  String get ttsDeviceCpu => 'CPU';

  @override
  String get localTtsTestSpeak => 'Preview';

  @override
  String get localTtsTestStop => 'Stop';

  @override
  String get localTtsStatusPreparing => 'Loading model…';

  @override
  String get localTtsStatusSynthesizing => 'Synthesizing…';

  @override
  String get localTtsStatusPlaying => 'Playing';

  @override
  String get localTtsStatusIdle => 'Idle';

  @override
  String get localTtsStatusError => 'Error';

  @override
  String get localTtsNotReady => 'Model not downloaded or incomplete';

  @override
  String get localTtsServeHint =>
      'Once downloaded, tap \"Create local TTS upstream\" below; clients call /v1/audio/speech (model name qwen3-tts).';

  @override
  String get localTtsUpstreamName => 'Local TTS';

  @override
  String get localTtsCreateUpstream => 'Create local TTS upstream';

  @override
  String get localTtsCreateUpstreamDesc =>
      'Automatically adds a \"Local TTS\" upstream (model qwen3-tts) so clients can call /v1/audio/speech.';

  @override
  String get localTtsUpstreamCreated => 'Local TTS upstream created';

  @override
  String get localTtsUpstreamExists => 'Local TTS upstream already exists';

  @override
  String get settingsFeaturesSection => 'Service & features';

  @override
  String get networkSettingsTitle => 'Network settings';

  @override
  String get networkSettingsDesc =>
      'Port & listen, temp WebUI, IP access rules';

  @override
  String get chatSettingsTitle => 'Chat settings';

  @override
  String get chatSettingsDesc => 'TTS 設定、自動播放與角色卡';

  @override
  String get ipRulesEmpty => 'No rules yet; all sources are allowed by default';

  @override
  String ipRulesCount(String count) {
    return '$count rule(s)';
  }

  @override
  String ruleDeletedCount(String count) {
    return '$count rule(s) deleted';
  }

  @override
  String ruleRestored(String count) {
    return '$count rule(s) restored';
  }

  @override
  String get characterEntryDesc =>
      'Manage character cards and default scenes for chat simulation';

  @override
  String get ttsProviderLabel => 'Default TTS provider';

  @override
  String get ttsProviderOff => 'Off';

  @override
  String get ttsProviderLocal => 'Local Qwen3-TTS';

  @override
  String get ttsProviderNoneHint =>
      'No speech-capable model yet: add a model to an audio upstream or download the local model first';

  @override
  String get ttsDesignModelLabel => 'Default voice design model';

  @override
  String get ttsDesignModelDesc =>
      'Used when the character card has no voice sample; the prompt describes the voice';

  @override
  String get ttsDesignPromptLabel => 'Voice design prompt';

  @override
  String get ttsDesignPromptDesc =>
      'Voice description sent as the user message; leave empty for default';

  @override
  String get ttsCloneModelLabel => 'Default voice clone model';

  @override
  String get ttsCloneModelDesc =>
      'Used when the character card has a voice sample';

  @override
  String get ttsDesignPromptDefault => 'Default';

  @override
  String get ttsPlaygroundTitle => 'TTS Playground';

  @override
  String get ttsPlaygroundDesc =>
      'Swap samples and text to debug clone and design quality';

  @override
  String get ttsPlaygroundHint =>
      'Pick a model, attach a voice sample, type text and play. If the clone sounds off, try a cleaner sample first: a single speaker, 5–10 seconds, no background music, no reverb.';

  @override
  String get ttsPlaygroundModel => 'Model';

  @override
  String get ttsPlaygroundText => 'Text to synthesize';

  @override
  String get ttsPlaygroundInstructions =>
      'Style instructions / voice description (optional)';

  @override
  String get ttsPlaygroundPlay => 'Play';

  @override
  String get ttsPlaygroundEmptyText => 'Type the text to synthesize first';

  @override
  String get ttsPlaygroundCloneNeedsSample =>
      'Clone models need a voice sample: attach one above first';

  @override
  String get ttsSpeak => 'Read aloud';

  @override
  String get characterVoiceLabel => 'Voice sample';

  @override
  String get characterVoiceHint =>
      'Pick a clear voice recording (wav/mp3, ≤7MB) for voice cloning. Cloud cloning (MiMo) is recommended — it answers in seconds; local cloning needs the 1.4GB model loaded and can take minutes the first time.';

  @override
  String get characterVoicePick => 'Pick audio';

  @override
  String get characterVoiceRemove => 'Remove';

  @override
  String get characterVoiceTooBig =>
      'Sample too large; please compress it under 7MB';

  @override
  String get characterVoiceBadType => 'Only wav / mp3 audio is supported';

  @override
  String get characterOverrideReset => 'Builtin card restored to original';

  @override
  String get upstreamNameLabel => 'Name';

  @override
  String get baseUrlLabel => 'Base URL';

  @override
  String get baseUrlHint => 'http://192.168.1.10:11434/v1';

  @override
  String get upstreamKeyLabel => 'Upstream API key (optional)';

  @override
  String get upstreamNoteLabel => 'Note';

  @override
  String get upstreamNoteHint =>
      'What this upstream is for, anything worth remembering (optional)';

  @override
  String get upstreamJsonTitle => 'Upstream JSON';

  @override
  String get fetchModelsBtn => 'Fetch models';

  @override
  String get testBtn => 'Test';

  @override
  String get testOk => 'Connection OK';

  @override
  String testFailed(String error) {
    return 'Connection failed: $error';
  }

  @override
  String fetchFailed(String error) {
    return 'Fetch failed: $error';
  }

  @override
  String fetchedModels(String count) {
    return 'Got $count models';
  }

  @override
  String get saveBtn => 'Save';

  @override
  String get deleteBtn => 'Delete';

  @override
  String deleteUpstreamConfirm(String name) {
    return 'Delete upstream \"$name\"?';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get exposedModelsTitle => 'Exposed models';

  @override
  String get noExposedModels => 'No models exposed';

  @override
  String get modelAliasLabel => 'Public name';

  @override
  String get modelTargetLabel => 'Upstream model';

  @override
  String get enabledLabel => 'Enabled';

  @override
  String get exposedLabel => 'Exposed';

  @override
  String get baseUrlInvalid => 'Invalid URL, must start with http(s)://';

  @override
  String get fetchingModels => 'Fetching models…';

  @override
  String get testing => 'Testing…';

  @override
  String get editUpstream => 'Edit upstream';

  @override
  String get newUpstream => 'New upstream';

  @override
  String get upstreamNameRequired => 'Name is required';

  @override
  String modelCountLabel(String count) {
    return '$count models';
  }

  @override
  String get upstreamEditHint =>
      'An upstream is one OpenAI-compatible endpoint. Save from the top bar when you are done.';

  @override
  String get upstreamModeLabel => 'Mode';

  @override
  String get pickModeTitle => 'Choose mode';

  @override
  String get notFilled => 'Not set';

  @override
  String get testConnectionTitle => 'Test connection';

  @override
  String get testConnectionDesc => 'Try once with the current URL and key';

  @override
  String get addModelBtn => 'Add model';

  @override
  String get modelsPageHint =>
      'Tap the download icon to fetch models from the upstream, then tick the ones to expose. The plus sign adds one by hand.';

  @override
  String get modelsSortTitle => 'Sort order';

  @override
  String get modelsSortNatural => 'Default order';

  @override
  String get modelsSortAlphabet => 'A–Z order';

  @override
  String get keysTitle => 'API keys';

  @override
  String get addKey => 'Add key';

  @override
  String get keyNameLabel => 'Label';

  @override
  String get keyNameHint => 'e.g. My phone';

  @override
  String get keyValueLabel => 'Key';

  @override
  String get generate => 'Generate';

  @override
  String get noKeysHint => 'No keys yet, any client can call this server';

  @override
  String deleteKeyConfirm(String name) {
    return 'Delete key \"$name\"?';
  }

  @override
  String get keyExists => 'This key already exists';

  @override
  String get keyRequired => 'Key is required';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get networkSection => 'Network & access';

  @override
  String get accessRules => 'IP access rules';

  @override
  String get accessRuleDesc =>
      'Matched in order, first match wins; empty means allow all';

  @override
  String get addRule => 'Add rule';

  @override
  String get ruleAllow => 'Allow';

  @override
  String get ruleDeny => 'Deny';

  @override
  String get cidrHint => 'e.g. 192.168.0.0/16';

  @override
  String get cidrInvalid => 'Invalid CIDR';

  @override
  String get corsToggle => 'Allow CORS';

  @override
  String get corsDesc => 'Let web frontends call this server directly';

  @override
  String get autoStartToggle => 'Start server automatically on launch';

  @override
  String get appearanceSection => 'Appearance';

  @override
  String get themeLabel => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get languageLabel => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get languageNote =>
      'On Android 13+ this follows the system per-app language';

  @override
  String get aboutSection => 'About';

  @override
  String get aboutDesc =>
      'Forwards llama.cpp, Ollama or any OpenAI-compatible API in your LAN/VPN into a new authenticated API layer with a model allowlist.';

  @override
  String get versionLabel => 'Version';

  @override
  String get aboutEntryDesc => 'Version, components and effect background';

  @override
  String get aboutTapLogoHint => 'Try tapping the icon above';

  @override
  String get aboutOpenLicenses => 'Open source licenses';

  @override
  String get ossTitle => 'Open source licenses';

  @override
  String get ossSearchHint => 'Search packages or licenses';

  @override
  String get ossClearSearch => 'Clear search';

  @override
  String ossPackagesCount(String count, String licenses) {
    return '$count packages · $licenses licenses';
  }

  @override
  String ossLicensesCount(String count) {
    return '$count licenses';
  }

  @override
  String get ossEmptySearch => 'No matching packages';

  @override
  String get ossLoadFailed => 'Failed to load the license list';

  @override
  String get ossRetry => 'Retry';

  @override
  String get ossLoading => 'Collecting licenses…';

  @override
  String get ossCopyFullText => 'Copy all licenses';

  @override
  String get ossLicenseCopied => 'Copied to clipboard';

  @override
  String ossLicenseIndex(String index, String count) {
    return 'License $index of $count';
  }

  @override
  String get aboutComponents => 'Built with';

  @override
  String get aboutComponentsDesc => 'Flutter · flutter_miuix (HyperOS style)';

  @override
  String get textureSetTitle => 'Texture Set';

  @override
  String get textureSetEffectVariant => 'Effect Variant';

  @override
  String get textureSetOs2 => 'OS2';

  @override
  String get textureSetOs3 => 'OS3';

  @override
  String get textureSetEffectBg => 'Effect Background';

  @override
  String get textureSetDynamicBg => 'Dynamic Background';

  @override
  String get textureSetBlurEnable => 'Blur';

  @override
  String get textureSetBlurRadius => 'Blur Radius';

  @override
  String get textureSetNoise => 'Noise';

  @override
  String get textureSetBrightness => 'Brightness';

  @override
  String get textureSetContrast => 'Contrast';

  @override
  String get textureSetSaturation => 'Saturation';

  @override
  String get textureSetBlendMode => 'Blend Mode';

  @override
  String get textureSetReset => 'Reset to defaults';

  @override
  String get blendModeDefault => 'Default';

  @override
  String get blendModeOverlay => 'Overlay';

  @override
  String get blendModeScreen => 'Screen';

  @override
  String get blendModeMultiply => 'Multiply';

  @override
  String get blendModePlusLighter => 'Plus Lighter';

  @override
  String get blendModePlusDarker => 'Plus Darker';

  @override
  String get blendModeLinearLight => 'Linear Light';

  @override
  String get blendModeDifference => 'Difference';

  @override
  String get unsavedChangesTitle => 'Unsaved changes';

  @override
  String get unsavedChangesMessage =>
      'Your edits to this upstream haven\'t been saved. Save now?';

  @override
  String get unsavedSave => 'Save';

  @override
  String get unsavedDiscard => 'Discard';

  @override
  String get chatSimModelPicker => 'Simulation model';

  @override
  String get chatSimModelAll => 'All (whole group)';

  @override
  String get chatSimModelAllDesc =>
      'Every model in the group receives this context';

  @override
  String get chatSimModelSpecificDesc =>
      'Only this model receives this context';

  @override
  String get editMenuUndo => '&Undo';

  @override
  String get editMenuCut => 'Cu&t';

  @override
  String get editMenuCopy => '&Copy';

  @override
  String get editMenuPaste => '&Paste';

  @override
  String get editMenuDelete => '&Delete';

  @override
  String get editMenuSelectAll => 'Select &All';

  @override
  String get portRangeInvalid => 'Port must be 1024-65535';

  @override
  String get logsTitle => 'Request logs';

  @override
  String get clearLogs => 'Clear';

  @override
  String get logsCleared => 'Cleared';

  @override
  String get stopServerConfirm => 'Stop the server?';

  @override
  String get clientLabel => 'Client';

  @override
  String get modelLabel => 'Model';

  @override
  String get statusLabel => 'Status';

  @override
  String get durationLabel => 'Duration';

  @override
  String get colorAmber => 'Amber';

  @override
  String get colorBlue => 'Blue';

  @override
  String get colorBlueGrey => 'Blue grey';

  @override
  String get colorBrown => 'Brown';

  @override
  String get colorCyan => 'Cyan';

  @override
  String get colorDeepPurple => 'Deep purple';

  @override
  String get colorDefaultGreen => 'Default green';

  @override
  String get colorGreen => 'Green';

  @override
  String get colorGrey => 'Grey';

  @override
  String get colorIndigo => 'Indigo';

  @override
  String get colorLightBlue => 'Light blue';

  @override
  String get colorLightGreen => 'Light green';

  @override
  String get colorLime => 'Lime';

  @override
  String get colorOrange => 'Orange';

  @override
  String get colorPink => 'Pink';

  @override
  String get colorPurple => 'Purple';

  @override
  String get colorRed => 'Red';

  @override
  String get colorTeal => 'Teal';

  @override
  String get colorYellow => 'Yellow';

  @override
  String get commonBackTooltip => 'Navigate up';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonCreate => 'Create';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonSave => 'Save';

  @override
  String get displayFollowSystemColor => 'Follow system color';

  @override
  String get displayFontWeight => 'Font weight';

  @override
  String get displayOff => 'Off';

  @override
  String get displayPureBlack => 'Pure black dark mode';

  @override
  String get displayPureBlackOn => 'Dark mode (pure black)';

  @override
  String get displayScaleCompact => 'Compact mode · Show more content';

  @override
  String get displayScaleCompactBig => 'Compact · Good for large screens';

  @override
  String get displayScaleDefault => 'Default';

  @override
  String get displayScaleFineTune => 'Fine tune';

  @override
  String get displayScaleHuge => 'Extra large · Assistive features';

  @override
  String get displayModeTitle => 'Screen refresh rate';

  @override
  String get displayModeAuto => 'Auto';

  @override
  String get displayModeSystemTag => '[System]';

  @override
  String get displayModeHint => 'Not working? Try restarting the app';

  @override
  String get displayModeUnsupported =>
      'Screen refresh rate settings are only supported on Android';

  @override
  String get displayModeLoading => 'Loading screen refresh rates...';

  @override
  String get displayModeEmpty => 'No screen refresh rates available';

  @override
  String get displayScaleLarge => 'Slightly larger · Easier to read';

  @override
  String get displayScaleLargeFont => 'Large text · Accessibility friendly';

  @override
  String get displayScaleLargeFontShort => 'Large text · Accessibility';

  @override
  String get displayScaleMin => 'Smallest · Highest information density';

  @override
  String get displayScaleNote =>
      'The scale applies globally to text and some layout sizes. Set it to 100% to restore the default. Changes take effect immediately without a restart.';

  @override
  String get displayScalePresets => 'Quick presets';

  @override
  String get displayScaleReset => 'Reset to 100%';

  @override
  String get displayScaleSmall => 'Slightly smaller · Good for large screens';

  @override
  String get displayScaleSystemDefault => 'System default';

  @override
  String get displayScaleTitle => 'Display Scale';

  @override
  String get displaySectionAppearance => 'Appearance';

  @override
  String get displaySectionPersonalize => 'Personalization';

  @override
  String get displaySeedAmber => 'Amber';

  @override
  String get displaySeedBlue => 'Blue';

  @override
  String get displaySeedBlueGrey => 'Blue grey';

  @override
  String get displaySeedBrown => 'Brown';

  @override
  String get displaySeedCustom => 'Custom';

  @override
  String get displaySeedCyan => 'Cyan';

  @override
  String get displaySeedDeepPurple => 'Deep purple';

  @override
  String get displaySeedDefaultGreen => 'Default green';

  @override
  String get displaySeedGreen => 'Green';

  @override
  String get displaySeedGrey => 'Grey';

  @override
  String get displaySeedIndigo => 'Indigo';

  @override
  String get displaySeedLightBlue => 'Light blue';

  @override
  String get displaySeedLightGreen => 'Light green';

  @override
  String get displaySeedLime => 'Lime';

  @override
  String get displaySeedOrange => 'Orange';

  @override
  String get displaySeedPink => 'Pink';

  @override
  String get displaySeedPurple => 'Purple';

  @override
  String get displaySeedRed => 'Red';

  @override
  String get displaySeedTeal => 'Teal';

  @override
  String get displaySeedYellow => 'Yellow';

  @override
  String get displaySettingsTitle => 'Display';

  @override
  String get displayThemeColor => 'Theme color';

  @override
  String get displayThemeDark => 'Dark';

  @override
  String get displayThemeLight => 'Light';

  @override
  String get displayThemeMode => 'Theme mode';

  @override
  String displayWeightBlack(int weight) {
    return 'Black ($weight)';
  }

  @override
  String displayWeightBold(int weight) {
    return 'Bold ($weight)';
  }

  @override
  String displayWeightCustom(int weight) {
    return 'Custom ($weight)';
  }

  @override
  String displayWeightLight(int weight) {
    return 'Light ($weight)';
  }

  @override
  String displayWeightMedium(int weight) {
    return 'Medium ($weight)';
  }

  @override
  String displayWeightRegular(int weight) {
    return 'Regular ($weight)';
  }

  @override
  String displayWeightThin(int weight) {
    return 'Thin ($weight)';
  }

  @override
  String get drawerSystemMode => 'Follow system';

  @override
  String get fontWeightBlack => 'Black';

  @override
  String get fontWeightBold => 'Bold';

  @override
  String get fontWeightLight => 'Light';

  @override
  String get fontWeightMedium => 'Medium';

  @override
  String get fontWeightRegular => 'Regular';

  @override
  String get fontWeightSampleText =>
      'The quick brown fox jumps over the lazy dog.\nThe quick brown fox jumps over the lazy dog.';

  @override
  String get fontWeightSaveApply => 'Save and apply';

  @override
  String get fontWeightUnsavedTitle => 'Unsaved changes';

  @override
  String fontWeightUnsavedBody(int weight) {
    return 'Font weight is now $weight but you have not confirmed it.';
  }

  @override
  String get fontWeightUnsavedSave => 'Save';

  @override
  String get fontWeightUnsavedDiscard => 'Discard';

  @override
  String get fontWeightThin => 'Thin';

  @override
  String get playlistMenuMore => 'More actions';

  @override
  String get searchPureBlack => 'Pure black dark mode';

  @override
  String get searchThemeMode => 'Theme mode';

  @override
  String get startScreenGoBack => 'Navigate up';

  @override
  String get themeAppearance => 'Appearance';

  @override
  String themeColorCopied(String hex) {
    return 'Color code copied: $hex';
  }

  @override
  String get themeColorExtracted => 'Theme color extracted from image';

  @override
  String themeColorFailed(String error) {
    return 'Failed to pick color: $error';
  }

  @override
  String get themeColorsSection => 'Colors';

  @override
  String get themeCopyColor => 'Copy color code';

  @override
  String get themeCreateTitle => 'Create custom theme';

  @override
  String themeCreated(String name) {
    return 'Theme \"$name\" created and saved';
  }

  @override
  String get themeDarkBlackened => 'Dark mode (pure black)';

  @override
  String themeDeleteConfirm(String name) {
    return 'Delete the custom theme \"$name\"?';
  }

  @override
  String get themeDeleteTitle => 'Delete theme';

  @override
  String themeDeleted(String name) {
    return '\"$name\" deleted';
  }

  @override
  String get themeDropHint =>
      'Release to extract the theme color from the image';

  @override
  String get themeEnabled => 'On';

  @override
  String get themeFollowSystem => 'Follow system colors';

  @override
  String get themeHexHint => 'e.g. #FF0000 or 255,0,0';

  @override
  String get themeHexLabel => 'Hex / RGB';

  @override
  String get themeImageOnly => 'Only image formats are supported';

  @override
  String get themeNameHint => 'Enter text';

  @override
  String get themeNameLabel => 'Theme name';

  @override
  String get themeNewTheme => 'New theme';

  @override
  String get themeOff => 'Off';

  @override
  String get themePaletteStyle => 'Palette style';

  @override
  String get themePickColor => 'Pick a color';

  @override
  String get settingsBlurTitle => 'Enable blur';

  @override
  String get settingsBlurDesc => 'Enable blur effects for the app';

  @override
  String get settingsCustomColorsTitle => 'Custom colors';

  @override
  String get settingsCustomColorsDesc =>
      'Customize theme colors in the Miuix theme style';

  @override
  String get themeCustomColorsNeeded => 'Enable custom colors first';

  @override
  String get themePickFromImage => 'Pick color from image';

  @override
  String themeSwitched(String name) {
    return 'Switched to the $name theme';
  }

  @override
  String get themeTitle => 'Theme';

  @override
  String get settingsDisplaySection => 'Appearance';

  @override
  String get settingsDisplayEntry => 'Display settings';

  @override
  String get drawerDarkMode => 'Dark mode';

  @override
  String get drawerLightMode => 'Light mode';

  @override
  String get sideBarCollapse => 'Collapse sidebar';

  @override
  String get sideBarExpand => 'Expand sidebar';

  @override
  String get navDiscover => 'Discover';

  @override
  String get laneProbing => 'Checking…';

  @override
  String get laneUsable => 'Usable';

  @override
  String get laneRestricted => 'Official client only';

  @override
  String get laneThrottled => 'Quota reached';

  @override
  String get laneRegionBlocked => 'Region-limited';

  @override
  String get laneUnavailable => 'Model not available';

  @override
  String get laneFailed => 'Unavailable';

  @override
  String get laneNetUnreachable => 'Unreachable';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get dashboardTitle => 'Dashboard';

  @override
  String get fabRefresh => 'Refresh';

  @override
  String get fabAppearance => 'Appearance';

  @override
  String get appearancePanelTitle => 'Quick appearance settings';

  @override
  String get fabDelayTest => 'Test connection';

  @override
  String get laneUntested => 'Not tested yet';

  @override
  String get laneHintRoute =>
      'Tap a lane to make it the head; the rest stay as ordered fallbacks.';

  @override
  String get discoverTitle => 'Discover';

  @override
  String get discoverIntro =>
      'Every upstream is listed here: the switch enables it, the bolt speed-tests it, open a card to edit. Pull down to refresh the available model list.';

  @override
  String get fabNewUpstream => 'New upstream';

  @override
  String get createConfigTitle => 'Create config';

  @override
  String get createConfigFileTitle => 'File';

  @override
  String get createConfigFileDesc =>
      'Import from a file, a subscription URL, or pasted JSON';

  @override
  String get createConfigUpstreamDesc => 'Create an upstream group manually';

  @override
  String get profileNewUpstreamTitle => 'New upstream';

  @override
  String get profileGroupNameLabel => 'Name';

  @override
  String get profileGroupNameHint =>
      'Name this model group (blank keeps the document\'s own name)';

  @override
  String get profileGroupDescLabel => 'Description';

  @override
  String get profileGroupDescHint =>
      'What this group is and where it comes from (optional)';

  @override
  String get profileSpeedTest => 'Speed test';

  @override
  String get profileRefreshModels => 'Refresh model list';

  @override
  String get profileLanesDynamic => 'Model list changes with the upstream';

  @override
  String profileModelsRefreshed(int count) {
    return 'Refreshed the model list of $count groups';
  }

  @override
  String get profileModelsRefreshFailed =>
      'No group could be refreshed — check the network or endpoint address';

  @override
  String keyDeletedCount(int count) {
    return 'Deleted $count key(s)';
  }

  @override
  String get keyRestore => 'Undo';

  @override
  String keyRestored(int count) {
    return 'Restored $count key(s)';
  }

  @override
  String get keysManage => 'Manage keys';

  @override
  String get keysIntro =>
      'Keys are the gate on this layer: only clients holding one may call in. Swipe a row left to delete it.';

  @override
  String get keysEmptyPage => 'No keys yet — tap the + button to add one.';

  @override
  String get usageTitle => 'Token stats';

  @override
  String get usageIntro =>
      'Every request this proxy serves is accounted here: input / output / cache hits, by model and time.';

  @override
  String get usageAllModels => 'All models';

  @override
  String get usageRangeToday => 'Today';

  @override
  String get usageRange7 => 'Last 7 days';

  @override
  String get usageRange30 => 'Last 30 days';

  @override
  String get usageRangeAll => 'All';

  @override
  String get usageTotal => 'Total';

  @override
  String get usageInput => 'Input';

  @override
  String get usageOutput => 'Output';

  @override
  String get usageCacheHit => 'Cache hit';

  @override
  String get usageCacheMiss => 'Cache miss';

  @override
  String get usageHitRate => 'Hit rate';

  @override
  String get usageRequests => 'Requests';

  @override
  String get usageReasoning => 'Reasoning';

  @override
  String get usageByDay => 'By day';

  @override
  String get usageRecent => 'Recent';

  @override
  String get usageEmpty =>
      'Nothing recorded in this range yet — run a model once and it will show up here.';

  @override
  String get usageNoUsageData => 'no usage from upstream';

  @override
  String get usageClear => 'Clear usage';

  @override
  String get usageClearConfirm => 'Clear all recorded token usage?';

  @override
  String get usageCleared => 'Usage cleared';

  @override
  String get usageOpen => 'View token stats';

  @override
  String get usageCalendar => 'Usage calendar';

  @override
  String get usageCalendarOpen => 'Calendar';

  @override
  String get usageCalendarIntro =>
      'Tap a day to see which models were called that day; tap a card to go back to the stats page with that day.';

  @override
  String get usageCalendarPrevMonth => 'Previous month';

  @override
  String get usageCalendarNextMonth => 'Next month';

  @override
  String get usageCalendarEmptyDay => 'No calls recorded on this day';

  @override
  String usageCalendarDayModels(String date) {
    return '$date activity';
  }

  @override
  String get chatSimTitle => 'Chat simulation';

  @override
  String get chatSimAutoSaved =>
      'Conversations are saved on this device (per model group) and resumed next time.';

  @override
  String get chatSimVoiceInput => 'Voice input';

  @override
  String get chatSimVoiceStop => 'Stop voice input';

  @override
  String get chatSimVoicePreparing =>
      'Offline speech model is being prepared, try again shortly';

  @override
  String get chatSimVoiceUnavailable =>
      'Speech input isn\'t available on this device';

  @override
  String get chatSimAttach => 'Add attachment';

  @override
  String get chatSimAttachImage => 'Image';

  @override
  String get chatSimAttachFile => 'File';

  @override
  String get chatSimAttachUserOnly =>
      'Attachments can only be added to user messages';

  @override
  String get chatSimRemoved => 'Deleted';

  @override
  String get chatSimIntro =>
      'Sends this conversation as a downstream client would, through the local proxy\'s real path (routing / failover / fingerprint / request log). Earlier messages are included. Images go out with the message (switch to text only for text-only lanes); file attachments stay display-only. Long-press a message to delete it.';

  @override
  String get chatSimServerOff => 'The server is not running — start it first.';

  @override
  String get chatSimStartServer => 'Start server';

  @override
  String get chatSimNoModel =>
      'This group exposes no model yet — activate it on the Discover page.';

  @override
  String get chatSimSend => 'Send';

  @override
  String get chatSimSendOnly => 'Send only';

  @override
  String get chatSimSendOnlyDesc =>
      'Fire the request without waiting for a reply';

  @override
  String get chatSimSentOnly => 'Sent (no reply requested)';

  @override
  String get chatSimSendModeOnly => 'Send (no model response)';

  @override
  String get chatSimSendModeHint => 'Long-press to switch';

  @override
  String get chatSimSending => 'Generating…';

  @override
  String get chatSimClear => 'Clear chat';

  @override
  String get chatSimClearConfirm => 'Clear this conversation?';

  @override
  String get chatSimMore => 'More';

  @override
  String get chatSimAvatarTitle => 'Avatar settings';

  @override
  String get chatSimAvatarUser => 'User avatar';

  @override
  String get chatSimAvatarAssistant => 'Assistant avatar';

  @override
  String get chatSimAvatarPick => 'From gallery';

  @override
  String get chatSimAvatarCamera => 'Take photo';

  @override
  String get chatSimAvatarReset => 'Reset to default';

  @override
  String get chatSimAvatarUpdated => 'Avatar updated';

  @override
  String chatSimAvatarFailed(String error) {
    return 'Failed to update avatar: $error';
  }

  @override
  String get callTitleAction => 'Call';

  @override
  String get callTitleVoice => 'Voice call';

  @override
  String get callTitleVideo => 'Video call';

  @override
  String get callStatusCalling => 'Connecting…';

  @override
  String get callStatusEnded => 'Call ended';

  @override
  String get callRecords => 'Call transcript';

  @override
  String get callStatusListening => 'Listening…';

  @override
  String get callStatusThinking => 'Thinking…';

  @override
  String get callStatusSpeaking => 'Speaking…';

  @override
  String get callMic => 'Microphone';

  @override
  String get callMicDone => 'Done speaking';

  @override
  String get callInterrupt => 'Interrupt';

  @override
  String get callVideoNeedOmni => 'Video calls require an Omni model';

  @override
  String get callAsrUnavailable =>
      'Speech recognition unavailable — check microphone permission';

  @override
  String get callMute => 'Mute';

  @override
  String get callUnmute => 'Unmute';

  @override
  String get callSpeakerOn => 'Speaker';

  @override
  String get callSpeakerOff => 'Speaker off';

  @override
  String get callSwitchToVideo => 'Switch to video call';

  @override
  String get callSwitchToVoice => 'Switch to voice call';

  @override
  String get callHangUp => 'Hang up';

  @override
  String get callSettingsTitle => 'Call settings';

  @override
  String get callSettingsOmniHint =>
      'The current model is not an Omni model. Basic voice calls still work; \"Allow interruption\" and \"Allow camera\" require an Omni model.';

  @override
  String get callAllowInterrupt => 'Allow interruption';

  @override
  String get callAllowInterruptDesc =>
      'Interrupt the model while it is speaking (requires an Omni model)';

  @override
  String get callAllowCamera => 'Allow camera';

  @override
  String get callAllowCameraDesc =>
      'Send camera frames to the model during video calls (requires an Omni model)';

  @override
  String get callCameraBlocked => 'Camera access is disabled';

  @override
  String get callVideoStagePlaceholder => 'Camera preview · not connected yet';

  @override
  String get chatSimRegenerate => 'Regenerate';

  @override
  String get chatSimEditTitle => 'Edit message';

  @override
  String get chatSimSave => 'Save';

  @override
  String get chatSimSaveAndSend => 'Save and send';

  @override
  String get chatSimAddMessage => 'Add message';

  @override
  String get chatSimRoleLabel => 'Role';

  @override
  String get chatSimRoleSystem => 'System';

  @override
  String get chatSimRoleUser => 'User';

  @override
  String get chatSimRoleAssistant => 'Assistant';

  @override
  String get chatSimHintInput => 'Type a message (sent as user by default)';

  @override
  String chatSimModelLabel(String model) {
    return 'Requesting model $model';
  }

  @override
  String chatSimMeta(int words, String time) {
    return '$words words · $time';
  }

  @override
  String chatSimServedModel(String model) {
    return 'Served by $model';
  }

  @override
  String chatSimServedModelVia(String lane, String model) {
    return 'Served by $lane (requested $model)';
  }

  @override
  String get characterTitle => 'Character cards';

  @override
  String get characterIntro =>
      'Set a scene for chat simulation: applying a card replaces the system prompt and seeds preset messages.';

  @override
  String get characterDefault => 'Default scene';

  @override
  String get characterDefaultDesc =>
      'Generic assistant (You are a helpful assistant)';

  @override
  String characterPresetCount(int count) {
    return '$count preset pairs';
  }

  @override
  String characterApplied(String name) {
    return 'Applied character: $name';
  }

  @override
  String get characterResetDone => 'Back to the default scene';

  @override
  String get characterCreate => 'New character';

  @override
  String get characterNewTitle => 'New character';

  @override
  String get characterEditTitle => 'Edit character';

  @override
  String get characterNameLabel => 'Name';

  @override
  String get characterNameHint => 'e.g. Seele';

  @override
  String get characterPromptLabel => 'Persona prompt';

  @override
  String get characterPromptHint =>
      'Sent as the system prompt: describe identity, tone and habits';

  @override
  String get characterPresetsLabel => 'Preset dialogue';

  @override
  String get characterPresetsHint =>
      'Seeded into the conversation in order when applied';

  @override
  String get characterPresetUser => 'User';

  @override
  String get characterPresetAssistant => 'Assistant';

  @override
  String get characterAddPreset => 'Add a pair';

  @override
  String get characterBuiltin => 'Built-in';

  @override
  String characterDeleteConfirm(String name) {
    return 'Delete character \"$name\"?';
  }

  @override
  String get characterNeedName => 'Give the character a name first';

  @override
  String get characterActions => 'More actions';

  @override
  String get profileViewJson => 'View JSON';

  @override
  String get profileJsonTitle => 'Group JSON';

  @override
  String get profileJsonBuiltin =>
      'This group is generated in code; below is its current effective content.';

  @override
  String get profileJsonCopy => 'Copy';

  @override
  String get profileJsonExport => 'Export file';

  @override
  String get profileJsonCopied => 'JSON copied';

  @override
  String profileJsonExported(String path) {
    return 'Exported to $path';
  }

  @override
  String profileJsonExportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get fabAdd => 'Add';

  @override
  String get moreAction => 'More actions';

  @override
  String get profileSourceBuiltin => 'Built-in';

  @override
  String get profileSourceUrl => 'Subscription';

  @override
  String get profileSourceFile => 'File';

  @override
  String get profileSourceInline => 'Pasted';

  @override
  String get profileUpdateAvailable => 'Update available';

  @override
  String get profileCustomizedTag => 'Hand-edited';

  @override
  String get profileLanesAction => 'View lanes';

  @override
  String get profileUpdateAction => 'Update now';

  @override
  String get profileDeleteAction => 'Delete profile';

  @override
  String profileDeleteConfirm(String name) {
    return 'Delete “$name”? The upstreams it installed will be removed too.';
  }

  @override
  String profileDeleted(String name) {
    return 'Deleted “$name”';
  }

  @override
  String profileStats(int upstreams, int lanes) {
    return '$upstreams upstreams · $lanes lanes';
  }

  @override
  String get profileNeverUpdated => 'Not updated yet';

  @override
  String profileLastUpdated(String time) {
    return 'Updated $time';
  }

  @override
  String get profilePullHint => 'Pull down to refresh the available model list';

  @override
  String get profileIdConflict =>
      'Upstream id already taken; this profile was not installed';

  @override
  String get profileBuiltinZenSummary =>
      'Keyless access to OpenCode Zen\'s free model lanes; the public name zen-free fails over in order.';

  @override
  String get profileImportTitle => 'Add config profile';

  @override
  String get profileImportTabUrl => 'Subscription URL';

  @override
  String get profileImportTabFile => 'Local file';

  @override
  String get profileImportTabPaste => 'Paste JSON';

  @override
  String get profileImportUrlHint => 'https://example.com/profile.json';

  @override
  String get profileImportPickFile => 'Choose a JSON file';

  @override
  String get profileImportPasteHint => 'Paste the profile JSON here';

  @override
  String get profileImportNote =>
      'A profile only describes where models come from; it never changes the listen port, API keys or access rules.';

  @override
  String get profileImportSubmit => 'Import';

  @override
  String profileImported(String name) {
    return 'Imported “$name”';
  }

  @override
  String get profileFormatEmpty => 'The content is empty';

  @override
  String get profileFormatNotJson =>
      'Not valid JSON (Clash subscriptions are YAML, which isn\'t supported here)';

  @override
  String get profileFormatNotObject => 'The top level must be a JSON object';

  @override
  String get profileFormatUnsupportedSchema =>
      'Unsupported profile schema version';

  @override
  String get profileFormatMissingId =>
      'The profile has no id (and no name to derive one from)';

  @override
  String get profileFormatNoUpstreams => 'The profile declares no upstreams';

  @override
  String get profileFormatDuplicateId =>
      'A profile with that id already exists';

  @override
  String get laneHintNotInstalled =>
      'This profile isn\'t active yet — tap its card on the Discover page first.';

  @override
  String laneFallbackHint(String name) {
    return 'Clients can set model to $name to use the failover route.';
  }

  @override
  String get uiStyleLabel => 'UI style';

  @override
  String get uiStyleNote =>
      'Switches the whole app to a different set of screens';

  @override
  String get uiStyleMaterial => 'Material 3 Expressive';

  @override
  String get uiStyleMiuix => 'Xiaomi HyperOS';

  @override
  String get miuixPullToRefresh => 'Pull down to refresh';

  @override
  String get miuixReleaseToRefresh => 'Release to refresh';

  @override
  String get miuixRefreshing => 'Refreshing…';

  @override
  String get miuixRefreshDone => 'Refreshed';

  @override
  String get navBarStyleLabel => 'Bottom navigation bar';

  @override
  String get navBarStyleNote =>
      'Liquid glass renders natively; plain uses the system navigation bar';

  @override
  String get navBarStyleGlass => 'Liquid glass';

  @override
  String get navBarStylePlain => 'Plain';

  @override
  String get displayIosPushTransitionCorner => 'Transition corner radius';

  @override
  String get displayIosPushTransitionCornerAuto =>
      'Match device screen corners';

  @override
  String get displayIosPushTransitionCornerUnsupported =>
      'This device does not report screen corners; using the manual value below';

  @override
  String get edgeHapticLabel => 'Scroll haptics';

  @override
  String get edgeHapticNote =>
      'Light haptic when flinging to the top or bottom of a list';

  @override
  String get shortcutStartService => 'Start service';

  @override
  String get shortcutStopService => 'Stop service';

  @override
  String get shortcutTokenStats => 'View token usage';

  @override
  String get tasksDialogTitle => 'Tasks';

  @override
  String get taskPauseServer => 'Pause server';

  @override
  String taskListenOn(String address) {
    return 'Listening on $address';
  }

  @override
  String get taskStopListening => 'Stop listening';

  @override
  String get tasksRecentSection => 'Recent';

  @override
  String tasksModelCount(int count) {
    return '$count models';
  }

  @override
  String get createConfigScanTitle => 'Scan QR code';

  @override
  String get createConfigScanDesc =>
      'Add configs by scanning or picking a photo';

  @override
  String get qrScannerTitle => 'Scan QR code';

  @override
  String get qrScannerHint => 'Point anywhere at a QR code to scan it';

  @override
  String get qrScannerPermissionTitle => 'Camera permission required';

  @override
  String get qrScannerPermissionDesc =>
      'Scanning needs the camera. Allow camera access for this app in system settings.';

  @override
  String get qrScannerOpenSettings => 'Open settings';

  @override
  String get qrScannerRetry => 'Retry';

  @override
  String get qrScannerUnsupported =>
      'QR scanning is only available on Android / iOS';

  @override
  String get qrScannerSwitchCamera => 'Switch camera';

  @override
  String get qrScannerGallery => 'Scan from photo';

  @override
  String get qrScannerGalleryEmpty => 'No QR code found in that photo';

  @override
  String get qrResultTitle => 'Scan result';

  @override
  String get qrResultKindProfile => 'Config profile JSON';

  @override
  String get qrResultKindUpstream => 'Upstream JSON';

  @override
  String get qrResultKindUrl => 'Link';

  @override
  String get qrResultKindText => 'Text';

  @override
  String get qrResultImportProfile => 'Import profile';

  @override
  String get qrResultAddUpstream => 'Add as upstream';

  @override
  String get qrResultImportUrl => 'Import subscription';

  @override
  String qrResultUpstreamAdded(String name) {
    return 'Added upstream “$name”';
  }

  @override
  String get upstreamQrTitle => 'Upstream QR code';

  @override
  String get upstreamQrHint =>
      'Scan this with another device running this app to add the upstream to its rules.';

  @override
  String get upstreamQrTooLong => 'Too much data to fit into a QR code';

  @override
  String get progressiveTopBarTitle => 'Gradient blur top bar';

  @override
  String get progressiveTopBarDesc =>
      'Transparent top bar with a progressive blur that fades in as content scrolls under';

  @override
  String get navBarStyleFloating => 'Floating';

  @override
  String get biometricLockTitle => 'Biometric lock';

  @override
  String get biometricLockDesc =>
      'Require fingerprint or face to open the app (Android)';

  @override
  String get biometricLockUnavailable =>
      'No biometrics or screen-lock credential available on this device';

  @override
  String get biometricGateTitle => 'Local2API is locked';

  @override
  String get biometricGateHint => 'Verify your identity to continue';

  @override
  String get biometricUnlock => 'Unlock';

  @override
  String get networkTitle => 'Network';

  @override
  String get networkEntryDesc => 'Cloudflare Tunnel / Tailscale';

  @override
  String get cfTitle => 'Cloudflare Tunnel';

  @override
  String get cfDesc =>
      'Expose this server to the internet via a temporary trycloudflare tunnel';

  @override
  String get cfEnableSwitch => 'Enable trycloudflare';

  @override
  String get cfTermsTitle => 'Cloudflare license agreement';

  @override
  String get cfTermsAgree => 'Agree and enable';

  @override
  String get cfTermsDecline => 'Decline';

  @override
  String get cfTermsFetchFailed =>
      'Failed to fetch the license agreement. Check your network and retry.';

  @override
  String get cfTermsNote =>
      'Cloudflare\'s terms of service (trycloudflare.com) must be accepted before enabling.';

  @override
  String get cfStarting => 'Starting the tunnel…';

  @override
  String get cfRunning => 'Tunnel is running';

  @override
  String get cfStopped => 'Not running';

  @override
  String get cfPublicUrl => 'Public URL';

  @override
  String get cfBinaryMissing =>
      'cloudflared not found. The built-in tunnel is desktop-only for now — install cloudflared in PATH and retry.';

  @override
  String get cfRetry => 'Retry';

  @override
  String get cfStop => 'Stop';

  @override
  String get tsTitle => 'Tailscale';

  @override
  String get tsDesc => 'Reach this server over Tailscale (100.64.0.0/10 range)';

  @override
  String get tsAllowSwitch => 'Allow the Tailscale range';

  @override
  String tsDetected(String ip) {
    return 'Tailscale IP detected: $ip';
  }

  @override
  String get tsNotDetected =>
      'No Tailscale interface detected (not installed or not connected)';

  @override
  String get tsDownloadTitle => 'Get Tailscale';

  @override
  String get tsDownloadDesc =>
      'Install Tailscale on your phones and computers to reach this server from anywhere';

  @override
  String get tsOpenDownload => 'Open download page';

  @override
  String get securitySection => 'Security';

  @override
  String get webUiTitle => 'Temporary Web UI';

  @override
  String get webUiDesc =>
      'A browser console on its own port, separate from the API proxy';

  @override
  String get webUiEnable => 'Enable temporary Web UI';

  @override
  String get webUiToggleHint =>
      'Turning it off stops the web server only; the API proxy is unaffected';

  @override
  String get webUiPort => 'Web UI port';

  @override
  String get webUiHost => 'Web UI bind address';

  @override
  String get webUiRunning => 'Web UI running';

  @override
  String get webUiStopped => 'Web UI stopped';

  @override
  String get webUiFailed => 'Web UI failed to start';

  @override
  String get webUiOpen => 'Open in browser';

  @override
  String get webUiCopyUrl => 'Copy address';

  @override
  String get webUiEntryDesc => 'Port, switch and browser entry';

  @override
  String get webUiNote =>
      'Requests from the page still hit the API port; the two ports never collide';

  @override
  String get scheduleTitle => 'Peak / off-peak windows';

  @override
  String get scheduleEntryDesc =>
      'Restrict a model or model group by weekday and hour';

  @override
  String get scheduleDesc =>
      'Positive: usable only inside the selected window. Negative: blocked inside it. Chat simulation is never affected.';

  @override
  String get scheduleEmpty =>
      'No rules yet — without a rule a model is always available';

  @override
  String get scheduleAdd => 'Add rule';

  @override
  String get scheduleTarget => 'Applies to';

  @override
  String get scheduleTargetModel => 'Single model';

  @override
  String get scheduleTargetGroup => 'Model group';

  @override
  String get scheduleModel => 'Model';

  @override
  String get scheduleGroup => 'Model group';

  @override
  String get scheduleMode => 'Rule direction';

  @override
  String get scheduleModeAllow => 'Positive (usable only in the window)';

  @override
  String get scheduleModeDeny => 'Negative (blocked in the window)';

  @override
  String get scheduleWeekdays => 'Weekdays';

  @override
  String get scheduleSelectAll => 'Select all';

  @override
  String get scheduleUpstreamHint =>
      'Applies to this upstream\'s models only — select all to cover the whole upstream. Changes take effect immediately, no save needed.';

  @override
  String get scheduleUpstreamNoModel =>
      'This upstream has no exposed models yet — add some under Exposed models first.';

  @override
  String get schedulePickWeekday => 'Pick weekday';

  @override
  String get scheduleHours => 'Time window';

  @override
  String scheduleHourRange(String start, String end) {
    return '$start:00 - $end:00';
  }

  @override
  String get scheduleEnabled => 'Enable this rule';

  @override
  String get scheduleDelete => 'Delete rule';

  @override
  String get scheduleSaved => 'Rule saved';

  @override
  String get scheduleDeleted => 'Rule deleted';

  @override
  String get scheduleSimNote =>
      'Chat simulation stays usable regardless of these rules';

  @override
  String get schedulePickTarget => 'Pick a model or model group';

  @override
  String get schedulePickHour => 'Pick an hour';

  @override
  String get scheduleStartHour => 'From';

  @override
  String get scheduleEndHour => 'Until';

  @override
  String get scheduleAllDay => 'All day';

  @override
  String scheduleStatus(String count) {
    return '$count rules';
  }

  @override
  String get modelContextLabel => 'Max context tokens';

  @override
  String get modelContextHelper =>
      'Context tokens advertised to clients; empty falls back to 1M and is auto-filled when fetching models';

  @override
  String modelContextShort(String value) {
    return 'Context $value';
  }

  @override
  String contextAutoFilled(String count) {
    return 'Fetched context length for $count models from upstream';
  }

  @override
  String get modelOutputLabel => 'Max output tokens';

  @override
  String get modelOutputHelper =>
      'Max output tokens advertised to clients; leave empty to omit';

  @override
  String contextRingInfo(String percent, String used, String total) {
    return 'Context usage $percent% ($used / $total tokens)';
  }

  @override
  String get contextRingEstimated => ', estimated from text length';

  @override
  String get contextRingTap => 'Tap to see context usage';

  @override
  String get contextDetailTitle => 'Context usage';

  @override
  String contextDetailPercent(String percent) {
    return '$percent% of the context';
  }

  @override
  String contextDetailUsed(String used, String total) {
    return '$used / $total tokens';
  }

  @override
  String get contextDetailFromUsage =>
      'From the last response\'s usage (exact)';

  @override
  String get contextDetailEstimated =>
      'Estimated from text and images (no usage returned)';

  @override
  String contextDetailOutput(String limit) {
    return 'Max output $limit tokens';
  }

  @override
  String get contextDetailOutputNone => 'Max output not declared';

  @override
  String contextDetailModel(String model) {
    return 'Request model $model';
  }

  @override
  String contextDetailMessages(String count, String images) {
    return '$count messages · $images images';
  }

  @override
  String get contextDetailClose => 'Got it';

  @override
  String get chatSimSendImages => 'Send images';

  @override
  String get chatSimSendTextOnly => 'Text only';

  @override
  String get chatSimSendImagesTip =>
      'Images are sent as multimodal content. Switch to text only when a text-only lane rejects the request.';

  @override
  String get chatSimImagesOn => 'Images will be sent with the message';

  @override
  String get chatSimImagesOff => 'Images stay local and are not sent';

  @override
  String get chatSimAttachCamera => 'Take a photo';

  @override
  String chatSimAttachFailed(String error) {
    return 'Failed to read attachment: $error';
  }

  @override
  String get chatSimVoiceNoPermission =>
      'Microphone permission is required for voice input';

  @override
  String get chatSimVoiceOpenSettings => 'Open settings';

  @override
  String chatSimVoiceFailed(String error) {
    return 'Voice input failed: $error';
  }

  @override
  String get voiceHoldToTalk => 'Hold to talk';

  @override
  String get voiceReleaseToSend => 'Release to finish';

  @override
  String get voiceListeningHint => 'Listening…';

  @override
  String get voiceRecognizing => 'Recognizing…';

  @override
  String get voiceNothingHeard => 'Nothing heard, hold and try again';

  @override
  String chatSimCallPeer(String name) {
    return 'Call $name';
  }

  @override
  String get chatSimMsgMenuTitle => 'Message actions';

  @override
  String get chatSimMsgSpeak => 'Read aloud';

  @override
  String get chatSimMsgStopSpeak => 'Stop reading';

  @override
  String get chatSimMsgRegenerate => 'Regenerate';

  @override
  String get chatSimMsgDownload => 'Download audio';

  @override
  String get chatSimDownloadTitle => 'Download audio';

  @override
  String get chatSimDownloadFormat => 'Format';

  @override
  String get chatSimDownloadMp3Desc => 'Universal audio, widest compatibility';

  @override
  String get chatSimDownloadSilkDesc =>
      'SILK v3 — the WeChat / QQ voice format';

  @override
  String get chatSimDownloadSlkDesc =>
      'Same bytes as SILK, different extension';

  @override
  String get chatSimDownloadTencent => 'Tencent compatible (-tencent)';

  @override
  String get chatSimDownloadTencentDesc =>
      'Adds a 0x02 header byte and drops the trailing sentinel packet; WeChat / QQ will not play it otherwise';

  @override
  String get chatSimDownloadAction => 'Download';

  @override
  String get chatSimDownloadBusy => 'Synthesizing audio…';

  @override
  String get chatSimDownloadCanceled => 'Save canceled';

  @override
  String chatSimDownloadSaved(String path) {
    return 'Saved: $path';
  }

  @override
  String chatSimDownloadFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get balanceTitle => '餘額';

  @override
  String get balanceEntryDesc => '查詢這個上游的帳戶餘額';

  @override
  String get balancePullHint => 'Pull down to refresh the balance';

  @override
  String get balanceRefreshing => '查詢中…';

  @override
  String get balanceNoKey => '先填金鑰再查餘額';

  @override
  String get balanceUnsupported => '該上游不支援餘額查詢';

  @override
  String get balanceNoData => '沒有回傳餘額';

  @override
  String get balanceAvailableLabel => '可用餘額';

  @override
  String get balanceGrantedLabel => '贈送餘額';

  @override
  String get balanceToppedUpLabel => '充值餘額';

  @override
  String get balanceUsedLabel => '已用額度';

  @override
  String get balanceRequestsLabel => '累計請求';

  @override
  String get balanceGroupLabel => '分組';

  @override
  String get balanceSourceLabel => '查詢介面';

  @override
  String get balanceStatusOk => '帳戶可正常呼叫';

  @override
  String get balanceStatusBad => '帳戶不可用（欠費或受限）';

  @override
  String get balanceQuotaNote => '按 1 美元 = 500000 額度換算';

  @override
  String balanceFailed(String error) {
    return '查詢失敗：$error';
  }

  @override
  String balanceUpdatedAt(String time) {
    return '上次更新 $time';
  }

  @override
  String get balanceDetailsTitle => '餘額明細';

  @override
  String get balanceLimitLabel => '額度上限';

  @override
  String get balanceUnauthorized => '金鑰無效或無權讀取帳戶';

  @override
  String get balanceBadResponse => '餘額介面回傳的內容無法解讀';

  @override
  String get balanceNoKeyHint => '填好金鑰後再重新整理';

  @override
  String get balanceUnauthorizedHint => '確認金鑰有效，且允許讀取帳戶資訊';

  @override
  String get balanceUnsupportedHint => '不是所有上游都有餘額介面';

  @override
  String get balanceNetworkHint => '檢查本機能否連線該位址，稍後重試';

  @override
  String get thinkingDefaultLabel => '預設思考檔位';

  @override
  String get thinkingDefaultOff => '不干預';

  @override
  String get thinkingLevelLow => '精簡';

  @override
  String get thinkingLevelMedium => '均衡';

  @override
  String get thinkingLevelHigh => '深思';

  @override
  String get thinkingWireLabel => '檔位下發格式';

  @override
  String get thinkingWireBudget => '只壓輸出預算';

  @override
  String get thinkingWireEffort => 'reasoning_effort';

  @override
  String get thinkingWireThinking => 'thinking 開關';

  @override
  String get thinkingWireBoth => '兩者都發';

  @override
  String get logsFilterAll => 'All';

  @override
  String get logsFilterPassed => 'Passed';

  @override
  String get logsFilterFailed => 'Failed';

  @override
  String get logsEmptyFiltered => 'No requests match this filter';

  @override
  String get activeConnectionsTitle => 'Active connections';

  @override
  String get activeConnectionsEmpty => 'No active connections right now';

  @override
  String get activeConnDuration => 'Elapsed';

  @override
  String get activeConnStarted => 'Started at';

  @override
  String get activeConnPath => 'Path';

  @override
  String get tsOpenApp => 'Open Tailscale';

  @override
  String get tsInstalledDesc =>
      'Tailscale is installed — tap to open the client';

  @override
  String get tsOpenFailed =>
      'Could not open Tailscale, opened the download page instead';

  @override
  String get usageCalendarBackToday => 'Back to today';

  @override
  String get thinkingLevelNone => 'Off';

  @override
  String get thinkingLevelMinimal => 'Minimal';

  @override
  String get thinkingLevelXhigh => 'Extra high';

  @override
  String get thinkingLevelMax => 'Max';

  @override
  String get winCloseSection => 'Desktop window';

  @override
  String get winCloseBehaviorTitle => 'Close button action';

  @override
  String get winCloseAsk => 'Ask every time';

  @override
  String get winCloseTray => 'Minimize to tray';

  @override
  String get winCloseExit => 'Quit the app';

  @override
  String get winCloseAskSummary =>
      'Always confirm (you can tick \"do this from now on\")';

  @override
  String get winCloseTraySummary =>
      'Hide the window, keep forwarding in the background';

  @override
  String get winCloseExitSummary => 'Quit entirely — forwarding stops too';

  @override
  String get winCloseDialogTitle => 'Local2API';

  @override
  String get winCloseDialogHeading =>
      'You clicked the close button. What would you like?';

  @override
  String get winCloseDialogContent =>
      'Minimizing to tray keeps forwarding in the background — bring the window back any time from the tray icon.';

  @override
  String get winCloseLinkTray => 'Minimize to tray';

  @override
  String get winCloseLinkTraySubtitle =>
      'Hide the window, keep the service running';

  @override
  String get winCloseLinkExit => 'Quit the app';

  @override
  String get winCloseLinkExitSubtitle => 'Stops the forwarding service as well';

  @override
  String get winCloseRemember => 'Do this from now on';

  @override
  String get winTrayShow => 'Show main window';

  @override
  String get winTrayQuit => 'Quit Local2API';

  @override
  String get thinkingWireHint =>
      'If the upstream rejects this level, it steps down automatically (max → xhigh → … → not sent)';

  @override
  String get typeAnthropic => 'Anthropic Messages';

  @override
  String get trayHintBody => 'Hey, I\'m right here';

  @override
  String get trayHintDismiss => 'Don\'t show again';

  @override
  String get trayHintSettings => 'Settings';

  @override
  String get winTrayHintTitle => 'Show a hint when minimizing to tray';

  @override
  String get winTrayHintSummary =>
      'Show a system notification with \"Don\'t show again\" and \"Settings\" buttons';

  @override
  String get settingsLabTitle => 'Lab';

  @override
  String get settingsLabDesc =>
      'Install SillyTavern locally, built-in browser and other experiments';

  @override
  String get labTitle => 'Lab';

  @override
  String get labSubtitle => 'Local services and experimental features';

  @override
  String get labLocalServices => 'Local services';

  @override
  String get labSillyTavernDesc =>
      'Local AI roleplay frontend (Node.js); open it in the app when ready';

  @override
  String get labInstall => 'Install';

  @override
  String get labInstalled => 'Installed';

  @override
  String get labNotInstalled => 'Not installed';

  @override
  String get labRunning => 'Running';

  @override
  String get labStart => 'Start';

  @override
  String get labStop => 'Stop';

  @override
  String get labOpen => 'Open';

  @override
  String get labOpenFolder => 'Open folder';

  @override
  String get labUninstall => 'Uninstall';

  @override
  String get labUninstallTitle => 'Uninstall SillyTavern?';

  @override
  String get labUninstallBody =>
      'Downloaded program files (including character cards and chats under data) will be deleted permanently.';

  @override
  String get labInstallLocation => 'Install location';

  @override
  String get labChooseLocation => 'Choose location';

  @override
  String get labDefaultLocation => 'Default location';

  @override
  String get labNodeStatus => 'Node.js';

  @override
  String get labNodeMissing => 'Node.js not found';

  @override
  String get labNodeMissingHint =>
      'Install Node.js 18+ and tap Recheck to start; files can be installed first.';

  @override
  String get labNodeDownload => 'Download Node.js';

  @override
  String get labRecheck => 'Recheck';

  @override
  String get labInstallDeps => 'Install dependencies';

  @override
  String get labMobileNoRun =>
      'Node.js services cannot run on mobile; files are installed in the app directory and can be run via Termux.';

  @override
  String get labNodeRuntimeTitle => 'Node.js runtime';

  @override
  String get labNodeRuntimeDesc =>
      'Installs the Android build of Node.js (with npm) from the Termux repository. Required to run lab services on this device.';

  @override
  String get labNodeRuntimeInstall => 'Install Node.js';

  @override
  String get labNodeRuntimeReinstall => 'Reinstall';

  @override
  String get labNodeRuntimeRemove => 'Uninstall Node.js';

  @override
  String get labNodeRuntimeNotInstalled => 'Not installed';

  @override
  String get labNodeRunnerMode => 'Run mode';

  @override
  String get labRunnerDirect => 'Direct';

  @override
  String get labRunnerDirectDesc =>
      'Start processes as the app itself (works in debug builds; blocked by the system in release builds)';

  @override
  String get labRunnerShizuku => 'Shizuku';

  @override
  String get labRunnerShizukuDesc =>
      'Start processes as shell via Shizuku (recommended for release; requires Shizuku installed and authorized)';

  @override
  String get labNodeMirror => 'Download mirror';

  @override
  String get labMirrorOfficial => 'Official';

  @override
  String get labMirrorOfficialDesc =>
      'packages.termux.dev · registry.npmjs.org (very slow from mainland China; for proxied networks)';

  @override
  String get labMirrorCn => 'China mainland mirror';

  @override
  String get labMirrorCnDesc =>
      'TUNA termux mirror · npmmirror (fast direct connection in mainland China)';

  @override
  String get labShizukuStatus => 'Shizuku status';

  @override
  String get labShizukuNotDetected =>
      'Shizuku not detected (not installed or not running)';

  @override
  String get labShizukuGranted => 'Granted';

  @override
  String get labShizukuNotGranted => 'Not granted';

  @override
  String get labShizukuRequest => 'Grant Shizuku permission';

  @override
  String get labExecBlocked =>
      'The system blocks executing Node directly; switch to Shizuku mode';

  @override
  String get labVisibleDesc =>
      'The lab entry appears here only after you enable it manually';

  @override
  String get labOpenLab => 'Open lab';

  @override
  String get labDownloading => 'Downloading';

  @override
  String get labExtracting => 'Extracting';

  @override
  String get labInstallingDeps => 'Installing dependencies';

  @override
  String get labStarting => 'Starting';

  @override
  String get labLogs => 'Logs';

  @override
  String get labClearLogs => 'Clear';

  @override
  String get labVersion => 'Version';

  @override
  String get labPhaseIdle => 'Ready';

  @override
  String get labBrowserTools => 'Built-in tools';

  @override
  String get labBrowserTitle => 'Built-in browser';

  @override
  String get labBrowserDesc =>
      'Open local WebUI, SillyTavern or any URL inside the app';

  @override
  String get labOpenBrowser => 'Open browser';

  @override
  String get labManualUrl => 'Enter a URL, e.g. 127.0.0.1:8000';

  @override
  String get labGo => 'Go';

  @override
  String get labError => 'Something went wrong';

  @override
  String get labCancel => 'Cancel';

  @override
  String get browserTitle => 'Browser';

  @override
  String get browserEditUrl => 'Edit address';

  @override
  String get browserUrlHint => 'https://example.com';

  @override
  String get browserGo => 'Go';

  @override
  String get browserBack => 'Back';

  @override
  String get browserForward => 'Forward';

  @override
  String get browserReload => 'Reload';

  @override
  String get browserStop => 'Stop';

  @override
  String get browserMenu => 'More';

  @override
  String get browserCopyLink => 'Copy link';

  @override
  String get browserCopyCookie => 'Copy cookies';

  @override
  String get browserCookieEmpty => 'No cookies to copy on this page';

  @override
  String get browserCookieCopied => 'Cookies copied';

  @override
  String get browserUaLabel => 'User agent';

  @override
  String get browserUaAuto => 'Auto';

  @override
  String get browserUaDesktop => 'Desktop';

  @override
  String get browserUaMobile => 'Mobile';

  @override
  String get browserOpenExternal => 'Open in system browser';

  @override
  String browserInitFailed(String error) {
    return 'Failed to load page: $error';
  }

  @override
  String get browserUnsupported =>
      'Built-in browser is not supported on this platform; use the system browser';

  @override
  String get browserRetry => 'Retry';

  @override
  String get commonBack => 'Back';

  @override
  String get close => 'Close';

  @override
  String get labMoreSettings => 'More settings';

  @override
  String get labInstallFirstTitle => 'SillyTavern isn\'t installed yet';

  @override
  String get labInstallFirstBody =>
      'Install it under \"More settings\", then come back and flip this switch.';

  @override
  String get labGoSettings => 'Open settings';

  @override
  String get labStartFailed => 'Failed to start';

  @override
  String get labStopped => 'Stopped';

  @override
  String get labSectionStatus => 'Status';

  @override
  String get labSectionInstall => 'Installation';

  @override
  String get labApiConfig => 'API';

  @override
  String get labApiGroup => 'Model group';

  @override
  String get labApiGroupNone => 'Not selected';

  @override
  String get labApiModel => 'Model';

  @override
  String get labApiBaseUrl => 'Base URL';

  @override
  String get labApiKey => 'API key';

  @override
  String get labApiNoKey =>
      'No enabled API key yet — create one on the Keys page';

  @override
  String get labApiWrite => 'Write to SillyTavern';

  @override
  String get labApiWriteOk => 'Written — reload the SillyTavern page to apply';

  @override
  String labApiWriteFailed(String error) {
    return 'Write failed: $error';
  }

  @override
  String get labApiNeedGroup =>
      'Enable a model group on the Discover page first';

  @override
  String get labApiNeedService =>
      'Local service isn\'t reachable — start it from the dashboard';

  @override
  String get labApiNoUserData =>
      'SillyTavern has never been started; start it once first';

  @override
  String get labApiPickGroup => 'Pick a model group';

  @override
  String get labApiPickModel => 'Pick a model';

  @override
  String labApiModelCount(String count) {
    return '$count models';
  }

  @override
  String get labLogsEmpty => 'No logs yet';

  @override
  String get labCopyLogs => 'Copy logs';

  @override
  String get labLogsCopied => 'Logs copied';

  @override
  String get browserClosePage => 'Close page';

  @override
  String get browserShareQr => 'Share QR code';

  @override
  String get browserQrTitle => 'Scan to open on your phone';

  @override
  String get browserViewCookies => 'View cookies';

  @override
  String get browserCopyAll => 'Copy all';

  @override
  String get browserClipboardAccess => 'Allow clipboard writes';

  @override
  String get browserClipboardAllowed => 'Clipboard access allowed';

  @override
  String get browserClipboardBlocked => 'Clipboard access blocked';

  @override
  String get browserSetUa => 'Custom user agent';

  @override
  String get browserUaEmptyHint =>
      'Leave empty to restore the default; the page reloads on apply';

  @override
  String get browserApplyAndReload => 'Apply and reload';

  @override
  String get browserUaUpdated => 'User agent updated';

  @override
  String get browserTroubleshootNetwork => 'Network troubleshooter';

  @override
  String get browserTroubleshootFailed =>
      'Can\'t open the system troubleshooter';

  @override
  String get browserAndroidErrorTitle => 'System WebView crashed';

  @override
  String get browserAndroidErrorCause => 'Possible cause';

  @override
  String get browserAndroidErrorDetail =>
      'The system WebView is outdated or disabled, so the built-in browser can\'t start.';

  @override
  String get browserUpdateWebview => 'Update Android System WebView';

  @override
  String get browserOpenDevOptions =>
      'Open developer options (WebView implementation)';

  @override
  String get browserAppleErrorTitle => 'Built-in browser couldn\'t start';

  @override
  String get browserAppleErrorReport => 'Error report';

  @override
  String get browserAppleErrorDetail =>
      'WKWebView failed to initialize — usually an old OS version or an enterprise policy.';

  @override
  String get browserBsodMessage =>
      'Your built-in browser ran into a problem and needs to restart.';

  @override
  String get browserBsodNoRestart =>
      'We\'re just collecting some error info, and then we\'ll restart for you.';

  @override
  String get browserBsodComplete => '0% complete';

  @override
  String get browserBsodSolutions => 'Try these:';

  @override
  String get browserBsodDownload => 'Download Microsoft Edge WebView2 Runtime';

  @override
  String get browserBsodWinUpdate => 'Open Windows Update';

  @override
  String get browserBsodScanQr => 'Scan to open the WebView2 download page';

  @override
  String get browserBsodStopCode => 'Stop code: WEBVIEW2_NOT_INSTALLED';

  @override
  String get labStatus => 'Status';

  @override
  String get browserUaHint => 'Paste a full user agent string';

  @override
  String get labApiStopFirst =>
      'Stop SillyTavern before writing — a running instance overwrites this file';

  @override
  String get labAutoOpenBrowser => 'Open the browser on start';

  @override
  String get labAutoOpenBrowserDesc =>
      'When off, SillyTavern will not launch your system browser; use Open to enter manually';

  @override
  String get labDshTitle => 'DeepSeek Harness';

  @override
  String get labDshInstallFirstTitle => 'DeepSeek Harness is not installed';

  @override
  String get labDshInstallFirstBody =>
      'Install it in More settings first, then come back and flip this switch.';

  @override
  String get labDshUninstallTitle => 'Uninstall DeepSeek Harness?';

  @override
  String get labDshUninstallBody =>
      'This removes the npm-installed dsh files. Model config and chats stay in ~/.dsh.';

  @override
  String get labDshPickModels => 'Models to add to dsh';

  @override
  String get labDshDefaultModel => 'Default model';

  @override
  String get labDshPickDefault => 'Pick the default model';

  @override
  String get labDshWrite => 'Write dsh config';

  @override
  String get labDshWriteOk => 'dsh config written';

  @override
  String get labDshNeedModels =>
      'Pick a model group and select at least one model first';

  @override
  String get labDshWriteHint =>
      'dsh hot-reloads the model list; if it is running the app restarts it so the new key takes effect';

  @override
  String get labDshConfigPath => 'Config file';

  @override
  String get labDshOpenInApp => 'Open in app';

  @override
  String get labDshCompat => 'Android compatibility layer';

  @override
  String get labDshCompatDesc =>
      'Turns off the sandbox and pwsh integrations that cannot start on Android';

  @override
  String get browserSelectTitle => 'Select';

  @override
  String get browserOpenCustomTab => 'Open in Custom Tabs';

  @override
  String get browserCustomTabPick => 'Open with';

  @override
  String get browserCustomTabAuto => 'Automatic (system default)';

  @override
  String get browserCustomTabNone => 'No Custom Tabs browser installed';

  @override
  String get browserCustomTabFailed => 'Couldn\'t open this link';

  @override
  String get reply => 'Reply';

  @override
  String get labNotifySection => 'Notifications';

  @override
  String get labNotifyPermission => 'Notification permission';

  @override
  String get labNotifyPermissionDesc =>
      'Task progress, questions and results are delivered as notifications';

  @override
  String get labNotifyLiveUpdate => 'Live update';

  @override
  String get labNotifyLiveUpdateDesc =>
      'Android 16+ pins task progress to the shade, lock screen and status bar';

  @override
  String get labNotifyPromoted => 'Live updates are allowed';

  @override
  String get labNotifyNotPromoted => 'Not promoted to a live update right now';

  @override
  String get labNotifyBattery => 'Ignore battery optimization';

  @override
  String get labNotifyBatteryDesc =>
      'Lets node / dsh keep running in the background';

  @override
  String get labNotifyBatteryIgnored => 'Already ignoring battery optimization';

  @override
  String get labNotifyOpenSettings => 'System notification settings';

  @override
  String get labNotifyTest => 'Send a test notification';

  @override
  String get labNotifyTestSent => 'Test notification posted';

  @override
  String get labNotifyTestFailed => 'Not posted (check permission)';

  @override
  String get labDshTaskHint => 'Task prompt';

  @override
  String get labDshTaskHintDesc =>
      'Makes the model report step by step and stop to ask when it must';

  @override
  String get labDshPlugins => 'Plugins';

  @override
  String get labDshPluginMessageEdit => 'Edit messages';

  @override
  String get labDshPluginMessageEditDesc =>
      'Adds a pencil button to sent messages; edit and resend from the previous turn (dsh-message-edit)';

  @override
  String get labDshPluginComputerUse => 'Computer use mode';

  @override
  String get labDshPluginComputerUseDesc =>
      'Screenshots plus mouse and keyboard control in the new Computer use preset (dsh-computer-use-mode)';

  @override
  String get labDshPluginAndroid => '手机操作';

  @override
  String get labDshPluginAndroidDesc =>
      'Control this phone: screenshots, taps, swipes, UI tree, OCR, logcat (@zseven-w/dsh-android)';

  @override
  String get labDshPluginInstalling => 'Installing…';

  @override
  String get labDshPluginFailed => 'Plugin operation failed';

  @override
  String get labDshPluginRestartHint =>
      'Toggling restarts DSH automatically so the plugin takes effect';

  @override
  String get labDshRunTask => 'Run task';

  @override
  String get labDshRunTaskDesc =>
      'Hand a one-line task to dsh; progress and result go to notifications';

  @override
  String get labDshTaskPrompt => 'What should dsh do?';

  @override
  String get labDshTaskBusy => 'A task is already running';

  @override
  String get labDshTaskStarted => 'Task started; watch the notification';

  @override
  String get labDshTaskDone => 'Task finished';

  @override
  String get labDshTaskFailed => 'Task failed';

  @override
  String get labDshTaskCancelled => 'Task cancelled';

  @override
  String labDshTaskSteps(String done, String total) {
    return 'Step $done/$total';
  }

  @override
  String get labDshAgentDone => 'Agent finished this turn';

  @override
  String get labDshNeedAnswer => 'dsh is waiting for your answer';

  @override
  String get labDshAnswerHint => 'Open dsh web to answer';

  @override
  String get labDshToastReplyHint => 'Type a reply';

  @override
  String get labDshToastOptionsHint =>
      'Type 1-3 to choose; anything else is sent as your answer';

  @override
  String get labDshToastSkip => 'Skip';

  @override
  String get autoRefreshTitle => 'Auto-update models';

  @override
  String get autoRefreshOff => 'Off';

  @override
  String get autoRefreshEvery1d => 'Daily';

  @override
  String get autoRefreshEvery3d => 'Every 3 days';

  @override
  String get autoRefreshEvery7d => 'Every 7 days';

  @override
  String get autoRefreshEvery30d => 'Every 30 days';

  @override
  String get autoRefreshDesc =>
      'Pull the model list on a schedule: new models are added, delisted ones removed';

  @override
  String get autoRefreshNever => 'Never refreshed';

  @override
  String get autoRefreshJustNow => 'Refreshed just now';

  @override
  String autoRefreshNextIn(String when) {
    return 'Next in $when';
  }

  @override
  String get autoRefreshRefreshing => 'Refreshing…';

  @override
  String autoRefreshDone(String added, String removed) {
    return 'Model list updated: $added added, $removed removed';
  }

  @override
  String get autoRefreshNoChange => 'Model list is already up to date';

  @override
  String get autoRefreshRefreshNow => 'Refresh now';

  @override
  String get autoRefreshFailed => 'Refresh failed';

  @override
  String get pluginManagerTitle => 'dsh plugins';

  @override
  String get pluginManagerRefresh => 'Rescan';

  @override
  String get pluginManagerSubtitle => 'Install, enable, and remove dsh plugins';

  @override
  String get pluginManagerSearch => 'Search plugins';

  @override
  String get pluginManagerInstall => 'Install';

  @override
  String get pluginManagerInstallTitle => 'Install a third-party plugin';

  @override
  String get pluginManagerPackageHint =>
      'npm package name, e.g. @scope/dsh-plugin-xxx';

  @override
  String get pluginManagerPackageEmpty => 'Enter a package name first';

  @override
  String get pluginManagerInstalling => 'Installing…';

  @override
  String get pluginManagerUninstall => 'Uninstall';

  @override
  String pluginManagerUninstallConfirm(String name) {
    return 'Uninstall $name? It will be removed from dsh.';
  }

  @override
  String pluginManagerExitConfirm(String name) {
    return 'Disable $name? The downloaded package is kept, re-enabling needs no reinstall.';
  }

  @override
  String get pluginManagerRestartHint =>
      'Plugin changes take effect after dsh restarts';

  @override
  String get pluginManagerDescTitle => 'Third-party plugins';

  @override
  String get pluginManagerEmpty => 'No plugins installed yet';

  @override
  String get pluginManagerNotReady =>
      'dsh is not installed yet — install dsh first';

  @override
  String pluginManagerInstalledCount(String count) {
    return '$count enabled';
  }

  @override
  String get pluginManagerInstalledBadge => 'Installed';

  @override
  String get pluginManagerCustom => 'Third-party';

  @override
  String get pluginManagerOfficial => 'Built-in';

  @override
  String get pluginManagerLocal => 'Local directory';

  @override
  String get pluginManagerAddLocal => 'Install from a local directory';

  @override
  String get pluginManagerNoMatch => 'No matching plugins';

  @override
  String get pluginManagerSearchClear => 'Clear search';

  @override
  String get pluginManagerExpand => 'Expand';

  @override
  String get pluginManagerCollapse => 'Collapse';

  @override
  String pluginManagerOnlyOn(String platform) {
    return '$platform only';
  }

  @override
  String get pluginManagerNotInstalled => 'Not installed';

  @override
  String get pluginManagerDisabled => 'Disabled';

  @override
  String get pluginManagerEnabledState => 'Enabled';

  @override
  String pluginManagerOverview(String enabled, String total) {
    return '$enabled enabled · $total total';
  }

  @override
  String get usageApiKeyFilter => 'API key';

  @override
  String get usageAllApiKeys => 'All';

  @override
  String get usageModelFilter => 'Model';

  @override
  String get usageAllModelsShort => 'All models';

  @override
  String get usageRequestsShort => 'requests';

  @override
  String get usageByModel => 'Usage by model';

  @override
  String get usageModelCalls => 'API requests';

  @override
  String get usageNoModelCalls => 'No calls in this period';

  @override
  String get usageChartByModel => 'By model';

  @override
  String get usageChartByKey => 'By API key';

  @override
  String get usageKeyName => 'Key';

  @override
  String get usageKeyAnonymous => 'No API key';

  @override
  String get usageTotalRow => 'Total';

  @override
  String get usageCallsUnit => 'calls';
}
