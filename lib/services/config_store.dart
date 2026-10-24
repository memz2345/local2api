import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/proxy_config.dart';

/// 代理配置的持久化存储（shared_preferences 单键 JSON）。
class ConfigStore extends ChangeNotifier {
  static const String _prefKey = 'local2api.config.v1';

  ProxyConfig _config = ProxyConfig();
  bool _loaded = false;

  ProxyConfig get config => _config;
  bool get loaded => _loaded;

  Timer? _saveTimer;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        _config = ProxyConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // 损坏的配置回退默认值
        _config = ProxyConfig();
      }
    }
    _loaded = true;
    notifyListeners();
  }

  /// 更新配置（调用方改传入对象后调用，或直接传入新对象）。
  /// 会做一次防御性深拷贝再保存，避免 UI 编辑过程中写盘。
  void update(ProxyConfig config) {
    _config = config;
    notifyListeners();
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_save());
    });
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, jsonEncode(_config.toJson()));
    } catch (e) {
      debugPrint('ConfigStore save failed: $e');
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
