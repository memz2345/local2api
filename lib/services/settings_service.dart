import 'dart:convert';

import 'package:flex_seed_scheme/flex_seed_scheme.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../src/enums.dart';

/// 底部导航栏样式。对应设置里的「底部导航栏」三选一。
enum NavBarStyle {
  /// 液态玻璃（默认）：原生 ComposeView / flutter_miuix 玻璃胶囊。
  glass,

  /// 普通：Material NavigationBar / MiuixNavigationBar。
  plain,

  /// 悬浮：InstallerX FloatingBottomBar 同款实色胶囊（非玻璃）。
  floating,
}

/// 外观/显示设置（从 NaviFlash SettingsService 裁剪移植）。
///
/// 保留移植页面用到的全部字段与持久化键名；玻璃/转场相关的
/// 未上 UI 的字段保留默认值以兼容移植组件的读取。
/// toast 相关走静态镜像（与 NaviFlash 相同模式）。
class SettingsService extends ChangeNotifier {
  static const String _prefKeyPrefix = 'local2api.';

  // ---- 静态镜像（移植组件直接读静态） ----
  static bool fragmentRenderingEnabled = true;
  static bool heroTransitionBlurEnabled = true;
  static bool toastUseFluttertoastEnabled = false;
  static Color toastBgColorValue = const Color(0xFF323232);
  static double toastBgOpacityValue = 0.8;
  static bool toastBgBlurEnabled = false;

  // ---- 界面风格（Material 3 Expressive / 小米 HyperOS） ----
  // 对应 InstallerX 的 showMiuixUI：整个 app 的页面走哪一套实现。
  // 出厂默认 miuix（用户没在设置里选过就是 HyperOS 那套）。
  UiStyle _uiStyle = UiStyle.miuix;
  UiStyle get uiStyle => _uiStyle;
  Future<void> setUiStyle(UiStyle value) async {
    if (_uiStyle == value) return;
    _uiStyle = value;
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setString('${_prefKeyPrefix}uiStyle', value.id);
  }

  // ---- 底部导航栏样式（液态玻璃 / 普通 / 悬浮） ----
  // 玻璃档：Android 上走原生 ComposeView 液态玻璃底栏（LiquidGlassBarHost.kt，
  // Kyant0 backdrop），失败回落 Flutter 玻璃底栏；两套风格图标各用各的
  // （Material 字形 / miuix 矢量路径）。悬浮档：InstallerX FloatingBottomBar
  // 同款实色胶囊（非玻璃，带阴影 + 主色 15% 指示器）。普通档：Material
  // NavigationBar / MiuixNavigationBar。默认玻璃。
  NavBarStyle _navBarStyle = NavBarStyle.glass;
  NavBarStyle get navBarStyle => _navBarStyle;
  Future<void> setNavBarStyle(NavBarStyle value) async {
    if (_navBarStyle == value) return;
    _navBarStyle = value;
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setString('${_prefKeyPrefix}navBarStyle', value.name);
  }

  /// 兼容旧的 bool 开关（true=玻璃 / false=普通）：新键没写过时读旧键。
  static NavBarStyle _navBarStyleFromPrefs(SharedPreferences prefs) {
    final name = prefs.getString('${_prefKeyPrefix}navBarStyle');
    for (final style in NavBarStyle.values) {
      if (style.name == name) return style;
    }
    // 新键没写过：迁移旧 bool（true=玻璃 / false=普通，缺省玻璃）。
    return prefs.getBool('${_prefKeyPrefix}navBarGlass') == false
        ? NavBarStyle.plain
        : NavBarStyle.glass;
  }

  // ---- 主题模式 ----
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;
  Future<void> setThemeMode(ThemeMode value) async {
    if (_themeMode == value) return;
    _themeMode = value;
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setString('${_prefKeyPrefix}themeMode', value.name);
  }

  // ---- Windows：点标题栏关闭按钮的默认动作 ----
  // 桌面常驻工具的三选一：[WindowCloseBehavior.ask] 弹原生任务对话框（自带
  // 「下次也是这样」复选框），另外两档直接执行不再问。默认 ask。
  WindowCloseBehavior _windowCloseBehavior = WindowCloseBehavior.ask;
  WindowCloseBehavior get windowCloseBehavior => _windowCloseBehavior;
  Future<void> setWindowCloseBehavior(WindowCloseBehavior value) async {
    if (_windowCloseBehavior == value) return;
    _windowCloseBehavior = value;
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setString('${_prefKeyPrefix}windowCloseBehavior', value.name);
  }

  // ---- Windows：收进托盘时的系统提示 ----
  // 默认开：第一次（以及之后每次没点「不再提示」时）缩到托盘会弹一条
  // 原生 Toast，免得用户以为程序被自己关掉了。点 Toast 上的「不再提示」
  // 就把它关掉；这里留一个开关，用户改主意时能自己打开。
  bool _trayHintEnabled = true;
  bool get trayHintEnabled => _trayHintEnabled;
  Future<void> setTrayHintEnabled(bool value) async {
    if (_trayHintEnabled == value) return;
    _trayHintEnabled = value;
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setBool('${_prefKeyPrefix}trayHintEnabled', value);
  }

  // ---- 内置浏览器：UA 档位（自动 / 电脑端 / 手机端） ----
  BrowserUaMode _browserUaMode = BrowserUaMode.auto;
  BrowserUaMode get browserUaMode => _browserUaMode;
  Future<void> setBrowserUaMode(BrowserUaMode value) async {
    if (_browserUaMode == value) return;
    _browserUaMode = value;
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setString('${_prefKeyPrefix}browserUaMode', value.id);
  }

  // ---- 内置浏览器：网页能否写剪贴板（默认允许） ----
  bool _browserAllowClipboard = true;
  bool get browserAllowClipboard => _browserAllowClipboard;
  Future<void> setBrowserAllowClipboard(bool value) async {
    if (_browserAllowClipboard == value) return;
    _browserAllowClipboard = value;
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setBool('${_prefKeyPrefix}browserAllowClipboard', value);
  }

  // ---- 内置浏览器：Custom Tabs 用哪家（空 = 自动 / 系统默认） ----
  // 只当「上次选过谁」的预选值；装了多家 Chromium 系浏览器时每次都会弹单选框。
  String _browserCustomTabPackage = '';
  String get browserCustomTabPackage => _browserCustomTabPackage;
  Future<void> setBrowserCustomTabPackage(String value) async {
    if (_browserCustomTabPackage == value) return;
    _browserCustomTabPackage = value;
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setString(
      '${_prefKeyPrefix}browserCustomTabPackage',
      value,
    );
  }

  // ---- 触底/触顶震动（fling 撞列表顶/底轻震，EdgeScrollHaptic） ----
  // 自 NaviFlash 移植，外观设置页可开关。默认开。
  bool _edgeScrollHaptic = true;
  bool get edgeScrollHaptic => _edgeScrollHaptic;
  Future<void> setEdgeScrollHaptic(bool value) async {
    if (_edgeScrollHaptic == value) return;
    _edgeScrollHaptic = value;
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setBool('${_prefKeyPrefix}edgeScrollHaptic', value);
  }

  // ---- 启用模糊（miuix 顶栏毛玻璃 / 大标题模糊，对应 InstallerX 的 useBlur） ----
  // 关掉时所有 miuix 顶栏的两档模糊（BackdropFilter 毛玻璃 + 大标题折叠模糊）
  // 都不开，顶栏回到原版纯色背景。
  bool _useBlur = true;
  bool get useBlur => _useBlur;
  Future<void> setUseBlur(bool value) async {
    if (_useBlur == value) return;
    _useBlur = value;
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setBool('${_prefKeyPrefix}useBlur', value);
  }

  // ---- 渐变模糊顶栏（两套风格的顶栏都吃这一档） ----
  // 开启后顶栏从「纯色底 + 均匀毛玻璃」换成「透明顶栏 + 顶部渐进模糊带」
  // （模糊带随内容滚入淡入）：miuix 走 MiuixBlurTopBar，Material 走
  // FrostedPageBar，两边共用 liquid_glass.dart 的 progressiveTopBarOf 判门槛。
  // 依赖着色器滤镜，且只在「启用模糊」打开时生效/显示开关。
  // 出厂默认开（与出厂默认 miuix 风格配套）。
  bool _progressiveTopBar = true;
  bool get progressiveTopBar => _progressiveTopBar;
  Future<void> setProgressiveTopBar(bool value) async {
    if (_progressiveTopBar == value) return;
    _progressiveTopBar = value;
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setBool('${_prefKeyPrefix}progressiveTopBar', value);
  }

  // ---- 生物识别锁（Hail 同款应用锁，仅 Android） ----
  // 开启后冷启动与从后台回到前台都要先过一次生物识别（指纹/人脸/设备凭据）
  // 才能看到界面；关掉立即解锁。开关打开时会先做一次验证，设备没有录入
  // 生物识别（也不支持设备凭据）时拒绝开启 —— 防止把自己锁在外面。
  bool _biometricLock = false;
  bool get biometricLock => _biometricLock;
  Future<void> setBiometricLock(bool value) async {
    if (_biometricLock == value) return;
    _biometricLock = value;
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setBool('${_prefKeyPrefix}biometricLock', value);
  }

  // ---- 自定义颜色（Miuix 主题风格下自定义主题颜色，对应 InstallerX 的
  // useMiuixMonet） ----
  // 关掉时种子色 / 配色风格不生效（miuix 配色回出厂默认），主题配色页
  // 「配色」区禁用并提示「需要启用自定义颜色」。
  bool _useCustomThemeColors = true;
  bool get useCustomThemeColors => _useCustomThemeColors;
  Future<void> setUseCustomThemeColors(bool value) async {
    if (_useCustomThemeColors == value) return;
    _useCustomThemeColors = value;
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setBool('${_prefKeyPrefix}useCustomThemeColors', value);
  }

  // ---- 纯黑模式 ----
  bool _isPureBlackMode = false;
  bool get isPureBlackMode => _isPureBlackMode;
  Future<void> setIsPureBlackMode(bool value) async {
    if (_isPureBlackMode == value) return;
    _isPureBlackMode = value;
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setBool('${_prefKeyPrefix}isPureBlackMode', value);
  }

  // ---- 主题种子色 ----
  Color _themeSeedColor = Colors.blue;
  Color get themeSeedColor => _themeSeedColor;
  Future<void> setThemeSeedColor(Color value) async {
    if (_themeSeedColor.toARGB32() == value.toARGB32()) return;
    _themeSeedColor = value;
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setInt('${_prefKeyPrefix}themeSeedColor', value.toARGB32());
  }

  // ---- 跟随系统动态色（Android 12+ Material You） ----
  bool _useDynamicColor = false;
  bool get useDynamicColor => _useDynamicColor;
  Future<void> setUseDynamicColor(bool value) async {
    if (_useDynamicColor == value) return;
    _useDynamicColor = value;
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setBool('${_prefKeyPrefix}useDynamicColor', value);
  }

  // ---- Flex 种子方案变体 ----
  FlexSchemeVariant _schemeVariant = FlexSchemeVariant.tonalSpot;
  FlexSchemeVariant get schemeVariant => _schemeVariant;
  Future<void> setSchemeVariant(FlexSchemeVariant value) async {
    if (_schemeVariant == value) return;
    _schemeVariant = value;
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setInt('${_prefKeyPrefix}schemeVariant', value.index);
  }

  // ---- 自定义主题（图片取色保存的颜色） ----
  List<Map<String, dynamic>> _customThemes = [];
  List<Map<String, dynamic>> get customThemes =>
      List.unmodifiable(_customThemes);
  Future<void> addCustomTheme(String name, Color color) async {
    _customThemes = [
      ..._customThemes,
      {'name': name, 'color': color.toARGB32()},
    ];
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setString(
      '${_prefKeyPrefix}customThemes',
      customThemes.map((m) => '${m['name']}:${m['color']}').join('|'),
    );
  }

  Future<void> removeCustomTheme(int index) async {
    if (index < 0 || index >= _customThemes.length) return;
    final name = _customThemes[index]['name'];
    _customThemes = [..._customThemes]..removeAt(index);
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setString(
      '${_prefKeyPrefix}customThemes',
      customThemes.map((m) => '${m['name']}:${m['color']}').join('|'),
    );
    debugPrint('custom theme removed: $name');
  }

  // ---- 字体粗细 ----
  double _fontWeight = 400.0;
  double get fontWeight => _fontWeight;
  Future<void> setFontWeight(double value) async {
    final clamped = value.clamp(300.0, 800.0);
    if (_fontWeight == clamped) return;
    _fontWeight = clamped;
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setDouble('${_prefKeyPrefix}fontWeight', clamped);
  }

  // ---- 显示大小 ----
  double _displayScale = 1.0;
  double get displayScale => _displayScale;
  Future<void> setDisplayScale(double value) async {
    final clamped = value.clamp(0.7, 1.4);
    if (_displayScale == clamped) return;
    _displayScale = clamped;
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setDouble('${_prefKeyPrefix}displayScale', clamped);
  }

  // ---- 页面背景（PageBackground 组件读取；本项目未上 UI，恒为关闭） ----
  String? get pageBackgroundPath => null;
  bool get pageBackgroundEnabled => false;
  double get pageBackgroundOpacity => 0.0;
  double get pageBackgroundBlur => 0.0;
  String? get contentPageBackgroundPath => null;
  bool get contentPageBackgroundEnabled => false;
  double get contentPageBackgroundOpacity => 0.0;
  double get contentPageBackgroundBlur => 0.0;

  // ---- 玻璃/转场开关（移植组件兼容字段，未上 UI） ----
  // ---- 屏幕帧率（DisplayMode.toString()，NaviFlash 同款；仅 Android 生效）----
  // 存的就是 flutter_displaymode 的 DisplayMode.toString()（如
  // "1080x2400 @ 120Hz"），auto 也存它自己的 toString()；展示时经
  // DisplayModeService.labelOf 解析。系统不持久化这个窗口属性，冷启动由
  // DisplayModeService.restorePreferred 按这里的存档重新应用一次。
  String _displayMode = 'auto';
  String get displayMode => _displayMode;
  Future<void> setDisplayMode(String value) async {
    if (_displayMode == value) return;
    _displayMode = value;
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setString('${_prefKeyPrefix}displayMode', value);
  }

  bool _chatGlass = false;
  bool get chatGlass => _chatGlass;
  Future<void> setChatGlass(bool value) async {
    _chatGlass = value;
    notifyListeners();
  }

  bool _videoCardGlass = false;
  bool get videoCardGlass => _videoCardGlass;
  Future<void> setVideoCardGlass(bool value) async {
    _videoCardGlass = value;
    notifyListeners();
  }

  bool _disableLiquidGlassMenus = false;
  bool get disableLiquidGlassMenus => _disableLiquidGlassMenus;
  Future<void> setDisableLiquidGlassMenus(bool value) async {
    _disableLiquidGlassMenus = value;
    notifyListeners();
  }

  bool _liquidGlassBottomBarJelly = true;
  bool get liquidGlassBottomBarJelly => _liquidGlassBottomBarJelly;
  Future<void> setLiquidGlassBottomBarJelly(bool value) async {
    _liquidGlassBottomBarJelly = value;
    notifyListeners();
  }

  static bool _liquidGlassMenuJelly = true;
  bool get liquidGlassMenuJelly => _liquidGlassMenuJelly;

  /// 静态镜像（liquid_glass_menu_button 以静态方式读取）。
  static bool get liquidGlassMenuJellyEnabled => _liquidGlassMenuJelly;
  Future<void> setLiquidGlassMenuJelly(bool value) async {
    _liquidGlassMenuJelly = value;
    notifyListeners();
  }

  bool _heroTransitionBlur = true;
  bool get heroTransitionBlur => _heroTransitionBlur;
  Future<void> setHeroTransitionBlur(bool value) async {
    _heroTransitionBlur = value;
    notifyListeners();
  }

  bool _iosPushTransition = true;
  bool get iosPushTransition => _iosPushTransition;
  Future<void> setIosPushTransition(bool value) async {
    _iosPushTransition = value;
    notifyListeners();
  }

  // ---- iOS 风格页面转场圆角 ----
  // 打开「自动跟随设备」时用设备**物理屏幕**的圆角（Android 走
  // WindowInsets.getRoundedCorner / Display / 私有 dimen，见 DeviceCornerChannel；
  // 桌面与读不到时回退到下面这个手动值），这样滑入的卡片圆角刚好贴合屏幕本身
  // 的圆角，不会在圆角屏上偏小、也不会给方角屏凭空造圆角。
  double _iosPushTransitionCornerRadius = 26.0;
  double get iosPushTransitionCornerRadius => _iosPushTransitionCornerRadius;

  bool _iosPushTransitionCornerAuto = true;
  bool get iosPushTransitionCornerAuto => _iosPushTransitionCornerAuto;

  Future<void> setIosPushTransitionCornerRadius(double value) async {
    final clamped = value.clamp(0.0, 48.0).toDouble();
    if (_iosPushTransitionCornerRadius == clamped) return;
    _iosPushTransitionCornerRadius = clamped;
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setDouble(
      '${_prefKeyPrefix}iosPushTransitionCornerRadius',
      clamped,
    );
  }

  Future<void> setIosPushTransitionCornerAuto(bool value) async {
    if (_iosPushTransitionCornerAuto == value) return;
    _iosPushTransitionCornerAuto = value;
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setBool('${_prefKeyPrefix}iosPushTransitionCornerAuto', value);
  }

  bool _enableFragmentRendering = true;
  bool get enableFragmentRendering => _enableFragmentRendering;
  Future<void> setEnableFragmentRendering(bool value) async {
    _enableFragmentRendering = value;
    fragmentRenderingEnabled = value;
    notifyListeners();
  }

  // ---- toast 设置（静态镜像同步） ----
  Future<void> setToastUseFluttertoast(bool value) async {
    toastUseFluttertoastEnabled = value;
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setBool('${_prefKeyPrefix}toastUseFluttertoast', value);
  }

  Future<void> setToastBgOpacity(double value) async {
    toastBgOpacityValue = value.clamp(0.05, 1.0);
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setDouble(
      '${_prefKeyPrefix}toastBgOpacity',
      toastBgOpacityValue,
    );
  }

  Future<void> setToastBgBlur(bool value) async {
    toastBgBlurEnabled = value;
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setBool('${_prefKeyPrefix}toastBgBlur', value);
  }

  // ---- 仪表盘风险提示的关闭状态（逐条记忆） ----
  // 提示是「一个 info 一张卡」（InstallerX 配置页样式），每张卡有自己的 X，
  // 所以关闭也逐条记：key（keys/rules）→ 「被关闭时的警告组合签名」（如
  // keys+rules）。该条的签名不变就不再弹出，警告组合一变（新增/消失某条）
  // 就重新显示 —— 与之前整组一条签名的语义一致，只是粒度落到每条提示上。
  final Map<String, String> _warningsTipDismissedSigs = {};
  String? warningsTipDismissedSigOf(String key) =>
      _warningsTipDismissedSigs[key];
  Future<void> setWarningsTipDismissedSig(String key, String sig) async {
    if (_warningsTipDismissedSigs[key] == sig) return;
    _warningsTipDismissedSigs[key] = sig;
    notifyListeners();
    final prefs = await _prefs;
    await prefs.setString(
      '${_prefKeyPrefix}warningsTipDismissedSigs',
      jsonEncode(_warningsTipDismissedSigs),
    );
  }

  // ---- 页面「说明文字」info 卡的关闭状态（逐卡记忆） ----
  // 各页顶部/列表里的说明卡（keysIntro / discoverIntro / usageIntro …）都带
  // 行尾 X，点了就按 id 记住，重启后不再显示。
  //
  // 为什么不挂在实例上走 Provider（风险提示那套）：这些说明卡散落在多个
  // miuix 页面里，页面本身不读 SettingsService，单页测试/独立预览的树里
  // 也没有 Provider —— 挂在静态上谁都能用，读的也就是一份本地偏好。
  // 需要重建的地方监听 [infoCardDismissals]（只影响卡自己，不动整页）。
  static final Set<String> _dismissedInfoCards = {};

  /// 关闭记录变化的信号（值本身没意义，只用来触发重建）。
  static final ValueNotifier<int> infoCardDismissals = ValueNotifier(0);

  static bool infoCardDismissed(String id) => _dismissedInfoCards.contains(id);
  static Future<void> dismissInfoCard(String id) async {
    if (!_dismissedInfoCards.add(id)) return;
    infoCardDismissals.value++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      '${_prefKeyPrefix}dismissedInfoCards',
      _dismissedInfoCards.toList(),
    );
  }

  // ---- 加载 ----
  SharedPreferences? _prefsInstance;
  Future<SharedPreferences> get _prefs async =>
      _prefsInstance ??= await SharedPreferences.getInstance();

  Future<void> load() async {
    final prefs = await _prefs;
    _uiStyle = UiStyleX.fromId(prefs.getString('${_prefKeyPrefix}uiStyle'));
    _navBarStyle = _navBarStyleFromPrefs(prefs);
    final dismissedRaw = prefs.getString(
      '${_prefKeyPrefix}warningsTipDismissedSigs',
    );
    if (dismissedRaw != null && dismissedRaw.isNotEmpty) {
      try {
        for (final e
            in (jsonDecode(dismissedRaw) as Map<String, dynamic>).entries) {
          _warningsTipDismissedSigs[e.key] = '${e.value}';
        }
      } catch (e) {
        debugPrint('SettingsService: 提示关闭记录损坏，忽略（$e）');
      }
    }
    final tm = prefs.getString('${_prefKeyPrefix}themeMode');
    _themeMode = switch (tm) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    _edgeScrollHaptic =
        prefs.getBool('${_prefKeyPrefix}edgeScrollHaptic') ?? true;
    _useBlur = prefs.getBool('${_prefKeyPrefix}useBlur') ?? true;
    _progressiveTopBar =
        prefs.getBool('${_prefKeyPrefix}progressiveTopBar') ?? true;
    _biometricLock = prefs.getBool('${_prefKeyPrefix}biometricLock') ?? false;
    _dismissedInfoCards
      ..clear()
      ..addAll(
        prefs.getStringList('${_prefKeyPrefix}dismissedInfoCards') ?? const [],
      );
    _useCustomThemeColors =
        prefs.getBool('${_prefKeyPrefix}useCustomThemeColors') ?? true;
    _isPureBlackMode =
        prefs.getBool('${_prefKeyPrefix}isPureBlackMode') ?? false;
    _themeSeedColor = Color(
      prefs.getInt('${_prefKeyPrefix}themeSeedColor') ?? Colors.blue.toARGB32(),
    );
    _useDynamicColor =
        prefs.getBool('${_prefKeyPrefix}useDynamicColor') ?? false;
    final variantIndex = prefs.getInt('${_prefKeyPrefix}schemeVariant');
    _schemeVariant =
        (variantIndex == null ||
            variantIndex < 0 ||
            variantIndex >= FlexSchemeVariant.values.length)
        ? FlexSchemeVariant.tonalSpot
        : FlexSchemeVariant.values[variantIndex];
    _customThemes = [
      for (final entry
          in (prefs.getString('${_prefKeyPrefix}customThemes') ?? '').split(
            '|',
          ))
        if (entry.contains(':'))
          {
            'name': entry.split(':').first,
            'color': int.tryParse(entry.split(':').last) ?? 0,
          },
    ];
    _fontWeight = prefs.getDouble('${_prefKeyPrefix}fontWeight') ?? 400.0;
    _displayMode = prefs.getString('${_prefKeyPrefix}displayMode') ?? 'auto';
    _displayScale = prefs.getDouble('${_prefKeyPrefix}displayScale') ?? 1.0;
    _iosPushTransitionCornerRadius =
        prefs.getDouble('${_prefKeyPrefix}iosPushTransitionCornerRadius') ??
        26.0;
    _iosPushTransitionCornerAuto =
        prefs.getBool('${_prefKeyPrefix}iosPushTransitionCornerAuto') ?? true;
    // 没存过 / 存了不认识的名字都回到「每次问」（其余两档会让用户直接失去
    // 确认机会，宁可归到安全的那一档）。
    final closeName = prefs.getString('${_prefKeyPrefix}windowCloseBehavior');
    _windowCloseBehavior = WindowCloseBehavior.values.asNameMap()[closeName] ??
        WindowCloseBehavior.ask;
    _trayHintEnabled =
        prefs.getBool('${_prefKeyPrefix}trayHintEnabled') ?? true;
    _browserUaMode = BrowserUaMode.fromId(
      prefs.getString('${_prefKeyPrefix}browserUaMode'),
    );
    _browserAllowClipboard =
        prefs.getBool('${_prefKeyPrefix}browserAllowClipboard') ?? true;
    _browserCustomTabPackage =
        prefs.getString('${_prefKeyPrefix}browserCustomTabPackage') ?? '';
    fragmentRenderingEnabled =
        prefs.getBool('${_prefKeyPrefix}fragmentRendering') ?? true;
    toastUseFluttertoastEnabled =
        prefs.getBool('${_prefKeyPrefix}toastUseFluttertoast') ?? false;
    toastBgOpacityValue =
        prefs.getDouble('${_prefKeyPrefix}toastBgOpacity') ?? 0.8;
    toastBgBlurEnabled = prefs.getBool('${_prefKeyPrefix}toastBgBlur') ?? false;
    notifyListeners();
  }
}
