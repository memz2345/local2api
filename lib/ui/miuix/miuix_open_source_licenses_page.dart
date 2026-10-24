// lib/ui/miuix/miuix_open_source_licenses_page.dart
//
// 第三方依赖清单（miuix 版）：LicenseRegistry + pubspec.lock 版本，
// 搜索 / 一行一个依赖包 / 点进独立许可页。版式照 KernelSU 的模块页：
// 搜索框在最上面，下面一卡一项，右侧版本与箭头。
// Material 版在 `ui/open_source_licenses_page.dart`。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField;

import '../../l10n/app_localizations.dart';
import '../../services/oss_license_service.dart';
import '../../widgets/miuix/miuix_app_icon.dart';
import '../../widgets/miuix/miuix_blur_top_bar.dart';
import '../../widgets/miuix/miuix_group_card.dart';
import '../../widgets/miuix/miuix_text_field.dart';
import 'miuix_about_page.dart' show kAppName;
import 'miuix_oss_package_license_page.dart';

class MiuixOpenSourceLicensesPage extends StatefulWidget {
  const MiuixOpenSourceLicensesPage({super.key});

  @override
  State<MiuixOpenSourceLicensesPage> createState() =>
      _MiuixOpenSourceLicensesPageState();
}

class _MiuixOpenSourceLicensesPageState
    extends State<MiuixOpenSourceLicensesPage> {
  final TextEditingController _search = TextEditingController();

  OssLicenseData? _data;
  Object? _error;
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      if (_search.text == _query) return;
      setState(() => _query = _search.text);
    });
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await loadOssLicenses(refresh: refresh);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  List<OssPackage> get _visiblePackages {
    final all = _data?.packages ?? const <OssPackage>[];
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return all;
    return [
      for (final pkg in all)
        if (pkg.name.toLowerCase().contains(query) ||
            (pkg.version ?? '').toLowerCase().contains(query) ||
            pkg.licenseIds.any((id) => id.toLowerCase().contains(query)))
          pkg,
    ];
  }

  void _openPackage(OssPackage pkg) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MiuixOssPackageLicensePage(package: pkg),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final packages = _visiblePackages;
    final query = _query.trim();

    return Material(
      type: MaterialType.transparency,
      child: MiuixScaffold(
        containerColor: colors.surface,
        topBar: MiuixBlurTopBar(
          title: l10n.ossTitle,
          navigationIcon: MiuixIconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const MiuixAppIcon(
              AppIconNames.back,
              fallback: Icons.arrow_back,
            ),
          ),
        ),
        content: (padding) => CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, padding.top + 6, 16, 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildHeader(l10n, colors),
                  const SizedBox(height: 14),
                  MiuixTextField(
                    controller: _search,
                    label: l10n.ossSearchHint,
                    useLabelAsPlaceholder: true,
                    singleLine: true,
                    textInputAction: TextInputAction.search,
                    leadingIcon: const MiuixAppIcon(
                      AppIconNames.search,
                      fallback: Icons.search,
                      size: 20,
                    ),
                    trailingIcon: query.isEmpty
                        ? null
                        : MiuixIconButton(
                            onPressed: () => _search.clear(),
                            child: const MiuixAppIcon(
                              AppIconNames.close,
                              fallback: Icons.close,
                              size: 18,
                            ),
                          ),
                  ),
                  if (query.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: MiuixText(
                        '${packages.length} / ${_data?.packages.length ?? 0}',
                        fontSize: 11,
                        color: colors.onSurfaceVariantSummary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                ]),
              ),
            ),
            _buildSliver(colors, l10n, packages),
            SliverToBoxAdapter(
              child: SizedBox(height: padding.bottom + 24),
            ),
          ],
        ),
      ),
    );
  }

  /// 头部：应用名 + Flutter/Dart + 包与许可总数（清单没就绪时先说「正在收集」）。
  Widget _buildHeader(AppLocalizations l10n, MiuixColors colors) {
    final count = _data?.packages.length ?? 0;
    final licenses = _data?.totalLicenses ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 4),
          child: MiuixText(
            kAppName,
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: colors.primary,
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: MiuixText(
            'Flutter · Dart ${_dartVersion()}',
            fontSize: 12.5,
            color: colors.onSurfaceVariantSummary,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: MiuixText(
            _data == null
                ? l10n.ossLoading
                : l10n.ossPackagesCount('$count', '$licenses'),
            fontSize: 12,
            color: colors.onSurfaceVariantSummary,
          ),
        ),
      ],
    );
  }

  String _dartVersion() {
    try {
      final version = Platform.version;
      final space = version.indexOf(' ');
      return space > 0 ? version.substring(0, space) : version;
    } catch (_) {
      return '—';
    }
  }

  Widget _buildSliver(
    MiuixColors colors,
    AppLocalizations l10n,
    List<OssPackage> packages,
  ) {
    if (_loading) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 60),
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: colors.primary,
            ),
          ),
        ),
      );
    }
    if (_error != null) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(
          child: _Placeholder(
            text: l10n.ossLoadFailed,
            onRetry: () => _load(refresh: true),
            retryLabel: l10n.ossRetry,
          ),
        ),
      );
    }
    if (packages.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(
          child: _Placeholder(
            text: _query.trim().isEmpty
                ? l10n.ossLoadFailed
                : l10n.ossEmptySearch,
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.builder(
        itemCount: packages.length,
        itemBuilder: (context, index) {
          final pkg = packages[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: MiuixGroupCard(
              insideMargin: EdgeInsets.zero,
              feedbackType: MiuixPressFeedbackType.sink,
              onPressed: () => _openPackage(pkg),
              child: MiuixBasicComponent(
                insideMargin: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                title: pkg.name,
                summary: [
                  if (pkg.distinctLicenseIds.isNotEmpty)
                    pkg.distinctLicenseIds.join(' / '),
                  l10n.ossLicensesCount('${pkg.licenseCount}'),
                ].join(' · '),
                endActions: [
                  if (pkg.version != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: MiuixText(
                        'v${pkg.version}',
                        fontSize: 11,
                        color: colors.onSurfaceVariantSummary,
                      ),
                    ),
                  MiuixAppIcon(
                    AppIconNames.forward,
                    fallback: Icons.chevron_right,
                    size: 18,
                    color: colors.onSurfaceVariantActions,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.text, this.onRetry, this.retryLabel});

  final String text;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixGroupCard(
      insideMargin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
        child: Column(
          children: [
            MiuixText(
              text,
              fontSize: 13,
              height: 1.5,
              textAlign: TextAlign.center,
              color: colors.onSurfaceVariantSummary,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              MiuixTextButton(
                retryLabel ?? '',
                onPressed: onRetry,
                minWidth: 0,
                minHeight: 34,
                insideMargin: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                textStyle: const TextStyle(fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
