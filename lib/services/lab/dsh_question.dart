// lib/services/lab/dsh_question.dart
//
// dsh 会话里「等用户回应」的那条提问（ask_user_question / 权限审批）。
//
// 抽成独立文件是为了避免 watcher（读会话）和 task center（通知）互相 import：
// watcher 把解析结果交给通知层，通知层直接用 callId / question id 调
// `userQuestions/answer` RPC。

/// ask_user_question 里的一条问题（一个批次可以有多条）。
class DshQuestionItem {
  const DshQuestionItem({
    required this.id,
    required this.text,
    required this.options,
  });

  final String id;
  final String text;
  final List<String> options;

  static DshQuestionItem? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final text = '${raw['text'] ?? ''}'.trim();
    final options = <String>[];
    final list = raw['options'];
    if (list is List) {
      for (final item in list) {
        final v = '$item'.trim();
        if (v.isNotEmpty) options.add(v);
      }
    }
    if (text.isEmpty && options.isEmpty) return null;
    return DshQuestionItem(
      id: '${raw['id'] ?? ''}',
      text: text,
      options: options,
    );
  }
}

/// dsh 在等用户回应的东西（模型提问 / 权限审批）。
class DshQuestion {
  const DshQuestion({
    required this.text,
    required this.options,
    this.id = '',
    this.callId = '',
    this.items = const <DshQuestionItem>[],
  });

  final String text;
  final List<String> options;

  /// 第一条问题的 id / 工具调用 id：直接回复要拿它们调 dsh RPC。
  final String id;
  final String callId;

  /// 整批问题；通知只展示第一条，其余按「跳过」回答。
  final List<DshQuestionItem> items;

  /// 能不能从通知直接送回去（审批类问题没有 callId，只能去 web）。
  bool get answerable => callId.isNotEmpty && items.isNotEmpty;

  static DshQuestion? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final text = '${raw['text'] ?? ''}'.trim();
    final options = <String>[];
    final list = raw['options'];
    if (list is List) {
      for (final item in list) {
        final v = '$item'.trim();
        if (v.isNotEmpty) options.add(v);
      }
    }
    final items = <DshQuestionItem>[];
    final rawItems = raw['items'];
    if (rawItems is List) {
      for (final item in rawItems) {
        final parsed = DshQuestionItem.tryParse(item);
        if (parsed != null) items.add(parsed);
      }
    }
    if (items.isEmpty && (text.isNotEmpty || options.isNotEmpty)) {
      items.add(
        DshQuestionItem(id: '${raw['id'] ?? ''}', text: text, options: options),
      );
    }
    if (text.isEmpty && options.isEmpty && items.isEmpty) return null;
    return DshQuestion(
      text: text.isNotEmpty ? text : items.first.text,
      options: options.isNotEmpty ? options : items.first.options,
      id: '${raw['id'] ?? ''}',
      callId: '${raw['callId'] ?? ''}',
      items: items,
    );
  }
}
