import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField;
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/ui/miuix/miuix_tts_section.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';

/// TTS 设置页（miuix 版二级页，自 `MiuixChatSettingsPage` 拆出，对应
/// Material 版 `TtsSettingsPage`）。
///
/// 对话设置里只留一行入口，本地 TTS 的全部内容（模型下载 / 一键建上游 /
/// 推理后端 / 服务商与音色路线 / 试听 / 调试台）都收在这页。
class MiuixTtsSettingsPage extends StatefulWidget {
  const MiuixTtsSettingsPage({super.key, required this.controller});

  final ServerController controller;

  @override
  State<MiuixTtsSettingsPage> createState() => _MiuixTtsSettingsPageState();
}

class _MiuixTtsSettingsPageState extends State<MiuixTtsSettingsPage> {
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();

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
          title: l10n.ttsSettingsTitle,
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
            children: [MiuixTtsSection(controller: widget.controller)],
          ),
        ),
      ),
    );
  }
}
