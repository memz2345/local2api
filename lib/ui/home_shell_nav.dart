/// 首页 shell 的导航状态，**跨 UI 引擎、也跨窄/宽两种布局共享**。
///
/// 两件会让本地 State 归零的事都在这里兜底：
/// 1. 切换界面风格会把 HomeShell / MiuixHomeShell 整棵换掉（两套渲染各写一份），
///    本地 State 里的 tab 位置当场归零 —— 表现就是「一切换风格就跳回仪表盘页」。
///    照 InstallerX 的做法把 tab 位置提到页面外面（它家是
///    `SettingsSharedViewModel.lastMainPageIndex`，重建时
///    `rememberPagerState(initialPage: ...)` 读回来），换引擎就还在原地。
/// 2. 横竖屏切换会让窄屏的底栏壳（HomeShell / MiuixHomeShell）换成宽屏的
///    侧栏壳（SideBarShell / MiuixSideBarShell）—— 也是两棵独立的 State。
///    侧栏壳原来各自把 `_index` 写死成 0，一转横屏就跳回仪表盘。
///
/// 所以：**凡是要展示/修改「当前是一级页第几个 tab」的地方，一律读写这里**，
/// 别在各自的 State 里再存一份。
///
/// [pagePixels] 是各 tab 的滚动位移，同理一起挪出来。
class HomeShellNav {
  HomeShellNav._();

  /// 一级 tab 总数（仪表盘 / 发现 / 设置）。窄屏壳、侧栏壳与外部动作
  /// （安卓 Shortcut、Windows 跳转列表）分发 tab 请求时都按这个上限校验。
  static const int tabCount = 3;

  /// 当前选中的 tab 下标（0 = 仪表盘 / 1 = 发现 / 2 = 设置）。
  static int index = 0;

  /// 各 tab 页自己的滚动位置（逻辑像素）。
  static final Map<int, double> pagePixels = <int, double>{};
}
