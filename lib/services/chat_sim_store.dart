import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_simulation.dart';

/// 「对话模拟」的本地存档：按模型组（scope）存一段对话，默认一直留着。
///
/// 为什么要存：模拟器的意义是「把历史一起发给下游」。历史只活在内存里的话，
/// 退出页面再进来就只剩一条系统提示词，请求跟第一次一模一样 —— 等于白聊。
///
/// 与 `UsageStats` 一样：只存本机、不上报；上限 [maxMessages] 条，
/// 超了从头截掉（保留最近的）。
class ChatSimStore extends ChangeNotifier {
  static const String _key = 'local2api.chatsim.v1';

  /// 每个 scope 最多存多少条（含系统提示词）。防止一个聊了很久的对话
  /// 把 SharedPreferences 撑肥。
  static const int maxMessages = 200;

  /// 单个 scope 的文本总量上限（字符），比条数更贴近真实占用。
  static const int maxChars = 64 * 1024;

  final Map<String, List<ChatMsg>> _byScope = {};

  /// 每个 scope 记住上次选的「模拟模型」（'' = 全部 / 组对外名）。
  final Map<String, String> _selectedModelByScope = {};

  /// 每个 scope 记住最后应用的角色卡 id（仅用于界面上显示「当前角色」，
  /// 场景本身存在 messages 里，不依赖它）。
  final Map<String, String> _characterByScope = {};

  bool _loaded = false;
  Timer? _saveTimer;

  bool get loaded => _loaded;

  /// 读过一次就缓存住；返回空列表表示这个组还没聊过。
  List<ChatMsg> messagesOf(String scope) =>
      List.unmodifiable(_byScope[scope] ?? const <ChatMsg>[]);

  /// 这个组上次选的模拟模型；null = 没选过（用组对外名）。
  String? selectedModelOf(String scope) {
    final v = _selectedModelByScope[scope];
    return (v == null || v.isEmpty) ? null : v;
  }

  void setSelectedModel(String scope, String? model) {
    if (scope.isEmpty) return;
    if (model == null || model.isEmpty) {
      _selectedModelByScope.remove(scope);
    } else {
      _selectedModelByScope[scope] = model;
    }
    _scheduleSave();
  }

  /// 这个 scope 最后应用的角色卡 id；null = 没应用过（默认场景）。
  String? characterOf(String scope) {
    final v = _characterByScope[scope];
    return (v == null || v.isEmpty) ? null : v;
  }

  void setCharacter(String scope, String? characterId) {
    if (scope.isEmpty) return;
    if (characterId == null || characterId.isEmpty) {
      _characterByScope.remove(scope);
    } else {
      _characterByScope[scope] = characterId;
    }
    _scheduleSave();
  }

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          for (final entry in decoded.entries) {
            final value = entry.value;
            if (value is! Map<String, dynamic>) continue;
            final list = value['messages'];
            if (list is! List) continue;
            _byScope[entry.key] = [
              for (final m in list)
                if (m is Map<String, dynamic>) ChatMsg.fromJson(m),
            ];
            final selectedModel = value['selectedModel'];
            if (selectedModel is String && selectedModel.isNotEmpty) {
              _selectedModelByScope[entry.key] = selectedModel;
            }
            final characterId = value['characterId'];
            if (characterId is String && characterId.isNotEmpty) {
              _characterByScope[entry.key] = characterId;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('ChatSimStore load failed: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  /// 存一段对话（防抖落盘）。
  void save(String scope, List<ChatMsg> messages) {
    if (scope.isEmpty) return;
    final trimmed = _trim(messages);
    _byScope[scope] = [
      for (final m in trimmed)
        ChatMsg(
          m.role,
          m.content,
          elapsedMs: m.elapsedMs,
          error: m.error,
          model: m.model,
          lane: m.lane,
          attachments: [for (final a in m.attachments) a.copy()],
        ),
    ];
    _scheduleSave();
  }

  /// 丢掉某个 scope 的存档（页面上的「清空对话」用）。
  void remove(String scope) {
    _byScope.remove(scope);
    _scheduleSave();
    notifyListeners();
  }

  void clear() {
    _byScope.clear();
    _scheduleSave();
    notifyListeners();
  }

  /// 超上限就砍掉**最老的**（保留最后 [maxMessages] 条，且总字数不超上限）。
  static List<ChatMsg> _trim(List<ChatMsg> messages) {
    var out = messages.length > maxMessages
        ? messages.sublist(messages.length - maxMessages)
        : messages;
    var chars = out.fold<int>(0, (a, m) => a + m.content.length);
    if (chars <= maxChars) return out;
    // 从头部丢（系统提示词那条留着：它是对话的锚）
    final kept = <ChatMsg>[];
    for (final m in out.reversed) {
      final cost = m.content.length;
      if (chars - cost < maxChars / 2) break;
      chars -= cost;
      kept.insert(0, m);
    }
    return kept.isEmpty ? out : kept;
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
      await prefs.setString(
        _key,
        jsonEncode({
          for (final e in _byScope.entries)
            e.key: {
              'messages': [
                // 附件缩略图按预算放行：从最新的对话往回数，超了预算的
                // 只存元信息（名字/大小还在，图没了）—— 防止几张截图把
                // SharedPreferences 撑肥。
                for (final (m, includeThumbs) in _withinThumbBudget(e.value))
                  m.toJson(includeAttachmentThumbs: includeThumbs),
              ],
              'selectedModel': ?_selectedModelByScope[e.key],
              'characterId': ?_characterByScope[e.key],
            },
        }),
      );
    } catch (e) {
      debugPrint('ChatSimStore save failed: $e');
    }
  }

  /// 附件缩略图的落盘预算：单个 scope 最多 4MB。越新的消息越优先保留。
  static List<(ChatMsg, bool)> _withinThumbBudget(List<ChatMsg> messages) {
    const budget = 4 * 1024 * 1024;
    var used = 0;
    final out = <(ChatMsg, bool)>[];
    for (final m in messages.reversed) {
      var cost = 0;
      for (final a in m.attachments) {
        if (a.thumbnail != null) cost += a.thumbnail!.length;
      }
      // 4/3 ≈ base64 膨胀；四舍五入的误差无所谓，预算只是防撑爆。
      final include = used + cost <= budget;
      if (include) used += cost;
      out.add((m, include));
    }
    return out.reversed.toList();
  }

  /// 立即落盘（退出前调用，别指望防抖定时器）。
  Future<void> flush() async {
    _saveTimer?.cancel();
    await _save();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}

final ChatSimStore chatSimStore = ChatSimStore();
