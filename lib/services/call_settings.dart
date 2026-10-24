import 'package:shared_preferences/shared_preferences.dart';

import '../models/proxy_config.dart';

/// 通话功能的模型判定与两个能力开关。
///
/// 「是不是 Omni 全模态」按模型名判定：`publicName` 或 `target` 里含
/// `omni`（大小写不敏感）就算 —— Qwen3-Omni 这类模型天生带这个字样，
/// 不用额外配置；改名 / 换真实目标名两条路都能命中。
bool isOmniModelName(String name) => name.toLowerCase().contains('omni');

/// 这个模型条目算不算 Omni（对外名或真实目标名含 omni）。
bool isOmniModel(ModelEntry entry) =>
    isOmniModelName(entry.publicName) || isOmniModelName(entry.target);

/// 组内挑一个可用的 Omni 模型（启用中、含 omni）；没有返回 null。
ModelEntry? omniModelOf(Upstream upstream) {
  for (final m in upstream.models) {
    if (m.enabled && isOmniModel(m)) return m;
  }
  return null;
}

/// 通话偏好（允许打断 / 允许调用摄像头）。
///
/// 与语言、排序偏好同一套路：纯本机 UI 偏好直接落 shared_preferences，
/// 不进 `ProxyConfig`（那会跟着档案导入导出一起漂）。
class CallPrefs {
  CallPrefs._();

  static const String _allowInterruptKey = 'local2api.call.allowInterrupt';
  static const String _allowCameraKey = 'local2api.call.allowCamera';

  /// 允许打断：模型说话时用户可以随时插话。默认开。
  static Future<bool> loadAllowInterrupt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_allowInterruptKey) ?? true;
  }

  static Future<void> saveAllowInterrupt(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_allowInterruptKey, value);
  }

  /// 允许调用摄像头：视频通话把画面发送给模型。默认开。
  static Future<bool> loadAllowCamera() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_allowCameraKey) ?? true;
  }

  static Future<void> saveAllowCamera(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_allowCameraKey, value);
  }
}
