import 'dart:async';
import 'dart:io';

import 'package:flex_seed_scheme/flex_seed_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/app_locale_bridge.dart';
import 'package:local2api/services/app_settings.dart';
import 'package:local2api/services/biometric_service.dart';
import 'package:local2api/services/app_shortcuts.dart';
import 'package:local2api/services/device_corner_service.dart';
import 'package:local2api/services/jump_list_service.dart';
import 'package:local2api/services/lab/dsh_service.dart';
import 'package:local2api/services/lab/dsh_task_center.dart';
import 'package:local2api/services/lab/dsh_windows_toast.dart';
import 'package:local2api/services/liquid_glass_bar_service.dart';
import 'package:local2api/services/quick_actions.dart'
    show publishWindowsJumpList;
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/services/window_service.dart';
import 'package:local2api/src/app_dynamic_color.dart';
import 'package:local2api/src/enums.dart';
import 'package:local2api/src/theme_seed_ext.dart';
import 'package:local2api/widgets/xiaomi_freeform_media_query.dart';
import 'package:local2api/widgets/biometric_gate.dart';
import 'package:local2api/widgets/custom_toast.dart';
import 'package:local2api/widgets/edge_scroll_haptic.dart';
import 'package:local2api/widgets/global_mouse_back.dart';
import 'package:local2api/widgets/miuix/miuix_overscroll.dart';
import 'package:local2api/ui/quick_task_actions.dart' show dispatchQuickAction;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'home_shell.dart';
import 'miuix/miuix_home_shell.dart';
import 'miuix/miuix_material_bridge.dart';

/// 根组件：MaterialApp + l10n + 动态取色/种子色主题 + 显示缩放 + toast。
///
/// 界面风格（[UiStyle]）在这里分流：Material 3 Expressive 走原来的
/// 动态取色/种子色那一套；小米 HyperOS 由 MiuixThemeController 解析配色，
/// 再经 [materialSchemeFromMiuix] 搭桥喂给 ThemeData，好让还没迁到 miuix
/// 实现的页面配色不打架。
class Local2ApiApp extends StatefulWidget {
  const Local2ApiApp({
    super.key,
    required this.settings,
    required this.controller,
  });

  final AppSettings settings;
  final ServerController controller;

  @override
  State<Local2ApiApp> createState() => _Local2ApiAppState();
}

class _Local2ApiAppState extends State<Local2ApiApp>
    with WidgetsBindingObserver {
  /// 根 Navigator key：鼠标侧键 / ESC 全局回退用（GlobalMouseBackWrapper）。
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  bool _shortcutsWired = false;
  bool _shortcutsRetryScheduled = false;
  int _shortcutsRetries = 0;

  /// 系统的深/浅色（[didChangePlatformBrightness] 同步刷新）。
  ///
  /// 这是「跟随系统」的第二条保险：[MediaQuery] 那条继承依赖没搭上（某些桌面
  /// 回落 / 测试壳里没有 MediaQuery）时，观察者这条也能把新亮度带进来。
  Brightness _systemBrightness = Brightness.light;

  // ---- 生物识别锁（Hail 同款应用锁） ----
  final BiometricService _biometric = BiometricService();

  /// 锁定中：整棵 MaterialApp 的内容换成 [BiometricGate]。
  ///
  /// **只在冷启动（进程新起）时置位** —— 对齐 Hail 的 MainActivity：
  /// 验证只在 onCreate 发起一次，onStop 里那句 `finishAndRemoveTask()`
  /// 是注释掉的。所以切后台、切屏、从最近任务回来都**不再**上锁；只有进程
  /// 被系统回收后重新打开才要再验一次。「进后台切个屏就要识别」正是把
  /// 上锁挂到 paused/hidden 上的后果。
  bool _biometricLocked = false;

  /// 系统验证框挂着时，暂停/恢复事件（尤其回落 PIN / 图案的独立页面）
  /// 不再翻锁定标记，免得取消后跟 Resume 互相触发重弹。
  bool _biometricPrompting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.settings.addListener(_onSettings);
    _systemBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    // Windows：桌面窗口管家（托盘 + 关闭按钮接管）。挂在 initState 里：
    // 托盘菜单要显示服务状态，第一帧就可能用到，不等到 runApp 之后。
    if (WindowService.isSupported) {
      WindowService.instance.attach(
        settings: context.read<SettingsService>(),
        controller: widget.controller,
        contextResolver: () => _navigatorKey.currentContext,
      );
      unawaited(WindowService.instance.init());
    }
    // Windows：dsh 系统通知的事件通道要在任何任务/会话开始前挂好。
    // 文案与输入框占位由 dsh 页面在拿到 l10n 后再注入一次。
    if (DshWindowsToast.isSupported) {
      unawaited(DshWindowsToast.instance.init());
      // web 会话的「打开」按钮：页面没开着时也能用 dsh 启动日志里的令牌地址。
      DshTaskCenter.instance.onOpenWeb ??= () {
        final dsh = DshService.instance;
        if (!dsh.running) return;
        final url = dsh.openUrl;
        if (url.isEmpty) return;
        unawaited(
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        );
      };
    }
    // Windows 任务栏跳转列表：先注册热推送 handler，再领冷启动参数（顺序反了
    // 冷启动动作可能早于 handler 到达而丢，见 jump_list_service.dart）。
    if (JumpListService.isSupported) {
      JumpListService.instance.onAction = _handleQuickAction;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_initWindowsJumpList());
      });
    }
    // 冷启动（进程新起）才上锁：首帧直接出门禁页（门禁自己会再弹验证）。
    // 进程活着期间不再上锁 —— 从后台回来、切屏都不用再验。
    // 锁开关挂在 SettingsService（外观设置）上，不在 AppSettings。
    if (Platform.isAndroid || Platform.isIOS) {
      final lockEnabled = context.read<SettingsService>().biometricLock;
      if (lockEnabled) _biometricLocked = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_shortcutsWired) {
      _shortcutsWired = true;
      // 服务状态一变就重发 Shortcut 清单（「启动/关闭服务」标签跟状态走）
      widget.controller.addListener(_publishShortcuts);
      _publishShortcuts();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回到前台（含冷启动 / 从 Shortcut 点进来）：取走暂存的 Shortcut 动作
    if (state == AppLifecycleState.resumed) _handlePendingShortcut();
    // 这里**不**上锁：应用锁只在冷启动生效（见 [_biometricLocked]）。
    // 切后台 / 回到前台都要验一次的话，切屏、看通知、拉个分享都会撞上
    // 验证框 —— Hail 自己也没这么做。
  }

  /// 发起一次生物识别验证；通过即解锁。失败保持门禁页（手动重试）。
  Future<void> _runBiometricAuth() async {
    if (_biometricPrompting || !_biometricLocked) return;
    _biometricPrompting = true;
    final navContext = _navigatorKey.currentContext;
    final l10n = navContext == null ? null : AppLocalizations.of(navContext);
    final ok = await _biometric.authenticate(
      l10n?.biometricGateHint ?? 'Unlock Local2API',
    );
    _biometricPrompting = false;
    if (!mounted) return;
    if (ok) setState(() => _biometricLocked = false);
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    if (brightness == _systemBrightness) return;
    // 「跟随系统」时这一下就是主题模式变了：miuix 的配色是单份（明或暗），
    // 不重算的话 MaterialApp 的 themeMode 会停在上一次那份上。
    setState(() => _systemBrightness = brightness);
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    super.didChangeLocales(locales);
    _syncSystemLocale();
  }

  /// 系统「应用信息 → 语言」被改动时的热同步。manifest 里
  /// `configChanges=locale` 让 Activity 不重建（转场/状态得以保留），
  /// 但 MaterialApp 的 locale 钉在设置里 —— 不同步的话，系统里换语言要
  /// 杀掉重开才生效。应用内手动选过语言时 syncFromSystemLocaleCode 自己
  /// 会跳过（手动选择优先）；清掉系统里的应用语言则回到「跟随系统」。
  Future<void> _syncSystemLocale() async {
    final tag = await AppLocaleBridge.getSystemAppLocale();
    if (!mounted) return;
    widget.settings.syncFromSystemLocaleCode(tag);
  }

  /// 安卓长按快捷入口的标签与分发。
  ///
  /// 同一个监听也负责 Windows 的任务栏跳转列表：两处都是「入口清单」，
  /// 内容都跟着服务状态 / 上游组变化，没必要分两个订阅。
  ///
  /// 注意 l10n 必须经根 Navigator 的 context 取——本 State 挂在
  /// MaterialApp 之上，直接 AppLocalizations.of(context) 是 null。
  Future<void> _publishShortcuts() async {
    if (!mounted) return;
    final navContext = _navigatorKey.currentContext;
    final l10n = navContext == null ? null : AppLocalizations.of(navContext);
    if (l10n == null) {
      // Navigator 还没挂起来（首帧前监听就触发了）：下一帧再试，最多 3 帧，
      // 避免异常环境（无 Localizations 的测试壳）里空转。
      if (_shortcutsRetryScheduled || _shortcutsRetries >= 3) return;
      _shortcutsRetryScheduled = true;
      _shortcutsRetries++;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _shortcutsRetryScheduled = false;
        if (mounted) _publishShortcuts();
      });
      return;
    }
    _shortcutsRetries = 0;
    // l10n 到手 = 根 Navigator 挂好了：托盘菜单这时重刷一次才能拿到本地化文案
    // （建托盘时大概率还早，那份先用英文兜底）。
    if (WindowService.isSupported) {
      unawaited(WindowService.instance.refreshTrayMenu());
    }
    await AppShortcuts.instance.publish(
      toggleLabel: widget.controller.isRunning
          ? l10n.shortcutStopService
          : l10n.shortcutStartService,
      statsLabel: l10n.shortcutTokenStats,
      discoverLabel: l10n.navDiscover,
    );
    await publishWindowsJumpList(l10n, widget.controller);
  }

  /// Windows：注册热推送通道 + 领取冷启动暂存的动作。
  Future<void> _initWindowsJumpList() async {
    final service = JumpListService.instance;
    await service.init();
    final action = await service.consumeLaunchAction();
    if (action != null && action.isNotEmpty) _handleQuickAction(action);
  }

  /// 外部入口（Windows 跳转列表 / 安卓 Shortcut）的动作统一入口。
  ///
  /// [Navigator] 还没挂起来时不能直接路由：推迟到下一帧再试，否则这次点击
  /// 会被静默丢掉（表现就是「点了任务栏菜单没反应」）。
  void _handleQuickAction(String action, {int retries = 0}) {
    final navContext = _navigatorKey.currentContext;
    if (navContext == null) {
      if (retries >= 3) {
        debugPrint('⚠️ Navigator 仍不可用，丢弃快捷动作: $action');
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handleQuickAction(action, retries: retries + 1);
      });
      return;
    }
    unawaited(dispatchQuickAction(navContext, widget.controller, action));
  }

  Future<void> _handlePendingShortcut() async {
    final id = await AppShortcuts.instance.takePending();
    if (id == null || !mounted) return;
    _handleQuickAction(id);
  }

  void _onSettings() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.settings.removeListener(_onSettings);
    widget.controller.removeListener(_publishShortcuts);
    super.dispose();
  }

  /// zh-HK/zh-MO → 繁体资源；其余走 Flutter 默认解析。
  Locale? _resolve(List<Locale>? locales, Iterable<Locale> supported) {
    if (locales == null || locales.isEmpty) return null;
    final first = locales.first;
    if (first.languageCode.toLowerCase() == 'zh') {
      final region = first.countryCode?.toUpperCase();
      if (region == 'HK' || region == 'MO') return const Locale('zh', 'TW');
      return const Locale('zh', 'CN');
    }
    return basicLocaleListResolution(locales, supported);
  }

  @override
  Widget build(BuildContext context) {
    return AppDynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return Consumer<SettingsService>(
          builder: (context, settings, child) {
            // ⚠️ 两支必须**同形**：外面都是 MiuixThemeController、里面都是
            // _materialApp(...)。返回类型一变，MaterialApp 就整棵卸载重建，
            // Navigator 的路由栈当场清空 —— 这是「一切换风格就回到仪表盘页」
            // 的一半根因（另一半是首页 tab 位置归零，见 HomeShellNav）。
            // InstallerX 的做法也是「一份路由栈摆在引擎分支之上」：
            // 换引擎只换叶子上渲染哪一套，back stack 根本不动。
            // 「自定义颜色」关掉且没开系统动态取色时，走 miuix 的**静态出厂
            // 配色**（HyperOS 蓝）—— 对应 InstallerX `useMiuixMonet=false` 的
            // Default Miuix Theme Path；其余情况走 monet：有种子用种子，
            // 留空 miuix 才会去读 Android 壁纸。
            // Material 分支不读这个开关（见 _buildMaterialApp），互不影响。
            final customColors = settings.useCustomThemeColors;
            final miuixMonet = customColors || settings.useDynamicColor;

            // ── 明暗（先在外面解析成确定值）──
            // 原来把 ThemeMode.system 原样丢给 MiuixThemeController（isDark=null
            // 让它自己去读 MediaQuery），而下面 MaterialApp 的 themeMode 又是
            // 拿 MiuixTheme.brightness 反推出来的 —— 两边各判一次，系统亮度变
            // 了只要有一边没跟着重算，就是「一半变了、一半没变」（配色对了、
            // 但没迁页的主题还停在老的那份）。现在外面只定一份，两边读同一个值。
            final systemBrightness =
                MediaQuery.maybeOf(context)?.platformBrightness ??
                _systemBrightness;
            final dark = switch (settings.themeMode) {
              ThemeMode.light => false,
              ThemeMode.dark => true,
              ThemeMode.system => systemBrightness == Brightness.dark,
            };

            // ── 跟随系统配色 ──
            // flutter_miuix 自己那趟平台取色（keyColor 为空时走的
            // miuixPlatformDynamicColors）调的是 DynamicColorPlugin
            // .getAccentColor()，而它的原生实现只有 macOS 10.14+ /
            // Windows Vista+ / GTK —— Android 侧的 Kotlin 插件只认
            // getCorePalette，OptionalMethodChannel 对没实现的方法直接回 null，
            // 于是安卓上永远掉回 miuix 的固定种子 0xFF6750A4，表现就是
            // 「跟随系统配色」开了跟没开一个样。
            // 这里把 AppDynamicColorBuilder 已经拿到的系统取色直接喂给
            // keyColor：非空时 MiuixThemeController 走同步的 HCT 计算，
            // 不再碰那条在安卓上必然失效的异步取色。
            final systemScheme = settings.useDynamicColor
                ? (dark ? darkDynamic : lightDynamic)
                : null;
            final miuixKeyColor = systemScheme?.primary ??
                (miuixMonet && !settings.useDynamicColor
                    ? settings.themeSeedColor
                    : null);

            return MiuixThemeController(
              colorSchemeMode: miuixMonet
                  ? miuixColorSchemeModeOf(themeMode: settings.themeMode)
                  : miuixDefaultColorSchemeModeOf(
                      themeMode: settings.themeMode,
                    ),
              keyColor: miuixKeyColor,
              paletteStyle: miuixPaletteStyleOf(
                customColors
                    ? settings.schemeVariant
                    : FlexSchemeVariant.tonalSpot,
              ),
              textStyles: _miuixTextStyles,
              fontWeightAdjustment: miuixFontWeightAdjustmentOf(
                settings.fontWeight,
              ),
              // isDark 给确定值：上面已经把 ThemeMode.system 解析过了，留空
              // 让它再判一次只会多一处错位的机会。
              isDark: dark,
              child: Builder(
                builder: (context) => settings.uiStyle.isMiuix
                    ? _buildMiuixApp(context, settings, dark)
                    : _buildMaterialApp(settings, lightDynamic, darkDynamic),
              ),
            );
          },
        );
      },
    );
  }

  // ---- Material 3 Expressive ----

  Widget _buildMaterialApp(
    SettingsService settings,
    ColorScheme? lightDynamic,
    ColorScheme? darkDynamic,
  ) {
    final useDynamic =
        settings.useDynamicColor && lightDynamic != null && darkDynamic != null;

    final lightScheme = useDynamic
        ? lightDynamic
        : settings.themeSeedColor.asColorSchemeSeed(
            settings.schemeVariant,
            Brightness.light,
          );
    final darkScheme = useDynamic
        ? darkDynamic
        : settings.themeSeedColor.asColorSchemeSeed(
            settings.schemeVariant,
            Brightness.dark,
          );

    // 转场圆角：自动跟随设备物理屏幕圆角（读不到就用手动值）。见
    // DeviceCornerService —— 只影响圆角，速率 / 压暗 / 曲线不动。
    final corner = DeviceCornerService.resolveFor(settings);

    return _materialApp(
      theme: _theme(
        AppTheme.light(cornerRadius: corner),
        lightScheme,
        settings.fontWeight,
      ),
      darkTheme: _theme(
        AppTheme.dark(cornerRadius: corner),
        settings.isPureBlackMode ? _pureBlack(darkScheme) : darkScheme,
        settings.fontWeight,
      ),
      themeMode: settings.themeMode,
      displayScale: settings.displayScale,
    );
  }

  // ---- 小米 HyperOS ----

  /// MiuixThemeController 只解析出**一份**配色（明或暗，由它自己按 isDark /
  /// 系统亮度决定），所以 MaterialApp 的 themeMode 要跟着它走，
  /// 不能再拿 settings.themeMode 去二次判定，否则两边会打架。
  /// [dark] 是外层按「主题模式 + 系统亮度」解析出来的结果，两边共用同一个值。
  Widget _buildMiuixApp(
    BuildContext context,
    SettingsService settings,
    bool dark,
  ) {
    final miuix = MiuixTheme.of(context);
    if (dark != (miuix.brightness == Brightness.dark)) {
      // 理论上不会发生：出现说明 MiuixThemeController 没跟上外面那份明暗，
      // 记一句比默默用错配色好排查。
      assert(() {
        debugPrint(
          '⚠️ miuix brightness 与外层解析不一致：theme=${settings.themeMode} '
          'outer=${dark ? 'dark' : 'light'} inner=${miuix.brightness}',
        );
        return true;
      }());
    }
    var scheme = materialSchemeFromMiuix(miuix.colors, miuix.brightness);
    if (dark && settings.isPureBlackMode) scheme = _pureBlack(scheme);

    // 转场圆角同 Material 分支：设备屏幕圆角优先，读不到用手动值。
    final corner = DeviceCornerService.resolveFor(settings);
    final base = dark
        ? AppTheme.dark(cornerRadius: corner)
        : AppTheme.light(cornerRadius: corner);
    // 输入装饰归零：AppTheme 那套 filled/fillColor 会漏进 MiuixTextField 内层的
    // Material TextField，在 miuix 自己的底色上再糊一层灰（见常量注释）。
    final theme = _theme(
      base,
      scheme,
      settings.fontWeight,
    ).copyWith(inputDecorationTheme: kMiuixNeutralInputDecoration);

    return _materialApp(
      theme: theme,
      darkTheme: theme,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      displayScale: settings.displayScale,
      // 越界换成 miuix 的「整体位移 + 阻尼 + 弹簧回位」，不用 Material 的纵向拉伸
      scrollBehavior: const MiuixOverscrollBehavior(),
    );
  }

  // ---- 公共 ----

  ThemeData _theme(ThemeData base, ColorScheme scheme, double fontWeight) {
    // 注意：copyWith(textTheme:) 是整体替换，裸 TextStyle（无 color）
    // 会丢掉 ThemeData 上色管线的结果（文字变白）。
    // 正确做法：在主题已解析的带色 TextTheme 上只改字重。
    return base
        .copyWith(colorScheme: scheme)
        .copyWith(textTheme: _applyWeight(base.textTheme, fontWeight));
  }

  static TextTheme _applyWeight(TextTheme t, double fontWeight) {
    FontWeight w() {
      if (fontWeight <= 100) return FontWeight.w100;
      if (fontWeight <= 200) return FontWeight.w200;
      if (fontWeight <= 300) return FontWeight.w300;
      if (fontWeight <= 400) return FontWeight.w400;
      if (fontWeight <= 500) return FontWeight.w500;
      if (fontWeight <= 600) return FontWeight.w600;
      if (fontWeight <= 700) return FontWeight.w700;
      if (fontWeight <= 800) return FontWeight.w800;
      return FontWeight.w900;
    }

    final weight = w();
    return t.copyWith(
      bodyLarge: t.bodyLarge?.copyWith(fontWeight: weight),
      bodyMedium: t.bodyMedium?.copyWith(fontWeight: weight),
      bodySmall: t.bodySmall?.copyWith(fontWeight: weight),
      titleLarge: t.titleLarge?.copyWith(fontWeight: weight),
      titleMedium: t.titleMedium?.copyWith(fontWeight: weight),
      titleSmall: t.titleSmall?.copyWith(fontWeight: weight),
      labelLarge: t.labelLarge?.copyWith(fontWeight: weight),
      labelMedium: t.labelMedium?.copyWith(fontWeight: weight),
      labelSmall: t.labelSmall?.copyWith(fontWeight: weight),
    );
  }

  /// miuix 文本样式，**行高全部钉住**成外层 Material 正文的行高。
  ///
  /// 为什么必须钉：`MiuixTopAppBar` 用 `TextPainter` 单独量一次大标题高度，
  /// 拿它当大标题层的 `ClipRect` 高度；而真正渲染的 `Text` 还会跟外层
  /// `DefaultTextStyle` 合并 —— 顶栏内部那个 `Material` 会把 DefaultTextStyle
  /// 设成 `theme.textTheme.bodyMedium`（Material 3 带 `height: 1.43`）。
  /// miuix 的 `title1`（32sp）本身没有 height，于是合并后真实行高变成
  /// 32 × 1.43 ≈ 45.8，而 TextPainter 量到的是字体自然行高
  /// 32 × 1.172 ≈ 37.5 —— 底部约 4px 被 ClipRect 切掉，正好切到 p / y
  /// 这类字母的下伸部（「Display」的尾巴就是这么没的）。
  ///
  /// 给 miuix 各样式显式写上同一个 height，测量与渲染就一致了；视觉零变化
  /// （本来合并后就是这个值），只是不再被裁。
  static final MiuixTextStyles _miuixTextStyles = _buildMiuixTextStyles();

  static MiuixTextStyles _buildMiuixTextStyles() {
    final h = AppTheme.light().textTheme.bodyMedium?.height ?? 1.43;
    final d = defaultTextStyles();
    return d.copy(
      main: d.main.copyWith(height: h),
      paragraph: d.paragraph.copyWith(height: h),
      body1: d.body1.copyWith(height: h),
      body2: d.body2.copyWith(height: h),
      button: d.button.copyWith(height: h),
      footnote1: d.footnote1.copyWith(height: h),
      footnote2: d.footnote2.copyWith(height: h),
      headline1: d.headline1.copyWith(height: h),
      headline2: d.headline2.copyWith(height: h),
      subtitle: d.subtitle.copyWith(height: h),
      title1: d.title1.copyWith(height: h),
      title2: d.title2.copyWith(height: h),
      title3: d.title3.copyWith(height: h),
      title4: d.title4.copyWith(height: h),
    );
  }

  static ColorScheme _pureBlack(ColorScheme scheme) => scheme.copyWith(
    surface: Colors.black,
    surfaceDim: Colors.black,
    surfaceContainerLowest: Colors.black,
    surfaceContainerLow: Colors.black,
    surfaceContainer: Colors.black,
    surfaceContainerHigh: Colors.black,
    surfaceContainerHighest: const Color(0xFF1C1C1E),
    surfaceTint: Colors.transparent,
  );

  Widget _materialApp({
    required ThemeData theme,
    required ThemeData darkTheme,
    required ThemeMode themeMode,
    required double displayScale,
    ScrollBehavior? scrollBehavior,
  }) {
    return MaterialApp(
      title: 'Local2API',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      scrollBehavior: scrollBehavior,
      locale: widget.settings.locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('zh', 'TW'),
        Locale('zh'),
        Locale('en', 'US'),
        Locale('en'),
      ],
      localeListResolutionCallback: _resolve,
      navigatorKey: _navigatorKey,
      navigatorObservers: [
        liquidGlassBarRouteObserver,
        FlutterSmartDialog.observer,
      ],
      builder: FlutterSmartDialog.init(
        toastBuilder: CustomToast.new,
        builder: (context, child) {
          // 生物识别锁（Hail 同款）：锁定期间整棵界面换成门禁页 ——
          // 底下不渲染任何业务内容，最近任务的截图也是锁屏。门禁出现时
          // 自动弹一次系统验证，取消 / 失败停在门禁页手动重试。
          // 锁定只发生在冷启动（进程新起），回前台不重复验证。
          if (_biometricLocked) {
            return BiometricGate(onRetry: _runBiometricAuth);
          }
          if (child == null) return const SizedBox.shrink();
          // 全局鼠标/键盘操作（鼠标侧键 / ESC 回退，自 NaviFlash 移植），
          // 以及外观开关控制的「快速滑动碰边」震动。
          final hapticOn = context.watch<SettingsService>().edgeScrollHaptic;
          final Widget content = GlobalMouseBackWrapper(
            navigatorKey: _navigatorKey,
            child: hapticOn ? EdgeScrollHaptic(child: child) : child,
          );
          // 小米 HyperOS2 + Android 15 小窗(freeform)下 MediaQuery.padding.top 会
          // 返回离谱值（640/737…，flutter#161086 Open），SafeArea 会把整页挤下去。
          // **先兜底修正，再走显示缩放** —— 顺序反了会把异常值一起放大。
          final raw = MediaQuery.of(context);
          final mq = sanitizeXiaomiFreeformPadding(raw);
          // 不需要缩放、padding 也没被修正过时直通，避免无谓的包裹层
          if (displayScale == 1.0 && identical(mq, raw)) return content;
          final scaledChild = MediaQuery(
            data: mq.copyWith(
              textScaler: TextScaler.noScaling,
              size: mq.size / displayScale,
              padding: mq.padding / displayScale,
              viewPadding: mq.viewPadding / displayScale,
              viewInsets: mq.viewInsets / displayScale,
            ),
            child: Transform.scale(
              scale: displayScale,
              alignment: Alignment.topLeft,
              child: Stack(fit: StackFit.expand, children: [content]),
            ),
          );

          return Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 0,
                width: mq.size.width / displayScale,
                height: mq.size.height / displayScale,
                child: scaledChild,
              ),
            ],
          );
        },
      ),
      home: _StyledHome(
        material: HomeShell(
          controller: widget.controller,
          settings: widget.settings,
        ),
        miuix: MiuixHomeShell(
          controller: widget.controller,
          settings: widget.settings,
        ),
      ),
    );
  }
}

/// 首页：两套 shell 在**同一个位置**换，类型恒定，路由栈不动。
///
/// 对应 InstallerX `InstallerNavContainer` 里「`entry<Route.Main>` 里
/// if (useMiuix) MiuixXxx() else Xxx()」的写法 —— 引擎只决定叶子渲染哪
/// 一套，导航容器（这里是 MaterialApp 的 Navigator）根本不受影响。
class _StyledHome extends StatelessWidget {
  const _StyledHome({required this.material, required this.miuix});

  final Widget material;
  final Widget miuix;

  @override
  Widget build(BuildContext context) {
    // select 只在 uiStyle 变化时重建，别把整棵树跟着其它设置项一起抖。
    final isMiuix = context.select<SettingsService, bool>(
      (s) => s.uiStyle.isMiuix,
    );
    return isMiuix ? miuix : material;
  }
}
