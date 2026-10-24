// lib/services/lab/dsh_windows_toast.dart
//
// dsh 的 Windows 系统通知桥（Dart 侧）。原生实现见
// `windows/runner/dsh_toast.cpp`（WinRT ToastGeneric）。
//
// 和安卓的 `android_notifications.dart` 是同构的两条车道：
//   · 进度 = 一条带 ProgressBar 的常驻 Toast，按 tag+group 原地替换；
//   · 询问 = 正文 + <input type="text"> + 发送/跳过按钮；
//   · 选项 = 正文里列 1/2/3，按钮映射到同一组选项；输入框里打 1/2/3
//     由 [resolveOptionReply] 映射成预置选项，其他文字当自定义回答；
//   · 完成 = 标题（会话标题）+ 正文（agent 输出）。
//
// 只有 Windows 注册了这条通道；其它平台 [isSupported] 为 false，
// 调用方不用分支。

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Toast 上的一个按钮。
class DshWindowsToastButton {
  const DshWindowsToastButton({
    required this.key,
    required this.label,
    this.value = '',
    this.submit = false,
  });

  /// 回传给 Dart 的动作名（`reply` / `skip` / `option` / `open`…）。
  final String key;

  final String label;

  /// 选项序号（`1`、`2`…），自由文本走输入框。
  final String value;

  /// true = 这个按钮挨着输入框（hint-inputId），点击时带上输入内容。
  final bool submit;

  Map<String, Object?> toMap() => <String, Object?>{
    'key': key,
    'label': label,
    if (value.isNotEmpty) 'value': value,
    'submit': submit,
  };
}

/// 一条 Windows Toast 的描述。
class DshWindowsToastSpec {
  const DshWindowsToastSpec({
    required this.tag,
    this.group = 'dsh',
    required this.title,
    this.body = '',
    this.detail = '',
    this.input = false,
    this.inputPlaceholder = '',
    this.hasProgress = false,
    this.progress = 0,
    this.progressText = '',
    this.silent = false,
    this.longDuration = false,
    this.buttons = const <DshWindowsToastButton>[],
    this.launchKey = 'open',
  });

  /// 同一 tag+group 再次 show = 原地替换（进度条 Stepper 靠它）。
  final String tag;

  final String group;

  final String title;
  final String body;
  final String detail;

  /// 是否带输入框（询问 / 选项）。
  final bool input;
  final String inputPlaceholder;

  /// 是否带进度条（0..1）。
  final bool hasProgress;
  final double progress;
  final String progressText;

  /// 更新同一条通知时不响铃。
  final bool silent;

  /// 询问 / 选项用 long duration（25s），留给用户输入的时间。
  final bool longDuration;

  final List<DshWindowsToastButton> buttons;

  /// 点正文时回传的动作名。
  final String launchKey;

  Map<String, Object?> toMap() => <String, Object?>{
    'tag': tag,
    'group': group,
    'title': title,
    'body': body,
    'detail': detail,
    'input': input,
    'inputPlaceholder': inputPlaceholder,
    'progress': hasProgress,
    'progressValue': progress,
    'progressText': progressText,
    'silent': silent,
    'longDuration': longDuration,
    'buttons': [for (final button in buttons) button.toMap()],
    'launchKey': launchKey,
  };
}

/// Toast 回传的事件。
class DshWindowsToastEvent {
  const DshWindowsToastEvent({
    required this.type,
    required this.tag,
    this.group = 'dsh',
    this.key,
    this.value,
    this.text,
    this.reason,
  });

  /// `reply`（带输入文字）/ `action`（只点了按钮）/ `dismissed`。
  final String type;

  final String tag;
  final String group;

  /// 按钮动作名。
  final String? key;

  /// 选项序号。
  final String? value;

  /// 输入框里的文字。
  final String? text;

  /// 关闭原因：`user` / `app` / `timeout`。
  final String? reason;

  bool get isReply => type == 'reply';
  bool get isDismissed => type == 'dismissed';

  static DshWindowsToastEvent? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final type = raw['type'];
    if (type is! String) return null;
    return DshWindowsToastEvent(
      type: type,
      tag: '${raw['tag'] ?? ''}',
      group: '${raw['group'] ?? 'dsh'}',
      key: raw['key'] is String ? raw['key'] as String : null,
      value: raw['value'] is String ? raw['value'] as String : null,
      text: raw['text'] is String ? raw['text'] as String : null,
      reason: raw['reason'] is String ? raw['reason'] as String : null,
    );
  }
}

/// 把输入框内容映射成回答：`1`..`N` 取预置选项，其余原样。
///
/// 这是「选项 toast」的核心语义，抽成纯函数方便单测。
String? resolveOptionReply(String raw, List<String> options) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  if (options.isNotEmpty) {
    final index = int.tryParse(text);
    if (index != null && index >= 1 && index <= options.length) {
      return options[index - 1];
    }
  }
  return text;
}

/// 解析 Toast 按钮的 arguments：
/// `--l2a-action=dsh_toast;k=option;tag=...;group=dsh;v=1`
///
/// 进程不在时系统会用快捷方式重新拉起本 exe，动作经单实例 WM_COPYDATA
/// 转给正在运行的实例；这时没有 Toast 对象，只能靠这段字符串兜底。
({String key, String tag, String group, String value}) parseToastAction(
  String raw,
) {
  var body = raw;
  const prefix = '--l2a-action=';
  if (body.startsWith(prefix)) body = body.substring(prefix.length);
  var key = '';
  var tag = '';
  var group = 'dsh';
  var value = '';
  for (final part in body.split(';')) {
    final eq = part.indexOf('=');
    if (eq <= 0) continue;
    final name = part.substring(0, eq);
    final text = part.substring(eq + 1);
    switch (name) {
      case 'k':
        key = text;
      case 'tag':
        tag = text;
      case 'group':
        group = text;
      case 'v':
        value = text;
    }
  }
  return (key: key, tag: tag, group: group, value: value);
}

class DshWindowsToast {
  DshWindowsToast._();

  static final DshWindowsToast instance = DshWindowsToast._();

  static const MethodChannel _channel = MethodChannel(
    'com.memz2345.local2api/dsh_toast',
  );

  static bool get isSupported => !kIsWeb && Platform.isWindows;

  /// 通道叫不通（老 runner / 测试壳）时置 false，别反复撞。
  bool _available = isSupported;
  bool _initialized = false;

  void Function(DshWindowsToastEvent event)? onEvent;

  bool get available => _available;

  /// 单元测试（纯 Dart，没有 WidgetsBinding）里不能碰平台通道。
  bool get _bindingReady {
    try {
      // ignore: unnecessary_statements
      ServicesBinding.instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 注册原生事件回调。重复调用安全。
  Future<void> init() async {
    if (!isSupported || _initialized) return;
    _initialized = true;
    if (!_bindingReady) {
      _available = false;
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onEvent') return null;
      final event = DshWindowsToastEvent.fromMap(call.arguments);
      if (event != null) onEvent?.call(event);
      return null;
    });
    try {
      _available = await _channel.invokeMethod<bool>('ping') ?? false;
    } on MissingPluginException {
      _available = false;
    } on PlatformException {
      _available = false;
    }
    // 原生自测钩子：只认环境变量，正式用户不会碰到。
    final testMode = Platform.environment['L2A_DSH_TOAST_TEST'];
    if (_available && kDebugMode && testMode != null && testMode.isNotEmpty) {
      try {
        final setting = await _channel.invokeMethod<String>('setting');
        debugPrint('[dsh-toast-test] notifier setting=$setting');
      } catch (e) {
        debugPrint('[dsh-toast-test] setting failed: $e');
      }
      onEvent ??= (event) {
        debugPrint(
          '[dsh-toast-test] type=${event.type} tag=${event.tag} '
          'key=${event.key} value=${event.value} text=${event.text} '
          'reason=${event.reason}',
        );
      };
      Future<void>.delayed(const Duration(seconds: 4), () async {
        if (testMode == 'simple') {
          final shown = await show(
            const DshWindowsToastSpec(
              tag: 'dsh-simple',
              title: 'Local2API',
              body: 'Windows 系统通知测试',
              longDuration: true,
            ),
          );
          debugPrint('[dsh-toast-test] simple shown=$shown');
        } else if (testMode == 'progress') {
          final shown = await showProgress(
            tag: 'dsh-progress-test',
            title: '测试任务 · 执行',
            body: '已完成 2/4',
            detail: '✓ 准备\n▸ 执行\n· 收尾',
            progress: 0.5,
            progressText: '2/4',
            silent: false,
          );
          debugPrint('[dsh-toast-test] progress shown=$shown');
        } else {
          final shown = await showAsk(
            tag: 'dsh-self-test',
            title: 'Local2API · dsh',
            question: '选择一个方案，或直接输入自定义回答',
            options: const ['准备', '执行', '收尾'],
            inputPlaceholder: '输入 1-3 或自定义内容',
            submitLabel: '发送',
            skipLabel: '跳过',
            optionsHint: '输入 1/2/3 选择预置项',
          );
          debugPrint('[dsh-toast-test] ask shown=$shown');
        }
        await Future<void>.delayed(const Duration(seconds: 1));
        try {
          final history = await _channel.invokeMethod<List<Object?>>('history');
          debugPrint('[dsh-toast-test] history=$history');
        } catch (e) {
          debugPrint('[dsh-toast-test] history failed: $e');
        }
      });
    }
  }

  Future<bool> show(DshWindowsToastSpec spec) async {
    if (!_available || !_bindingReady) return false;
    try {
      return await _channel.invokeMethod<bool>('show', spec.toMap()) ?? false;
    } on MissingPluginException {
      _available = false;
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> cancel({required String tag, String group = 'dsh'}) async {
    if (!_available || !_bindingReady) return;
    try {
      await _channel.invokeMethod<void>('cancel', {
        'tag': tag,
        'group': group,
      });
    } on MissingPluginException {
      _available = false;
    } on PlatformException {
      // 通知没撤掉不影响业务；下一次同 tag 会覆盖。
    }
  }

  Future<void> cancelGroup({String group = 'dsh'}) async {
    if (!_available || !_bindingReady) return;
    try {
      await _channel.invokeMethod<void>('cancelGroup', {'group': group});
    } on MissingPluginException {
      _available = false;
    } on PlatformException {
      // 同上。
    }
  }

  /// 原生侧的 Show / Update 计数（集成测试用）。
  ///
  /// `show` = 会弹横幅的发布，`update` = 静默原地替换。修复「每调一次
  /// 工具弹一条」后，正常任务里 update 应远多于 show。
  @visibleForTesting
  Future<Map<String, int>> stats() async {
    if (!_available || !_bindingReady) return const <String, int>{};
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('stats');
      if (raw == null) return const <String, int>{};
      return <String, int>{
        for (final entry in raw.entries)
          if (entry.key is String && entry.value is int)
            entry.key as String: entry.value as int,
      };
    } on MissingPluginException {
      _available = false;
      return const <String, int>{};
    } on PlatformException {
      return const <String, int>{};
    }
  }

  /// 询问 / 选项 Toast：正文 + 输入框 + 选项按钮 + 发送 / 跳过。
  ///
  /// [optionsHint] 是「输入 1/2/3 选择…」那行说明，由 UI 层按语言注入。
  Future<bool> showAsk({
    required String tag,
    required String title,
    required String question,
    List<String> options = const <String>[],
    String inputPlaceholder = '',
    String submitLabel = 'Reply',
    String skipLabel = 'Skip',
    String optionsHint = '',
    String group = 'dsh',
  }) async {
    final detail = StringBuffer();
    if (options.isNotEmpty) {
      for (var i = 0; i < options.length; i++) {
        detail.writeln('${i + 1}. ${options[i]}');
      }
    }
    if (optionsHint.isNotEmpty) {
      if (detail.isNotEmpty) detail.writeln();
      detail.write(optionsHint);
    }
    final buttons = <DshWindowsToastButton>[
      for (var i = 0; i < options.length && i < 3; i++)
        DshWindowsToastButton(
          key: 'option',
          label: '${i + 1}',
          value: '${i + 1}',
        ),
      DshWindowsToastButton(
        key: 'reply',
        label: submitLabel,
        submit: true,
      ),
      if (skipLabel.isNotEmpty)
        DshWindowsToastButton(key: 'skip', label: skipLabel),
    ];
    return show(
      DshWindowsToastSpec(
        tag: tag,
        group: group,
        title: title,
        body: question,
        detail: detail.toString().trimRight(),
        input: true,
        inputPlaceholder: inputPlaceholder,
        silent: false,
        longDuration: true,
        buttons: buttons,
      ),
    );
  }

  /// 进度 / Stepper Toast（同一 tag 原地更新）。
  Future<bool> showProgress({
    required String tag,
    required String title,
    String body = '',
    String detail = '',
    double progress = 0,
    String progressText = '',
    bool silent = true,
    String group = 'dsh',
  }) {
    return show(
      DshWindowsToastSpec(
        tag: tag,
        group: group,
        title: title,
        body: body,
        detail: detail,
        hasProgress: true,
        progress: progress,
        progressText: progressText,
        silent: silent,
      ),
    );
  }

  /// 完成 / 失败 Toast：标题 = 会话标题，正文 = agent 输出。
  Future<bool> showDone({
    required String tag,
    required String title,
    required String text,
    String detail = '',
    bool failed = false,
    String openLabel = 'Open',
    String group = 'dsh',
  }) {
    return show(
      DshWindowsToastSpec(
        tag: tag,
        group: group,
        title: title,
        body: text,
        detail: detail,
        silent: false,
        launchKey: 'open',
        buttons: [
          if (openLabel.isNotEmpty)
            DshWindowsToastButton(key: 'open', label: openLabel),
        ],
      ),
    );
  }
}
