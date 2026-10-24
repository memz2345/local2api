import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField;
import 'package:local2api/widgets/miuix/miuix_text_field.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_bottom_sheet.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/network_utils.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';

import 'miuix_keys_page.dart';

/// 仪表盘的「API 密钥」分区（miuix 版，对应 `keySections`）—— 只留一张
/// 概览卡 + 「管理密钥」入口，增删与开关都挪进独立的 [MiuixKeysPage]。
/// [keysSectionKey] 挂在分区头上，供状态卡跳转定位。
List<Widget> miuixKeySections(
  BuildContext context,
  ServerController controller, {
  Key? keysSectionKey,
}) {
  final l10n = AppLocalizations.of(context);
  final colors = MiuixTheme.of(context).colors;
  final keys = controller.config.apiKeys;
  final enabled = keys.where((k) => k.enabled).length;
  return [
    _MiuixSectionHeader(
      key: keysSectionKey,
      title: l10n.keysTitle,
      trailing: MiuixTextButton(
        l10n.keysManage,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MiuixKeysPage(controller: controller),
          ),
        ),
      ),
    ),
    MiuixGroupCard(
      insideMargin: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: MiuixText(
        keys.isEmpty
            ? l10n.noKeysHint
            : '${l10n.keysTitle} · $enabled/${keys.length}',
        fontSize: 12,
        color: colors.onSurfaceVariantSummary,
      ),
    ),
  ];
}

/// 新增密钥面板（miuix 版）。
///
/// 外壳仍是 Material 的 showModalBottomSheet（flutter_miuix 的
/// MiuixOverlayBottomSheet 要挂在 MiuixScaffold 弹层上），底色与圆角取 miuix 值。
Future<void> showMiuixAddKeySheet(
  BuildContext context,
  ServerController controller,
) async {
  final l10n = AppLocalizations.of(context);
  final colors = MiuixTheme.of(context).colors;
  final nameCtrl = TextEditingController();
  final keyCtrl = TextEditingController(text: ApiKeyEntry.generate());
  await showMiuixBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                child: MiuixText(
                  l10n.addKey,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              MiuixTextField(
                controller: nameCtrl,
                label: l10n.keyNameLabel,
                singleLine: true,
              ),
              // MiuixTextField 只有 label 一个提示槽（浮动标签 / 占位符二选一），
              // Material 版的 hintText 就落成行下面那行小字。
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
                child: MiuixText(
                  l10n.keyNameHint,
                  fontSize: 12,
                  color: colors.onSurfaceVariantSummary,
                ),
              ),
              const SizedBox(height: 12),
              MiuixTextField(
                controller: keyCtrl,
                label: l10n.keyValueLabel,
                singleLine: true,
                keyboardType: TextInputType.url,
                trailingIcon: MiuixIconButton(
                  onPressed: () => keyCtrl.text = ApiKeyEntry.generate(),
                  child: const Icon(Icons.casino_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: MiuixButton(
                  onPressed: () {
                    final key = keyCtrl.text.trim();
                    if (key.isEmpty) {
                      showMiuixToast(sheetCtx, l10n.keyRequired, error: true);
                      return;
                    }
                    final exists = controller.config.apiKeys.any(
                      (k) => k.key == key,
                    );
                    if (exists) {
                      showMiuixToast(sheetCtx, l10n.keyExists, error: true);
                      return;
                    }
                    controller.config.apiKeys.add(
                      ApiKeyEntry(
                        id: NetworkUtils.newId(),
                        name: nameCtrl.text.trim(),
                        key: key,
                      ),
                    );
                    controller.store.update(controller.config);
                    Navigator.pop(sheetCtx);
                  },
                  colors: MiuixButtonColors(
                    color: colors.primary,
                    contentColor: colors.onPrimary,
                    disabledColor: colors.disabledPrimaryButton,
                    disabledContentColor: colors.disabledOnPrimaryButton,
                  ),
                  child: MiuixText(l10n.saveBtn),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 分组小标题（可带尾部动作）。
class _MiuixSectionHeader extends StatelessWidget {
  const _MiuixSectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 18, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: MiuixSmallTitle(title, insideMargin: EdgeInsets.zero),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
