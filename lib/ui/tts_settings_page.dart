import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/ui/tts_section.dart';
import 'package:local2api/widgets/frosted_page_bar.dart';

/// TTS 设置页（Material 版二级页，自 `ChatSettingsPage` 拆出，对应 miuix 版
/// `MiuixTtsSettingsPage`）。
///
/// 对话设置里只留一行入口，本地 TTS 的全部内容（模型下载 / 一键建上游 /
/// 推理后端 / 服务商与音色路线 / 试听 / 调试台）都收在这页。
class TtsSettingsPage extends StatelessWidget {
  const TtsSettingsPage({super.key, required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FrostedBarPage(
      title: l10n.ttsSettingsTitle,
      child: ListView(
        padding: EdgeInsets.only(
          top: frostedPageBarInset(context) + 8,
          bottom: 32,
        ),
        children: [TtsSection(controller: controller)],
      ),
    );
  }
}
