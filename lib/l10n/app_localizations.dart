import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'Local2API'**
  String get appTitle;

  /// No description provided for @navServer.
  ///
  /// In zh_CN, this message translates to:
  /// **'服务'**
  String get navServer;

  /// No description provided for @navModels.
  ///
  /// In zh_CN, this message translates to:
  /// **'模型'**
  String get navModels;

  /// No description provided for @navKeys.
  ///
  /// In zh_CN, this message translates to:
  /// **'密钥'**
  String get navKeys;

  /// No description provided for @navSettings.
  ///
  /// In zh_CN, this message translates to:
  /// **'设置'**
  String get navSettings;

  /// No description provided for @serverTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'服务'**
  String get serverTitle;

  /// No description provided for @serverRunning.
  ///
  /// In zh_CN, this message translates to:
  /// **'运行中'**
  String get serverRunning;

  /// No description provided for @serverStopped.
  ///
  /// In zh_CN, this message translates to:
  /// **'已停止'**
  String get serverStopped;

  /// No description provided for @serverStarting.
  ///
  /// In zh_CN, this message translates to:
  /// **'启动中…'**
  String get serverStarting;

  /// No description provided for @homeStatusDescRunning.
  ///
  /// In zh_CN, this message translates to:
  /// **'服务已启动，客户端可以直接调用了'**
  String get homeStatusDescRunning;

  /// No description provided for @homeStatusDescStopped.
  ///
  /// In zh_CN, this message translates to:
  /// **'服务未启动，点一下卡片启动'**
  String get homeStatusDescStopped;

  /// No description provided for @homeStatusDescStarting.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在启动服务…'**
  String get homeStatusDescStarting;

  /// No description provided for @homeStatusDescError.
  ///
  /// In zh_CN, this message translates to:
  /// **'启动失败，点一下卡片重试'**
  String get homeStatusDescError;

  /// No description provided for @startServer.
  ///
  /// In zh_CN, this message translates to:
  /// **'启动服务'**
  String get startServer;

  /// No description provided for @stopServer.
  ///
  /// In zh_CN, this message translates to:
  /// **'停止服务'**
  String get stopServer;

  /// No description provided for @restartServer.
  ///
  /// In zh_CN, this message translates to:
  /// **'重启服务'**
  String get restartServer;

  /// No description provided for @endpointTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'接入地址'**
  String get endpointTitle;

  /// No description provided for @listenAddress.
  ///
  /// In zh_CN, this message translates to:
  /// **'监听地址'**
  String get listenAddress;

  /// No description provided for @listenPort.
  ///
  /// In zh_CN, this message translates to:
  /// **'监听端口'**
  String get listenPort;

  /// No description provided for @copy.
  ///
  /// In zh_CN, this message translates to:
  /// **'复制'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In zh_CN, this message translates to:
  /// **'已复制'**
  String get copied;

  /// No description provided for @allInterfaces.
  ///
  /// In zh_CN, this message translates to:
  /// **'所有网卡 (0.0.0.0)'**
  String get allInterfaces;

  /// No description provided for @loopbackOnly.
  ///
  /// In zh_CN, this message translates to:
  /// **'仅本机 (127.0.0.1)'**
  String get loopbackOnly;

  /// No description provided for @lanIpsLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'局域网/VPN 地址'**
  String get lanIpsLabel;

  /// No description provided for @statsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'请求统计'**
  String get statsTitle;

  /// No description provided for @statTotalRequests.
  ///
  /// In zh_CN, this message translates to:
  /// **'累计请求'**
  String get statTotalRequests;

  /// No description provided for @statErrors.
  ///
  /// In zh_CN, this message translates to:
  /// **'失败'**
  String get statErrors;

  /// No description provided for @statActive.
  ///
  /// In zh_CN, this message translates to:
  /// **'活跃连接'**
  String get statActive;

  /// No description provided for @recentLogs.
  ///
  /// In zh_CN, this message translates to:
  /// **'最近请求'**
  String get recentLogs;

  /// No description provided for @viewAll.
  ///
  /// In zh_CN, this message translates to:
  /// **'查看全部'**
  String get viewAll;

  /// No description provided for @noLogsYet.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无请求日志'**
  String get noLogsYet;

  /// No description provided for @noKeysWarningTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'未配置密钥'**
  String get noKeysWarningTitle;

  /// No description provided for @noKeysWarningBody.
  ///
  /// In zh_CN, this message translates to:
  /// **'任何客户端都可以直接调用此服务，建议在仪表盘「密钥」分区添加至少一个密钥。'**
  String get noKeysWarningBody;

  /// No description provided for @noCidrWarningTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'对所有来源开放'**
  String get noCidrWarningTitle;

  /// No description provided for @noCidrWarningBody.
  ///
  /// In zh_CN, this message translates to:
  /// **'未配置任何 IP 规则，所有网段均可访问。'**
  String get noCidrWarningBody;

  /// No description provided for @serverErrorTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'服务异常'**
  String get serverErrorTitle;

  /// No description provided for @portInUse.
  ///
  /// In zh_CN, this message translates to:
  /// **'端口 {port} 被占用'**
  String portInUse(String port);

  /// No description provided for @autoStart.
  ///
  /// In zh_CN, this message translates to:
  /// **'启动时自动开启服务'**
  String get autoStart;

  /// No description provided for @modelsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'模型'**
  String get modelsTitle;

  /// No description provided for @upstreams.
  ///
  /// In zh_CN, this message translates to:
  /// **'上游服务'**
  String get upstreams;

  /// No description provided for @addUpstream.
  ///
  /// In zh_CN, this message translates to:
  /// **'添加上游'**
  String get addUpstream;

  /// No description provided for @noUpstreams.
  ///
  /// In zh_CN, this message translates to:
  /// **'还没有上游，先添加一个'**
  String get noUpstreams;

  /// No description provided for @upstreamTypeLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'类型'**
  String get upstreamTypeLabel;

  /// No description provided for @typeOpenai.
  ///
  /// In zh_CN, this message translates to:
  /// **'OpenAI 兼容'**
  String get typeOpenai;

  /// No description provided for @typeLlamacpp.
  ///
  /// In zh_CN, this message translates to:
  /// **'llama.cpp'**
  String get typeLlamacpp;

  /// No description provided for @typeOllama.
  ///
  /// In zh_CN, this message translates to:
  /// **'Ollama'**
  String get typeOllama;

  /// No description provided for @typeLocalTts.
  ///
  /// In zh_CN, this message translates to:
  /// **'本地 TTS (Qwen3)'**
  String get typeLocalTts;

  /// No description provided for @modalityLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'模态'**
  String get modalityLabel;

  /// No description provided for @modalityChat.
  ///
  /// In zh_CN, this message translates to:
  /// **'对话 (chat)'**
  String get modalityChat;

  /// No description provided for @modalityAudio.
  ///
  /// In zh_CN, this message translates to:
  /// **'语音 (audio)'**
  String get modalityAudio;

  /// No description provided for @modalityAudioHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'开启后 /v1/audio/speech 会把 OpenAI TTS 请求翻译成该上游的 chat.completions 语音请求（MiMo TTS 等），再把回包音频解给客户端'**
  String get modalityAudioHint;

  /// No description provided for @localTtsSectionTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'本地 TTS（Qwen3-TTS）'**
  String get localTtsSectionTitle;

  /// No description provided for @ttsSettingsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'TTS 设置'**
  String get ttsSettingsTitle;

  /// No description provided for @ttsSettingsDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'本地模型、服务商与试听'**
  String get ttsSettingsDesc;

  /// No description provided for @ttsAutoPlayTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'自动播放 TTS'**
  String get ttsAutoPlayTitle;

  /// No description provided for @localTtsModelSize.
  ///
  /// In zh_CN, this message translates to:
  /// **'共约 {size} GB'**
  String localTtsModelSize(String size);

  /// No description provided for @localTtsStateInstalled.
  ///
  /// In zh_CN, this message translates to:
  /// **'已安装'**
  String get localTtsStateInstalled;

  /// No description provided for @localTtsStatePartial.
  ///
  /// In zh_CN, this message translates to:
  /// **'未下完（可续传）'**
  String get localTtsStatePartial;

  /// No description provided for @localTtsStateNotInstalled.
  ///
  /// In zh_CN, this message translates to:
  /// **'未下载'**
  String get localTtsStateNotInstalled;

  /// No description provided for @localTtsDownload.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载模型'**
  String get localTtsDownload;

  /// No description provided for @localTtsDownloadProgress.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载中 {received}/{total} MB'**
  String localTtsDownloadProgress(String received, String total);

  /// No description provided for @localTtsDeleteConfirm.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除本地 TTS 模型文件？'**
  String get localTtsDeleteConfirm;

  /// No description provided for @localTtsDevicePreference.
  ///
  /// In zh_CN, this message translates to:
  /// **'推理后端'**
  String get localTtsDevicePreference;

  /// No description provided for @ttsDeviceAuto.
  ///
  /// In zh_CN, this message translates to:
  /// **'自动（高通优先 NPU）'**
  String get ttsDeviceAuto;

  /// No description provided for @ttsDeviceNpu.
  ///
  /// In zh_CN, this message translates to:
  /// **'NPU (Hexagon)'**
  String get ttsDeviceNpu;

  /// No description provided for @ttsDeviceGpu.
  ///
  /// In zh_CN, this message translates to:
  /// **'GPU (Vulkan)'**
  String get ttsDeviceGpu;

  /// No description provided for @ttsDeviceCpu.
  ///
  /// In zh_CN, this message translates to:
  /// **'CPU'**
  String get ttsDeviceCpu;

  /// No description provided for @localTtsTestSpeak.
  ///
  /// In zh_CN, this message translates to:
  /// **'试听'**
  String get localTtsTestSpeak;

  /// No description provided for @localTtsTestStop.
  ///
  /// In zh_CN, this message translates to:
  /// **'停止'**
  String get localTtsTestStop;

  /// No description provided for @localTtsStatusPreparing.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在加载模型…'**
  String get localTtsStatusPreparing;

  /// No description provided for @localTtsStatusSynthesizing.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在合成语音…'**
  String get localTtsStatusSynthesizing;

  /// No description provided for @localTtsStatusPlaying.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放中'**
  String get localTtsStatusPlaying;

  /// No description provided for @localTtsStatusIdle.
  ///
  /// In zh_CN, this message translates to:
  /// **'空闲'**
  String get localTtsStatusIdle;

  /// No description provided for @localTtsStatusError.
  ///
  /// In zh_CN, this message translates to:
  /// **'出错'**
  String get localTtsStatusError;

  /// No description provided for @localTtsNotReady.
  ///
  /// In zh_CN, this message translates to:
  /// **'模型未下载或下载不完整'**
  String get localTtsNotReady;

  /// No description provided for @localTtsServeHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载完成后，点下方「创建本地 TTS 上游」一键配置；客户端通过 /v1/audio/speech 调用（模型名 qwen3-tts）'**
  String get localTtsServeHint;

  /// No description provided for @localTtsUpstreamName.
  ///
  /// In zh_CN, this message translates to:
  /// **'本地 TTS'**
  String get localTtsUpstreamName;

  /// No description provided for @localTtsCreateUpstream.
  ///
  /// In zh_CN, this message translates to:
  /// **'创建本地 TTS 上游'**
  String get localTtsCreateUpstream;

  /// No description provided for @localTtsCreateUpstreamDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'自动在模型页添加「本地 TTS」上游（模型 qwen3-tts），客户端即可调 /v1/audio/speech'**
  String get localTtsCreateUpstreamDesc;

  /// No description provided for @localTtsUpstreamCreated.
  ///
  /// In zh_CN, this message translates to:
  /// **'已创建「本地 TTS」上游'**
  String get localTtsUpstreamCreated;

  /// No description provided for @localTtsUpstreamExists.
  ///
  /// In zh_CN, this message translates to:
  /// **'已存在「本地 TTS」上游'**
  String get localTtsUpstreamExists;

  /// No description provided for @settingsFeaturesSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'服务与功能'**
  String get settingsFeaturesSection;

  /// No description provided for @networkSettingsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'网络设置'**
  String get networkSettingsTitle;

  /// No description provided for @networkSettingsDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'端口与监听、临时 WebUI、IP 访问规则'**
  String get networkSettingsDesc;

  /// No description provided for @chatSettingsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'对话设置'**
  String get chatSettingsTitle;

  /// No description provided for @chatSettingsDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'TTS 设置、自动播放与角色卡'**
  String get chatSettingsDesc;

  /// No description provided for @ipRulesEmpty.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无规则，默认放行所有来源'**
  String get ipRulesEmpty;

  /// No description provided for @ipRulesCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'{count} 条规则'**
  String ipRulesCount(String count);

  /// No description provided for @ruleDeletedCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'已删除 {count} 条规则'**
  String ruleDeletedCount(String count);

  /// No description provided for @ruleRestored.
  ///
  /// In zh_CN, this message translates to:
  /// **'已恢复 {count} 条规则'**
  String ruleRestored(String count);

  /// No description provided for @characterEntryDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'管理对话模拟的角色卡与默认场景'**
  String get characterEntryDesc;

  /// No description provided for @ttsProviderLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认 TTS 服务商'**
  String get ttsProviderLabel;

  /// No description provided for @ttsProviderOff.
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭'**
  String get ttsProviderOff;

  /// No description provided for @ttsProviderLocal.
  ///
  /// In zh_CN, this message translates to:
  /// **'本地 Qwen3-TTS'**
  String get ttsProviderLocal;

  /// No description provided for @ttsProviderNoneHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'还没有能发声的模型：给语音上游加个模型，或先下载本地模型'**
  String get ttsProviderNoneHint;

  /// No description provided for @ttsDesignModelLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认语音设计模型'**
  String get ttsDesignModelLabel;

  /// No description provided for @ttsDesignModelDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'角色卡没配音色样本时用它合成，提示词即音色描述'**
  String get ttsDesignModelDesc;

  /// No description provided for @ttsDesignPromptLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'音色设计提示词'**
  String get ttsDesignPromptLabel;

  /// No description provided for @ttsDesignPromptDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'设计模型的音色描述（user 消息），留空用默认'**
  String get ttsDesignPromptDesc;

  /// No description provided for @ttsCloneModelLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认克隆模型'**
  String get ttsCloneModelLabel;

  /// No description provided for @ttsCloneModelDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'角色卡配了音色样本时用它克隆合成'**
  String get ttsCloneModelDesc;

  /// No description provided for @ttsDesignPromptDefault.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认'**
  String get ttsDesignPromptDefault;

  /// No description provided for @ttsPlaygroundTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'TTS 调试台'**
  String get ttsPlaygroundTitle;

  /// No description provided for @ttsPlaygroundDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'换样本 / 文本反复试听，排查克隆与设计效果'**
  String get ttsPlaygroundDesc;

  /// No description provided for @ttsPlaygroundHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'选模型、配音色样本、输入文本后播放。克隆不像时优先换样本：一段干净的单人声（5–10 秒、无背景音乐、无混响）比长音频效果好得多。'**
  String get ttsPlaygroundHint;

  /// No description provided for @ttsPlaygroundModel.
  ///
  /// In zh_CN, this message translates to:
  /// **'模型'**
  String get ttsPlaygroundModel;

  /// No description provided for @ttsPlaygroundText.
  ///
  /// In zh_CN, this message translates to:
  /// **'合成文本'**
  String get ttsPlaygroundText;

  /// No description provided for @ttsPlaygroundInstructions.
  ///
  /// In zh_CN, this message translates to:
  /// **'风格指令 / 音色描述（可选）'**
  String get ttsPlaygroundInstructions;

  /// No description provided for @ttsPlaygroundPlay.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放'**
  String get ttsPlaygroundPlay;

  /// No description provided for @ttsPlaygroundEmptyText.
  ///
  /// In zh_CN, this message translates to:
  /// **'先输入要合成的文本'**
  String get ttsPlaygroundEmptyText;

  /// No description provided for @ttsPlaygroundCloneNeedsSample.
  ///
  /// In zh_CN, this message translates to:
  /// **'克隆模型需要音色样本：先在上方配一段音频'**
  String get ttsPlaygroundCloneNeedsSample;

  /// No description provided for @ttsSpeak.
  ///
  /// In zh_CN, this message translates to:
  /// **'朗读'**
  String get ttsSpeak;

  /// No description provided for @characterVoiceLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'音色样本'**
  String get characterVoiceLabel;

  /// No description provided for @characterVoiceHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'选一段清晰人声（wav/mp3，≤7MB）用于克隆音色。推荐配云端克隆（快，几秒出声）；本地克隆要等 1.4GB 模型加载，首次可能要几分钟。'**
  String get characterVoiceHint;

  /// No description provided for @characterVoicePick.
  ///
  /// In zh_CN, this message translates to:
  /// **'选择音频'**
  String get characterVoicePick;

  /// No description provided for @characterVoiceRemove.
  ///
  /// In zh_CN, this message translates to:
  /// **'移除'**
  String get characterVoiceRemove;

  /// No description provided for @characterVoiceTooBig.
  ///
  /// In zh_CN, this message translates to:
  /// **'音频样本太大，请压缩到 7MB 以内'**
  String get characterVoiceTooBig;

  /// No description provided for @characterVoiceBadType.
  ///
  /// In zh_CN, this message translates to:
  /// **'仅支持 wav / mp3 音频'**
  String get characterVoiceBadType;

  /// No description provided for @characterOverrideReset.
  ///
  /// In zh_CN, this message translates to:
  /// **'已恢复内置原文'**
  String get characterOverrideReset;

  /// No description provided for @upstreamNameLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'名称'**
  String get upstreamNameLabel;

  /// No description provided for @baseUrlLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'接口地址 (Base URL)'**
  String get baseUrlLabel;

  /// No description provided for @baseUrlHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'http://192.168.1.10:11434/v1'**
  String get baseUrlHint;

  /// No description provided for @upstreamKeyLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'上游密钥（可选）'**
  String get upstreamKeyLabel;

  /// No description provided for @upstreamNoteLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'备注'**
  String get upstreamNoteLabel;

  /// No description provided for @upstreamNoteHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'这个上游是干什么的、有什么注意事项（可留空）'**
  String get upstreamNoteHint;

  /// No description provided for @upstreamJsonTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'上游 JSON'**
  String get upstreamJsonTitle;

  /// No description provided for @fetchModelsBtn.
  ///
  /// In zh_CN, this message translates to:
  /// **'拉取模型'**
  String get fetchModelsBtn;

  /// No description provided for @testBtn.
  ///
  /// In zh_CN, this message translates to:
  /// **'测试'**
  String get testBtn;

  /// No description provided for @testOk.
  ///
  /// In zh_CN, this message translates to:
  /// **'连接成功'**
  String get testOk;

  /// No description provided for @testFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'连接失败：{error}'**
  String testFailed(String error);

  /// No description provided for @fetchFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'拉取失败：{error}'**
  String fetchFailed(String error);

  /// No description provided for @fetchedModels.
  ///
  /// In zh_CN, this message translates to:
  /// **'获取到 {count} 个模型'**
  String fetchedModels(String count);

  /// No description provided for @saveBtn.
  ///
  /// In zh_CN, this message translates to:
  /// **'保存'**
  String get saveBtn;

  /// No description provided for @deleteBtn.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除'**
  String get deleteBtn;

  /// No description provided for @deleteUpstreamConfirm.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除上游「{name}」？'**
  String deleteUpstreamConfirm(String name);

  /// No description provided for @cancel.
  ///
  /// In zh_CN, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In zh_CN, this message translates to:
  /// **'确定'**
  String get confirm;

  /// No description provided for @exposedModelsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'对外模型'**
  String get exposedModelsTitle;

  /// No description provided for @noExposedModels.
  ///
  /// In zh_CN, this message translates to:
  /// **'没有对外暴露的模型'**
  String get noExposedModels;

  /// No description provided for @modelAliasLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'对外名称'**
  String get modelAliasLabel;

  /// No description provided for @modelTargetLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'上游模型'**
  String get modelTargetLabel;

  /// No description provided for @enabledLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'启用'**
  String get enabledLabel;

  /// No description provided for @exposedLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'暴露'**
  String get exposedLabel;

  /// No description provided for @baseUrlInvalid.
  ///
  /// In zh_CN, this message translates to:
  /// **'地址无效，需要 http(s):// 开头'**
  String get baseUrlInvalid;

  /// No description provided for @fetchingModels.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在获取模型…'**
  String get fetchingModels;

  /// No description provided for @testing.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在测试…'**
  String get testing;

  /// No description provided for @editUpstream.
  ///
  /// In zh_CN, this message translates to:
  /// **'编辑上游'**
  String get editUpstream;

  /// No description provided for @newUpstream.
  ///
  /// In zh_CN, this message translates to:
  /// **'新建上游'**
  String get newUpstream;

  /// No description provided for @upstreamNameRequired.
  ///
  /// In zh_CN, this message translates to:
  /// **'名称不能为空'**
  String get upstreamNameRequired;

  /// No description provided for @modelCountLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'{count} 个模型'**
  String modelCountLabel(String count);

  /// No description provided for @upstreamEditHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'一个上游就是一个 OpenAI 兼容端点，改完点右上角保存。'**
  String get upstreamEditHint;

  /// No description provided for @upstreamModeLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'模式'**
  String get upstreamModeLabel;

  /// No description provided for @pickModeTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'选择模式'**
  String get pickModeTitle;

  /// No description provided for @notFilled.
  ///
  /// In zh_CN, this message translates to:
  /// **'未填写'**
  String get notFilled;

  /// No description provided for @testConnectionTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'测试连接'**
  String get testConnectionTitle;

  /// No description provided for @testConnectionDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'用当前地址和密钥试一次'**
  String get testConnectionDesc;

  /// No description provided for @addModelBtn.
  ///
  /// In zh_CN, this message translates to:
  /// **'添加模型'**
  String get addModelBtn;

  /// No description provided for @modelsPageHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'点右上角下载图标从上游拉取模型，再勾要暴露的；加号可以手动填一个。'**
  String get modelsPageHint;

  /// No description provided for @modelsSortTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'排序方式'**
  String get modelsSortTitle;

  /// No description provided for @modelsSortNatural.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认顺序'**
  String get modelsSortNatural;

  /// No description provided for @modelsSortAlphabet.
  ///
  /// In zh_CN, this message translates to:
  /// **'首字母正序'**
  String get modelsSortAlphabet;

  /// No description provided for @keysTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'密钥'**
  String get keysTitle;

  /// No description provided for @addKey.
  ///
  /// In zh_CN, this message translates to:
  /// **'添加密钥'**
  String get addKey;

  /// No description provided for @keyNameLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'备注'**
  String get keyNameLabel;

  /// No description provided for @keyNameHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'例如：我的手机'**
  String get keyNameHint;

  /// No description provided for @keyValueLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'密钥'**
  String get keyValueLabel;

  /// No description provided for @generate.
  ///
  /// In zh_CN, this message translates to:
  /// **'随机生成'**
  String get generate;

  /// No description provided for @noKeysHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'尚无密钥，任何客户端都能直接调用'**
  String get noKeysHint;

  /// No description provided for @deleteKeyConfirm.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除密钥「{name}」？'**
  String deleteKeyConfirm(String name);

  /// No description provided for @keyExists.
  ///
  /// In zh_CN, this message translates to:
  /// **'该密钥已存在'**
  String get keyExists;

  /// No description provided for @keyRequired.
  ///
  /// In zh_CN, this message translates to:
  /// **'密钥不能为空'**
  String get keyRequired;

  /// No description provided for @settingsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'设置'**
  String get settingsTitle;

  /// No description provided for @networkSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'网络与访问'**
  String get networkSection;

  /// No description provided for @accessRules.
  ///
  /// In zh_CN, this message translates to:
  /// **'IP 访问规则'**
  String get accessRules;

  /// No description provided for @accessRuleDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'按顺序匹配，先命中先生效；为空则全部放行'**
  String get accessRuleDesc;

  /// No description provided for @addRule.
  ///
  /// In zh_CN, this message translates to:
  /// **'添加规则'**
  String get addRule;

  /// No description provided for @ruleAllow.
  ///
  /// In zh_CN, this message translates to:
  /// **'放行'**
  String get ruleAllow;

  /// No description provided for @ruleDeny.
  ///
  /// In zh_CN, this message translates to:
  /// **'拒绝'**
  String get ruleDeny;

  /// No description provided for @cidrHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'例如 192.168.0.0/16'**
  String get cidrHint;

  /// No description provided for @cidrInvalid.
  ///
  /// In zh_CN, this message translates to:
  /// **'CIDR 格式不正确'**
  String get cidrInvalid;

  /// No description provided for @corsToggle.
  ///
  /// In zh_CN, this message translates to:
  /// **'允许跨域（CORS）'**
  String get corsToggle;

  /// No description provided for @corsDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'允许网页前端直接调用本服务'**
  String get corsDesc;

  /// No description provided for @autoStartToggle.
  ///
  /// In zh_CN, this message translates to:
  /// **'启动时自动运行服务'**
  String get autoStartToggle;

  /// No description provided for @appearanceSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'外观'**
  String get appearanceSection;

  /// No description provided for @themeLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'主题'**
  String get themeLabel;

  /// No description provided for @themeSystem.
  ///
  /// In zh_CN, this message translates to:
  /// **'跟随系统'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In zh_CN, this message translates to:
  /// **'浅色'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In zh_CN, this message translates to:
  /// **'深色'**
  String get themeDark;

  /// No description provided for @languageLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'语言'**
  String get languageLabel;

  /// No description provided for @languageSystem.
  ///
  /// In zh_CN, this message translates to:
  /// **'跟随系统'**
  String get languageSystem;

  /// No description provided for @languageNote.
  ///
  /// In zh_CN, this message translates to:
  /// **'Android 13+ 可在系统「应用语言」中设置'**
  String get languageNote;

  /// No description provided for @aboutSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'关于'**
  String get aboutSection;

  /// No description provided for @aboutDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'将局域网/VPN 内的 llama.cpp、Ollama 或任意 OpenAI 兼容接口，转发为带鉴权与模型白名单的一层新 API。'**
  String get aboutDesc;

  /// No description provided for @versionLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'版本'**
  String get versionLabel;

  /// No description provided for @aboutEntryDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'版本、组件与效果背景'**
  String get aboutEntryDesc;

  /// No description provided for @aboutTapLogoHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'点一点上面的图标试试'**
  String get aboutTapLogoHint;

  /// No description provided for @aboutOpenLicenses.
  ///
  /// In zh_CN, this message translates to:
  /// **'开源许可'**
  String get aboutOpenLicenses;

  /// No description provided for @ossTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'开源许可'**
  String get ossTitle;

  /// No description provided for @ossSearchHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'搜索依赖包或许可标识'**
  String get ossSearchHint;

  /// No description provided for @ossClearSearch.
  ///
  /// In zh_CN, this message translates to:
  /// **'清除搜索'**
  String get ossClearSearch;

  /// 开源许可页头部统计
  ///
  /// In zh_CN, this message translates to:
  /// **'共 {count} 个依赖包 · {licenses} 份许可'**
  String ossPackagesCount(String count, String licenses);

  /// 一个依赖包名下的许可份数
  ///
  /// In zh_CN, this message translates to:
  /// **'{count} 份许可'**
  String ossLicensesCount(String count);

  /// No description provided for @ossEmptySearch.
  ///
  /// In zh_CN, this message translates to:
  /// **'没有匹配的依赖包'**
  String get ossEmptySearch;

  /// No description provided for @ossLoadFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'许可清单加载失败'**
  String get ossLoadFailed;

  /// No description provided for @ossRetry.
  ///
  /// In zh_CN, this message translates to:
  /// **'重试'**
  String get ossRetry;

  /// No description provided for @ossLoading.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在收集许可清单…'**
  String get ossLoading;

  /// No description provided for @ossCopyFullText.
  ///
  /// In zh_CN, this message translates to:
  /// **'复制全部许可'**
  String get ossCopyFullText;

  /// No description provided for @ossLicenseCopied.
  ///
  /// In zh_CN, this message translates to:
  /// **'已复制到剪贴板'**
  String get ossLicenseCopied;

  /// 包详情页里一份许可的序号
  ///
  /// In zh_CN, this message translates to:
  /// **'第 {index} / {count} 份'**
  String ossLicenseIndex(String index, String count);

  /// No description provided for @aboutComponents.
  ///
  /// In zh_CN, this message translates to:
  /// **'构建组件'**
  String get aboutComponents;

  /// No description provided for @aboutComponentsDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'Flutter · flutter_miuix（HyperOS 风格）'**
  String get aboutComponentsDesc;

  /// No description provided for @textureSetTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'纹理集'**
  String get textureSetTitle;

  /// No description provided for @textureSetEffectVariant.
  ///
  /// In zh_CN, this message translates to:
  /// **'效果变体'**
  String get textureSetEffectVariant;

  /// No description provided for @textureSetOs2.
  ///
  /// In zh_CN, this message translates to:
  /// **'OS2'**
  String get textureSetOs2;

  /// No description provided for @textureSetOs3.
  ///
  /// In zh_CN, this message translates to:
  /// **'OS3'**
  String get textureSetOs3;

  /// No description provided for @textureSetEffectBg.
  ///
  /// In zh_CN, this message translates to:
  /// **'效果背景'**
  String get textureSetEffectBg;

  /// No description provided for @textureSetDynamicBg.
  ///
  /// In zh_CN, this message translates to:
  /// **'动态背景'**
  String get textureSetDynamicBg;

  /// No description provided for @textureSetBlurEnable.
  ///
  /// In zh_CN, this message translates to:
  /// **'模糊'**
  String get textureSetBlurEnable;

  /// No description provided for @textureSetBlurRadius.
  ///
  /// In zh_CN, this message translates to:
  /// **'模糊半径'**
  String get textureSetBlurRadius;

  /// No description provided for @textureSetNoise.
  ///
  /// In zh_CN, this message translates to:
  /// **'噪点'**
  String get textureSetNoise;

  /// No description provided for @textureSetBrightness.
  ///
  /// In zh_CN, this message translates to:
  /// **'亮度'**
  String get textureSetBrightness;

  /// No description provided for @textureSetContrast.
  ///
  /// In zh_CN, this message translates to:
  /// **'对比度'**
  String get textureSetContrast;

  /// No description provided for @textureSetSaturation.
  ///
  /// In zh_CN, this message translates to:
  /// **'饱和度'**
  String get textureSetSaturation;

  /// No description provided for @textureSetBlendMode.
  ///
  /// In zh_CN, this message translates to:
  /// **'混合模式'**
  String get textureSetBlendMode;

  /// No description provided for @textureSetReset.
  ///
  /// In zh_CN, this message translates to:
  /// **'恢复默认'**
  String get textureSetReset;

  /// No description provided for @blendModeDefault.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认'**
  String get blendModeDefault;

  /// No description provided for @blendModeOverlay.
  ///
  /// In zh_CN, this message translates to:
  /// **'叠加'**
  String get blendModeOverlay;

  /// No description provided for @blendModeScreen.
  ///
  /// In zh_CN, this message translates to:
  /// **'滤色'**
  String get blendModeScreen;

  /// No description provided for @blendModeMultiply.
  ///
  /// In zh_CN, this message translates to:
  /// **'正片叠底'**
  String get blendModeMultiply;

  /// No description provided for @blendModePlusLighter.
  ///
  /// In zh_CN, this message translates to:
  /// **'加亮'**
  String get blendModePlusLighter;

  /// No description provided for @blendModePlusDarker.
  ///
  /// In zh_CN, this message translates to:
  /// **'加深'**
  String get blendModePlusDarker;

  /// No description provided for @blendModeLinearLight.
  ///
  /// In zh_CN, this message translates to:
  /// **'线性光'**
  String get blendModeLinearLight;

  /// No description provided for @blendModeDifference.
  ///
  /// In zh_CN, this message translates to:
  /// **'差值'**
  String get blendModeDifference;

  /// No description provided for @unsavedChangesTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'未保存的更改'**
  String get unsavedChangesTitle;

  /// No description provided for @unsavedChangesMessage.
  ///
  /// In zh_CN, this message translates to:
  /// **'你对这个上游的修改还没有保存，要现在保存吗？'**
  String get unsavedChangesMessage;

  /// No description provided for @unsavedSave.
  ///
  /// In zh_CN, this message translates to:
  /// **'保存'**
  String get unsavedSave;

  /// No description provided for @unsavedDiscard.
  ///
  /// In zh_CN, this message translates to:
  /// **'不保存'**
  String get unsavedDiscard;

  /// No description provided for @chatSimModelPicker.
  ///
  /// In zh_CN, this message translates to:
  /// **'模拟模型'**
  String get chatSimModelPicker;

  /// No description provided for @chatSimModelAll.
  ///
  /// In zh_CN, this message translates to:
  /// **'全部（整组共享）'**
  String get chatSimModelAll;

  /// No description provided for @chatSimModelAllDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'组内任意模型被调用都带上这段上下文'**
  String get chatSimModelAllDesc;

  /// No description provided for @chatSimModelSpecificDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'仅此模型带上这段上下文'**
  String get chatSimModelSpecificDesc;

  /// No description provided for @editMenuUndo.
  ///
  /// In zh_CN, this message translates to:
  /// **'撤消(U)'**
  String get editMenuUndo;

  /// No description provided for @editMenuCut.
  ///
  /// In zh_CN, this message translates to:
  /// **'剪切(T)'**
  String get editMenuCut;

  /// No description provided for @editMenuCopy.
  ///
  /// In zh_CN, this message translates to:
  /// **'复制(C)'**
  String get editMenuCopy;

  /// No description provided for @editMenuPaste.
  ///
  /// In zh_CN, this message translates to:
  /// **'粘贴(P)'**
  String get editMenuPaste;

  /// No description provided for @editMenuDelete.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除(D)'**
  String get editMenuDelete;

  /// No description provided for @editMenuSelectAll.
  ///
  /// In zh_CN, this message translates to:
  /// **'全选(A)'**
  String get editMenuSelectAll;

  /// No description provided for @portRangeInvalid.
  ///
  /// In zh_CN, this message translates to:
  /// **'端口范围 1024-65535'**
  String get portRangeInvalid;

  /// No description provided for @logsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'请求日志'**
  String get logsTitle;

  /// No description provided for @clearLogs.
  ///
  /// In zh_CN, this message translates to:
  /// **'清空'**
  String get clearLogs;

  /// No description provided for @logsCleared.
  ///
  /// In zh_CN, this message translates to:
  /// **'已清空'**
  String get logsCleared;

  /// No description provided for @stopServerConfirm.
  ///
  /// In zh_CN, this message translates to:
  /// **'停止服务？'**
  String get stopServerConfirm;

  /// No description provided for @clientLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'客户端'**
  String get clientLabel;

  /// No description provided for @modelLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'模型'**
  String get modelLabel;

  /// No description provided for @statusLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'状态'**
  String get statusLabel;

  /// No description provided for @durationLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'耗时'**
  String get durationLabel;

  /// No description provided for @colorAmber.
  ///
  /// In zh_CN, this message translates to:
  /// **'琥珀色'**
  String get colorAmber;

  /// No description provided for @colorBlue.
  ///
  /// In zh_CN, this message translates to:
  /// **'蓝色'**
  String get colorBlue;

  /// No description provided for @colorBlueGrey.
  ///
  /// In zh_CN, this message translates to:
  /// **'蓝灰色'**
  String get colorBlueGrey;

  /// No description provided for @colorBrown.
  ///
  /// In zh_CN, this message translates to:
  /// **'棕色'**
  String get colorBrown;

  /// No description provided for @colorCyan.
  ///
  /// In zh_CN, this message translates to:
  /// **'青色'**
  String get colorCyan;

  /// No description provided for @colorDeepPurple.
  ///
  /// In zh_CN, this message translates to:
  /// **'深紫色'**
  String get colorDeepPurple;

  /// No description provided for @colorDefaultGreen.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认绿'**
  String get colorDefaultGreen;

  /// No description provided for @colorGreen.
  ///
  /// In zh_CN, this message translates to:
  /// **'绿色'**
  String get colorGreen;

  /// No description provided for @colorGrey.
  ///
  /// In zh_CN, this message translates to:
  /// **'灰色'**
  String get colorGrey;

  /// No description provided for @colorIndigo.
  ///
  /// In zh_CN, this message translates to:
  /// **'靛蓝色'**
  String get colorIndigo;

  /// No description provided for @colorLightBlue.
  ///
  /// In zh_CN, this message translates to:
  /// **'浅蓝色'**
  String get colorLightBlue;

  /// No description provided for @colorLightGreen.
  ///
  /// In zh_CN, this message translates to:
  /// **'浅绿色'**
  String get colorLightGreen;

  /// No description provided for @colorLime.
  ///
  /// In zh_CN, this message translates to:
  /// **'酸橙色'**
  String get colorLime;

  /// No description provided for @colorOrange.
  ///
  /// In zh_CN, this message translates to:
  /// **'橙色'**
  String get colorOrange;

  /// No description provided for @colorPink.
  ///
  /// In zh_CN, this message translates to:
  /// **'粉红色'**
  String get colorPink;

  /// No description provided for @colorPurple.
  ///
  /// In zh_CN, this message translates to:
  /// **'紫色'**
  String get colorPurple;

  /// No description provided for @colorRed.
  ///
  /// In zh_CN, this message translates to:
  /// **'红色'**
  String get colorRed;

  /// No description provided for @colorTeal.
  ///
  /// In zh_CN, this message translates to:
  /// **'蓝绿色'**
  String get colorTeal;

  /// No description provided for @colorYellow.
  ///
  /// In zh_CN, this message translates to:
  /// **'黄色'**
  String get colorYellow;

  /// No description provided for @commonBackTooltip.
  ///
  /// In zh_CN, this message translates to:
  /// **'转到上一层级'**
  String get commonBackTooltip;

  /// No description provided for @commonCancel.
  ///
  /// In zh_CN, this message translates to:
  /// **'取消'**
  String get commonCancel;

  /// No description provided for @commonCreate.
  ///
  /// In zh_CN, this message translates to:
  /// **'创建'**
  String get commonCreate;

  /// No description provided for @commonDelete.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除'**
  String get commonDelete;

  /// No description provided for @commonSave.
  ///
  /// In zh_CN, this message translates to:
  /// **'保存'**
  String get commonSave;

  /// No description provided for @displayFollowSystemColor.
  ///
  /// In zh_CN, this message translates to:
  /// **'跟随系统配色'**
  String get displayFollowSystemColor;

  /// No description provided for @displayFontWeight.
  ///
  /// In zh_CN, this message translates to:
  /// **'文字粗细'**
  String get displayFontWeight;

  /// No description provided for @displayOff.
  ///
  /// In zh_CN, this message translates to:
  /// **'已关闭'**
  String get displayOff;

  /// No description provided for @displayPureBlack.
  ///
  /// In zh_CN, this message translates to:
  /// **'纯黑深色模式'**
  String get displayPureBlack;

  /// No description provided for @displayPureBlackOn.
  ///
  /// In zh_CN, this message translates to:
  /// **'深色模式（已黑化）'**
  String get displayPureBlackOn;

  /// No description provided for @displayScaleCompact.
  ///
  /// In zh_CN, this message translates to:
  /// **'紧凑模式 · 显示更多内容'**
  String get displayScaleCompact;

  /// No description provided for @displayScaleCompactBig.
  ///
  /// In zh_CN, this message translates to:
  /// **'紧凑 · 适合大屏'**
  String get displayScaleCompactBig;

  /// No description provided for @displayScaleDefault.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认'**
  String get displayScaleDefault;

  /// No description provided for @displayScaleFineTune.
  ///
  /// In zh_CN, this message translates to:
  /// **'精细调节'**
  String get displayScaleFineTune;

  /// No description provided for @displayScaleHuge.
  ///
  /// In zh_CN, this message translates to:
  /// **'超大 · 辅助功能'**
  String get displayScaleHuge;

  /// No description provided for @displayModeTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'屏幕帧率'**
  String get displayModeTitle;

  /// No description provided for @displayModeAuto.
  ///
  /// In zh_CN, this message translates to:
  /// **'自动'**
  String get displayModeAuto;

  /// No description provided for @displayModeSystemTag.
  ///
  /// In zh_CN, this message translates to:
  /// **'[系统]'**
  String get displayModeSystemTag;

  /// No description provided for @displayModeHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'没有生效？重启应用试试'**
  String get displayModeHint;

  /// No description provided for @displayModeUnsupported.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前平台不支持设置屏幕帧率（仅 Android）'**
  String get displayModeUnsupported;

  /// No description provided for @displayModeLoading.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在获取屏幕帧率...'**
  String get displayModeLoading;

  /// No description provided for @displayModeEmpty.
  ///
  /// In zh_CN, this message translates to:
  /// **'未获取到可用的屏幕帧率'**
  String get displayModeEmpty;

  /// No description provided for @displayScaleLarge.
  ///
  /// In zh_CN, this message translates to:
  /// **'略大 · 更易阅读'**
  String get displayScaleLarge;

  /// No description provided for @displayScaleLargeFont.
  ///
  /// In zh_CN, this message translates to:
  /// **'大字体 · 无障碍友好'**
  String get displayScaleLargeFont;

  /// No description provided for @displayScaleLargeFontShort.
  ///
  /// In zh_CN, this message translates to:
  /// **'大字体 · 无障碍'**
  String get displayScaleLargeFontShort;

  /// No description provided for @displayScaleMin.
  ///
  /// In zh_CN, this message translates to:
  /// **'最小 · 信息密度最高'**
  String get displayScaleMin;

  /// No description provided for @displayScaleNote.
  ///
  /// In zh_CN, this message translates to:
  /// **'缩放比例会全局应用于文字与部分布局尺寸。设为 100% 可恢复默认。修改即时生效，无需重启。'**
  String get displayScaleNote;

  /// No description provided for @displayScalePresets.
  ///
  /// In zh_CN, this message translates to:
  /// **'快捷预设'**
  String get displayScalePresets;

  /// No description provided for @displayScaleReset.
  ///
  /// In zh_CN, this message translates to:
  /// **'重置为 100%'**
  String get displayScaleReset;

  /// No description provided for @displayScaleSmall.
  ///
  /// In zh_CN, this message translates to:
  /// **'略小 · 适合大屏'**
  String get displayScaleSmall;

  /// No description provided for @displayScaleSystemDefault.
  ///
  /// In zh_CN, this message translates to:
  /// **'系统默认'**
  String get displayScaleSystemDefault;

  /// No description provided for @displayScaleTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'显示缩放'**
  String get displayScaleTitle;

  /// No description provided for @displaySectionAppearance.
  ///
  /// In zh_CN, this message translates to:
  /// **'外观'**
  String get displaySectionAppearance;

  /// No description provided for @displaySectionPersonalize.
  ///
  /// In zh_CN, this message translates to:
  /// **'个性化'**
  String get displaySectionPersonalize;

  /// No description provided for @displaySeedAmber.
  ///
  /// In zh_CN, this message translates to:
  /// **'琥珀色'**
  String get displaySeedAmber;

  /// No description provided for @displaySeedBlue.
  ///
  /// In zh_CN, this message translates to:
  /// **'蓝色'**
  String get displaySeedBlue;

  /// No description provided for @displaySeedBlueGrey.
  ///
  /// In zh_CN, this message translates to:
  /// **'蓝灰色'**
  String get displaySeedBlueGrey;

  /// No description provided for @displaySeedBrown.
  ///
  /// In zh_CN, this message translates to:
  /// **'棕色'**
  String get displaySeedBrown;

  /// No description provided for @displaySeedCustom.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义'**
  String get displaySeedCustom;

  /// No description provided for @displaySeedCyan.
  ///
  /// In zh_CN, this message translates to:
  /// **'青色'**
  String get displaySeedCyan;

  /// No description provided for @displaySeedDeepPurple.
  ///
  /// In zh_CN, this message translates to:
  /// **'深紫色'**
  String get displaySeedDeepPurple;

  /// No description provided for @displaySeedDefaultGreen.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认绿'**
  String get displaySeedDefaultGreen;

  /// No description provided for @displaySeedGreen.
  ///
  /// In zh_CN, this message translates to:
  /// **'绿色'**
  String get displaySeedGreen;

  /// No description provided for @displaySeedGrey.
  ///
  /// In zh_CN, this message translates to:
  /// **'灰色'**
  String get displaySeedGrey;

  /// No description provided for @displaySeedIndigo.
  ///
  /// In zh_CN, this message translates to:
  /// **'靛蓝色'**
  String get displaySeedIndigo;

  /// No description provided for @displaySeedLightBlue.
  ///
  /// In zh_CN, this message translates to:
  /// **'浅蓝色'**
  String get displaySeedLightBlue;

  /// No description provided for @displaySeedLightGreen.
  ///
  /// In zh_CN, this message translates to:
  /// **'浅绿色'**
  String get displaySeedLightGreen;

  /// No description provided for @displaySeedLime.
  ///
  /// In zh_CN, this message translates to:
  /// **'酸橙色'**
  String get displaySeedLime;

  /// No description provided for @displaySeedOrange.
  ///
  /// In zh_CN, this message translates to:
  /// **'橙色'**
  String get displaySeedOrange;

  /// No description provided for @displaySeedPink.
  ///
  /// In zh_CN, this message translates to:
  /// **'粉红色'**
  String get displaySeedPink;

  /// No description provided for @displaySeedPurple.
  ///
  /// In zh_CN, this message translates to:
  /// **'紫色'**
  String get displaySeedPurple;

  /// No description provided for @displaySeedRed.
  ///
  /// In zh_CN, this message translates to:
  /// **'红色'**
  String get displaySeedRed;

  /// No description provided for @displaySeedTeal.
  ///
  /// In zh_CN, this message translates to:
  /// **'蓝绿色'**
  String get displaySeedTeal;

  /// No description provided for @displaySeedYellow.
  ///
  /// In zh_CN, this message translates to:
  /// **'黄色'**
  String get displaySeedYellow;

  /// No description provided for @displaySettingsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'显示'**
  String get displaySettingsTitle;

  /// No description provided for @displayThemeColor.
  ///
  /// In zh_CN, this message translates to:
  /// **'主题配色'**
  String get displayThemeColor;

  /// No description provided for @displayThemeDark.
  ///
  /// In zh_CN, this message translates to:
  /// **'深色'**
  String get displayThemeDark;

  /// No description provided for @displayThemeLight.
  ///
  /// In zh_CN, this message translates to:
  /// **'浅色'**
  String get displayThemeLight;

  /// No description provided for @displayThemeMode.
  ///
  /// In zh_CN, this message translates to:
  /// **'主题模式'**
  String get displayThemeMode;

  /// No description provided for @displayWeightBlack.
  ///
  /// In zh_CN, this message translates to:
  /// **'极粗 ({weight})'**
  String displayWeightBlack(int weight);

  /// No description provided for @displayWeightBold.
  ///
  /// In zh_CN, this message translates to:
  /// **'粗 ({weight})'**
  String displayWeightBold(int weight);

  /// No description provided for @displayWeightCustom.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义 ({weight})'**
  String displayWeightCustom(int weight);

  /// No description provided for @displayWeightLight.
  ///
  /// In zh_CN, this message translates to:
  /// **'细 ({weight})'**
  String displayWeightLight(int weight);

  /// No description provided for @displayWeightMedium.
  ///
  /// In zh_CN, this message translates to:
  /// **'中等 ({weight})'**
  String displayWeightMedium(int weight);

  /// No description provided for @displayWeightRegular.
  ///
  /// In zh_CN, this message translates to:
  /// **'常规 ({weight})'**
  String displayWeightRegular(int weight);

  /// No description provided for @displayWeightThin.
  ///
  /// In zh_CN, this message translates to:
  /// **'极细 ({weight})'**
  String displayWeightThin(int weight);

  /// No description provided for @drawerSystemMode.
  ///
  /// In zh_CN, this message translates to:
  /// **'跟随系统'**
  String get drawerSystemMode;

  /// No description provided for @fontWeightBlack.
  ///
  /// In zh_CN, this message translates to:
  /// **'极粗'**
  String get fontWeightBlack;

  /// No description provided for @fontWeightBold.
  ///
  /// In zh_CN, this message translates to:
  /// **'粗'**
  String get fontWeightBold;

  /// No description provided for @fontWeightLight.
  ///
  /// In zh_CN, this message translates to:
  /// **'细'**
  String get fontWeightLight;

  /// No description provided for @fontWeightMedium.
  ///
  /// In zh_CN, this message translates to:
  /// **'中等'**
  String get fontWeightMedium;

  /// No description provided for @fontWeightRegular.
  ///
  /// In zh_CN, this message translates to:
  /// **'常规'**
  String get fontWeightRegular;

  /// No description provided for @fontWeightSampleText.
  ///
  /// In zh_CN, this message translates to:
  /// **'The quick brown fox jumps over the lazy dog.\n敏捷的棕色狐狸跳过懒惰的狗。'**
  String get fontWeightSampleText;

  /// No description provided for @fontWeightSaveApply.
  ///
  /// In zh_CN, this message translates to:
  /// **'保存并应用'**
  String get fontWeightSaveApply;

  /// No description provided for @fontWeightUnsavedTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'有未保存的调整'**
  String get fontWeightUnsavedTitle;

  /// No description provided for @fontWeightUnsavedBody.
  ///
  /// In zh_CN, this message translates to:
  /// **'文字粗细改成了 {weight}，还没确认。'**
  String fontWeightUnsavedBody(int weight);

  /// No description provided for @fontWeightUnsavedSave.
  ///
  /// In zh_CN, this message translates to:
  /// **'保存'**
  String get fontWeightUnsavedSave;

  /// No description provided for @fontWeightUnsavedDiscard.
  ///
  /// In zh_CN, this message translates to:
  /// **'不保存'**
  String get fontWeightUnsavedDiscard;

  /// No description provided for @fontWeightThin.
  ///
  /// In zh_CN, this message translates to:
  /// **'极细'**
  String get fontWeightThin;

  /// No description provided for @playlistMenuMore.
  ///
  /// In zh_CN, this message translates to:
  /// **'更多操作'**
  String get playlistMenuMore;

  /// No description provided for @searchPureBlack.
  ///
  /// In zh_CN, this message translates to:
  /// **'纯黑深色模式'**
  String get searchPureBlack;

  /// No description provided for @searchThemeMode.
  ///
  /// In zh_CN, this message translates to:
  /// **'主题模式'**
  String get searchThemeMode;

  /// No description provided for @startScreenGoBack.
  ///
  /// In zh_CN, this message translates to:
  /// **'转到上一层级'**
  String get startScreenGoBack;

  /// No description provided for @themeAppearance.
  ///
  /// In zh_CN, this message translates to:
  /// **'外观'**
  String get themeAppearance;

  /// No description provided for @themeColorCopied.
  ///
  /// In zh_CN, this message translates to:
  /// **'已复制色号: {hex}'**
  String themeColorCopied(String hex);

  /// No description provided for @themeColorExtracted.
  ///
  /// In zh_CN, this message translates to:
  /// **'已从图片提取主题色'**
  String get themeColorExtracted;

  /// No description provided for @themeColorFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'取色失败: {error}'**
  String themeColorFailed(String error);

  /// No description provided for @themeColorsSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'配色'**
  String get themeColorsSection;

  /// No description provided for @themeCopyColor.
  ///
  /// In zh_CN, this message translates to:
  /// **'复制色号'**
  String get themeCopyColor;

  /// No description provided for @themeCreateTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'创建自定义主题'**
  String get themeCreateTitle;

  /// No description provided for @themeCreated.
  ///
  /// In zh_CN, this message translates to:
  /// **'主题 \"{name}\" 已创建并保存'**
  String themeCreated(String name);

  /// No description provided for @themeDarkBlackened.
  ///
  /// In zh_CN, this message translates to:
  /// **'深色模式（已黑化）'**
  String get themeDarkBlackened;

  /// No description provided for @themeDeleteConfirm.
  ///
  /// In zh_CN, this message translates to:
  /// **'确定要删除自定义主题 \"{name}\" 吗？'**
  String themeDeleteConfirm(String name);

  /// No description provided for @themeDeleteTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除主题'**
  String get themeDeleteTitle;

  /// No description provided for @themeDeleted.
  ///
  /// In zh_CN, this message translates to:
  /// **'已删除 \"{name}\"'**
  String themeDeleted(String name);

  /// No description provided for @themeDropHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'松开以从图片提取主题色'**
  String get themeDropHint;

  /// No description provided for @themeEnabled.
  ///
  /// In zh_CN, this message translates to:
  /// **'已启用'**
  String get themeEnabled;

  /// No description provided for @themeFollowSystem.
  ///
  /// In zh_CN, this message translates to:
  /// **'跟随系统配色'**
  String get themeFollowSystem;

  /// No description provided for @themeHexHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'例如 #FF0000 或 255,0,0'**
  String get themeHexHint;

  /// No description provided for @themeHexLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'十六进制/RGB'**
  String get themeHexLabel;

  /// No description provided for @themeImageOnly.
  ///
  /// In zh_CN, this message translates to:
  /// **'仅支持图片格式'**
  String get themeImageOnly;

  /// No description provided for @themeNameHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'请输入文本'**
  String get themeNameHint;

  /// No description provided for @themeNameLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'主题名称'**
  String get themeNameLabel;

  /// No description provided for @themeNewTheme.
  ///
  /// In zh_CN, this message translates to:
  /// **'新建主题'**
  String get themeNewTheme;

  /// No description provided for @themeOff.
  ///
  /// In zh_CN, this message translates to:
  /// **'已关闭'**
  String get themeOff;

  /// No description provided for @themePaletteStyle.
  ///
  /// In zh_CN, this message translates to:
  /// **'调色板风格'**
  String get themePaletteStyle;

  /// No description provided for @themePickColor.
  ///
  /// In zh_CN, this message translates to:
  /// **'选择颜色'**
  String get themePickColor;

  /// No description provided for @settingsBlurTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'启用模糊'**
  String get settingsBlurTitle;

  /// No description provided for @settingsBlurDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'为应用启用模糊效果'**
  String get settingsBlurDesc;

  /// No description provided for @settingsCustomColorsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义颜色'**
  String get settingsCustomColorsTitle;

  /// No description provided for @settingsCustomColorsDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'在 Miuix 主题风格下自定义主题颜色'**
  String get settingsCustomColorsDesc;

  /// No description provided for @themeCustomColorsNeeded.
  ///
  /// In zh_CN, this message translates to:
  /// **'需要启用自定义颜色'**
  String get themeCustomColorsNeeded;

  /// No description provided for @themePickFromImage.
  ///
  /// In zh_CN, this message translates to:
  /// **'从图片取色'**
  String get themePickFromImage;

  /// No description provided for @themeSwitched.
  ///
  /// In zh_CN, this message translates to:
  /// **'已切换至 {name} 主题'**
  String themeSwitched(String name);

  /// No description provided for @themeTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'主题'**
  String get themeTitle;

  /// No description provided for @settingsDisplaySection.
  ///
  /// In zh_CN, this message translates to:
  /// **'外观'**
  String get settingsDisplaySection;

  /// No description provided for @settingsDisplayEntry.
  ///
  /// In zh_CN, this message translates to:
  /// **'显示设置'**
  String get settingsDisplayEntry;

  /// No description provided for @drawerDarkMode.
  ///
  /// In zh_CN, this message translates to:
  /// **'深色模式'**
  String get drawerDarkMode;

  /// No description provided for @drawerLightMode.
  ///
  /// In zh_CN, this message translates to:
  /// **'浅色模式'**
  String get drawerLightMode;

  /// No description provided for @sideBarCollapse.
  ///
  /// In zh_CN, this message translates to:
  /// **'收起侧边栏'**
  String get sideBarCollapse;

  /// No description provided for @sideBarExpand.
  ///
  /// In zh_CN, this message translates to:
  /// **'展开侧边栏'**
  String get sideBarExpand;

  /// No description provided for @navDiscover.
  ///
  /// In zh_CN, this message translates to:
  /// **'发现'**
  String get navDiscover;

  /// No description provided for @laneProbing.
  ///
  /// In zh_CN, this message translates to:
  /// **'探测中…'**
  String get laneProbing;

  /// No description provided for @laneUsable.
  ///
  /// In zh_CN, this message translates to:
  /// **'可用'**
  String get laneUsable;

  /// No description provided for @laneRestricted.
  ///
  /// In zh_CN, this message translates to:
  /// **'仅限官方客户端'**
  String get laneRestricted;

  /// No description provided for @laneThrottled.
  ///
  /// In zh_CN, this message translates to:
  /// **'额度已达上限'**
  String get laneThrottled;

  /// No description provided for @laneRegionBlocked.
  ///
  /// In zh_CN, this message translates to:
  /// **'出口地区受限'**
  String get laneRegionBlocked;

  /// No description provided for @laneUnavailable.
  ///
  /// In zh_CN, this message translates to:
  /// **'模型当前不可用'**
  String get laneUnavailable;

  /// No description provided for @laneFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'不可用'**
  String get laneFailed;

  /// No description provided for @laneNetUnreachable.
  ///
  /// In zh_CN, this message translates to:
  /// **'连不上端点'**
  String get laneNetUnreachable;

  /// No description provided for @navDashboard.
  ///
  /// In zh_CN, this message translates to:
  /// **'仪表盘'**
  String get navDashboard;

  /// No description provided for @dashboardTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'仪表盘'**
  String get dashboardTitle;

  /// No description provided for @fabRefresh.
  ///
  /// In zh_CN, this message translates to:
  /// **'刷新'**
  String get fabRefresh;

  /// No description provided for @fabAppearance.
  ///
  /// In zh_CN, this message translates to:
  /// **'外观'**
  String get fabAppearance;

  /// No description provided for @appearancePanelTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'外观快速设置'**
  String get appearancePanelTitle;

  /// No description provided for @fabDelayTest.
  ///
  /// In zh_CN, this message translates to:
  /// **'测试连接'**
  String get fabDelayTest;

  /// No description provided for @laneUntested.
  ///
  /// In zh_CN, this message translates to:
  /// **'尚未测试'**
  String get laneUntested;

  /// No description provided for @laneHintRoute.
  ///
  /// In zh_CN, this message translates to:
  /// **'点选一条车道作为链首，其余按顺序自动回退。'**
  String get laneHintRoute;

  /// No description provided for @discoverTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'发现'**
  String get discoverTitle;

  /// No description provided for @discoverIntro.
  ///
  /// In zh_CN, this message translates to:
  /// **'这里列出全部上游：开关管启用/停用，闪电测速，点卡片改配置；下拉刷新可用模型列表。'**
  String get discoverIntro;

  /// No description provided for @fabNewUpstream.
  ///
  /// In zh_CN, this message translates to:
  /// **'新建上游'**
  String get fabNewUpstream;

  /// No description provided for @createConfigTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'创建配置'**
  String get createConfigTitle;

  /// No description provided for @createConfigFileTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件'**
  String get createConfigFileTitle;

  /// No description provided for @createConfigFileDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'从文件、订阅链接或粘贴 JSON 导入'**
  String get createConfigFileDesc;

  /// No description provided for @createConfigUpstreamDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'手动创建一组上游配置'**
  String get createConfigUpstreamDesc;

  /// No description provided for @profileNewUpstreamTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'新建上游'**
  String get profileNewUpstreamTitle;

  /// No description provided for @profileGroupNameLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'名称'**
  String get profileGroupNameLabel;

  /// No description provided for @profileGroupNameHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'给这个模型组起个名字（留空就用档案自带的）'**
  String get profileGroupNameHint;

  /// No description provided for @profileGroupDescLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'说明'**
  String get profileGroupDescLabel;

  /// No description provided for @profileGroupDescHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'这一组是什么、从哪来（可留空）'**
  String get profileGroupDescHint;

  /// No description provided for @profileSpeedTest.
  ///
  /// In zh_CN, this message translates to:
  /// **'测速'**
  String get profileSpeedTest;

  /// No description provided for @profileRefreshModels.
  ///
  /// In zh_CN, this message translates to:
  /// **'刷新可用模型'**
  String get profileRefreshModels;

  /// No description provided for @profileLanesDynamic.
  ///
  /// In zh_CN, this message translates to:
  /// **'模型清单随上游变动'**
  String get profileLanesDynamic;

  /// No description provided for @profileModelsRefreshed.
  ///
  /// In zh_CN, this message translates to:
  /// **'已刷新 {count} 个组的可用模型'**
  String profileModelsRefreshed(int count);

  /// No description provided for @profileModelsRefreshFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'一个组都没刷出来，看看网络或端点地址'**
  String get profileModelsRefreshFailed;

  /// No description provided for @keyDeletedCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'已删除 {count} 个密钥'**
  String keyDeletedCount(int count);

  /// No description provided for @keyRestore.
  ///
  /// In zh_CN, this message translates to:
  /// **'恢复'**
  String get keyRestore;

  /// No description provided for @keyRestored.
  ///
  /// In zh_CN, this message translates to:
  /// **'已恢复 {count} 个密钥'**
  String keyRestored(int count);

  /// No description provided for @keysManage.
  ///
  /// In zh_CN, this message translates to:
  /// **'管理密钥'**
  String get keysManage;

  /// No description provided for @keysIntro.
  ///
  /// In zh_CN, this message translates to:
  /// **'密钥是这一层的门禁：只有带着密钥的客户端才允许调用。左滑一行可以删除。'**
  String get keysIntro;

  /// No description provided for @keysEmptyPage.
  ///
  /// In zh_CN, this message translates to:
  /// **'还没有密钥，点右下角加号添加一个。'**
  String get keysEmptyPage;

  /// No description provided for @usageTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'Token 统计'**
  String get usageTitle;

  /// No description provided for @usageIntro.
  ///
  /// In zh_CN, this message translates to:
  /// **'本机代理接住的每一次请求都在这里记账：输入 / 输出 / 缓存命中，按模型与时间查。'**
  String get usageIntro;

  /// No description provided for @usageAllModels.
  ///
  /// In zh_CN, this message translates to:
  /// **'全部模型'**
  String get usageAllModels;

  /// No description provided for @usageRangeToday.
  ///
  /// In zh_CN, this message translates to:
  /// **'今天'**
  String get usageRangeToday;

  /// No description provided for @usageRange7.
  ///
  /// In zh_CN, this message translates to:
  /// **'近 7 天'**
  String get usageRange7;

  /// No description provided for @usageRange30.
  ///
  /// In zh_CN, this message translates to:
  /// **'近 30 天'**
  String get usageRange30;

  /// No description provided for @usageRangeAll.
  ///
  /// In zh_CN, this message translates to:
  /// **'全部'**
  String get usageRangeAll;

  /// No description provided for @usageTotal.
  ///
  /// In zh_CN, this message translates to:
  /// **'合计'**
  String get usageTotal;

  /// No description provided for @usageInput.
  ///
  /// In zh_CN, this message translates to:
  /// **'输入'**
  String get usageInput;

  /// No description provided for @usageOutput.
  ///
  /// In zh_CN, this message translates to:
  /// **'输出'**
  String get usageOutput;

  /// No description provided for @usageCacheHit.
  ///
  /// In zh_CN, this message translates to:
  /// **'缓存命中'**
  String get usageCacheHit;

  /// No description provided for @usageCacheMiss.
  ///
  /// In zh_CN, this message translates to:
  /// **'缓存未命中'**
  String get usageCacheMiss;

  /// No description provided for @usageHitRate.
  ///
  /// In zh_CN, this message translates to:
  /// **'命中率'**
  String get usageHitRate;

  /// No description provided for @usageRequests.
  ///
  /// In zh_CN, this message translates to:
  /// **'请求数'**
  String get usageRequests;

  /// No description provided for @usageReasoning.
  ///
  /// In zh_CN, this message translates to:
  /// **'思考'**
  String get usageReasoning;

  /// No description provided for @usageByDay.
  ///
  /// In zh_CN, this message translates to:
  /// **'按天'**
  String get usageByDay;

  /// No description provided for @usageRecent.
  ///
  /// In zh_CN, this message translates to:
  /// **'最近记录'**
  String get usageRecent;

  /// No description provided for @usageEmpty.
  ///
  /// In zh_CN, this message translates to:
  /// **'这段时间还没有记录，跑一轮模型后这里就有数了。'**
  String get usageEmpty;

  /// No description provided for @usageNoUsageData.
  ///
  /// In zh_CN, this message translates to:
  /// **'上游未给用量'**
  String get usageNoUsageData;

  /// No description provided for @usageClear.
  ///
  /// In zh_CN, this message translates to:
  /// **'清空用量'**
  String get usageClear;

  /// No description provided for @usageClearConfirm.
  ///
  /// In zh_CN, this message translates to:
  /// **'清空全部 token 用量记录？'**
  String get usageClearConfirm;

  /// No description provided for @usageCleared.
  ///
  /// In zh_CN, this message translates to:
  /// **'用量记录已清空'**
  String get usageCleared;

  /// No description provided for @usageOpen.
  ///
  /// In zh_CN, this message translates to:
  /// **'查看 Token 统计'**
  String get usageOpen;

  /// No description provided for @usageCalendar.
  ///
  /// In zh_CN, this message translates to:
  /// **'用量日历'**
  String get usageCalendar;

  /// No description provided for @usageCalendarOpen.
  ///
  /// In zh_CN, this message translates to:
  /// **'日历'**
  String get usageCalendarOpen;

  /// No description provided for @usageCalendarIntro.
  ///
  /// In zh_CN, this message translates to:
  /// **'点日期看当天调用了哪些模型，点卡片就带着那一天回到统计页。'**
  String get usageCalendarIntro;

  /// No description provided for @usageCalendarPrevMonth.
  ///
  /// In zh_CN, this message translates to:
  /// **'上个月'**
  String get usageCalendarPrevMonth;

  /// No description provided for @usageCalendarNextMonth.
  ///
  /// In zh_CN, this message translates to:
  /// **'下个月'**
  String get usageCalendarNextMonth;

  /// No description provided for @usageCalendarEmptyDay.
  ///
  /// In zh_CN, this message translates to:
  /// **'这天没有调用记录'**
  String get usageCalendarEmptyDay;

  /// No description provided for @usageCalendarDayModels.
  ///
  /// In zh_CN, this message translates to:
  /// **'{date} 的活动'**
  String usageCalendarDayModels(String date);

  /// No description provided for @chatSimTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'对话模拟'**
  String get chatSimTitle;

  /// No description provided for @chatSimAutoSaved.
  ///
  /// In zh_CN, this message translates to:
  /// **'对话默认保存在本机（按模型组分开放），下次进来接着聊。'**
  String get chatSimAutoSaved;

  /// No description provided for @chatSimVoiceInput.
  ///
  /// In zh_CN, this message translates to:
  /// **'语音输入'**
  String get chatSimVoiceInput;

  /// No description provided for @chatSimVoiceStop.
  ///
  /// In zh_CN, this message translates to:
  /// **'停止语音输入'**
  String get chatSimVoiceStop;

  /// No description provided for @chatSimVoicePreparing.
  ///
  /// In zh_CN, this message translates to:
  /// **'离线语音模型准备中，稍等再试'**
  String get chatSimVoicePreparing;

  /// No description provided for @chatSimVoiceUnavailable.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前设备不支持语音输入'**
  String get chatSimVoiceUnavailable;

  /// No description provided for @chatSimAttach.
  ///
  /// In zh_CN, this message translates to:
  /// **'添加附件'**
  String get chatSimAttach;

  /// No description provided for @chatSimAttachImage.
  ///
  /// In zh_CN, this message translates to:
  /// **'图片'**
  String get chatSimAttachImage;

  /// No description provided for @chatSimAttachFile.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件'**
  String get chatSimAttachFile;

  /// No description provided for @chatSimAttachUserOnly.
  ///
  /// In zh_CN, this message translates to:
  /// **'附件只加在用户消息上'**
  String get chatSimAttachUserOnly;

  /// No description provided for @chatSimRemoved.
  ///
  /// In zh_CN, this message translates to:
  /// **'已删除'**
  String get chatSimRemoved;

  /// No description provided for @chatSimIntro.
  ///
  /// In zh_CN, this message translates to:
  /// **'把这里的对话当成下游客户端发的一条请求，走本机代理的真实链路（路由 / 回退 / 指纹 / 请求日志）。前面的消息会一起带出去。图片会随消息发给模型（纯文本车道可切「仅发文字」），文件只在界面上展示；长按消息可直接删除。'**
  String get chatSimIntro;

  /// No description provided for @chatSimServerOff.
  ///
  /// In zh_CN, this message translates to:
  /// **'服务没在运行，先启动它再发。'**
  String get chatSimServerOff;

  /// No description provided for @chatSimStartServer.
  ///
  /// In zh_CN, this message translates to:
  /// **'启动服务'**
  String get chatSimStartServer;

  /// No description provided for @chatSimNoModel.
  ///
  /// In zh_CN, this message translates to:
  /// **'这一组还没有对外暴露的模型，先在发现页启用它。'**
  String get chatSimNoModel;

  /// No description provided for @chatSimSend.
  ///
  /// In zh_CN, this message translates to:
  /// **'发送'**
  String get chatSimSend;

  /// No description provided for @chatSimSendOnly.
  ///
  /// In zh_CN, this message translates to:
  /// **'仅发送'**
  String get chatSimSendOnly;

  /// No description provided for @chatSimSendOnlyDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'只把请求发出去，不等模型回复'**
  String get chatSimSendOnlyDesc;

  /// No description provided for @chatSimSentOnly.
  ///
  /// In zh_CN, this message translates to:
  /// **'已发送（未等待回复）'**
  String get chatSimSentOnly;

  /// No description provided for @chatSimSendModeOnly.
  ///
  /// In zh_CN, this message translates to:
  /// **'发送（模型不响应）'**
  String get chatSimSendModeOnly;

  /// No description provided for @chatSimSendModeHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'长按切换'**
  String get chatSimSendModeHint;

  /// No description provided for @chatSimSending.
  ///
  /// In zh_CN, this message translates to:
  /// **'生成中…'**
  String get chatSimSending;

  /// No description provided for @chatSimClear.
  ///
  /// In zh_CN, this message translates to:
  /// **'清空对话'**
  String get chatSimClear;

  /// No description provided for @chatSimClearConfirm.
  ///
  /// In zh_CN, this message translates to:
  /// **'清空这次对话？'**
  String get chatSimClearConfirm;

  /// 顶栏「三个点」菜单按钮的提示
  ///
  /// In zh_CN, this message translates to:
  /// **'更多'**
  String get chatSimMore;

  /// 对话模拟：用户/助手头像设置弹层标题
  ///
  /// In zh_CN, this message translates to:
  /// **'头像设置'**
  String get chatSimAvatarTitle;

  /// 头像设置里的用户一行
  ///
  /// In zh_CN, this message translates to:
  /// **'用户头像'**
  String get chatSimAvatarUser;

  /// 头像设置里的助手一行
  ///
  /// In zh_CN, this message translates to:
  /// **'助手头像'**
  String get chatSimAvatarAssistant;

  /// 换头像：从相册选图
  ///
  /// In zh_CN, this message translates to:
  /// **'从相册选择'**
  String get chatSimAvatarPick;

  /// 换头像：拍照
  ///
  /// In zh_CN, this message translates to:
  /// **'拍照'**
  String get chatSimAvatarCamera;

  /// 换头像：恢复默认图标
  ///
  /// In zh_CN, this message translates to:
  /// **'恢复默认'**
  String get chatSimAvatarReset;

  /// 换头像成功的 toast
  ///
  /// In zh_CN, this message translates to:
  /// **'头像已更新'**
  String get chatSimAvatarUpdated;

  /// 换头像失败（选图或压缩失败）
  ///
  /// In zh_CN, this message translates to:
  /// **'头像更新失败：{error}'**
  String chatSimAvatarFailed(String error);

  /// 通话功能入口按钮的提示
  ///
  /// In zh_CN, this message translates to:
  /// **'通话'**
  String get callTitleAction;

  /// 通话页顶部标题：语音模式
  ///
  /// In zh_CN, this message translates to:
  /// **'语音通话'**
  String get callTitleVoice;

  /// 通话页顶部标题：视频模式
  ///
  /// In zh_CN, this message translates to:
  /// **'视频通话'**
  String get callTitleVideo;

  /// 呼叫中的状态文字
  ///
  /// In zh_CN, this message translates to:
  /// **'正在接通…'**
  String get callStatusCalling;

  /// 挂断后的状态文字
  ///
  /// In zh_CN, this message translates to:
  /// **'通话已结束'**
  String get callStatusEnded;

  /// 通话页左划打开的对话记录面板标题
  ///
  /// In zh_CN, this message translates to:
  /// **'对话记录'**
  String get callRecords;

  /// 通话中：正在收音
  ///
  /// In zh_CN, this message translates to:
  /// **'在听…'**
  String get callStatusListening;

  /// 通话中：等待模型回复
  ///
  /// In zh_CN, this message translates to:
  /// **'思考中…'**
  String get callStatusThinking;

  /// 通话中：TTS 播放回复
  ///
  /// In zh_CN, this message translates to:
  /// **'说话中…'**
  String get callStatusSpeaking;

  /// 通话麦克风按钮的中性提示
  ///
  /// In zh_CN, this message translates to:
  /// **'麦克风'**
  String get callMic;

  /// 点麦克风立即提交当前这句
  ///
  /// In zh_CN, this message translates to:
  /// **'说完了'**
  String get callMicDone;

  /// 打断正在播放的回复（需要 Omni）
  ///
  /// In zh_CN, this message translates to:
  /// **'打断'**
  String get callInterrupt;

  /// 非 Omni 模型点视频的提示
  ///
  /// In zh_CN, this message translates to:
  /// **'视频通话需要 Omni 模型'**
  String get callVideoNeedOmni;

  /// 收音引擎起不来时的状态
  ///
  /// In zh_CN, this message translates to:
  /// **'语音识别不可用，检查麦克风权限'**
  String get callAsrUnavailable;

  /// 通话按钮：静音
  ///
  /// In zh_CN, this message translates to:
  /// **'静音'**
  String get callMute;

  /// 通话按钮：取消静音
  ///
  /// In zh_CN, this message translates to:
  /// **'取消静音'**
  String get callUnmute;

  /// 通话按钮：开免提
  ///
  /// In zh_CN, this message translates to:
  /// **'免提'**
  String get callSpeakerOn;

  /// 通话按钮：关免提
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭免提'**
  String get callSpeakerOff;

  /// 通话按钮：切到视频
  ///
  /// In zh_CN, this message translates to:
  /// **'切换到视频通话'**
  String get callSwitchToVideo;

  /// 通话按钮：切回语音
  ///
  /// In zh_CN, this message translates to:
  /// **'切换到语音通话'**
  String get callSwitchToVoice;

  /// 挂断按钮
  ///
  /// In zh_CN, this message translates to:
  /// **'挂断'**
  String get callHangUp;

  /// 通话设置弹层标题
  ///
  /// In zh_CN, this message translates to:
  /// **'通话设置'**
  String get callSettingsTitle;

  /// 通话设置里非 omni 的置灰说明
  ///
  /// In zh_CN, this message translates to:
  /// **'当前模型不是 Omni 模型：基础语音通话照常可用；「允许打断」和「允许调用摄像头」需要 Omni 模型。'**
  String get callSettingsOmniHint;

  /// 通话设置：允许打断
  ///
  /// In zh_CN, this message translates to:
  /// **'允许打断'**
  String get callAllowInterrupt;

  /// 允许打断的说明
  ///
  /// In zh_CN, this message translates to:
  /// **'模型说话时可以随时插话（需要 Omni 模型）'**
  String get callAllowInterruptDesc;

  /// 通话设置：允许调用摄像头
  ///
  /// In zh_CN, this message translates to:
  /// **'允许调用摄像头'**
  String get callAllowCamera;

  /// 允许摄像头的说明
  ///
  /// In zh_CN, this message translates to:
  /// **'视频通话时把摄像头画面发送给模型（需要 Omni 模型）'**
  String get callAllowCameraDesc;

  /// 摄像头被禁时切视频/视频占位的提示
  ///
  /// In zh_CN, this message translates to:
  /// **'已禁止调用摄像头'**
  String get callCameraBlocked;

  /// 视频通话画面占位文字
  ///
  /// In zh_CN, this message translates to:
  /// **'摄像头画面 · 暂未接入'**
  String get callVideoStagePlaceholder;

  /// No description provided for @chatSimRegenerate.
  ///
  /// In zh_CN, this message translates to:
  /// **'重新生成'**
  String get chatSimRegenerate;

  /// No description provided for @chatSimEditTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'编辑消息'**
  String get chatSimEditTitle;

  /// No description provided for @chatSimSave.
  ///
  /// In zh_CN, this message translates to:
  /// **'保存'**
  String get chatSimSave;

  /// No description provided for @chatSimSaveAndSend.
  ///
  /// In zh_CN, this message translates to:
  /// **'保存并发送'**
  String get chatSimSaveAndSend;

  /// No description provided for @chatSimAddMessage.
  ///
  /// In zh_CN, this message translates to:
  /// **'添加消息'**
  String get chatSimAddMessage;

  /// No description provided for @chatSimRoleLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'角色'**
  String get chatSimRoleLabel;

  /// No description provided for @chatSimRoleSystem.
  ///
  /// In zh_CN, this message translates to:
  /// **'系统'**
  String get chatSimRoleSystem;

  /// No description provided for @chatSimRoleUser.
  ///
  /// In zh_CN, this message translates to:
  /// **'用户'**
  String get chatSimRoleUser;

  /// No description provided for @chatSimRoleAssistant.
  ///
  /// In zh_CN, this message translates to:
  /// **'助手'**
  String get chatSimRoleAssistant;

  /// No description provided for @chatSimHintInput.
  ///
  /// In zh_CN, this message translates to:
  /// **'输入一条消息（默认按用户发）'**
  String get chatSimHintInput;

  /// No description provided for @chatSimModelLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'请求模型 {model}'**
  String chatSimModelLabel(String model);

  /// No description provided for @chatSimMeta.
  ///
  /// In zh_CN, this message translates to:
  /// **'字数 {words} · 耗时 {time}'**
  String chatSimMeta(int words, String time);

  /// No description provided for @chatSimServedModel.
  ///
  /// In zh_CN, this message translates to:
  /// **'响应模型 {model}'**
  String chatSimServedModel(String model);

  /// No description provided for @chatSimServedModelVia.
  ///
  /// In zh_CN, this message translates to:
  /// **'响应模型 {lane}（请求 {model}）'**
  String chatSimServedModelVia(String lane, String model);

  /// No description provided for @characterTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'角色卡'**
  String get characterTitle;

  /// No description provided for @characterIntro.
  ///
  /// In zh_CN, this message translates to:
  /// **'给对话模拟换个场景：应用角色卡会替换系统提示词，并按顺序铺上预制问答。'**
  String get characterIntro;

  /// No description provided for @characterDefault.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认场景'**
  String get characterDefault;

  /// No description provided for @characterDefaultDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'通用助手（You are a helpful assistant）'**
  String get characterDefaultDesc;

  /// No description provided for @characterPresetCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'{count} 条预制对话'**
  String characterPresetCount(int count);

  /// No description provided for @characterApplied.
  ///
  /// In zh_CN, this message translates to:
  /// **'已应用角色：{name}'**
  String characterApplied(String name);

  /// No description provided for @characterResetDone.
  ///
  /// In zh_CN, this message translates to:
  /// **'已回到默认场景'**
  String get characterResetDone;

  /// No description provided for @characterCreate.
  ///
  /// In zh_CN, this message translates to:
  /// **'创建角色'**
  String get characterCreate;

  /// No description provided for @characterNewTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'新建角色'**
  String get characterNewTitle;

  /// No description provided for @characterEditTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'编辑角色'**
  String get characterEditTitle;

  /// No description provided for @characterNameLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'角色名'**
  String get characterNameLabel;

  /// No description provided for @characterNameHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'例如：希儿'**
  String get characterNameHint;

  /// No description provided for @characterPromptLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'人设提示词'**
  String get characterPromptLabel;

  /// No description provided for @characterPromptHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'会作为 system 提示词发给模型：写清楚身份、语气与习惯'**
  String get characterPromptHint;

  /// No description provided for @characterPresetsLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'预制对话'**
  String get characterPresetsLabel;

  /// No description provided for @characterPresetsHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'应用后按顺序铺进对话，让开场就带着上下文'**
  String get characterPresetsHint;

  /// No description provided for @characterPresetUser.
  ///
  /// In zh_CN, this message translates to:
  /// **'用户'**
  String get characterPresetUser;

  /// No description provided for @characterPresetAssistant.
  ///
  /// In zh_CN, this message translates to:
  /// **'助手'**
  String get characterPresetAssistant;

  /// No description provided for @characterAddPreset.
  ///
  /// In zh_CN, this message translates to:
  /// **'添加一组问答'**
  String get characterAddPreset;

  /// No description provided for @characterBuiltin.
  ///
  /// In zh_CN, this message translates to:
  /// **'内置'**
  String get characterBuiltin;

  /// No description provided for @characterDeleteConfirm.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除角色「{name}」？'**
  String characterDeleteConfirm(String name);

  /// No description provided for @characterNeedName.
  ///
  /// In zh_CN, this message translates to:
  /// **'先给角色起个名字'**
  String get characterNeedName;

  /// No description provided for @characterActions.
  ///
  /// In zh_CN, this message translates to:
  /// **'更多操作'**
  String get characterActions;

  /// No description provided for @profileViewJson.
  ///
  /// In zh_CN, this message translates to:
  /// **'查看 JSON'**
  String get profileViewJson;

  /// No description provided for @profileJsonTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'组的 JSON'**
  String get profileJsonTitle;

  /// No description provided for @profileJsonBuiltin.
  ///
  /// In zh_CN, this message translates to:
  /// **'这一组由代码生成，下面是它当前的有效内容。'**
  String get profileJsonBuiltin;

  /// No description provided for @profileJsonCopy.
  ///
  /// In zh_CN, this message translates to:
  /// **'复制'**
  String get profileJsonCopy;

  /// No description provided for @profileJsonExport.
  ///
  /// In zh_CN, this message translates to:
  /// **'导出文件'**
  String get profileJsonExport;

  /// No description provided for @profileJsonCopied.
  ///
  /// In zh_CN, this message translates to:
  /// **'已复制 JSON'**
  String get profileJsonCopied;

  /// No description provided for @profileJsonExported.
  ///
  /// In zh_CN, this message translates to:
  /// **'已导出到 {path}'**
  String profileJsonExported(String path);

  /// No description provided for @profileJsonExportFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'导出失败：{error}'**
  String profileJsonExportFailed(String error);

  /// No description provided for @fabAdd.
  ///
  /// In zh_CN, this message translates to:
  /// **'添加'**
  String get fabAdd;

  /// No description provided for @moreAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'更多操作'**
  String get moreAction;

  /// No description provided for @profileSourceBuiltin.
  ///
  /// In zh_CN, this message translates to:
  /// **'内置'**
  String get profileSourceBuiltin;

  /// No description provided for @profileSourceUrl.
  ///
  /// In zh_CN, this message translates to:
  /// **'订阅'**
  String get profileSourceUrl;

  /// No description provided for @profileSourceFile.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件'**
  String get profileSourceFile;

  /// No description provided for @profileSourceInline.
  ///
  /// In zh_CN, this message translates to:
  /// **'粘贴'**
  String get profileSourceInline;

  /// No description provided for @profileUpdateAvailable.
  ///
  /// In zh_CN, this message translates to:
  /// **'有更新'**
  String get profileUpdateAvailable;

  /// No description provided for @profileCustomizedTag.
  ///
  /// In zh_CN, this message translates to:
  /// **'已手动改过'**
  String get profileCustomizedTag;

  /// No description provided for @profileLanesAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'查看车道'**
  String get profileLanesAction;

  /// No description provided for @profileUpdateAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'立即更新'**
  String get profileUpdateAction;

  /// No description provided for @profileDeleteAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除档案'**
  String get profileDeleteAction;

  /// No description provided for @profileDeleteConfirm.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除「{name}」？它装进来的上游会一并摘掉。'**
  String profileDeleteConfirm(String name);

  /// No description provided for @profileDeleted.
  ///
  /// In zh_CN, this message translates to:
  /// **'已删除「{name}」'**
  String profileDeleted(String name);

  /// No description provided for @profileStats.
  ///
  /// In zh_CN, this message translates to:
  /// **'{upstreams} 个上游 · {lanes} 条车道'**
  String profileStats(int upstreams, int lanes);

  /// No description provided for @profileNeverUpdated.
  ///
  /// In zh_CN, this message translates to:
  /// **'尚未更新'**
  String get profileNeverUpdated;

  /// No description provided for @profileLastUpdated.
  ///
  /// In zh_CN, this message translates to:
  /// **'上次更新 {time}'**
  String profileLastUpdated(String time);

  /// No description provided for @profilePullHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'下拉刷新可用模型列表'**
  String get profilePullHint;

  /// No description provided for @profileIdConflict.
  ///
  /// In zh_CN, this message translates to:
  /// **'上游 id 已被占用，这份档案没有装入'**
  String get profileIdConflict;

  /// No description provided for @profileBuiltinZenSummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'免登录接入 OpenCode Zen 的免费模型车道；对外名 zen-free 自带顺序回退。'**
  String get profileBuiltinZenSummary;

  /// No description provided for @profileImportTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'添加配置文件'**
  String get profileImportTitle;

  /// No description provided for @profileImportTabUrl.
  ///
  /// In zh_CN, this message translates to:
  /// **'订阅地址'**
  String get profileImportTabUrl;

  /// No description provided for @profileImportTabFile.
  ///
  /// In zh_CN, this message translates to:
  /// **'本地文件'**
  String get profileImportTabFile;

  /// No description provided for @profileImportTabPaste.
  ///
  /// In zh_CN, this message translates to:
  /// **'粘贴 JSON'**
  String get profileImportTabPaste;

  /// No description provided for @profileImportUrlHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'https://example.com/profile.json'**
  String get profileImportUrlHint;

  /// No description provided for @profileImportPickFile.
  ///
  /// In zh_CN, this message translates to:
  /// **'选择 JSON 文件'**
  String get profileImportPickFile;

  /// No description provided for @profileImportPasteHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'把档案 JSON 粘到这里'**
  String get profileImportPasteHint;

  /// No description provided for @profileImportNote.
  ///
  /// In zh_CN, this message translates to:
  /// **'档案只描述模型从哪来，不会改监听端口、密钥和访问规则。'**
  String get profileImportNote;

  /// No description provided for @profileImportSubmit.
  ///
  /// In zh_CN, this message translates to:
  /// **'导入'**
  String get profileImportSubmit;

  /// No description provided for @profileImported.
  ///
  /// In zh_CN, this message translates to:
  /// **'已导入「{name}」'**
  String profileImported(String name);

  /// No description provided for @profileFormatEmpty.
  ///
  /// In zh_CN, this message translates to:
  /// **'内容是空的'**
  String get profileFormatEmpty;

  /// No description provided for @profileFormatNotJson.
  ///
  /// In zh_CN, this message translates to:
  /// **'不是合法 JSON（Clash 订阅是 YAML，这里不吃）'**
  String get profileFormatNotJson;

  /// No description provided for @profileFormatNotObject.
  ///
  /// In zh_CN, this message translates to:
  /// **'顶层得是一个 JSON 对象'**
  String get profileFormatNotObject;

  /// No description provided for @profileFormatUnsupportedSchema.
  ///
  /// In zh_CN, this message translates to:
  /// **'档案格式版本不支持'**
  String get profileFormatUnsupportedSchema;

  /// No description provided for @profileFormatMissingId.
  ///
  /// In zh_CN, this message translates to:
  /// **'档案缺 id（也没写 name 可以推）'**
  String get profileFormatMissingId;

  /// No description provided for @profileFormatNoUpstreams.
  ///
  /// In zh_CN, this message translates to:
  /// **'档案里一个上游都没有'**
  String get profileFormatNoUpstreams;

  /// No description provided for @profileFormatDuplicateId.
  ///
  /// In zh_CN, this message translates to:
  /// **'已经有一份同 id 的档案了'**
  String get profileFormatDuplicateId;

  /// No description provided for @laneHintNotInstalled.
  ///
  /// In zh_CN, this message translates to:
  /// **'这份档案还没启用，先在发现页点一下卡片装上它。'**
  String get laneHintNotInstalled;

  /// No description provided for @laneFallbackHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'客户端把 model 填成 {name} 即可走容灾。'**
  String laneFallbackHint(String name);

  /// No description provided for @uiStyleLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'界面风格'**
  String get uiStyleLabel;

  /// No description provided for @uiStyleNote.
  ///
  /// In zh_CN, this message translates to:
  /// **'切换后整个应用改用另一套页面实现'**
  String get uiStyleNote;

  /// No description provided for @uiStyleMaterial.
  ///
  /// In zh_CN, this message translates to:
  /// **'Material 3 Expressive'**
  String get uiStyleMaterial;

  /// No description provided for @uiStyleMiuix.
  ///
  /// In zh_CN, this message translates to:
  /// **'小米 HyperOS'**
  String get uiStyleMiuix;

  /// No description provided for @miuixPullToRefresh.
  ///
  /// In zh_CN, this message translates to:
  /// **'下拉刷新'**
  String get miuixPullToRefresh;

  /// No description provided for @miuixReleaseToRefresh.
  ///
  /// In zh_CN, this message translates to:
  /// **'松开立即刷新'**
  String get miuixReleaseToRefresh;

  /// No description provided for @miuixRefreshing.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在刷新…'**
  String get miuixRefreshing;

  /// No description provided for @miuixRefreshDone.
  ///
  /// In zh_CN, this message translates to:
  /// **'刷新完成'**
  String get miuixRefreshDone;

  /// No description provided for @navBarStyleLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'底部导航栏'**
  String get navBarStyleLabel;

  /// No description provided for @navBarStyleNote.
  ///
  /// In zh_CN, this message translates to:
  /// **'液态玻璃走原生渲染，普通档用系统导航栏'**
  String get navBarStyleNote;

  /// No description provided for @navBarStyleGlass.
  ///
  /// In zh_CN, this message translates to:
  /// **'液态玻璃'**
  String get navBarStyleGlass;

  /// No description provided for @navBarStylePlain.
  ///
  /// In zh_CN, this message translates to:
  /// **'普通'**
  String get navBarStylePlain;

  /// No description provided for @displayIosPushTransitionCorner.
  ///
  /// In zh_CN, this message translates to:
  /// **'转场圆角'**
  String get displayIosPushTransitionCorner;

  /// No description provided for @displayIosPushTransitionCornerAuto.
  ///
  /// In zh_CN, this message translates to:
  /// **'跟随设备屏幕圆角'**
  String get displayIosPushTransitionCornerAuto;

  /// No description provided for @displayIosPushTransitionCornerUnsupported.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前设备读不到屏幕圆角，改用下面这个手动值'**
  String get displayIosPushTransitionCornerUnsupported;

  /// No description provided for @edgeHapticLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'滑动触感反馈'**
  String get edgeHapticLabel;

  /// No description provided for @edgeHapticNote.
  ///
  /// In zh_CN, this message translates to:
  /// **'快速滑动到顶部/底部时轻震一下'**
  String get edgeHapticNote;

  /// No description provided for @shortcutStartService.
  ///
  /// In zh_CN, this message translates to:
  /// **'启动服务'**
  String get shortcutStartService;

  /// No description provided for @shortcutStopService.
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭服务'**
  String get shortcutStopService;

  /// No description provided for @shortcutTokenStats.
  ///
  /// In zh_CN, this message translates to:
  /// **'查看 Token 用量'**
  String get shortcutTokenStats;

  /// No description provided for @tasksDialogTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'任务'**
  String get tasksDialogTitle;

  /// No description provided for @taskPauseServer.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂停服务'**
  String get taskPauseServer;

  /// No description provided for @taskListenOn.
  ///
  /// In zh_CN, this message translates to:
  /// **'监听 {address}'**
  String taskListenOn(String address);

  /// No description provided for @taskStopListening.
  ///
  /// In zh_CN, this message translates to:
  /// **'停止监听'**
  String get taskStopListening;

  /// No description provided for @tasksRecentSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'最近'**
  String get tasksRecentSection;

  /// No description provided for @tasksModelCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'{count} 个模型'**
  String tasksModelCount(int count);

  /// No description provided for @createConfigScanTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'扫描二维码'**
  String get createConfigScanTitle;

  /// No description provided for @createConfigScanDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'扫码或从相册识别来添加配置'**
  String get createConfigScanDesc;

  /// No description provided for @qrScannerTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'扫描二维码'**
  String get qrScannerTitle;

  /// No description provided for @qrScannerHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'对准屏幕任意位置，识别到二维码自动跳转'**
  String get qrScannerHint;

  /// No description provided for @qrScannerPermissionTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'需要相机权限'**
  String get qrScannerPermissionTitle;

  /// No description provided for @qrScannerPermissionDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'扫码需要使用相机，请在系统设置中允许本应用访问相机。'**
  String get qrScannerPermissionDesc;

  /// No description provided for @qrScannerOpenSettings.
  ///
  /// In zh_CN, this message translates to:
  /// **'去设置'**
  String get qrScannerOpenSettings;

  /// No description provided for @qrScannerRetry.
  ///
  /// In zh_CN, this message translates to:
  /// **'重试'**
  String get qrScannerRetry;

  /// No description provided for @qrScannerUnsupported.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前平台不支持扫码，请在 Android / iOS 设备上使用'**
  String get qrScannerUnsupported;

  /// No description provided for @qrScannerSwitchCamera.
  ///
  /// In zh_CN, this message translates to:
  /// **'切换前后摄像头'**
  String get qrScannerSwitchCamera;

  /// No description provided for @qrScannerGallery.
  ///
  /// In zh_CN, this message translates to:
  /// **'从相册识别'**
  String get qrScannerGallery;

  /// No description provided for @qrScannerGalleryEmpty.
  ///
  /// In zh_CN, this message translates to:
  /// **'图片里没有识别到二维码'**
  String get qrScannerGalleryEmpty;

  /// No description provided for @qrResultTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'扫码结果'**
  String get qrResultTitle;

  /// No description provided for @qrResultKindProfile.
  ///
  /// In zh_CN, this message translates to:
  /// **'配置档案 JSON'**
  String get qrResultKindProfile;

  /// No description provided for @qrResultKindUpstream.
  ///
  /// In zh_CN, this message translates to:
  /// **'上游 JSON'**
  String get qrResultKindUpstream;

  /// No description provided for @qrResultKindUrl.
  ///
  /// In zh_CN, this message translates to:
  /// **'网页链接'**
  String get qrResultKindUrl;

  /// No description provided for @qrResultKindText.
  ///
  /// In zh_CN, this message translates to:
  /// **'纯文本'**
  String get qrResultKindText;

  /// No description provided for @qrResultImportProfile.
  ///
  /// In zh_CN, this message translates to:
  /// **'导入配置文件'**
  String get qrResultImportProfile;

  /// No description provided for @qrResultAddUpstream.
  ///
  /// In zh_CN, this message translates to:
  /// **'添加为上游'**
  String get qrResultAddUpstream;

  /// No description provided for @qrResultImportUrl.
  ///
  /// In zh_CN, this message translates to:
  /// **'导入订阅'**
  String get qrResultImportUrl;

  /// No description provided for @qrResultUpstreamAdded.
  ///
  /// In zh_CN, this message translates to:
  /// **'已添加上游「{name}」'**
  String qrResultUpstreamAdded(String name);

  /// No description provided for @upstreamQrTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'上游二维码'**
  String get upstreamQrTitle;

  /// No description provided for @upstreamQrHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'用另一台装了本应用的设备扫一扫，即可把这个上游导入到它的规则里。'**
  String get upstreamQrHint;

  /// No description provided for @upstreamQrTooLong.
  ///
  /// In zh_CN, this message translates to:
  /// **'内容过长，生成不了二维码'**
  String get upstreamQrTooLong;

  /// No description provided for @progressiveTopBarTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'渐变模糊顶栏'**
  String get progressiveTopBarTitle;

  /// No description provided for @progressiveTopBarDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'顶栏透明化，顶部渐进模糊随内容滚入淡入'**
  String get progressiveTopBarDesc;

  /// No description provided for @navBarStyleFloating.
  ///
  /// In zh_CN, this message translates to:
  /// **'悬浮'**
  String get navBarStyleFloating;

  /// No description provided for @biometricLockTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'生物识别锁'**
  String get biometricLockTitle;

  /// No description provided for @biometricLockDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'打开应用时需要验证指纹 / 人脸（Android）'**
  String get biometricLockDesc;

  /// No description provided for @biometricLockUnavailable.
  ///
  /// In zh_CN, this message translates to:
  /// **'此设备没有可用的生物识别或屏幕锁凭据'**
  String get biometricLockUnavailable;

  /// No description provided for @biometricGateTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'Local2API 已锁定'**
  String get biometricGateTitle;

  /// No description provided for @biometricGateHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'验证生物识别以继续'**
  String get biometricGateHint;

  /// No description provided for @biometricUnlock.
  ///
  /// In zh_CN, this message translates to:
  /// **'解锁'**
  String get biometricUnlock;

  /// No description provided for @networkTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'网络'**
  String get networkTitle;

  /// No description provided for @networkEntryDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'Cloudflare Tunnel / Tailscale'**
  String get networkEntryDesc;

  /// No description provided for @cfTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'Cloudflare Tunnel'**
  String get cfTitle;

  /// No description provided for @cfDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'通过 trycloudflare 临时隧道，把本服务公开到互联网'**
  String get cfDesc;

  /// No description provided for @cfEnableSwitch.
  ///
  /// In zh_CN, this message translates to:
  /// **'启用 trycloudflare'**
  String get cfEnableSwitch;

  /// No description provided for @cfTermsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'Cloudflare 许可协议'**
  String get cfTermsTitle;

  /// No description provided for @cfTermsAgree.
  ///
  /// In zh_CN, this message translates to:
  /// **'同意并启用'**
  String get cfTermsAgree;

  /// No description provided for @cfTermsDecline.
  ///
  /// In zh_CN, this message translates to:
  /// **'不同意'**
  String get cfTermsDecline;

  /// No description provided for @cfTermsFetchFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'许可协议拉取失败，请检查网络后重试'**
  String get cfTermsFetchFailed;

  /// No description provided for @cfTermsNote.
  ///
  /// In zh_CN, this message translates to:
  /// **'启用前需要同意 Cloudflare 的服务条款（trycloudflare.com）。'**
  String get cfTermsNote;

  /// No description provided for @cfStarting.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在启动隧道…'**
  String get cfStarting;

  /// No description provided for @cfRunning.
  ///
  /// In zh_CN, this message translates to:
  /// **'隧道运行中'**
  String get cfRunning;

  /// No description provided for @cfStopped.
  ///
  /// In zh_CN, this message translates to:
  /// **'未运行'**
  String get cfStopped;

  /// No description provided for @cfPublicUrl.
  ///
  /// In zh_CN, this message translates to:
  /// **'公开地址'**
  String get cfPublicUrl;

  /// No description provided for @cfBinaryMissing.
  ///
  /// In zh_CN, this message translates to:
  /// **'没有找到 cloudflared。内建隧道目前只在桌面端可用（PATH 里装好 cloudflared 后重试）。'**
  String get cfBinaryMissing;

  /// No description provided for @cfRetry.
  ///
  /// In zh_CN, this message translates to:
  /// **'重试'**
  String get cfRetry;

  /// No description provided for @cfStop.
  ///
  /// In zh_CN, this message translates to:
  /// **'停止'**
  String get cfStop;

  /// No description provided for @tsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'Tailscale'**
  String get tsTitle;

  /// No description provided for @tsDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'在 Tailscale 网络内访问本服务（100.64.0.0/10 网段）'**
  String get tsDesc;

  /// No description provided for @tsAllowSwitch.
  ///
  /// In zh_CN, this message translates to:
  /// **'放行 Tailscale 网段'**
  String get tsAllowSwitch;

  /// No description provided for @tsDetected.
  ///
  /// In zh_CN, this message translates to:
  /// **'检测到 Tailscale IP：{ip}'**
  String tsDetected(String ip);

  /// No description provided for @tsNotDetected.
  ///
  /// In zh_CN, this message translates to:
  /// **'未检测到 Tailscale 接口（本机没装或没连）'**
  String get tsNotDetected;

  /// No description provided for @tsDownloadTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'获取 Tailscale'**
  String get tsDownloadTitle;

  /// No description provided for @tsDownloadDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'在手机 / 电脑上安装 Tailscale，随时随地访问本服务'**
  String get tsDownloadDesc;

  /// No description provided for @tsOpenDownload.
  ///
  /// In zh_CN, this message translates to:
  /// **'打开下载页'**
  String get tsOpenDownload;

  /// No description provided for @securitySection.
  ///
  /// In zh_CN, this message translates to:
  /// **'安全'**
  String get securitySection;

  /// 独立的网页控制台页面标题
  ///
  /// In zh_CN, this message translates to:
  /// **'临时 WebUI'**
  String get webUiTitle;

  /// 临时 WebUI 的说明
  ///
  /// In zh_CN, this message translates to:
  /// **'和 API 转发分开的端口，用来临时在浏览器里试模型'**
  String get webUiDesc;

  /// WebUI 开关
  ///
  /// In zh_CN, this message translates to:
  /// **'启用临时 WebUI'**
  String get webUiEnable;

  /// WebUI 开关说明
  ///
  /// In zh_CN, this message translates to:
  /// **'关掉就停掉网页服务，不影响 API 转发'**
  String get webUiToggleHint;

  /// WebUI 端口字段
  ///
  /// In zh_CN, this message translates to:
  /// **'WebUI 端口'**
  String get webUiPort;

  /// WebUI 监听地址字段
  ///
  /// In zh_CN, this message translates to:
  /// **'WebUI 监听地址'**
  String get webUiHost;

  /// WebUI 运行中
  ///
  /// In zh_CN, this message translates to:
  /// **'网页已启动'**
  String get webUiRunning;

  /// WebUI 未运行
  ///
  /// In zh_CN, this message translates to:
  /// **'网页未启动'**
  String get webUiStopped;

  /// WebUI 启动失败
  ///
  /// In zh_CN, this message translates to:
  /// **'网页启动失败'**
  String get webUiFailed;

  /// 打开网页按钮
  ///
  /// In zh_CN, this message translates to:
  /// **'在浏览器打开'**
  String get webUiOpen;

  /// 复制网页地址
  ///
  /// In zh_CN, this message translates to:
  /// **'复制地址'**
  String get webUiCopyUrl;

  /// 设置页入口描述
  ///
  /// In zh_CN, this message translates to:
  /// **'端口、开关、浏览器入口'**
  String get webUiEntryDesc;

  /// WebUI 与 API 端口关系的说明
  ///
  /// In zh_CN, this message translates to:
  /// **'页面上的请求仍然打 API 端口，两个端口互不干扰'**
  String get webUiNote;

  /// 峰谷策略页标题
  ///
  /// In zh_CN, this message translates to:
  /// **'峰谷时段'**
  String get scheduleTitle;

  /// 设置页入口描述
  ///
  /// In zh_CN, this message translates to:
  /// **'按星期和时间段限制模型 / 模型组'**
  String get scheduleEntryDesc;

  /// 策略说明
  ///
  /// In zh_CN, this message translates to:
  /// **'正向：只有选中的时间段能用。反向：选中的时间段禁用。对话模拟不受影响。'**
  String get scheduleDesc;

  /// 空态文案
  ///
  /// In zh_CN, this message translates to:
  /// **'还没有策略：不加就是全天可用'**
  String get scheduleEmpty;

  /// 新增按钮
  ///
  /// In zh_CN, this message translates to:
  /// **'添加策略'**
  String get scheduleAdd;

  /// 策略对象
  ///
  /// In zh_CN, this message translates to:
  /// **'作用对象'**
  String get scheduleTarget;

  /// 模型级
  ///
  /// In zh_CN, this message translates to:
  /// **'单个模型'**
  String get scheduleTargetModel;

  /// 组级
  ///
  /// In zh_CN, this message translates to:
  /// **'模型组'**
  String get scheduleTargetGroup;

  /// 模型选择
  ///
  /// In zh_CN, this message translates to:
  /// **'模型'**
  String get scheduleModel;

  /// 模型组选择
  ///
  /// In zh_CN, this message translates to:
  /// **'模型组'**
  String get scheduleGroup;

  /// 正向/反向
  ///
  /// In zh_CN, this message translates to:
  /// **'策略方向'**
  String get scheduleMode;

  /// 正向
  ///
  /// In zh_CN, this message translates to:
  /// **'正向（选中时段才能用）'**
  String get scheduleModeAllow;

  /// 反向
  ///
  /// In zh_CN, this message translates to:
  /// **'反向（选中时段禁止用）'**
  String get scheduleModeDeny;

  /// 星期选择
  ///
  /// In zh_CN, this message translates to:
  /// **'星期'**
  String get scheduleWeekdays;

  /// No description provided for @scheduleSelectAll.
  ///
  /// In zh_CN, this message translates to:
  /// **'全选'**
  String get scheduleSelectAll;

  /// No description provided for @scheduleUpstreamHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'只作用于这个上游的模型；全选就等于给整个上游套窗口。改动即时生效，不用点保存。'**
  String get scheduleUpstreamHint;

  /// No description provided for @scheduleUpstreamNoModel.
  ///
  /// In zh_CN, this message translates to:
  /// **'这个上游还没有对外模型，先在「对外模型」里加几个。'**
  String get scheduleUpstreamNoModel;

  /// No description provided for @schedulePickWeekday.
  ///
  /// In zh_CN, this message translates to:
  /// **'选择星期'**
  String get schedulePickWeekday;

  /// 小时区间
  ///
  /// In zh_CN, this message translates to:
  /// **'时间段'**
  String get scheduleHours;

  /// 小时区间展示
  ///
  /// In zh_CN, this message translates to:
  /// **'{start}:00 - {end}:00'**
  String scheduleHourRange(String start, String end);

  /// 策略开关
  ///
  /// In zh_CN, this message translates to:
  /// **'启用这条策略'**
  String get scheduleEnabled;

  /// 删除按钮
  ///
  /// In zh_CN, this message translates to:
  /// **'删除策略'**
  String get scheduleDelete;

  /// 保存提示
  ///
  /// In zh_CN, this message translates to:
  /// **'策略已保存'**
  String get scheduleSaved;

  /// 删除提示
  ///
  /// In zh_CN, this message translates to:
  /// **'策略已删除'**
  String get scheduleDeleted;

  /// 模拟对话不受限说明
  ///
  /// In zh_CN, this message translates to:
  /// **'对话模拟永远可用，不受这些策略限制'**
  String get scheduleSimNote;

  /// 选择对象对话框标题
  ///
  /// In zh_CN, this message translates to:
  /// **'选一个模型或模型组'**
  String get schedulePickTarget;

  /// 小时选择对话框标题
  ///
  /// In zh_CN, this message translates to:
  /// **'选择小时'**
  String get schedulePickHour;

  /// 起始小时
  ///
  /// In zh_CN, this message translates to:
  /// **'起始'**
  String get scheduleStartHour;

  /// 结束小时
  ///
  /// In zh_CN, this message translates to:
  /// **'结束'**
  String get scheduleEndHour;

  /// 全天选项
  ///
  /// In zh_CN, this message translates to:
  /// **'全天'**
  String get scheduleAllDay;

  /// 策略条数
  ///
  /// In zh_CN, this message translates to:
  /// **'{count} 条策略'**
  String scheduleStatus(String count);

  /// 模型编辑里的最大上下文数字段
  ///
  /// In zh_CN, this message translates to:
  /// **'最大上下文数'**
  String get modelContextLabel;

  /// 上下文长度字段的说明
  ///
  /// In zh_CN, this message translates to:
  /// **'对外声明给客户端的上下文 token 数；留空按默认 1M，拉取模型列表时也会自动补'**
  String get modelContextHelper;

  /// 模型行尾的上下文长度徽标
  ///
  /// In zh_CN, this message translates to:
  /// **'上下文 {value}'**
  String modelContextShort(String value);

  /// 自动回填上下文长度后的提示
  ///
  /// In zh_CN, this message translates to:
  /// **'已从上游获取 {count} 个模型的上下文长度'**
  String contextAutoFilled(String count);

  /// 模型编辑里的最大输出数字段
  ///
  /// In zh_CN, this message translates to:
  /// **'最大输出数'**
  String get modelOutputLabel;

  /// 最大输出数字段的说明
  ///
  /// In zh_CN, this message translates to:
  /// **'对外声明的最大输出 token 数；留空不声明'**
  String get modelOutputHelper;

  /// 上下文占用环的悬停说明
  ///
  /// In zh_CN, this message translates to:
  /// **'上下文占用 {percent}%（{used} / {total} tokens）'**
  String contextRingInfo(String percent, String used, String total);

  /// 占用为估算值时的补充说明
  ///
  /// In zh_CN, this message translates to:
  /// **'，按字数估算'**
  String get contextRingEstimated;

  /// 占用环的悬停提示（点开看详情）
  ///
  /// In zh_CN, this message translates to:
  /// **'点击查看上下文详情'**
  String get contextRingTap;

  /// 上下文详情弹窗标题
  ///
  /// In zh_CN, this message translates to:
  /// **'上下文占用'**
  String get contextDetailTitle;

  /// 弹窗里的百分比一行
  ///
  /// In zh_CN, this message translates to:
  /// **'占上下文 {percent}%'**
  String contextDetailPercent(String percent);

  /// 弹窗里的 token 用量一行
  ///
  /// In zh_CN, this message translates to:
  /// **'{used} / {total} tokens'**
  String contextDetailUsed(String used, String total);

  /// 数字来自上游 usage 时的说明
  ///
  /// In zh_CN, this message translates to:
  /// **'取自上一轮响应的 usage（精确值）'**
  String get contextDetailFromUsage;

  /// 数字是本地估算时的说明
  ///
  /// In zh_CN, this message translates to:
  /// **'按字数与图片粗估（上游没回 usage）'**
  String get contextDetailEstimated;

  /// 声明了最大输出时的一行
  ///
  /// In zh_CN, this message translates to:
  /// **'最大输出 {limit} tokens'**
  String contextDetailOutput(String limit);

  /// 没声明最大输出时的一行
  ///
  /// In zh_CN, this message translates to:
  /// **'最大输出未声明'**
  String get contextDetailOutputNone;

  /// 当前请求目标模型
  ///
  /// In zh_CN, this message translates to:
  /// **'请求模型 {model}'**
  String contextDetailModel(String model);

  /// 消息条数与图片张数
  ///
  /// In zh_CN, this message translates to:
  /// **'{count} 条消息 · {images} 张图片'**
  String contextDetailMessages(String count, String images);

  /// 弹窗关闭按钮
  ///
  /// In zh_CN, this message translates to:
  /// **'知道了'**
  String get contextDetailClose;

  /// 带图发送开关（开）
  ///
  /// In zh_CN, this message translates to:
  /// **'发送图片'**
  String get chatSimSendImages;

  /// 带图发送开关（关）
  ///
  /// In zh_CN, this message translates to:
  /// **'仅发文字'**
  String get chatSimSendTextOnly;

  /// 带图发送开关的说明
  ///
  /// In zh_CN, this message translates to:
  /// **'图片会作为多模态内容一起发给模型；纯文本车道报错时切到「仅发文字」，图就只留在界面上。'**
  String get chatSimSendImagesTip;

  /// 切到「发送图片」时的 toast
  ///
  /// In zh_CN, this message translates to:
  /// **'图片会随消息发出'**
  String get chatSimImagesOn;

  /// 切到「仅发文字」时的 toast
  ///
  /// In zh_CN, this message translates to:
  /// **'图片只在本地展示，不发给模型'**
  String get chatSimImagesOff;

  /// 附件清单里的拍照项
  ///
  /// In zh_CN, this message translates to:
  /// **'拍照'**
  String get chatSimAttachCamera;

  /// 选图/读文件失败
  ///
  /// In zh_CN, this message translates to:
  /// **'读取附件失败：{error}'**
  String chatSimAttachFailed(String error);

  /// 麦克风权限被拒
  ///
  /// In zh_CN, this message translates to:
  /// **'没有麦克风权限，无法语音输入'**
  String get chatSimVoiceNoPermission;

  /// 去系统设置开权限
  ///
  /// In zh_CN, this message translates to:
  /// **'去设置'**
  String get chatSimVoiceOpenSettings;

  /// 识别过程报错
  ///
  /// In zh_CN, this message translates to:
  /// **'语音输入失败：{error}'**
  String chatSimVoiceFailed(String error);

  /// 录音弹层的底栏提示（未按下时）
  ///
  /// In zh_CN, this message translates to:
  /// **'按住说话'**
  String get voiceHoldToTalk;

  /// 录音弹层的底栏提示（按住中）
  ///
  /// In zh_CN, this message translates to:
  /// **'松开结束'**
  String get voiceReleaseToSend;

  /// 收音中还没有识别文本时的提示
  ///
  /// In zh_CN, this message translates to:
  /// **'正在聆听…'**
  String get voiceListeningHint;

  /// 松手后等最后一版定稿的提示
  ///
  /// In zh_CN, this message translates to:
  /// **'识别中…'**
  String get voiceRecognizing;

  /// 松手后一条结果都没拿到
  ///
  /// In zh_CN, this message translates to:
  /// **'没听清，再按住说一次'**
  String get voiceNothingHeard;

  /// 通话选择弹层里语音选项的摘要（当前角色名）
  ///
  /// In zh_CN, this message translates to:
  /// **'和 {name} 通话'**
  String chatSimCallPeer(String name);

  /// No description provided for @chatSimMsgMenuTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'消息操作'**
  String get chatSimMsgMenuTitle;

  /// No description provided for @chatSimMsgSpeak.
  ///
  /// In zh_CN, this message translates to:
  /// **'朗读'**
  String get chatSimMsgSpeak;

  /// No description provided for @chatSimMsgStopSpeak.
  ///
  /// In zh_CN, this message translates to:
  /// **'停止朗读'**
  String get chatSimMsgStopSpeak;

  /// No description provided for @chatSimMsgRegenerate.
  ///
  /// In zh_CN, this message translates to:
  /// **'重新回答'**
  String get chatSimMsgRegenerate;

  /// No description provided for @chatSimMsgDownload.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载音频'**
  String get chatSimMsgDownload;

  /// No description provided for @chatSimDownloadTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载音频'**
  String get chatSimDownloadTitle;

  /// No description provided for @chatSimDownloadFormat.
  ///
  /// In zh_CN, this message translates to:
  /// **'格式'**
  String get chatSimDownloadFormat;

  /// No description provided for @chatSimDownloadMp3Desc.
  ///
  /// In zh_CN, this message translates to:
  /// **'通用音频，兼容性最好'**
  String get chatSimDownloadMp3Desc;

  /// No description provided for @chatSimDownloadSilkDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'SILK v3，微信 / QQ 的语音格式'**
  String get chatSimDownloadSilkDesc;

  /// No description provided for @chatSimDownloadSlkDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'与 SILK 字节相同，只是扩展名不同'**
  String get chatSimDownloadSlkDesc;

  /// No description provided for @chatSimDownloadTencent.
  ///
  /// In zh_CN, this message translates to:
  /// **'腾讯兼容（-tencent）'**
  String get chatSimDownloadTencent;

  /// No description provided for @chatSimDownloadTencentDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件头加 0x02、结尾不写哨兵包，微信 / QQ 才认'**
  String get chatSimDownloadTencentDesc;

  /// No description provided for @chatSimDownloadAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载'**
  String get chatSimDownloadAction;

  /// No description provided for @chatSimDownloadBusy.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在合成音频…'**
  String get chatSimDownloadBusy;

  /// No description provided for @chatSimDownloadCanceled.
  ///
  /// In zh_CN, this message translates to:
  /// **'已取消保存'**
  String get chatSimDownloadCanceled;

  /// 另存为完成后回报的落盘路径
  ///
  /// In zh_CN, this message translates to:
  /// **'已保存：{path}'**
  String chatSimDownloadSaved(String path);

  /// 合成 / 转码 / 存盘任一步的错误文案
  ///
  /// In zh_CN, this message translates to:
  /// **'导出失败：{error}'**
  String chatSimDownloadFailed(String error);

  /// No description provided for @balanceTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'余额'**
  String get balanceTitle;

  /// No description provided for @balanceEntryDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'查询这个上游的账户余额'**
  String get balanceEntryDesc;

  /// No description provided for @balancePullHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'下拉刷新余额'**
  String get balancePullHint;

  /// No description provided for @balanceRefreshing.
  ///
  /// In zh_CN, this message translates to:
  /// **'查询中…'**
  String get balanceRefreshing;

  /// No description provided for @balanceNoKey.
  ///
  /// In zh_CN, this message translates to:
  /// **'先填密钥再查余额'**
  String get balanceNoKey;

  /// No description provided for @balanceUnsupported.
  ///
  /// In zh_CN, this message translates to:
  /// **'该上游不支持余额查询'**
  String get balanceUnsupported;

  /// No description provided for @balanceNoData.
  ///
  /// In zh_CN, this message translates to:
  /// **'没有返回余额'**
  String get balanceNoData;

  /// No description provided for @balanceAvailableLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'可用余额'**
  String get balanceAvailableLabel;

  /// No description provided for @balanceGrantedLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'赠送余额'**
  String get balanceGrantedLabel;

  /// No description provided for @balanceToppedUpLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'充值余额'**
  String get balanceToppedUpLabel;

  /// No description provided for @balanceUsedLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'已用额度'**
  String get balanceUsedLabel;

  /// No description provided for @balanceRequestsLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'累计请求'**
  String get balanceRequestsLabel;

  /// No description provided for @balanceGroupLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'分组'**
  String get balanceGroupLabel;

  /// No description provided for @balanceSourceLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'查询接口'**
  String get balanceSourceLabel;

  /// No description provided for @balanceStatusOk.
  ///
  /// In zh_CN, this message translates to:
  /// **'账号可正常调用'**
  String get balanceStatusOk;

  /// No description provided for @balanceStatusBad.
  ///
  /// In zh_CN, this message translates to:
  /// **'账号不可用（欠费或受限）'**
  String get balanceStatusBad;

  /// No description provided for @balanceQuotaNote.
  ///
  /// In zh_CN, this message translates to:
  /// **'按 1 美元 = 500000 额度换算'**
  String get balanceQuotaNote;

  /// 余额查询失败原因
  ///
  /// In zh_CN, this message translates to:
  /// **'查询失败：{error}'**
  String balanceFailed(String error);

  /// 上次刷新的时刻
  ///
  /// In zh_CN, this message translates to:
  /// **'上次更新 {time}'**
  String balanceUpdatedAt(String time);

  /// No description provided for @balanceDetailsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'余额明细'**
  String get balanceDetailsTitle;

  /// No description provided for @balanceLimitLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'额度上限'**
  String get balanceLimitLabel;

  /// No description provided for @balanceUnauthorized.
  ///
  /// In zh_CN, this message translates to:
  /// **'密钥无效或无权读取账户'**
  String get balanceUnauthorized;

  /// No description provided for @balanceBadResponse.
  ///
  /// In zh_CN, this message translates to:
  /// **'余额接口返回的内容读不懂'**
  String get balanceBadResponse;

  /// No description provided for @balanceNoKeyHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'填好密钥后再刷新'**
  String get balanceNoKeyHint;

  /// No description provided for @balanceUnauthorizedHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'确认密钥有效，且允许读取账户信息'**
  String get balanceUnauthorizedHint;

  /// No description provided for @balanceUnsupportedHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'不是所有上游都有余额接口'**
  String get balanceUnsupportedHint;

  /// No description provided for @balanceNetworkHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'检查本机能否访问该地址，稍后重试'**
  String get balanceNetworkHint;

  /// No description provided for @thinkingDefaultLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认思考档位'**
  String get thinkingDefaultLabel;

  /// No description provided for @thinkingDefaultOff.
  ///
  /// In zh_CN, this message translates to:
  /// **'不干预'**
  String get thinkingDefaultOff;

  /// No description provided for @thinkingLevelLow.
  ///
  /// In zh_CN, this message translates to:
  /// **'精简'**
  String get thinkingLevelLow;

  /// No description provided for @thinkingLevelMedium.
  ///
  /// In zh_CN, this message translates to:
  /// **'均衡'**
  String get thinkingLevelMedium;

  /// No description provided for @thinkingLevelHigh.
  ///
  /// In zh_CN, this message translates to:
  /// **'深思'**
  String get thinkingLevelHigh;

  /// No description provided for @thinkingWireLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'档位下发格式'**
  String get thinkingWireLabel;

  /// No description provided for @thinkingWireBudget.
  ///
  /// In zh_CN, this message translates to:
  /// **'只压输出预算'**
  String get thinkingWireBudget;

  /// No description provided for @thinkingWireEffort.
  ///
  /// In zh_CN, this message translates to:
  /// **'reasoning_effort'**
  String get thinkingWireEffort;

  /// No description provided for @thinkingWireThinking.
  ///
  /// In zh_CN, this message translates to:
  /// **'thinking 开关'**
  String get thinkingWireThinking;

  /// No description provided for @thinkingWireBoth.
  ///
  /// In zh_CN, this message translates to:
  /// **'两者都发'**
  String get thinkingWireBoth;

  /// 请求日志筛选：全部
  ///
  /// In zh_CN, this message translates to:
  /// **'全部'**
  String get logsFilterAll;

  /// 请求日志筛选：只显示成功的请求
  ///
  /// In zh_CN, this message translates to:
  /// **'通过'**
  String get logsFilterPassed;

  /// 请求日志筛选：只显示失败的请求
  ///
  /// In zh_CN, this message translates to:
  /// **'失败'**
  String get logsFilterFailed;

  /// 请求日志页：筛选后一条都没有
  ///
  /// In zh_CN, this message translates to:
  /// **'当前筛选下没有请求'**
  String get logsEmptyFiltered;

  /// 活跃连接页标题
  ///
  /// In zh_CN, this message translates to:
  /// **'活跃连接'**
  String get activeConnectionsTitle;

  /// 活跃连接页空态
  ///
  /// In zh_CN, this message translates to:
  /// **'当前没有活跃连接'**
  String get activeConnectionsEmpty;

  /// 活跃连接页：连接已持续的时间
  ///
  /// In zh_CN, this message translates to:
  /// **'已持续'**
  String get activeConnDuration;

  /// 活跃连接页：连接建立时刻
  ///
  /// In zh_CN, this message translates to:
  /// **'开始于'**
  String get activeConnStarted;

  /// 活跃连接页：请求路径
  ///
  /// In zh_CN, this message translates to:
  /// **'路径'**
  String get activeConnPath;

  /// 网络页：已安装时卡片的标题（点击打开客户端）
  ///
  /// In zh_CN, this message translates to:
  /// **'打开 Tailscale'**
  String get tsOpenApp;

  /// 网络页：已安装时卡片的副标题
  ///
  /// In zh_CN, this message translates to:
  /// **'已安装 Tailscale，点一下打开客户端'**
  String get tsInstalledDesc;

  /// 网络页：打开客户端失败的提示
  ///
  /// In zh_CN, this message translates to:
  /// **'没能打开 Tailscale，已改为打开下载页'**
  String get tsOpenFailed;

  /// 用量日历：非当前月时右下角按钮的提示
  ///
  /// In zh_CN, this message translates to:
  /// **'返回今天'**
  String get usageCalendarBackToday;

  /// 上游默认思考档位：显式关闭（reasoning_effort: none）
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭思考'**
  String get thinkingLevelNone;

  /// 上游默认思考档位：minimal
  ///
  /// In zh_CN, this message translates to:
  /// **'极轻'**
  String get thinkingLevelMinimal;

  /// 上游默认思考档位：xhigh
  ///
  /// In zh_CN, this message translates to:
  /// **'极深'**
  String get thinkingLevelXhigh;

  /// 上游默认思考档位：max
  ///
  /// In zh_CN, this message translates to:
  /// **'最重'**
  String get thinkingLevelMax;

  /// Windows：显示设置页里「桌面窗口」分区标题
  ///
  /// In zh_CN, this message translates to:
  /// **'桌面窗口'**
  String get winCloseSection;

  ///  Windows：点标题栏关闭按钮时的默认动作
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭按钮行为'**
  String get winCloseBehaviorTitle;

  /// 关闭按钮行为：每次弹确认框
  ///
  /// In zh_CN, this message translates to:
  /// **'每次询问'**
  String get winCloseAsk;

  /// 关闭按钮行为：窗口最小化到托盘
  ///
  /// In zh_CN, this message translates to:
  /// **'收进托盘'**
  String get winCloseTray;

  /// 关闭按钮行为：直接退出
  ///
  /// In zh_CN, this message translates to:
  /// **'退出程序'**
  String get winCloseExit;

  /// 关闭按钮行为=每次询问 的说明
  ///
  /// In zh_CN, this message translates to:
  /// **'每次都问一句（可以勾选「下次也是这样」）'**
  String get winCloseAskSummary;

  /// 关闭按钮行为=收进托盘 的说明
  ///
  /// In zh_CN, this message translates to:
  /// **'窗口收进托盘，转发服务继续跑'**
  String get winCloseTraySummary;

  /// 关闭按钮行为=退出程序 的说明
  ///
  /// In zh_CN, this message translates to:
  /// **'程序整体退出，服务随之停止'**
  String get winCloseExitSummary;

  /// 关闭确认任务对话框的标题栏
  ///
  /// In zh_CN, this message translates to:
  /// **'Local2API'**
  String get winCloseDialogTitle;

  /// 关闭确认任务对话框的主指令
  ///
  /// In zh_CN, this message translates to:
  /// **'您点击了关闭按钮，您希望？'**
  String get winCloseDialogHeading;

  /// 关闭确认任务对话框的正文
  ///
  /// In zh_CN, this message translates to:
  /// **'收进托盘后程序在后台继续转发，可以从托盘图标随时叫回来。'**
  String get winCloseDialogContent;

  /// 关闭确认对话框的第一个命令链接
  ///
  /// In zh_CN, this message translates to:
  /// **'收进托盘'**
  String get winCloseLinkTray;

  /// 关闭确认对话框：收进托盘的副标题
  ///
  /// In zh_CN, this message translates to:
  /// **'窗口藏起来，服务照常运行'**
  String get winCloseLinkTraySubtitle;

  /// 关闭确认对话框的第二个命令链接
  ///
  /// In zh_CN, this message translates to:
  /// **'退出程序'**
  String get winCloseLinkExit;

  /// 关闭确认对话框：退出程序的副标题
  ///
  /// In zh_CN, this message translates to:
  /// **'连转发服务一起停掉'**
  String get winCloseLinkExitSubtitle;

  /// 关闭确认对话框底部的复选框文案
  ///
  /// In zh_CN, this message translates to:
  /// **'下次也是这样'**
  String get winCloseRemember;

  /// 托盘菜单：显示主窗口
  ///
  /// In zh_CN, this message translates to:
  /// **'显示主窗口'**
  String get winTrayShow;

  /// 托盘菜单：退出程序
  ///
  /// In zh_CN, this message translates to:
  /// **'退出 Local2API'**
  String get winTrayQuit;

  /// 档位下发格式行的说明
  ///
  /// In zh_CN, this message translates to:
  /// **'上游不认这一档时会自动逐级下调（max → xhigh → … → 不下发）'**
  String get thinkingWireHint;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'Anthropic Messages'**
  String get typeAnthropic;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'嘿嘿，我在这里哦'**
  String get trayHintBody;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'不再提示'**
  String get trayHintDismiss;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'设置'**
  String get trayHintSettings;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'收进托盘时显示提示'**
  String get winTrayHintTitle;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'弹一条系统通知：「嘿嘿，我在这里哦」，带「不再提示 / 设置」两个按钮'**
  String get winTrayHintSummary;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'实验室'**
  String get settingsLabTitle;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'把 SillyTavern 装到本地、内置浏览器等实验功能'**
  String get settingsLabDesc;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'实验室'**
  String get labTitle;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'本地服务与实验性功能'**
  String get labSubtitle;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'本地服务'**
  String get labLocalServices;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'本地 AI 角色扮演前端（Node.js），装好后在应用内打开'**
  String get labSillyTavernDesc;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'安装'**
  String get labInstall;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'已安装'**
  String get labInstalled;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'未安装'**
  String get labNotInstalled;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'运行中'**
  String get labRunning;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'启动'**
  String get labStart;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'停止'**
  String get labStop;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'打开'**
  String get labOpen;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'打开目录'**
  String get labOpenFolder;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'卸载'**
  String get labUninstall;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'卸载 SillyTavern？'**
  String get labUninstallTitle;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'会删除已下载的程序文件（含 data 目录里的角色卡与聊天记录），且不可恢复。'**
  String get labUninstallBody;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'安装位置'**
  String get labInstallLocation;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'选择位置'**
  String get labChooseLocation;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'默认位置'**
  String get labDefaultLocation;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'Node.js'**
  String get labNodeStatus;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'未检测到 Node.js'**
  String get labNodeMissing;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'装好 Node.js 18+ 后点「重新检测」即可启动；文件可以先装着。'**
  String get labNodeMissingHint;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'下载 Node.js'**
  String get labNodeDownload;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'重新检测'**
  String get labRecheck;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'安装依赖'**
  String get labInstallDeps;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'移动端不能直接运行 Node.js 服务；文件已装到应用目录，可用 Termux 等环境运行。'**
  String get labMobileNoRun;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'Node.js 运行时'**
  String get labNodeRuntimeTitle;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'从 Termux 软件源安装 Android 版 Node.js（含 npm），实验室的本地服务在本机运行必备。'**
  String get labNodeRuntimeDesc;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'安装 Node.js'**
  String get labNodeRuntimeInstall;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'重新安装'**
  String get labNodeRuntimeReinstall;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'卸载 Node.js'**
  String get labNodeRuntimeRemove;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'未安装'**
  String get labNodeRuntimeNotInstalled;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'运行模式'**
  String get labNodeRunnerMode;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'直接运行'**
  String get labRunnerDirect;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'以应用身份启动进程（debug 构建可用；release 会被系统拦截）'**
  String get labRunnerDirectDesc;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'Shizuku'**
  String get labRunnerShizuku;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'经 Shizuku 以 shell 身份启动进程（release 推荐，需安装并授权 Shizuku）'**
  String get labRunnerShizukuDesc;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'下载镜像'**
  String get labNodeMirror;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'官方源'**
  String get labMirrorOfficial;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'packages.termux.dev · registry.npmjs.org（境内直连很慢，适合已有代理的网络）'**
  String get labMirrorOfficialDesc;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'中国大陆镜像'**
  String get labMirrorCn;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'清华 TUNA termux 源 · npmmirror（境内直连快，实测数 MB/s）'**
  String get labMirrorCnDesc;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'Shizuku 状态'**
  String get labShizukuStatus;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'未检测到 Shizuku（未安装或未启动）'**
  String get labShizukuNotDetected;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'已授权'**
  String get labShizukuGranted;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'未授权'**
  String get labShizukuNotGranted;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'授权 Shizuku'**
  String get labShizukuRequest;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'系统禁止应用直接执行 Node，请切换到 Shizuku 模式'**
  String get labExecBlocked;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'手动开启后，这里才会显示实验室入口'**
  String get labVisibleDesc;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'进入实验室'**
  String get labOpenLab;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'下载中'**
  String get labDownloading;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'解压中'**
  String get labExtracting;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'安装依赖中'**
  String get labInstallingDeps;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'启动中'**
  String get labStarting;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'日志'**
  String get labLogs;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'清空'**
  String get labClearLogs;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'版本'**
  String get labVersion;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'就绪'**
  String get labPhaseIdle;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'内置工具'**
  String get labBrowserTools;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'内置浏览器'**
  String get labBrowserTitle;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'在应用内打开本地 WebUI、SillyTavern 或任意网址'**
  String get labBrowserDesc;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'打开浏览器'**
  String get labOpenBrowser;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'输入网址，例如 127.0.0.1:8000'**
  String get labManualUrl;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'前往'**
  String get labGo;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'出错了'**
  String get labError;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'取消'**
  String get labCancel;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'浏览器'**
  String get browserTitle;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'编辑地址'**
  String get browserEditUrl;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'https://example.com'**
  String get browserUrlHint;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'前往'**
  String get browserGo;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'后退'**
  String get browserBack;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'前进'**
  String get browserForward;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'刷新'**
  String get browserReload;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'停止'**
  String get browserStop;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'更多'**
  String get browserMenu;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'复制链接'**
  String get browserCopyLink;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'复制 Cookie'**
  String get browserCopyCookie;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'当前页面没有可复制的 Cookie'**
  String get browserCookieEmpty;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'Cookie 已复制'**
  String get browserCookieCopied;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'浏览器标识'**
  String get browserUaLabel;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'自动'**
  String get browserUaAuto;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'电脑端'**
  String get browserUaDesktop;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'手机端'**
  String get browserUaMobile;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'在系统浏览器打开'**
  String get browserOpenExternal;

  /// No description provided for @browserInitFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'网页加载失败：{error}'**
  String browserInitFailed(String error);

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'当前平台不支持内置浏览器，请用系统浏览器打开'**
  String get browserUnsupported;

  /// 实验室 / 内置浏览器 / 托盘提示相关
  ///
  /// In zh_CN, this message translates to:
  /// **'重试'**
  String get browserRetry;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'返回'**
  String get commonBack;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭'**
  String get close;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'更多设置'**
  String get labMoreSettings;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'还没有安装 SillyTavern'**
  String get labInstallFirstTitle;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'先在「更多设置」里装好，再回来打开这个开关。'**
  String get labInstallFirstBody;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'去设置'**
  String get labGoSettings;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'启动失败'**
  String get labStartFailed;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'已停止'**
  String get labStopped;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'运行状态'**
  String get labSectionStatus;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'安装'**
  String get labSectionInstall;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'API 配置'**
  String get labApiConfig;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'模型组'**
  String get labApiGroup;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'未选择'**
  String get labApiGroupNone;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'模型'**
  String get labApiModel;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'接口地址'**
  String get labApiBaseUrl;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'API Key'**
  String get labApiKey;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'还没有启用的 API Key（先去「密钥」页建一个）'**
  String get labApiNoKey;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'写入 SillyTavern'**
  String get labApiWrite;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'已写入，刷新 SillyTavern 页面即生效'**
  String get labApiWriteOk;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'写入失败：{error}'**
  String labApiWriteFailed(String error);

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'先在「发现」页启用一个模型组'**
  String get labApiNeedGroup;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'没连上本机服务，先在仪表盘启动服务'**
  String get labApiNeedService;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'SillyTavern 还没启动过，先启动一次再写入'**
  String get labApiNoUserData;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'选择模型组'**
  String get labApiPickGroup;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'选择模型'**
  String get labApiPickModel;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'{count} 个模型'**
  String labApiModelCount(String count);

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'还没有日志'**
  String get labLogsEmpty;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'复制日志'**
  String get labCopyLogs;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'日志已复制'**
  String get labLogsCopied;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭页面'**
  String get browserClosePage;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'分享二维码'**
  String get browserShareQr;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'扫码在手机上打开'**
  String get browserQrTitle;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'查看 Cookie'**
  String get browserViewCookies;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'全部复制'**
  String get browserCopyAll;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'允许网页写剪贴板'**
  String get browserClipboardAccess;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'已允许剪贴板访问'**
  String get browserClipboardAllowed;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'已阻止剪贴板访问'**
  String get browserClipboardBlocked;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义浏览器标识'**
  String get browserSetUa;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'留空恢复默认；改完会刷新页面'**
  String get browserUaEmptyHint;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'应用并刷新'**
  String get browserApplyAndReload;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'浏览器标识已更新'**
  String get browserUaUpdated;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'网络疑难解答'**
  String get browserTroubleshootNetwork;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'打不开系统疑难解答'**
  String get browserTroubleshootFailed;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'系统 WebView 挂了'**
  String get browserAndroidErrorTitle;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'可能原因'**
  String get browserAndroidErrorCause;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'系统 WebView 版本过旧或被禁用，内置浏览器起不来。'**
  String get browserAndroidErrorDetail;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'更新 Android System WebView'**
  String get browserUpdateWebview;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'查看 WebView 实现（开发者选项）'**
  String get browserOpenDevOptions;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'内置浏览器无法启动'**
  String get browserAppleErrorTitle;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'错误报告'**
  String get browserAppleErrorReport;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'WKWebView 初始化失败，通常是系统版本过低或受企业策略限制。'**
  String get browserAppleErrorDetail;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'你的内置浏览器遇到了问题，需要重新启动。'**
  String get browserBsodMessage;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'我们只收集某些错误信息，然后为你重新启动。'**
  String get browserBsodNoRestart;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'0% 完成'**
  String get browserBsodComplete;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'可以试试这些：'**
  String get browserBsodSolutions;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'下载 Microsoft Edge WebView2 Runtime'**
  String get browserBsodDownload;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'打开 Windows 更新'**
  String get browserBsodWinUpdate;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'手机扫码打开 WebView2 下载页'**
  String get browserBsodScanQr;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'停止代码：WEBVIEW2_NOT_INSTALLED'**
  String get browserBsodStopCode;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'状态'**
  String get labStatus;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'粘贴或输入完整的 UA 字符串'**
  String get browserUaHint;

  /// 实验室 / 内置浏览器（浏览器能力与 SillyTavern API 配置）
  ///
  /// In zh_CN, this message translates to:
  /// **'先停止 SillyTavern 再写入（运行中的配置会被它自己覆盖）'**
  String get labApiStopFirst;

  /// No description provided for @labAutoOpenBrowser.
  ///
  /// In zh_CN, this message translates to:
  /// **'启动后自动打开浏览器'**
  String get labAutoOpenBrowser;

  /// No description provided for @labAutoOpenBrowserDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'关掉后 SillyTavern 不再自己拉起系统浏览器；用「打开」手动进入'**
  String get labAutoOpenBrowserDesc;

  /// No description provided for @labDshTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'DeepSeek Harness'**
  String get labDshTitle;

  /// No description provided for @labDshInstallFirstTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'还没有安装 DeepSeek Harness'**
  String get labDshInstallFirstTitle;

  /// No description provided for @labDshInstallFirstBody.
  ///
  /// In zh_CN, this message translates to:
  /// **'先在「更多设置」里装好，再回来打开这个开关。'**
  String get labDshInstallFirstBody;

  /// No description provided for @labDshUninstallTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'卸载 DeepSeek Harness？'**
  String get labDshUninstallTitle;

  /// No description provided for @labDshUninstallBody.
  ///
  /// In zh_CN, this message translates to:
  /// **'会删除 npm 安装的 dsh 程序文件，模型配置与聊天记录保留在 ~/.dsh。'**
  String get labDshUninstallBody;

  /// No description provided for @labDshPickModels.
  ///
  /// In zh_CN, this message translates to:
  /// **'选择要加入 dsh 的模型'**
  String get labDshPickModels;

  /// No description provided for @labDshDefaultModel.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认模型'**
  String get labDshDefaultModel;

  /// No description provided for @labDshPickDefault.
  ///
  /// In zh_CN, this message translates to:
  /// **'选择默认模型'**
  String get labDshPickDefault;

  /// No description provided for @labDshWrite.
  ///
  /// In zh_CN, this message translates to:
  /// **'写入 dsh 配置'**
  String get labDshWrite;

  /// No description provided for @labDshWriteOk.
  ///
  /// In zh_CN, this message translates to:
  /// **'已写入 dsh 配置'**
  String get labDshWriteOk;

  /// No description provided for @labDshNeedModels.
  ///
  /// In zh_CN, this message translates to:
  /// **'先选模型组并勾选至少一个模型'**
  String get labDshNeedModels;

  /// No description provided for @labDshWriteHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'写入后 dsh 的模型列表会热加载；正在运行时应用会自动重启它，让新密钥生效'**
  String get labDshWriteHint;

  /// No description provided for @labDshConfigPath.
  ///
  /// In zh_CN, this message translates to:
  /// **'配置文件'**
  String get labDshConfigPath;

  /// No description provided for @labDshOpenInApp.
  ///
  /// In zh_CN, this message translates to:
  /// **'应用内打开'**
  String get labDshOpenInApp;

  /// No description provided for @labDshCompat.
  ///
  /// In zh_CN, this message translates to:
  /// **'Android 兼容层'**
  String get labDshCompat;

  /// No description provided for @labDshCompatDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'关掉安卓上起不来的沙箱与 pwsh'**
  String get labDshCompatDesc;

  /// 内置浏览器：网页 <select> 弹出的底部选择器标题（猜不到字段名时）
  ///
  /// In zh_CN, this message translates to:
  /// **'选择'**
  String get browserSelectTitle;

  /// No description provided for @browserOpenCustomTab.
  ///
  /// In zh_CN, this message translates to:
  /// **'用 Custom Tabs 打开'**
  String get browserOpenCustomTab;

  /// No description provided for @browserCustomTabPick.
  ///
  /// In zh_CN, this message translates to:
  /// **'用哪个浏览器打开'**
  String get browserCustomTabPick;

  /// No description provided for @browserCustomTabAuto.
  ///
  /// In zh_CN, this message translates to:
  /// **'自动（系统默认）'**
  String get browserCustomTabAuto;

  /// No description provided for @browserCustomTabNone.
  ///
  /// In zh_CN, this message translates to:
  /// **'没装支持 Custom Tabs 的浏览器'**
  String get browserCustomTabNone;

  /// No description provided for @browserCustomTabFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'打不开这个链接'**
  String get browserCustomTabFailed;

  /// 实验室：Android 通知（进度为中心的实时更新 / 带回复）与 dsh 任务模式
  ///
  /// In zh_CN, this message translates to:
  /// **'回复'**
  String get reply;

  /// 实验室：Android 通知（进度为中心的实时更新 / 带回复）与 dsh 任务模式
  ///
  /// In zh_CN, this message translates to:
  /// **'通知'**
  String get labNotifySection;

  /// 实验室：Android 通知（进度为中心的实时更新 / 带回复）与 dsh 任务模式
  ///
  /// In zh_CN, this message translates to:
  /// **'通知权限'**
  String get labNotifyPermission;

  /// 实验室：Android 通知（进度为中心的实时更新 / 带回复）与 dsh 任务模式
  ///
  /// In zh_CN, this message translates to:
  /// **'任务进度、提问与结果都走通知'**
  String get labNotifyPermissionDesc;

  /// 实验室：Android 通知（进度为中心的实时更新 / 带回复）与 dsh 任务模式
  ///
  /// In zh_CN, this message translates to:
  /// **'实时更新'**
  String get labNotifyLiveUpdate;

  /// 实验室：Android 通知（进度为中心的实时更新 / 带回复）与 dsh 任务模式
  ///
  /// In zh_CN, this message translates to:
  /// **'Android 16+ 把任务进度置顶在通知栏、锁屏与状态栏'**
  String get labNotifyLiveUpdateDesc;

  /// 实验室：Android 通知（进度为中心的实时更新 / 带回复）与 dsh 任务模式
  ///
  /// In zh_CN, this message translates to:
  /// **'系统已放行实时更新'**
  String get labNotifyPromoted;

  /// 实验室：Android 通知（进度为中心的实时更新 / 带回复）与 dsh 任务模式
  ///
  /// In zh_CN, this message translates to:
  /// **'当前不会升级为实时更新'**
  String get labNotifyNotPromoted;

  /// 实验室：Android 通知（进度为中心的实时更新 / 带回复）与 dsh 任务模式
  ///
  /// In zh_CN, this message translates to:
  /// **'忽略电池优化'**
  String get labNotifyBattery;

  /// 实验室：Android 通知（进度为中心的实时更新 / 带回复）与 dsh 任务模式
  ///
  /// In zh_CN, this message translates to:
  /// **'让 node / dsh 能在后台长时间跑'**
  String get labNotifyBatteryDesc;

  /// 实验室：Android 通知（进度为中心的实时更新 / 带回复）与 dsh 任务模式
  ///
  /// In zh_CN, this message translates to:
  /// **'已忽略电池优化'**
  String get labNotifyBatteryIgnored;

  /// 实验室：Android 通知（进度为中心的实时更新 / 带回复）与 dsh 任务模式
  ///
  /// In zh_CN, this message translates to:
  /// **'系统通知设置'**
  String get labNotifyOpenSettings;

  /// 实验室：Android 通知（进度为中心的实时更新 / 带回复）与 dsh 任务模式
  ///
  /// In zh_CN, this message translates to:
  /// **'发一条测试通知'**
  String get labNotifyTest;

  /// 实验室：Android 通知（进度为中心的实时更新 / 带回复）与 dsh 任务模式
  ///
  /// In zh_CN, this message translates to:
  /// **'测试通知已发出'**
  String get labNotifyTestSent;

  /// 实验室：Android 通知（进度为中心的实时更新 / 带回复）与 dsh 任务模式
  ///
  /// In zh_CN, this message translates to:
  /// **'通知没发出去（检查权限）'**
  String get labNotifyTestFailed;

  /// 实验室：Android 通知（进度为中心的实时更新 / 带回复）与 dsh 任务模式
  ///
  /// In zh_CN, this message translates to:
  /// **'任务提示词'**
  String get labDshTaskHint;

  /// 实验室：Android 通知（进度为中心的实时更新 / 带回复）与 dsh 任务模式
  ///
  /// In zh_CN, this message translates to:
  /// **'让模型按步骤汇报进度、需要拍板时停下来问你'**
  String get labDshTaskHintDesc;

  /// dsh 设置页：社区插件开关
  ///
  /// In zh_CN, this message translates to:
  /// **'插件'**
  String get labDshPlugins;

  /// dsh 插件：用户消息原位编辑与分叉重发
  ///
  /// In zh_CN, this message translates to:
  /// **'编辑消息'**
  String get labDshPluginMessageEdit;

  /// dsh 插件：用户消息原位编辑与分叉重发
  ///
  /// In zh_CN, this message translates to:
  /// **'在用户消息旁加铅笔按钮，改完可从上一轮分叉重发（dsh-message-edit）'**
  String get labDshPluginMessageEditDesc;

  /// dsh 插件：截屏与鼠标键盘控制（仅 Windows）
  ///
  /// In zh_CN, this message translates to:
  /// **'电脑操作模式'**
  String get labDshPluginComputerUse;

  /// dsh 插件：截屏与鼠标键盘控制（仅 Windows）
  ///
  /// In zh_CN, this message translates to:
  /// **'截屏 + 鼠标键盘控制，新任务可选「电脑操作模式」（dsh-computer-use-mode）'**
  String get labDshPluginComputerUseDesc;

  /// dsh 插件：20 个 adb 工具，让模型直接操作这台手机
  ///
  /// In zh_CN, this message translates to:
  /// **'手机操作'**
  String get labDshPluginAndroid;

  /// dsh 插件：手机操作的说明文案
  ///
  /// In zh_CN, this message translates to:
  /// **'手机操作：截屏、点按、滑动、UI 树、OCR、logcat（@zseven-w/dsh-android）'**
  String get labDshPluginAndroidDesc;

  /// dsh 插件：安装中的状态文案
  ///
  /// In zh_CN, this message translates to:
  /// **'正在安装…'**
  String get labDshPluginInstalling;

  /// dsh 插件：失败提示
  ///
  /// In zh_CN, this message translates to:
  /// **'插件操作失败'**
  String get labDshPluginFailed;

  /// dsh 插件：重启提示
  ///
  /// In zh_CN, this message translates to:
  /// **'开关后会自动重启 DSH 让插件生效'**
  String get labDshPluginRestartHint;

  /// 实验室：Android 通知（进度为中心的实时更新 / 带回复）与 dsh 任务模式
  ///
  /// In zh_CN, this message translates to:
  /// **'运行任务'**
  String get labDshRunTask;

  /// 实验室：Android 通知（进度为中心的实时更新 / 带回复）与 dsh 任务模式
  ///
  /// In zh_CN, this message translates to:
  /// **'把一句话交给 dsh 跑，进度与结果走通知'**
  String get labDshRunTaskDesc;

  /// 实验室：Android 通知（进度为中心的实时更新 / 带回复）与 dsh 任务模式
  ///
  /// In zh_CN, this message translates to:
  /// **'要 dsh 做什么？'**
  String get labDshTaskPrompt;

  /// 实验室：Android 通知（进度为中心的实时更新 / 带回复）与 dsh 任务模式
  ///
  /// In zh_CN, this message translates to:
  /// **'已经有一个任务在跑'**
  String get labDshTaskBusy;

  /// 实验室：Android 通知（进度为中心的实时更新 / 带回复）与 dsh 任务模式
  ///
  /// In zh_CN, this message translates to:
  /// **'任务已开始，进度看通知'**
  String get labDshTaskStarted;

  /// 实验室：Android 通知（进度为中心的实时更新 / 带回复）与 dsh 任务模式
  ///
  /// In zh_CN, this message translates to:
  /// **'任务完成'**
  String get labDshTaskDone;

  /// 实验室：Android 通知（进度为中心的实时更新 / 带回复）与 dsh 任务模式
  ///
  /// In zh_CN, this message translates to:
  /// **'任务失败'**
  String get labDshTaskFailed;

  /// 实验室：Android 通知（进度为中心的实时更新 / 带回复）与 dsh 任务模式
  ///
  /// In zh_CN, this message translates to:
  /// **'任务已取消'**
  String get labDshTaskCancelled;

  /// 实验室：Android 通知（进度为中心的实时更新 / 带回复）与 dsh 任务模式
  ///
  /// In zh_CN, this message translates to:
  /// **'{done}/{total} 步'**
  String labDshTaskSteps(String done, String total);

  /// No description provided for @labDshAgentDone.
  ///
  /// In zh_CN, this message translates to:
  /// **'agent 已完成此轮操作'**
  String get labDshAgentDone;

  /// No description provided for @labDshNeedAnswer.
  ///
  /// In zh_CN, this message translates to:
  /// **'dsh 在等你回答'**
  String get labDshNeedAnswer;

  /// No description provided for @labDshAnswerHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'打开 dsh web 回答'**
  String get labDshAnswerHint;

  /// Windows 系统通知：输入框占位
  ///
  /// In zh_CN, this message translates to:
  /// **'输入回答'**
  String get labDshToastReplyHint;

  /// Windows 系统通知：选项提示
  ///
  /// In zh_CN, this message translates to:
  /// **'输入 1-3 选择，其他内容作为自定义回答'**
  String get labDshToastOptionsHint;

  /// Windows 系统通知：跳过按钮
  ///
  /// In zh_CN, this message translates to:
  /// **'跳过'**
  String get labDshToastSkip;

  /// 编辑上游页：自动更新模型列表那一行
  ///
  /// In zh_CN, this message translates to:
  /// **'自动更新模型'**
  String get autoRefreshTitle;

  /// No description provided for @autoRefreshOff.
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭'**
  String get autoRefreshOff;

  /// No description provided for @autoRefreshEvery1d.
  ///
  /// In zh_CN, this message translates to:
  /// **'每天'**
  String get autoRefreshEvery1d;

  /// No description provided for @autoRefreshEvery3d.
  ///
  /// In zh_CN, this message translates to:
  /// **'每 3 天'**
  String get autoRefreshEvery3d;

  /// No description provided for @autoRefreshEvery7d.
  ///
  /// In zh_CN, this message translates to:
  /// **'每 7 天'**
  String get autoRefreshEvery7d;

  /// No description provided for @autoRefreshEvery30d.
  ///
  /// In zh_CN, this message translates to:
  /// **'每 30 天'**
  String get autoRefreshEvery30d;

  /// 编辑上游页：自动更新行的说明
  ///
  /// In zh_CN, this message translates to:
  /// **'按设定的间隔去上游拉一次模型清单，新上的补进来、下架的删掉'**
  String get autoRefreshDesc;

  /// No description provided for @autoRefreshNever.
  ///
  /// In zh_CN, this message translates to:
  /// **'还没刷新过'**
  String get autoRefreshNever;

  /// No description provided for @autoRefreshJustNow.
  ///
  /// In zh_CN, this message translates to:
  /// **'刚刚刷新过'**
  String get autoRefreshJustNow;

  /// 自动更新：距下次还有多久
  ///
  /// In zh_CN, this message translates to:
  /// **'下次 {when}'**
  String autoRefreshNextIn(String when);

  /// No description provided for @autoRefreshRefreshing.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在刷新…'**
  String get autoRefreshRefreshing;

  /// 自动更新完成提示
  ///
  /// In zh_CN, this message translates to:
  /// **'模型列表已更新：新增 {added} 个，移除 {removed} 个'**
  String autoRefreshDone(String added, String removed);

  /// No description provided for @autoRefreshNoChange.
  ///
  /// In zh_CN, this message translates to:
  /// **'模型列表已是最新'**
  String get autoRefreshNoChange;

  /// No description provided for @autoRefreshRefreshNow.
  ///
  /// In zh_CN, this message translates to:
  /// **'立即刷新'**
  String get autoRefreshRefreshNow;

  /// No description provided for @autoRefreshFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'刷新失败'**
  String get autoRefreshFailed;

  /// 插件管理页标题
  ///
  /// In zh_CN, this message translates to:
  /// **'dsh 插件'**
  String get pluginManagerTitle;

  /// 重新扫描已装插件
  ///
  /// In zh_CN, this message translates to:
  /// **'重新扫描'**
  String get pluginManagerRefresh;

  /// dsh 设置页：插件管理入口说明
  ///
  /// In zh_CN, this message translates to:
  /// **'安装、开关与卸载 dsh 插件'**
  String get pluginManagerSubtitle;

  /// No description provided for @pluginManagerSearch.
  ///
  /// In zh_CN, this message translates to:
  /// **'搜索插件'**
  String get pluginManagerSearch;

  /// No description provided for @pluginManagerInstall.
  ///
  /// In zh_CN, this message translates to:
  /// **'安装'**
  String get pluginManagerInstall;

  /// No description provided for @pluginManagerInstallTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'安装第三方插件'**
  String get pluginManagerInstallTitle;

  /// No description provided for @pluginManagerPackageHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'npm 包名，如 @scope/dsh-plugin-xxx'**
  String get pluginManagerPackageHint;

  /// No description provided for @pluginManagerPackageEmpty.
  ///
  /// In zh_CN, this message translates to:
  /// **'请先填包名'**
  String get pluginManagerPackageEmpty;

  /// No description provided for @pluginManagerInstalling.
  ///
  /// In zh_CN, this message translates to:
  /// **'安装中…'**
  String get pluginManagerInstalling;

  /// No description provided for @pluginManagerUninstall.
  ///
  /// In zh_CN, this message translates to:
  /// **'卸载'**
  String get pluginManagerUninstall;

  /// 卸载插件确认框
  ///
  /// In zh_CN, this message translates to:
  /// **'卸载 {name}？这个包会从 dsh 里移除。'**
  String pluginManagerUninstallConfirm(String name);

  /// 停用插件说明
  ///
  /// In zh_CN, this message translates to:
  /// **'停用 {name}？已下载的包会保留，下次启用不用重装。'**
  String pluginManagerExitConfirm(String name);

  /// No description provided for @pluginManagerRestartHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'插件改动在 dsh 重启后生效'**
  String get pluginManagerRestartHint;

  /// No description provided for @pluginManagerDescTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'第三方插件'**
  String get pluginManagerDescTitle;

  /// No description provided for @pluginManagerEmpty.
  ///
  /// In zh_CN, this message translates to:
  /// **'还没装过插件'**
  String get pluginManagerEmpty;

  /// No description provided for @pluginManagerNotReady.
  ///
  /// In zh_CN, this message translates to:
  /// **'dsh 还没装好，先装 dsh 再来管插件'**
  String get pluginManagerNotReady;

  /// No description provided for @pluginManagerInstalledCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'{count} 个已启用'**
  String pluginManagerInstalledCount(String count);

  /// No description provided for @pluginManagerInstalledBadge.
  ///
  /// In zh_CN, this message translates to:
  /// **'已安装'**
  String get pluginManagerInstalledBadge;

  /// No description provided for @pluginManagerCustom.
  ///
  /// In zh_CN, this message translates to:
  /// **'第三方'**
  String get pluginManagerCustom;

  /// No description provided for @pluginManagerOfficial.
  ///
  /// In zh_CN, this message translates to:
  /// **'内置'**
  String get pluginManagerOfficial;

  /// No description provided for @pluginManagerLocal.
  ///
  /// In zh_CN, this message translates to:
  /// **'本地目录'**
  String get pluginManagerLocal;

  /// No description provided for @pluginManagerAddLocal.
  ///
  /// In zh_CN, this message translates to:
  /// **'从本地目录安装'**
  String get pluginManagerAddLocal;

  /// No description provided for @pluginManagerNoMatch.
  ///
  /// In zh_CN, this message translates to:
  /// **'没有匹配的插件'**
  String get pluginManagerNoMatch;

  /// No description provided for @pluginManagerSearchClear.
  ///
  /// In zh_CN, this message translates to:
  /// **'清除搜索'**
  String get pluginManagerSearchClear;

  /// No description provided for @pluginManagerExpand.
  ///
  /// In zh_CN, this message translates to:
  /// **'展开'**
  String get pluginManagerExpand;

  /// No description provided for @pluginManagerCollapse.
  ///
  /// In zh_CN, this message translates to:
  /// **'收起'**
  String get pluginManagerCollapse;

  /// 插件平台限制提示
  ///
  /// In zh_CN, this message translates to:
  /// **'仅支持 {platform}'**
  String pluginManagerOnlyOn(String platform);

  /// No description provided for @pluginManagerNotInstalled.
  ///
  /// In zh_CN, this message translates to:
  /// **'未安装'**
  String get pluginManagerNotInstalled;

  /// No description provided for @pluginManagerDisabled.
  ///
  /// In zh_CN, this message translates to:
  /// **'未启用'**
  String get pluginManagerDisabled;

  /// No description provided for @pluginManagerEnabledState.
  ///
  /// In zh_CN, this message translates to:
  /// **'已启用'**
  String get pluginManagerEnabledState;

  /// 插件页顶部统计
  ///
  /// In zh_CN, this message translates to:
  /// **'{enabled} 个已启用 · 共 {total} 个'**
  String pluginManagerOverview(String enabled, String total);

  /// No description provided for @usageApiKeyFilter.
  ///
  /// In zh_CN, this message translates to:
  /// **'API Key'**
  String get usageApiKeyFilter;

  /// No description provided for @usageAllApiKeys.
  ///
  /// In zh_CN, this message translates to:
  /// **'全部'**
  String get usageAllApiKeys;

  /// No description provided for @usageModelFilter.
  ///
  /// In zh_CN, this message translates to:
  /// **'模型'**
  String get usageModelFilter;

  /// No description provided for @usageAllModelsShort.
  ///
  /// In zh_CN, this message translates to:
  /// **'全部模型'**
  String get usageAllModelsShort;

  /// No description provided for @usageRequestsShort.
  ///
  /// In zh_CN, this message translates to:
  /// **'请求'**
  String get usageRequestsShort;

  /// No description provided for @usageByModel.
  ///
  /// In zh_CN, this message translates to:
  /// **'各模型用量'**
  String get usageByModel;

  /// No description provided for @usageModelCalls.
  ///
  /// In zh_CN, this message translates to:
  /// **'API 请求次数'**
  String get usageModelCalls;

  /// No description provided for @usageNoModelCalls.
  ///
  /// In zh_CN, this message translates to:
  /// **'这段时间没有调用记录'**
  String get usageNoModelCalls;

  /// No description provided for @usageChartByModel.
  ///
  /// In zh_CN, this message translates to:
  /// **'按模型'**
  String get usageChartByModel;

  /// No description provided for @usageChartByKey.
  ///
  /// In zh_CN, this message translates to:
  /// **'按 API Key'**
  String get usageChartByKey;

  /// No description provided for @usageKeyName.
  ///
  /// In zh_CN, this message translates to:
  /// **'密钥'**
  String get usageKeyName;

  /// No description provided for @usageKeyAnonymous.
  ///
  /// In zh_CN, this message translates to:
  /// **'未鉴权调用'**
  String get usageKeyAnonymous;

  /// No description provided for @usageTotalRow.
  ///
  /// In zh_CN, this message translates to:
  /// **'合计'**
  String get usageTotalRow;

  /// No description provided for @usageCallsUnit.
  ///
  /// In zh_CN, this message translates to:
  /// **'次'**
  String get usageCallsUnit;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'CN':
            return AppLocalizationsZhCn();
          case 'TW':
            return AppLocalizationsZhTw();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
