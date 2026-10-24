import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/config_profile.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/ui/qr_scanner_page.dart';
import 'package:local2api/ui/qr_scan_result.dart';
import 'package:local2api/widgets/frosted_page_bar.dart';
import 'package:local2api/widgets/predictive_back_sheet.dart';

import 'profile_import_sheet.dart';
import 'upstream_edit_page.dart';
import 'widgets/common.dart' show pushPage;

/// 创建配置页：发现页 FAB 加号打开的这一页。
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
/// [UpstreamEditPage]。发现页现在直接列上游卡片，两个入口都能一眼看到结果。
class CreateConfigPage extends StatelessWidget {
  const CreateConfigPage({super.key, required this.controller});

  final ServerController controller;

  /// 打开档案导入面板（订阅地址 / 本地文件 / 粘贴 JSON 三选一）。
  ///
  /// 以前这一行只收本地文件，URL 订阅与「粘贴 JSON」两个入口挂在发现页的
  /// 「新建上游」面板上；那份面板现在让位给上游编辑页，就把三种导入一起
  /// 收进这里，功能一个都不少。
  Future<void> _importProfile(BuildContext context) =>
      showAppBottomSheet<ConfigProfile>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const ProfileImportSheet(),
      );

  /// 「新建上游」= 打开真正的上游编辑页（与仪表盘「上游服务」卡片的加号
  /// 同一个页面）。不再是「给一个档案组起名 / 选导入方式」的面板 —— 那是
  /// 另一件事，跟这一行的语义对不上。
  void _openNewUpstream(BuildContext context) {
    pushPage(context, UpstreamEditPage(controller: controller));
  }

  /// 扫码页识别到内容后带值 pop 回来，在这里分类处理（导入 / 复制 / 订阅）。
  Future<void> _scanQr(BuildContext context) async {
    final text = await pushPage<String>(context, const QrScannerPage());
    if (text == null || text.isEmpty || !context.mounted) return;
    await handleScanResult(context, controller, text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FrostedBarPage(
      title: l10n.createConfigTitle,
      child: ListView(
        padding: EdgeInsets.only(
          top: frostedPageBarInset(context) + 8,
          bottom: 32,
        ),
        children: [
          _CreateOption(
            icon: Icons.attach_file,
            title: l10n.profileImportTitle,
            subtitle: l10n.createConfigFileDesc,
            onTap: () => _importProfile(context),
          ),
          _CreateOption(
            icon: Icons.qr_code_scanner,
            title: l10n.createConfigScanTitle,
            subtitle: l10n.createConfigScanDesc,
            onTap: () => _scanQr(context),
          ),
          _CreateOption(
            icon: Icons.add_circle_outline,
            title: l10n.profileNewUpstreamTitle,
            subtitle: l10n.createConfigUpstreamDesc,
            onTap: () => _openNewUpstream(context),
          ),
        ],
      ),
    );
  }
}

/// 一行创建入口：图标 + 标题 + 副标题（对齐设计稿，不走卡片）。
///
/// ⚠️ 那层 `Material(type: transparency)` 不是多余的：这一页铺在
/// [FrostedBarPage] 上，body 里 `PageBackground` 画在 `Scaffold` 自带的
/// `Material` **之上**，而 `InkWell` 的墨迹是画在**最近的祖先 Material** 上的
/// —— 不自己套一层，ripple 就落在背景图底下，点了完全看不见（这就是
/// 「两行没有 ripple」的成因）。行本身透明，所以套透明 Material 不改观感。
class _CreateOption extends StatelessWidget {
  const _CreateOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  static const BorderRadius _shape = BorderRadius.all(Radius.circular(16));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: _shape,
        child: InkWell(
          onTap: onTap,
          borderRadius: _shape,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 28, color: cs.onSurface),
                const SizedBox(width: 22),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
