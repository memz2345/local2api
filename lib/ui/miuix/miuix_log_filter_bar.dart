// lib/ui/miuix/miuix_log_filter_bar.dart
//
// 请求日志页的状态筛选（miuix 版）—— 与峰谷策略页的 `_MiuixChoiceChip`
// 同款：选中态把整张卡片染成 primary。

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/proxy_server.dart';

import '../widgets/log_filter_bar.dart' show logFilterLabel;
import '../../widgets/miuix/miuix_group_card.dart';

class MiuixLogFilterBar extends StatelessWidget {
  const MiuixLogFilterBar({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final LogStatusFilter value;
  final ValueChanged<LogStatusFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    return Row(
      children: [
        for (final f in LogStatusFilter.values) ...[
          if (f != LogStatusFilter.all) const SizedBox(width: 8),
          Expanded(
            child: MiuixGroupCard(
              cornerRadius: 12,
              insideMargin: const EdgeInsets.symmetric(vertical: 10),
              feedbackType: MiuixPressFeedbackType.sink,
              onPressed: () => onChanged(f),
              colors: value == f
                  ? MiuixCardColors(
                      color: colors.primary,
                      contentColor: colors.onPrimary,
                    )
                  : null,
              child: Center(
                child: MiuixText(
                  logFilterLabel(l10n, f),
                  fontSize: 13,
                  fontWeight: value == f ? FontWeight.w700 : FontWeight.w500,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
