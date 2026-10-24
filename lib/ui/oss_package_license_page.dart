// lib/ui/oss_package_license_page.dart
//
// 单个开源包的完整许可页（Material 版，从依赖清单点进来）。
// 头部一张卡放元信息，下面一份许可一张卡，正文保留原文缩进、可选中复制。
// miuix 版在 `ui/miuix/miuix_oss_package_license_page.dart`。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/oss_license_service.dart';
import '../widgets/app_toast.dart';
import '../widgets/expressive_app_bar.dart' show MorphIconButton;
import '../widgets/frosted_page_bar.dart';

class OssPackageLicensePage extends StatelessWidget {
  const OssPackageLicensePage({super.key, required this.package});

  final OssPackage package;

  Future<void> _copyAll(BuildContext context, AppLocalizations l10n) async {
    await Clipboard.setData(ClipboardData(text: package.fullText));
    if (!context.mounted) return;
    showAppToast(context, l10n.ossLicenseCopied);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final count = package.licenses.length;

    return FrostedBarPage(
      title: package.name,
      actions: [
        MorphIconButton(
          icon: Icons.copy_rounded,
          iconSize: 20,
          tooltip: l10n.ossCopyFullText,
          transparent: true,
          onTap: () => _copyAll(context, l10n),
        ),
        const SizedBox(width: 4),
      ],
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(
          16,
          frostedPageBarInset(context) + 8,
          16,
          MediaQuery.paddingOf(context).bottom + 32,
        ),
        itemCount: count + 1,
        itemBuilder: (context, index) {
          if (index == 0) return _buildHeader(context, cs, l10n);
          return _buildLicenseCard(context, cs, l10n, index - 1, count);
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme cs, AppLocalizations l10n) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                package.name,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                [
                  if (package.version != null) 'v${package.version}',
                  if (package.distinctLicenseIds.isNotEmpty)
                    package.distinctLicenseIds.join(' / '),
                  l10n.ossLicensesCount('${package.licenseCount}'),
                ].join(' · '),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 一份许可一张卡片：标题（第 n / N 份 · 标识）+ 正文段落。
  Widget _buildLicenseCard(
    BuildContext context,
    ColorScheme cs,
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
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                count > 1
                    ? '${l10n.ossLicenseIndex('${index + 1}', '$count')} · $id'
                    : id,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
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
                      color: cs.onSurface.withValues(alpha: 0.85),
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
