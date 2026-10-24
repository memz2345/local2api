// lib/services/android_notifications.dart
//
// Android 通知桥（原生实现见
// `android/app/src/main/kotlin/.../NotificationHost.kt`）。
//
// 分两层：
//   1. **Android 16（API 36）「以进度为中心的通知」** —— `Notification.ProgressStyle`
//      把一段任务画成「分段 + 里程碑点」的进度条，还能申请升级成系统的
//      「实时更新」（置顶通知抽屉 / 锁屏 / 状态栏 chip）。升级是**显式申请**
//      才有：少一条条件系统就静默降级成普通通知，所以 `show` 返回里带
//      `promoted`（这次到底升没升），方便排查。
//   2. **带回复的通知** —— 用户在通知里直接打字（RemoteInput），文字经广播
//      回到 Dart。应用被杀时回复先存在原生侧，下次 `drainPending()` 补发。
//
// 非 Android 平台全部走空实现（返回 false / null），调用方不用分支。

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 通知上的一个按钮。
class AndroidNotificationAction {
  const AndroidNotificationAction({
    required this.key,
    required this.title,
    this.reply = false,
    this.replyLabel,
  });

  /// 回传给 Dart 的标识（`key=null` 时按 title 匹配）。
  final String key;

  final String title;

  /// true = 这条按钮带输入框（RemoteInput），用户打字后回 `reply` 事件。
  final bool reply;

  /// 输入框的标签（RemoteInput 没有 placeholder 这个概念）。
  final String? replyLabel;

  Map<String, Object?> toMap() => <String, Object?>{
    'key': key,
    'title': title,
    'reply': reply,
    if (replyLabel != null) 'replyLabel': replyLabel,
  };
}

/// 一条通知的描述。
class AndroidNotificationSpec {
  const AndroidNotificationSpec({
    required this.id,
    required this.title,
    this.text = '',
    this.subText,
    this.bigText,
    this.ongoing = false,
    this.promoted = false,
    this.silent = false,
    this.alertOnce = true,
    this.autoCancel,
    this.showWhen = false,
    this.route,
    this.result = false,
    this.progressMax = 0,
    this.progress = 0,
    this.indeterminate = false,
    this.styledByProgress = true,
    this.segments = const <AndroidProgressSegment>[],
    this.points = const <AndroidProgressPoint>[],
    this.actions = const <AndroidNotificationAction>[],
  });

  /// 通知 id：同一个 id 再次 show = 更新（不会叠出第二条）。
  final int id;

  final String title;
  final String text;

  /// 标题下面的小字（副文本）。
  final String? subText;

  /// 展开后的大段文字。
  final String? bigText;

  /// 常驻通知（不可清除）。实时更新必须是 ongoing。
  final bool ongoing;

  /// 申请升级成系统「实时更新」（API 36+，且必须 ongoing）。
  final bool promoted;

  final bool silent;

  /// 更新同一条通知时不再响铃/震动（连续刷新进度时必须开）。
  final bool alertOnce;

  final bool? autoCancel;
  final bool showWhen;

  /// 点击通知时带回的路由（Dart 侧 `getLaunchRoute()` 取）。
  final String? route;

  /// true = 走「结果」渠道（会响铃、可清除）；false = 走「任务」渠道。
  final bool result;

  final int progressMax;
  final int progress;
  final bool indeterminate;

  /// 整个通知卡片是否以进度条为主视觉（false 时更突出文字）。
  final bool styledByProgress;

  final List<AndroidProgressSegment> segments;
  final List<AndroidProgressPoint> points;
  final List<AndroidNotificationAction> actions;

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'title': title,
    'text': text,
    if (subText != null) 'subText': subText,
    if (bigText != null) 'bigText': bigText,
    'ongoing': ongoing,
    'promoted': promoted,
    'silent': silent,
    'alertOnce': alertOnce,
    if (autoCancel != null) 'autoCancel': autoCancel,
    'showWhen': showWhen,
    if (route != null) 'route': route,
    'result': result,
    'progressMax': progressMax,
    'progress': progress,
    'indeterminate': indeterminate,
    'styledByProgress': styledByProgress,
    'segments': [for (final s in segments) s.toMap()],
    'points': [for (final p in points) p.toMap()],
    'actions': [for (final a in actions) a.toMap()],
  };
}

/// ProgressStyle 的一段（长度 + 颜色）。总进度 = 各段长度之和。
class AndroidProgressSegment {
  const AndroidProgressSegment(this.length, {this.color});

  final int length;

  /// ARGB（如 `0xFF34A853`）。不给就是系统默认色。
  final int? color;

  Map<String, Object?> toMap() => <String, Object?>{
    'length': length,
    if (color != null) 'color': color,
  };
}

/// ProgressStyle 的里程碑点（位置 + 颜色）。
class AndroidProgressPoint {
  const AndroidProgressPoint(this.position, {this.color});

  final int position;
  final int? color;

  Map<String, Object?> toMap() => <String, Object?>{
    'position': position,
    if (color != null) 'color': color,
  };
}

/// 通知回传的事件（按钮点击 / 直接回复 / 被清除）。
class AndroidNotificationEvent {
  const AndroidNotificationEvent({
    required this.type,
    required this.id,
    this.key,
    this.text,
    this.route,
  });

  /// `reply` / `action` / `dismiss`。
  final String type;
  final int id;
  final String? key;

  /// 用户在通知里输入的文字（type=reply 时非空）。
  final String? text;
  final String? route;

  bool get isReply => type == 'reply';

  static AndroidNotificationEvent? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final type = raw['type'];
    if (type is! String) return null;
    return AndroidNotificationEvent(
      type: type,
      id: (raw['id'] as num?)?.toInt() ?? 0,
      key: raw['key'] is String ? raw['key'] as String : null,
      text: raw['text'] is String ? raw['text'] as String : null,
      route: raw['route'] is String ? raw['route'] as String : null,
    );
  }
}

/// 分段进度条常用配色（与实验室任务状态一一对应）。
abstract final class AndroidProgressColors {
  /// 未开始：中性灰。
  static const int pending = 0xFF8A8F98;

  /// 进行中：品牌蓝。
  static const int active = 0xFF4C6FFF;

  /// 已完成：绿。
  static const int done = 0xFF34A853;

  /// 失败：红。
  static const int failed = 0xFFE5484D;
}

class AndroidNotifications {
  AndroidNotifications._();

  static const MethodChannel _channel = MethodChannel(
    'com.memz2345.local2api/notifications',
  );
  static const MethodChannel _events = MethodChannel(
    'com.memz2345.local2api/notifications_events',
  );

  static void Function(AndroidNotificationEvent event)? onEvent;

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// 注册事件回调，并把原生侧攒下的（应用被杀期间的）事件补发一遍。
  static Future<void> attach(
    void Function(AndroidNotificationEvent event)? handler,
  ) async {
    onEvent = handler;
    if (handler == null || !isSupported) return;
    _events.setMethodCallHandler((call) async {
      if (call.method != 'onEvent') return null;
      final event = AndroidNotificationEvent.fromMap(call.arguments);
      if (event != null) handler(event);
      return null;
    });
    final pending = await drainPending();
    for (final event in pending) {
      handler(event);
    }
  }

  static Future<bool> hasPermission() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 申请通知权限（Android 13+）。13 以下没权限说明用户在设置里关了 → 跳设置页。
  static Future<bool> requestPermission() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 系统允许本应用发「实时更新」吗（API 36+ 且用户没在设置里关掉）。
  static Future<bool> canPostPromoted() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('canPostPromoted') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 发出 / 更新一条通知。
  static Future<NotificationPostResult> show(AndroidNotificationSpec spec) async {
    if (!isSupported) return const NotificationPostResult(posted: false);
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'show',
        spec.toMap(),
      );
      return NotificationPostResult(
        posted: raw?['posted'] == true,
        promoted: raw?['promoted'] == true,
      );
    } on MissingPluginException {
      return const NotificationPostResult(posted: false);
    } on PlatformException {
      return const NotificationPostResult(posted: false);
    }
  }

  static Future<void> cancel(int id) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('cancel', {'id': id});
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static Future<void> cancelAll() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('cancelAll');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  /// 取走原生侧攒下的事件（应用被杀期间用户在通知里的回复等）。
  static Future<List<AndroidNotificationEvent>> drainPending() async {
    if (!isSupported) return const <AndroidNotificationEvent>[];
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('drainPending');
      if (raw == null) return const <AndroidNotificationEvent>[];
      return raw
          .map(AndroidNotificationEvent.fromMap)
          .whereType<AndroidNotificationEvent>()
          .toList(growable: false);
    } on MissingPluginException {
      return const <AndroidNotificationEvent>[];
    } on PlatformException {
      return const <AndroidNotificationEvent>[];
    }
  }

  /// 是否已经忽略电池优化（后台长时间跑 node/dsh 的前提）。
  static Future<bool?> isIgnoringBatteryOptimizations() async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// 弹系统的「允许后台运行？」对话框；已经忽略时直接返回 true。
  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'requestIgnoreBatteryOptimizations',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> openBatteryOptimizationSettings() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('openBatteryOptimizationSettings');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static Future<void> openNotificationSettings() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('openNotificationSettings');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  /// 通知把应用拉起来时带的路由（冷启动也取得到）。
  static Future<String?> getLaunchRoute() async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('getLaunchRoute');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}

/// `show` 的结果。
class NotificationPostResult {
  const NotificationPostResult({
    required this.posted,
    this.promoted = false,
  });

  /// 通知到底发出去了吗（没权限 / 原生异常 = false）。
  final bool posted;

  /// 系统有没有把它升级成「实时更新」（置顶 + 锁屏 + 状态栏 chip）。
  final bool promoted;
}
