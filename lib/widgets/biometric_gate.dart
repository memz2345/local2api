import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';

/// 生物识别锁的门禁页（Hail 同款应用锁）。
///
/// 锁定期间整棵 MaterialApp 的内容都换成这一页 —— 底下**不渲染任何
/// 业务界面**，最近任务的应用截图看到的也是锁屏。出现时自动弹一次系统
/// 验证（由宿主 [_runAuth] 发起）；取消 / 失败停在这页，手动点「解锁」
/// 重试 —— 不做失败自动重弹，免得跟系统验证框互相触发（尤其回落到
/// PIN / 图案这种独立页面时，Resume 事件会绕回来）。
class BiometricGate extends StatefulWidget {
  const BiometricGate({super.key, required this.onRetry});

  /// 发起一次系统验证；通过后宿主会把锁定状态翻过来。
  final Future<void> Function() onRetry;

  @override
  State<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends State<BiometricGate> {
  @override
  void initState() {
    super.initState();
    // 首帧后自动弹验证（弹太早会被转场/主题构建吞掉系统窗口）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onRetry();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 56, color: cs.primary),
              const SizedBox(height: 20),
              Text(
                l10n.biometricGateTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.biometricGateHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: widget.onRetry,
                icon: const Icon(Icons.fingerprint),
                label: Text(l10n.biometricUnlock),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
