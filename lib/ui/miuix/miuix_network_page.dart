import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/cloudflared_tunnel.dart';
import 'package:local2api/services/network_utils.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/tailscale_service.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/widgets/miuix/miuix_dialog.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';
import 'package:url_launcher/url_launcher.dart';

/// 网络管理页（miuix 版，对应 Material 版 `NetworkPage`）。
///
/// CF（trycloudflare）：开关 + 条款同意流 + 隧道状态 / 公开地址；
/// Tailscale：放行网段的开关 + 探测到的 IP；下载页走参考图那种
/// 「标题 + 副标题 + 行尾链接图标」的卡片（MiuixBasicComponent）。
class MiuixNetworkPage extends StatefulWidget {
  const MiuixNetworkPage({super.key, required this.controller});

  final ServerController controller;

  @override
  State<MiuixNetworkPage> createState() => _MiuixNetworkPageState();
}

class _MiuixNetworkPageState extends State<MiuixNetworkPage> {
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();
  String? _tailscaleIp;

  /// Tailscale 装没装：装了那张卡片就改成「打开」，没装才是下载页。
  bool _tailscaleInstalled = false;

  static const String _kTailscaleCidr = '100.64.0.0/10';

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

  @override
  void dispose() {
    _behavior.state.dispose();
    super.dispose();
  }

  ProxyConfig get _config => widget.controller.config;

  bool get _tsAllowed => _config.cidrRules.any(
    (r) => r.cidr == _kTailscaleCidr && r.allow && r.enabled,
  );

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
  /// 失败给「重试」。同意动作在全文就绪前置灰（MiuixDialogAction 不支持
  /// 禁用态，动作行用 MiuixDialogButton 自己拼）。
  Future<bool> _agreeTerms() async {
    final l10n = AppLocalizations.of(context);
    final agreed = await showMiuixDialog<bool>(
      context: context,
      title: l10n.cfTermsTitle,
      content: const _MiuixCloudflareTermsBody(),
    );
    return agreed == true;
  }

  Future<void> _toggleTailscale(bool want) async {
    final config = _config;
    if (want) {
      // 插到最前：CIDR 先命中先生效，放行规则被自定义拒绝压住就没意义了。
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
    showMiuixToast(
      context,
      AppLocalizations.of(context).tsOpenFailed,
      error: true,
    );
  }

  /// 打开下载页（Tailscale 官方安装说明）。
  Future<void> _openTailscaleDownload() async {
    final uri = Uri.parse('https://tailscale.com/download');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        showMiuixToast(
          context,
          AppLocalizations.of(context).cfTermsFetchFailed,
          error: true,
        );
      }
    }
  }

  void _copyUrl(String url) {
    final l10n = AppLocalizations.of(context);
    Clipboard.setData(ClipboardData(text: url));
    showMiuixToast(context, l10n.copied);
  }

  ({String label, bool error}) _cfStatus(AppLocalizations l10n) {
    final tunnel = widget.controller.tunnel;
    return switch (tunnel.state) {
      CloudflaredState.running => (label: l10n.cfRunning, error: false),
      CloudflaredState.starting => (label: l10n.cfStarting, error: false),
      CloudflaredState.error => (
        // 二进制缺失给本地化的说明；其余（超时 / 进程退出）原样展示日志细节。
        label: (tunnel.error ?? '').contains('not found')
            ? l10n.cfBinaryMissing
            : (tunnel.error ?? ''),
        error: true,
      ),
      _ => (label: l10n.cfStopped, error: false),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final tunnel = widget.controller.tunnel;

    return Material(
      type: MaterialType.transparency,
      child: MiuixScaffold(
        containerColor: colors.surface,
        topBar: MiuixBlurTopBar(
          scrollBehavior: _behavior,
          title: l10n.networkTitle,
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
          child: AnimatedBuilder(
            animation: Listenable.merge([tunnel, widget.controller]),
            builder: (context, _) => ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(16, padding.top + 8, 16, 24),
              children: [
                // ---- Cloudflare Tunnel ----
                MiuixGroupCard(
                  insideMargin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      MiuixSwitchPreference(
                        title: l10n.cfEnableSwitch,
                        summary: l10n.cfDesc,
                        value: _config.cloudflaredEnabled,
                        onChanged: _toggleCf,
                      ),
                      _StatusRow(
                        label: _cfStatus(l10n).label,
                        error: _cfStatus(l10n).error,
                      ),
                      if (tunnel.url != null)
                        MiuixBasicComponent(
                          title: l10n.cfPublicUrl,
                          summary: tunnel.url!,
                          onClick: () => _copyUrl(tunnel.url!),
                          endActions: [
                            MiuixAppIcon(
                              AppIconNames.copy,
                              fallback: Icons.copy_outlined,
                              size: 20,
                              color: colors.onSurfaceVariantActions,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // ---- Tailscale ----
                MiuixGroupCard(
                  insideMargin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      MiuixSwitchPreference(
                        title: l10n.tsTitle,
                        summary: l10n.tsDesc,
                        value: _tsAllowed,
                        onChanged: _toggleTailscale,
                      ),
                      _StatusRow(
                        label: _tailscaleIp == null
                            ? l10n.tsNotDetected
                            : l10n.tsDetected(_tailscaleIp!),
                        error: false,
                      ),
                      if (_tailscaleIp != null)
                        MiuixBasicComponent(
                          title: 'IP',
                          summary: 'http://$_tailscaleIp:${_config.listenPort}',
                          onClick: () => _copyUrl(
                            'http://$_tailscaleIp:${_config.listenPort}',
                          ),
                          endActions: [
                            MiuixAppIcon(
                              AppIconNames.copy,
                              fallback: Icons.copy_outlined,
                              size: 20,
                              color: colors.onSurfaceVariantActions,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // ---- Tailscale 客户端卡片 ----
                // 装了就是「打开客户端」，没装才是下载页。
                MiuixGroupCard(
                  insideMargin: EdgeInsets.zero,
                  child: MiuixBasicComponent(
                    title: _tailscaleInstalled
                        ? l10n.tsOpenApp
                        : l10n.tsDownloadTitle,
                    summary: _tailscaleInstalled
                        ? l10n.tsInstalledDesc
                        : l10n.tsDownloadDesc,
                    onClick: _openTailscale,
                    endActions: [
                      MiuixAppIcon(
                        AppIconNames.link,
                        fallback: _tailscaleInstalled
                            ? Icons.open_in_new
                            : Icons.link,
                        size: 24,
                        color: colors.primary,
                      ),
                      // 已装时卡片本体是「打开客户端」，下载页退到这个按钮上。
                      MiuixIconButton(
                        onPressed: _openTailscaleDownload,
                        child: MiuixAppIcon(
                          AppIconNames.download,
                          fallback: Icons.download_outlined,
                          size: 20,
                          color: colors.onSurfaceVariantActions,
                        ),
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
}

/// Cloudflare 条款确认弹窗内容（miuix 版）。
///
/// 打开即加载：加载动画 → 全文；失败给「重试」。动作行用
/// [MiuixDialogButton]（支持 null onPressed 的禁用态）——「同意并启用」
/// 在全文就绪前置灰。
class _MiuixCloudflareTermsBody extends StatefulWidget {
  const _MiuixCloudflareTermsBody();

  @override
  State<_MiuixCloudflareTermsBody> createState() =>
      _MiuixCloudflareTermsBodyState();
}

class _MiuixCloudflareTermsBodyState extends State<_MiuixCloudflareTermsBody> {
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
    final colors = MiuixTheme.of(context).colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MiuixText(
          l10n.cfTermsNote,
          fontSize: 12,
          color: colors.onSurfaceVariantSummary,
        ),
        const SizedBox(height: 10),
        // 正文区：三态（加载 / 失败重试 / 全文），高度稳定不跳。
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 340),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: _loading
                ? const Center(
                    child: MiuixCircularProgressIndicator(
                      size: 26,
                      strokeWidth: 2.5,
                    ),
                  )
                : _failed
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      MiuixText(
                        l10n.cfTermsFetchFailed,
                        fontSize: 12,
                        textAlign: TextAlign.center,
                        color: colors.onSurfaceVariantSummary,
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: MiuixDialogButton(
                          label: l10n.cfRetry,
                          onPressed: _load,
                        ),
                      ),
                    ],
                  )
                : SingleChildScrollView(
                    child: MiuixText(
                      _text!,
                      fontSize: 12,
                      color: colors.onSurface,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            MiuixDialogButton(
              label: l10n.cfTermsDecline,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            const SizedBox(width: 10),
            MiuixDialogButton(
              label: l10n.cfTermsAgree,
              primary: true,
              // 全文就绪前不允许同意 —— 不能对没见过的条款点头。
              onPressed: _text == null
                  ? null
                  : () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ],
    );
  }
}

/// 状态行：一句话（隧道状态 / 探测结果），不可点。
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.error});

  final String label;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: MiuixText(
        label,
        fontSize: 12,
        maxLines: 3,
        color: error ? colors.error : colors.onSurfaceVariantSummary,
      ),
    );
  }
}
