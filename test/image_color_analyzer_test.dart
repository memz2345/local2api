import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/image_color_analyzer.dart';

int _crc32(List<int> data) {
  final table = List<int>.generate(256, (i) {
    var c = i;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) == 1 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    }
    return c;
  });
  var crc = 0xFFFFFFFF;
  for (final b in data) {
    crc = table[(crc ^ b) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// 生成纯色 PNG（测试取色算法用）。
Uint8List solidPng(int w, int h, List<int> rgb) {
  final raw = <int>[];
  for (var y = 0; y < h; y++) {
    raw.add(0);
    for (var x = 0; x < w; x++) {
      raw.addAll(rgb);
    }
  }
  List<int> chunk(String type, List<int> data) {
    final body = [...type.codeUnits, ...data];
    final crc = _crc32(body);
    final len = data.length;
    return [
      (len >>> 24) & 0xff,
      (len >>> 16) & 0xff,
      (len >>> 8) & 0xff,
      len & 0xff,
      ...body,
      (crc >>> 24) & 0xff,
      (crc >>> 16) & 0xff,
      (crc >>> 8) & 0xff,
      crc & 0xff,
    ];
  }

  final ihdr = [
    (w >>> 24) & 0xff,
    (w >>> 16) & 0xff,
    (w >>> 8) & 0xff,
    w & 0xff,
    (h >>> 24) & 0xff,
    (h >>> 16) & 0xff,
    (h >>> 8) & 0xff,
    h & 0xff,
    8,
    2,
    0,
    0,
    0,
  ];
  final idat = ZLibEncoder().convert(raw);
  final bytes = <int>[
    ...[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
    ...chunk('IHDR', ihdr),
    ...chunk('IDAT', idat),
    ...chunk('IEND', []),
  ];
  return Uint8List.fromList(bytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('纯绿色图片取色结果为绿色系', () async {
    final color = await analyzeImageColor(solidPng(32, 32, [40, 180, 90]));
    expect(color.g, greaterThan(color.r));
    expect(color.g, greaterThan(color.b));
    // 饱和度提升后绿色应保持较高的 green 通道
    expect((color.g * 255).round(), greaterThan(100));
  });

  test('近白图片回退到全像素平均', () async {
    final color = await analyzeImageColor(solidPng(32, 32, [250, 250, 250]));
    // 接近白的像素被过滤，回退平均路径后仍是白色系
    expect((color.r * 255).round(), greaterThan(200));
    expect((color.g * 255).round(), greaterThan(200));
    expect((color.b * 255).round(), greaterThan(200));
  });

  test('损坏数据返回兜底色', () async {
    final color = await analyzeImageColor(Uint8List.fromList([1, 2, 3]));
    expect(color, Colors.deepPurple);
  });
}
