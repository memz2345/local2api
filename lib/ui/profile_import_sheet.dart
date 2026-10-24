import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/widgets/native_text_context_menu.dart';
import 'package:local2api/models/config_profile.dart';
import 'package:local2api/services/profile_service.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:local2api/widgets/app_toast.dart';
import 'package:provider/provider.dart';

/// 档案解析/更新失败的原因 → 用户能看懂的一句话。
///
/// 刻意按错误码翻，不把 jsonDecode 的原文甩给用户；`notJson` 那条还点明了
/// Clash 订阅是 YAML —— 这是最常见的误填。
String profileErrorMessage(AppLocalizations l10n, Object e) => switch (e) {
  ProfileFormatException(:final code) => switch (code) {
    ProfileFormatError.empty => l10n.profileFormatEmpty,
    ProfileFormatError.notJson => l10n.profileFormatNotJson,
    ProfileFormatError.notObject => l10n.profileFormatNotObject,
    ProfileFormatError.unsupportedSchema => l10n.profileFormatUnsupportedSchema,
    ProfileFormatError.missingId => l10n.profileFormatMissingId,
    ProfileFormatError.noUpstreams => l10n.profileFormatNoUpstreams,
    ProfileFormatError.duplicateId => l10n.profileFormatDuplicateId,
  },
  ProfileUpdateException(:final message) => message,
  _ => '$e',
};

/// FAB「新建上游」弹出的导入面板：先给这一组起名 + 写说明，
/// 再选从订阅地址 / 本地文件 / 粘贴 JSON 哪条路把模型组导进来。
class ProfileImportSheet extends StatefulWidget {
  const ProfileImportSheet({super.key, this.initialUrl});

  /// 预填进「订阅地址」框的初始值（扫码识别到链接时带进来）。
  /// 非空时默认就停在订阅地址这一档。
  final String? initialUrl;

  @override
  State<ProfileImportSheet> createState() => _ProfileImportSheetState();
}

class _ProfileImportSheetState extends State<ProfileImportSheet> {
  int _tab = 0;
  bool _busy = false;
  String? _pickedName;
  String? _pickedText;

  /// 用户给这个组起的名字与说明（留空就用档案文档自带的名字）。
  final _groupNameController = TextEditingController();
  final _groupDescController = TextEditingController();

  late final TextEditingController _urlController;
  final _pasteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl ?? '');
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _groupDescController.dispose();
    _urlController.dispose();
    _pasteController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    final file = result?.files.singleOrNull;
    if (file == null) return;
    final bytes = file.bytes;
    if (bytes == null) return;
    setState(() {
      _pickedName = file.name;
      _pickedText = utf8.decode(bytes, allowMalformed: true);
    });
  }

  Future<void> _submit(ProfileStore store) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final profile = switch (_tab) {
        0 => await ProfileService.importFromUrl(
          store,
          _urlController.text.trim(),
        ),
        1 => store.importDocument(
          _pickedText!,
          ProfileSource(ProfileSourceKind.file, fileName: _pickedName),
        ),
        _ => store.importDocument(
          _pasteController.text,
          const ProfileSource(ProfileSourceKind.inline),
        ),
      };
      if (!mounted) return;
      // 带出档案：创建配置页据此知道自己该跟着回发现页（卡片在那儿）。
      Navigator.of(context).pop(profile);
      // 名字与说明存在 store 的 labels 里（不写回文档）：订阅类档案每次更新
      // 都会整份换掉文档，写进去的名字会被下一次拉取覆盖。
      final name = _groupNameController.text.trim();
      final desc = _groupDescController.text.trim();
      if (name.isNotEmpty || desc.isNotEmpty) {
        store.setLabel(
          profile.id,
          name: name.isEmpty ? null : name,
          description: desc.isEmpty ? null : desc,
        );
      }
      showAppToast(
        context,
        l10n.profileImported((store.profileOf(profile.id) ?? profile).name),
      );
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, profileErrorMessage(l10n, e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _canSubmit => switch (_tab) {
    // 地址得像个 http(s) URL，否则拉取必然失败，不如先拦住
    0 => Uri.tryParse(_urlController.text.trim())?.host.isNotEmpty ?? false,
    1 => _pickedText != null,
    _ => _pasteController.text.trim().isNotEmpty,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final store = context.read<ProfileStore>();
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                // 标题用「添加配置文件」而不是「新建上游」：这面板干的是
                // 「导入一组上游配置（档案）」的活，跟真正的「新建上游」
                // （上游编辑页）是两件事，别同名。
                l10n.profileImportTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            // 先给这一组起名、写说明，再选从哪导入 —— 名字是用户给这个组的
            // 身份，跟文档里那个 id 是两回事。
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                // Windows 上右键弹原生编辑菜单
                contextMenuBuilder: textContextMenuBuilder,
                controller: _groupNameController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.profileGroupNameLabel,
                  hintText: l10n.profileGroupNameHint,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: TextField(
                // Windows 上右键弹原生编辑菜单
                contextMenuBuilder: textContextMenuBuilder,
                controller: _groupDescController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: l10n.profileGroupDescLabel,
                  hintText: l10n.profileGroupDescHint,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<int>(
                segments: [
                  ButtonSegment(
                    value: 0,
                    label: Text(l10n.profileImportTabUrl),
                    icon: const Icon(Icons.link),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text(l10n.profileImportTabFile),
                    icon: const Icon(Icons.folder_open),
                  ),
                  ButtonSegment(
                    value: 2,
                    label: Text(l10n.profileImportTabPaste),
                    icon: const Icon(Icons.content_paste),
                  ),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: switch (_tab) {
                0 => TextField(
                  // Windows 上右键弹原生编辑菜单
                  contextMenuBuilder: textContextMenuBuilder,
                  controller: _urlController,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    hintText: l10n.profileImportUrlHint,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                1 => OutlinedButton.icon(
                  onPressed: _busy ? null : _pickFile,
                  icon: const Icon(Icons.attach_file),
                  label: Text(
                    _pickedName ?? l10n.profileImportPickFile,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _ => TextField(
                  // Windows 上右键弹原生编辑菜单
                  contextMenuBuilder: textContextMenuBuilder,
                  controller: _pasteController,
                  maxLines: 8,
                  decoration: InputDecoration(
                    hintText: l10n.profileImportPasteHint,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.profileImportNote,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _busy || !_canSubmit
                        ? null
                        : () => _submit(store),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.profileImportSubmit),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
