import 'package:shared_preferences/shared_preferences.dart';

import '../models/proxy_config.dart';

/// 对外模型页的列表排序方式。
enum ModelsSortMode {
  /// 默认：保持配置里的原始顺序（也就是保存顺序）。
  natural,

  /// 首字母正序：A→Z，非字母（中文 / 数字 / 符号）归 `#` 并排在最后。
  alphabet,
}

/// 排序偏好的持久化。跟语言设置一样，直接落 shared_preferences ——
/// 它是纯 UI 偏好，不该进 `ProxyConfig`（那会跟着档案导入导出一起漂）。
class ModelsSortStore {
  ModelsSortStore._();

  static const String _key = 'local2api.modelsSortMode';

  static Future<ModelsSortMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) == ModelsSortMode.alphabet.name
        ? ModelsSortMode.alphabet
        : ModelsSortMode.natural;
  }

  static Future<void> save(ModelsSortMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}

/// 一个模型名落在哪个首字母分组。非 ASCII 字母一律归 `#`。
String modelGroupKey(String name) {
  final t = name.trim();
  if (t.isEmpty) return '#';
  final c = t[0].toUpperCase();
  final code = c.codeUnitAt(0);
  if (code >= 65 && code <= 90) return c;
  return '#';
}

/// 一个首字母分组：字母 + 它包含的模型下标（指向原始列表）。
class ModelGroup {
  const ModelGroup(this.letter, this.indices);

  final String letter;
  final List<int> indices;
}

/// 首字母正序下每个模型的下标顺序（[ModelsSortMode.natural] 时就是 0..n-1）。
List<int> orderedModelIndices(List<ModelEntry> models, ModelsSortMode mode) {
  final indices = List<int>.generate(models.length, (i) => i);
  if (mode != ModelsSortMode.alphabet) return indices;
  indices.sort((a, b) {
    final ka = modelGroupKey(models[a].publicName);
    final kb = modelGroupKey(models[b].publicName);
    final ha = ka == '#' ? 1 : 0;
    final hb = kb == '#' ? 1 : 0;
    if (ha != hb) return ha - hb;
    if (ka != kb) return ka.compareTo(kb);
    return models[a].publicName.toLowerCase().compareTo(
      models[b].publicName.toLowerCase(),
    );
  });
  return indices;
}

/// 按首字母分组（组内已经是字母序，组间 A→Z、`#` 最后）。
List<ModelGroup> groupModelIndices(List<ModelEntry> models) {
  final groups = <String, List<int>>{};
  for (final i in orderedModelIndices(models, ModelsSortMode.alphabet)) {
    groups.putIfAbsent(modelGroupKey(models[i].publicName), () => []).add(i);
  }
  return [
    for (final e in groups.entries) ModelGroup(e.key, e.value),
  ];
}
