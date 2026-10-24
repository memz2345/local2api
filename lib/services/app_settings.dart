import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用语言设置（主题/外观归 SettingsService，本类只管语言）。
class AppSettings extends ChangeNotifier {
  static const String _kLocaleCode = 'local2api.localeCode';

  /// null = 跟随系统；否则是**应用内规范码**：'zh-CN' / 'zh-TW' / 'en-US'。
  ///
  /// ⚠️ 系统侧的 tag 不一定是这个形式 —— Android 13+ 会按 likely-subtags 给
  /// 中文补 script（zh-CN ⇄ zh-Hans-CN），有的 OEM 还会用下划线（zh_CN）。
  /// 系统的值一律先过 [normalizeLocaleCode] 再进来（见
  /// [syncFromSystemLocaleCode]），别把原始 tag 存进来，设置页的下拉匹配
  /// （'zh-CN' => 简体中文）会认不出。
  String? _localeCode;

  /// [_localeCode] 是否来自用户在应用内的手动选择（区别于从系统镜像来的
  /// 暂存值）。手动选择优先于系统镜像；选「跟随系统」等于交还控制权，
  /// 之后的系统改动重新可镜像。镜像值不落盘，重启后自然回到系统视角。
  bool _localeSetByUser = false;

  String? get localeCode => _localeCode;

  Locale? get locale =>
      _localeCode == null ? null : _localeFromCode(_localeCode!);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _localeCode = prefs.getString(_kLocaleCode);
    // 落过盘的一定是用户手动选的（镜像值从不落盘）。
    _localeSetByUser = _localeCode != null;
    notifyListeners();
  }

  /// 设置应用语言并持久化；tag 为 null 表示跟随系统（交还系统控制权）。
  Future<void> setLocale(String? tag) async {
    _localeCode = tag;
    _localeSetByUser = tag != null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (tag == null) {
      await prefs.remove(_kLocaleCode);
    } else {
      await prefs.setString(_kLocaleCode, tag);
    }
  }

  /// 从系统镜像出的应用语言列表（Android 13+ 系统设置里选的语言）。
  ///
  /// 传入的 tag 可能是任意合法形式（zh-Hans-CN / zh-CN / zh_CN / en-US…），
  /// 统一归一化成应用内规范码再存；null / 不支持的语言 → 清成 null
  /// （跟随系统）。用户在应用内手动选过就不覆盖 —— 应用内选择是更明确的
  /// 意图，且选择时会写回系统，两边本来就该一致。
  void syncFromSystemLocaleCode(String? code) {
    if (_localeSetByUser) return; // 用户手动选择过，不覆盖
    final normalized = normalizeLocaleCode(code);
    if (normalized == _localeCode) return;
    _localeCode = normalized;
    notifyListeners();
  }

  /// 把任意 BCP-47 / OEM 变体的语言 tag 归一化成应用内规范码。
  ///
  /// - `zh-Hans-CN` / `zh-CN` / `zh_CN` / `zh-Hans` → `zh-CN`（简体）
  /// - `zh-Hant-TW` / `zh-TW` / `zh-Hant` / `zh-HK` / `zh-MO` → `zh-TW`（繁体）
  /// - `en-US` / `en-GB` / `en` → `en-US`（应用内只有一份英文资源）
  /// - 应用不支持的语言 → null（保持「跟随系统」，交给 locale 解析回退）
  ///
  /// ⚠️ 别用 `split('-')[1]` 这类裸拆：`zh-Hans-CN` 的第二段是 script
  /// 不是 region，拆出来会得到 `Locale('zh', 'Hans')` 这种垃圾。
  static String? normalizeLocaleCode(String? raw) {
    if (raw == null) return null;
    final parts = raw.trim().replaceAll('_', '-').split('-')
      ..removeWhere((p) => p.isEmpty);
    if (parts.isEmpty) return null;
    final language = parts.first.toLowerCase();
    String? script;
    String? region;
    for (final part in parts.skip(1)) {
      if (part.length == 4) {
        script =
            part.substring(0, 1).toUpperCase() +
            part.substring(1).toLowerCase();
      } else if (part.length == 2 || part.length == 3) {
        region = part.toUpperCase();
      }
      // 数字变体（如 # Latn 之外的扩展）与应用无关，跳过
    }
    switch (language) {
      case 'zh':
        final isTraditional =
            script == 'Hant' ||
            // 没写 script 时按 region 推：港澳是繁体，其余按简体
            (script == null &&
                (region == 'TW' || region == 'HK' || region == 'MO'));
        return isTraditional ? 'zh-TW' : 'zh-CN';
      case 'en':
        return 'en-US';
      default:
        return null;
    }
  }

  /// 应用内规范码（'zh-CN' 这种两段式）→ Locale。只做兜底解析，
  /// 正常路径都已被 [normalizeLocaleCode] 收敛成两段以内。
  static Locale _localeFromCode(String code) {
    final parts = code.split('-');
    if (parts.length == 1) return Locale(parts[0]);
    return Locale(parts[0], parts.last);
  }
}
