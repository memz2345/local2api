// 实验室可见性开关（LabGate）：默认隐藏、手动打开、重启后保持。
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/lab/lab_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // 重置单例状态（测试间隔离）。
    LabGate.instance
      ..setVisibleForTest(false)
      ..resetLoadedForTest();
  });

  test('默认不可见；打开后写入 prefs', () async {
    final gate = LabGate.instance;
    await gate.load();
    expect(gate.visible, isFalse);

    await gate.setVisible(true);
    expect(gate.visible, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('lab.visible'), isTrue);
  });

  test('重启后（重新 load）保持用户的选择', () async {
    SharedPreferences.setMockInitialValues({'lab.visible': true});
    final gate = LabGate.instance;
    await gate.load();
    expect(gate.visible, isTrue);
  });

  test('关掉开关后入口消失（写回 false）', () async {
    SharedPreferences.setMockInitialValues({'lab.visible': true});
    final gate = LabGate.instance;
    await gate.load();
    expect(gate.visible, isTrue);

    await gate.setVisible(false);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('lab.visible'), isFalse);
  });
}
