import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'local_asr_service.dart';

/// 实机排障用：debug 包把收音引擎的关键节点打到 logcat（tag=flutter）。
/// vivo 等 ROM 屏掉三方应用 logcat 时，还会兜底写一份到
/// `cache/stt_debug.log`（run-as 可拉取），release 完全静音。
void _sttLog(String message) {
  if (!kDebugMode) return;
  debugPrint('[stt] $message');
  unawaited(() async {
    try {
      final dir = await getTemporaryDirectory();
      final f = File(p.join(dir.path, 'stt_debug.log'));
      final stamp = DateTime.now().toIso8601String().substring(11, 23);
      await f.writeAsString('$stamp [stt] $message\n',
          mode: FileMode.append, flush: false);
    } on Object {
      // 排障日志写不进去就算了，别影响主流程。
    }
  }());
}

/// 语音输入（转文字）。
///
/// 包一层 [SpeechToText]：懒建引擎（第一次用才碰插件）、把增量结果归一成
/// 「(文本, 是否定稿)」两个参数、错误统一走回调。
///
/// 之前踩过的坑，这版都修了：
/// 1. **失败被缓存**：`initialize()` 返回 false 后 `_initialized` 仍是 true，
///    于是第二次点麦克风直接返回「不可用」，看着就是「点了没反应」。
///    现在失败不缓存，每次点都真的重试一遍。
/// 2. **原因不分**：没权限、设备没识别服务、识别中途报错，全挤在
///    「当前设备不支持语音输入」这一句里。现在 [SpeechReady] 分开返回，
///    页面据此给不同提示（缺权限时还能一键去系统设置）。
/// 3. **收音卡死**：识别引擎报错时 [onResult] 永远不会再来，页面上的
///    麦克风图标就停在「正在收音」的红色状态。现在错误走 [start] 的
///    `onError`，页面能立刻把状态收回去。
/// 4. **pauseFor 一刀切**：安卓谷歌引擎是流式的（边说边出增量），短静音
///    判定（3s）体验最好；Windows 的 SAPI 没有增量事件，一次断句才出一版
///    final（实测首版要 8~10s），3s 的 pauseFor 计时器会在引擎出结果**之前**
///    就把整个会话掐死 —— 表现为「语音转文字一直转不了」。现在 start 用
///    长 pauseFor 起步，收到第一个增量时再收紧回短值：流式引擎两不误，
///    非流式引擎靠自己的断句出 final。
/// 5. **`error_client` 重开**：安卓上第一次收音（尤其是「刚拿到麦克风权限」
///    之后、或上一轮刚 cancel 完）识别服务往往还没绑定好，`startListening`
///    会立刻回 `error_client` —— 系统原文是「Client side error」，属于转瞬
///    即逝的客户端侧握手失败，等一拍再开一次就好。以前这条错误会直接弹给
///    用户（界面上就是「语音输入失败：error_client」），现在静默重开一次
///    （一轮只重开一次，第二次还错才如实上报），见 [_retryOnClientError]。
/// 6. **系统识别服务整个是坏的**：国产 ROM 上默认服务可能「注册了但对三方
///    应用一律报错」（vivo Copilot 秒回 error_client；无 Play 认证的机器上
///    Google 服务报 error_too_many_requests）。这种错重开多少次都没用，
///    检测到后本会话内永久切到 [LocalAsrService]（离线模型）兜底：模型已
///    下载就直接顶上，没下载就先下载、下完自动接管当前这轮收音。
class SpeechInputService {
  /// 流式引擎（有增量事件）收紧后的静音判定。
  static const Duration _streamingPauseFor = Duration(seconds: 3);

  /// **进程级单例**：底下的 `SpeechToText` 本身就是单例（工厂直接返回
  /// 全局实例），error/status 监听只在第一次 initialize 时注册一次。
  /// 如果每个页面各 new 一个本服务，第二个页面的 initialize 会被短路，
  /// 它的 onError / onStatus 永远收不到事件（错误不弹、通话页的
  /// notListening 自愈失灵）。所以这里也收敛成单例，sink 每次 start
  /// 重新挂，谁在收音谁收事件。
  SpeechInputService._();

  static final SpeechInputService instance = SpeechInputService._();

  factory SpeechInputService() => instance;

  /// `error_client` 重开前的等待（见 [_retryOnClientError]）：让识别服务的
  /// 绑定先落定，再 startListening 就稳了。
  static const Duration _clientRetryDelay = Duration(milliseconds: 320);

  SpeechToText? _stt;
  bool _initialized = false;
  bool _initializing = false;
  bool _available = false;
  String? _lastError;

  /// 本会话内系统识别服务被判死刑后走本地引擎（见类注释第 6 条）。
  /// 会话内存：下个会话还会先试一次系统引擎（万一用户装好了 GMS）。
  bool _useLocal = false;

  /// 这轮收音里「切本地」是否已经试过（每次 [start] 重置）。
  bool _localTried = false;

  final LocalAsrService _local = LocalAsrService.instance;

  /// 本次收音的错误出口（[start] 装的，引擎的错误都从这里转出去）。
  void Function(String message)? _errorSink;

  /// 本次收音的结果出口（[start] 装的；切本地引擎后靠它转发）。
  void Function(String text, bool isFinal)? _onResultSink;

  /// 本次收音的状态出口（[start] 装的）：listening / notListening / done…
  void Function(String status)? _statusSink;

  /// 本次收音的重开入口（[start] 装的）—— 见 [_retryOnClientError]。
  Future<void> Function()? _restart;

  /// 这轮收音还在跑（true = 引擎该在收音、或正在重开）。stop / cancel 置
  /// false：留着的那次 `error_client` 重开定时器不该在收音收尾后又把麦克风
  /// 打开一遍。
  bool _listenActive = false;

  /// 这轮收音有没有把「`error_client` 重开」用掉（每次 [start] 重置）。
  bool _clientRetried = false;

  /// `error_client` 重开窗口内：引擎紧接着还会报一次 notListening，那是这次
  /// 握手失败的收尾，不是真的「收音结束」。压住别转给页面 —— 否则通话页的
  /// 自愈循环会抢在我们重开之前又 listen 一次，两边打架。
  bool _retryingClient = false;

  /// 引擎 localeId 的解析缓存，键 = 应用 locale 的 `lang_COUNTRY`。
  ///
  /// 通话页每轮收音都要挑一次识别语言，而底层 `locales()` 在 Android 13+
  /// 会**另起一个 on-device 识别器**跑 checkRecognitionSupport 再把它销毁
  /// （真机日志里就是那句「Connection to speech recognition service lost」）。
  /// 一轮一段地把识别器建了又拆，等于给 `startListening` 多添了几次竞态
  /// 机会，所以同一门语言只问一次就好。
  final Map<String, String?> _localeCache = {};

  /// 最近一次错误（初始化失败或识别报错）。
  String? get lastError => _lastError;

  SpeechToText get _engine => _stt ??= SpeechToText();

  /// 是否正在收音。
  bool get isListening =>
      _useLocal ? _local.isListening : (_stt?.isListening ?? false);

  /// 能不能用（[ensureReady] 成功后才有意义）。
  bool get isAvailable => _useLocal || (_initialized && _available);

  /// 准备好收音：申请权限 + 初始化引擎。
  ///
  /// 幂等只在「已经成功」时成立 —— 失败一律下次重试（见类注释第 1 条）。
  Future<SpeechReady> ensureReady() async {
    if (_useLocal) return _ensureLocalReady();
    if (_initialized && _available) return SpeechReady.available;
    if (_initializing) return SpeechReady.busy;
    _initializing = true;
    _sttLog('ensureReady: begin');
    try {
      final granted = await _ensurePermission();
      _sttLog('ensureReady: permission granted=$granted');
      if (!granted) {
        _available = false;
        // 权限没给：不缓存 _initialized，用户去系统设置里开了回来还能点。
        return SpeechReady.noPermission;
      }
      _available = await _engine
          .initialize(
            debugLogging: kDebugMode,
            // 识别过程的错误也是从这里回来的（listen 没有独立的 onError），
            // 转发给当前那次收音的回调，页面据此收回麦克风状态。
            // 例外：`error_client` 先走 [_retryOnClientError] 静默重开一次。
            onError: (e) {
              _lastError = e.errorMsg;
              _sttLog('engine onError: ${e.errorMsg}');
              if (_retryOnClientError(e.errorMsg)) return;
              if (_fallbackToLocal(e.errorMsg)) return;
              _errorSink?.call(e.errorMsg);
            },
            // 会话状态（listening / notListening / done…）原样转出去；
            // 重开窗口里的那次 notListening 压住不发（见 [_retryingClient]）。
            onStatus: (s) {
              _sttLog('engine onStatus: $s');
              if (_retryingClient) return;
              _statusSink?.call(s);
            },
          )
          // 厂商 ROM 上识别服务偶发「不回调」（实测过点了没有任何反应）：
          // 超时按不可用收场，至少让页面给出明确提示，别永久挂起。
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () => false,
          );
      _initialized = _available;
      _sttLog('ensureReady: initialize -> available=$_available');
      if (!_available) {
        // 引擎起不来：把实例丢掉，下次重新建一个再试（有的 ROM 第一次
        // 拿不到 RecognitionService，第二次就有了）。
        _stt = null;
        return _ensureLocalReady();
      }
      return SpeechReady.available;
    } on Object catch (e) {
      _lastError = '$e';
      _initialized = false;
      _available = false;
      _stt = null;
      return _ensureLocalReady();
    } finally {
      _initializing = false;
    }
  }

  /// 本地引擎的就绪检查：模型齐了直接可用；没下就后台下载（幂等）并按
  /// 不可用收场 —— 下完以后下一轮收音/点麦克风就能用。
  Future<SpeechReady> _ensureLocalReady() async {
    _sttLog('ensureLocalReady: begin');
    // 权限照常要查：本地引擎同样吃麦克风，而且这条路径不经过系统引擎的
    // 初始化（权限在那边查），不补的话没权限只会报「麦克风打开失败」。
    if (!await _ensurePermission()) {
      _lastError ??= 'microphone permission denied';
      return SpeechReady.noPermission;
    }
    _sttLog('ensureLocalReady: permission ok');
    if (await _local.isModelReady()) {
      _useLocal = true;
      return SpeechReady.available;
    }
    if (!_local.isDownloading) {
      _sttLog('local: start model download');
      unawaited(
        _local.ensureModelDownloaded().then((ok) {
          _sttLog('local: model download ok=$ok');
        }),
      );
    }
    return SpeechReady.unavailable;
  }

  /// 系统识别服务「整个是坏的」的判断（见类注释第 6 条）：这些错误码在
  /// 健康的机器上只会由服务端结构性问题产生，重开无益 —— 命中后本会话
  /// 内永久切本地引擎。
  static const Set<String> _kSystemBrokenErrors = {
    'error_client',
    'error_too_many_requests',
  };

  /// 尝试切本地引擎兜底。返回 true = 已接管（或已开下载），错误别再往
  /// 页面甩（页面还停在「在听」，等本地起来/下载完自动续上）。
  bool _fallbackToLocal(String errorMsg) {
    if (_useLocal || _localTried) return false;
    if (!_kSystemBrokenErrors.contains(errorMsg)) return false;
    if (!_listenActive) return false;
    _localTried = true;
    _useLocal = true;
    _sttLog('system engine broken ($errorMsg), fallback to local asr');
    unawaited(() async {
      if (await _local.isModelReady()) {
        if (!_listenActive) return;
        await _local.start(
          onResult: _forwardLocalResult,
          onError: _forwardLocalError,
          onStatus: _forwardLocalStatus,
        );
        return;
      }
      // 模型没下：先下（约 25MB）。期间页面保持「在听」；下完这轮收音
      // 还活着就自动顶上，死了（用户挂断/松手）就等下一轮。
      _sttLog('local: start model download (mid-listen)');
      final ok = await _local.ensureModelDownloaded();
      _sttLog('local: model download ok=$ok');
      if (ok && _listenActive) {
        await _local.start(
          onResult: _forwardLocalResult,
          onError: _forwardLocalError,
          onStatus: _forwardLocalStatus,
        );
      } else if (!ok) {
        _useLocal = false;
        _errorSink?.call(errorMsg);
      }
    }());
    return true;
  }

  void _forwardLocalResult(String text, bool isFinal) =>
      _onResultSink?.call(text, isFinal);

  void _forwardLocalError(String message) {
    _lastError = message;
    _errorSink?.call(message);
  }

  void _forwardLocalStatus(String status) => _statusSink?.call(status);

  /// `error_client`（安卓「Client side error」）静默重开：识别服务还没绑定
  /// 好就 startListening，系统会立刻回这条错。它是转瞬即逝的，停下等绑定
  /// 落定再开一次就正常 —— 所以这里不把它当失败甩给页面，而是重开一次
  /// （**一轮只重开一次**，第二次再错就如实上报，避免死循环）。
  ///
  /// 返回 true = 这条错误已被吃掉、正在重开（调用方别再转发）。
  bool _retryOnClientError(String errorMsg) {
    if (errorMsg != 'error_client') return false;
    if (!_listenActive || _clientRetried) return false;
    final restart = _restart;
    if (restart == null) return false;
    _clientRetried = true;
    _retryingClient = true;
    Future<void>.delayed(_clientRetryDelay, () {
      // 等待期间用户松手 / 取消收音了：别再把麦克风打开。
      if (!_listenActive) {
        _retryingClient = false;
        return;
      }
      _retryingClient = false;
      restart().ignore();
    });
    return true;
  }

  /// 麦克风权限：已经给过就直接过，没给过用 permission_handler 正经弹一次
  /// （speech_to_text 自己在部分 ROM 上不弹，只会返回 false）。
  Future<bool> _ensurePermission() async {
    try {
      if (await _engine.hasPermission) return true;
      final status = await Permission.microphone.request();
      if (status.isGranted || status.isLimited) return true;
      _lastError = status.isPermanentlyDenied
          ? 'microphone permission denied permanently'
          : 'microphone permission denied';
      return false;
    } on Object catch (_) {
      // 平台没接 permission_handler（比如 Linux）：别拦着，
      // 交给 initialize 自己去判断。
      return true;
    }
  }

  /// 打开系统设置页（权限被永久拒绝时给用户的出口）。
  Future<bool> openSettings() async {
    try {
      return await openAppSettings();
    } on Object catch (_) {
      return false;
    }
  }

  /// 把应用 locale 映射成识别引擎认的 localeId。
  ///
  /// 引擎没装这个语言时返回 null，交给系统默认 —— 硬塞一个它不认识的
  /// localeId 会直接以 `error_no_match` 失败。
  ///
  /// 结果按 `lang_COUNTRY` 缓存（见 [_localeCache]）：底层 `locales()` 在
  /// 安卓 13+ 会另起一个 on-device 识别器，通话页一轮一段地问太浪费、也
  /// 太容易踩上 `startListening` 的竞态。
  Future<String?> resolveLocale(Locale locale) async {
    // 本地引擎是固定中英模型，不需要 localeId；也别去碰系统引擎。
    if (_useLocal) return null;
    final want =
        '${locale.languageCode}_${(locale.countryCode ?? '').toUpperCase()}';
    if (_localeCache.containsKey(want)) return _localeCache[want];
    _sttLog('resolveLocale: want=$want');
    try {
      final locales = await _engine
          .locales()
          .timeout(const Duration(seconds: 8), onTimeout: () => const []);
      // 一个语言都没报（超时 / 引擎没起来）是暂时性的，不缓存，下次再问。
      if (locales.isEmpty) return null;
      for (final l in locales) {
        if (l.localeId.replaceAll('-', '_').toLowerCase() ==
            want.toLowerCase()) {
          return _localeCache[want] = l.localeId;
        }
      }
      for (final l in locales) {
        if (l.localeId.toLowerCase().startsWith(
          locale.languageCode.toLowerCase(),
        )) {
          return _localeCache[want] = l.localeId;
        }
      }
      // 清单拿到了、确实没有这门语言：缓存 null，别反复问。
      _localeCache[want] = null;
    } catch (_) {
      // 异常同样是暂时性的，不缓存。
    }
    _sttLog('resolveLocale: miss -> null (want=$want)');
    return null;
  }

  /// 开始收音。[onResult] 会多次回调（partial 增量 + 最后一次 final）；
  /// [onError] 在识别中途报错时回调一次（带引擎原文），页面据此收尾状态。
  ///
  /// [onStatus] 转发引擎的会话状态（listening / notListening / done…）。
  /// 关键用途：**桌面端（Windows SAPI）没有 partial 事件**，引擎自己会在
  /// 断句处出一版 final 然后把会话收掉 —— 页面必须从 notListening 感知
  /// 「这一轮已经结束但没等到 final」，否则界面会永远停在收音态。
  Future<void> start({
    required void Function(String text, bool isFinal) onResult,
    void Function(String message)? onError,
    void Function(String status)? onStatus,
    String? localeId,
    Duration listenFor = const Duration(minutes: 2),
    Duration pauseFor = const Duration(seconds: 30),
  }) async {
    _errorSink = onError;
    _statusSink = onStatus;
    _onResultSink = onResult;
    _clientRetried = false;
    _retryingClient = false;
    _localTried = false;
    _listenActive = true;
    _sttLog('start: localeId=$localeId pauseFor=$pauseFor');

    // 系统服务已判死刑（或这轮先按系统走、中途切本地）：本地引擎的回调
    // 直接用 sink 转发 —— 切换发生在 listen 中途，闭包里的 sink 可能被
    // 下一轮 start 换掉，所以经字段转发而不是闭包捕获。
    if (_useLocal) {
      await _local.start(
        onResult: _forwardLocalResult,
        onError: _forwardLocalError,
        onStatus: _forwardLocalStatus,
      );
      return;
    }

    // 收一次收音封装成可重入的闭包：`error_client` 重开时要按**同一套参数**
    // 再开一次（见 [_retryOnClientError]）。
    Future<void> open() async {
      var pauseShortened = false;
      await _engine.listen(
        onResult: (r) {
          _sttLog('onResult: final=${r.finalResult} text=${r.recognizedWords}');
          // 第一个增量到手 = 这个引擎是流式的：把静音判定收紧回短值，
          // 说完停顿一拍就定稿。非流式引擎（Windows SAPI）永远没有增量，
          // 就靠它自己的断句出 final，[pauseFor] 只当「哑火保护」用。
          if (!r.finalResult && !pauseShortened) {
            pauseShortened = true;
            _engine.changePauseFor(_streamingPauseFor);
          }
          onResult(r.recognizedWords, r.finalResult);
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenFor: listenFor,
          pauseFor: pauseFor,
          localeId: localeId,
        ),
      );
    }

    _restart = open;
    await open();
  }

  /// 停止收音（保留已识别结果）。
  Future<void> stop() async {
    _listenActive = false;
    _restart = null;
    _retryingClient = false;
    if (_useLocal) {
      await _local.stop();
      _errorSink = null;
      _statusSink = null;
      _onResultSink = null;
      return;
    }
    final s = _stt;
    if (s == null) return;
    _errorSink = null;
    _statusSink = null;
    _onResultSink = null;
    try {
      await s.stop();
    } catch (_) {}
  }

  /// 取消收音（丢弃本次结果）。
  Future<void> cancel() async {
    _listenActive = false;
    _restart = null;
    _retryingClient = false;
    if (_useLocal) {
      await _local.cancel();
      _errorSink = null;
      _statusSink = null;
      _onResultSink = null;
      return;
    }
    final s = _stt;
    if (s == null) return;
    _errorSink = null;
    _statusSink = null;
    _onResultSink = null;
    try {
      await s.cancel();
    } catch (_) {}
  }
}

/// [SpeechInputService.ensureReady] 的结果。
enum SpeechReady {
  /// 可以开始收音。
  available,

  /// 麦克风权限没给（区分「永久拒绝」看 [SpeechInputService.lastError]）。
  noPermission,

  /// 设备上没有可用的识别服务。
  unavailable,

  /// 上一次准备还没回来（连点时的忙，页面什么都不用做）。
  busy,
}
