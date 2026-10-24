import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart'
    hide MiuixTextField, MiuixTextFieldColors;

import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/call_settings.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';

/// 通话设置页（miuix 版，从通话页的齿轮进入）。
///
/// 两个能力开关（改动即落盘，无需保存按钮）：
/// - 允许打断：模型说话时可以随时插话；
/// - 允许调用摄像头：视频通话把画面发送给模型。
///
/// 两项都需要 **Omni 全模态**模型 —— [omni] 为 false 时整体置灰，
/// 并在顶部说明「基础语音通话不受影响」。基础通话（说话→转文字→
/// 模型回复→朗读）任何模型都能用，不受这里的开关影响。
class MiuixCallSettingsPage extends StatefulWidget {
  const MiuixCallSettingsPage({super.key, required this.omni});

  /// 当前通话的对端模型是不是 Omni（决定开关的可点性）。
  final bool omni;

  @override
  State<MiuixCallSettingsPage> createState() => _MiuixCallSettingsPageState();
}

class _MiuixCallSettingsPageState extends State<MiuixCallSettingsPage> {
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();

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
  void dispose() {
    _behavior.state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;

    return Material(
      type: MaterialType.transparency,
      child: MiuixScaffold(
        containerColor: colors.surface,
        topBar: MiuixBlurTopBar(
          title: l10n.callSettingsTitle,
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
              if (!widget.omni) ...[
                // 非 Omni：说明基础通话不受影响，别让用户以为「没用了」。
                MiuixGroupCard(
                  insideMargin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: MiuixText(
                    l10n.callSettingsOmniHint,
                    fontSize: 13,
                    color: colors.onSurfaceVariantSummary,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              MiuixGroupCard(
                insideMargin: EdgeInsets.zero,
                child: Column(
                  children: [
                    MiuixSwitchPreference(
                      title: l10n.callAllowInterrupt,
                      summary: l10n.callAllowInterruptDesc,
                      value: _allowInterrupt,
                      enabled: widget.omni && _loaded,
                      onChanged: (v) {
                        setState(() => _allowInterrupt = v);
                        CallPrefs.saveAllowInterrupt(v).ignore();
                      },
                    ),
                    MiuixSwitchPreference(
                      title: l10n.callAllowCamera,
                      summary: l10n.callAllowCameraDesc,
                      value: _allowCamera,
                      enabled: widget.omni && _loaded,
                      onChanged: (v) {
                        setState(() => _allowCamera = v);
                        CallPrefs.saveAllowCamera(v).ignore();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
