// 共享的「点行改一项」字段编辑弹窗（miuix 版）。
//
// 自 miuix_upstream_edit_page.dart 抽出来：上游编辑页和角色卡编辑页都是
// 「一行一个字段」的 CMFA 式布局，点行弹这个对话框改那一项。
//
// 弹窗用 [showMiuixDialog]（HyperOS 那种居中大圆角卡 + 左取消右确定），
// 不用底部抽屉 —— 行式设置页改一项，弹个对话框比抽屉更贴。
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField;
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/widgets/miuix/miuix_text_field.dart';
import 'package:local2api/widgets/miuix/miuix_dialog.dart';

/// 弹出字段编辑对话框，确定返回输入值，取消返回 null。
///
/// ⚠️ 输入框的 controller 归 [MiuixFieldDialogBody] 自己管：调用方
/// `await` 完就 dispose 的话，对话框的退场动画还在跑，TextField 会再去读
/// 一次已释放的 controller → 「used after being disposed」。草稿通过
/// `onChanged` 回写到局部变量，确定时再取，不碰那个 controller。
Future<String?> showMiuixFieldEditor(
  BuildContext context, {
  required String label,
  required String initial,
  String? hint,
  TextInputType? keyboardType,
  int maxLines = 1,
}) async {
  final l10n = AppLocalizations.of(context);
  var draft = initial;
  final ok = await showMiuixDialog<bool>(
    context: context,
    title: label,
    content: MiuixFieldDialogBody(
      label: label,
      initial: initial,
      hint: hint,
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: (v) => draft = v,
    ),
    actions: [
      MiuixDialogAction(
        label: l10n.cancel,
        onPressed: (ctx) => Navigator.of(ctx).pop(false),
      ),
      MiuixDialogAction(
        label: l10n.confirm,
        primary: true,
        onPressed: (ctx) => Navigator.of(ctx).pop(true),
      ),
    ],
  );
  if (ok != true) return null;
  return draft;
}

/// 对话框里的一个文本输入（名称 / URL / 密钥 / 备注 / 人设共用），给
/// [showMiuixDialog] 的 `content` 用。
///
/// controller 由这个 State 自己建、自己释放，草稿通过 [onChanged] 回写给调用方
/// 的局部变量 —— 调用方不要去碰这个 controller，见
/// [showMiuixFieldEditor] 的注释。
class MiuixFieldDialogBody extends StatefulWidget {
  const MiuixFieldDialogBody({
    super.key,
    required this.label,
    required this.initial,
    required this.onChanged,
    this.hint,
    this.keyboardType,
    this.maxLines = 1,
  });

  final String label;
  final String initial;
  final String? hint;
  final TextInputType? keyboardType;
  final int maxLines;
  final ValueChanged<String> onChanged;

  @override
  State<MiuixFieldDialogBody> createState() => _MiuixFieldDialogBodyState();
}

class _MiuixFieldDialogBodyState extends State<MiuixFieldDialogBody> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
    // 对话框一进来就把当前值交出去：用户不动输入框直接点确定时，
    // 调用方拿到的草稿至少是初始值。
    widget.onChanged(widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MiuixTextField(
          controller: _ctrl,
          label: widget.label,
          autofocus: true,
          singleLine: widget.maxLines <= 1,
          minLines: widget.maxLines > 1 ? 1 : null,
          maxLines: widget.maxLines,
          keyboardType: widget.keyboardType,
          onChanged: widget.onChanged,
        ),
        if (widget.hint != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: MiuixText(
              widget.hint!,
              fontSize: 12,
              color: colors.onSurfaceVariantSummary,
            ),
          ),
      ],
    );
  }
}
