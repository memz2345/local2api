import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

/// CIDR 匹配与本机地址枚举。
class NetworkUtils {
  NetworkUtils._();

  static const MethodChannel _channel = MethodChannel(
    'com.memz2345.local2api/locale',
  );

  /// 读系统级 HTTP 代理（Android 的 Settings.Global.http_proxy，即
  /// 「Wi-Fi 代理 / 全局代理」设置，宿主可用 `adb shell settings put
  /// global http_proxy 10.0.2.2:PORT` 给模拟器配）。非 Android 或未配置
  /// 返回 null。
  static String? _cachedProxy;
  static Future<String?> systemHttpProxy() async {
    if (_cachedProxy != null) return _cachedProxy;
    if (!Platform.isAndroid) return null;
    try {
      final proxy =
          await _channel.invokeMethod<String>('getSystemHttpProxy');
      return _cachedProxy = (proxy == null || proxy.trim().isEmpty)
          ? null
          : proxy.trim();
    } catch (_) {
      return null;
    }
  }

  /// 给实验室的下载 HttpClient 配代理：优先系统代理，其次环境变量。
  static Future<void> configureDownloadProxy(HttpClient client) async {
    final proxy = await systemHttpProxy();
    if (proxy != null) {
      client.findProxy = (_) => 'PROXY $proxy';
      return;
    }
    client.findProxy = HttpClient.findProxyFromEnvironment;
  }

  /// 解析 CIDR 为 (网络地址 BigInt, 前缀长度, 是否 IPv4)。
  /// IPv4 与 IPv6 都支持；解析失败返回 null。
  static (BigInt, int, bool)? parseCidr(String cidr) {
    final s = cidr.trim();
    if (s.isEmpty) return null;
    final slash = s.indexOf('/');
    String addrPart;
    int prefix;
    if (slash < 0) {
      addrPart = s;
      prefix = -1; // 单个地址，按 /32 或 /128 处理
    } else {
      addrPart = s.substring(0, slash);
      prefix = int.tryParse(s.substring(slash + 1)) ?? -1;
    }
    final addr = InternetAddress.tryParse(addrPart);
    if (addr == null) return null;

    // IPv4-mapped IPv6 (::ffff:a.b.c.d) 按 IPv4 处理
    final bool isV4 = addr.type == InternetAddressType.IPv4;
    final BigInt raw = _toBigInt(addr, isV4);
    final int bits = isV4 ? 32 : 128;
    if (prefix < 0) prefix = bits;
    if (prefix > bits) return null;
    // 网络地址 = 原地址 & mask
    final BigInt mask = prefix == 0
        ? BigInt.zero
        : ((BigInt.one << prefix) - BigInt.one) << (bits - prefix);
    return (raw & mask, prefix, isV4);
  }

  static BigInt _toBigInt(InternetAddress addr, bool isV4) {
    var raw = addr.rawAddress;
    if (!isV4 && _isV4Mapped(raw)) raw = raw.sublist(12);
    BigInt v = BigInt.zero;
    for (final b in raw) {
      v = (v << 8) | BigInt.from(b);
    }
    return v;
  }

  static bool _isV4Mapped(List<int> raw) {
    if (raw.length != 16) return false;
    for (var i = 0; i < 10; i++) {
      if (raw[i] != 0) return false;
    }
    return raw[10] == 0xff && raw[11] == 0xff;
  }

  /// 判断客户端 IP 是否命中 CIDR。
  /// 客户端与规则地址族不同（且无 v4-mapped 关系）时不匹配。
  static bool cidrMatches(String cidr, InternetAddress client) {
    final rule = parseCidr(cidr);
    if (rule == null) return false;
    final (net, prefix, ruleV4) = rule;
    final clientV4 = client.type == InternetAddressType.IPv4;
    final bool treatClientAsV4 = clientV4 || _isV4Mapped(client.rawAddress);
    if (ruleV4 != treatClientAsV4) return false;
    final BigInt clientRaw = _toBigInt(client, treatClientAsV4);
    final int bits = ruleV4 ? 32 : 128;
    if (prefix <= 0) return true;
    final BigInt mask =
        ((BigInt.one << prefix) - BigInt.one) << (bits - prefix);
    return (clientRaw & mask) == net;
  }

  /// 列出本机所有非回环的 IPv4 地址（局域网/VPN 展示用）。
  static Future<List<String>> localLanAddresses() async {
    final result = <String>[];
    try {
      for (final iface in await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      )) {
        for (final a in iface.addresses) {
          if (a.type == InternetAddressType.IPv4) result.add(a.address);
        }
      }
    } catch (_) {}
    return result;
  }

  /// 生成一个短随机 ID。
  static String newId() {
    final rand = Random.secure();
    const chars = 'abcdef0123456789';
    return List.generate(12, (_) => chars[rand.nextInt(chars.length)]).join();
  }
}
