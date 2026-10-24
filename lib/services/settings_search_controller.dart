import 'package:flutter/foundation.dart';

/// NaviFlash 设置搜索目标（morph 组件的高亮定位协议）。
class SettingsSearchTarget {
  final int token;

  final String pageRoute;

  final String? optionKey;

  final String pageTitle;

  final String optionName;

  const SettingsSearchTarget({
    required this.token,
    required this.pageRoute,
    this.optionKey,
    required this.pageTitle,
    required this.optionName,
  });
}

/// 设置搜索控制器的最小桩：本项目没有设置搜索功能，永远空值。
class SettingsSearchController extends ValueNotifier<SettingsSearchTarget?> {
  SettingsSearchController._() : super(null);

  static final SettingsSearchController current = SettingsSearchController._();
}
