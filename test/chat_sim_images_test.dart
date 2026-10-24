// 图片输入（多模态请求体）+ 输入区布局 + 上下文详情弹窗。
//
// 布局那几条刻意在 360×640 的窄屏上跑：用户报的就是「输入框被挤成竖排」，
// 宽屏测不出来。RenderFlex 溢出会以异常的形式挂在 tester 上，
// 所以每条布局断言都顺手 takeException() 一次。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/chat_sim_store.dart';
import 'package:local2api/services/chat_simulation.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/chat_simulation_page.dart';
import 'package:local2api/ui/miuix/miuix_chat_simulation_page.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';
import 'package:local2api/widgets/context_ring.dart';
import 'package:local2api/widgets/miuix/miuix_text_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一张最小的真 JPEG（1×1），够字节头嗅探与 base64 编码。
final Uint8List kTinyJpeg = Uint8List.fromList(<int>[
  0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
  0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9,
]);

ChatAttachment kImageAttachment({String name = 'shot.jpg'}) => ChatAttachment(
  name: name,
  isImage: true,
  sizeBytes: kTinyJpeg.length,
  thumbnail: kTinyJpeg,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('附件 → 请求体', () {
    test('图片 MIME 从字节头嗅探，认不出来时按 JPEG 报', () {
      expect(ChatAttachment.sniffImageMime(kTinyJpeg), 'image/jpeg');
      expect(
        ChatAttachment.sniffImageMime(<int>[
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
          ...List.filled(8, 0),
        ]),
        'image/png',
      );
      final webp = <int>[
        ...'RIFF'.codeUnits,
        0,
        0,
        0,
        0,
        ...'WEBP'.codeUnits,
        0,
        0,
      ];
      expect(ChatAttachment.sniffImageMime(webp), 'image/webp');
      expect(ChatAttachment.sniffImageMime(<int>[1, 2, 3]), '');
    });

    test('dataUrl 是 image_picker 压完那份字节的 base64', () {
      final a = kImageAttachment();
      expect(
        a.dataUrl,
        'data:image/jpeg;base64,${base64Encode(kTinyJpeg)}',
      );
      // 只有元信息（缩略图被落盘预算砍掉）的发不出去
      expect(
        ChatAttachment(name: 'x', isImage: true).dataUrl,
        isNull,
      );
    });

    test('没有图片时 content 仍是字符串（纯文本车道照收）', () {
      final m = ChatMsg(ChatRole.user, '你好');
      expect(m.toWire(), {'role': 'user', 'content': '你好'});
      expect(
        ChatMsg(ChatRole.user, '带文件', attachments: [
          ChatAttachment(name: 'a.pdf', isImage: false, sizeBytes: 10),
        ]).toWire(),
        {'role': 'user', 'content': '带文件'},
      );
    });

    test('带图片时 content 换成多模态 parts：text 段 + 每图一个 image_url', () {
      final m = ChatMsg(
        ChatRole.user,
        '这张图里是什么',
        attachments: [kImageAttachment(), kImageAttachment(name: 'b.jpg')],
      );
      final wire = m.toWire();
      expect(wire['role'], 'user');
      final parts = wire['content'] as List;
      expect(parts, hasLength(3));
      expect(parts.first, {'type': 'text', 'text': '这张图里是什么'});
      expect(
        parts[1],
        {
          'type': 'image_url',
          'image_url': {'url': 'data:image/jpeg;base64,${base64Encode(kTinyJpeg)}'},
        },
      );
    });

    test('只有图片没有文字时不塞空 text 段', () {
      final m = ChatMsg(ChatRole.user, '   ', attachments: [kImageAttachment()]);
      final parts = (m.toWire()['content'] as List);
      expect(parts, hasLength(1));
      expect((parts.single as Map)['type'], 'image_url');
    });

    test('includeImages:false = 图只留在界面，请求体里只有文字', () {
      final m = ChatMsg(
        ChatRole.user,
        '看图',
        attachments: [kImageAttachment()],
      );
      expect(m.toWire(includeImages: false), {'role': 'user', 'content': '看图'});
      // 空文字 + 关带图 = 这条没内容可发
      final empty = ChatMsg(
        ChatRole.user,
        '',
        attachments: [kImageAttachment()],
      );
      expect(empty.sendable(), isTrue);
      expect(empty.sendable(includeImages: false), isFalse);
    });

    test('bodyOf 会把「只有图」那条也带出去', () {
      final body = ChatSimulator.bodyOf(
        model: 'm',
        messages: [
          ChatMsg(ChatRole.user, '', attachments: [kImageAttachment()]),
          ChatMsg(ChatRole.user, '   '),
        ],
      );
      final sent = jsonDecode(body) as Map<String, dynamic>;
      expect(sent['messages'], hasLength(1));
      expect((sent['messages'].single['content'] as List), hasLength(1));

      final off = jsonDecode(
        ChatSimulator.bodyOf(
          model: 'm',
          messages: [ChatMsg(ChatRole.user, '', attachments: [kImageAttachment()])],
          includeImages: false,
        ),
      ) as Map<String, dynamic>;
      expect(off['messages'], isEmpty);
    });

    test('落盘预算砍掉缩略图后，那条只剩元信息、发不出去', () async {
      final a = kImageAttachment();
      final back = ChatAttachment.fromJson(a.toJson(includeThumbnail: false));
      expect(back.isImage, isTrue);
      expect(back.thumbnail, isNull);
      expect(back.hasImageData, isFalse);
      expect(ChatMsg(ChatRole.user, '', attachments: [back]).sendable(), isFalse);
    });
  });

  group('上下文详情', () {
    test('数字齐了：百分比 / 用量 / 估算标记 / 输出上限 / 模型 / 图片数', () {
      final config = ProxyConfig()
        ..upstreams = [
          Upstream(
            id: 'u',
            name: 'U',
            baseUrl: 'http://127.0.0.1:1',
            models: [
              ModelEntry(
                publicName: 'zen-free',
                contextLength: 2000,
                maxOutputTokens: 300,
              ),
            ],
          ),
        ];
      final sim = ChatSimController(
        model: 'zen-free',
        config: config,
        scope: '',
      );
      sim.add(ChatRole.user, '一二三四五', [kImageAttachment()]);

      final d = sim.contextDetails();
      // 默认那条系统提示词 + 5 个汉字 + 一张图 600
      expect(d.estimated, isTrue);
      expect(
        d.used,
        estimateContextTokens(ChatSimController.defaultSystemPrompt) +
            estimateContextTokens('一二三四五') +
            kImageTokenEstimate,
      );
      expect(d.limit, 2000);
      expect(d.maxOutput, 300);
      expect(d.model, 'zen-free');
      expect(d.images, 1);
      expect(d.messages, 2);
      expect(d.percent, closeTo(d.used / 2000 * 100, 0.001));
      sim.dispose();
    });

    test('关掉带图后图片不再算进占用', () {
      final sim = ChatSimController(
        model: 'm',
        config: ProxyConfig(),
        scope: '',
      );
      sim.add(ChatRole.user, '看图', [kImageAttachment()]);
      final withImg = sim.contextDetails();
      sim.toggleSendImages();
      final without = sim.contextDetails();
      expect(without.used, withImg.used - kImageTokenEstimate);
      sim.dispose();
    });

    test('上一轮有 usage 时用精确值，不再估', () {
      final sim = ChatSimController(
        model: 'm',
        config: ProxyConfig(),
        scope: '',
      );
      sim.add(ChatRole.user, '问');
      sim.messages.add(
        ChatMsg(ChatRole.assistant, '答', usageTokens: 1234),
      );
      final d = sim.contextDetails();
      expect(d.used, 1234);
      expect(d.estimated, isFalse);
      sim.dispose();
    });
  });

  group('输入区布局（360×640 窄屏）', () {
    late ConfigStore configStore;
    late ServerController controller;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await chatSimStore.load();
      chatSimStore.clear();
      configStore = ConfigStore();
      await configStore.load();
      controller = ServerController(configStore);
    });

    tearDown(() {
      controller.dispose();
      chatSimStore.clear();
    });

    Future<void> useNarrowScreen(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Widget materialPage({String model = 'zen-free'}) => MaterialApp(
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light(),
      home: ChatSimulationPage(
        controller: controller,
        model: model,
        scope: 'opencodezen',
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
              scope: 'opencodezen',
              groupModels: const ['longcat-2.5-preview-free'],
            ),
          );
        },
      ),
    );

    testWidgets('Material：输入框与角色/发送同排，工具行另起一行', (tester) async {
      await useNarrowScreen(tester);
      await tester.pumpWidget(materialPage());
      await tester.pumpAndSettle();

      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      final box = tester.getSize(field);
      // 与角色头像 / 占用环 / 发送键共享一行（360 窄屏上仍占输入区大头）
      expect(box.width, greaterThan(120));

      final fieldBottom = tester.getBottomLeft(field).dy;
      for (final icon in [
        Icons.memory_outlined,
        Icons.insert_drive_file_outlined,
        Icons.mic_none,
        Icons.image_outlined,
        Icons.photo_camera_outlined,
      ]) {
        expect(
          tester.getCenter(find.byIcon(icon)).dy,
          greaterThan(fieldBottom),
          reason: '$icon 应该在输入框下面的工具行，而不是挤在同一行',
        );
      }
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('Material：长模型名下输入台不溢出，模型入口在工具行', (tester) async {
      await useNarrowScreen(tester);
      await tester.pumpWidget(
        materialPage(model: 'longcat-2.5-preview-free'),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.memory_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('Material：点占用环弹详情，不再只挂在 tooltip 上', (tester) async {
      await useNarrowScreen(tester);
      await tester.pumpWidget(materialPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ContextRing));
      await tester.pumpAndSettle();

      expect(find.text('上下文占用'), findsOneWidget);
      expect(find.text('请求模型 zen-free'), findsOneWidget);
      expect(find.textContaining('tokens'), findsWidgets);
      expect(find.text('知道了'), findsOneWidget);

      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(find.text('上下文占用'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('miuix：输入框与角色/发送同排，工具行另起一行', (tester) async {
      await useNarrowScreen(tester);
      await tester.pumpWidget(miuixPage());
      await tester.pumpAndSettle();

      final field = find.byType(MiuixTextField);
      expect(field, findsOneWidget);
      expect(tester.getSize(field).width, greaterThan(150));

      final fieldBottom = tester.getBottomLeft(field).dy;
      for (final icon in [
        Icons.memory_outlined,
        Icons.insert_drive_file_outlined,
        Icons.mic_none,
        Icons.image_outlined,
        Icons.photo_camera_outlined,
      ]) {
        expect(
          tester.getCenter(find.byIcon(icon)).dy,
          greaterThan(fieldBottom),
          reason: '$icon 应该在输入框下面的工具行',
        );
      }
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('miuix：点占用环弹详情（showMiuixDialog）', (tester) async {
      await useNarrowScreen(tester);
      await tester.pumpWidget(miuixPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ContextRing));
      await tester.pumpAndSettle();

      expect(find.text('上下文占用'), findsOneWidget);
      expect(find.text('请求模型 zen-free'), findsOneWidget);
      expect(find.text('知道了'), findsOneWidget);

      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(find.text('上下文占用'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('切到「仅发文字」：开关收进模型清单，切换有 toast', (tester) async {
      await useNarrowScreen(tester);
      await tester.pumpWidget(materialPage());
      await tester.pumpAndSettle();

      // 打开模型清单（工具行的模型入口）
      await tester.tap(find.byIcon(Icons.memory_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.text('发送图片'));
      await tester.pumpAndSettle();
      expect(find.text('图片只在本地展示，不发给模型'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    });
  });

  // 这一组要真发 HTTP，所以放在**没有** widget binding 的独立文件里跑
  // （见 chat_sim_e2e_test.dart 的说明）；这里只验请求体形状，不起服务。
  group('请求体形状', () {
    test('多模态那条序列化后仍是合法 JSON，且 image_url 带 data URL', () {
      final body = ChatSimulator.bodyOf(
        model: 'vision',
        messages: [
          ChatMsg(ChatRole.system, '看图说话'),
          ChatMsg(
            ChatRole.user,
            '这是什么',
            attachments: [kImageAttachment()],
          ),
        ],
      );
      final sent = jsonDecode(body) as Map<String, dynamic>;
      final msgs = sent['messages'] as List;
      // system 仍是字符串，user 是数组 —— 混合形状 OpenAI 兼容端点都收
      expect((msgs[0] as Map)['content'], isA<String>());
      final url = (((msgs[1] as Map)['content'] as List)[0]
          as Map)['image_url'];
      expect(url, isNull, reason: '第一段是 text');
      final img = ((msgs[1] as Map)['content'] as List)[1] as Map;
      expect(
        (img['image_url'] as Map)['url'],
        startsWith('data:image/jpeg;base64,'),
      );
    });
  });
}
