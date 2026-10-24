import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/widgets/native_text_context_menu.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/network_utils.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/widgets/app_toast.dart';
import 'package:local2api/widgets/app_tooltip.dart';
import 'package:local2api/widgets/predictive_back_sheet.dart';

import 'keys_page.dart';
import 'widgets/common.dart';

/// 仪表盘的「API 密钥」分区 —— 只留一张概览卡 + 「管理密钥」入口，
/// 增删与开关都挪进独立的 [KeysPage]（仪表盘上摆一长串密钥太占地方）。
/// [keysSectionKey] 挂在分组卡上，供状态卡跳转定位。
List<Widget> keySections(
  BuildContext context,
  ServerController controller, {
  Key? keysSectionKey,
}) {
  final l10n = AppLocalizations.of(context);
  final theme = Theme.of(context);
  final keys = controller.config.apiKeys;
  final enabled = keys.where((k) => k.enabled).length;
  return [
    SectionCard(
      key: keysSectionKey,
      title: l10n.keysTitle,
      trailing: TextButton(
        onPressed: () => pushPage(context, KeysPage(controller: controller)),
        child: Text(l10n.keysManage),
      ),
      child: Text(
        keys.isEmpty
            ? l10n.noKeysHint
            : '${l10n.keysTitle} · $enabled/${keys.length}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  ];
}

/// 新增密钥面板。
Future<void> showAddKeySheet(
  BuildContext context,
  ServerController controller,
) async {
  final l10n = AppLocalizations.of(context);
  final nameCtrl = TextEditingController();
  final keyCtrl = TextEditingController(text: ApiKeyEntry.generate());
  await showAppBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetCtx) {
      return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.addKey, style: Theme.of(sheetCtx).textTheme.titleMedium),
            const SizedBox(height: 14),
            TextField(
              // Windows 上右键弹原生编辑菜单
              contextMenuBuilder: textContextMenuBuilder,
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.keyNameLabel,
                hintText: l10n.keyNameHint,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              // Windows 上右键弹原生编辑菜单
              contextMenuBuilder: textContextMenuBuilder,
              controller: keyCtrl,
              decoration: InputDecoration(
                labelText: l10n.keyValueLabel,
                suffixIcon: AppTooltip(
                  message: l10n.generate,
                  child: IconButton(
                    icon: const Icon(Icons.casino_outlined, size: 20),
                    onPressed: () => keyCtrl.text = ApiKeyEntry.generate(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final key = keyCtrl.text.trim();
                if (key.isEmpty) {
                  showAppToast(context, l10n.keyRequired);
                  return;
                }
                final exists = controller.config.apiKeys.any(
                  (k) => k.key == key,
                );
                if (exists) {
                  showAppToast(context, l10n.keyExists);
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
              child: Text(l10n.saveBtn),
            ),
          ],
        ),
      );
    },
  );
}
