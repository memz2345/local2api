// lib/ui/miuix/miuix_browser_page.dart
//
// 内置浏览器（miuix 版，对应 Material 版 `ui/browser_page.dart`）。
//
// 这一版是把 NaviFlash v2 `screens/browser_page.dart` 整套搬过来的：
//   · 顶栏：返回（关页面）+ 停止/刷新 + 更多；标题跟着网页标题走
//   · 加载：顶栏下方 2px 进度条 + 初始化阶段 M3E 形状形变加载动画
//   · 返回行为：系统返回先退网页历史；鼠标侧键 X1/X2 = 前进/后退；
//     顶栏返回键直接关页面（与 NaviFlash 一致）
//   · 菜单：前进 / 编辑地址 / 复制链接 / 二维码 / Cookie / 剪贴板开关 /
//     自定义 UA / UA 档位 / 刷新 / 系统浏览器 / 网络疑难解答
//   · 错误页：BSOD / 挂掉的安卓机器人 / Apple / kernel panic 四套
//
// webview 适配仍在 `services/browser_controller.dart`，两边共用。

import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField;
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../services/browser_controller.dart';
import '../../services/custom_tabs_service.dart';
import '../../services/lab/dsh_web_answer_bridge.dart';
import '../../services/settings_service.dart';
import '../../src/enums.dart';
import '../../src/expressive_loading_indicator.dart';
import '../../widgets/browser_error_pages.dart';
import '../../widgets/browser_webview.dart';
import '../../widgets/custom_tabs_picker.dart';
import '../../widgets/miuix/miuix_app_icon.dart';
import '../../widgets/miuix/miuix_blur_top_bar.dart';
import '../../widgets/miuix/miuix_bottom_sheet.dart';
import '../../widgets/miuix/miuix_dialog.dart';
import '../../widgets/miuix/miuix_group_card.dart';
import '../../widgets/miuix/miuix_text_field.dart';
import '../../widgets/miuix/miuix_toast.dart';

class MiuixBrowserPage extends StatefulWidget {
  const MiuixBrowserPage({super.key, required this.initialUrl, this.title});

  final String initialUrl;
  final String? title;

  /// 集成测试用：拿到页内 controller，往 WKWebView 里注入 JS、读取页面状态。
  @visibleForTesting
  static BrowserController? debugLastController;

  @override
  State<MiuixBrowserPage> createState() => _MiuixBrowserPageState();
}

class _MiuixBrowserPageState extends State<MiuixBrowserPage> {
  late final BrowserController _controller;
  bool _clipboardBusy = false;

  /// 顶栏折叠状态：页面内容是 webview，不是滚动列表，折叠量没人驱动 ——
  /// 在这里持有一份自己的 state，进页面第一帧就把折叠量压到上限，
  /// 让顶栏保持「折叠后的窄条」常态（网页标题太长时只有小标题放得下）。
  final MiuixExitUntilCollapsedScrollBehavior _topBarBehavior =
      MiuixExitUntilCollapsedScrollBehavior();

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    _controller = BrowserController(
      initialUrl: widget.initialUrl,
      uaMode: settings.browserUaMode,
      allowClipboard: settings.browserAllowClipboard,
    );
    MiuixBrowserPage.debugLastController = _controller;
    DshWebAnswerBridge.attach(_controller);
    _controller.addListener(_onChanged);
    _controller.init();
    _foldTopBarWhenMeasured();
  }

  /// 顶栏的展开量（heightOffsetLimit）是它自己布局完才量出来的
  /// （包版在 post-frame 回调里写 state），所以这里逐帧重试，量出来即折叠。
  void _foldTopBarWhenMeasured() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = _topBarBehavior.state;
      if (state.heightOffsetLimit.isFinite && state.heightOffsetLimit < 0) {
        state.heightOffset = state.heightOffsetLimit;
      } else {
        _foldTopBarWhenMeasured();
      }
    });
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (identical(MiuixBrowserPage.debugLastController, _controller)) {
      MiuixBrowserPage.debugLastController = null;
    }
    _controller.removeListener(_onChanged);
    DshWebAnswerBridge.detach(_controller);
    _controller.dispose();
    _topBarBehavior.state.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  String get _currentUrl =>
      _controller.url.isEmpty ? widget.initialUrl : _controller.url;

  // ---- 地址 / 链接 ----

  Future<void> _editUrl() async {
    final l10n = AppLocalizations.of(context);
    final textController = TextEditingController(text: _currentUrl);
    final value = await showMiuixDialog<String>(
      context: context,
      title: l10n.browserEditUrl,
      content: MiuixTextField(
        controller: textController,
        label: l10n.browserUrlHint,
        useLabelAsPlaceholder: true,
        singleLine: true,
        autofocus: true,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.go,
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        MiuixDialogAction(
          label: l10n.cancel,
          onPressed: (dialogContext) => Navigator.of(dialogContext).pop(),
        ),
        MiuixDialogAction(
          label: l10n.browserGo,
          primary: true,
          onPressed: (dialogContext) =>
              Navigator.of(dialogContext).pop(textController.text),
        ),
      ],
    );
    if (!mounted || value == null || value.trim().isEmpty) return;
    await _controller.loadInput(value);
  }

  Future<void> _copyLink() async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: _currentUrl));
    if (!mounted) return;
    showMiuixToast(context, l10n.copied);
  }

  Future<void> _showCookieDialog() async {
    final l10n = AppLocalizations.of(context);
    final cookie = await _controller.readDocumentCookie();
    if (!mounted) return;
    if (cookie == null) {
      showMiuixToast(context, l10n.browserCookieEmpty, error: true);
      return;
    }
    await showMiuixDialog<void>(
      context: context,
      title: l10n.browserViewCookies,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: SingleChildScrollView(
          child: SelectableText(
            cookie,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ),
      actions: [
        MiuixDialogAction(
          label: l10n.close,
          onPressed: (dialogContext) => Navigator.of(dialogContext).pop(),
        ),
        MiuixDialogAction(
          label: l10n.browserCopyAll,
          primary: true,
          onPressed: (dialogContext) async {
            await Clipboard.setData(ClipboardData(text: cookie));
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          },
        ),
      ],
    );
  }

  void _showQrCode() {
    final l10n = AppLocalizations.of(context);
    final url = _currentUrl;
    showMiuixDialog<void>(
      context: context,
      title: l10n.browserQrTitle,
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
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
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
        MiuixDialogAction(
          label: l10n.close,
          onPressed: (dialogContext) => Navigator.of(dialogContext).pop(),
        ),
        MiuixDialogAction(
          label: l10n.browserCopyLink,
          primary: true,
          onPressed: (dialogContext) async {
            await Clipboard.setData(ClipboardData(text: url));
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          },
        ),
      ],
    );
  }

  Future<void> _showUaDialog() async {
    final l10n = AppLocalizations.of(context);
    final current = await _controller.readUserAgent();
    if (!mounted) return;
    final textController = TextEditingController(
      text: _controller.customUa.isEmpty
          ? (current ?? '')
          : _controller.customUa,
    );
    final value = await showMiuixDialog<String>(
      context: context,
      title: l10n.browserSetUa,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MiuixTextField(
            controller: textController,
            label: l10n.browserUaHint,
            useLabelAsPlaceholder: true,
            singleLine: false,
            minLines: 2,
            maxLines: 4,
          ),
          const SizedBox(height: 8),
          MiuixText(
            l10n.browserUaEmptyHint,
            fontSize: 12,
            color: MiuixTheme.of(context).colors.onSurfaceVariantSummary,
          ),
        ],
      ),
      actions: [
        MiuixDialogAction(
          label: l10n.cancel,
          onPressed: (dialogContext) => Navigator.of(dialogContext).pop(),
        ),
        MiuixDialogAction(
          label: l10n.browserApplyAndReload,
          primary: true,
          onPressed: (dialogContext) =>
              Navigator.of(dialogContext).pop(textController.text),
        ),
      ],
    );
    if (!mounted || value == null) return;
    await _controller.setUserAgent(value);
    if (!mounted) return;
    showMiuixToast(context, l10n.browserUaUpdated);
  }

  /// 剪贴板开关：控制器里注入 JS，偏好落 SettingsService（下次进来还是这个值）。
  Future<void> _toggleClipboard() async {
    if (_clipboardBusy) return;
    final l10n = AppLocalizations.of(context);
    final next = !_controller.allowClipboard;
    setState(() => _clipboardBusy = true);
    await _controller.setAllowClipboard(next);
    if (!mounted) return;
    await context.read<SettingsService>().setBrowserAllowClipboard(next);
    if (!mounted) return;
    setState(() => _clipboardBusy = false);
    showMiuixToast(
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
    showMiuixToast(context, l10n.browserTroubleshootFailed, error: true);
  }

  /// Custom Tabs：交给 Chromium 系浏览器；一台都没装就回退系统浏览器。
  Future<void> _openCustomTabs() async {
    final l10n = AppLocalizations.of(context);
    final handled = await openInCustomTabs(
      context,
      url: _currentUrl,
      useMiuix: true,
      ask: true,
    );
    if (handled || !mounted) return;
    await _controller.openInSystemBrowser();
    if (!mounted) return;
    showMiuixToast(context, l10n.browserCustomTabNone, error: true);
  }

  String _uaLabel(AppLocalizations l10n, BrowserUaMode mode) => switch (mode) {
    BrowserUaMode.auto => l10n.browserUaAuto,
    BrowserUaMode.desktop => l10n.browserUaDesktop,
    BrowserUaMode.mobile => l10n.browserUaMobile,
  };

  /// 鼠标侧键：X1 后退（没历史就关页面），X2 前进 —— NaviFlash 同款。
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

  Future<void> _pickUaMode() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showMiuixBottomSheet<BrowserUaMode>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: MiuixGroupCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in BrowserUaMode.values)
                  MiuixRadioButtonPreference(
                    title: _uaLabel(l10n, mode),
                    selected: mode == _controller.uaMode,
                    insideMargin: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    onClick: () => Navigator.of(sheetContext).pop(mode),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked == null) return;
    await _controller.setUaMode(picked);
    if (mounted) {
      unawaited(context.read<SettingsService>().setBrowserUaMode(picked));
    }
  }

  Future<void> _showMenu() async {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final action = await showMiuixBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: MiuixGroupCard(
                    child: Column(
                      children: [
                        if (_controller.canGoForward)
                          _MiuixMenuRow(
                            icon: AppIconNames.forward,
                            fallback: Icons.arrow_forward,
                            label: l10n.browserForward,
                            onTap: () =>
                                Navigator.of(sheetContext).pop('forward'),
                          ),
                        _MiuixMenuRow(
                          icon: AppIconNames.edit,
                          fallback: Icons.edit_outlined,
                          label: l10n.browserEditUrl,
                          onTap: () =>
                              Navigator.of(sheetContext).pop('edit_url'),
                        ),
                        _MiuixMenuRow(
                          icon: AppIconNames.link,
                          fallback: Icons.link,
                          label: l10n.browserCopyLink,
                          onTap: () =>
                              Navigator.of(sheetContext).pop('copy_link'),
                        ),
                        _MiuixMenuRow(
                          icon: AppIconNames.scan,
                          fallback: Icons.qr_code_2,
                          label: l10n.browserShareQr,
                          onTap: () => Navigator.of(sheetContext).pop('qr'),
                        ),
                        _MiuixMenuRow(
                          icon: AppIconNames.copy,
                          fallback: Icons.cookie_outlined,
                          label: l10n.browserViewCookies,
                          onTap: () => Navigator.of(sheetContext).pop('cookie'),
                        ),
                        _MiuixMenuRow(
                          icon: AppIconNames.paste,
                          fallback: Icons.content_paste_go,
                          label: l10n.browserClipboardAccess,
                          trailing: _controller.allowClipboard
                              ? Icon(
                                  Icons.check,
                                  size: 18,
                                  color: colors.primary,
                                )
                              : null,
                          onTap: () =>
                              Navigator.of(sheetContext).pop('clipboard'),
                        ),
                        _MiuixMenuRow(
                          icon: AppIconNames.edit,
                          fallback: Icons.emoji_people,
                          label: l10n.browserSetUa,
                          onTap: () => Navigator.of(sheetContext).pop('ua'),
                        ),
                        _MiuixMenuRow(
                          icon: AppIconNames.show,
                          fallback: Icons.devices_outlined,
                          label:
                              '${l10n.browserUaLabel} · '
                              '${_uaLabel(l10n, _controller.uaMode)}',
                          onTap: () =>
                              Navigator.of(sheetContext).pop('ua_mode'),
                        ),
                        _MiuixMenuRow(
                          icon: AppIconNames.refresh,
                          fallback: Icons.refresh,
                          label: l10n.browserReload,
                          onTap: () => Navigator.of(sheetContext).pop('reload'),
                        ),
                        if (CustomTabsService.isSupported)
                          _MiuixMenuRow(
                            icon: AppIconNames.link,
                            fallback: Icons.tab_outlined,
                            label: l10n.browserOpenCustomTab,
                            onTap: () =>
                                Navigator.of(sheetContext).pop('custom_tabs'),
                          ),
                        _MiuixMenuRow(
                          icon: AppIconNames.share,
                          fallback: Icons.open_in_browser,
                          label: l10n.browserOpenExternal,
                          onTap: () =>
                              Navigator.of(sheetContext).pop('external'),
                        ),
                        _MiuixMenuRow(
                          icon: AppIconNames.info,
                          fallback: Icons.network_check,
                          label: l10n.browserTroubleshootNetwork,
                          onTap: () =>
                              Navigator.of(sheetContext).pop('troubleshoot'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_controller.url.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
                  child: MiuixText(
                    _controller.url,
                    fontSize: 12,
                    color: colors.onSurfaceVariantSummary,
                    maxLines: 2,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
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
        await _controller.openInSystemBrowser();
      case 'troubleshoot':
        await _troubleshootNetwork();
    }
  }

  BrowserErrorStyle get _errorStyle {
    if (_controller.isWindows) return BrowserErrorStyle.bsod;
    if (Platform.isAndroid) return BrowserErrorStyle.android;
    if (Platform.isIOS || Platform.isMacOS) return BrowserErrorStyle.apple;
    return BrowserErrorStyle.generic;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final title = _controller.displayTitle.isEmpty
        ? (widget.title ?? l10n.browserTitle)
        : _controller.displayTitle;
    return PopScope(
      // 网页还能后退时，系统返回先退网页；退到头了才关页面（NaviFlash 同款）。
      canPop: !_controller.canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _controller.canGoBack) _controller.goBack();
      },
      child: Material(
        type: MaterialType.transparency,
        child: MiuixScaffold(
          containerColor: colors.surface,
          topBar: MiuixBlurTopBar(
            title: title,
            scrollBehavior: _topBarBehavior,
            navigationIcon: MiuixIconButton(
              onPressed: _close,
              child: const MiuixAppIcon(
                AppIconNames.back,
                fallback: Icons.arrow_back,
              ),
            ),
            actions: [
              MiuixIconButton(
                onPressed: _controller.loading
                    ? _controller.stop
                    : _controller.reload,
                child: MiuixAppIcon(
                  _controller.loading
                      ? AppIconNames.close
                      : AppIconNames.refresh,
                  fallback: _controller.loading ? Icons.close : Icons.refresh,
                ),
              ),
              MiuixIconButton(
                onPressed: _showMenu,
                child: const MiuixAppIcon(
                  AppIconNames.more,
                  fallback: Icons.more_vert,
                ),
              ),
            ],
          ),
          content: (padding) => Padding(
            padding: EdgeInsets.only(top: padding.top),
            child: Column(
              children: [
                if (_controller.loading)
                  MiuixLinearProgressIndicator(
                    progress: _controller.progress <= 0
                        ? null
                        : _controller.progress,
                    height: 2,
                  ),
                Expanded(
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: _onPointerDown,
                    child: _buildBody(colors),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(MiuixColors colors) {
    if (_controller.initError != null) {
      return BrowserErrorPage(
        style: _errorStyle,
        detail: _controller.initError,
        onBack: _close,
      );
    }
    if (!_controller.isReady) {
      // NaviFlash 同款：初始化阶段用 M3E 形状形变加载动画，不用转圈。
      return Center(child: ExpressiveLoadingIndicator(color: colors.primary));
    }
    return BrowserWebView(controller: _controller, useMiuix: true);
  }
}

/// 底部菜单里的一行（miuix）。
class _MiuixMenuRow extends StatelessWidget {
  const _MiuixMenuRow({
    required this.icon,
    required this.fallback,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final String icon;
  final IconData fallback;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixPressable(
      onPressed: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
        child: Row(
          children: [
            MiuixAppIcon(
              icon,
              fallback: fallback,
              size: 21,
              color: colors.onSurface,
            ),
            const SizedBox(width: 14),
            Expanded(child: MiuixText(label, fontSize: 15)),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
