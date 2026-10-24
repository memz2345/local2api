import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/models/builtin_profiles.dart';
import 'package:local2api/models/config_profile.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _indexKey = 'local2api.profiles.v1';
const _docPrefix = 'local2api.profile.doc.';

String _doc({String id = 'demo', String baseUrl = 'https://a.example/v1'}) =>
    jsonEncode({
      'id': id,
      'name': id.toUpperCase(),
      'upstreams': [
        {
          'id': 'u-$id',
          'name': 'U',
          'baseUrl': baseUrl,
          'models': [
            {'publicName': 'm1', 'target': 'm1'},
          ],
        },
      ],
    });

/// 让 unawaited 的落盘与防抖定时器跑完。
Future<void> _drain() async {
  await Future<void>.delayed(const Duration(milliseconds: 500));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProfileStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = ProfileStore();
    await store.load();
  });

  tearDown(() => store.dispose());

  group('加载', () {
    test('全新安装：没有索引键，内置档案在列且不激活', () {
      expect(store.hadPersistedIndex, isFalse);
      expect(store.profiles.map((p) => p.id), [kZenProfileId]);
      expect(store.activeId, isNull);
      expect(store.isBuiltin(kZenProfileId), isTrue);
    });

    test('内置档案每次 load 都由代码生成，不落盘', () async {
      await store.flush();
      await _drain();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().any((k) => k.startsWith(_docPrefix)), isFalse);
    });
  });

  group('导入与持久化', () {
    test('导入后重载还在，来源与原文都保得住', () async {
      store.importDocument(
        _doc(),
        const ProfileSource(ProfileSourceKind.url, url: 'https://s/p.json'),
      );
      await store.flush();
      await _drain();

      final reloaded = ProfileStore();
      addTearDown(reloaded.dispose);
      await reloaded.load();

      expect(reloaded.hadPersistedIndex, isTrue);
      expect(reloaded.profiles.map((p) => p.id), [kZenProfileId, 'demo']);
      final p = reloaded.profileOf('demo')!;
      expect(p.source.kind, ProfileSourceKind.url);
      expect(p.source.url, 'https://s/p.json');
      expect(p.upstreams.single.baseUrl, 'https://a.example/v1');
      expect(reloaded.rawOf('demo'), isNotNull);
    });

    test('文件来源保得住文件名', () async {
      store.importDocument(
        _doc(id: 'fromfile'),
        const ProfileSource(ProfileSourceKind.file, fileName: 'my.json'),
      );
      await store.flush();
      await _drain();

      final reloaded = ProfileStore();
      addTearDown(reloaded.dispose);
      await reloaded.load();
      expect(reloaded.profileOf('fromfile')!.source.kind, ProfileSourceKind.file);
      expect(reloaded.profileOf('fromfile')!.source.fileName, 'my.json');
    });

    test('id 撞内置档案直接拒：否则会把不落盘的内置那份盖掉', () {
      expect(
        () => store.importDocument(
          _doc(id: kZenProfileId),
          const ProfileSource(ProfileSourceKind.inline),
        ),
        throwsA(
          isA<ProfileFormatException>().having(
            (e) => e.code,
            'code',
            ProfileFormatError.duplicateId,
          ),
        ),
      );
    });

    test('id 撞已导入的档案也拒', () {
      store.importDocument(_doc(), const ProfileSource(ProfileSourceKind.inline));
      expect(
        () => store.importDocument(
          _doc(baseUrl: 'https://b.example/v1'),
          const ProfileSource(ProfileSourceKind.inline),
        ),
        throwsA(isA<ProfileFormatException>()),
      );
    });

    test('删除：档案、状态、原文键一起清掉，内置的删不动', () async {
      store.importDocument(_doc(), const ProfileSource(ProfileSourceKind.inline));
      store.setActive('demo');
      await store.flush();
      await _drain();

      store.remove('demo');
      await store.flush();
      await _drain();

      expect(store.profileOf('demo'), isNull);
      expect(store.activeId, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('${_docPrefix}demo'), isNull);

      store.remove(kZenProfileId);
      expect(store.profileOf(kZenProfileId), isNotNull);
    });

    test('索引里没有、文档键却残留的会被清掉', () async {
      SharedPreferences.setMockInitialValues({
        _indexKey: jsonEncode({'activeId': null, 'order': [], 'states': []}),
        '${_docPrefix}ghost': _doc(id: 'ghost'),
      });
      final s = ProfileStore();
      addTearDown(s.dispose);
      await s.load();
      await _drain();

      expect(s.profileOf('ghost'), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('${_docPrefix}ghost'), isNull);
    });
  });

  group('激活标记', () {
    test('单选：换激活对象时旧的自动落下', () {
      store.importDocument(
        _doc(id: 'a'),
        const ProfileSource(ProfileSourceKind.inline),
      );
      store.importDocument(
        _doc(id: 'b'),
        const ProfileSource(ProfileSourceKind.inline),
      );

      store.setActive('a');
      expect(store.stateOf('a').active, isTrue);

      store.setActive('b');
      expect(store.activeId, 'b');
      expect(store.stateOf('a').active, isFalse);
      expect(store.stateOf('b').active, isTrue);

      store.setActive(null);
      expect(store.stateOf('b').active, isFalse);
    });

    test('激活标记跟着索引持久化', () async {
      store.importDocument(
        _doc(),
        const ProfileSource(ProfileSourceKind.inline),
      );
      store.setActive('demo');
      store.mutateState('demo', (s) => s.etag = 'W/"x"');
      await store.flush();
      await _drain();

      final reloaded = ProfileStore();
      addTearDown(reloaded.dispose);
      await reloaded.load();
      expect(reloaded.activeId, 'demo');
      expect(reloaded.stateOf('demo').etag, 'W/"x"');
    });
  });

  group('文档替换', () {
    test('订阅方改了 id 等于换了一份档案，拒绝就地顶替', () {
      store.importDocument(_doc(), const ProfileSource(ProfileSourceKind.inline));
      expect(
        () => store.replaceDocument('demo', _doc(id: 'other')),
        throwsA(
          isA<ProfileFormatException>().having(
            (e) => e.code,
            'code',
            ProfileFormatError.duplicateId,
          ),
        ),
      );
      // 旧文档原地不动
      expect(store.profileOf('demo')!.upstreams.single.id, 'u-demo');
    });

    test('同 id 换内容成功，状态（激活/自定义标记）保持不动', () {
      store.importDocument(_doc(), const ProfileSource(ProfileSourceKind.inline));
      store.setActive('demo');
      store.mutateState('demo', (s) => s.customized = true);

      store.replaceDocument(
        'demo',
        _doc(baseUrl: 'https://new.example/v1'),
      );

      expect(
        store.profileOf('demo')!.upstreams.single.baseUrl,
        'https://new.example/v1',
      );
      expect(store.activeId, 'demo');
      expect(store.stateOf('demo').customized, isTrue);
      expect(
        store.profileOf('demo')!.source.kind,
        ProfileSourceKind.inline,
        reason: '来源沿用原来那份，不由新文档自报',
      );
    });

    test('坏内容替换失败时旧文档不受影响', () {
      store.importDocument(_doc(), const ProfileSource(ProfileSourceKind.inline));
      expect(
        () => store.replaceDocument('demo', 'not json at all'),
        throwsA(isA<ProfileFormatException>()),
      );
      expect(store.profileOf('demo')!.upstreams.single.baseUrl, 'https://a.example/v1');
    });
  });

  group('坏索引', () {
    test('索引是垃圾时不崩，退回全新安装的样子', () async {
      SharedPreferences.setMockInitialValues({_indexKey: '这不是 JSON'});
      final s = ProfileStore();
      addTearDown(s.dispose);
      await s.load();
      expect(s.profiles.map((p) => p.id), [kZenProfileId]);
      expect(s.activeId, isNull);
    });
  });
}
