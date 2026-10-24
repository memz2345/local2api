// lib/services/window_service.dart
//
// Windows 桌面端的「窗口 + 托盘」管家：
//   · 接管标题栏关闭按钮（WM_CLOSE → window_manager 的 setPreventClose），
//     按用户选的默认行为决定「收进托盘」还是「退出」；
//   · 托盘图标 + 右键菜单（显示主窗口 / 启动·停止服务 / 退出）；
//   · 第一次关闭（或设置里选了「每次询问」）时弹原生任务对话框问一句，
//     对话框底部带「下次也是这样」复选框，勾上就把这次的选择记成默认值。
//
// 为什么做成进程级单例而不是塞在某个 Widget 里：window_manager / tray_manager
// 的监听器挂在引擎上，页面重建不应该重复注册；而且询问框走的是**原生**任务
// 对话框（不经 Flutter 的 Navigator），窗口已经被系统要求关闭时照样弹得出来。
// 文案从 [AppLocalizations] 取 —— 需要 context 的地方统一找 [contextResolver]
// 要（根 Navigator 的 context；第一帧之前还没就绪，那时按已保存的行为执行）。
//
// 非 Windows 平台：整个服务退化为 no-op（[isSupported] 为 false），
// main.dart 侧不会 init，其它平台的流程完全不受影响。

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../src/enums.dart';
import 'server_controller.dart';
import 'settings_service.dart';
import 'tray_hint_service.dart';
import 'windows_task_dialog.dart';

/// 托盘图标的资源路径。
///
/// tray_manager 会把路径拼到 `<exe 目录>/data/flutter_assets/` 后面，所以这里
/// 写的就是 pubspec 里声明的 asset 路径本身（改了要同步改 pubspec 的 assets）。
const String kTrayIconAsset = 'assets/tray_icon.ico';

/// 桌面窗口 + 托盘管家（Windows 独占）。
class WindowService with WindowListener, TrayListener {
  WindowService._();

  static final WindowService instance = WindowService._();

  static bool get isSupported => Platform.isWindows;

  bool _initialized = false;

  SettingsService? _settings;
  ServerController? _controller;

  /// 根 Navigator 的 context（用来取本地化文案）。没就绪时返回 null。
  BuildContext? Function()? _contextResolver;

  /// 挂上行需在异步 init 之前调用 —— 托盘菜单里「启动/停止服务」要读控制器状态。
  void attach({
    required SettingsService settings,
    required ServerController controller,
    required BuildContext? Function() contextResolver,
  }) {
    _settings = settings;
    _controller = controller;
    _contextResolver = contextResolver;
    // 服务一启一停，托盘菜单里那行的标签要跟着换（菜单是每次打开前现算的）。
    controller.addListener(_refreshTrayMenu);
  }

  Future<void> init() async {
    if (!isSupported || _initialized) return;
    _initialized = true;

    try {
      await windowManager.ensureInitialized();
      // ⚠️ 必须配合 windows/runner/main.cpp 的 `SetQuitOnClose(false)`：
      // 原生层拿到 WM_CLOSE 就 PostQuitMessage 的话，Dart 这里的
      // onWindowClose 根本轮不到跑。
      await windowManager.setPreventClose(true);
      windowManager.addListener(this);
      trayManager.addListener(this);
      await trayManager.setIcon(kTrayIconAsset);
      await trayManager.setToolTip('Local2API');
      await _refreshTrayMenu();
    } catch (_) {
      // 插件没注册（widget test 里在 Windows 上跑就是这种情况）/ 图标资源缺失：
      // 桌面管家整体退化成 no-op，绝不能把冷启动拖崩。
      return;
    }
  }

  /// 托盘右键菜单。服务状态一变就重刷一次（标签跟着走）。
  ///
  /// 外部（app.dart 拿到 l10n 之后）也会调一次 —— 建菜单时根 Navigator 可能还
  /// 没挂起来，那时只能先用英文兜底，等本地化就绪再刷成用户语言。
  Future<void> refreshTrayMenu() => _refreshTrayMenu();

  Future<void> _refreshTrayMenu() async {
    final l10n = _l10n;
    try {
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(
              key: 'show',
              label: l10n?.winTrayShow ?? 'Show window',
              onClick: (_) => unawaited(showWindow()),
            ),
            MenuItem(
              key: 'toggle-service',
              label: _controller?.isRunning == true
                  ? (l10n?.shortcutStopService ?? 'Stop service')
                  : (l10n?.shortcutStartService ?? 'Start service'),
              onClick: (_) => unawaited(_toggleService()),
            ),
            MenuItem.separator(),
            MenuItem(
              key: 'quit',
              label: l10n?.winTrayQuit ?? 'Quit',
              onClick: (_) => unawaited(quitApp()),
            ),
          ],
        ),
      );
    } catch (_) {
      // 插件没注册（widget test 里在 Windows 上跑就是这种情况）：菜单刷不了
      // 就算了，绝不能把「服务状态一变就重刷菜单」这条链路变成未捕获异常。
    }
  }

  AppLocalizations? get _l10n {
    final context = _contextResolver?.call();
    if (context == null) return null;
    try {
      return AppLocalizations.of(context);
    } catch (_) {
      // context 已经卸载 / Localizations 还没挂上。
      return null;
    }
  }

  // ---- 窗口 ----

  /// 托盘图标被左键点：窗口藏了就恢复，没藏就提到最前。
  @override
  void onTrayIconMouseDown() => unawaited(showWindow());

  /// 右键：Windows 上 tray_manager **不会**自己弹菜单 —— 原生端的
  /// `WM_RBUTTONUP` 只发一个 `onTrayIconRightMouseDown` 事件，菜单得由 Dart
  /// 侧显式叫一次 `popUpContextMenu`。少了这一步，右键就是纯静音。
  @override
  void onTrayIconRightMouseDown() => unawaited(_popUpTrayMenu());

  Future<void> _popUpTrayMenu() async {
    try {
      // 打开前重算一次：服务可能刚被启停过，那行标签要跟着走。
      await _refreshTrayMenu();
      // bringAppToFront 在 Windows 上会先 SetForegroundWindow —— 少了它，
      // TrackPopupMenu 出来的菜单点空白处不会收起（Win32 的老毛病）。
      // ignore: deprecated_member_use
      await trayManager.popUpContextMenu(bringAppToFront: true);
    } catch (_) {
      // 没托盘 / 插件没注册：右键就当没发生。
    }
  }

  /// 菜单项点击后重刷一次菜单：切换服务开关时那行标签要跟着变。
  @override
  void onTrayMenuItemClick(MenuItem menuItem) =>
      unawaited(_refreshTrayMenu());

  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _toggleService() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.toggle();
    await _refreshTrayMenu();
  }

  Future<void> quitApp() async {
    try {
      await trayManager.destroy();
    } catch (_) {
      // 托盘压根没起来：无所谓。
    }
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    // 少数环境 destroy 之后消息循环还留着一口：兜一刀，别留僵尸进程。
    exit(0);
  }

  // ---- 关闭按钮 ----

  /// 点标题栏 X：window_manager 拦下 WM_CLOSE 后走这里。
  @override
  void onWindowClose() => unawaited(_handleClose());

  Future<void> _handleClose() async {
    switch (await _resolveCloseBehavior()) {
      // null = 用户把询问框关了（× / Esc / 点了遮罩）：**什么都不做**，
      // 窗口原样留着。曾经这里退回「收进托盘」，于是误点一下 × 窗口就没了，
      // 用户只能去托盘里翻 —— 「我明明只是关掉这个对话框」。
      case null:
        return;
      case WindowCloseBehavior.minimizeToTray:
        await windowManager.hide();
        await _refreshTrayMenu();
        await _maybeShowTrayHint();
      case WindowCloseBehavior.exit:
        await quitApp();
      case WindowCloseBehavior.ask:
        // 不会走到：内部已经把 ask 解析成具体动作。真到了就按「退出」兜底。
        await quitApp();
    }
  }

  /// 收进托盘后弹一条系统提示（「嘿嘿，我在这里哦」+ 不再提示 / 设置）。
  ///
  /// 窗口已经 hide 了，Flutter 画什么都看不见，所以只能走原生 WinRT Toast。
  /// 用户点「不再提示」后 [SettingsService.trayHintEnabled] 变 false，之后
  /// 静默收托盘。弹不出来（老系统 / 通道没注册）就算了 —— 这只是个提示。
  Future<void> _maybeShowTrayHint() async {
    final settings = _settings;
    if (settings == null || !settings.trayHintEnabled) return;
    final l10n = _l10n;
    if (l10n == null) return;
    await TrayHintService.instance.show(
      title: l10n.appTitle,
      body: l10n.trayHintBody,
      dismissLabel: l10n.trayHintDismiss,
      settingsLabel: l10n.trayHintSettings,
    );
  }

  /// 把对话框的返回值翻译成动作。抽成静态方法是为了能被单测钉住 ——
  /// “取消 = 什么都不做” 这条规则以前写错成 “取消 = 收进托盘”。
  @visibleForTesting
  static WindowCloseBehavior? resolveDialogOutcome(TaskDialogResult? picked) {
    if (picked == null) return null; // 取消：保持窗口原样
    return picked.index == 1
        ? WindowCloseBehavior.exit
        : WindowCloseBehavior.minimizeToTray;
  }

  /// 决定这次关闭怎么执行。
  ///
  /// 返回 null 表示「用户反悔了」——调用方必须什么都不做。
  ///
  /// [WindowCloseBehavior.ask] 会弹原生任务对话框；勾了「下次也是这样」就把
  /// 这次的选择落进 [SettingsService]，以后不再问。拿不到 l10n（根 Navigator
  /// 还没挂起来）时才退回「最小化到托盘」：那时连对话框都弹不出来，桌面常驻
  /// 工具既不替用户做「直接退出」这种不可逆决定，也不能让 X 完全失灵。
  Future<WindowCloseBehavior?> _resolveCloseBehavior() async {
    final settings = _settings;
    if (settings == null) return WindowCloseBehavior.exit;

    final saved = settings.windowCloseBehavior;
    if (saved != WindowCloseBehavior.ask) return saved;

    final l10n = _l10n;
    if (l10n == null) return WindowCloseBehavior.minimizeToTray;

    final picked = await WindowsTaskDialog.show(
      title: l10n.winCloseDialogTitle,
      heading: l10n.winCloseDialogHeading,
      content: l10n.winCloseDialogContent,
      verificationText: l10n.winCloseRemember,
      links: [
        (text: l10n.winCloseLinkTray, subtitle: l10n.winCloseLinkTraySubtitle),
        (text: l10n.winCloseLinkExit, subtitle: l10n.winCloseLinkExitSubtitle),
      ],
    );

    final behavior = resolveDialogOutcome(picked);
    if (behavior != null && picked!.verified) {
      await settings.setWindowCloseBehavior(behavior);
    }
    return behavior;
  }
}
