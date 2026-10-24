import 'package:flutter/material.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSettings.normalizeLocaleCode', () {
    test('系统规范化形式（zh-Hans-CN）→ 应用内规范码', () {
      expect(AppSettings.normalizeLocaleCode('zh-Hans-CN'), 'zh-CN');
      expect(AppSettings.normalizeLocaleCode('zh-Hant-TW'), 'zh-TW');
    });

    test('region 形式与下划线变体 → 应用内规范码', () {
      expect(AppSettings.normalizeLocaleCode('zh-CN'), 'zh-CN');
      expect(AppSettings.normalizeLocaleCode('zh-TW'), 'zh-TW');
      expect(AppSettings.normalizeLocaleCode('zh_CN'), 'zh-CN');
    });

    test('只有 script / 只有语言 → 按 likely 方向收敛', () {
      expect(AppSettings.normalizeLocaleCode('zh'), 'zh-CN');
      expect(AppSettings.normalizeLocaleCode('zh-Hans'), 'zh-CN');
      expect(AppSettings.normalizeLocaleCode('zh-Hant'), 'zh-TW');
      // 港澳是繁体
      expect(AppSettings.normalizeLocaleCode('zh-HK'), 'zh-TW');
      expect(AppSettings.normalizeLocaleCode('zh-MO'), 'zh-TW');
    });

    test('英文各变体收敛到 en-US', () {
      expect(AppSettings.normalizeLocaleCode('en-US'), 'en-US');
      expect(AppSettings.normalizeLocaleCode('en'), 'en-US');
      expect(AppSettings.normalizeLocaleCode('en-GB'), 'en-US');
    });

    test('大小写不敏感', () {
      expect(AppSettings.normalizeLocaleCode('ZH-hans-CN'), 'zh-CN');
      expect(AppSettings.normalizeLocaleCode('zh-hant-tw'), 'zh-TW');
    });

    test('不支持的语言 / 空值 → null（跟随系统）', () {
      expect(AppSettings.normalizeLocaleCode('fr'), isNull);
      expect(AppSettings.normalizeLocaleCode('fr-FR'), isNull);
      expect(AppSettings.normalizeLocaleCode(''), isNull);
      expect(AppSettings.normalizeLocaleCode('  '), isNull);
      expect(AppSettings.normalizeLocaleCode(null), isNull);
    });
  });

  group('AppSettings.syncFromSystemLocaleCode', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('系统值归一化后镜像（冷启动同步）', () async {
      final settings = AppSettings();
      await settings.load();
      settings.syncFromSystemLocaleCode('zh-Hans-CN');
      expect(settings.localeCode, 'zh-CN');
      expect(settings.locale, const Locale('zh', 'CN'));
    });

    test('用户在应用内手动选过 → 不被系统值覆盖', () async {
      final settings = AppSettings();
      await settings.load();
      await settings.setLocale('en-US');
      settings.syncFromSystemLocaleCode('zh-Hant-TW');
      expect(settings.localeCode, 'en-US');
    });

    test('系统里清掉应用语言 → 回到跟随系统', () async {
      final settings = AppSettings();
      await settings.load();
      settings.syncFromSystemLocaleCode('zh-Hans-CN');
      expect(settings.localeCode, 'zh-CN');
      settings.syncFromSystemLocaleCode(null);
      expect(settings.localeCode, isNull);
      expect(settings.locale, isNull);
    });
  });
}
