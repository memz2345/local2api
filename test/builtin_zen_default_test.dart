// test/builtin_zen_default_test.dart
//
// 回归：内置的 OpenCode Zen 上游必须**默认启用**并出现在发现页。
//
// 曾经的 bug：发现页改版成「上游服务列表」（列 `config.upstreams`）之后，
// 内置档案只活在 ProfileStore 里、从不装配 —— 全新安装（以及「装过但没手动
// 激活过」的配置）里上游列表是空的，那个预制提供商就凭空消失了。
//
// 这里钉三条：
//   1. 首次启动把 OpenCode Zen 装进配置、打开开关、标成激活；
//   2. 只跑一次（门闩），且**不复活**用户关掉 / 删掉的上游；
//   3. 装完之后发现页上确实有这张卡。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/builtin_profiles.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/profile_service.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/ui/profiles_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一次性门闩的持久化键（ProfileService 里的私有常量，这里是它的契约）。
const String _latchKey = 'local2api.builtinZen.default.v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProfileStore profileStore;
  late ProxyConfig config;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    profileStore = ProfileStore();
    await profileStore.load();
    config = ProxyConfig();
  });

  tearDown(() => profileStore.dispose());

  test('首次启动：装进配置、启用、标成激活', () async {
    final installed = await ProfileService.ensureBuiltinDefaultUpstream(
      store: profileStore,
      config: config,
    );

    expect(installed, isTrue);
    final zen = ProfileService.upstreamOf(config, kZenUpstreamId);
    expect(zen, isNotNull);
    expect(zen!.enabled, isTrue, reason: '默认启用的就是这个上游');
    expect(zen.name, 'OpenCode Zen');
    expect(zen.baseUrl, kOpenCodeZenBaseUrl);
    expect(zen.managedBy, kZenProfileId, reason: '必须认领给内置档案');
    expect(zen.models, isNotEmpty);
    // 容灾路由（对外名 zen-free）要在，客户端才有得填。
    expect(
      zen.models.any(
        (m) => ProfileService.isRoute(m) && m.publicName == kZenRouteName,
      ),
      isTrue,
    );
    expect(profileStore.activeId, kZenProfileId);
  });

  test('只跑一次：第二次调用什么都不做', () async {
    await ProfileService.ensureBuiltinDefaultUpstream(
      store: profileStore,
      config: config,
    );
    final modelsBefore = ProfileService.upstreamOf(
      config,
      kZenUpstreamId,
    )!.models.length;

    final again = await ProfileService.ensureBuiltinDefaultUpstream(
      store: profileStore,
      config: config,
    );

    expect(again, isFalse);
    expect(
      ProfileService.upstreamOf(config, kZenUpstreamId)!.models.length,
      modelsBefore,
    );
    expect(config.upstreams.length, 1);
  });

  test('不复活：用户关掉过的上游不会被重新打开', () async {
    await ProfileService.ensureBuiltinDefaultUpstream(
      store: profileStore,
      config: config,
    );
    final zen = ProfileService.upstreamOf(config, kZenUpstreamId)!;
    zen.enabled = false;
    // 模拟「已经跑过门闩」的下一轮启动 / 升级。
    SharedPreferences.setMockInitialValues({_latchKey: true});

    final installed = await ProfileService.ensureBuiltinDefaultUpstream(
      store: profileStore,
      config: config,
    );

    expect(installed, isFalse);
    expect(zen.enabled, isFalse, reason: '用户特意关掉的，不该被升级流程打开');
  });

  test('门闩已落过 + 上游缺失 → 不再补（用户删了就是删了）', () async {
    SharedPreferences.setMockInitialValues({_latchKey: true});

    final installed = await ProfileService.ensureBuiltinDefaultUpstream(
      store: profileStore,
      config: config,
    );

    expect(installed, isFalse);
    expect(config.upstreams, isEmpty);
  });

  testWidgets('装完之后发现页上有这张上游卡', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final configStore = ConfigStore();
    await configStore.load();
    final controller = ServerController(configStore);
    addTearDown(() {
      configStore.dispose();
      controller.dispose();
    });

    final installed = await ProfileService.ensureBuiltinDefaultUpstream(
      store: profileStore,
      config: configStore.config,
    );
    expect(installed, isTrue);
    configStore.update(configStore.config);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ProfileStore>.value(value: profileStore),
        ],
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ProfilesPage(controller: controller),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('OpenCode Zen'), findsWidgets);
    expect(find.text('还没有上游，先添加一个'), findsNothing);
  });
}
