import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/jump_list_service.dart';
import 'package:local2api/services/quick_actions.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Windows 跳转列表的 Dart 侧：清单内容、通道协议与动作串解析。
///
/// 原生那半（ICustomDestinationList / WM_COPYDATA）在 `flutter test` 里跑不到，
/// 这里用 mock method handler 钉住**发过去的载荷形状**——那是 C++ 端唯一
/// 关心的东西，形状错了菜单就是空的。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.memz2345.local2api/jumplist');

  late ConfigStore configStore;
  late ServerController controller;
  final calls = <MethodCall>[];
  Object? replyFor;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    replyFor = null;
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return replyFor;
    });
    // ⚠️ ServerController 的构造函数里有 NetworkInterface.list() 这种真实
    // 异步 IO；放在 testWidgets 体内建会被假时钟吊死（10 分钟超时），
    // 所以和其它页面测试一样放 setUp（logs_filter_test 同款）。
    configStore = ConfigStore();
    await configStore.load();
    controller = ServerController(configStore)..webUiAutoStart = false;
  });

  tearDown(() {
    controller.dispose();
    configStore.dispose();
  });

  void useConfig(ProxyConfig cfg) => configStore.update(cfg);

  Future<AppLocalizations> l10nOf(WidgetTester tester) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return l10n;
  }

  Upstream upstream(String id, String name, {int models = 1}) => Upstream(
    id: id,
    name: name,
    type: UpstreamType.openai,
    baseUrl: 'https://$id.example/v1',
    models: [for (var i = 0; i < models; i++) ModelEntry(publicName: '$name-$i')],
  );

  group('跳转清单条目', () {
    testWidgets('任务区固定三项，顺序是 启动 / 暂停 / 设置', (tester) async {
      final l10n = await l10nOf(tester);
      useConfig(ProxyConfig(listenHost: '0.0.0.0', listenPort: 8123));
      // ConfigStore.update 会挂一个 400ms 的合并保存计时器，不放它跑完
      // 测试会报「A Timer is still pending」。
      await tester.pump(const Duration(milliseconds: 500));

      final items = quickTaskItems(l10n, controller);
      expect(
        items.map((i) => i.action),
        [QuickAction.serverStart, QuickAction.serverPause, QuickAction.settings],
      );
      // 副标题把「监听哪个地址」直接写在菜单上，省得用户猜。
      expect(items.first.subtitle, contains('0.0.0.0:8123'));

    });

    testWidgets('「最近」= 当前的上游组，最多 5 条', (tester) async {
      final l10n = await l10nOf(tester);
      final cfg = ProxyConfig(
        upstreams: [
          for (var i = 0; i < 7; i++) upstream('u$i', '组 $i'),
        ],
      );

      final items = quickRecentItems(l10n, cfg);
      expect(items.length, 5);
      expect(items.first.action, 'upstream:u0');
      expect(items.first.title, '组 0');
      expect(items.first.subtitle, '1 个模型');
    });

    test('动作串解析：只有 upstream:<id> 能解出 id', () {
      expect(QuickAction.upstreamIdOf(QuickAction.upstream('abc')), 'abc');
      expect(QuickAction.upstreamIdOf('settings'), isNull);
      expect(QuickAction.upstreamIdOf('upstream:'), isNull);
    });
  });

  group('通道协议', () {
    testWidgets('publishWindowsJumpList 发的载荷形状', (tester) async {
      final l10n = await l10nOf(tester);
      useConfig(
        ProxyConfig(
          listenHost: '127.0.0.1',
          listenPort: 8080,
          upstreams: [upstream('a', '家里那组', models: 3)],
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      replyFor = true;

      final ok = await publishWindowsJumpList(l10n, controller);
      expect(ok, isTrue);
      expect(calls.map((c) => c.method), ['setJumpList']);

      final args = calls.single.arguments as Map;
      expect(args['recentTitle'], '最近');
      final tasks = args['tasks'] as List;
      // 任务三项 + 「最近」一条上游组
      expect(tasks.length, 3);
      expect(
        (tasks.first as Map)['action'],
        QuickAction.serverStart,
      );
      final recents = args['recents'] as List;
      expect(recents.length, 1);
      expect((recents.single as Map)['name'], '家里那组');
      expect((recents.single as Map)['subtitle'], '3 个模型');
    });

    testWidgets('consumeLaunchAction 取回冷启动动作', (tester) async {
      await l10nOf(tester);
      replyFor = {'action': 'settings'};

      final action = await JumpListService.instance.consumeLaunchAction();
      expect(action, 'settings');
      expect(calls.map((c) => c.method), ['consumeLaunchArgs']);
    });

    testWidgets('通道不存在时静默降级，不再反复撞', (tester) async {
      await l10nOf(tester);
      // 没有 mock handler 时测试环境的通道调用永远不返回，所以这里用
      // 「抛 MissingPluginException」来模拟非 Windows 壳 / 老 runner。
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw MissingPluginException();
          });

      expect(
        await JumpListService.instance.consumeLaunchAction(),
        isNull,
      );
      // 第二次不会再发（_available 已被 MissingPluginException 关掉）。
      final before = calls.length;
      await JumpListService.instance.clear();
      expect(calls.length, before);

      // 复位单例可用性，免得影响同一次运行里的其它用例。
      JumpListService.instance.resetAvailableForTest();
    });
  });
}
