import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField;
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/ui/miuix/miuix_ip_rules_page.dart';
import 'package:local2api/ui/miuix/miuix_network_page.dart';
import 'package:local2api/ui/miuix/miuix_webui_page.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';
import 'package:local2api/widgets/miuix/miuix_text_field.dart';

/// 网络设置页（miuix 版二级页，自 `MiuixSettingsPage` 拆出）。
///
/// 收纳三类「服务对外暴露」相关的配置：
/// - 网络与访问：监听地址 / 端口 / 自启 / CORS + 网络管理页入口（隧道）；
/// - 临时 WebUI：独立端口的网页控制台；
/// - IP 访问规则：独立成页（密钥页同款交互，见 [MiuixIpRulesPage]）。
class MiuixNetworkSettingsPage extends StatefulWidget {
  const MiuixNetworkSettingsPage({super.key, required this.controller});

  final ServerController controller;

  @override
  State<MiuixNetworkSettingsPage> createState() =>
      _MiuixNetworkSettingsPageState();
}

class _MiuixNetworkSettingsPageState extends State<MiuixNetworkSettingsPage> {
  /// 二级页统一的可折叠大标题行为。
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();

  /// 端口输入：首次构建取当前端口，之后由用户输入驱动。
  late final TextEditingController _portCtrl = TextEditingController(
    text: '${widget.controller.config.listenPort}',
  );
  int _lastWrittenPort = -1;

  @override
  void initState() {
    super.initState();
    _lastWrittenPort = widget.controller.config.listenPort;
  }

  @override
  void dispose() {
    _behavior.state.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final controller = widget.controller;
    final config = controller.config;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final ruleCount = config.cidrRules.length;
        return Material(
          type: MaterialType.transparency,
          child: MiuixScaffold(
            containerColor: colors.surface,
            topBar: MiuixBlurTopBar(
              title: l10n.networkSettingsTitle,
              scrollBehavior: _behavior,
              navigationIcon: MiuixIconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const MiuixAppIcon(
                  AppIconNames.back,
                  fallback: Icons.arrow_back,
                ),
              ),
            ),
            content: (padding) => MiuixScrollBehaviorListener(
              behavior: _behavior,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(16, padding.top + 8, 16, 40),
                children: [
                  // ── 网络与访问 ──
                  MiuixGroupCard(
                    insideMargin: EdgeInsets.zero,
                    child: MiuixArrowPreference(
                      title: l10n.networkTitle,
                      summary: l10n.networkEntryDesc,
                      startAction: const Icon(Icons.lan_outlined),
                      onClick: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => MiuixNetworkPage(controller: controller),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  MiuixGroupCard(
                    insideMargin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        MiuixOverlayDropdownPreference(
                          title: l10n.listenAddress,
                          items: [l10n.allInterfaces, l10n.loopbackOnly],
                          selectedIndex: config.listenHost == '0.0.0.0' ? 0 : 1,
                          startAction: const Icon(Icons.lan_outlined),
                          onSelectedIndexChange: (i) {
                            config.listenHost = i == 0 ? '0.0.0.0' : '127.0.0.1';
                            controller.store.update(config);
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          child: MiuixTextField(
                            controller: _portCtrl,
                            label: l10n.listenPort,
                            singleLine: true,
                            keyboardType: TextInputType.number,
                            onChanged: (s) {
                              final port = int.tryParse(s.trim());
                              if (port == null ||
                                  port < 1024 ||
                                  port > 65535) {
                                return;
                              }
                              if (port == _lastWrittenPort) return;
                              _lastWrittenPort = port;
                              config.listenPort = port;
                              controller.store.update(config);
                            },
                          ),
                        ),
                        MiuixSwitchPreference(
                          title: l10n.autoStartToggle,
                          startAction: const Icon(Icons.power_outlined),
                          value: config.autoStart,
                          onChanged: (v) {
                            config.autoStart = v;
                            controller.store.update(config);
                          },
                        ),
                        MiuixSwitchPreference(
                          title: l10n.corsToggle,
                          summary: l10n.corsDesc,
                          startAction: const Icon(Icons.web_outlined),
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
                  const SizedBox(height: 20),
                  MiuixGroupCard(
                    insideMargin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        MiuixArrowPreference(
                          title: l10n.webUiTitle,
                          summary: l10n.webUiEntryDesc,
                          startAction: const Icon(Icons.language),
                          onClick: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  MiuixWebUiPage(controller: controller),
                            ),
                          ),
                        ),
                        MiuixSwitchPreference(
                          title: l10n.webUiEnable,
                          summary: l10n.webUiToggleHint,
                          startAction: const Icon(Icons.language),
                          value: controller.config.webUiEnabled,
                          onChanged: (v) => controller.setWebUiEnabled(v),
                        ),
                      ],
                    ),
                  ),
                  // ── IP 访问规则（独立页） ──
                  const SizedBox(height: 20),
                  MiuixGroupCard(
                    insideMargin: EdgeInsets.zero,
                    child: MiuixArrowPreference(
                      title: l10n.accessRules,
                      summary: ruleCount == 0
                          ? l10n.ipRulesEmpty
                          : l10n.ipRulesCount('$ruleCount'),
                      startAction: const Icon(Icons.security_outlined),
                      onClick: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              MiuixIpRulesPage(controller: controller),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
