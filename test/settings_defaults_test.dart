import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/src/enums.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 出厂默认：进入应用就是 miuix 风格 + 渐变模糊顶栏。
///
/// 「默认」只作用于**没存过这一项**的设备（全新安装 / 清过数据）；
/// 用户在设置里选过的值一律照原样读回来，包括他特意选的 material /
/// 关闭渐变档 —— 所以 fromId 的兜底必须是 miuix，而认 key 必须显式。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsService 出厂默认', () {
    test('没存过偏好：miuix + 渐变模糊顶栏开着', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.load();
      expect(settings.uiStyle, UiStyle.miuix);
      expect(settings.progressiveTopBar, isTrue);
    });

    test('字段初值与 load 的缺省一致（没 load 也按出厂默认）', () {
      final settings = SettingsService();
      expect(settings.uiStyle, UiStyle.miuix);
      expect(settings.progressiveTopBar, isTrue);
    });

    test('用户选过 material / 关掉渐变：照旧读回，不被默认覆盖', () async {
      SharedPreferences.setMockInitialValues({
        'local2api.uiStyle': 'material',
        'local2api.progressiveTopBar': false,
      });
      final settings = SettingsService();
      await settings.load();
      expect(settings.uiStyle, UiStyle.materialExpressive);
      expect(settings.progressiveTopBar, isFalse);
    });

    test('改完落盘，重启读回', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.load();
      await settings.setUiStyle(UiStyle.materialExpressive);
      await settings.setProgressiveTopBar(false);

      final restarted = SettingsService();
      await restarted.load();
      expect(restarted.uiStyle, UiStyle.materialExpressive);
      expect(restarted.progressiveTopBar, isFalse);
    });
  });
}
