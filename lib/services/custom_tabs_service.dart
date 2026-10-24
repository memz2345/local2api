// lib/services/custom_tabs_service.dart
//
// Chrome Custom Tabs 桥（Android）。
//
// 为什么不用 url_launcher：`LaunchMode.externalApplication` 走的是
// `ACTION_VIEW`，系统默认浏览器如果是 WebView 壳或性能差的浏览器，网页
// （SillyTavern / dsh web 这种重前端）体验很差；Custom Tabs 能把链接交给
// 用户装的 Chromium 系浏览器（Chrome / Edge / Brave / 三星浏览器…），
// 复用它的内核、Cookie 与渲染性能，且视觉上仍是「应用内的一个页面」
// （TiebaLite 同款做法）。
//
// 原生实现在 `android/app/src/main/kotlin/.../CustomTabsHost.kt`；这个类
// 只做「有没有 / 有哪几个 / 打开」三件事，失败一律返回 false / 空，让调用
// 方回退到系统浏览器。

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 一个支持 Custom Tabs 的浏览器。
class CustomTabsBrowser {
  const CustomTabsBrowser({
    required this.packageName,
    required this.label,
    this.isDefault = false,
  });

  final String packageName;
  final String label;

  /// 是否是系统当前的默认 Custom Tabs 提供者（`CustomTabsClient.getPackageName`）。
  final bool isDefault;

  static CustomTabsBrowser? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final pkg = raw['packageName'];
    if (pkg is! String || pkg.isEmpty) return null;
    final label = raw['label'];
    return CustomTabsBrowser(
      packageName: pkg,
      label: label is String && label.trim().isNotEmpty ? label.trim() : pkg,
      isDefault: raw['isDefault'] == true,
    );
  }
}

class CustomTabsService {
  CustomTabsService._();

  static const MethodChannel _channel = MethodChannel(
    'com.memz2345.local2api/custom_tabs',
  );

  /// 只有 Android 有 Custom Tabs（iOS 的 SFSafariViewController 是另一套，不在此列）。
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// 当前设备有没有能接 Custom Tabs 的浏览器。
  static Future<bool> isAvailable() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 列出装了 Custom Tabs 服务的浏览器（默认那家排最前）。
  static Future<List<CustomTabsBrowser>> browsers() async {
    if (!isSupported) return const [];
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('listBrowsers');
      if (raw == null) return const [];
      return raw
          .map(CustomTabsBrowser.fromMap)
          .whereType<CustomTabsBrowser>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// 打开链接。返回 false = 没打开（调用方回退系统浏览器）。
  ///
  /// [packageName] 为空时交给系统的默认 Custom Tabs 提供者；
  /// [toolbarColor] 是地址栏底色（这里传应用当前配色，视觉上连得上）。
  static Future<bool> open(
    String url, {
    String? packageName,
    int? toolbarColor,
  }) async {
    if (!isSupported || url.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('open', {
            'url': url,
            'package': packageName,
            'toolbarColor': toolbarColor,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
