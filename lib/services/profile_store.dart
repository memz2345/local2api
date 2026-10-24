import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/builtin_profiles.dart';
import '../models/config_profile.dart';

/// 配置档案的注册表与持久化。
///
/// 刻意不塞进 ConfigStore：ProxyConfig 是每请求热路径上的配置，
/// 而档案原始文档可能几十 KB，混进同一个防抖单键 blob 会放大写入、
/// 也让两边的迁移互相牵连。
///
/// 分工：本类只管「有哪些档案、各自什么状态、原文是什么」；
/// 档案怎么装进 ProxyConfig、谁归属谁，是 ProfileService 的事。
class ProfileStore extends ChangeNotifier {
  static const String _indexKey = 'local2api.profiles.v1';
  static const String _docKeyPrefix = 'local2api.profile.doc.';

  /// 内置档案由代码生成、不落盘，这样升级版本时目录能跟着自更新。
  final List<ConfigProfile> _builtins = builtinProfiles();

  /// 导入顺序，决定发现页上的排列。
  final List<String> _importedOrder = [];
  final Map<String, ConfigProfile> _imported = {};
  final Map<String, String> _rawDocs = {};
  final Map<String, ProfileState> _states = {};

  /// 来源由导入渠道决定、不写在文档里，所以得单独存一份，
  /// 否则重新加载时认不出这份档案是订阅来的还是粘贴来的。
  final Map<String, ProfileSource> _sources = {};

  /// 用户给这个组起的名字与说明。
  ///
  /// 单独存而不是写回文档：订阅类档案每次更新都会整份换掉文档，
  /// 写进去的名字会被下一次拉取覆盖掉。
  final Map<String, _GroupLabel> _labels = {};

  String? _activeId;
  bool _hadPersistedIndex = false;
  bool _loaded = false;

  Timer? _saveTimer;

  bool get loaded => _loaded;

  /// 索引键存不存在。不存在 = 这是升级后的首次启动，需要跑一次迁移。
  bool get hadPersistedIndex => _hadPersistedIndex;

  /// 全部档案：内置在前，导入的按导入顺序跟在后面。
  List<ConfigProfile> get profiles => [
    ..._builtins,
    for (final id in _importedOrder)
      if (_imported[id] != null) _applyLabel(_imported[id]!),
  ];

  String? get activeId => _activeId;

  ConfigProfile? profileOf(String id) {
    for (final p in profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  bool isBuiltin(String id) => _builtins.any((p) => p.id == id);

  /// 取状态；没记录过就给一份默认的。内置档案永远要有状态，
  /// 否则迁移前 UI 会拿不到 active 标记。
  ProfileState stateOf(String id) =>
      _states.putIfAbsent(id, () => ProfileState(profileId: id));

  /// 导入档案的原始文本；内置档案返回 null。
  String? rawOf(String id) => _rawDocs[id];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_indexKey);
    _hadPersistedIndex = raw != null && raw.isNotEmpty;

    // 直接用 raw 自己的空判进分支：把结果存进字段再判，Dart 不会提升 raw 的类型。
    if (raw != null && raw.isNotEmpty) {
      try {
        final index = jsonDecode(raw) as Map<String, dynamic>;
        _activeId = index['activeId'] as String?;
        for (final s in (index['states'] as List? ?? const [])) {
          if (s is! Map<String, dynamic>) continue;
          final state = ProfileState.fromJson(s);
          if (state.profileId.isEmpty) continue;
          _states[state.profileId] = state;
        }
        // 来源要先于文档就位：解析文档时要用它填 ConfigProfile.source。
        final sources = index['sources'];
        if (sources is Map) {
          for (final entry in sources.entries) {
            if (entry.value is Map<String, dynamic>) {
              _sources['${entry.key}'] = ProfileSource.fromJson(entry.value);
            }
          }
        }
        for (final id in (index['order'] as List? ?? const [])) {
          if (id is! String) continue;
          final doc = prefs.getString('$_docKeyPrefix$id');
          if (doc == null || doc.isEmpty) continue;
          final profile = _tryParse(doc, id);
          if (profile == null) continue;
          _imported[id] = profile;
          _rawDocs[id] = doc;
          _importedOrder.add(id);
        }
        final labels = index['labels'];
        if (labels is Map) {
          for (final entry in labels.entries) {
            if (entry.value is! Map<String, dynamic>) continue;
            final m = entry.value as Map<String, dynamic>;
            _labels['${entry.key}'] = _GroupLabel(
              name: (m['name'] as String?) ?? '',
              description: (m['description'] as String?) ?? '',
            );
          }
        }
      } catch (e) {
        debugPrint('ProfileStore load failed: $e');
      }
    }

    _dropOrphanDocs(prefs);
    _loaded = true;
    notifyListeners();
  }

  /// 索引里没有、但文档键还留着的，清掉。
  void _dropOrphanDocs(SharedPreferences prefs) {
    final known = _importedOrder.toSet();
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_docKeyPrefix)) continue;
      if (known.contains(key.substring(_docKeyPrefix.length))) continue;
      unawaited(prefs.remove(key));
    }
  }

  /// 重新加载时解析已存文档。落盘前必然解析成功过，所以这里再失败
  /// 只可能是 prefs 被写坏了 —— 丢掉这条、记日志，不去 invent 恢复路径。
  ConfigProfile? _tryParse(String raw, String id) {
    try {
      return parseConfigProfile(
        raw,
        source: _sources[id] ?? const ProfileSource(ProfileSourceKind.inline),
      );
    } catch (e) {
      debugPrint('ProfileStore: 档案 $id 已损坏，丢弃（$e）');
      return null;
    }
  }

  /// 给一个组改名 / 写说明。传空串表示「不填这一项」，不是清空。
  void setLabel(String id, {String? name, String? description}) {
    if (name == null && description == null) return;
    final current = _labels[id];
    _labels[id] = _GroupLabel(
      name: name ?? current?.name ?? '',
      description: description ?? current?.description ?? '',
    );
    notifyListeners();
    _scheduleIndexSave();
  }

  ConfigProfile _applyLabel(ConfigProfile profile) {
    final label = _labels[profile.id];
    if (label == null) return profile;
    return profile.withLabel(name: label.name, description: label.description);
  }

  /// 导入一份新档案。id 撞车（含撞内置）直接拒，免得把内置那份盖掉。
  ConfigProfile importDocument(String raw, ProfileSource source) {
    final profile = parseConfigProfile(raw, source: source);
    if (profileOf(profile.id) != null) {
      throw ProfileFormatException(ProfileFormatError.duplicateId, profile.id);
    }
    _imported[profile.id] = profile;
    _rawDocs[profile.id] = raw;
    _sources[profile.id] = source;
    _importedOrder.add(profile.id);
    stateOf(profile.id);
    notifyListeners();
    unawaited(_persistDoc(profile.id, raw));
    _scheduleIndexSave();
    return profile;
  }

  /// 远程订阅拉到了新内容：换掉文档，但状态（激活/自定义标记）保持不动。
  /// 返回解析后的新档案；解析失败抛 [ProfileFormatException]，旧文档原地不动。
  ConfigProfile replaceDocument(String id, String raw) {
    final source =
        _sources[id] ?? const ProfileSource(ProfileSourceKind.inline);
    final profile = parseConfigProfile(raw, source: source);
    if (profile.id != id) {
      // 订阅方把 id 改了等于换了一份档案，不能就地顶替（会甩下已装的上游）。
      throw ProfileFormatException(
        ProfileFormatError.duplicateId,
        '$id -> ${profile.id}',
      );
    }
    _imported[id] = profile;
    _rawDocs[id] = raw;
    notifyListeners();
    unawaited(_persistDoc(id, raw));
    return profile;
  }

  /// 删档案。内置的不给删。
  void remove(String id) {
    if (isBuiltin(id)) return;
    _imported.remove(id);
    _rawDocs.remove(id);
    _sources.remove(id);
    _labels.remove(id);
    _importedOrder.remove(id);
    _states.remove(id);
    if (_activeId == id) _activeId = null;
    notifyListeners();
    unawaited(_removeDoc(id));
    _scheduleIndexSave();
  }

  /// 单选激活：传 null 表示全都不激活。
  void setActive(String? id) {
    if (_activeId == id) return;
    _activeId = id;
    // 只为确保这个 id 有状态条目，active 的值统一由下面的循环赋。
    if (id != null) stateOf(id);
    for (final entry in _states.entries) {
      entry.value.active = entry.key == id;
    }
    notifyListeners();
    _scheduleIndexSave();
  }

  /// 改状态并落盘。
  void mutateState(String id, void Function(ProfileState state) mutate) {
    mutate(stateOf(id));
    notifyListeners();
    _scheduleIndexSave();
  }

  void _scheduleIndexSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_saveIndex());
    });
  }

  Future<void> _saveIndex() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _indexKey,
        jsonEncode({
          'activeId': _activeId,
          'order': _importedOrder,
          'states': [for (final s in _states.values) s.toJson()],
          'sources': {
            for (final e in _sources.entries) e.key: e.value.toJson(),
          },
          'labels': {
            for (final e in _labels.entries)
              e.key: {'name': e.value.name, 'description': e.value.description},
          },
        }),
      );
    } catch (e) {
      debugPrint('ProfileStore save failed: $e');
    }
  }

  Future<void> _persistDoc(String id, String raw) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_docKeyPrefix$id', raw);
    } catch (e) {
      debugPrint('ProfileStore doc save failed: $e');
    }
  }

  Future<void> _removeDoc(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_docKeyPrefix$id');
    } catch (e) {
      debugPrint('ProfileStore doc remove failed: $e');
    }
  }

  /// 立即落盘，退出前调用，别指望防抖定时器。
  Future<void> flush() async {
    _saveTimer?.cancel();
    await _saveIndex();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}

/// 用户给一个组起的名字与说明（存在索引里，不写回文档）。
final class _GroupLabel {
  const _GroupLabel({required this.name, required this.description});

  final String name;
  final String description;
}
