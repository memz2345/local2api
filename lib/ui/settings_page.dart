import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/screens/display_settings_screen.dart';
import 'package:local2api/services/app_locale_bridge.dart';
import 'package:local2api/services/app_settings.dart';
import 'package:local2api/services/biometric_service.dart';
import 'package:local2api/services/lab/lab_gate.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/src/enums.dart';
import 'package:local2api/ui/about_page.dart';
import 'package:local2api/ui/chat_settings_page.dart';
import 'package:local2api/ui/lab_page.dart';
import 'package:local2api/ui/network_settings_page.dart';
import 'package:local2api/widgets/app_toast.dart';
import 'package:local2api/widgets/expressive_app_bar.dart';
import 'package:local2api/widgets/liquid_glass.dart' show naviGlassAdvanced;
import 'package:provider/provider.dart';

import 'widgets/common.dart';

/// 设置页：二级页入口（网络 / 对话）、主题、语言（Android 13+ 应用语言）、关于。
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    required this.settings,
  });

  final ServerController controller;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([controller, settings]),
      builder: (context, _) => CustomScrollView(
        slivers: [
          ExpressiveSliverAppBar(title: l10n.settingsTitle),
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 110),
            sliver: SliverList.list(
              children: [
                _FeaturesSection(controller: controller),
                _AppearanceSection(settings: settings),
                const _SecuritySection(),
                const _AboutSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 界面风格选择对话框。
///
/// 不用 RadioListTile：新版 Flutter 把 groupValue / onChanged 那套标了弃用，
/// 用它会带进告警，这里自己画单选图标就够。
Future<void> _pickUiStyle(
  BuildContext context,
  SettingsService display,
  AppLocalizations l10n,
) async {
  final theme = Theme.of(context);
  final picked = await showDialog<UiStyle>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(l10n.uiStyleLabel),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(
            l10n.uiStyleNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final style in UiStyle.values)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(style),
            child: Row(
              children: [
                Icon(
                  style == display.uiStyle
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: style == display.uiStyle
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    style.isMiuix ? l10n.uiStyleMiuix : l10n.uiStyleMaterial,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
  if (picked != null) await display.setUiStyle(picked);
}

/// 服务与功能：网络设置 / 对话设置两个二级页的入口（带副标题说明）。
///
/// 拆分逻辑与 miuix 版一致：这一页只留「全局外观与安全」，服务相关的
/// 配置按受众分进两个二级页 —— 网络设置（对外暴露：端口 / WebUI / IP 规则）
/// 与对话设置（本地 TTS / 角色卡）。
///
/// 实验室默认隐藏：它要在本机装 Node、跑本地服务，属于进阶玩法，
/// 用户把「实验室」开关拨开后入口才显示（状态收在 [LabGate]）。
class _FeaturesSection extends StatelessWidget {
  const _FeaturesSection({required this.controller});

  final ServerController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: LabGate.instance,
      builder: (context, _) {
        final gate = LabGate.instance;
        if (!gate.loaded) unawaited(gate.load());
        return SectionCard(
          title: l10n.settingsFeaturesSection,
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lan_outlined),
                title: Text(l10n.networkSettingsTitle),
                subtitle: Text(l10n.networkSettingsDesc),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => pushPage(
                  context,
                  NetworkSettingsPage(controller: controller),
                ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.forum_outlined),
                title: Text(l10n.chatSettingsTitle),
                subtitle: Text(l10n.chatSettingsDesc),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => pushPage(
                  context,
                  ChatSettingsPage(controller: controller),
                ),
              ),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.science_outlined),
                title: Text(l10n.settingsLabTitle),
                subtitle: Text(l10n.labVisibleDesc),
                value: gate.visible,
                onChanged: (v) => gate.setVisible(v),
              ),
              if (gate.visible)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.chevron_right),
                  title: Text(l10n.labOpenLab),
                  onTap: () => pushPage(
                    context,
                    LabPage(controller: controller),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SectionCard(
      title: l10n.settingsDisplaySection,
      child: Column(
        children: [
          // 显示设置（主题模式/纯黑/主题颜色/图片取色/字重/显示大小）
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.palette_outlined),
            title: Text(l10n.settingsDisplayEntry),
            trailing: Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            onTap: () => pushPage(context, const DisplaySettingsScreen()),
          ),
          const Divider(),
          // 界面风格（Material 3 Expressive / 小米 HyperOS）
          // 值在 SettingsService 上，不是传进来的 AppSettings。
          // 用箭头行 + 对话框而不是 trailing 里塞 DropdownButton：两个风格名
          // 很长，DropdownButton 在窄屏下会把 ListTile 的布局搞崩。
          Consumer<SettingsService>(
            builder: (context, display, _) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.style_outlined),
              title: Text(l10n.uiStyleLabel),
              subtitle: Text(
                display.uiStyle.isMiuix
                    ? l10n.uiStyleMiuix
                    : l10n.uiStyleMaterial,
              ),
              trailing: Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              onTap: () => _pickUiStyle(context, display, l10n),
            ),
          ),
          const Divider(),
          // 底部导航栏样式（液态玻璃 / 普通）。用 DropdownButton 而不是
          // SegmentedButton：trailing 塞两枚带字的按钮在窄屏放不下
          //（同语言行的取舍）。
          Consumer<SettingsService>(
            builder: (context, display, _) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.dock_outlined),
              title: Text(l10n.navBarStyleLabel),
              subtitle: Text(l10n.navBarStyleNote),
              trailing: DropdownButton<NavBarStyle>(
                value: display.navBarStyle,
                underline: const SizedBox.shrink(),
                items: [
                  DropdownMenuItem(
                    value: NavBarStyle.glass,
                    child: Text(l10n.navBarStyleGlass),
                  ),
                  DropdownMenuItem(
                    value: NavBarStyle.plain,
                    child: Text(l10n.navBarStylePlain),
                  ),
                  DropdownMenuItem(
                    value: NavBarStyle.floating,
                    child: Text(l10n.navBarStyleFloating),
                  ),
                ],
                onChanged: (v) =>
                    display.setNavBarStyle(v ?? NavBarStyle.glass),
              ),
            ),
          ),
          const Divider(),
          // 渐变模糊顶栏（AppMarket 同款）：顶栏那层均匀毛玻璃换成「顶边满
          // 强度、往下溶解到清晰」的渐进模糊。跑得动 fragment shader 才有
          // 意义，跑不动就不露这一行 —— 露了也点不出效果。
          if (naviGlassAdvanced) ...[
            Consumer<SettingsService>(
              builder: (context, display, _) => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.blur_on_outlined),
                title: Text(l10n.progressiveTopBarTitle),
                subtitle: Text(l10n.progressiveTopBarDesc),
                value: display.progressiveTopBar,
                onChanged: (v) => display.setProgressiveTopBar(v),
              ),
            ),
            const Divider(),
          ],
          // 滑动触感反馈（快速滑动撞列表顶/底轻震，自 NaviFlash 移植）
          Consumer<SettingsService>(
            builder: (context, display, _) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.vibration_outlined),
              title: Text(l10n.edgeHapticLabel),
              subtitle: Text(l10n.edgeHapticNote),
              value: display.edgeScrollHaptic,
              onChanged: (v) => display.setEdgeScrollHaptic(v),
            ),
          ),
          const Divider(),
          // 语言（Android 13+ 写回系统应用语言）
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.translate),
            title: Text(l10n.languageLabel),
            subtitle: Text(l10n.languageNote),
            trailing: DropdownButton<String?>(
              value: settings.localeCode,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem(value: null, child: Text(l10n.languageSystem)),
                const DropdownMenuItem(value: 'zh-CN', child: Text('简体中文')),
                const DropdownMenuItem(value: 'zh-TW', child: Text('繁體中文')),
                const DropdownMenuItem(value: 'en-US', child: Text('English')),
              ],
              onChanged: (tag) {
                settings.setLocale(tag);
                AppLocaleBridge.setSystemAppLocale(tag);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 安全分区：生物识别锁（Hail 同款应用锁，仅 Android）。
///
/// 开启流程会先做一次试验证：设备没有可用凭据时开不了 —— 防止把自己
/// 锁在应用外面。锁的拦截点在根组件（app.dart）：冷启动与从后台回到
/// 前台都要过一次验证。
class _SecuritySection extends StatelessWidget {
  const _SecuritySection();

  @override
  Widget build(BuildContext context) {
    // local_auth 只有 Android / iOS 实现；本项目无 iOS 目录，桌面直接不显示。
    if (!Platform.isAndroid) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return SectionCard(
      title: l10n.securitySection,
      child: Consumer<SettingsService>(
        builder: (context, display, _) => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.biometricLockTitle),
          subtitle: Text(l10n.biometricLockDesc),
          value: display.biometricLock,
          onChanged: (want) => _toggle(context, display, l10n, want),
        ),
      ),
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
        showAppToast(context, l10n.biometricLockUnavailable, error: true);
      }
      return;
    }
    // 试验证：这一步过了才允许开启，确保锁得上也解得开。
    final ok = await biometric.authenticate(l10n.biometricLockDesc);
    if (!context.mounted) return;
    if (ok) {
      await display.setBiometricLock(true);
    } else {
      showAppToast(context, l10n.biometricLockUnavailable, error: true);
    }
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 关于独立成页（InstallerX 同款效果背景 + 纹理集彩蛋）
    return SectionCard(
      title: l10n.aboutSection,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.info_outline),
        title: Text(l10n.aboutSection),
        subtitle: Text(l10n.aboutEntryDesc),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => pushPage(
          context,
          AboutPage(settings: context.read<SettingsService>()),
        ),
      ),
    );
  }
}
