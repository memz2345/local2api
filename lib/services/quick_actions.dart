// lib/services/quick_actions.dart
//
// 「快捷任务」的公共层：动作词汇表 + 条目构造 + Windows 跳转列表发布。
//
// 三个入口共用同一套动作串，这样无论用户是从任务栏右键（Windows 跳转列表）、
// 桌面长按图标（安卓 App Shortcuts，见 app_shortcuts.dart）还是应用内的
// 「任务」对话框点进来，走的都是同一条分发：
//   server_start / server_pause / settings      ← 任务区
//   upstream:<id>                               ← 最近（当前的上游组）
//   token_stats / discover / toggle_server      ← 安卓 Shortcut 已有的三个
//
// 分发本身（要 push 页面、要切 tab）在 lib/ui/quick_actions_ui.dart —— 这层
// 不碰 ui，与仓库里其它 service 一致。

import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/jump_list_service.dart';
import 'package:local2api/services/server_controller.dart';

/// 动作词汇表。⚠️ 值会被写进 Windows 跳转列表的命令行
/// （`--l2a-action=<值>`）与安卓 Shortcut 的 extra，改了旧条目会在用户
/// 下次重发清单前失效，动它们前想清楚。
abstract final class QuickAction {
  static const String serverStart = 'server_start';
  static const String serverPause = 'server_pause';
  static const String settings = 'settings';

  /// 上游组条目：`upstream:<Upstream.id>`。
  static const String upstreamPrefix = 'upstream:';

  // ---- 安卓 App Shortcuts 已有的三个 id（app_shortcuts.dart / ShortcutHost.kt） ----
  static const String legacyToggle = 'toggle_server';
  static const String tokenStats = 'token_stats';
  static const String discover = 'discover';

  // ---- 托盘提示 Toast 的两个按钮（windows/runner/tray_toast.cpp 里的
  //      arguments 必须与这两个值逐字一致） ----
  /// 不再提示：关掉托盘提示，本动作不需要打开窗口。
  static const String trayHintOff = 'tray_hint_off';

  /// 设置：把窗口叫回来并跳到显示设置的「桌面窗口」区。
  static const String trayHintSettings = 'tray_hint_settings';

  static String upstream(String id) => '$upstreamPrefix$id';

  /// 是上游组条目则返回它的 id，否则 null。
  static String? upstreamIdOf(String action) =>
      action.startsWith(upstreamPrefix) && action.length > upstreamPrefix.length
      ? action.substring(upstreamPrefix.length)
      : null;
}

/// 条目的图标槽：service 层不 import flutter_miuix，两套 UI 各自映射。
enum QuickTaskIcon { play, pause, settings, folder }

/// 「任务」对话框 / 跳转列表里的一行。
class QuickTaskItem {
  const QuickTaskItem({
    required this.action,
    required this.title,
    required this.icon,
    this.subtitle = '',
  });

  final String action;

  /// 主文本（跳转列表显示它，TaskDialog 命令链接的第一行也是它）。
  final String title;

  /// 副标题（命令链接的小字那行 / Flutter 对话框的摘要）。
  final String subtitle;

  final QuickTaskIcon icon;

  /// Material 侧的图标。
  IconData get materialIcon => switch (icon) {
    QuickTaskIcon.play => Icons.play_arrow_rounded,
    QuickTaskIcon.pause => Icons.pause_rounded,
    QuickTaskIcon.settings => Icons.settings_outlined,
    QuickTaskIcon.folder => Icons.folder_open_rounded,
  };

  JumpListItem toJumpListItem() => JumpListItem(
    name: title,
    action: action,
    subtitle: subtitle,
  );
}

/// 任务区三项：启动服务 / 暂停服务 / 设置。
///
/// 「启动」和「暂停」同时在场而不是只给当前需要的那一个：跳转列表与命令链接
/// 的条目一旦写进 Windows 就是静态的，等到状态变了再重发就晚了（用户点的
/// 正是上一份清单）；分发侧两个动作都是幂等的，多点一次没有副作用。
List<QuickTaskItem> quickTaskItems(
  AppLocalizations l10n,
  ServerController controller,
) {
  final cfg = controller.config;
  final address = '${cfg.listenHost}:${cfg.listenPort}';
  return [
    QuickTaskItem(
      action: QuickAction.serverStart,
      title: l10n.startServer,
      subtitle: l10n.taskListenOn(address),
      icon: QuickTaskIcon.play,
    ),
    QuickTaskItem(
      action: QuickAction.serverPause,
      title: l10n.taskPauseServer,
      subtitle: l10n.taskStopListening,
      icon: QuickTaskIcon.pause,
    ),
    QuickTaskItem(
      action: QuickAction.settings,
      title: l10n.navSettings,
      icon: QuickTaskIcon.settings,
    ),
  ];
}

/// 「最近」区 = 当前的上游组（模型组），按配置里的顺序，最多 5 条。
///
/// 上限是 Windows 跳转列表的规矩（NaviFlash 同款：再多任务栏菜单放不下）。
List<QuickTaskItem> quickRecentItems(AppLocalizations l10n, ProxyConfig cfg) {
  return [
    for (final up in cfg.upstreams.take(5))
      QuickTaskItem(
        action: QuickAction.upstream(up.id),
        title: up.name.isEmpty ? up.baseUrl : up.name,
        subtitle: l10n.tasksModelCount(up.models.length),
        icon: QuickTaskIcon.folder,
      ),
  ];
}

/// 把「任务 + 最近」写进 Windows 跳转列表。
///
/// 调用时机：上游清单或监听参数一变就重发（ServerController 是 ChangeNotifier，
/// app.dart 挂个监听即可）。非 Windows 直接空转。
Future<bool> publishWindowsJumpList(
  AppLocalizations l10n,
  ServerController controller,
) async {
  if (!JumpListService.isSupported) return false;
  final tasks = quickTaskItems(l10n, controller);
  final recents = quickRecentItems(l10n, controller.config);
  return JumpListService.instance.update(
    recentTitle: l10n.tasksRecentSection,
    tasks: [for (final t in tasks) t.toJumpListItem()],
    recents: [for (final r in recents) r.toJumpListItem()],
  );
}
