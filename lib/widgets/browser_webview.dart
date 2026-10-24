// lib/widgets/browser_webview.dart
//
// 两套 UI 共用的 webview 画布：按平台选 WebView2 / 系统 WebView。
// 页面壳子（Material / miuix）只管顶栏与错误页，这里只负责「把网页贴上去」。
//
// 另外这里也是网页 `<select>` 的宿主：注入的 shim（services/browser_web_shim）
// 把原生弹窗拦下来，本组件用对应风格的底部选择器画出来（Material 3 / miuix）。

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as win;

import '../l10n/app_localizations.dart';
import '../services/browser_controller.dart';
import '../services/browser_web_shim.dart';
import '../src/expressive_loading_indicator.dart';
import 'browser_web_select_sheet.dart';

class BrowserWebView extends StatefulWidget {
  const BrowserWebView({
    super.key,
    required this.controller,
    this.useMiuix = false,
  });

  final BrowserController controller;

  /// 网页 `<select>` 的选择器用哪套皮（与所在页面的风格一致）。
  final bool useMiuix;

  @override
  State<BrowserWebView> createState() => _BrowserWebViewState();
}

class _BrowserWebViewState extends State<BrowserWebView> {
  @override
  void initState() {
    super.initState();
    widget.controller.selectHandler = _handleSelect;
  }

  @override
  void didUpdateWidget(covariant BrowserWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.selectHandler = null;
      widget.controller.selectHandler = _handleSelect;
    }
  }

  @override
  void dispose() {
    if (widget.controller.selectHandler == _handleSelect) {
      widget.controller.selectHandler = null;
    }
    super.dispose();
  }

  Future<int?> _handleSelect(BrowserSelectRequest request) async {
    if (!mounted) return -1;
    final l10n = AppLocalizations.of(context);
    final label = request.label.trim();
    final picked = await showBrowserWebSelectSheet(
      context,
      request: request,
      title: label.isEmpty ? l10n.browserSelectTitle : label,
      useMiuix: widget.useMiuix,
    );
    return picked ?? -1;
  }

  @override
  Widget build(BuildContext context) {
    // NaviFlash 同款：webview 还没挂上时给 M3E 形状形变动画，不转圈。
    final loading = Center(
      child: ExpressiveLoadingIndicator(
        color: Theme.of(context).colorScheme.primary,
      ),
    );
    final controller = widget.controller;
    if (controller.isWindows) {
      final windows = controller.windowsController;
      if (windows == null) return loading;
      // WebView2 的画面是原生纹理，外面包一层 ClipRect 防止偶发的
      // 一像素越界（页面切场时能看到）。
      return ClipRect(child: win.Webview(windows));
    }
    final mobile = controller.mobileController;
    if (mobile == null) return loading;
    return WebViewWidget(controller: mobile);
  }
}
