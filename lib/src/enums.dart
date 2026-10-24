enum LoadingIndicatorM3EVariant { defaultStyle, contained }

/// 全局界面风格。对应 InstallerX 的 `showMiuixUI` 开关：
/// 同一个页面写两份实现，根处按这个值二选一。
enum UiStyle {
  /// Material 3 Expressive：液态玻璃底栏、形变加载指示器、iOS 推入转场。
  materialExpressive,

  /// 小米 HyperOS（默认）：squircle 圆角、Folme 弹簧、MiuixTopAppBar / NavigationBar。
  miuix,
}

extension UiStyleX on UiStyle {
  String get id => switch (this) {
    UiStyle.materialExpressive => 'material',
    UiStyle.miuix => 'miuix',
  };

  /// 没存过（全新安装）走默认的 miuix；存过的两个 id 各自认回来 ——
  /// 别把兜底写成 material，否则老用户选的 miuix 会被读成 material。
  static UiStyle fromId(String? id) => switch (id) {
    'material' => UiStyle.materialExpressive,
    _ => UiStyle.miuix,
  };

  bool get isMiuix => this == UiStyle.miuix;
}

/// Windows 下点标题栏「关闭」按钮的默认动作。
///
/// 桌面常驻型工具程序的标准三选一：每次问（默认）/ 直接收进托盘 / 直接退出。
/// 只有 [ask] 会弹那个原生任务对话框（带「下次也是这样」复选框），把其中一个
/// 勾上并记住之后就不再问了 —— 用户随时能在设置里改回来。
enum WindowCloseBehavior {
  /// 每次都问一次（默认）。
  ask,

  /// 收进托盘：窗口隐藏、转发服务照常跑，点托盘图标叫回来。
  minimizeToTray,

  /// 退出整个程序。
  exit,
}

/// 内置浏览器的 UA 档位（自 NaviFlash browser_page 移植）。
///
/// [auto] 用 webview 自己的 UA；[desktop] / [mobile] 只替换 UA 里的平台段与
/// Mobile 标记，不动 Chrome/WebKit 版本号 —— 很多站点靠版本号判能力，
/// 整串换掉反而会掉到「不支持的浏览器」页。
enum BrowserUaMode {
  auto,
  desktop,
  mobile;

  String get id => switch (this) {
    BrowserUaMode.auto => 'auto',
    BrowserUaMode.desktop => 'desktop',
    BrowserUaMode.mobile => 'mobile',
  };

  static BrowserUaMode fromId(String? id) => switch (id) {
    'desktop' => BrowserUaMode.desktop,
    'mobile' => BrowserUaMode.mobile,
    _ => BrowserUaMode.auto,
  };
}
