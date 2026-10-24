import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/ui/ip_rules_page.dart';
import 'package:local2api/ui/network_page.dart';
import 'package:local2api/ui/webui_page.dart';
import 'package:local2api/widgets/frosted_page_bar.dart';
import 'package:local2api/widgets/native_text_context_menu.dart';

import 'widgets/common.dart' show SectionCard, pushPage;

/// 网络设置页（Material 版二级页，自 `SettingsPage` 拆出，对应 miuix 版
/// `MiuixNetworkSettingsPage`）。
///
/// 收纳三类「服务对外暴露」相关的配置：
/// - 网络与访问：监听地址 / 端口 / 自启 / CORS + 网络管理页入口（隧道）；
/// - 临时 WebUI：独立端口的网页控制台；
/// - IP 访问规则：独立成页（密钥页同款交互，见 [IpRulesPage]）。
class NetworkSettingsPage extends StatelessWidget {
  const NetworkSettingsPage({super.key, required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final config = controller.config;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final ruleCount = controller.config.cidrRules.length;
        return FrostedBarPage(
          title: l10n.networkSettingsTitle,
          child: ListView(
            padding: EdgeInsets.only(
              top: frostedPageBarInset(context) + 8,
              bottom: 32,
            ),
            children: [
              // ── 网络与访问 ──
              SectionCard(
                title: l10n.networkSection,
                child: Column(
                  children: [
                    // 网络管理页：Cloudflare Tunnel / Tailscale 两条访问通道。
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.lan_outlined),
                      title: Text(l10n.networkTitle),
                      subtitle: Text(l10n.networkEntryDesc),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          pushPage(context, NetworkPage(controller: controller)),
                    ),
                    const Divider(),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            initialValue: config.listenHost,
                            decoration: InputDecoration(
                              labelText: l10n.listenAddress,
                            ),
                            items: [
                              DropdownMenuItem(
                                value: '0.0.0.0',
                                child: Text(l10n.allInterfaces),
                              ),
                              DropdownMenuItem(
                                value: '127.0.0.1',
                                child: Text(l10n.loopbackOnly),
                              ),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              config.listenHost = v;
                              controller.store.update(config);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            // Windows 上右键弹原生编辑菜单
                            contextMenuBuilder: textContextMenuBuilder,
                            initialValue: '${config.listenPort}',
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: l10n.listenPort,
                            ),
                            onChanged: (s) {
                              final port = int.tryParse(s.trim());
                              if (port == null ||
                                  port < 1024 ||
                                  port > 65535) {
                                return;
                              }
                              config.listenPort = port;
                              controller.store.update(config);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.autoStartToggle),
                      value: config.autoStart,
                      onChanged: (v) {
                        config.autoStart = v;
                        controller.store.update(config);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.corsToggle),
                      subtitle: Text(l10n.corsDesc),
                      value: config.corsEnabled,
                      onChanged: (v) {
                        config.corsEnabled = v;
                        controller.store.update(config);
                      },
                    ),
                  ],
                ),
              ),
              // ── 临时 WebUI ──
              SectionCard(
                title: l10n.webUiTitle,
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.language),
                      title: Text(l10n.webUiTitle),
                      subtitle: Text(l10n.webUiEntryDesc),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          pushPage(context, WebUiPage(controller: controller)),
                    ),
                    const Divider(),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.webUiEnable),
                      subtitle: Text(l10n.webUiToggleHint),
                      value: controller.config.webUiEnabled,
                      onChanged: (v) => controller.setWebUiEnabled(v),
                    ),
                  ],
                ),
              ),
              // ── IP 访问规则（独立页） ──
              SectionCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.security_outlined),
                  title: Text(l10n.accessRules),
                  subtitle: Text(
                    ruleCount == 0
                        ? l10n.ipRulesEmpty
                        : l10n.ipRulesCount('$ruleCount'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      pushPage(context, IpRulesPage(controller: controller)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
