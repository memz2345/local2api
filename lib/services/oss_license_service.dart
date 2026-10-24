// lib/services/oss_license_service.dart
//
// 开源许可数据收集（移植自 NaviFlash 的 oss_license_service）。
//
// 数据有两个来源：
//  1. [LicenseRegistry]（即随包分发的 NOTICES 资产）—— 覆盖全部 pub 依赖与
//     随产物分发的三方库（angle / abseil-cpp / harfbuzz…），是「完整清单」
//     的唯一可靠来源；它只登记包名与许可正文，不带版本。
//  2. `pubspec.lock`（pubspec.yaml 里声明成 asset）—— 补上「包名 -> 版本」，
//     列表里显示版本徽标。取不到时版本为 null，其余照常。
//
// 解析结果按包聚合，进程内只做一次。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// `pubspec.lock` 的 asset key（见 pubspec.yaml 的 assets 声明）。
const String kOssLockAssetKey = 'pubspec.lock';

/// 无法归类时的许可标识。
const String kOssOtherLicense = 'Other';

/// 许可正文中的一段，[indent] 为原文缩进层级（0 为顶格）。
class OssParagraph {
  final String text;
  final int indent;

  const OssParagraph(this.text, this.indent);
}

/// 一个开源包及其名下的全部许可文本。
class OssPackage {
  final String name;

  /// 版本号（来自 pubspec.lock；非 pub 包为 null）。
  final String? version;

  /// 每份许可的段落列表，顺序与 [licenseIds] 一致。
  final List<List<OssParagraph>> licenses;

  /// 每份许可识别出的标识：MIT / Apache-2.0 / BSD-3-Clause / Other…
  final List<String> licenseIds;

  const OssPackage({
    required this.name,
    required this.licenses,
    required this.licenseIds,
    this.version,
  });

  int get licenseCount => licenses.length;

  String get primaryLicenseId =>
      licenseIds.isEmpty ? kOssOtherLicense : licenseIds.first;

  /// 许可标识去重后的短列表（列表页副标题用）。
  List<String> get distinctLicenseIds {
    final seen = <String>{};
    final out = <String>[];
    for (final id in licenseIds) {
      if (seen.add(id)) out.add(id);
    }
    return out;
  }

  /// 该包全部许可正文（用于整段复制）。
  String get fullText => licenses
      .map((paragraphs) => paragraphs.map((p) => p.text).join('\n\n'))
      .join('\n\n${'-' * 72}\n\n');
}

/// 一份完整的开源许可清单。
class OssLicenseData {
  /// 按包名（忽略大小写）升序排列。
  final List<OssPackage> packages;

  /// 许可正文总份数。
  final int totalLicenses;

  /// 许可标识 -> 包数量。
  final Map<String, int> licenseHistogram;

  const OssLicenseData({
    required this.packages,
    required this.totalLicenses,
    required this.licenseHistogram,
  });

  static const OssLicenseData empty = OssLicenseData(
    packages: <OssPackage>[],
    totalLicenses: 0,
    licenseHistogram: <String, int>{},
  );

  bool get isEmpty => packages.isEmpty;
}

Future<OssLicenseData>? _pending;

/// 收集全部开源许可（进程内缓存，[refresh] 强制重来）。
///
/// 失败**不缓存**：首次进入若 NOTICES 还没就绪，用户点「重试」得能真的重来。
/// 清空必须放在 `then/onError` 里 —— `?? = _collect()` 的写法会在 `_collect()`
/// 返回之后才赋值，把同步阶段做的清空覆盖掉，结果是失败被永久记住。
Future<OssLicenseData> loadOssLicenses({bool refresh = false}) {
  if (refresh) _pending = null;
  final cached = _pending;
  if (cached != null) return cached;

  final future = _collect();
  _pending = future;
  future.then<void>(
    (_) {},
    onError: (Object _, StackTrace _) {
      if (identical(_pending, future)) _pending = null;
    },
  );
  return future;
}

/// 测试用：清掉进程内缓存，避免上一个用例里挂着的 future（它的超时定时器
/// 活在那个用例的 fake-async zone 里）被下一个用例 await 到、永远不完成。
@visibleForTesting
void debugResetOssLicenseCache() {
  _pending = null;
}

/// 仅解析 pubspec.lock 里的「包名 -> 版本」映射，供测试与外部复用。
Map<String, String> parseLockVersions(String raw) {
  final versions = <String, String>{};
  var inPackages = false;
  String? current;

  for (final line in const LineSplitter().convert(raw)) {
    if (line.isEmpty) continue;
    // 顶层键：packages: / sdks: …
    if (!line.startsWith(' ')) {
      inPackages = line.trimRight() == 'packages:';
      current = null;
      continue;
    }
    if (!inPackages) continue;
    // 恰好两格缩进 = 包名（再深的缩进属于它的字段）。
    if (line.startsWith('  ') && !line.startsWith('   ')) {
      final trimmed = line.trim();
      current = trimmed.endsWith(':')
          ? trimmed.substring(0, trimmed.length - 1)
          : null;
      continue;
    }
    if (current == null) continue;
    final trimmed = line.trim();
    if (!trimmed.startsWith('version:')) continue;
    var version = trimmed.substring('version:'.length).trim();
    if (version.length >= 2 &&
        ((version.startsWith('"') && version.endsWith('"')) ||
            (version.startsWith("'") && version.endsWith("'")))) {
      version = version.substring(1, version.length - 1);
    }
    if (version.isNotEmpty) versions[current] = version;
    current = null;
  }
  return versions;
}

/// 从许可正文识别许可标识（NOTICES 不提供机器可读的 SPDX 标识）。
///
/// 只看开头一段：权威清单里单份正文可能几十 KB，许可身份声明总在开头。
String detectLicenseId(String text) {
  const headLimit = 4000;
  final t = (text.length > headLimit ? text.substring(0, headLimit) : text)
      .toLowerCase();
  if (t.contains('apache license') && t.contains('version 2.0')) {
    return 'Apache-2.0';
  }
  if (t.contains('mozilla public license')) {
    return t.contains('2.0') ? 'MPL-2.0' : 'MPL-1.1';
  }
  if (t.contains('gnu lesser general public license')) return 'LGPL';
  if (t.contains('gnu library general public license')) return 'LGPL';
  if (t.contains('gnu general public license')) return 'GPL';
  if (t.contains('redistribution and use in source and binary forms')) {
    // 三条款版必有「Neither the name …」这一条。
    return t.contains('neither the name') ? 'BSD-3-Clause' : 'BSD-2-Clause';
  }
  if (t.contains('permission is hereby granted, free of charge')) return 'MIT';
  if (t.contains('permission to use, copy, modify, and')) return 'ISC';
  if (t.contains('this is free and unencumbered software')) return 'Unlicense';
  if (t.contains('zlib license') || t.contains('altered source versions')) {
    return 'Zlib';
  }
  return kOssOtherLicense;
}

Future<Map<String, String>> _loadVersions() async {
  try {
    final raw = await rootBundle.loadString(kOssLockAssetKey);
    return parseLockVersions(raw);
  } catch (error) {
    debugPrint('OssLicenseService: pubspec.lock asset 不可用 ($error)');
    return const <String, String>{};
  }
}

/// 兜底超时：资产读取 / NOTICES 解析任何一步卡住时，页面必须能落到「失败 +
/// 重试」，而不是无限转圈。
Future<OssLicenseData> _collect() async {
  try {
    return await _collectInner().timeout(const Duration(seconds: 45));
  } on TimeoutException {
    throw StateError('收集开源许可超时：NOTICES 资产不可用？');
  }
}

Future<OssLicenseData> _collectInner() async {
  final versions = await _loadVersions();
  final grouped = <String, List<List<OssParagraph>>>{};
  Object? failure;

  try {
    final entries = await LicenseRegistry.licenses
        .timeout(const Duration(seconds: 30))
        .toList();
    for (final entry in entries) {
      final paragraphs = <OssParagraph>[
        for (final p in entry.paragraphs) OssParagraph(p.text, p.indent),
      ];
      if (paragraphs.isEmpty) continue;
      for (final name in entry.packages) {
        if (name.trim().isEmpty) continue;
        grouped.putIfAbsent(name, () => <List<OssParagraph>>[]).add(paragraphs);
      }
    }
  } catch (error) {
    failure = error;
  }

  // 一条都没读到且确有异常 —— 交给页面报错，而不是假装「没有依赖」。
  if (grouped.isEmpty && failure != null) {
    throw StateError('读取许可清单失败: $failure');
  }

  final packages = grouped.entries.map((e) {
    return OssPackage(
      name: e.key,
      version: versions[e.key],
      licenses: e.value,
      licenseIds: [
        for (final paragraphs in e.value)
          detectLicenseId(paragraphs.map((p) => p.text).join('\n')),
      ],
    );
  }).toList()..sort(
    (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
  );

  final histogram = <String, int>{};
  var totalLicenses = 0;
  for (final pkg in packages) {
    totalLicenses += pkg.licenseCount;
    for (final id in pkg.licenseIds.toSet()) {
      histogram[id] = (histogram[id] ?? 0) + 1;
    }
  }

  return OssLicenseData(
    packages: packages,
    totalLicenses: totalLicenses,
    licenseHistogram: Map.unmodifiable(histogram),
  );
}
