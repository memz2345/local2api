// lib/services/lab/lab_gate.dart
//
// 实验室的「手动可见性」开关。
//
// 实验室属于进阶功能（要在本机装 Node、跑本地服务），默认不在设置里露出；
// 用户在设置页把开关拨开后，入口才显示出来。状态就一个 bool，收在这个
// 单例里：设置页（Material / miuix 两套）只是渲染 + 拨它。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LabGate extends ChangeNotifier {
  LabGate._();

  static final LabGate instance = LabGate._();

  static const String _prefVisible = 'lab.visible';

  SharedPreferences? _prefs;
  bool _loaded = false;
  bool _visible = false;

  bool get visible => _visible;
  bool get loaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    _prefs = await SharedPreferences.getInstance();
    _visible = _prefs!.getBool(_prefVisible) ?? false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setVisible(bool value) async {
    if (_loaded && value == _visible) return;
    _visible = value;
    notifyListeners();
    await (_prefs ??= await SharedPreferences.getInstance())
        .setBool(_prefVisible, value);
  }

  // ---- 测试钩子（单例跨用例共享状态，需要能重置） ----

  @visibleForTesting
  void setVisibleForTest(bool value) => _visible = value;

  @visibleForTesting
  void resetLoadedForTest() {
    _loaded = false;
    _prefs = null;
  }
}
