import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:provider/provider.dart';

// 注意：这里一律用 package: 导入（别混相对导入）—— ui/app.dart 等文件用
// package: 引这些类型，混用会把同一个文件当成两个库，AppSettings /
// ServerController 传参就报「类型不相容」。
import 'package:local2api/services/app_locale_bridge.dart';
import 'package:local2api/services/app_settings.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/device_corner_service.dart';
import 'package:local2api/services/display_mode_service.dart';
import 'package:local2api/services/model_auto_refresh.dart';
import 'package:local2api/services/character_store.dart';
import 'package:local2api/services/chat_avatar_store.dart';
import 'package:local2api/services/profile_service.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/chat_sim_store.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/services/tts/tts_export_licenses.dart';
import 'package:local2api/services/usage_stats.dart';
import 'package:local2api/ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 液态玻璃着色器预热（NaviFlash 同款初始化，含渐进模糊着色器
  // ProgressiveBlur.preload —— 渐变模糊顶栏要用）
  await LiquidGlassWidgets.initialize();

  // 随包原生编码器（SILK 定点 SDK / LAME）的第三方许可登记，
  // 关于页的「开源许可」里能看到。
  registerTtsExportLicenses();

  final settings = AppSettings();
  final displaySettings = SettingsService();
  final store = ConfigStore();
  final profileStore = ProfileStore();
  await Future.wait([
    settings.load(),
    displaySettings.load(),
    store.load(),
    profileStore.load(),
    // token 用量账本：代理每接住一次请求就记一条（见 UsageStats）
    usageStats.load(),
    // 对话模拟的本地存档（按模型组存，默认一直留着）
    chatSimStore.load(),
    // 角色卡（对话模拟的场景预设；内置流萤/蕾姆由代码生成，不在这里）
    characterStore.load(),
    // 对话模拟的用户 / 助手自定义头像（一张几十 KB 的 JPEG，base64 落盘）
    chatAvatarStore.load(),
    // 设备物理屏幕圆角（原生通道读一次并缓存）：iOS 风格转场圆角自适应要用，
    // 主题在首帧就得拿到值，必须等它回来再 runApp。
    DeviceCornerService.load(),
  ]);

  final controller = ServerController(store);

  // 屏幕帧率偏好是窗口属性，系统不持久保存，每次启动重新应用一次
  // （仅 Android 生效，失败静默）。
  await DisplayModeService.restorePreferred(displaySettings);

  // 从「广场预设」时代升级上来的首次启动：认领旧上游、回填激活标记。
  // 只跑一次（索引键存在即跳过），且只加字段不删东西，降级回旧版也安全。
  if (ProfileService.migrateIfNeeded(profileStore, store.config)) {
    store.update(store.config);
    await profileStore.flush();
  }

  // 内置 OpenCode Zen 上游：默认装进配置并启用（一次性门闩）。
  // 发现页现在列的是 config.upstreams，档案不装配就什么都不显示 ——
  // 新装与「升级上来但没激活过」的配置都会看不到那个预制提供商。
  if (await ProfileService.ensureBuiltinDefaultUpstream(
    store: profileStore,
    config: store.config,
  )) {
    store.update(store.config);
    await profileStore.flush();
  }

  // 内置 MiMo TTS 语音上游：同一次性门闩套路（三个 TTS 模型全勾，
  // API Key 留空由用户在发现页的卡片里自填）。
  if (await ProfileService.ensureBuiltinMimoTtsUpstream(store.config)) {
    store.update(store.config);
  }

  // 老配置的自动更新策略回填：内置 Zen / MiMo 补成 7 天一次（一次性门闩）。
  if (await ModelAutoRefresh.backfillBuiltinDefaults(store.config)) {
    store.update(store.config);
  }

  // Android 13+：跟随系统「应用语言」设置（用户在系统里选过则以其为准）
  final localeTag = await AppLocaleBridge.getSystemAppLocale();
  if (localeTag != null && localeTag.isNotEmpty) {
    settings.syncFromSystemLocaleCode(localeTag);
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: displaySettings),
        ChangeNotifierProvider<ProfileStore>.value(value: profileStore),
        // 角色卡：对话模拟的场景预设（内置流萤/蕾姆 + 用户自建）
        ChangeNotifierProvider<CharacterStore>.value(value: characterStore),
      ],
      child: LiquidGlassWidgets.wrap(
        brightnessResolver: Theme.maybeBrightnessOf,
        child: Local2ApiApp(settings: settings, controller: controller),
      ),
    ),
  );

  // 配置里勾选了「启动时自动运行服务」
  if (store.config.autoStart) {
    await controller.start();
  }

  // 上游模型列表的自动更新（后台跑，不挡首屏）。
  //
  // 内置的 Zen / MiMo 默认 7 天一次、且 `modelsRefreshedAtMs` 是 0 ——
  // 所以「用户第一次进入应用」这两个上游会各刷一次清单，之后再按周走。
  // 进程常开的桌面端靠 startWatching 定期巡检（不碰网络，只看有没有到点）。
  final autoRefresh = ModelAutoRefresh(store);
  autoRefresh
      .runDue()
      .then((results) {
        for (final r in results) {
          if (r.changed) {
            debugPrint(
              '模型列表已更新（${r.upstreamName}）：+${r.added.length} '
              '-${r.removed.length}',
            );
          }
        }
      })
      .catchError((Object e) {
        debugPrint('模型列表自动更新失败：$e');
      });
  autoRefresh.startWatching();
}
