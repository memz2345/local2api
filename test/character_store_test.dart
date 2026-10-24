// 内置角色卡「编辑覆盖」机制的回归测试。
//
// 覆盖只动内存 + shared_preferences（mock），不碰文件系统 —— 音色样本
// 为空时 resetBuiltin 不会走到 path_provider。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/character_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CharacterStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = CharacterStore();
    await store.load();
  });

  group('内置角色卡编辑覆盖', () {
    test('内置卡默认不可覆盖，用户卡正常增删', () {
      final builtin = store.cards.first;
      expect(builtin.builtin, isTrue);

      // copyWith 不给改 builtin 标记（那是出身，不是属性）；
      // 用户卡直接构造。
      final user = CharacterCard(id: 'user.1', name: '我的卡', prompt: '');
      store.upsert(user);
      expect(store.cards.last.name, '我的卡');

      store.remove('user.1');
      expect(store.cards.any((c) => c.id == 'user.1'), isFalse);
    });

    test('编辑内置卡走覆盖：列表反映改动，原文可一键重置', () async {
      final builtin = store.cards.first;
      final originalPrompt = builtin.prompt;

      final edited = builtin.copyWith(
        name: '${builtin.name}·改',
        prompt: '新的提示词',
        voiceSamplePath: '',
      );
      store.upsert(edited);

      // 列表里同名 id 已是被改过的那份，且仍是内置（不可删除）
      expect(store.cardOf(builtin.id)!.name, '${builtin.name}·改');
      expect(store.cardOf(builtin.id)!.prompt, '新的提示词');
      expect(store.cardOf(builtin.id)!.builtin, isTrue);
      expect(store.isOverridden(builtin.id), isTrue);
      // 内置卡数量不变（不会因为编辑多出一张重复卡）
      expect(store.cards.where((c) => c.builtin), hasLength(2));

      await store.resetBuiltin(builtin.id);
      expect(store.isOverridden(builtin.id), isFalse);
      expect(store.cardOf(builtin.id)!.prompt, originalPrompt);
      expect(store.cardOf(builtin.id)!.name, builtin.name);
    });

    test('覆盖随 blob 持久化，重启后还在', () async {
      final builtin = store.cards.first;
      store.upsert(builtin.copyWith(prompt: '持久化的覆盖'));
      // 落盘是防抖的（400ms），测试里直接 flush
      await store.flush();

      // 新实例从同一份 mock prefs 读回
      final store2 = CharacterStore();
      await store2.load();
      expect(store2.isOverridden(builtin.id), isTrue);
      expect(store2.cardOf(builtin.id)!.prompt, '持久化的覆盖');
    });

    test('编辑内置卡不污染用户卡列表（id 不串账）', () {
      final builtin = store.cards.first;
      final before = store.cards.length;
      store.upsert(builtin.copyWith(name: '改名'));
      expect(store.cards.length, before);
    });
  });

  group('影子卡修复（旧版 miuix 编辑页丢 builtin 标记）', () {
    test('用户卡账本里的 builtin.* 卡搬回覆盖账本，样本随之生效', () async {
      SharedPreferences.setMockInitialValues({
        'local2api.characters.v1': jsonEncode([
          {
            'id': 'builtin.firefly',
            'name': '流萤·改',
            'prompt': '改过的提示词',
            'voiceSamplePath': '/x/voice.mp3',
            'presets': <Map<String, dynamic>>[],
          },
        ]),
        'local2api.characterOverrides.v1': jsonEncode([]),
      });
      final dirty = CharacterStore();
      await dirty.load();

      // cardOf 命中的是被搬进覆盖账本的改动版（样本在内），不再是内置原版
      final card = dirty.cardOf('builtin.firefly')!;
      expect(card.builtin, isTrue);
      expect(card.voiceSamplePath, '/x/voice.mp3');
      expect(card.prompt, '改过的提示词');
      expect(dirty.isOverridden('builtin.firefly'), isTrue);
      // 列表不再有同名影子卡
      expect(dirty.cards.where((c) => c.id == 'builtin.firefly'), hasLength(1));

      // 修复已落盘：新实例读回来还是覆盖版，且没有重复卡
      final reopened = CharacterStore();
      await reopened.load();
      expect(reopened.cardOf('builtin.firefly')!.voiceSamplePath, '/x/voice.mp3');
      expect(
        reopened.cards.where((c) => c.id == 'builtin.firefly'),
        hasLength(1),
      );
    });

    test('已有正式覆盖时影子卡以其内容为准搬入（用户最近一次编辑优先）', () async {
      SharedPreferences.setMockInitialValues({
        'local2api.characters.v1': jsonEncode([
          {
            'id': 'builtin.rem',
            'name': '蕾姆·影子',
            'prompt': '影子提示词',
            'voiceSamplePath': '/x/rem.mp3',
          },
        ]),
        'local2api.characterOverrides.v1': jsonEncode([
          {'id': 'builtin.rem', 'name': '蕾姆·正式覆盖', 'prompt': '旧覆盖'},
        ]),
      });
      final dirty = CharacterStore();
      await dirty.load();
      final card = dirty.cardOf('builtin.rem')!;
      expect(card.name, '蕾姆·影子');
      expect(card.voiceSamplePath, '/x/rem.mp3');
      expect(dirty.cards.where((c) => c.id == 'builtin.rem'), hasLength(1));
    });
  });
}
