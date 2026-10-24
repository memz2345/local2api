/// Zen 免密车道的会话 / 请求 id：形状必须长成网关自己铸造的样子。
///
/// 2026-10 起网关不只看形状：`ses_` 的 12 位 hex 前缀必须能解码成
/// `~(毫秒时间戳 * 4096 + counter)` —— 官方客户端用当前时间铸造，网关把
/// 前缀取反后校验时间戳。真网实测（2026-10-13）：纯 sha256 派生的随机前缀
/// 一律 403 FreeTierError（「需要官方客户端」报错的根因），而前缀合公式时
/// 24 小时前的时间戳仍放行、`msg_` 前缀完全不被校验。
///
/// 所以会话 id 改成「现铸时间戳前缀 + 种子派生的尾段」，同一会话的稳定性
/// 由一张 LRU 表保住（9router PR #4782 的同一方案）：免费额度按 session
/// 计，一次请求一个新 id 会撞 429 且 retry-after 递增。重铸或被挤出后
/// 换新 id 的代价只是新起一份额度，不破坏任何语义。
///
/// 重铸周期是 **6 天**，不是半小时（对齐 zen-gate `internal/lane/upstream.go`
/// 的 `sessionRemintAfter`）：上游免费档容忍约一周内的前缀，6 天重铸是为了
/// 留在窗口内；半小时一换等于每半小时新开一份额度桶，并且每次都把上游的
/// prompt cache 丢掉（整段对话重新 prefill）。
///
/// `msg_` 请求 id 保留 sha256 派生：上游不校验它的前缀，而「同一回合的
/// 重试共用一个 id」仍有意义（宿主侧的错误关联）。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

const String _base62Alphabet =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

final RegExp kZenSessionRe = RegExp(r'^ses_[0-9a-f]{12}[0-9A-Za-z]{14}$');
final RegExp kZenRequestRe = RegExp(r'^msg_[0-9a-f]{12}[0-9A-Za-z]{14}$');

String zenBase62(Iterable<int> bytes) =>
    bytes.map((b) => _base62Alphabet[b % 62]).join();

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// 取「现在」的钩子：TTL 判定用它，测试钉住钟点。
@visibleForTesting
DateTime Function() zenSessionClock = DateTime.now;

/// 清空会话表，并把铸造计数器归零（测试要钉住钟点逐条比对前缀，
/// 计数器不归零会跨用例串味）。
@visibleForTesting
void zenSessionCacheClear() {
  _sessionCache.clear();
  _lastStamp = 0;
  _seqCounter = 0;
}

class _SessionEntry {
  final String id;

  /// **铸造时刻**，不是最后使用时刻。
  ///
  /// 这里必须是铸造时刻才能保证「表里的 id 一定还在网关的新鲜度窗口内」：
  /// 若按最后使用时间续期，一条天天在用的会话永远不过期，它的 id 会在
  /// 第 7 天悄悄越过窗口、开始 403。zen-gate 的 `mintedSession.at` 同样是
  /// 铸造时刻（`internal/lane/upstream.go:112,121`）。
  final DateTime mintedAt;
  _SessionEntry(this.id, this.mintedAt);
}

/// 种子 → 会话 id 的 LRU 表。插入序即访问序（命中时摘下重插），挤掉最老的。
final Map<String, _SessionEntry> _sessionCache = <String, _SessionEntry>{};

const int _sessionCacheCap = 1024;

/// 会话 id 的重铸周期。必须 ≤ [zenSessionIdUsable] 的新鲜度窗口，
/// 否则表里会存着一个网关已经不再放行的 id。
const Duration _sessionTtl = Duration(days: 6);

/// 一个 `ses_` id 是否能直接拿去打网关：形状对，且 12 位 hex 前缀按
/// 「取反时间戳」公式解码后与当下对得上。
///
/// 注意精度陷阱：`时间戳 * 4096` 是 53 位，而前缀只有 48 位（6 字节），
/// 官方客户端铸造时高位被截断。所以解码只能还原出 `ts mod 2^36`
/// （约 797 天一周期的计数），拿它跟「当下的同余值」比窗口，而不是跟
/// 绝对时间戳比大小。
bool zenSessionIdUsable(String? id) {
  if (id == null) return false;
  final trimmed = id.trim();
  if (!kZenSessionRe.hasMatch(trimmed)) return false;
  // 48 位 hex 在 int 范围内，直接解析。
  final inverted = int.parse(trimmed.substring(4, 16), radix: 16);
  final decoded = (~inverted & 0xFFFFFFFFFFFF) >> 12; // ts mod 2^36
  const period = 1 << 36;
  final now = zenSessionClock().millisecondsSinceEpoch;
  var delta = (now % period) - decoded;
  if (delta < 0) delta += period;
  // 窗口 = 上游免费档容忍的前缀年龄（约一周），收到 6 天与重铸周期对齐：
  // 「缓存里的 id 一定还在可用窗口内」这条不变量就是靠这两个数相等成立的。
  // 真网实测 24 小时前的 id 仍被放行，所以 6 天是安全的；同时也足以挡掉
  // 「解码出来根本不是时间戳同余值」的纯哈希前缀（那些均匀散布在整个周期
  // 上，几乎必然落在窗口外）。往未来方向的偏差单独放 1 天，容忍设备时钟
  // 略微偏快。
  const window = 6 * 86400000;
  return delta <= window || delta >= period - 86400000;
}

/// `ses_` 铸造用的进程内单调计数器（zen-gate `internal/lane/upstream.go:50-72`
/// 的 `lastStamp` / `seqCounter`）。Dart 这一段跑在单 isolate 里，普通 int 就够。
int _lastStamp = 0;
int _seqCounter = 0;

/// 铸一个合公式的会话 id：前缀 = `~((当下毫秒 << 12) | (seq & 0xFFF))` 的
/// 6 字节大端，尾段仍由种子派生（网关不校验尾段，但让同一批种子铸出的 id
/// 可辨识）。
///
/// seq 是**每毫秒归零的单调递增计数器**，不是固定的 1：官方客户端在同一毫秒
/// 内铸出多个会话时前缀也各不相同，固定 +1 会让同一毫秒内的两个会话拿到
/// 完全相同的前缀 —— 一个明显的指纹异味。
String _mintSession(String seed) {
  final digest = sha256.convert(utf8.encode('our-free-model\x00$seed')).bytes;
  final tail = zenBase62(digest.sublist(6, 20));
  final now = zenSessionClock().millisecondsSinceEpoch;
  if (_lastStamp != now) {
    _lastStamp = now;
    _seqCounter = 0;
  }
  _seqCounter += 1;
  final value = ~((now << 12) | (_seqCounter & 0xFFF));
  final prefix = List.generate(
    6,
    (i) => ((value >> (40 - 8 * i)) & 0xFF).toRadixString(16).padLeft(2, '0'),
  ).join();
  return 'ses_$prefix$tail';
}

/// 同一个会话永远得到同一个 `ses_`（重铸周期内）。已经是合法 id 的原样透传，
/// 这样官方客户端自己带了会话 id 时我们不用另起一份额度。
String zenSessionFor(String seed) {
  final trimmed = seed.trim();
  if (zenSessionIdUsable(trimmed)) return trimmed;
  final key = trimmed.isEmpty ? 'global' : trimmed;
  final now = zenSessionClock();
  final hit = _sessionCache[key];
  if (hit != null) {
    // 摘下重插维持 LRU 序，但**不刷新铸造时刻**：过期判定看的是 id 本身的
    // 年龄，跟这条会话有多活跃无关。
    _sessionCache.remove(key);
    if (now.difference(hit.mintedAt) < _sessionTtl) {
      _sessionCache[key] = hit;
      return hit.id;
    }
  }
  final id = _mintSession(key);
  _sessionCache[key] = _SessionEntry(id, now);
  while (_sessionCache.length > _sessionCacheCap) {
    _sessionCache.remove(_sessionCache.keys.first);
  }
  return id;
}

/// 同一回合的重试共用一个 `msg_`；`turnSeed` 由调用方从消息内容算出来。
/// 前缀不被上游校验（真网实测），确定性派生即可。
String zenRequestIdFor(String session, String turnSeed) {
  final digest = sha256
      .convert(utf8.encode('our-free-model-req\x00$session\x00$turnSeed'))
      .bytes;
  return 'msg_${_hex(digest.sublist(0, 6))}${zenBase62(digest.sublist(6, 20))}';
}
