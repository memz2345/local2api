import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/tts/tts_settings.dart';
import 'package:local2api/ui/character_card_page.dart';
import 'package:local2api/ui/tts_settings_page.dart';
import 'package:local2api/widgets/frosted_page_bar.dart';

import 'widgets/common.dart' show SectionCard, pushPage;

/// 对话设置页（Material 版二级页，自 `SettingsPage` 拆出，对应 miuix 版
/// `MiuixChatSettingsPage`）。
///
/// 收纳「对话/语音」相关的功能配置：
/// - TTS 设置：本地模型、服务商与试听都在那一页（[TtsSettingsPage]）；
/// - 自动播放 TTS：回复落地即朗读，不用点喇叭；
/// - 角色卡：对话模拟的人设场景管理。
class ChatSettingsPage extends StatefulWidget {
  const ChatSettingsPage({super.key, required this.controller});

  final ServerController controller;

  @override
  State<ChatSettingsPage> createState() => _ChatSettingsPageState();
}

class _ChatSettingsPageState extends State<ChatSettingsPage> {
  @override
  void initState() {
    super.initState();
    // 「自动播放」这行读的是 TtsSettings。它不像配置那样在启动时加载，
    // 冷启动直接进这页时不 load 一下会永远显示默认值（关）。
    unawaited(TtsSettings.instance.load());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FrostedBarPage(
      title: l10n.chatSettingsTitle,
      child: ListView(
        padding: EdgeInsets.only(
          top: frostedPageBarInset(context) + 8,
          bottom: 32,
        ),
        children: [
          SectionCard(
            child: Column(
              children: [
                // TTS 的所有配置都搬进独立页了，这里只留入口
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.record_voice_over_outlined),
                  title: Text(l10n.ttsSettingsTitle),
                  subtitle: Text(l10n.ttsSettingsDesc),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => pushPage(
                    context,
                    TtsSettingsPage(controller: widget.controller),
                  ),
                ),
                const Divider(),
                // 自动播放：开关状态是 TtsSettings 的本地偏好，不是 ProxyConfig
                AnimatedBuilder(
                  animation: TtsSettings.instance,
                  builder: (context, _) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.play_circle_outline),
                    title: Text(l10n.ttsAutoPlayTitle),
                    value: TtsSettings.instance.autoPlay,
                    onChanged: TtsSettings.instance.setAutoPlay,
                  ),
                ),
              ],
            ),
          ),
          // 角色卡：对话模拟的人设场景（从对话模拟页搬一份常驻入口）
          SectionCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(l10n.characterTitle),
              subtitle: Text(l10n.characterEntryDesc),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => pushPage(context, const CharacterCardPage()),
            ),
          ),
        ],
      ),
    );
  }
}
