import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/webui_server.dart';
import 'package:local2api/widgets/custom_tabs_picker.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_info_card.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';
import 'package:url_launcher/url_launcher.dart';

import '../browser_page.dart';
import '../widgets/common.dart' show pushStyledPage;
import 'miuix_browser_page.dart';

/// 临时 WebUI 设置页（miuix 版，对应 Material 版 `WebUiPage`）。
///
/// 同一份 `ProxyConfig`（webUiEnabled / webUiHost / webUiPort），只换渲染：
/// 分组用 `MiuixGroupCard`、开关行用 `MiuixSwitchPreference`、
/// 下拉用 `MiuixOverlayDropdownPreference`。
class MiuixWebUiPage extends StatefulWidget {
  const MiuixWebUiPage({super.key, required this.controller});

  final ServerController controller;

  @override
  State<MiuixWebUiPage> createState() => _MiuixWebUiPageState();
}

class _MiuixWebUiPageState extends State<MiuixWebUiPage> {
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();
  late final TextEditingController _portCtrl;
  int _lastWrittenPort = 0;

  @override
  void initState() {
    super.initState();
    final port = widget.controller.config.webUiPort;
    _lastWrittenPort = port;
    _portCtrl = TextEditingController(text: '$port');
  }

  @override
  void dispose() {
    _behavior.state.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final l10n = AppLocalizations.of(context);
    final url = widget.controller.webUi.url;
    if (url == null) return;
    final handled = await openInCustomTabs(
      context,
      url: url.toString(),
      useMiuix: true,
    );
    if (handled) return;
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) showMiuixToast(context, l10n.webUiFailed, error: true);
    }
  }

  void _copy() {
    final l10n = AppLocalizations.of(context);
    final url = widget.controller.webUi.url;
    if (url == null) return;
    Clipboard.setData(ClipboardData(text: url.toString()));
    showMiuixToast(context, l10n.copied);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final config = widget.controller.config;

    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, widget.controller.webUi.state]),
      builder: (context, _) => Material(
        type: MaterialType.transparency,
        child: MiuixScaffold(
          containerColor: colors.surface,
          topBar: MiuixBlurTopBar(
            scrollBehavior: _behavior,
            title: l10n.webUiTitle,
            navigationIcon: MiuixIconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const MiuixAppIcon(
                AppIconNames.back,
                fallback: Icons.arrow_back,
              ),
            ),
            actions: [
              MiuixIconButton(
                onPressed: () {
                  final url = widget.controller.webUi.url;
                  if (url == null) return;
                  pushStyledPage(
                    context,
                    material: BrowserPage(initialUrl: url.toString()),
                    miuix: MiuixBrowserPage(initialUrl: url.toString()),
                  );
                },
                child: const MiuixAppIcon(
                  'public',
                  fallback: Icons.public,
                ),
              ),
            ],
          ),
          content: (padding) => MiuixScrollBehaviorListener(
            behavior: _behavior,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(16, padding.top + 4, 16, 120),
              children: [
                MiuixDismissibleInfoCard(id: 'intro.webui', text: l10n.webUiDesc),
                const SizedBox(height: 8),
                MiuixDismissibleInfoCard(
                  id: 'intro.webui.note',
                  text: l10n.webUiNote,
                ),
                const SizedBox(height: 12),
                MiuixGroupCard(
                  insideMargin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      MiuixSwitchPreference(
                        title: l10n.webUiEnable,
                        summary: l10n.webUiToggleHint,
                        startAction: const Icon(Icons.language),
                        value: config.webUiEnabled,
                        onChanged: (v) => widget.controller.setWebUiEnabled(v),
                      ),
                      MiuixOverlayDropdownPreference(
                        title: l10n.webUiHost,
                        items: [l10n.loopbackOnly, l10n.allInterfaces],
                        selectedIndex: config.webUiHost == '0.0.0.0' ? 1 : 0,
                        startAction: const Icon(Icons.lan_outlined),
                        onSelectedIndexChange: (i) {
                          config.webUiHost = i == 1 ? '0.0.0.0' : '127.0.0.1';
                          widget.controller.store.update(config);
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: MiuixTextField(
                          controller: _portCtrl,
                          label: l10n.webUiPort,
                          singleLine: true,
                          keyboardType: TextInputType.number,
                          onChanged: (s) {
                            final port = int.tryParse(s.trim());
                            if (port == null || port < 1024 || port > 65535) {
                              return;
                            }
                            if (port == _lastWrittenPort) return;
                            _lastWrittenPort = port;
                            config.webUiPort = port;
                            widget.controller.store.update(config);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                MiuixGroupCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MiuixText(_statusLabel(l10n), fontSize: 15),
                      const SizedBox(height: 8),
                      ValueListenableBuilder<WebUiState>(
                        valueListenable: widget.controller.webUi.state,
                        builder: (context, _, _) {
                          final url = widget.controller.webUi.url;
                          if (url == null) return const SizedBox.shrink();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              MiuixText(
                                url.toString(),
                                fontSize: 13,
                                color: colors.onSurfaceVariantSummary,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: MiuixButton(
                                      onPressed: _open,
                                      child: MiuixText(l10n.webUiOpen),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: MiuixButton(
                                      onPressed: _copy,
                                      child: MiuixText(l10n.webUiCopyUrl),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _statusLabel(AppLocalizations l10n) =>
      switch (widget.controller.webUi.state.value) {
        WebUiState.running => l10n.webUiRunning,
        WebUiState.starting => l10n.serverStarting,
        WebUiState.error => l10n.webUiFailed,
        WebUiState.stopped => l10n.webUiStopped,
      };
}
