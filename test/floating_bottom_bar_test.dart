import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/widgets/floating_bottom_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SettingsService 底栏样式', () {
    test('旧 bool 键迁移：false → plain', () async {
      SharedPreferences.setMockInitialValues({
        'local2api.navBarGlass': false,
      });
      final settings = SettingsService();
      await settings.load();
      expect(settings.navBarStyle, NavBarStyle.plain);
    });

    test('旧 bool 键迁移：缺省 / true → glass', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.load();
      expect(settings.navBarStyle, NavBarStyle.glass);
    });

    test('新键优先于旧键，写回新键', () async {
      SharedPreferences.setMockInitialValues({
        'local2api.navBarGlass': true,
        'local2api.navBarStyle': 'floating',
      });
      final settings = SettingsService();
      await settings.load();
      expect(settings.navBarStyle, NavBarStyle.floating);

      await settings.setNavBarStyle(NavBarStyle.plain);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('local2api.navBarStyle'), 'plain');
    });
  });

  group('FloatingBottomBar', () {
    final captured = <int>[];

    Future<void> pumpBar(WidgetTester tester, {int initial = 0}) async {
      captured.clear();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: SafeArea(
              child: FloatingBottomBar(
                items: [
                  for (final label in const ['仪表盘', '发现', '设置'])
                    FloatingBottomBarItem(
                      label: label,
                      iconBuilder: (selected) =>
                          const Icon(Icons.circle_outlined),
                    ),
                ],
                selectedIndex: initial,
                onSelected: captured.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('点按切换：回调带目标索引', (tester) async {
      await pumpBar(tester);
      await tester.tap(find.text('发现'));
      await tester.pumpAndSettle();
      expect(captured, [1]);
    });

    testWidgets('点已选中的 tab 不重复回调', (tester) async {
      await pumpBar(tester);
      await tester.tap(find.text('仪表盘'));
      await tester.pumpAndSettle();
      expect(captured, isEmpty);
    });

    testWidgets('横向拖动吸附到最近的 tab', (tester) async {
      await pumpBar(tester);
      // 整栏宽约 400：从最左往右拖过一格半，应吸附到第 1 格。
      await tester.drag(find.text('仪表盘'), const Offset(160, 0));
      await tester.pumpAndSettle();
      expect(captured, [1]);
    });
  });
}
