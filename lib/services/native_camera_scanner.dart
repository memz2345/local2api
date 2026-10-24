import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// 一颗物理/逻辑镜头（[Camera2Scanner] 报上来的）。
///
/// 厂商（vivo/OPPO 一类）会把辅助后置镜头从 `cameraIdList` 里摘走，
/// CameraX 因此选不到超广角；但 Camera2 按 id 直开是通的，所以这里连
/// `listed=false` 的镜头一起收。
class NativeCameraLens {
  const NativeCameraLens({
    required this.id,
    required this.facing,
    required this.eq35mm,
    required this.kind,
    required this.zoomMin,
    required this.zoomMax,
    required this.listed,
    required this.sensorOrientation,
    this.physicalIds = const [],
  });

  final String id;

  /// 0 = 前摄，1 = 后置（CameraCharacteristics.LENS_FACING_*）。
  final int facing;

  /// 35mm 等效焦距（算不出来是 -1）。
  final int eq35mm;

  /// wide / normal / zoom / front / unknown。
  final String kind;

  final double zoomMin;
  final double zoomMax;
  final bool listed;
  final int sensorOrientation;

  /// 逻辑多摄包含的物理镜头 id。
  final List<String> physicalIds;

  bool get isFront => facing == 0;
  bool get isWide => kind == 'wide';
  bool get isNormal => kind == 'normal';

  /// 镜头短标签：「广角 15mm」「广角 0.6x」「主摄 23mm」；
  /// zoomMin < 1 的逻辑多摄头（0.6x 起步）优先按 0.6x 标，别和主摄重名。
  String get label {
    if (isFront) return '前摄';
    if (zoomMin > 0.05 && zoomMin < 0.99) {
      return '广角 ${zoomMin.toStringAsFixed(1)}x';
    }
    final prefix = switch (kind) {
      'wide' => '广角',
      'zoom' => '长焦',
      _ => '主摄',
    };
    return eq35mm > 0 ? '$prefix ${eq35mm}mm' : '$prefix #$id';
  }

  static NativeCameraLens? from(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    return NativeCameraLens(
      id: '${map['id']}',
      facing: (map['facing'] as num?)?.toInt() ?? 1,
      eq35mm: (map['eq35mm'] as num?)?.toInt() ?? -1,
      kind: '${map['kind']}',
      zoomMin: (map['zoomMin'] as num?)?.toDouble() ?? 1,
      zoomMax: (map['zoomMax'] as num?)?.toDouble() ?? 1,
      listed: map['listed'] == true,
      sensorOrientation: (map['sensorOrientation'] as num?)?.toInt() ?? 0,
      physicalIds: [
        for (final p in (map['physicalIds'] as List?) ?? const []) '$p',
      ],
    );
  }
}

/// 一次 Camera2 会话的取景信息（供 Texture 渲染）。
class NativeCameraView {
  const NativeCameraView({
    required this.textureId,
    required this.width,
    required this.height,
    required this.rotation,
  });

  final int textureId;
  final int width;
  final int height;

  /// 画面要顺时针转多少度才是正的（0/90/180/270）。
  final int rotation;

  int get quarterTurns => ((rotation % 360) ~/ 90) % 4;
}

/// Camera2 直连扫码（Android 专用）。
///
/// 给扫码页兜底用：mobile_scanner（CameraX）够不着的隐藏广角镜头走这边。
/// 解码结果从 [barcodes] 广播出去。
class NativeCameraScanner {
  NativeCameraScanner._();

  static const MethodChannel _channel = MethodChannel(
    'com.memz2345.local2api/camera2',
  );

  static final StreamController<String> _barcodes =
      StreamController<String>.broadcast();

  /// 解出来的码（只有内容串，格式信息用不上）。
  static Stream<String> get barcodes => _barcodes.stream;

  static bool _handlerInstalled = false;

  static void _ensureHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'barcode') {
        final value = (call.arguments as Map?)?['value'];
        if (value is String && value.isNotEmpty) _barcodes.add(value);
      }
      return null;
    });
  }

  /// 枚举设备上的镜头（含被厂商藏起来的）。
  static Future<List<NativeCameraLens>> lenses() async {
    _ensureHandler();
    try {
      final raw = await _channel.invokeMethod<String>('lenses');
      if (raw == null || raw.isEmpty) return const [];
      final list = (jsonListDecode(raw) as List?) ?? const [];
      return [
        for (final item in list) NativeCameraLens.from(item),
      ].whereType<NativeCameraLens>().toList();
    } on PlatformException {
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// 开指定镜头；返回取景信息（textureId 等）。
  static Future<NativeCameraView?> start(String cameraId) async {
    _ensureHandler();
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>('start', {
        'cameraId': cameraId,
      });
      if (res == null) return null;
      final map = Map<String, dynamic>.from(res);
      return NativeCameraView(
        textureId: (map['textureId'] as num?)?.toInt() ?? -1,
        width: (map['width'] as num?)?.toInt() ?? 0,
        height: (map['height'] as num?)?.toInt() ?? 0,
        rotation: (map['rotation'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> setZoom(double ratio) =>
      _channel.invokeMethod<void>('setZoom', {'ratio': ratio}).catchError(
        (_) {},
      );

  static Future<void> setTorch(bool on) =>
      _channel.invokeMethod<void>('torch', {'on': on}).catchError((_) {});

  static Future<void> stop() =>
      _channel.invokeMethod<void>('stop').catchError((_) {});
}

/// 极简 JSON 数组解析（免得为这一个小用途拉 dart:convert 之外的依赖）。
Object? jsonListDecode(String raw) {
  // 原生侧已经用 org.json 编好了；这里直接复用 dart:convert 更稳。
  return const JsonDecoder().convert(raw);
}
