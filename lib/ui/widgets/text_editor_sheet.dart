// 共享的「点行改一项」文本编辑抽屉（Material 版）。
//
// 自 upstream_edit_page.dart 抽出来：上游编辑页与角色卡编辑页都是
// 「一行一个字段」布局，点行弹这个抽屉改那一项，确定返回输入值
// （取消返回 null）。
import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/widgets/native_text_context_menu.dart';
import 'package:local2api/widgets/predictive_back_sheet.dart';

/// 弹出字段编辑抽屉，确定返回输入值，取消返回 null。
///
/// ⚠️ 抽屉里的 controller 归 [_TextEditorSheet] 自己管：以前调用方
/// `await` 完就 `dispose()`，而 bottom sheet 的**退场动画还在跑**，
/// TextField 又去读一次已释放的 controller → 「used after being disposed」。
/// controller 在路由真正 dispose 时释放，动画早结束了，才安全。
Future<String?> showTextEditorSheet(
  BuildContext context, {
  required String label,
  required String initial,
  String? hint,
  TextInputType? keyboardType,
  int maxLines = 1,
}) {
  return showAppBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _TextEditorSheet(
      label: label,
      initial: initial,
      hint: hint,
      keyboardType: keyboardType,
      maxLines: maxLines,
    ),
  );
}

class _TextEditorSheet extends StatefulWidget {
  const _TextEditorSheet({
    required this.label,
    required this.initial,
    this.hint,
    this.keyboardType,
    this.maxLines = 1,
  });

  final String label;
  final String initial;
  final String? hint;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  State<_TextEditorSheet> createState() => _TextEditorSheetState();
}

class _TextEditorSheetState extends State<_TextEditorSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Text(
                  widget.label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextField(
                // Windows 上右键弹原生编辑菜单
                contextMenuBuilder: textContextMenuBuilder,
                controller: _ctrl,
                autofocus: true,
                maxLines: widget.maxLines,
                minLines: widget.maxLines > 1 ? 1 : null,
                keyboardType: widget.keyboardType,
                decoration: InputDecoration(
                  labelText: widget.label,
                  hintText: widget.hint,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _ctrl.text),
                    child: Text(l10n.confirm),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
