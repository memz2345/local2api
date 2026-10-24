// lib/ui/quick_task_actions.dart
//
// 「快捷任务」的 UI 侧：动作分发 + 任务对话框。
//
// 三个入口（Windows 跳转列表、安卓长按 Shortcut、应用内「任务」按钮）点进来的
// 都是同一个动作串，全部走 [dispatchQuickAction] 这一条路，避免三处各写一份
// 「启动服务该怎么启动」。
//
// [showQuickTaskDialog] 的落地方式按平台分档（同 NaviFlash 的
// `WindowsTaskDialog.isSupported` 优先原生那一套）：
//   · Windows：原生 TaskDialog 命令链接（task_dialog.cpp）—— 系统原生的
//     「主标题 + 图标 + 主文本 + 副标题」；
//   · 其它平台：Flutter 同构弹窗，按界面风格二选一（Material AlertDialog /
//     miuix 卡片弹窗），保持双风格各有一套（本仓库的既定做法）。

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart'
    show MiuixPressFeedbackType, MiuixText, MiuixTheme;
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/screens/display_settings_screen.dart';
import 'package:local2api/screens/miuix/miuix_display_settings_screen.dart';
import 'package:local2api/services/lab/dsh_task_center.dart';
import 'package:local2api/services/lab/dsh_windows_toast.dart';
import 'package:local2api/services/nav_bus.dart';
import 'package:local2api/services/quick_actions.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/services/window_service.dart';
import 'package:local2api/services/windows_task_dialog.dart';
import 'package:local2api/src/enums.dart' show UiStyleX;
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_dialog.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:provider/provider.dart';

import 'miuix/miuix_token_stats_page.dart';
import 'miuix/miuix_upstream_edit_page.dart';
import 'token_stats_page.dart';
import 'upstream_edit_page.dart';
import 'widgets/common.dart' show pushStyledPage;

/// 分发一个快捷动作。[context] 用根 Navigator 的上下文（跳转列表 / Shortcut
/// 都是应用级入口，不该在某一页的导航栈里找页面）。
Future<void> dispatchQuickAction(
  BuildContext context,
  ServerController controller,
  String action,
) async {
  switch (action) {
    case QuickAction.serverStart:
      // 幂等：已经在跑就不重复起（跳转列表里的条目是上一次发布的静态清单，
      // 用户点的可能是状态已经变了的那一项）。
      if (!controller.isRunning) await controller.start();
    case QuickAction.serverPause:
      if (controller.isRunning) await controller.stop();
    case QuickAction.settings:
      // 设置是一级 tab，不是独立页面：切过去即可（宽屏侧栏壳也听得见，
      // 见 SideBarShell 的 NavBus 监听）。
      NavBus.requestTab(2);
    case QuickAction.tokenStats:
      await pushStyledPage(
        context,
        material: const TokenStatsPage(),
        miuix: const MiuixTokenStatsPage(),
      );
    case QuickAction.discover:
      NavBus.requestTab(1);
    case QuickAction.trayHintOff:
      // Toast 上的「不再提示」：只改偏好，窗口保持隐藏（用户本来就在收托盘）。
      await context.read<SettingsService>().setTrayHintEnabled(false);
    case QuickAction.trayHintSettings:
      // Toast 上的「设置」：先把窗口叫回来，再进显示设置的「桌面窗口」区
      // （关闭行为与托盘提示两个开关都在那儿）。
      if (WindowService.isSupported) {
        await WindowService.instance.showWindow();
      }
      if (!context.mounted) return;
      await pushStyledPage(
        context,
        material: const DisplaySettingsScreen(),
        miuix: const MiuixDisplaySettingsScreen(),
      );
    case QuickAction.legacyToggle:
      // 安卓 Shortcut 的历史 id：运行中就停、停止就启动。
      if (controller.isRunning) {
        await controller.stop();
      } else {
        await controller.start();
      }
    default:
      // dsh 系统 Toast 的按钮/正文点击：进程不在时系统会用快捷方式拉起
      // 本 exe，动作经 WM_COPYDATA 转到这里。输入框文字只在进程内事件里
      // 有，这条兜底路径能处理选项 / 跳过 / 打开。
      if (action.startsWith('dsh_toast') ||
          action.startsWith('--l2a-action=dsh_toast')) {
        final parsed = parseToastAction(action);
        if (parsed.key == 'open') {
          if (WindowService.isSupported) {
            await WindowService.instance.showWindow();
          }
        }
        DshTaskCenter.instance.handleToastAction(
          tag: parsed.tag,
          key: parsed.key,
          value: parsed.value.isEmpty ? null : parsed.value,
        );
        return;
      }
      final id = QuickAction.upstreamIdOf(action);
      if (id == null) {
        debugPrint('⚠️ 未知的快捷动作: $action');
        return;
      }
      final upstream = controller.config.upstreams
          .where((u) => u.id == id)
          .firstOrNull;
      if (upstream == null) {
        // 这一组在上次发布清单后被删掉了：静默回到「什么都没发生」，
        // 下一次发布就会把清单纠正过来。
        debugPrint('⚠️ 快捷动作指向的上游组已不存在: $id');
        return;
      }
      await pushStyledPage(
        context,
        material: UpstreamEditPage(controller: controller, upstream: upstream),
        miuix: MiuixUpstreamEditPage(
          controller: controller,
          upstream: upstream,
        ),
      );
  }
}

/// 弹「任务」对话框，选中项就地分发。
Future<void> showQuickTaskDialog(
  BuildContext context,
  ServerController controller,
) async {
  final l10n = AppLocalizations.of(context);
  final tasks = quickTaskItems(l10n, controller);
  final recents = quickRecentItems(l10n, controller.config);
  final all = <QuickTaskItem>[...tasks, ...recents];

  if (WindowsTaskDialog.isSupported) {
    final picked = await WindowsTaskDialog.show(
      title: l10n.tasksDialogTitle,
      heading: l10n.tasksDialogTitle,
      links: [
        for (final item in all)
          (text: item.title, subtitle: item.subtitle),
      ],
    );
    final index = picked?.index;
    if (index == null || index < 0 || index >= all.length) return;
    if (!context.mounted) return;
    await dispatchQuickAction(context, controller, all[index].action);
    return;
  }

  final isMiuix = context.read<SettingsService>().uiStyle.isMiuix;
  final action = isMiuix
      ? await _showMiuixTaskDialog(context, l10n, tasks, recents)
      : await _showMaterialTaskDialog(context, l10n, tasks, recents);
  if (action == null || !context.mounted) return;
  await dispatchQuickAction(context, controller, action);
}

// ---------------------------------------------------------------------------
// Material
// ---------------------------------------------------------------------------

Future<String?> _showMaterialTaskDialog(
  BuildContext context,
  AppLocalizations l10n,
  List<QuickTaskItem> tasks,
  List<QuickTaskItem> recents,
) {
  return showDialog<String>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: Text(l10n.tasksDialogTitle),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in tasks)
                _MaterialTaskRow(
                  item: item,
                  onTap: () => Navigator.of(dialogCtx).pop(item.action),
                ),
              if (recents.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
                  child: Text(
                    l10n.tasksRecentSection,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final item in recents)
                  _MaterialTaskRow(
                    item: item,
                    onTap: () => Navigator.of(dialogCtx).pop(item.action),
                  ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _MaterialTaskRow extends StatelessWidget {
  const _MaterialTaskRow({required this.item, required this.onTap});

  final QuickTaskItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(item.materialIcon, color: cs.onSurfaceVariant),
      title: Text(item.title),
      subtitle: item.subtitle.isEmpty ? null : Text(item.subtitle),
      onTap: onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// miuix（HyperOS）
// ---------------------------------------------------------------------------

Future<String?> _showMiuixTaskDialog(
  BuildContext context,
  AppLocalizations l10n,
  List<QuickTaskItem> tasks,
  List<QuickTaskItem> recents,
) {
  return showMiuixDialog<String>(
    context: context,
    title: l10n.tasksDialogTitle,
    content: Builder(
      builder: (dialogCtx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in tasks)
            _MiuixTaskRow(
              item: item,
              onTap: () => Navigator.of(dialogCtx).pop(item.action),
            ),
          if (recents.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: MiuixText(
                  l10n.tasksRecentSection,
                  fontSize: 13,
                  color: MiuixTheme.of(context).colors.onSurfaceVariantSummary,
                ),
              ),
            ),
            for (final item in recents)
              _MiuixTaskRow(
                item: item,
                onTap: () => Navigator.of(dialogCtx).pop(item.action),
              ),
          ],
        ],
      ),
    ),
  );
}

/// HyperOS 味道的可选行：卡片底 + 按下下沉（与 `MiuixLogFilterBar` 同一档
/// 反馈），图标 + 主文本 + 小字摘要。
///
/// 用 [MiuixGroupCard] 而不是 `MiuixArrowPreference`：后者尾部永远带「进去」
/// 的箭头，而这里的行都是就地执行的动作，不是下一级页面。
class _MiuixTaskRow extends StatelessWidget {
  const _MiuixTaskRow({required this.item, required this.onTap});

  final QuickTaskItem item;
  final VoidCallback onTap;

  static const Map<QuickTaskIcon, String> _miuixIconNames = {
    QuickTaskIcon.play: AppIconNames.play,
    QuickTaskIcon.pause: AppIconNames.pause,
    QuickTaskIcon.settings: AppIconNames.settings,
    QuickTaskIcon.folder: AppIconNames.folder,
  };

  static const Map<QuickTaskIcon, IconData> _miuixIconFallbacks = {
    QuickTaskIcon.play: Icons.play_arrow,
    QuickTaskIcon.pause: Icons.pause,
    QuickTaskIcon.settings: Icons.settings,
    QuickTaskIcon.folder: Icons.folder_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MiuixGroupCard(
        cornerRadius: 16,
        insideMargin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        feedbackType: MiuixPressFeedbackType.sink,
        onPressed: onTap,
        child: Row(
          children: [
            MiuixAppIcon(
              _miuixIconNames[item.icon]!,
              fallback: _miuixIconFallbacks[item.icon],
              size: 22,
              color: colors.onSurface,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MiuixText(item.title, fontSize: 16),
                  if (item.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    MiuixText(
                      item.subtitle,
                      fontSize: 12,
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
