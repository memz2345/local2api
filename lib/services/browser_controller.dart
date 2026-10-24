// lib/services/browser_controller.dart
//
// 内置浏览器的跨平台控制器（自 NaviFlash `screens/browser_page.dart` 抽出来）：
// 业务状态与 webview 适配都放这里，Material / miuix 两个页面只负责画壳子。
//
// 平台分档：
//   · Windows → webview_windows（WebView2，vendored 在 third_party）
//   · Android / iOS / macOS → webview_flutter（系统 WebView / WKWebView）
//   · 其它（Linux 桌面等）→ 不建 webview，页面提示「用系统浏览器打开」
//
// 这里刻意不碰 B 站登录 / Cookie 导入那套 —— 本项目的浏览器是给 WebUI、
// SillyTavern 这类本地服务用的，通用能力（地址栏 / 前进后退 / UA / 外部打开）
// 就够，少一份平台特化的维护成本。

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_windows/webview_windows.dart' as win;

import '../src/enums.dart';
import 'browser_web_shim.dart';

/// 桌面 UA 兜底（WebView2 / 系统 WebView 的默认 UA 读不到时用）。
const String kBrowserDesktopUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0';

const String kBrowserMobileUa =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

bool _isMobileUa(String ua) {
  final lower = ua.toLowerCase();
  return lower.contains('android') ||
      lower.contains('iphone') ||
      lower.contains('ipad') ||
      lower.contains('mobile') ||
      lower.contains('mobi');
}

/// 替换 UA 里第一个括号内的平台段（`(Windows NT ...; ...)` 等）。
String _replacePlatformSegment(String ua, String replacement) {
  final start = ua.indexOf('(');
  if (start < 0) return ua;
  final end = ua.indexOf(')', start + 1);
  if (end < 0) return ua;
  return ua.replaceRange(start, end + 1, '($replacement)');
}

String _stripMobileMarkers(String ua) => ua.replaceAll(
  RegExp(r'\s+Mobile(?:/[0-9A-Za-z.\-]+)?\b', caseSensitive: false),
  '',
);

String _addMobileMarkers(String ua) {
  if (RegExp(r'\bMobile\b', caseSensitive: false).hasMatch(ua)) return ua;
  final idx = ua.indexOf(' Safari/');
  if (idx >= 0) return ua.replaceRange(idx, idx + 1, ' Mobile Safari/');
  return ua;
}

/// 把 UA 切成电脑端（已是电脑端则原样返回）。
String uaToDesktop(String ua) {
  if (ua.isEmpty || !_isMobileUa(ua)) return ua;
  final stripped = _stripMobileMarkers(ua);
  return _replacePlatformSegment(stripped, 'Windows NT 10.0; Win64; x64');
}

/// 把 UA 切成手机端（已是手机端则原样返回）。
String uaToMobile(String ua) {
  if (ua.isEmpty || _isMobileUa(ua)) return ua;
  final seg = ua.contains('Macintosh')
      ? 'iPhone; CPU iPhone OS 16_0 like Mac OS X'
      : 'Linux; Android 13; Pixel 7';
  return _addMobileMarkers(_replacePlatformSegment(ua, seg));
}

/// 用户在地址栏里敲的东西 → 真正要加载的 URL。
///
/// 有 scheme 原样用；像域名（含点、无空格）补 https；其余当搜索词。
String normalizeBrowserInput(String input) {
  final text = input.trim();
  if (text.isEmpty) return '';
  final lower = text.toLowerCase();
  const schemes = [
    'http://',
    'https://',
    'file://',
    'about:',
    'data:',
    'blob:',
    'javascript:',
    'chrome:',
    'edge:',
  ];
  if (schemes.any(lower.startsWith)) return text;
  if (!text.contains(' ') && (text.contains('.') || text.contains(':'))) {
    return 'https://$text';
  }
  return 'https://www.bing.com/search?q=${Uri.encodeQueryComponent(text)}';
}

class BrowserController extends ChangeNotifier {
  BrowserController({
    required this.initialUrl,
    BrowserUaMode uaMode = BrowserUaMode.auto,
    bool allowClipboard = true,
    String customUa = '',
  }) : _uaMode = uaMode, // ignore: prefer_initializing_formals
       // ignore: prefer_initializing_formals
       _allowClipboard = allowClipboard,
       // ignore: prefer_initializing_formals
       _customUa = customUa;

  final String initialUrl;

  BrowserUaMode _uaMode;
  BrowserUaMode get uaMode => _uaMode;

  /// 网页能不能写剪贴板（`navigator.clipboard` / `execCommand('copy')`）。
  ///
  /// 默认允许 —— 很多 WebUI（SillyTavern 的角色卡导出、WebUI 的复制配置）
  /// 依赖它；关掉后页面里那些按钮会静默失败。开关状态由页面持久化到
  /// `SettingsService.browserAllowClipboard`，这里只负责注入 JS。
  bool _allowClipboard = true;
  bool get allowClipboard => _allowClipboard;

  /// 用户自定义的 UA（空 = 用系统默认 / 按档位改写）。
  String _customUa = '';
  String get customUa => _customUa;

  WebViewController? _mobile;
  win.WebviewController? _windows;
  StreamSubscription<dynamic>? _webMessageSub;

  /// 手机端未改写的基准 UA（用来在「自动 / 电脑端 / 手机端」之间来回切）。
  String _baseUa = '';

  /// 网页里点了 `<select>` 时回调宿主。null = 不接管（原生弹窗照旧）。
  ///
  /// 返回值是选中项在 `<select>` 里的下标；null / 负数 = 取消（不改变原值）。
  /// 由 `widgets/browser_webview.dart` 挂上（Material / miuix 两套皮都在那里
  /// 按 `useMiuix` 分派）。
  Future<int?> Function(BrowserSelectRequest request)? selectHandler;

  /// 同一时间只处理一个选择请求（连点两下只会开一个面板）。
  bool _selectBusy = false;

  /// 要不要往网页里塞外壳补丁（滚动条 CSS + `<select>` 拦截）。
  ///
  /// iOS 的 WKWebView 原生 select 是滚轮选择器，比自绘的好用，不动它；
  /// macOS 的原生 select 只是一个小弹窗，和桌面端其它平台统一走应用内的
  /// Material / miuix 选择面板。
  static bool get _useShim =>
      Platform.isAndroid || Platform.isWindows || Platform.isMacOS;

  bool _ready = false;
  bool _disposed = false;

  /// 非空 = 初始化 / 主文档加载失败，页面显示错误视图。
  String? initError;

  String url = '';
  String? pageTitle;
  double progress = 0;
  bool loading = false;
  bool canGoBack = false;
  bool canGoForward = false;

  bool get isReady => _ready;
  bool get isWindows => Platform.isWindows;

  /// Windows 侧给 `win.Webview` 组件用的控制器。null = 还没初始化好。
  win.WebviewController? get windowsController => _windows;

  /// 移动端给 `WebViewWidget` 用的控制器。null = 还没初始化好 / 非移动端。
  WebViewController? get mobileController => _mobile;

  /// 当前页面的展示标题（标题为空时回退到主机名）。
  String get displayTitle {
    final t = pageTitle?.trim() ?? '';
    if (t.isNotEmpty) return t;
    final uri = Uri.tryParse(url);
    if (uri != null && uri.host.isNotEmpty) return uri.host;
    return url.isNotEmpty ? url : initialUrl;
  }

  Future<void> init() async {
    if (!_isSupportedPlatform) {
      initError = 'unsupported';
      _ready = true;
      _notify();
      return;
    }
    try {
      if (Platform.isWindows) {
        await _initWindows();
      } else {
        await _initMobile();
      }
    } catch (e) {
      initError = '$e';
    }
    _ready = true;
    _notify();
  }

  static bool get _isSupportedPlatform =>
      Platform.isWindows ||
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS;

  Future<void> _initWindows() async {
    final controller = win.WebviewController();
    await controller.initialize();
    _windows = controller;
    controller.url.listen((value) {
      url = value;
      _notify();
    });
    controller.title.listen((value) {
      if (value.trim().isEmpty) return;
      pageTitle = value.trim();
      _notify();
    });
    controller.loadingState.listen((state) {
      if (state == win.LoadingState.loading) {
        loading = true;
        progress = 0.2;
        initError = null;
      } else if (state == win.LoadingState.navigationCompleted) {
        loading = false;
        progress = 1;
        // 网页外壳补丁：滚动条 CSS + <select> 接管（每次导航重装，幂等）
        unawaited(_injectShim());
      }
      _notify();
    });
    controller.historyChanged.listen((history) {
      canGoBack = history.canGoBack;
      canGoForward = history.canGoForward;
      _notify();
    });
    controller.onLoadError.listen((error) {
      // WebView2 的证书错误 / 连接失败都走这里；页面自身 404 不算。
      initError = error.toString();
      loading = false;
      _notify();
    });
    // 自定义 scheme（mailto: / tel: / 第三方 app）交给系统，否则 WebView2
    // 会当成导航失败。移动端在 onNavigationRequest 里拦，见 _initMobile。
    await controller.addScriptToExecuteOnDocumentCreated(_customSchemeJs);
    // 剪贴板闸门：页面一加载就装好拦截器，再用 __ALLOW_CLIPBOARD__ 放行/否决。
    await controller.addScriptToExecuteOnDocumentCreated(_clipboardInterceptJs);
    await controller.addScriptToExecuteOnDocumentCreated(
      'window.__ALLOW_CLIPBOARD__ = $_allowClipboard;',
    );
    _webMessageSub = controller.webMessage.listen((message) {
      unawaited(handleWebMessage(message?.toString() ?? ''));
    });
    final ua = _effectiveUa(kBrowserDesktopUa);
    if (ua.isNotEmpty) await controller.setUserAgent(ua);
    await controller.loadUrl(normalizeBrowserInput(initialUrl));
  }

  static const String _customSchemeJs = r'''
document.addEventListener('click', function(e) {
  var target = e.target;
  while (target && target.tagName !== 'A') { target = target.parentElement; }
  if (!target || !target.href) return;
  var scheme = target.href.split(':')[0].toLowerCase();
  if (['http','https','file','data','javascript','blob','about'].indexOf(scheme) === -1) {
    e.preventDefault();
    if (window.chrome && window.chrome.webview) {
      window.chrome.webview.postMessage('CUSTOM_SCHEME:' + target.href);
    }
  }
}, true);
''';

  /// 剪贴板闸门（自 NaviFlash 原样搬来）：同时盖住 Clipboard API 与
  /// 老的 `execCommand('copy')`，只认页面里的 `window.__ALLOW_CLIPBOARD__`。
  static const String _clipboardInterceptJs = r'''
(function() {
  if (window.__CLIPBOARD_INTERCEPTED__) return;
  window.__CLIPBOARD_INTERCEPTED__ = true;
  if (typeof window.__ALLOW_CLIPBOARD__ === 'undefined') {
    window.__ALLOW_CLIPBOARD__ = true;
  }
  if (navigator.clipboard) {
    var originalWriteText = navigator.clipboard.writeText;
    if (originalWriteText) {
      navigator.clipboard.writeText = function(text) {
        if (!window.__ALLOW_CLIPBOARD__) {
          console.warn('Clipboard write blocked by app.');
          return Promise.reject(new DOMException('Blocked by app', 'NotAllowedError'));
        }
        return originalWriteText.call(navigator.clipboard, text);
      };
    }
    var originalWrite = navigator.clipboard.write;
    if (originalWrite) {
      navigator.clipboard.write = function(data) {
        if (!window.__ALLOW_CLIPBOARD__) {
          return Promise.reject(new DOMException('Blocked', 'NotAllowedError'));
        }
        return originalWrite.call(navigator.clipboard, data);
      };
    }
  }
  var originalExecCommand = document.execCommand;
  if (originalExecCommand) {
    document.execCommand = function(cmd, ui, val) {
      if ((cmd === 'copy' || cmd === 'cut') && !window.__ALLOW_CLIPBOARD__) {
        console.warn('Clipboard execCommand blocked by app.');
        return false;
      }
      return originalExecCommand.call(document, cmd, ui, val);
    };
  }
})();
''';

  Future<void> _initMobile() async {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
    _mobile = controller;
    if (_useShim) {
      // 网页里的 <select> 走 JS 通道抛给宿主（见 browser_web_shim.dart）。
      // 必须建在 load 之前：通道是随页面注入的。
      controller.addJavaScriptChannel(
        'L2ASelect',
        onMessageReceived: (message) =>
            unawaited(_handleShimMessage(message.message)),
      );
    }
    try {
      final base = await controller.getUserAgent();
      if (base != null && base.trim().isNotEmpty) _baseUa = base.trim();
    } catch (_) {}
    if (_baseUa.isEmpty) {
      _baseUa = Platform.isMacOS ? kBrowserDesktopUa : kBrowserMobileUa;
    }

    final ua = _effectiveUa(_baseUa);
    if (ua.isNotEmpty) {
      try {
        await controller.setUserAgent(ua);
      } catch (_) {}
    }
    await _applyWideViewport();

    controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.navigate;
          const allowed = {
            'http',
            'https',
            'file',
            'data',
            'about',
            'blob',
            'chrome',
            'javascript',
          };
          if (allowed.contains(uri.scheme.toLowerCase())) {
            return NavigationDecision.navigate;
          }
          unawaited(_openExternalUri(uri));
          return NavigationDecision.prevent;
        },
        onUrlChange: (change) {
          final next = change.url;
          if (next != null && next.isNotEmpty) {
            url = next;
            _notify();
          }
        },
        onPageStarted: (value) {
          url = value;
          loading = true;
          progress = 0;
          initError = null;
          unawaited(_injectClipboardGate());
          // 外壳补丁：document 可能还没建好，这里只是抢个早；真正的兜底在
          // onPageFinished 那次（脚本幂等）。
          unawaited(_injectShim());
          unawaited(_refreshHistory());
          _notify();
        },
        onProgress: (value) {
          progress = value / 100;
          _notify();
        },
        onPageFinished: (value) async {
          url = value;
          loading = false;
          progress = 1;
          // 页面 DOM 就绪，补丁这时候一定装得上（含 CSP 严格的页面：
          // runJavaScript 走的是 evaluateJavascript，不受页面 CSP 限制）。
          await _injectShim();
          try {
            final title = await controller.getTitle();
            if (title != null && title.trim().isNotEmpty) {
              pageTitle = title.trim();
            }
          } catch (_) {}
          await _refreshHistory();
          _notify();
        },
        onWebResourceError: (error) {
          // 子资源失败（图片 / 字体）不该把整页判死。
          if (error.isForMainFrame == false) return;
          initError = error.description;
          loading = false;
          _notify();
        },
      ),
    );
    await controller.loadRequest(Uri.parse(normalizeBrowserInput(initialUrl)));
  }

  /// 移动端：每次主文档开始加载时重装剪贴板闸门（页面换了，window 上的
  /// 拦截器与放行位都会重置）。
  Future<void> _injectClipboardGate() async {
    try {
      await _mobile?.runJavaScript(_clipboardInterceptJs);
      await _mobile?.runJavaScript(
        'window.__ALLOW_CLIPBOARD__ = $_allowClipboard;',
      );
    } catch (_) {}
  }

  /// 把外壳补丁写进页面（滚动条 CSS + `<select>` 接管）。幂等，可重复调。
  Future<void> _injectShim() async {
    if (!_useShim) return;
    try {
      if (Platform.isWindows) {
        await _windows?.executeScript(kBrowserShimJs);
      } else {
        await _mobile?.runJavaScript(kBrowserShimJs);
      }
    } catch (_) {}
  }

  /// 网页抛来的选择请求：交给 [selectHandler] 画面板，选完回填。
  Future<void> _handleShimMessage(Object? raw) async {
    final data = decodeBrowserShimMessage(raw);
    final request = BrowserSelectRequest.tryParse(data);
    if (request == null) return;
    if (_selectBusy) {
      await _resolveSelect(request.id, -1);
      return;
    }
    _selectBusy = true;
    int? picked;
    try {
      picked = await selectHandler?.call(request);
    } catch (_) {
      picked = null;
    } finally {
      _selectBusy = false;
    }
    await _resolveSelect(request.id, picked ?? -1);
  }

  /// 把选中的下标回填给页面（`__l2aSelectResolve` 见 browser_web_shim）。
  Future<void> _resolveSelect(String id, int index) async {
    final safeId = id.replaceAll(RegExp(r"[^0-9A-Za-z_-]"), '');
    final js =
        "window.__l2aSelectResolve && window.__l2aSelectResolve('$safeId', $index);";
    try {
      if (Platform.isWindows) {
        await _windows?.executeScript(js);
      } else {
        await _mobile?.runJavaScript(js);
      }
    } catch (_) {}
  }

  Future<void> _refreshHistory() async {
    final controller = _mobile;
    if (controller == null) return;
    try {
      canGoBack = await controller.canGoBack();
      canGoForward = await controller.canGoForward();
    } catch (_) {}
    _notify();
  }

  /// 当前档位下实际要设置的 UA。
  ///
  /// 用户显式填了自定义 UA 就原样用；否则按档位从基准值改写（Windows 用
  /// 桌面兜底，移动端用系统 WebView 的默认值）。
  String _effectiveUa(String base) {
    final custom = _customUa.trim();
    if (custom.isNotEmpty) return custom;
    final fallback = base.isEmpty
        ? (Platform.isWindows || Platform.isMacOS
              ? kBrowserDesktopUa
              : kBrowserMobileUa)
        : base;
    return switch (_uaMode) {
      BrowserUaMode.auto => fallback,
      BrowserUaMode.desktop => uaToDesktop(fallback),
      BrowserUaMode.mobile => uaToMobile(fallback),
    };
  }

  /// 读当前 webview 真实在用的 UA（给「自定义 UA」弹窗做初值）。
  Future<String?> readUserAgent() async {
    try {
      if (Platform.isWindows) {
        final result = await _windows?.executeScript(
          'return navigator.userAgent;',
        );
        return _cleanJsString(result);
      }
      return await _mobile?.getUserAgent();
    } catch (_) {
      return null;
    }
  }

  /// 按 UA 档位调 Android WebView 的宽视口。
  ///
  /// 桌面 UA 下页面期望宽布局：宽视口关着（插件默认 false）时桌面布局会被
  /// 钳进设备宽度，元素相对巨大（「整页被放大」的观感）。desktop 档位开
  /// useWideViewPort，页面按 ~980px 布局再整体缩放适配（即 Chrome「桌面版
  /// 网站」的行为，可双指缩放）。仅安卓有这个设置，其它平台是空操作。
  Future<void> _applyWideViewport() async {
    if (!Platform.isAndroid) return;
    final android = _mobile?.platform;
    if (android is! AndroidWebViewController) return;
    try {
      await android.setUseWideViewPort(_uaMode == BrowserUaMode.desktop);
    } catch (_) {}
  }

  /// 设自定义 UA（空 = 恢复默认）并刷新。
  Future<void> setUserAgent(String ua) async {
    _customUa = ua.trim();
    _notify();
    final effective = _effectiveUa(_baseUa);
    try {
      if (Platform.isWindows) {
        if (effective.isNotEmpty) await _windows?.setUserAgent(effective);
        await _windows?.reload();
      } else {
        await _mobile?.setUserAgent(effective.isEmpty ? null : effective);
        await _applyWideViewport();
        await _mobile?.reload();
      }
    } catch (_) {}
  }

  /// 开关网页写剪贴板的权限（立刻对新页面生效）。
  Future<void> setAllowClipboard(bool value) async {
    if (_allowClipboard == value) return;
    _allowClipboard = value;
    _notify();
    final js = 'window.__ALLOW_CLIPBOARD__ = $value;';
    try {
      if (Platform.isWindows) {
        await _windows?.executeScript(js);
      } else {
        await _mobile?.runJavaScript(js);
      }
    } catch (_) {}
  }

  Future<void> setUaMode(BrowserUaMode mode) async {
    if (_uaMode == mode) return;
    _uaMode = mode;
    _notify();
    final ua = _effectiveUa(_baseUa);
    try {
      if (Platform.isWindows) {
        await _windows?.setUserAgent(ua);
        await _windows?.reload();
      } else {
        await _mobile?.setUserAgent(ua);
        await _applyWideViewport();
        await _mobile?.reload();
      }
    } catch (_) {}
  }

  Future<void> loadInput(String input) async {
    final target = normalizeBrowserInput(input);
    if (target.isEmpty) return;
    initError = null;
    _notify();
    try {
      if (Platform.isWindows) {
        await _windows?.loadUrl(target);
      } else {
        await _mobile?.loadRequest(Uri.parse(target));
      }
    } catch (e) {
      initError = '$e';
      _notify();
    }
  }

  Future<void> reload() async {
    initError = null;
    _notify();
    try {
      if (Platform.isWindows) {
        await _windows?.reload();
      } else {
        await _mobile?.reload();
      }
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      if (Platform.isWindows) {
        await _windows?.stop();
      } else {
        // webview_flutter 4.x 的 WebViewController 没有 stopLoading：
        // 用页面自己的 window.stop() 停掉还在加载的资源。
        await _mobile?.runJavaScript('window.stop();');
        loading = false;
        _notify();
      }
    } catch (_) {}
  }

  Future<void> goBack() async {
    try {
      if (Platform.isWindows) {
        await _windows?.goBack();
      } else {
        await _mobile?.goBack();
      }
    } catch (_) {}
  }

  Future<void> goForward() async {
    try {
      if (Platform.isWindows) {
        await _windows?.goForward();
      } else {
        await _mobile?.goForward();
      }
    } catch (_) {}
  }

  /// 读取当前页的 document.cookie（不含 HttpOnly；给调试 / 长按复制用）。
  Future<String?> readDocumentCookie() async {
    try {
      if (Platform.isWindows) {
        final result = await _windows?.executeScript('return document.cookie;');
        return _cleanJsString(result);
      }
      final result = await _mobile?.runJavaScriptReturningResult(
        'document.cookie',
      );
      return _cleanJsString(result);
    } catch (_) {
      return null;
    }
  }

  static String? _cleanJsString(Object? value) {
    if (value is! String) return null;
    final cleaned = value.replaceAll(RegExp(r'^"|"$'), '').trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  Future<void> _openExternalUri(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// 把当前页交给系统默认浏览器打开。
  Future<void> openInSystemBrowser() async {
    final target = url.isNotEmpty ? url : normalizeBrowserInput(initialUrl);
    final uri = Uri.tryParse(target);
    if (uri == null) return;
    await _openExternalUri(uri);
  }

  /// Windows 的 webview 把自定义 scheme / 网页选择请求通过 webMessage 发过来，
  /// 控制器内部订阅后调这个（见 [_initWindows]）。
  Future<void> handleWebMessage(String message) async {
    if (message.startsWith('CUSTOM_SCHEME:')) {
      final uri = Uri.tryParse(message.substring('CUSTOM_SCHEME:'.length));
      if (uri == null) return;
      await _openExternalUri(uri);
      return;
    }
    final trimmed = message.trimLeft();
    if (trimmed.startsWith('{')) {
      await _handleShimMessage(trimmed);
    }
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    selectHandler = null;
    _webMessageSub?.cancel();
    _webMessageSub = null;
    _windows?.dispose();
    _windows = null;
    _mobile = null;
    super.dispose();
  }
}
