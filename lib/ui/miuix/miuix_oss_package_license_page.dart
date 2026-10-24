// lib/ui/miuix/miuix_oss_package_license_page.dart
//
// 单个开源包的完整许可页（miuix 版）。头部一张卡放元信息，下面一份许可
// 一张卡（第 n / N 份 · 许可标识），正文保留原文缩进、可选中复制。
// Material 版在 `ui/oss_package_license_page.dart`。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../l10n/app_localizations.dart';
import '../../services/oss_license_service.dart';
import '../../widgets/miuix/miuix_app_icon.dart';
import '../../widgets/miuix/miuix_blur_top_bar.dart';
import '../../widgets/miuix/miuix_group_card.dart';
import '../../widgets/miuix/miuix_toast.dart';

class MiuixOssPackageLicensePage extends StatelessWidget {
  const MiuixOssPackageLicensePage({super.key, required this.package});

  final OssPackage package;

  Future<void> _copyAll(BuildContext context, AppLocalizations l10n) async {
    await Clipboard.setData(ClipboardData(text: package.fullText));
    if (!context.mounted) return;
    showMiuixToast(context, l10n.ossLicenseCopied);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final count = package.licenses.length;

    return Material(
      type: MaterialType.transparency,
      child: MiuixScaffold(
        containerColor: colors.surface,
        topBar: MiuixBlurTopBar(
          title: package.name,
          navigationIcon: MiuixIconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const MiuixAppIcon(
              AppIconNames.back,
              fallback: Icons.arrow_back,
            ),
          ),
          actions: [
            MiuixIconButton(
              onPressed: () => _copyAll(context, l10n),
              child: const MiuixAppIcon(
                AppIconNames.copy,
                fallback: Icons.copy_rounded,
              ),
            ),
          ],
        ),
        content: (padding) => ListView.builder(
          padding: EdgeInsets.fromLTRB(
            16,
            padding.top + 6,
            16,
            padding.bottom + 24,
          ),
          itemCount: count + 1,
          itemBuilder: (context, index) {
            if (index == 0) return _header(l10n, colors);
            return _licenseCard(context, colors, l10n, index - 1, count);
          },
        ),
      ),
    );
  }

  Widget _header(AppLocalizations l10n, MiuixColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MiuixGroupCard(
        insideMargin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MiuixText(
                package.name,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
              const SizedBox(height: 6),
              MiuixText(
                [
                  if (package.version != null) 'v${package.version}',
                  if (package.distinctLicenseIds.isNotEmpty)
                    package.distinctLicenseIds.join(' / '),
                  l10n.ossLicensesCount('${package.licenseCount}'),
                ].join(' · '),
                fontSize: 12,
                color: colors.onSurfaceVariantSummary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _licenseCard(
    BuildContext context,
    MiuixColors colors,
    AppLocalizations l10n,
    int index,
    int count,
  ) {
    final paragraphs = package.licenses[index];
    final id = package.licenseIds.length > index
        ? package.licenseIds[index]
        : kOssOtherLicense;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MiuixGroupCard(
        insideMargin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MiuixText(
                count > 1
                    ? '${l10n.ossLicenseIndex('${index + 1}', '$count')} · $id'
                    : id,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariantSummary,
              ),
              const SizedBox(height: 10),
              for (final paragraph in paragraphs)
                Padding(
                  padding: EdgeInsets.only(
                    left: paragraph.indent * 16.0,
                    top: 5,
                    bottom: 5,
                  ),
                  child: SelectableText(
                    paragraph.text,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.6,
                      color: colors.onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
