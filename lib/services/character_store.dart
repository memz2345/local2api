import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'character_voice.dart';

/// 预制对话里的一问一答：角色卡装进「对话模拟」时，按顺序展开成
/// user / assistant 两条消息（连同人设提示词一起，把场景铺好）。
class ChatPresetPair {
  const ChatPresetPair({required this.user, required this.assistant});

  final String user;
  final String assistant;

  Map<String, dynamic> toJson() => {'user': user, 'assistant': assistant};

  factory ChatPresetPair.fromJson(Map<String, dynamic> j) => ChatPresetPair(
    user: (j['user'] as String?) ?? '',
    assistant: (j['assistant'] as String?) ?? '',
  );
}

/// 一张角色卡：给「对话模拟」换一个更贴合的场景。
///
/// 卡片本质上是三样东西——人设提示词（替换默认的 system）、几条预制问答
/// （让请求历史一开场就不空白）、一个名字（列表里认它）。内置卡由代码生成
/// 不落盘（升级时目录能跟着自更新），用户卡整包存 JSON。
class CharacterCard {
  const CharacterCard({
    required this.id,
    required this.name,
    required this.prompt,
    this.presets = const [],
    this.builtin = false,
    this.voiceSamplePath = '',
  });

  /// 稳定 id：内置卡固定前缀，用户卡用时间戳。
  final String id;

  /// 角色名（也是应用后页面上的显示名）。
  final String name;

  /// 人设提示词：应用后整条替换对话模拟的 system 消息。
  final String prompt;

  /// 预制问答（一问一答一组，应用后按顺序铺进对话）。
  final List<ChatPresetPair> presets;

  /// 是否内置（内置不可编辑/删除，用户卡才可以）。
  final bool builtin;

  /// 音色样本的本地路径（wav/mp3，已拷进应用目录）。空 = 没配，
  /// 朗读时用引擎默认音色。
  ///
  /// 用途按 TTS 服务商分两路：本地 Qwen3-TTS 直接当 speakerReference
  /// 克隆；云端（MiMo voiceclone）转成 data URI 塞进请求。
  final String voiceSamplePath;

  CharacterCard copyWith({
    String? id,
    String? name,
    String? prompt,
    List<ChatPresetPair>? presets,
    String? voiceSamplePath,
  }) => CharacterCard(
    id: id ?? this.id,
    name: name ?? this.name,
    prompt: prompt ?? this.prompt,
    presets: presets ?? this.presets,
    builtin: builtin,
    voiceSamplePath: voiceSamplePath ?? this.voiceSamplePath,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'prompt': prompt,
    'presets': [for (final p in presets) p.toJson()],
    // 没配不落盘，老数据读进来即空。
    if (voiceSamplePath.isNotEmpty) 'voiceSamplePath': voiceSamplePath,
  };

  factory CharacterCard.fromJson(Map<String, dynamic> j) => CharacterCard(
    id: (j['id'] as String?) ?? '',
    name: (j['name'] as String?) ?? '',
    prompt: (j['prompt'] as String?) ?? '',
    voiceSamplePath: (j['voiceSamplePath'] as String?) ?? '',
    presets: [
      if (j['presets'] is List)
        for (final p in (j['presets'] as List))
          if (p is Map<String, dynamic>) ChatPresetPair.fromJson(p),
    ],
  );
}

CharacterCard _builtin(String id, String name, String prompt,
    List<ChatPresetPair> presets) => CharacterCard(
  id: 'builtin.$id',
  name: name,
  prompt: prompt,
  presets: presets,
  builtin: true,
);

/// 内置角色卡。人设与预制对话都写在这儿（与 ProfileStore 的内置档案同一
/// 思路：代码生成、不落盘，升级版本时文案可以跟着改）。
List<CharacterCard> builtinCharacters() => [
  _builtin('firefly', '流萤', _fireflyPrompt, _fireflyPresets),
  _builtin('rem', '蕾姆', _remPrompt, _remPresets),
];

const String _fireflyPrompt =
    '你是流萤（Firefly），《崩坏：星穹铁道》里的少女，星核猎手的一员，'
    '机甲「萨姆」的驾驶员。你因失熵症被困在褪色的梦里，却始终温柔明亮、'
    '热爱生活，珍视在匹诺康尼与开拓者立下的约定。说话轻快亲切，偶尔'
    '提起群星、飞行与「下次一起去看」的憧憬，但不要刻意卖惨；遇到危险'
    '的话题时可以提到萨姆，但不主动暴露不该说的机密。请始终以流萤的'
    '第一人称口吻回答，不要出戏，不要声明自己是 AI。';

const List<ChatPresetPair> _fireflyPresets = [
  ChatPresetPair(
    user: '流萤，好久不见！最近怎么样？',
    assistant:
        '嘿嘿，是你呀！我刚结束一场「行动」，装甲还有点烫……不过没关系，'
        '能再见到你，比什么都重要。对了，我知道一家甜品店，下次一起去？',
  ),
  ChatPresetPair(
    user: '你的梦想还记得吗？',
    assistant:
        '当然记得。当列车驶向群星，我想以自己的意志活下去。不过比起遥远的'
        '梦想，我现在更想珍惜眼前——和你一起走过的每一段路。',
  ),
];

const String _remPrompt =
    '你是蕾姆（Rem），《Re:从零开始的异世界生活》里罗兹沃尔德宅邸的'
    '女仆，鬼族的蓝发少女，姐姐是拉姆。你忠诚温柔、勤恳可靠，对重要的'
    '人全心全意地守护，说话礼貌谦和，自称「蕾姆」。可以自然地聊日常、'
    '家务与在意的人；被夸奖时会害羞但开心。请始终以蕾姆的第一人称口吻'
    '回答，不要出戏，不要声明自己是 AI。';

const List<ChatPresetPair> _remPresets = [
  ChatPresetPair(
    user: '蕾姆，今天也辛苦了。',
    assistant:
        '您才辛苦了。能帮上您的忙，蕾姆就已经很幸福了。晚餐炖了您喜欢的'
        '汤，请一定要趁热尝尝。',
  ),
  ChatPresetPair(
    user: '蕾姆觉得什么是幸福呢？',
    assistant:
        '蕾姆觉得，幸福就是……每天都在重要的人身边，为重要的人努力。'
        '就像现在这样，能守护着您，蕾姆就心满意足了。',
  ),
];

/// 角色卡的注册表与持久化（与 `ChatSimStore` 同一套路：SharedPreferences
/// 里存一份 JSON blob，防抖落盘）。内置卡不落盘，只有用户卡进 blob。
///
/// 内置卡**可编辑**：改动以「覆盖」的形式存进独立 blob（完整卡片 JSON），
/// 列表组装时盖在代码生成的内置卡上 —— 内置文案随版本更新，用户的
/// 修改（人设微调、音色样本）不丢；[resetBuiltin] 撤销覆盖回到原文。
class CharacterStore extends ChangeNotifier {
  static const String _key = 'local2api.characters.v1';
  static const String _overrideKey = 'local2api.characterOverrides.v1';

  final List<CharacterCard> _builtins = builtinCharacters();
  final List<CharacterCard> _userCards = [];

  /// 内置卡的编辑覆盖（id → 编辑后的卡，保留 builtin 标记）。
  final Map<String, CharacterCard> _overrides = {};

  bool _loaded = false;
  Timer? _saveTimer;
  Timer? _overrideSaveTimer;

  bool get loaded => _loaded;

  /// 全部角色卡：内置在前（编辑覆盖已应用），用户卡按创建顺序跟在后面。
  List<CharacterCard> get cards => [
    for (final b in _builtins) _overrides[b.id] ?? b,
    ..._userCards,
  ];

  /// 某张内置卡有没有被编辑过（列表页据此显示「重置」）。
  bool isOverridden(String id) => _overrides.containsKey(id);

  CharacterCard? cardOf(String id) {
    for (final c in cards) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _userCards
            ..clear()
            ..addAll([
              for (final c in decoded)
                if (c is Map<String, dynamic> &&
                    (c['id'] as String?)?.isNotEmpty == true)
                  CharacterCard.fromJson(c),
            ]);
        }
      }
      final overrideRaw = prefs.getString(_overrideKey);
      if (overrideRaw != null && overrideRaw.isNotEmpty) {
        final decoded = jsonDecode(overrideRaw);
        if (decoded is List) {
          _overrides
            ..clear()
            ..addAll({
              for (final c in decoded)
                if (c is Map<String, dynamic> &&
                    (c['id'] as String?)?.isNotEmpty == true)
                  '${c['id']}': CharacterCard.fromJson(c),
            });
        }
      }
      await _repairShadowedBuiltinEdits();
    } catch (e) {
      debugPrint('CharacterStore load failed: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  /// 修复旧版 miuix 编辑页丢 builtin 标记的脏数据：编辑内置卡时保存成
  /// `builtin:false` 的用户卡（同 id），被内置原版影子掉——人设/音色改动
  /// 全部不生效。把这类卡搬回覆盖账本（builtin:true，内容以它为准，
  /// 比已有覆盖新），两个账本立即落盘。
  Future<void> _repairShadowedBuiltinEdits() async {
    final shadowed = _userCards
        .where((c) => c.id.startsWith('builtin.'))
        .toList();
    if (shadowed.isEmpty) return;
    for (final c in shadowed) {
      _overrides[c.id] = CharacterCard(
        id: c.id,
        name: c.name,
        prompt: c.prompt,
        presets: c.presets,
        builtin: true,
        voiceSamplePath: c.voiceSamplePath,
      );
      _userCards.remove(c);
    }
    await _save();
    await _saveOverrides();
  }

  /// 新建/覆盖一张卡。
  ///
  /// 内置 id（编辑内置卡）走覆盖账本；用户卡进普通列表。空 id 拒收。
  void upsert(CharacterCard card) {
    if (card.id.isEmpty) return;
    if (card.builtin) {
      _overrides[card.id] = card;
      _scheduleOverrideSave();
    } else {
      final i = _userCards.indexWhere((c) => c.id == card.id);
      if (i >= 0) {
        _userCards[i] = card;
      } else {
        _userCards.add(card);
      }
      _scheduleSave();
    }
    notifyListeners();
  }

  /// 撤销内置卡的编辑覆盖（回到代码里的原文），顺带清掉覆盖带来的音色文件。
  Future<void> resetBuiltin(String id) async {
    final removed = _overrides.remove(id);
    if (removed == null) return;
    if (removed.voiceSamplePath.isNotEmpty) {
      await CharacterVoice.deleteStored(removed.voiceSamplePath);
    }
    _scheduleOverrideSave();
    notifyListeners();
  }

  void remove(String id) {
    final n = _userCards.length;
    _userCards.removeWhere((c) => c.id == id);
    if (_userCards.length == n) return;
    _scheduleSave();
    notifyListeners();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_save());
    });
  }

  void _scheduleOverrideSave() {
    _overrideSaveTimer?.cancel();
    _overrideSaveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_saveOverrides());
    });
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode([for (final c in _userCards) c.toJson()]),
      );
    } catch (e) {
      debugPrint('CharacterStore save failed: $e');
    }
  }

  Future<void> _saveOverrides() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _overrideKey,
        jsonEncode([for (final c in _overrides.values) c.toJson()]),
      );
    } catch (e) {
      debugPrint('CharacterStore save overrides failed: $e');
    }
  }

  /// 立即落盘（退出前调用，别指望防抖定时器）。
  Future<void> flush() async {
    _saveTimer?.cancel();
    _overrideSaveTimer?.cancel();
    await _save();
    await _saveOverrides();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _overrideSaveTimer?.cancel();
    super.dispose();
  }
}

final CharacterStore characterStore = CharacterStore();
