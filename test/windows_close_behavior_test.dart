// Windows 关闭按钮默认行为 + 原生任务对话框复选框的回归。
//
// 覆盖两块：
//   1. SettingsService 的持久化：默认「每次询问」、改了能存住、脏值回退到安全档；
//   2. WindowsTaskDialog 的新返回契约：{index, verified} —— 「下次也是这样」
//      那个复选框的勾选状态就是要从这里拿回来的。
//
// 真正的窗口隐藏 / 退出动作用 window_manager + tray_manager 走平台通道，
// 在 widget test 里没有意义（而且 WindowService 那边对插件缺失是整体降级
// 成 no-op 的），所以这里只测到「决定怎么关」之前这一层。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/services/window_service.dart';
import 'package:local2api/services/windows_task_dialog.dart';
import 'package:local2api/src/enums.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsService.windowCloseBehavior', () {
    test('没存过 → 每次询问', () async {
      SharedPreferences.setMockInitialValues({});
      final service = SettingsService();
      await service.load();
      expect(service.windowCloseBehavior, WindowCloseBehavior.ask);
    });

    test('改过之后能存住（换一个实例读回来）', () async {
      SharedPreferences.setMockInitialValues({});
      final service = SettingsService();
      await service.load();
      await service.setWindowCloseBehavior(WindowCloseBehavior.minimizeToTray);
      expect(service.windowCloseBehavior, WindowCloseBehavior.minimizeToTray);

      final reloaded = SettingsService();
      await reloaded.load();
      expect(reloaded.windowCloseBehavior, WindowCloseBehavior.minimizeToTray);

      await service.setWindowCloseBehavior(WindowCloseBehavior.exit);
      final again = SettingsService();
      await again.load();
      expect(again.windowCloseBehavior, WindowCloseBehavior.exit);
    });

    test('脏值 / 不认识的名字 → 回退到「每次询问」', () async {
      // 「直接退出」那档是不可逆的，读到脏数据宁可回到会问一句的那档。
      SharedPreferences.setMockInitialValues({
        'local2api.windowCloseBehavior': 'nonsense',
      });
      final service = SettingsService();
      await service.load();
      expect(service.windowCloseBehavior, WindowCloseBehavior.ask);
    });

    test('同值重复 set 不刷盘（与项目里其它 setter 同构）', () async {
      SharedPreferences.setMockInitialValues({});
      final service = SettingsService();
      await service.load();
      var notified = 0;
      service.addListener(() => notified++);
      await service.setWindowCloseBehavior(WindowCloseBehavior.ask);
      expect(notified, 0, reason: '值没变就不该 notify，免得整棵设置页重刷');
    });
  });

  group('关闭询问框的结果翻译（WindowService.resolveDialogOutcome）', () {
    test('取消 → null（窗口保持原样）', () {
      expect(WindowService.resolveDialogOutcome(null), isNull);
    });

    test('选第一个链接（收进托盘）', () {
      expect(
        WindowService.resolveDialogOutcome(
          const TaskDialogResult(index: 0, verified: false),
        ),
        WindowCloseBehavior.minimizeToTray,
      );
    });

    test('选第二个链接（退出程序）', () {
      expect(
        WindowService.resolveDialogOutcome(
          const TaskDialogResult(index: 1, verified: false),
        ),
        WindowCloseBehavior.exit,
      );
    });

    test('勾没勾复选框都不影响「关哪个动作」', () {
      expect(
        WindowService.resolveDialogOutcome(
          const TaskDialogResult(index: 1, verified: true),
        ),
        WindowCloseBehavior.exit,
      );
    });
  });

  group('WindowsTaskDialog 返回的 verified', () {
    const channelName = 'com.memz2345.local2api/task_dialog';
    const channel = MethodChannel(channelName);

    void mockReply(Object? reply) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => reply);
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
    }

    test('勾上「下次也是这样」→ verified 为 true', () async {
      mockReply({'index': 1, 'verified': true});
      final result = await WindowsTaskDialog.show(
        title: 'Local2API',
        heading: '您点击了关闭按钮，您希望？',
        verificationText: '下次也是这样',
        links: [
          (text: '收进托盘', subtitle: '窗口藏起来'),
          (text: '退出程序', subtitle: '服务也停'),
        ],
      );

      expect(result, isNotNull);
      expect(result!.index, 1);
      expect(result.verified, isTrue);
    });

    test('没勾 → verified 为 false；没给复选框文案时也一样', () async {
      mockReply({'index': 0, 'verified': false});
      final result = await WindowsTaskDialog.show(
        title: 'Local2API',
        heading: '您点击了关闭按钮，您希望？',
        links: [(text: '收进托盘', subtitle: '')],
      );
      expect(result!.index, 0);
      expect(result.verified, isFalse);
    });

    test('原生层回 null（取消 / 创建失败）→ 整个结果是 null', () async {
      mockReply(null);
      final result = await WindowsTaskDialog.show(
        title: 'Local2API',
        heading: '您点击了关闭按钮，您希望？',
        links: [(text: '退出程序', subtitle: '')],
      );
      expect(result, isNull);
    });

    test('点 × / Esc（取消）→ 返回 null，绝不等于「收进托盘」', () async {
      mockReply(null);
      final result = await WindowsTaskDialog.show(
        title: 'Local2API',
        heading: '您点击了关闭按钮，您希望？',
        verificationText: '下次也是这样',
        links: [(text: '收进托盘', subtitle: '')],
      );

      // 这是这个用例的真正目的：WindowService 把 null 翻成 null（什么都不做）。
      // 以前翻成 minimizeToTray —— 用户误点一下 × 窗口就消失，还以为程序自己关了。
      expect(WindowService.resolveDialogOutcome(result), isNull);
    });

    test('平台通道抛异常 → 返回 null（交回 Flutter 侧兜底）', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'boom'),
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final result = await WindowsTaskDialog.show(
        title: 'Local2API',
        heading: '您点击了关闭按钮，您希望？',
        links: [(text: '退出程序', subtitle: '')],
      );
      expect(result, isNull);
    });
  });
}
