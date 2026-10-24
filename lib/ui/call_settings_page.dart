import 'package:flutter/material.dart';

import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/call_settings.dart';
import 'package:local2api/widgets/frosted_page_bar.dart';

/// 通话设置页（Material 版，从通话页的齿轮进入；对应 miuix 版
/// `MiuixCallSettingsPage`）。
///
/// 两个能力开关（改动即落盘，无需保存按钮）：
/// - 允许打断：模型说话时可以随时插话；
/// - 允许调用摄像头：视频通话把画面发送给模型。
///
/// 两项都需要 **Omni 全模态**模型 —— [omni] 为 false 时整体置灰，
/// 并在顶部说明「基础语音通话不受影响」。
class CallSettingsPage extends StatefulWidget {
  const CallSettingsPage({super.key, required this.omni});

  /// 当前通话的对端模型是不是 Omni（决定开关的可点性）。
  final bool omni;

  @override
  State<CallSettingsPage> createState() => _CallSettingsPageState();
}

class _CallSettingsPageState extends State<CallSettingsPage> {
  bool _allowInterrupt = true;
  bool _allowCamera = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final allowInterrupt = await CallPrefs.loadAllowInterrupt();
    final allowCamera = await CallPrefs.loadAllowCamera();
    if (!mounted) return;
    setState(() {
      _allowInterrupt = allowInterrupt;
      _allowCamera = allowCamera;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return FrostedBarPage(
      title: l10n.callSettingsTitle,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        padding: EdgeInsets.fromLTRB(
          16,
          frostedPageBarInset(context) + 8,
          16,
          40,
        ),
        children: [
          if (!widget.omni) ...[
            // 非 Omni：说明基础通话不受影响，别让用户以为「没用了」。
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Text(
                  l10n.callSettingsOmniHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.6,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(l10n.callAllowInterrupt),
                  subtitle: Text(l10n.callAllowInterruptDesc),
                  value: _allowInterrupt,
                  onChanged: widget.omni && _loaded
                      ? (v) {
                          setState(() => _allowInterrupt = v);
                          CallPrefs.saveAllowInterrupt(v).ignore();
                        }
                      : null,
                ),
                SwitchListTile(
                  title: Text(l10n.callAllowCamera),
                  subtitle: Text(l10n.callAllowCameraDesc),
                  value: _allowCamera,
                  onChanged: widget.omni && _loaded
                      ? (v) {
                          setState(() => _allowCamera = v);
                          CallPrefs.saveAllowCamera(v).ignore();
                        }
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
