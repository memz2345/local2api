// 「对话模拟」顶栏改造（角色卡 + 三个点）与用户/助手自定义头像的回归测试。
//
// 三块：
// 1) 头像存储 ChatAvatarStore：设置 / 恢复默认 / 重启读回 / system 拒收；
// 2) 两套风格顶栏：只留「角色卡 + 三个点」，其余动作（添加消息 / 重新生成 /
//    清空 / 头像 / 对话设置）进菜单；
// 3) 自定义头像在角色头像上生效（Image.memory 渲染）。
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/chat_avatar_store.dart';
import 'package:local2api/services/chat_sim_store.dart';
import 'package:local2api/services/chat_simulation.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/chat_simulation_page.dart';
import 'package:local2api/ui/miuix/miuix_chat_simulation_page.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'miuix_finders.dart';

/// 2×2 红色 PNG（标准 chunk 结构，Flutter 解码器认），给头像渲染用。
final Uint8List kTinyPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x02,
  0x08, 0x02, 0x00, 0x00, 0x00, 0xFD, 0xD4, 0x9A, 0x73, 0x00, 0x00, 0x00,
  0x10, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x44, 0x0C, 0x10, 0x0A, 0x00, 0x1F, 0xEE, 0x03, 0xFD, 0x8B, 0x5F, 0x14,
  0xD4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60,
  0x82,
]);

/// 页面里出现「自定义头像」的 Image（MemoryImage）个数。
Finder memoryImages() => find.byWidgetPredicate(
  (w) => w is Image && w.image is MemoryImage,
);

/// 卸载页面并把防抖计时器跑完。
///
/// 页面 dispose 时 `ChatSimController._persist()` 会写一次存档（400ms
/// 防抖），不跑完 flutter_test 会报 "A Timer is still pending" —— 与
/// `chat_sim_images_test.dart` 尾部同一套收尾。
Future<void> teardownPage(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 600));
  // setAvatar 的防抖也顺手清干净（没有 pending 时是空操作）。
  await chatAvatarStore.flush();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('头像存储', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('设置后能读回，恢复默认（null）后清掉', () async {
      final store = ChatAvatarStore();
      await store.load();
      expect(store.avatarOf(ChatRole.user), isNull);

      await store.setAvatar(ChatRole.user, kTinyPng);
      expect(store.hasAvatarOf(ChatRole.user), isTrue);
      expect(store.avatarOf(ChatRole.user), kTinyPng);

      await store.setAvatar(ChatRole.user, null);
      expect(store.hasAvatarOf(ChatRole.user), isFalse);
      await store.flush();
      store.dispose();
    });

    test('落盘后重启读回（新实例），用户与助手互不串', () async {
      final store = ChatAvatarStore();
      await store.load();
      await store.setAvatar(ChatRole.user, kTinyPng);
      await store.flush();
      store.dispose();

      final again = ChatAvatarStore();
      await again.load();
      expect(again.avatarOf(ChatRole.user), isNotNull);
      expect(again.avatarOf(ChatRole.assistant), isNull);
      await again.flush();
      again.dispose();
    });

    test('system 角色不接受设置', () async {
      final store = ChatAvatarStore();
      await store.load();
      await store.setAvatar(ChatRole.system, kTinyPng);
      expect(store.avatarOf(ChatRole.system), isNull);
      await store.flush();
      store.dispose();
    });
  });

  group('对话模拟顶栏与头像', () {
    late ConfigStore configStore;
    late ServerController controller;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      configStore = ConfigStore();
      await configStore.load();
      controller = ServerController(configStore);
      // 全局单例：抹掉别的用例可能留下的头像（顺带取消防抖定时器）。
      await chatAvatarStore.setAvatar(ChatRole.user, null);
      await chatAvatarStore.setAvatar(ChatRole.assistant, null);
      await chatAvatarStore.flush();
    });

    tearDown(() async {
      controller.dispose();
      chatSimStore.clear();
      await chatAvatarStore.flush();
      await chatSimStore.flush();
    });

    Widget materialPage() => MaterialApp(
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light(),
      home: ChatSimulationPage(
        controller: controller,
        model: 'zen-free',
        scope: 'toolbar-test',
        groupModels: const ['longcat-2.5-preview-free'],
      ),
    );

    Widget miuixPage() => MiuixThemeController(
      colorSchemeMode: miuixColorSchemeModeOf(themeMode: ThemeMode.light),
      keyColor: const Color(0xFF386A20),
      child: Builder(
        builder: (context) {
          final miuix = MiuixTheme.of(context);
          return MaterialApp(
            locale: const Locale('zh', 'CN'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light().copyWith(
              colorScheme: materialSchemeFromMiuix(
                miuix.colors,
                miuix.brightness,
              ),
            ),
            home: MiuixChatSimulationPage(
              controller: controller,
              model: 'zen-free',
              scope: 'toolbar-test',
              groupModels: const ['longcat-2.5-preview-free'],
            ),
          );
        },
      ),
    );

    testWidgets('Material：顶栏只剩「角色卡 + 三个点」，原动作不再外露', (tester) async {
      await tester.pumpWidget(materialPage());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.face_retouching_natural), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      // 原来的三个图标不该再直接露在顶栏上（只在菜单里，此时未展开）。
      expect(find.byIcon(Icons.add_comment_outlined), findsNothing);
      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(find.byIcon(Icons.delete_sweep_outlined), findsNothing);
      expect(tester.takeException(), isNull);
      await teardownPage(tester);
    });

    testWidgets('Material：三个点菜单含全部动作与对话设置', (tester) async {
      await tester.pumpWidget(materialPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('添加消息'), findsOneWidget);
      expect(find.text('重新生成'), findsOneWidget);
      expect(find.text('头像设置'), findsOneWidget);
      expect(find.text('清空对话'), findsOneWidget);
      expect(find.text('对话设置'), findsOneWidget);
      // 菜单项里带上原动作图标
      expect(find.byIcon(Icons.add_comment_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_sweep_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
      await teardownPage(tester);
    });

    testWidgets('Material：换头像后角色头像用自定义图渲染，恢复默认还原', (tester) async {
      await tester.pumpWidget(materialPage());
      await tester.pumpAndSettle();
      // 没有自定义头像时，页面上不该有 MemoryImage。
      expect(memoryImages(), findsNothing);

      await chatAvatarStore.setAvatar(ChatRole.user, kTinyPng);
      await tester.pump();
      // 输入台的角色头像（默认按用户发）换成自定义图。
      expect(memoryImages(), findsWidgets);

      await chatAvatarStore.setAvatar(ChatRole.user, null);
      await tester.pump();
      expect(memoryImages(), findsNothing);
      expect(tester.takeException(), isNull);
      await teardownPage(tester);
    });

    testWidgets('miuix：顶栏只剩「角色卡 + 三个点」，点开底部菜单', (tester) async {
      await tester.pumpWidget(miuixPage());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.face_retouching_natural), findsOneWidget);
      final more = miuixIcon(AppIconNames.more);
      expect(more, findsOneWidget);
      // 原动作不在顶栏。
      expect(find.byIcon(Icons.add_comment_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_sweep_outlined), findsNothing);

      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text('添加消息'), findsOneWidget);
      expect(find.text('头像设置'), findsOneWidget);
      expect(find.text('清空对话'), findsOneWidget);
      expect(find.text('对话设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await teardownPage(tester);
    });

    testWidgets('miuix：换头像后角色头像用自定义图渲染', (tester) async {
      await tester.pumpWidget(miuixPage());
      await tester.pumpAndSettle();
      expect(memoryImages(), findsNothing);

      // 输入台当前角色是用户 —— 直接设用户头像验证渲染管线。
      await chatAvatarStore.setAvatar(ChatRole.user, kTinyPng);
      await tester.pump();
      expect(memoryImages(), findsWidgets);
      expect(tester.takeException(), isNull);
      await teardownPage(tester);
    });
  });
}
