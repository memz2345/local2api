// Custom Tabs 浏览器选择面板的渲染 / 回传测试（两套皮）。

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/custom_tabs_service.dart';
import 'package:local2api/ui/app_theme.dart';
import 'package:local2api/ui/miuix/miuix_material_bridge.dart';
import 'package:local2api/widgets/custom_tabs_picker.dart';

const _browsers = [
  CustomTabsBrowser(
    packageName: 'com.android.chrome',
    label: 'Chrome',
    isDefault: true,
  ),
  CustomTabsBrowser(packageName: 'com.microsoft.emmx', label: 'Edge'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host({
    required bool useMiuix,
    required ValueChanged<String?> onResult,
  }) {
    final page = Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async {
              onResult(
                await showCustomTabsBrowserPicker(
                  context,
                  browsers: _browsers,
                  selectedPackage: 'com.android.chrome',
                  useMiuix: useMiuix,
                  title: '用哪个浏览器打开',
                ),
              );
            },
            child: const Text('pick'),
          ),
        ),
      ),
    );
    if (!useMiuix) {
      return MaterialApp(theme: AppTheme.light(), home: page);
    }
    return MiuixThemeController(
      colorSchemeMode: miuixColorSchemeModeOf(themeMode: ThemeMode.light),
      keyColor: const Color(0xFF3482FF),
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
    testWidgets('浏览器选择面板（${useMiuix ? 'miuix' : 'Material 3'}）回传包名', (
      tester,
    ) async {
      String? picked;
      await tester.pumpWidget(
        host(useMiuix: useMiuix, onResult: (v) => picked = v),
      );
      await tester.tap(find.text('pick'));
      await tester.pumpAndSettle();

      expect(find.text('Chrome'), findsOneWidget);
      expect(find.text('Edge'), findsOneWidget);

      await tester.tap(find.text('Edge'));
      await tester.pumpAndSettle();
      expect(picked, 'com.microsoft.emmx');
    });
  }
}
