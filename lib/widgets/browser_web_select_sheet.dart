// lib/widgets/browser_web_select_sheet.dart
//
// 网页 `<select>` 的宿主选择器（内置浏览器专用）。
//
// WebView 自带的弹窗是 `android.R.layout.select_dialog_singlechoice` ——
// 灰 radio、细分割线、系统老滚动条，也就是「安卓 2.x」的那张脸。这里用
// 两套皮重画：
//   · Material 3：`showAppBottomSheet` + `RadioGroup` + 常驻细滚动条；
//   · miuix（HyperOS）：`showMiuixBottomSheet` + `MiuixGroupCard` 里的
//     `MiuixRadioButtonPreference` 行。
//
// 返回值 = 选中的 `<option>.index`；null = 取消（用户滑掉 / 点遮罩 / 返回）。

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../services/browser_web_shim.dart';
import 'miuix/miuix_bottom_sheet.dart';
import 'miuix/miuix_group_card.dart';
import 'predictive_back_sheet.dart';

/// 弹出选择面板。两套风格二选一，由调用方（[BrowserWebView]）决定。
Future<int?> showBrowserWebSelectSheet(
  BuildContext context, {
  required BrowserSelectRequest request,
  required String title,
  required bool useMiuix,
}) {
  if (useMiuix) {
    return showMiuixBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _BrowserSelectSheet(request: request, title: title, useMiuix: true),
    );
  }
  return showAppBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        _BrowserSelectSheet(request: request, title: title, useMiuix: false),
  );
}

class _BrowserSelectSheet extends StatefulWidget {
  const _BrowserSelectSheet({
    required this.request,
    required this.title,
    required this.useMiuix,
  });

  final BrowserSelectRequest request;
  final String title;
  final bool useMiuix;

  @override
  State<_BrowserSelectSheet> createState() => _BrowserSelectSheetState();
}

class _BrowserSelectSheetState extends State<_BrowserSelectSheet> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _pick(int index) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop(index);
  }

  @override
  Widget build(BuildContext context) {
    return widget.useMiuix ? _buildMiuix(context) : _buildMaterial(context);
  }

  // ---- Material 3 ----

  Widget _buildMaterial(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.62;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              thickness: 4,
              radius: const Radius.circular(2),
              child: RadioGroup<int>(
                groupValue: widget.request.selectedIndex,
                onChanged: (value) {
                  if (value != null) _pick(value);
                },
                child: ListView(
                  controller: _scroll,
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  children: _materialRows(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _materialRows(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    var lastGroup = '';
    for (final option in widget.request.options) {
      if (option.group.isNotEmpty && option.group != lastGroup) {
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 24, 2),
            child: Text(
              option.group,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
        lastGroup = option.group;
      }
      rows.add(
        ListTile(
          enabled: !option.disabled,
          selected: option.index == widget.request.selectedIndex,
          onTap: option.disabled ? null : () => _pick(option.index),
          // Radio 只做指示器（不吃点击），点击统一交给 ListTile：
          // RadioGroup 的 onChanged 在「点已选中项」时不会触发，那条路就哑了。
          leading: IgnorePointer(child: Radio<int>(value: option.index)),
          title: Text(
            option.label.isEmpty ? '—' : option.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          visualDensity: VisualDensity.compact,
        ),
      );
    }
    return rows;
  }

  // ---- miuix ----

  Widget _buildMiuix(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.62;
    final options = widget.request.options;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: MiuixText(
                widget.title,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(
                controller: _scroll,
                child: MiuixGroupCard(
                  insideMargin: EdgeInsets.zero,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < options.length; i++) ...[
                        if (i > 0)
                          const Padding(
                            padding: EdgeInsets.only(left: 16),
                            child: MiuixHorizontalDivider(),
                          ),
                        MiuixRadioButtonPreference(
                          title: options[i].label.isEmpty
                              ? '—'
                              : options[i].label,
                          selected:
                              options[i].index == widget.request.selectedIndex,
                          enabled: !options[i].disabled,
                          insideMargin: const EdgeInsets.fromLTRB(
                            16,
                            13,
                            16,
                            13,
                          ),
                          onClick: () => _pick(options[i].index),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
