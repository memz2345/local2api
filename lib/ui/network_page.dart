import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/cloudflared_tunnel.dart';
import 'package:local2api/services/network_utils.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/tailscale_service.dart';
import 'package:local2api/widgets/app_toast.dart';
import 'package:local2api/widgets/frosted_page_bar.dart';
import 'package:local2api/widgets/predictive_back_sheet.dart';
import 'package:url_launcher/url_launcher.dart';

import 'widgets/common.dart' show CopyableRow;

/// 网络管理页：本服务对外的两条「通道」。
///
/// - **Cloudflare Tunnel（trycloudflare）**：内建一条临时隧道把本服务公开到
///   互联网。启用前要拉取并同意 Cloudflare 的服务条款（trycloudflare 受其
///   约束），同意记录随配置落盘，之后不再重复弹。隧道本体是 cloudflared
///   子进程（内建隧道目前只在桌面端现实可用，Android 的 W^X 限制不允许
///   执行应用目录里的二进制，找不到 cloudflared 时给出明确提示）。
/// - **Tailscale**：只是「放行 100.64.0.0/10 网段」的开关（往 CIDR 规则里
///   加/摘一条 allow 规则）+ 探测本机的 Tailscale IP + 一张打开下载页的
///   卡片（Tailscale 得用户自己装，应用不代跑）。
class NetworkPage extends StatefulWidget {
  const NetworkPage({super.key, required this.controller});

  final ServerController controller;

  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  String? _tailscaleIp;

  /// Tailscale 装没装：装了那张卡片就改成「打开」，没装才是下载页。
  bool _tailscaleInstalled = false;

  @override
  void initState() {
    super.initState();
    CloudflaredTunnelService.detectTailscaleIpV4().then((ip) {
      if (mounted) setState(() => _tailscaleIp = ip);
    });
    TailscaleService.instance.isInstalled().then((installed) {
      if (mounted) setState(() => _tailscaleInstalled = installed);
    });
  }

  ProxyConfig get _config => widget.controller.config;

  bool get _tsAllowed => _config.cidrRules.any(
    (r) => r.cidr == _kTailscaleCidr && r.allow && r.enabled,
  );

  static const String _kTailscaleCidr = '100.64.0.0/10';

  /// CF 开关。关 = 停隧道；开 = 先过条款同意关，再起隧道。
  Future<void> _toggleCf(bool want) async {
    final config = _config;
    if (!want) {
      config.cloudflaredEnabled = false;
      widget.controller.store.update(config);
      await widget.controller.tunnel.stop();
      return;
    }
    if (config.cloudflaredAgreedMs == 0) {
      final agreed = await _agreeTerms();
      if (!agreed || !mounted) return;
      config.cloudflaredAgreedMs = DateTime.now().millisecondsSinceEpoch;
    }
    config.cloudflaredEnabled = true;
    widget.controller.store.update(config);
    await widget.controller.tunnel.start(config.listenPort);
  }

  /// 条款确认：**先弹窗**，弹窗内部再拉条款 —— 加载动画 → 全文；
  /// 拉取失败在弹窗里给「重试」，不用关掉重来。
  Future<bool> _agreeTerms() async {
    final agreed = await showAppBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CloudflareTermsSheet(),
    );
    return agreed == true;
  }

  Future<void> _toggleTailscale(bool want) async {
    final config = _config;
    if (want) {
      // 插到最前：CIDR 规则先命中先生效，放行规则被后面的自定义拒绝规则
      // 压住就失去意义了。
      config.cidrRules.insert(
        0,
        CidrRule(id: NetworkUtils.newId(), cidr: _kTailscaleCidr, allow: true),
      );
    } else {
      config.cidrRules.removeWhere((r) => r.cidr == _kTailscaleCidr);
    }
    widget.controller.store.update(config);
  }

  /// 打开 Tailscale：装了就起客户端，没装（或起不来）就回退下载页。
  Future<void> _openTailscale() async {
    final ok = await TailscaleService.instance.open();
    if (ok || !mounted) return;
    showAppToast(
      context,
      AppLocalizations.of(context).tsOpenFailed,
      error: true,
    );
  }

  /// 打开下载页（Tailscale 官方安装说明）。
  ///
  /// 卡片本体走 `_openTailscale`（装了就起客户端）；这里另给一个「下载页」
  /// 入口 —— 已装时想重装/升级也用得上。
  Future<void> _openTailscaleDownload() async {
    final uri = Uri.parse('https://tailscale.com/download');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        showAppToast(
          context,
          AppLocalizations.of(context).cfTermsFetchFailed,
          error: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tunnel = widget.controller.tunnel;

    return FrostedBarPage(
      title: l10n.networkTitle,
      child: AnimatedBuilder(
        animation: Listenable.merge([tunnel, widget.controller]),
        builder: (context, _) => ListView(
          padding: EdgeInsets.only(
            top: frostedPageBarInset(context) + 8,
            bottom: 32,
          ),
          children: [
            // ---- Cloudflare Tunnel ----
            _Section(
              title: l10n.cfTitle,
              desc: l10n.cfDesc,
              switchValue: _config.cloudflaredEnabled,
              onChanged: _toggleCf,
              switchLabel: l10n.cfEnableSwitch,
              status: switch (tunnel.state) {
                CloudflaredState.running => (
                  label: l10n.cfRunning,
                  error: false,
                ),
                CloudflaredState.starting => (
                  label: l10n.cfStarting,
                  error: false,
                ),
                CloudflaredState.error => (
                  label: (tunnel.error ?? '').contains('not found')
                      ? l10n.cfBinaryMissing
                      : (tunnel.error ?? ''),
                  error: true,
                ),
                _ => (label: l10n.cfStopped, error: false),
              },
              child: AnimatedBuilder(
                animation: tunnel,
                builder: (context, _) {
                  if (tunnel.url == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: CopyableRow(value: tunnel.url!, icon: Icons.public),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            // ---- Tailscale ----
            _Section(
              title: l10n.tsTitle,
              desc: l10n.tsDesc,
              switchValue: _tsAllowed,
              onChanged: _toggleTailscale,
              switchLabel: l10n.tsAllowSwitch,
              status: _tailscaleIp == null
                  ? (label: l10n.tsNotDetected, error: false)
                  : (label: l10n.tsDetected(_tailscaleIp!), error: false),
              child: _tailscaleIp == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: CopyableRow(
                        value: 'http://$_tailscaleIp:${_config.listenPort}',
                        icon: Icons.vpn_key_outlined,
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            // ---- Tailscale 客户端卡片 ----
            // 装了就是「打开客户端」，没装才是下载页。
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  onTap: _openTailscale,
                  title: Text(
                    _tailscaleInstalled ? l10n.tsOpenApp : l10n.tsDownloadTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    _tailscaleInstalled
                        ? l10n.tsInstalledDesc
                        : l10n.tsDownloadDesc,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _tailscaleInstalled ? Icons.open_in_new : Icons.link,
                        color: cs.primary,
                      ),
                      // 已装时卡片本体是「打开客户端」，下载页退到这个图标上。
                      IconButton(
                        tooltip: l10n.tsDownloadTitle,
                        icon: const Icon(Icons.download_outlined, size: 20),
                        onPressed: _openTailscaleDownload,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cloudflare 条款确认弹窗（Material 版）。
///
/// 打开即弹，条款在弹窗**内部**加载：加载动画 → 全文；失败给「重试」，
/// 不用关掉重开。「同意并启用」在全文就绪前置灰 —— 不允许对没见过的
/// 条款点头。
class _CloudflareTermsSheet extends StatefulWidget {
  const _CloudflareTermsSheet();

  @override
  State<_CloudflareTermsSheet> createState() => _CloudflareTermsSheetState();
}

class _CloudflareTermsSheetState extends State<_CloudflareTermsSheet> {
  String? _text;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final text = await CloudflaredTunnelService.fetchCloudflareTermsText();
      if (!mounted) return;
      setState(() {
        _text = text.trim().isEmpty ? null : text;
        _loading = false;
        _failed = _text == null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.cfTermsTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.cfTermsNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            // 正文区：三态（加载 / 失败重试 / 全文），高度稳定不跳。
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 380),
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: const BorderRadius.all(Radius.circular(14)),
                ),
                padding: const EdgeInsets.all(14),
                child: _loading
                    ? const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      )
                    : _failed
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            l10n.cfTermsFetchFailed,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: Text(l10n.cfRetry),
                          ),
                        ],
                      )
                    : SingleChildScrollView(
                        child: Text(
                          _text!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.4,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(l10n.cfTermsDecline),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  // 全文就绪前不允许同意 —— 不能对没见过的条款点头。
                  onPressed: _text == null
                      ? null
                      : () => Navigator.of(context).pop(true),
                  child: Text(l10n.cfTermsAgree),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 一个通道的卡片：标题 + 说明 + 开关 + 状态行 + 附加内容（地址行等）。
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.desc,
    required this.switchValue,
    required this.onChanged,
    required this.switchLabel,
    required this.status,
    this.child,
  });

  final String title;
  final String desc;
  final bool switchValue;
  final ValueChanged<bool> onChanged;
  final String switchLabel;
  final ({String label, bool error}) status;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Switch(value: switchValue, onChanged: onChanged),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              desc,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    status.label,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: status.error
                          ? theme.colorScheme.error
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            ?child,
          ],
        ),
      ),
    );
  }
}
