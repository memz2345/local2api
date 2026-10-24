import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/webui_server.dart';
import 'package:local2api/widgets/app_toast.dart';
import 'package:local2api/widgets/custom_tabs_picker.dart';
import 'package:local2api/widgets/expressive_app_bar.dart';
import 'package:local2api/widgets/frosted_page_bar.dart';
import 'package:url_launcher/url_launcher.dart';

import 'browser_page.dart';
import 'miuix/miuix_browser_page.dart';
import 'widgets/common.dart' show CopyableRow, pushStyledPage;

/// 临时 WebUI 设置页（Material 版）。
///
/// 它管的是**另一个端口**上的网页控制台：开关、监听地址、端口、当前地址。
/// 与 API 转发端口完全独立 —— 转发口是客户端里写死的地址，不该被调试页面挤占，
/// 所以这里起的停的都只是旁路，主服务的状态不受影响。
class WebUiPage extends StatelessWidget {
  const WebUiPage({super.key, required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final config = controller.config;
    return AnimatedBuilder(
      animation: Listenable.merge([controller, controller.webUi.state]),
      builder: (ctx, _) => FrostedBarPage(
        title: l10n.webUiTitle,
        actions: [
          MorphIconButton(
            icon: Icons.public,
            tooltip: l10n.browserTitle,
            transparent: true,
            onTap: () {
              final url = controller.webUi.url;
              if (url == null) return;
              pushStyledPage(
                ctx,
                material: BrowserPage(initialUrl: url.toString()),
                miuix: MiuixBrowserPage(initialUrl: url.toString()),
              );
            },
          ),
          MorphIconButton(
            icon: Icons.open_in_browser,
            tooltip: l10n.webUiOpen,
            transparent: true,
            onTap: () => _open(ctx, controller),
          ),
        ],
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          padding: EdgeInsets.fromLTRB(
            16,
            frostedPageBarInset(context) + 8,
            16,
            120,
          ),
          children: [
            Text(
              l10n.webUiDesc,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.webUiNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.webUiEnable),
              subtitle: Text(l10n.webUiToggleHint),
              value: config.webUiEnabled,
              onChanged: (v) => controller.setWebUiEnabled(v),
            ),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    initialValue: config.webUiHost,
                    decoration: InputDecoration(labelText: l10n.webUiHost),
                    items: [
                      DropdownMenuItem(
                        value: '127.0.0.1',
                        child: Text(l10n.loopbackOnly),
                      ),
                      DropdownMenuItem(
                        value: '0.0.0.0',
                        child: Text(l10n.allInterfaces),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      config.webUiHost = v;
                      controller.store.update(config);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    initialValue: '${config.webUiPort}',
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: l10n.webUiPort),
                    onChanged: (s) {
                      final port = int.tryParse(s.trim());
                      if (port == null || port < 1024 || port > 65535) return;
                      config.webUiPort = port;
                      controller.store.update(config);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _StatusRow(controller: controller),
            const SizedBox(height: 8),
            ValueListenableBuilder<WebUiState>(
              valueListenable: controller.webUi.state,
              builder: (context, _, _) {
                final url = controller.webUi.url;
                if (url == null) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CopyableRow(value: url.toString(), icon: Icons.language),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: () => _open(context, controller),
                      icon: const Icon(Icons.open_in_browser),
                      label: Text(l10n.webUiOpen),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 交给外部浏览器：WebUI 是本机另一个端口上的普通网页，
  /// 不值得为此内嵌一个 WebView。装了 Chromium 系浏览器就走 Custom Tabs。
  Future<void> _open(BuildContext context, ServerController controller) async {
    final url = controller.webUi.url;
    if (url == null) return;
    final handled = await openInCustomTabs(
      context,
      url: url.toString(),
      useMiuix: false,
    );
    if (handled) return;
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        showAppToast(context, AppLocalizations.of(context).webUiFailed);
      }
    }
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ValueListenableBuilder<WebUiState>(
      valueListenable: controller.webUi.state,
      builder: (context, state, _) {
        final (label, color) = switch (state) {
          WebUiState.running => (l10n.webUiRunning, cs.primary),
          WebUiState.starting => (l10n.serverStarting, cs.secondary),
          WebUiState.error => (l10n.webUiFailed, cs.error),
          WebUiState.stopped => (l10n.webUiStopped, cs.onSurfaceVariant),
        };
        return Row(
          children: [
            Icon(Icons.language, size: 18, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ],
        );
      },
    );
  }
}
