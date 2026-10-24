import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/ui/qr_scan_result.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';

import 'miuix_profile_import_sheet.dart' show showMiuixProfileImportSheet;
import 'miuix_qr_scanner_page.dart';
import 'miuix_upstream_edit_page.dart';

/// miuix 风格的「创建配置」页（对应 Material 版 `CreateConfigPage`）。
///
/// 三个入口：
/// - 添加配置文件：打开档案导入面板（订阅地址 / 本地文件 / 粘贴 JSON），
///   导入一组上游配置；
/// - 扫描二维码：开扫码页，识别应用 JSON（导入到规则）、网页链接
///   （带进订阅导入）与纯文本；
/// - 新建上游：打开**真正的上游编辑页**（与仪表盘「上游服务」卡片的加号
///   同一个页面）。
///
/// ⚠️ 「新建上游」以前打开的是档案导入面板（给一个模型组起名 + 选导入方式），
/// 那是「建一个组」不是「建一个上游」，跟这一行的语义对不上，已改成直连
/// [MiuixUpstreamEditPage]。发现页现在直接列上游卡片，两个入口都能一眼看到结果。
class MiuixCreateConfigPage extends StatefulWidget {
  const MiuixCreateConfigPage({super.key, required this.controller});

  final ServerController controller;

  @override
  State<MiuixCreateConfigPage> createState() => _MiuixCreateConfigPageState();
}

class _MiuixCreateConfigPageState extends State<MiuixCreateConfigPage> {
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();

  @override
  void dispose() {
    _behavior.state.dispose();
    super.dispose();
  }

  /// 打开档案导入面板（订阅地址 / 本地文件 / 粘贴 JSON 三选一）。
  ///
  /// 以前这一行只收本地文件，URL 订阅与「粘贴 JSON」两个入口挂在发现页的
  /// 「新建上游」面板上；那份面板现在让位给上游编辑页，就把三种导入一起
  /// 收进这里，功能一个都不少。
  Future<void> _importProfile() => showMiuixProfileImportSheet(context);

  /// 「新建上游」= 打开真正的上游编辑页（与仪表盘「上游服务」卡片的加号
  /// 同一个页面）。不再是「给一个档案组起名 / 选导入方式」的面板 —— 那是
  /// 另一件事，跟这一行的语义对不上。
  void _openNewUpstream() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MiuixUpstreamEditPage(controller: widget.controller),
      ),
    );
  }

  /// 扫码页识别到内容后带值 pop 回来，在这里分类处理（导入 / 复制 / 订阅）。
  Future<void> _scanQr() async {
    final text = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const MiuixQrScannerPage()),
    );
    if (text == null || text.isEmpty || !mounted) return;
    await handleScanResult(context, widget.controller, text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;

    return Material(
      type: MaterialType.transparency,
      child: MiuixScaffold(
        containerColor: colors.surface,
        topBar: MiuixBlurTopBar(
          scrollBehavior: _behavior,
          title: l10n.createConfigTitle,
          navigationIcon: MiuixIconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const MiuixAppIcon(
              AppIconNames.back,
              fallback: Icons.arrow_back,
            ),
          ),
        ),
        // 内容铺满整页、顶栏画在其上；顶栏高度垫进 padding，从栏下穿过。
        content: (padding) => MiuixScrollBehaviorListener(
          behavior: _behavior,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(16, padding.top + 8, 16, 24),
            children: [
              MiuixGroupCard(
                insideMargin: EdgeInsets.zero,
                child: Column(
                  children: [
                    MiuixArrowPreference(
                      title: l10n.profileImportTitle,
                      summary: l10n.createConfigFileDesc,
                      startAction: MiuixAppIcon(
                        AppIconNames.file,
                        fallback: Icons.attach_file,
                        size: 24,
                        color: colors.primary,
                      ),
                      onClick: _importProfile,
                    ),
                    const MiuixHorizontalDivider(),
                    MiuixArrowPreference(
                      title: l10n.createConfigScanTitle,
                      summary: l10n.createConfigScanDesc,
                      startAction: MiuixAppIcon(
                        AppIconNames.scan,
                        fallback: Icons.qr_code_scanner,
                        size: 24,
                        color: colors.primary,
                      ),
                      onClick: _scanQr,
                    ),
                    const MiuixHorizontalDivider(),
                    MiuixArrowPreference(
                      title: l10n.profileNewUpstreamTitle,
                      summary: l10n.createConfigUpstreamDesc,
                      startAction: MiuixAppIcon(
                        AppIconNames.addCircle,
                        fallback: Icons.add_circle_outline,
                        size: 24,
                        color: colors.primary,
                      ),
                      onClick: _openNewUpstream,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
