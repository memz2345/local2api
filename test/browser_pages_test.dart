// 内置浏览器的两个纯逻辑/纯渲染回归：
//   · normalizeBrowserInput：域名补 https、空格当搜索词、带 scheme 原样；
//   · 四套错误页（BSOD / 挂掉的安卓 / Apple / kernel panic）能正常渲染，
//     l10n 键没漏（这几页是 Material / miuix 共用的）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/browser_controller.dart';
import 'package:local2api/widgets/browser_error_pages.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('normalizeBrowserInput', () {
    test('带 scheme 原样保留', () {
      expect(
        normalizeBrowserInput('http://127.0.0.1:8000'),
        'http://127.0.0.1:8000',
      );
      expect(normalizeBrowserInput('about:blank'), 'about:blank');
    });

    test('像域名就补 https', () {
      expect(normalizeBrowserInput('example.com'), 'https://example.com');
      expect(normalizeBrowserInput('127.0.0.1:9292'), 'https://127.0.0.1:9292');
    });

    test('带空格当搜索词', () {
      final url = normalizeBrowserInput('silly tavern');
      expect(url, startsWith('https://www.bing.com/search?q='));
      expect(url, contains('silly+tavern'));
    });

    test('空串返回空', () {
      expect(normalizeBrowserInput('   '), '');
    });
  });

  group('错误页渲染', () {
    Future<void> pump(WidgetTester tester, BrowserErrorStyle style) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BrowserErrorPage(
              style: style,
              detail: 'boom',
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Windows BSOD', (tester) async {
      await pump(tester, BrowserErrorStyle.bsod);
      expect(find.text(':('), findsOneWidget);
      expect(find.text('返回'), findsOneWidget);
    });

    testWidgets('Android 死机器人', (tester) async {
      await pump(tester, BrowserErrorStyle.android);
      expect(find.text('系统 WebView 挂了'), findsOneWidget);
      expect(find.text('No command.'), findsOneWidget);
    });

    testWidgets('Apple', (tester) async {
      await pump(tester, BrowserErrorStyle.apple);
      expect(find.text('内置浏览器无法启动'), findsOneWidget);
    });

    testWidgets('其它平台 kernel panic', (tester) async {
      await pump(tester, BrowserErrorStyle.generic);
      expect(find.text('Kernel panic - not syncing'), findsOneWidget);
    });
  });
}
