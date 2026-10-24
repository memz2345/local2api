import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField;
import 'package:local2api/widgets/miuix/miuix_text_field.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_bottom_sheet.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/config_profile.dart';
import 'package:local2api/services/profile_service.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';
import 'package:provider/provider.dart';

import '../profile_import_sheet.dart' show profileErrorMessage;

/// 打开 miuix 风格的「新建上游」面板（导入一组模型，可给组起名 + 写说明）。
///
/// 弹窗外壳用 Material 的 showModalBottomSheet：flutter_miuix 的
/// MiuixOverlayBottomSheet 是声明式的、且要挂在 MiuixScaffold 的弹层上，
/// 而本项目 miuix 外壳用的是 Material Scaffold。圆角与底色取 miuix 的值。
Future<ConfigProfile?> showMiuixProfileImportSheet(
  BuildContext context, {
  String? initialUrl,
}) => showMiuixBottomSheet<ConfigProfile>(
  context: context,
  isScrollControlled: true,
  builder: (_) => MiuixProfileImportSheet(initialUrl: initialUrl),
);

/// miuix 风格的档案导入面板（对应 Material 版 `ProfileImportSheet`）。
///
/// 导入逻辑、格式校验与错误文案映射全都共用 Material 版那一份
/// （`profileErrorMessage`），这里只换渲染。
class MiuixProfileImportSheet extends StatefulWidget {
  const MiuixProfileImportSheet({super.key, this.initialUrl});

  /// 预填进「订阅地址」框的初始值（扫码识别到链接时带进来）。
  final String? initialUrl;

  @override
  State<MiuixProfileImportSheet> createState() =>
      _MiuixProfileImportSheetState();
}

class _MiuixProfileImportSheetState extends State<MiuixProfileImportSheet> {
  int _tab = 0;
  bool _busy = false;
  String? _pickedName;
  String? _pickedText;

  /// 用户给这个组起的名字与说明（可留空：留空就用档案文档自带的名字）。
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
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
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
      // 名字与说明存在 store 的 labels 里（不写回文档）：订阅类档案每次
      // 更新都会整份换掉文档，写进文档会被下一次拉取覆盖。
      final name = _groupNameController.text.trim();
      final desc = _groupDescController.text.trim();
      if (name.isNotEmpty || desc.isNotEmpty) {
        store.setLabel(
          profile.id,
          name: name.isEmpty ? null : name,
          description: desc.isEmpty ? null : desc,
        );
      }
      showMiuixToast(
        context,
        l10n.profileImported((store.profileOf(profile.id) ?? profile).name),
      );
    } catch (e) {
      if (!mounted) return;
      showMiuixToast(context, profileErrorMessage(l10n, e), error: true);
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
    final colors = MiuixTheme.of(context).colors;
    final store = context.read<ProfileStore>();
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
                child: MiuixText(
                  // 标题用「添加配置文件」而不是「新建上游」：这面板干的是
                  // 「导入一组上游配置（档案）」的活，跟真正的「新建上游」
                  // （上游编辑页）是两件事，别同名。
                  l10n.profileImportTitle,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              // 先给这一组起名、写说明，再选从哪导入 —— 名字是用户给这个
              // 组的身份，跟文档里那个 id 是两回事。
              MiuixTextField(
                controller: _groupNameController,
                label: l10n.profileGroupNameHint,
                useLabelAsPlaceholder: true,
                singleLine: true,
                leadingIcon: const Icon(Icons.drive_file_rename_outline),
              ),
              const SizedBox(height: 10),
              MiuixTextField(
                controller: _groupDescController,
                label: l10n.profileGroupDescHint,
                useLabelAsPlaceholder: true,
                minLines: 1,
                maxLines: 3,
                leadingIcon: const Icon(Icons.notes_outlined),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _TabChip(
                    label: l10n.profileImportTabUrl,
                    selected: _tab == 0,
                    onTap: () => setState(() => _tab = 0),
                  ),
                  const SizedBox(width: 8),
                  _TabChip(
                    label: l10n.profileImportTabFile,
                    selected: _tab == 1,
                    onTap: () => setState(() => _tab = 1),
                  ),
                  const SizedBox(width: 8),
                  _TabChip(
                    label: l10n.profileImportTabPaste,
                    selected: _tab == 2,
                    onTap: () => setState(() => _tab = 2),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              switch (_tab) {
                0 => MiuixTextField(
                  controller: _urlController,
                  label: l10n.profileImportUrlHint,
                  useLabelAsPlaceholder: true,
                  singleLine: true,
                  keyboardType: TextInputType.url,
                  leadingIcon: const Icon(Icons.link),
                  onChanged: (_) => setState(() {}),
                ),
                1 => MiuixGroupCard(
                  cornerRadius: 16,
                  insideMargin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                  feedbackType: MiuixPressFeedbackType.sink,
                  onPressed: _busy ? null : _pickFile,
                  child: Row(
                    children: [
                      Icon(
                        Icons.attach_file,
                        size: 18,
                        color: colors.onSurfaceVariantSummary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: MiuixText(
                          _pickedName ?? l10n.profileImportPickFile,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          color: _pickedName == null
                              ? colors.onSurfaceVariantSummary
                              : colors.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                _ => MiuixTextField(
                  controller: _pasteController,
                  label: l10n.profileImportPasteHint,
                  useLabelAsPlaceholder: true,
                  minLines: 6,
                  maxLines: 10,
                  onChanged: (_) => setState(() {}),
                ),
              },
              const SizedBox(height: 12),
              MiuixText(
                l10n.profileImportNote,
                fontSize: 12,
                color: colors.onSurfaceVariantSummary,
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: MiuixButton(
                  onPressed: _busy || !_canSubmit ? null : () => _submit(store),
                  colors: MiuixButtonColors(
                    color: colors.primary,
                    contentColor: colors.onPrimary,
                    disabledColor: colors.disabledPrimary,
                    disabledContentColor: colors.disabledOnPrimaryButton,
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : MiuixText(l10n.profileImportSubmit),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 三个导入入口的选择片。用 MiuixCard 而不是 SegmentedButton，
/// 免得在 HyperOS 页面里露出一块 Material 控件。
class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return Expanded(
      child: MiuixGroupCard(
        cornerRadius: 12,
        insideMargin: const EdgeInsets.symmetric(vertical: 10),
        feedbackType: MiuixPressFeedbackType.sink,
        onPressed: onTap,
        colors: selected
            ? MiuixCardColors(
                color: colors.primary,
                contentColor: colors.onPrimary,
              )
            : null,
        child: Center(
          child: MiuixText(
            label,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
