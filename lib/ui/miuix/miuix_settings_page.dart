import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField;
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/screens/miuix/miuix_display_settings_screen.dart';
import 'package:local2api/services/app_locale_bridge.dart';
import 'package:local2api/services/app_settings.dart';
import 'package:local2api/services/biometric_service.dart';
import 'package:local2api/services/lab/lab_gate.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/ui/miuix/miuix_about_page.dart';
import 'package:local2api/ui/miuix/miuix_chat_settings_page.dart';
import 'package:local2api/ui/miuix/miuix_lab_page.dart';
import 'package:local2api/ui/miuix/miuix_network_settings_page.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';
import 'package:local2api/src/enums.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';
import 'package:provider/provider.dart';

/// 设置页（miuix 版，对应 Material 版 `SettingsPage`）。
///
/// 分区与写入目标与 Material 版完全一致（ProxyConfig 走 ConfigStore、
/// 界面风格走 SettingsService、语言走 AppSettings + AppLocaleBridge），
/// 只换渲染：分组用 MiuixSmallTitle + MiuixCard，开关行用
/// MiuixSwitchPreference，跳转行用 MiuixArrowPreference，单选走
/// MiuixOverlayDropdownPreference（行旁悬浮下拉菜单）。
///
/// 跳转不回到 Material 实现：「显示设置」进 miuix 版子页。
/// 顶栏走 HyperOS 一级页规范：可折叠大标题 [MiuixTopAppBar] +
/// [miuixScrollBehavior]，滚动容器用 [MiuixScrollBehaviorListener] 接线。
class MiuixSettingsPage extends StatefulWidget {
  const MiuixSettingsPage({
    super.key,
    required this.controller,
    required this.settings,
  });

  final ServerController controller;
  final AppSettings settings;

  @override
  State<MiuixSettingsPage> createState() => _MiuixSettingsPageState();
}

class _MiuixSettingsPageState extends State<MiuixSettingsPage> {
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();

  @override
  void dispose() {
    _behavior.state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AnimatedBuilder(
      // 配置/设置一变就整页重建：端口、规则、外观这些行都是读 widget.controller
      // 现算的，不重建的话选了也不刷新（监听地址那一行就靠它更新显示值）。
      animation: Listenable.merge([widget.controller, widget.settings]),
      builder: (context, _) => MiuixScaffold(
        containerColor: MiuixTheme.of(context).colors.surface,
        // 与仪表盘同构：内容铺满整页、毛玻璃顶栏画在其上，内容从栏下穿过。
        // 毛玻璃只在支持着色器滤镜的渲染路径上开（软渲染模拟器会崩，同底栏防护）。
        topBar: MiuixBlurTopBar(
          title: l10n.settingsTitle,
          scrollBehavior: _behavior,
        ),
        content: (padding) => MiuixScrollBehaviorListener(
          behavior: _behavior,
          child: ListView(
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(16, padding.top, 16, 110),
            children: [
              const SizedBox(height: 4),
              _MiuixFeaturesSection(controller: widget.controller),
              _MiuixAppearanceSection(settings: widget.settings),
              const _MiuixSecuritySection(),
              const _MiuixAboutSection(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 分区小标题 + 可选尾部动作。
class _MiuixSectionHeader extends StatelessWidget {
  const _MiuixSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: MiuixSmallTitle(title, insideMargin: EdgeInsets.zero),
          ),
        ],
      ),
    );
  }
}

/// 服务与功能：网络设置 / 对话设置两个二级页的入口（带副标题说明）。
///
/// 拆分逻辑：这一页只留「全局外观与安全」，服务相关的配置按受众分进
/// 两个二级页 —— 网络设置（对外暴露：端口 / WebUI / IP 规则）与
/// 对话设置（本地 TTS / 角色卡），比原来一页平铺七张卡清楚得多。
///
/// 实验室默认隐藏（与 Material 版一致）：拨开「实验室」开关后，
/// 下面的「进入实验室」入口才出现，状态收在 [LabGate]。
class _MiuixFeaturesSection extends StatelessWidget {
  const _MiuixFeaturesSection({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: LabGate.instance,
      builder: (context, _) {
        final gate = LabGate.instance;
        if (!gate.loaded) gate.load();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MiuixSectionHeader(title: l10n.settingsFeaturesSection),
            MiuixGroupCard(
              insideMargin: EdgeInsets.zero,
              child: Column(
                children: [
                  MiuixArrowPreference(
                    title: l10n.networkSettingsTitle,
                    summary: l10n.networkSettingsDesc,
                    startAction: const Icon(Icons.lan_outlined),
                    onClick: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            MiuixNetworkSettingsPage(controller: controller),
                      ),
                    ),
                  ),
                  MiuixArrowPreference(
                    title: l10n.chatSettingsTitle,
                    summary: l10n.chatSettingsDesc,
                    startAction: const Icon(Icons.forum_outlined),
                    onClick: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            MiuixChatSettingsPage(controller: controller),
                      ),
                    ),
                  ),
                  MiuixSwitchPreference(
                    title: l10n.settingsLabTitle,
                    summary: l10n.labVisibleDesc,
                    value: gate.visible,
                    onChanged: (v) => gate.setVisible(v),
                    startAction: const Icon(Icons.science_outlined),
                  ),
                  if (gate.visible)
                    MiuixArrowPreference(
                      title: l10n.labOpenLab,
                      startAction: const Icon(Icons.chevron_right),
                      onClick: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => MiuixLabPage(controller: controller),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MiuixAppearanceSection extends StatelessWidget {
  const _MiuixAppearanceSection({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MiuixSectionHeader(title: l10n.settingsDisplaySection),
        // 图1 / InstallerX 主题设置同款：主题模式 / 启用模糊 / 自定义颜色。
        MiuixGroupCard(
          insideMargin: EdgeInsets.zero,
          child: Column(
            children: [
              // 值在 SettingsService 上，不是传进来的 AppSettings。
              Consumer<SettingsService>(
                builder: (context, display, _) =>
                    MiuixOverlayDropdownPreference(
                      title: l10n.displayThemeMode,
                      items: [
                        l10n.drawerSystemMode,
                        l10n.displayThemeLight,
                        l10n.displayThemeDark,
                      ],
                      // ThemeMode.values 顺序就是 system / light / dark。
                      selectedIndex: display.themeMode.index,
                      onSelectedIndexChange: (i) =>
                          display.setThemeMode(ThemeMode.values[i]),
                    ),
              ),
              Consumer<SettingsService>(
                builder: (context, display, _) => MiuixSwitchPreference(
                  title: l10n.settingsBlurTitle,
                  summary: l10n.settingsBlurDesc,
                  value: display.useBlur,
                  onChanged: display.setUseBlur,
                ),
              ),
              // 渐变模糊顶栏：只在「启用模糊」开着时出现 —— 它是模糊的
              // 一种形态，模糊总开关关了它必然无效，留着只会让人困惑。
              Consumer<SettingsService>(
                builder: (context, display, _) => display.useBlur
                    ? MiuixSwitchPreference(
                        title: l10n.progressiveTopBarTitle,
                        summary: l10n.progressiveTopBarDesc,
                        value: display.progressiveTopBar,
                        onChanged: display.setProgressiveTopBar,
                      )
                    : const SizedBox.shrink(),
              ),
              Consumer<SettingsService>(
                builder: (context, display, _) => MiuixSwitchPreference(
                  title: l10n.settingsCustomColorsTitle,
                  summary: l10n.settingsCustomColorsDesc,
                  value: display.useCustomThemeColors,
                  onChanged: display.setUseCustomThemeColors,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        MiuixGroupCard(
          insideMargin: EdgeInsets.zero,
          child: Column(
            children: [
              MiuixArrowPreference(
                title: l10n.settingsDisplayEntry,
                startAction: const MiuixAppIcon(
                  AppIconNames.theme,
                  fallback: Icons.palette_outlined,
                ),
                onClick: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MiuixDisplaySettingsScreen(),
                  ),
                ),
              ),
              // 值在 SettingsService 上，不是传进来的 AppSettings。
              Consumer<SettingsService>(
                builder: (context, display, _) {
                  final labels = [
                    for (final style in UiStyle.values)
                      style.isMiuix ? l10n.uiStyleMiuix : l10n.uiStyleMaterial,
                  ];
                  return MiuixOverlayDropdownPreference(
                    title: l10n.uiStyleLabel,
                    items: labels,
                    selectedIndex: display.uiStyle.index,
                    startAction: const MiuixAppIcon(
                      AppIconNames.layers,
                      fallback: Icons.style_outlined,
                    ),
                    onSelectedIndexChange: (i) =>
                        display.setUiStyle(UiStyle.values[i]),
                  );
                },
              ),
              // 底部导航栏样式（液态玻璃 / 普通 / 悬浮）
              Consumer<SettingsService>(
                builder: (context, display, _) =>
                    MiuixOverlayDropdownPreference(
                      title: l10n.navBarStyleLabel,
                      items: [
                        l10n.navBarStyleGlass,
                        l10n.navBarStylePlain,
                        l10n.navBarStyleFloating,
                      ],
                      selectedIndex: switch (display.navBarStyle) {
                        NavBarStyle.glass => 0,
                        NavBarStyle.plain => 1,
                        NavBarStyle.floating => 2,
                      },
                      startAction: const MiuixAppIcon(
                        AppIconNames.album,
                        fallback: Icons.dock_outlined,
                      ),
                      onSelectedIndexChange: (i) =>
                          display.setNavBarStyle(switch (i) {
                            1 => NavBarStyle.plain,
                            2 => NavBarStyle.floating,
                            _ => NavBarStyle.glass,
                          }),
                    ),
              ),
              // 滑动触感反馈（快速滑动撞列表顶/底轻震，自 NaviFlash 移植）
              Consumer<SettingsService>(
                builder: (context, display, _) => MiuixSwitchPreference(
                  title: l10n.edgeHapticLabel,
                  summary: l10n.edgeHapticNote,
                  startAction: const MiuixAppIcon(
                    AppIconNames.tune,
                    fallback: Icons.vibration_outlined,
                  ),
                  value: display.edgeScrollHaptic,
                  onChanged: (v) => display.setEdgeScrollHaptic(v),
                ),
              ),
              MiuixOverlayDropdownPreference(
                title: l10n.languageLabel,
                items: [l10n.languageSystem, '简体中文', '繁體中文', 'English'],
                selectedIndex: switch (settings.localeCode) {
                  null => 0,
                  'zh-CN' => 1,
                  'zh-TW' => 2,
                  _ => 3,
                },
                startAction: const MiuixAppIcon(
                  AppIconNames.translate,
                  fallback: Icons.translate,
                ),
                onSelectedIndexChange: (i) {
                  final code = switch (i) {
                    1 => 'zh-CN',
                    2 => 'zh-TW',
                    3 => 'en-US',
                    _ => null,
                  };
                  settings.setLocale(code);
                  AppLocaleBridge.setSystemAppLocale(code);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 安全分组：生物识别锁（Hail 同款应用锁，仅 Android）。
///
/// 开启流程先做一次试验证：设备没有可用凭据时开不了 —— 防止把自己
/// 锁在外面。拦截点在根组件（app.dart）：冷启动与回前台都要过验证。
class _MiuixSecuritySection extends StatelessWidget {
  const _MiuixSecuritySection();

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MiuixSectionHeader(title: l10n.securitySection),
        MiuixGroupCard(
          insideMargin: EdgeInsets.zero,
          child: Consumer<SettingsService>(
            builder: (context, display, _) => MiuixSwitchPreference(
              title: l10n.biometricLockTitle,
              summary: l10n.biometricLockDesc,
              value: display.biometricLock,
              onChanged: (want) => _toggle(context, display, l10n, want),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _toggle(
    BuildContext context,
    SettingsService display,
    AppLocalizations l10n,
    bool want,
  ) async {
    if (!want) {
      await display.setBiometricLock(false);
      return;
    }
    final biometric = BiometricService();
    if (!await biometric.isSupported()) {
      if (context.mounted) {
        showMiuixToast(context, l10n.biometricLockUnavailable, error: true);
      }
      return;
    }
    final ok = await biometric.authenticate(l10n.biometricLockDesc);
    if (!context.mounted) return;
    if (ok) {
      await display.setBiometricLock(true);
    } else {
      showMiuixToast(context, l10n.biometricLockUnavailable, error: true);
    }
  }
}

class _MiuixAboutSection extends StatelessWidget {
  const _MiuixAboutSection();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MiuixSectionHeader(title: l10n.aboutSection),
        // 关于独立成页（InstallerX 同款效果背景 + 纹理集彩蛋）
        MiuixGroupCard(
          insideMargin: EdgeInsets.zero,
          child: MiuixArrowPreference(
            title: l10n.aboutSection,
            summary: l10n.aboutEntryDesc,
            startAction: const MiuixAppIcon(
              AppIconNames.info,
              fallback: Icons.info_outline,
            ),
            onClick: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MiuixAboutPage(
                  // 模糊默认值在 SettingsService 上（AppSettings 没有它）
                  settings: context.read<SettingsService>(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}


