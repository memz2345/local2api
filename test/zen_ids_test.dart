import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/zen/zen_ids.dart';

void main() {
  setUp(() {
    zenSessionCacheClear();
    zenSessionClock = DateTime.now;
  });

  group('Zen 会话 / 请求 id', () {
    test('任意种子都派生出网关认得的形状', () {
      for (final seed in ['a', '', '你好 world', 'x' * 500]) {
        final session = zenSessionFor(seed);
        expect(kZenSessionRe.hasMatch(session), isTrue, reason: seed);
        expect(
          kZenRequestRe.hasMatch(zenRequestIdFor(session, 'turn')),
          isTrue,
          reason: seed,
        );
      }
    });

    test('会话前缀合取反时间戳公式（模 2^36 意义下对得上当下）', () {
      final session = zenSessionFor('gpt-x 你好');
      expect(zenSessionIdUsable(session), isTrue);
      final inverted = int.parse(session.substring(4, 16), radix: 16);
      final decoded = (~inverted & 0xFFFFFFFFFFFF) >> 12;
      const period = 1 << 36;
      final nowLow = DateTime.now().millisecondsSinceEpoch % period;
      var delta = nowLow - decoded;
      if (delta < 0) delta += period;
      // 铸造时刻就是当下：模周期内偏差几秒以内。
      expect(delta, lessThan(60000));
    });

    test('同一会话的每一轮拿到同一个 ses_', () {
      // 免费额度按 session 计：每请求新铸一个 id 会立刻撞 429。
      expect(zenSessionFor('gpt-x 你好'), zenSessionFor('gpt-x 你好'));
      expect(zenSessionFor('a'), isNot(zenSessionFor('b')));
    });

    test('合公式的传入 ses_ 原样透传，不另起一份额度', () {
      final fromHost = zenSessionFor('another-host-session');
      expect(zenSessionFor(fromHost), fromHost);
    });

    test('形状对但不合公式的旧 id 被拦下重铸（否则上游 403）', () {
      // 旧版本用 sha256 直接派生前缀：ses_f4ebaef1db90… 打上去就是
      // FreeTierError（2026-10-13 真网实测）。
      final legacy = 'ses_f4ebaef1db909ZzzWfWUtU4Pcn';
      expect(kZenSessionRe.hasMatch(legacy), isTrue);
      expect(zenSessionIdUsable(legacy), isFalse);
      final reminted = zenSessionFor(legacy);
      expect(reminted, isNot(legacy));
      expect(zenSessionIdUsable(reminted), isTrue);
    });

    test('非法的传入 id 会被换成合法形状，不是原样发出去', () {
      expect(zenSessionFor('ses_too_short'), isNot('ses_too_short'));
      expect(kZenSessionRe.hasMatch(zenSessionFor('ses_too_short')), isTrue);
    });

    test('重铸周期内同一种子换新 id 才发生（周期是 6 天，不是半小时）', () {
      // 对齐 zen-gate `internal/lane/upstream.go:130-134` 的 sessionRemintAfter：
      // 上游免费档容忍约一周内的前缀，6 天重铸是为了留在窗口内。半小时一换
      // 等于每半小时新开一份额度桶、并把上游的 prompt cache 丢掉。
      var now = DateTime(2026, 10, 13, 12);
      zenSessionClock = () => now;
      final first = zenSessionFor('conv');
      now = now.add(const Duration(minutes: 5));
      expect(zenSessionFor('conv'), first, reason: '几分钟内必须稳定');
      now = now.add(const Duration(minutes: 31));
      expect(
        zenSessionFor('conv'),
        first,
        reason: '旧版在这里就重铸了 —— 半小时一换是 bug，不是特性',
      );
      now = now.add(const Duration(days: 5));
      expect(zenSessionFor('conv'), first, reason: '6 天以内都还算新鲜');

      now = now.add(const Duration(days: 2));
      final reminted = zenSessionFor('conv');
      expect(reminted, isNot(first));
      expect(zenSessionIdUsable(reminted), isTrue);
      expect(reminted.substring(4, 16), isNot(first.substring(4, 16)));
    });

    test('过期判定看的是铸造时刻：天天在用的会话也照样在 6 天后重铸', () {
      // 若按「最后使用时间」续期，一条持续活跃的会话永远不过期，它的 id 会
      // 悄悄越过网关的新鲜度窗口、开始 403。这条钉住不变量：
      // 表里给出的 id 一定还在 zenSessionIdUsable 的窗口内。
      var now = DateTime(2026, 10, 13, 12);
      zenSessionClock = () => now;
      final first = zenSessionFor('busy');
      for (var day = 1; day <= 5; day++) {
        now = now.add(const Duration(days: 1));
        expect(zenSessionFor('busy'), first, reason: '第 $day 天仍在用');
        expect(zenSessionIdUsable(first), isTrue, reason: '第 $day 天仍在窗口内');
      }
      now = now.add(const Duration(days: 2));
      final reminted = zenSessionFor('busy');
      expect(reminted, isNot(first), reason: '第 7 天必须重铸');
      expect(zenSessionIdUsable(reminted), isTrue);
    });

    test('同一毫秒内铸出的多个会话前缀各不相同（seq 单调递增，不是固定 +1）', () {
      // 固定 +1 会让同一毫秒内的两个会话拿到完全相同的 12 位 hex 前缀 ——
      // 一个明显的指纹异味。照 zen-gate `internal/lane/upstream.go:50-72`：
      // 毫秒变了 seq 归零，value = ~(ms<<12 | seq&0xFFF)。
      final pinned = DateTime(2026, 10, 13, 12);
      zenSessionClock = () => pinned;

      final a = zenSessionFor('seed-a');
      final b = zenSessionFor('seed-b');
      final c = zenSessionFor('seed-c');
      expect(a.substring(4, 16), isNot(b.substring(4, 16)));
      expect(b.substring(4, 16), isNot(c.substring(4, 16)));
      expect(a.substring(4, 16), isNot(c.substring(4, 16)));
      // 三个都仍然合公式、都能过网关校验。
      for (final id in [a, b, c]) {
        expect(kZenSessionRe.hasMatch(id), isTrue);
        expect(zenSessionIdUsable(id), isTrue);
      }
      // 解出来的时间戳同余值三者一致（同一毫秒），差的是低 12 位的 seq。
      int tsOf(String id) {
        final inverted = int.parse(id.substring(4, 16), radix: 16);
        return (~inverted & 0xFFFFFFFFFFFF) >> 12;
      }

      int seqOf(String id) {
        final inverted = int.parse(id.substring(4, 16), radix: 16);
        return (~inverted & 0xFFFFFFFFFFFF) & 0xFFF;
      }

      expect(tsOf(a), tsOf(b));
      expect(tsOf(b), tsOf(c));
      expect(tsOf(a), pinned.millisecondsSinceEpoch % (1 << 36));
      expect([seqOf(a), seqOf(b), seqOf(c)], [1, 2, 3]);

      // 毫秒一跳，seq 归零重新数。
      final next = DateTime(2026, 10, 13, 12).add(const Duration(milliseconds: 1));
      zenSessionClock = () => next;
      final d = zenSessionFor('seed-d');
      expect(seqOf(d), 1);
      expect(tsOf(d), next.millisecondsSinceEpoch % (1 << 36));
    });

    test('LRU 超限时挤掉最老的会话', () {
      var now = DateTime(2026, 10, 13, 12);
      zenSessionClock = () => now;
      final evicted = zenSessionFor('oldest');
      for (var i = 0; i < 1100; i++) {
        zenSessionFor('seed-$i');
      }
      // oldest 早已被挤出：重新来拿会拿到新铸的 id。
      now = now.add(const Duration(minutes: 1));
      expect(zenSessionFor('oldest'), isNot(evicted));
    });

    test('请求 id 由会话 + 回合决定，重试同一回合拿到同一个', () {
      final s = zenSessionFor('conv');
      expect(zenRequestIdFor(s, 'turn-1'), zenRequestIdFor(s, 'turn-1'));
      expect(zenRequestIdFor(s, 'turn-1'), isNot(zenRequestIdFor(s, 'turn-2')));
    });

    test('zenSessionIdUsable 拒绝时间戳同余值落在窗口外的 id', () {
      // 前缀按公式编码，但时间戳本身越界。钉住时钟，全程确定。
      final pinned = DateTime.utc(2026, 10, 13, 12).millisecondsSinceEpoch;
      zenSessionClock = () => DateTime.fromMillisecondsSinceEpoch(pinned);

      String encode(int ts) {
        final value = ~(ts * 4096 + 1) & 0xFFFFFFFFFFFF;
        return 'ses_${value.toRadixString(16).padLeft(12, '0')}Aaaaaaaaaaaaaa';
      }

      expect(zenSessionIdUsable(encode(pinned)), isTrue, reason: '当下铸造');
      // 窗口从 7 天收窄到 6 天，与重铸周期对齐：这样「表里的 id 一定还在
      // 可用窗口内」才是恒真的。
      expect(
        zenSessionIdUsable(encode(pinned - 5 * 86400000)),
        isTrue,
        reason: '5 天：窗口内',
      );
      expect(
        zenSessionIdUsable(encode(pinned - 6 * 86400000)),
        isTrue,
        reason: '6 天：窗口边界仍然放行',
      );
      expect(
        zenSessionIdUsable(encode(pinned - 6 * 86400000 - 1)),
        isFalse,
        reason: '6 天多 1 毫秒就越界',
      );
      expect(
        zenSessionIdUsable(encode(pinned - 7 * 86400000)),
        isFalse,
        reason: '旧窗口（7 天）会放行它，现在不行',
      );
      // 比「现在」老 30 天：窗口外。
      expect(zenSessionIdUsable(encode(pinned - 30 * 86400000)), isFalse);
      // 比「现在」快 3 天：未来容忍只有 1 天。
      expect(zenSessionIdUsable(encode(pinned + 3 * 86400000)), isFalse);
      // 纯哈希前缀：同余值均匀散布，跟当下对不上。
      expect(zenSessionIdUsable('ses_f4ebaef1db909ZzzWfWUtU4Pcn'), isFalse);
    });
  });
}
