// lib/ui/browser_page.dart
//
// 内置浏览器（Material 版，自 NaviFlash `screens/browser_page.dart` 移植）。
//
// 与 miuix 版同一套行为：
//   · 顶栏返回 = 关页面；系统返回先退网页历史；鼠标侧键 X1/X2 前进后退
//   · 顶栏下方 2px 进度条，初始化阶段 M3E 形状形变加载动画
//   · 菜单：前进 / 编辑地址 / 复制链接 / 二维码 / Cookie / 剪贴板开关 /
//     自定义 UA / UA 档位 / 刷新 / 系统浏览器 / 网络疑难解答
//   · 错误页共用 `widgets/browser_error_pages.dart` 的四套
//
// 具体 webview 适配在 `services/browser_controller.dart`，miuix 版是
// `ui/miuix/miuix_browser_page.dart`，两边共用同一个控制器。

import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, visibleForTesting;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../services/browser_controller.dart';
import '../services/custom_tabs_service.dart';
import '../services/lab/dsh_web_answer_bridge.dart';
import '../services/settings_service.dart';
import '../src/enums.dart';
import '../src/expressive_loading_indicator.dart';
import '../widgets/app_toast.dart';
import '../widgets/browser_error_pages.dart';
import '../widgets/browser_webview.dart';
import '../widgets/custom_tabs_picker.dart';

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key, required this.initialUrl, this.title});

  final String initialUrl;

  /// 首帧标题（页面标题还没读到时先显示它）。
  final String? title;

  /// 集成测试用：拿到当前页的 controller，往 WKWebView 里注入 JS、
  /// 读取页面状态。正常运行时不会有人读它。
  @visibleForTesting
  static BrowserController? debugLastController;

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  late final BrowserController _controller;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    _controller = BrowserController(
      initialUrl: widget.initialUrl,
      uaMode: settings.browserUaMode,
      allowClipboard: settings.browserAllowClipboard,
    );
    BrowserPage.debugLastController = _controller;
    DshWebAnswerBridge.attach(_controller);
    _controller.addListener(_onChanged);
    _controller.init();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (identical(BrowserPage.debugLastController, _controller)) {
      BrowserPage.debugLastController = null;
    }
    _controller.removeListener(_onChanged);
    DshWebAnswerBridge.detach(_controller);
    _controller.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  String get _currentUrl =>
      _controller.url.isEmpty ? widget.initialUrl : _controller.url;

  Future<void> _editUrl() async {
    final l10n = AppLocalizations.of(context);
    final input = TextEditingController(text: _currentUrl);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.browserEditUrl),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          decoration: InputDecoration(
            hintText: l10n.browserUrlHint,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(input.text),
            child: Text(l10n.browserGo),
          ),
        ],
      ),
    );
    if (!mounted || value == null || value.trim().isEmpty) return;
    await _controller.loadInput(value);
  }

  Future<void> _copyLink() async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: _currentUrl));
    if (!mounted) return;
    showAppToast(context, l10n.copied);
  }

  Future<void> _showCookieDialog() async {
    final l10n = AppLocalizations.of(context);
    final cookie = await _controller.readDocumentCookie();
    if (!mounted) return;
    if (cookie == null) {
      showAppToast(context, l10n.browserCookieEmpty, error: true);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.browserViewCookies),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              cookie,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.close),
          ),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: cookie));
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: Text(l10n.browserCopyAll),
          ),
        ],
      ),
    );
  }

  void _showQrCode() {
    final l10n = AppLocalizations.of(context);
    final url = _currentUrl;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.browserQrTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: QrImageView(
                data: url,
                version: QrVersions.auto,
                size: 208,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              url,
              textAlign: TextAlign.center,
              maxLines: 3,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.close),
          ),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: Text(l10n.browserCopyLink),
          ),
        ],
      ),
    );
  }

  Future<void> _showUaDialog() async {
    final l10n = AppLocalizations.of(context);
    final current = await _controller.readUserAgent();
    if (!mounted) return;
    final input = TextEditingController(
      text: _controller.customUa.isEmpty
          ? (current ?? '')
          : _controller.customUa,
    );
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.browserSetUa),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: input,
              maxLines: 4,
              minLines: 2,
              decoration: InputDecoration(
                hintText: l10n.browserUaHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.browserUaEmptyHint,
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(input.text),
            child: Text(l10n.browserApplyAndReload),
          ),
        ],
      ),
    );
    if (!mounted || value == null) return;
    await _controller.setUserAgent(value);
    if (!mounted) return;
    showAppToast(context, l10n.browserUaUpdated);
  }

  Future<void> _toggleClipboard() async {
    final l10n = AppLocalizations.of(context);
    final next = !_controller.allowClipboard;
    await _controller.setAllowClipboard(next);
    if (!mounted) return;
    await context.read<SettingsService>().setBrowserAllowClipboard(next);
    if (!mounted) return;
    showAppToast(
      context,
      next ? l10n.browserClipboardAllowed : l10n.browserClipboardBlocked,
    );
  }

  Future<void> _troubleshootNetwork() async {
    final l10n = AppLocalizations.of(context);
    final uri = Uri.parse(
      'ms-contact-support://smc-to-emerald/NetworkAndInternetTroubleshooter',
    );
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    showAppToast(context, l10n.browserTroubleshootFailed, error: true);
  }

  Future<void> _openExternal() => _controller.openInSystemBrowser();

  /// Custom Tabs：交给 Chromium 系浏览器（Chrome / Edge / Brave…）。
  /// 一台都没装就回退系统浏览器，并给条提示（不然按钮像坏的）。
  Future<void> _openCustomTabs() async {
    final l10n = AppLocalizations.of(context);
    final handled = await openInCustomTabs(
      context,
      url: _currentUrl,
      useMiuix: false,
      ask: true,
    );
    if (handled || !mounted) return;
    await _controller.openInSystemBrowser();
    if (!mounted) return;
    showAppToast(context, l10n.browserCustomTabNone, error: true);
  }

  String _uaLabel(AppLocalizations l10n, BrowserUaMode mode) => switch (mode) {
    BrowserUaMode.auto => l10n.browserUaAuto,
    BrowserUaMode.desktop => l10n.browserUaDesktop,
    BrowserUaMode.mobile => l10n.browserUaMobile,
  };

  Future<void> _pickUaMode() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<BrowserUaMode>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final mode in BrowserUaMode.values)
              ListTile(
                title: Text(_uaLabel(l10n, mode)),
                trailing: mode == _controller.uaMode
                    ? Icon(
                        Icons.check,
                        color: Theme.of(sheetContext).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(mode),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await _controller.setUaMode(picked);
    if (mounted) {
      unawaited(context.read<SettingsService>().setBrowserUaMode(picked));
    }
  }

  /// 鼠标侧键：X1 后退（没历史就关页面），X2 前进。
  void _onPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    if (event.buttons & kBackMouseButton != 0) {
      if (_controller.canGoBack) {
        _controller.goBack();
      } else {
        _close();
      }
    } else if (event.buttons & kForwardMouseButton != 0) {
      if (_controller.canGoForward) _controller.goForward();
    }
  }

  BrowserErrorStyle get _errorStyle {
    if (_controller.isWindows) return BrowserErrorStyle.bsod;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return BrowserErrorStyle.android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return BrowserErrorStyle.apple;
      default:
        return BrowserErrorStyle.generic;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = _controller.displayTitle.isEmpty
        ? (widget.title ?? l10n.browserTitle)
        : _controller.displayTitle;

    return PopScope(
      // 网页还能后退时，系统返回手势先退网页；退到头了才 pop 页面。
      canPop: !_controller.canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _controller.canGoBack) _controller.goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: l10n.browserClosePage,
            onPressed: _close,
          ),
          titleSpacing: 0,
          title: InkWell(
            onTap: _editUrl,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  if (_controller.url.isNotEmpty)
                    Text(
                      _controller.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(_controller.loading ? Icons.close : Icons.refresh),
              tooltip: _controller.loading
                  ? l10n.browserStop
                  : l10n.browserReload,
              onPressed: _controller.loading
                  ? _controller.stop
                  : _controller.reload,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: l10n.browserMenu,
              onSelected: (value) async {
                switch (value) {
                  case 'forward':
                    await _controller.goForward();
                  case 'edit_url':
                    await _editUrl();
                  case 'copy_link':
                    await _copyLink();
                  case 'qr':
                    _showQrCode();
                  case 'cookie':
                    await _showCookieDialog();
                  case 'clipboard':
                    await _toggleClipboard();
                  case 'ua':
                    await _showUaDialog();
                  case 'ua_mode':
                    await _pickUaMode();
                  case 'reload':
                    await _controller.reload();
                  case 'custom_tabs':
                    await _openCustomTabs();
                  case 'external':
                    await _openExternal();
                  case 'troubleshoot':
                    await _troubleshootNetwork();
                }
              },
              itemBuilder: (menuContext) => [
                if (_controller.canGoForward)
                  PopupMenuItem(
                    value: 'forward',
                    child: ListTile(
                      leading: const Icon(Icons.arrow_forward),
                      title: Text(l10n.browserForward),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                PopupMenuItem(
                  value: 'edit_url',
                  child: ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: Text(l10n.browserEditUrl),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'copy_link',
                  child: ListTile(
                    leading: const Icon(Icons.link),
                    title: Text(l10n.browserCopyLink),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'qr',
                  child: ListTile(
                    leading: const Icon(Icons.qr_code_2),
                    title: Text(l10n.browserShareQr),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'cookie',
                  child: ListTile(
                    leading: const Icon(Icons.cookie_outlined),
                    title: Text(l10n.browserViewCookies),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'clipboard',
                  child: ListTile(
                    leading: const Icon(Icons.content_paste_go),
                    title: Text(l10n.browserClipboardAccess),
                    trailing: _controller.allowClipboard
                        ? Icon(
                            Icons.check,
                            size: 18,
                            color: colorScheme.primary,
                          )
                        : null,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'ua',
                  child: ListTile(
                    leading: const Icon(Icons.emoji_people),
                    title: Text(l10n.browserSetUa),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'ua_mode',
                  child: ListTile(
                    leading: const Icon(Icons.devices_outlined),
                    title: Text(
                      '${l10n.browserUaLabel} · '
                      '${_uaLabel(l10n, _controller.uaMode)}',
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'reload',
                  child: ListTile(
                    leading: const Icon(Icons.refresh),
                    title: Text(l10n.browserReload),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (CustomTabsService.isSupported)
                  PopupMenuItem(
                    value: 'custom_tabs',
                    child: ListTile(
                      leading: const Icon(Icons.tab_outlined),
                      title: Text(l10n.browserOpenCustomTab),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                PopupMenuItem(
                  value: 'external',
                  child: ListTile(
                    leading: const Icon(Icons.open_in_browser),
                    title: Text(l10n.browserOpenExternal),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'troubleshoot',
                  child: ListTile(
                    leading: const Icon(Icons.network_check),
                    title: Text(l10n.browserTroubleshootNetwork),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: _controller.loading
                ? LinearProgressIndicator(
                    value: _controller.progress <= 0
                        ? null
                        : _controller.progress,
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                  )
                : const SizedBox(height: 2),
          ),
        ),
        body: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          child: _buildBody(l10n),
        ),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_controller.initError != null) {
      return BrowserErrorPage(
        style: _errorStyle,
        detail: _controller.initError,
        onBack: _close,
      );
    }
    if (!_controller.isReady) {
      // NaviFlash 同款加载动画（M3E 形状形变）。
      return Center(
        child: ExpressiveLoadingIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }
    return BrowserWebView(controller: _controller, useMiuix: false);
  }
}
