// lib/services/jump_list_service.dart
//
// Windows 跳转列表（任务栏右键 / 开始菜单长按图标那份菜单）的平台通道封装。
//
// 形态照 NaviFlash 的 `services/jump_list_service.dart`，差别在：
//   · NaviFlash 的「任务」三项是 C++ 写死的，这里改成 Dart 下发 —— 文案要跟着
//     应用的 l10n 走，不能让 Windows 端只有中文/英文两套硬编码；
//   · 分区两块：「任务」（AddUserTasks，小标题由 Windows 按系统语言画）
//     与「最近」（AppendCategory，标题由 Dart 给，内容是当前的上游组）。
//
// 动作回传两条路（时序很关键，见 init/consumeLaunchAction 的注释）：
//   · 冷启动：进程点跳转列表项新起，命令行带 --l2a-action=…，原生先暂存，
//     Dart 就绪后 consumeLaunchAction() 领一次；
//   · 热启动：已有实例在跑时，新进程把动作经 WM_COPYDATA 转给老实例，
//     原生直接 InvokeMethod('onAction') 推过来。
// 必须先注册 handler 再领冷启动参数，否则冷启动动作可能早于 handler 到达而丢。

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 跳转列表里的一条（[subtitle] 只给 Flutter 侧的原生对话框用；Windows
/// 跳转列表显示的是 name，subtitle 当 tooltip/描述）。
class JumpListItem {
  const JumpListItem({
    required this.name,
    required this.action,
    this.subtitle = '',
  });

  final String name;
  final String action;
  final String subtitle;

  Map<String, dynamic> toMap() => {
    'name': name,
    'action': action,
    'subtitle': subtitle,
  };
}

class JumpListService {
  JumpListService._();

  static final JumpListService instance = JumpListService._();

  static const MethodChannel _channel = MethodChannel(
    'com.memz2345.local2api/jumplist',
  );

  /// 只有 Windows 壳注册了这条通道（jumplist.cpp）。
  static bool get isSupported => !kIsWeb && Platform.isWindows;

  /// 热启动时原生推来的动作。
  void Function(String action)? onAction;

  bool _initialized = false;

  /// 通道叫不通（非 Windows 构建 / 老 runner 没这段 C++）时置 false，别反复撞。
  bool _available = isSupported;

  Future<void> init() async {
    if (!isSupported || _initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onAction') {
        final action = call.arguments;
        if (action is String && action.isNotEmpty) onAction?.call(action);
      }
    });
  }

  /// 冷启动暂存的动作：主动取一次（取到即清除）。
  Future<String?> consumeLaunchAction() async {
    if (!_available) return null;
    try {
      final raw = await _channel.invokeMethod<Object?>('consumeLaunchArgs');
      if (raw is Map) return raw['action'] as String?;
      return raw is String ? raw : null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      _available = false;
      return null;
    }
  }

  /// 整体重建跳转列表：任务区 + 「最近」类别。返回原生是否写成功
  /// （Windows 对写入频率有限流，失败时界面照常，只是菜单没更新）。
  Future<bool> update({
    required String recentTitle,
    required List<JumpListItem> tasks,
    required List<JumpListItem> recents,
  }) async {
    if (!_available) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('setJumpList', {
        'recentTitle': recentTitle,
        'tasks': [for (final t in tasks) t.toMap()],
        'recents': [for (final r in recents) r.toMap()],
      });
      return ok ?? false;
    } on PlatformException {
      _available = false;
      return false;
    } on MissingPluginException {
      _available = false;
      return false;
    }
  }

  Future<void> clear() async {
    if (!_available) return;
    try {
      await _channel.invokeMethod<bool>('clearJumpList');
    } on PlatformException {
      _available = false;
    } on MissingPluginException {
      _available = false;
    }
  }

  /// 测试用：把「通道不可用」的闸门重新打开。
  ///
  /// 单例的 `_available` 一旦被 MissingPluginException 关掉就再也不发请求，
  /// 同一进程里接着跑别的用例时会在「第二次没再调用通道」之外拿不到任何信号，
  /// 所以清完状态要能复原。生产代码不调它。
  @visibleForTesting
  void resetAvailableForTest() {
    _available = isSupported;
    _initialized = false;
    onAction = null;
    _channel.setMethodCallHandler(null);
  }
}
