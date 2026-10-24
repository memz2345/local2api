/// 峰谷时段策略：给一个或多个对外模型套「星期 + 小时」的可用窗口。
///
/// 目标是**一组对外模型名**。历史配置里那种「模型组」规则（按配置档案 id 匹配）
/// 也一并收进 [ScheduleRule.targets] —— 判定时既比模型名也比档案 id，
/// 所以老配置照样生效，只是新 UI 里不再单独暴露「模型组」这个选项
/// （在上游页把该上游的模型全选，就等于以前给整个组套策略）。
enum ScheduleMode {
  /// 正向：只在命中窗口内放行，窗口外一律拒绝。
  allow,

  /// 反向：命中窗口内拒绝，其余时间放行。
  deny,
}

/// 一条峰谷策略。
///
/// [startHour] 含、[endHour] 不含（与 `usageStats.query` 的闭区间口径错开，
/// 因为这里是小时槽而不是时间轴：23-24 表示 23 点这一整小时）。
/// `startHour > endHour` 表示跨天（如 22-6 = 晚 22 点到次日早 6 点）。
/// [weekdays] 用 `DateTime.weekday`（1=周一 … 7=周日），空 = 每天。
class ScheduleRule {
  String id;

  /// 作用对象（对外模型名，或历史数据里的配置档案 id）。去重保序，空串会被丢掉。
  List<String> targets;

  ScheduleMode mode;

  /// 1=周一 … 7=周日；空 = 不限星期。
  List<int> weekdays;

  int startHour;
  int endHour;

  /// 关掉 = 整条不参与判定（临时停用，不删配置）。
  bool enabled;

  ScheduleRule({
    required this.id,
    required List<String> targets,
    this.mode = ScheduleMode.allow,
    List<int>? weekdays,
    this.startHour = 0,
    this.endHour = 24,
    this.enabled = true,
  }) : targets = _cleanTargets(targets),
       weekdays = weekdays == null || weekdays.isEmpty
           ? const [1, 2, 3, 4, 5, 6, 7]
           : List<int>.unmodifiable(
               [
                 for (final d in weekdays)
                   if (d >= 1 && d <= 7) d,
               ],
             );

  static List<String> _cleanTargets(List<String> raw) {
    final out = <String>[];
    for (final t in raw) {
      final s = t.trim();
      if (s.isNotEmpty && !out.contains(s)) out.add(s);
    }
    return List<String>.unmodifiable(out);
  }

  /// 当前时刻是否落在这条策略的窗口里（不看 [mode]，只看「命中」）。
  bool matches(DateTime now) {
    if (weekdays.isNotEmpty && !weekdays.contains(now.weekday)) return false;
    final h = now.hour;
    return startHour <= endHour
        ? (h >= startHour && h < endHour)
        : (h >= startHour || h < endHour);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'targets': targets,
    'mode': mode.name,
    'weekdays': weekdays,
    'startHour': startHour,
    'endHour': endHour,
    'enabled': enabled,
  };

  factory ScheduleRule.fromJson(Map<String, dynamic> j) {
    final start = ((j['startHour'] as num?)?.toInt() ?? 0).clamp(0, 23);
    final end = ((j['endHour'] as num?)?.toInt() ?? 24).clamp(0, 24);
    // 新格式：targets 数组；老格式：单个 target（scope 已经无所谓了，
    // 不管是 model 还是 group，判定时都只是拿字符串去比对）。
    final rawTargets = j['targets'];
    final legacy = (j['target'] as String?) ?? '';
    return ScheduleRule(
      id: (j['id'] as String?) ?? '',
      targets: rawTargets is List
          ? [for (final t in rawTargets) '$t']
          : [if (legacy.trim().isNotEmpty) legacy],
      mode: (j['mode'] as String?) == 'deny'
          ? ScheduleMode.deny
          : ScheduleMode.allow,
      weekdays: [
        for (final d in (j['weekdays'] as List? ?? const []))
          ((d as num?)?.toInt() ?? 0),
      ],
      startHour: start,
      // 只兜「读到 0」这种缺省值（0-0 没有意义，放宽成整天）；
      // start > end 是合法的跨天窗口（如 22-6），必须原样保留。
      endHour: end == 0 ? 24 : end,
      enabled: (j['enabled'] as bool?) ?? true,
    );
  }
}

/// 判定结果：[allowed] 为 false 时 [reason] 是给客户端看的拒绝理由。
class ScheduleDecision {
  final bool allowed;
  final String reason;

  const ScheduleDecision._(this.allowed, this.reason);

  static const ScheduleDecision allow = ScheduleDecision._(true, '');

  factory ScheduleDecision.deny(String reason) =>
      ScheduleDecision._(false, reason);
}

/// 纯函数判定入口：模型名 + 所属模型组在某个时刻能不能用。
///
/// 规则顺序即优先级（先命中先生效）：
/// 1. 命中一条 [ScheduleMode.deny] → 直接拒绝，后面不再看；
/// 2. 命中一条 [ScheduleMode.allow] → 直接放行；
/// 3. 一条都没命中：若该对象配了 allow 规则 → 拒绝（窗口外），否则放行。
ScheduleDecision scheduleAllows({
  required List<ScheduleRule> rules,
  required String model,
  String? groupId,
  required DateTime now,
}) {
  String? denyReason;
  var sawAllow = false;
  for (final r in rules) {
    if (!r.enabled) continue;
    if (!hits(r, model: model, groupId: groupId)) continue;
    if (!r.matches(now)) {
      if (r.mode == ScheduleMode.allow) sawAllow = true;
      continue;
    }
    if (r.mode == ScheduleMode.deny) {
      denyReason ??= _reasonOf(r);
      break;
    }
    return ScheduleDecision.allow;
  }
  if (denyReason != null) return ScheduleDecision.deny(denyReason);
  if (sawAllow) {
    return ScheduleDecision.deny(
      'Model "$model" is not available in the current time window',
    );
  }
  return ScheduleDecision.allow;
}

/// 这条规则管不管某个模型：命中对外模型名，或命中它所属的配置档案 id。
bool hits(ScheduleRule r, {required String model, String? groupId}) {
  if (r.targets.contains(model)) return true;
  return groupId != null &&
      groupId.isNotEmpty &&
      r.targets.contains(groupId);
}

String _reasonOf(ScheduleRule r) {
  final names = r.targets.isEmpty ? '-' : r.targets.join(',');
  return 'Model is blocked by schedule "${r.id}" '
      '(${r.startHour}:00-${r.endHour}:00'
      '${r.weekdays.length == 7 ? '' : ' on weekdays ${r.weekdays.join(",")}'})'
      ' [$names]';
}

/// 把星期列表渲染成 1/2/3… 这种本地化短名之前的原始值，供 UI 复用。
List<int> defaultWeekdays() => const [1, 2, 3, 4, 5, 6, 7];
