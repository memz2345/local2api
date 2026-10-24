import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField;
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/tts/tts_settings.dart';
import 'package:local2api/ui/miuix/miuix_character_card_page.dart';
import 'package:local2api/ui/miuix/miuix_tts_settings_page.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';

/// 对话设置页（miuix 版二级页，自 `MiuixSettingsPage` 拆出）。
///
/// 收纳「对话/语音」相关的功能配置：
/// - TTS 设置：本地模型、服务商与试听都在那一页（[MiuixTtsSettingsPage]）；
/// - 自动播放 TTS：回复落地即朗读，不用点喇叭；
/// - 角色卡：对话模拟的人设场景管理。
class MiuixChatSettingsPage extends StatefulWidget {
  const MiuixChatSettingsPage({super.key, required this.controller});

  final ServerController controller;

  @override
  State<MiuixChatSettingsPage> createState() => _MiuixChatSettingsPageState();
}

class _MiuixChatSettingsPageState extends State<MiuixChatSettingsPage> {
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();

  @override
  void initState() {
    super.initState();
    // 「自动播放」这行读的是 TtsSettings。它不像配置那样在启动时加载，
    // 冷启动直接进这页时不 load 一下会永远显示默认值（关）。
    unawaited(TtsSettings.instance.load());
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
          title: l10n.chatSettingsTitle,
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
              MiuixGroupCard(
                insideMargin: EdgeInsets.zero,
                child: Column(
                  children: [
                    // TTS 的所有配置都搬进独立页了，这里只留入口
                    MiuixArrowPreference(
                      title: l10n.ttsSettingsTitle,
                      summary: l10n.ttsSettingsDesc,
                      startAction: const MiuixAppIcon(
                        'voice',
                        fallback: Icons.record_voice_over_outlined,
                      ),
                      onClick: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              MiuixTtsSettingsPage(controller: widget.controller),
                        ),
                      ),
                    ),
                    const MiuixHorizontalDivider(),
                    // 自动播放：开关状态是 TtsSettings 的本地偏好，不是 ProxyConfig
                    AnimatedBuilder(
                      animation: TtsSettings.instance,
                      builder: (context, _) => MiuixSwitchPreference(
                        title: l10n.ttsAutoPlayTitle,
                        startAction: const MiuixAppIcon(
                          'play',
                          fallback: Icons.play_circle_outline,
                        ),
                        value: TtsSettings.instance.autoPlay,
                        onChanged: TtsSettings.instance.setAutoPlay,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // 角色卡：对话模拟的人设场景（从对话模拟页搬一份常驻入口）
              MiuixGroupCard(
                insideMargin: EdgeInsets.zero,
                child: MiuixArrowPreference(
                  title: l10n.characterTitle,
                  summary: l10n.characterEntryDesc,
                  startAction: const MiuixAppIcon(
                    'person',
                    fallback: Icons.person_outline,
                  ),
                  onClick: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MiuixCharacterCardPage(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
