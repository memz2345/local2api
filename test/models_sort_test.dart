import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/models_sort_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

ModelEntry m(String name) => ModelEntry(publicName: name);

void main() {
  group('modelGroupKey', () {
    test('字母按大写归组，非字母一律 #', () {
      expect(modelGroupKey('alpha'), 'A');
      expect(modelGroupKey('Zeta'), 'Z');
      expect(modelGroupKey('  beta'), 'B');
      expect(modelGroupKey('123'), '#');
      expect(modelGroupKey('中文模型'), '#');
      expect(modelGroupKey(''), '#');
      expect(modelGroupKey('_under'), '#');
    });
  });

  group('orderedModelIndices', () {
    test('默认顺序就是原样', () {
      final list = [m('zeta'), m('alpha'), m('123')];
      expect(orderedModelIndices(list, ModelsSortMode.natural), [0, 1, 2]);
    });

    test('首字母正序：A→Z，非字母排最后', () {
      final list = [m('zeta'), m('123'), m('alpha'), m('Beta')];
      expect(orderedModelIndices(list, ModelsSortMode.alphabet), [2, 3, 0, 1]);
    });

    test('同字母按名字字典序（忽略大小写）', () {
      final list = [m('delta'), m('Alpha'), m('apple'), m('Dusk')];
      // A 组（alpha < apple）在前，D 组（delta < dusk）在后
      expect(orderedModelIndices(list, ModelsSortMode.alphabet), [1, 2, 0, 3]);
    });
  });

  group('groupModelIndices', () {
    test('分组按字母升序，# 最后，组内保序', () {
      final list = [m('beta'), m('apple'), m('123'), m('Ant')];
      final groups = groupModelIndices(list);
      expect(groups.map((g) => g.letter).toList(), ['A', 'B', '#']);
      // 'ant' < 'apple' → Ant 在前
      expect(groups[0].indices, [3, 1]);
      expect(groups[1].indices, [0]);
      expect(groups[2].indices, [2]);
    });
  });

  group('ModelsSortStore 持久化', () {
    test('默认 natural，存过之后读回 alphabet', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await ModelsSortStore.load(), ModelsSortMode.natural);
      await ModelsSortStore.save(ModelsSortMode.alphabet);
      expect(await ModelsSortStore.load(), ModelsSortMode.alphabet);
      await ModelsSortStore.save(ModelsSortMode.natural);
      expect(await ModelsSortStore.load(), ModelsSortMode.natural);
    });
  });
}
