// 网页 `<select>` 选择器（内置浏览器）的回归测试。
//
// 覆盖两件事：
//   1. shim 抛来的 JSON 能正确解析（Android 是字符串，iOS 是 Map）；
//   2. 两套皮的底部选择器都能点选并回传 `<option>.index`。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/browser_web_shim.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';
import 'package:local2api/widgets/browser_web_select_sheet.dart';

BrowserSelectRequest _sampleRequest() => BrowserSelectRequest(
  id: '7-1',
  label: 'Chat Completion Source',
  selectedIndex: 1,
  options: const [
    BrowserSelectOption(index: 0, label: 'anthropic'),
    BrowserSelectOption(index: 1, label: 'azure'),
    BrowserSelectOption(index: 2, label: 'deepseek'),
    BrowserSelectOption(index: 3, label: 'disabled-one', disabled: true),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shim 消息解析', () {
    test('Android 的字符串消息能吃', () {
      final raw = jsonEncode({
        'type': 'select',
        'id': '3-1',
        'label': 'Provider',
        'index': 2,
        'options': [
          {'index': 0, 'label': 'a', 'group': '', 'disabled': false},
          {'index': 1, 'label': 'b', 'group': 'G', 'disabled': true},
        ],
      });
      final request = BrowserSelectRequest.tryParse(
        decodeBrowserShimMessage(raw),
      );
      expect(request, isNotNull);
      expect(request!.id, '3-1');
      expect(request.label, 'Provider');
      expect(request.selectedIndex, 2);
      expect(request.options.length, 2);
      expect(request.options[1].group, 'G');
      expect(request.options[1].disabled, isTrue);
    });

    test('iOS 的 Map 消息也吃', () {
      final request = BrowserSelectRequest.tryParse({
        'type': 'select',
        'id': 'k1',
        'index': 0,
        'options': [
          {'index': 0, 'label': 'only'},
        ],
      });
      expect(request?.options.single.label, 'only');
    });

    test('别的消息 / 坏数据直接丢弃', () {
      expect(decodeBrowserShimMessage('CUSTOM_SCHEME:mailto:a@b'), isNull);
      expect(BrowserSelectRequest.tryParse({'type': 'x'}), isNull);
      expect(
        BrowserSelectRequest.tryParse({'type': 'select', 'id': 'x'}),
        isNull,
      );
      expect(
        BrowserSelectRequest.tryParse({
          'type': 'select',
          'id': 'x',
          'options': [
            {'label': 'no index'},
          ],
        }),
        isNull,
      );
    });
  });

  Widget host({required bool useMiuix, required ValueChanged<int?> onResult}) {
    final page = Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async {
              onResult(
                await showBrowserWebSelectSheet(
                  context,
                  request: _sampleRequest(),
                  title: '选择',
                  useMiuix: useMiuix,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    if (!useMiuix) {
      return MaterialApp(theme: AppTheme.light(), home: page);
    }
    return MiuixThemeController(
      colorSchemeMode: miuixColorSchemeModeOf(themeMode: ThemeMode.light),
      keyColor: const Color(0xFF386A20),
      child: Builder(
        builder: (context) {
          final miuix = MiuixTheme.of(context);
          return MaterialApp(
            theme: AppTheme.light().copyWith(
              colorScheme: materialSchemeFromMiuix(
                miuix.colors,
                miuix.brightness,
              ),
            ),
            home: page,
          );
        },
      ),
    );
  }

  for (final useMiuix in [false, true]) {
    testWidgets('选择器（${useMiuix ? 'miuix' : 'Material 3'}）点选项回传下标', (
      tester,
    ) async {
      int? picked;
      await tester.pumpWidget(
        host(useMiuix: useMiuix, onResult: (v) => picked = v),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // 面板里四个选项都在
      expect(find.text('deepseek'), findsOneWidget);
      expect(find.text('anthropic'), findsOneWidget);

      await tester.tap(find.text('deepseek'));
      await tester.pumpAndSettle();
      expect(picked, 2);
    });
  }

  testWidgets('Material 3 面板常驻细滚动条', (tester) async {
    await tester.pumpWidget(host(useMiuix: false, onResult: (_) {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(Scrollbar), findsOneWidget);
  });
}
