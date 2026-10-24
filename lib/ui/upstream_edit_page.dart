import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/models/thinking_level.dart';
import 'package:local2api/services/network_utils.dart';
import 'package:local2api/services/model_auto_refresh.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/src/loading_indicator_m3e.dart';
import 'package:local2api/ui/widgets/field_row.dart';
import 'package:local2api/ui/widgets/text_editor_sheet.dart';
import 'package:local2api/widgets/app_toast.dart';
import 'package:local2api/widgets/expressive_app_bar.dart';
import 'package:local2api/widgets/frosted_page_bar.dart';
import 'package:local2api/widgets/predictive_back_sheet.dart';

import 'schedule_policy_page.dart';
import 'upstream_balance_page.dart';
import 'upstream_models_page.dart';
import 'upstream_qr_dialog.dart';
import 'widgets/common.dart' show pushPage;

/// 上游编辑页：新建/编辑一个上游。
///
/// UI 参考 ClashMetaForAndroid 的「配置」页：**一行一个字段**（左图标 +
/// 小标签 + 当前值 + 下划线，右端一支铅笔），点行开编辑器改那一项，
/// **保存动作在右上角顶栏**而不是页面底部的大按钮。「模型」也不在这页
/// 里铺开 —— 它单独一页 [UpstreamModelsPage]，这一行只显示「N 个模型」。
///
/// 字段顺序照 CMFA 那张图：名称 / URL / 模式（= 上游类型）/ 密钥 / 备注 /
/// 启用 / 模型 / 测试连接。CMFA 图里灰掉的「不可用」行我们不照抄：这里的
/// 行没有「不适用」状态，只有没填的显示成灰色占位文本。
class UpstreamEditPage extends StatefulWidget {
  const UpstreamEditPage({super.key, required this.controller, this.upstream});

  final ServerController controller;
  final Upstream? upstream; // null = 新建

  @override
  State<UpstreamEditPage> createState() => _UpstreamEditPageState();
}

class _UpstreamEditPageState extends State<UpstreamEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _note;
  late UpstreamType _type;
  late UpstreamModality _modality;
  late bool _enabled;
  late List<ModelEntry> _models;

  /// 默认思考档位（'' = 不干预）与它的下发形状。只在客户端自己没发档位时生效。
  late String _thinkingDefault;
  late ThinkingWireFormat _thinkingWire;

  /// 自动更新模型列表的间隔（小时，0 = 关）与上次刷新时间。
  late int _autoRefreshHours;
  late int _refreshedAtMs;

  bool _busy = false; // 测试连接进行中（拉模型已经挪到模型页）
  bool _refreshing = false; // 「立即刷新」进行中

  /// 进页时的初值快照：返回时拿来判断「有没有改过」，改过才弹确认框。
  late final String _initialName;
  late final String _initialBaseUrl;
  late final String _initialApiKey;
  late final String _initialNote;
  late final UpstreamType _initialType;
  late final UpstreamModality _initialModality;
  late final bool _initialEnabled;
  late final List<ModelEntry> _initialModels;
  late final String _initialThinkingDefault;
  late final ThinkingWireFormat _initialThinkingWire;
  late final int _initialAutoRefreshHours;

  /// 「未保存更改」确认框正在跑（防止返回手势连点弹两个框）。
  bool _confirmingLeave = false;

  @override
  void initState() {
    super.initState();
    final u = widget.upstream;
    _name = TextEditingController(text: u?.name ?? '');
    _baseUrl = TextEditingController(
      text: u?.baseUrl ?? UpstreamType.llamacpp.defaultBaseUrl,
    );
    _apiKey = TextEditingController(text: u?.apiKey ?? '');
    _note = TextEditingController(text: u?.note ?? '');
    _type = u?.type ?? UpstreamType.llamacpp;
    _modality = u?.modality ?? UpstreamModality.chat;
    _enabled = u?.enabled ?? true;
    _thinkingDefault = u?.thinkingDefault ?? '';
    _thinkingWire = u?.thinkingWire ?? ThinkingWireFormat.effort;
    _autoRefreshHours = u?.autoRefreshHours ?? 0;
    _refreshedAtMs = u?.modelsRefreshedAtMs ?? 0;
    _models = [
      ...?u?.models.map(
        (m) => ModelEntry(
          publicName: m.publicName,
          target: m.target,
          enabled: m.enabled,
          fallbacks: m.fallbacks,
          contextLength: m.contextLength,
          maxOutputTokens: m.maxOutputTokens,
        ),
      ),
    ];
    _initialName = _name.text;
    _initialBaseUrl = _baseUrl.text;
    _initialApiKey = _apiKey.text;
    _initialNote = _note.text;
    _initialType = _type;
    _initialModality = _modality;
    _initialEnabled = _enabled;
    _initialModels = _copyModels(_models);
    _initialThinkingDefault = _thinkingDefault;
    _initialThinkingWire = _thinkingWire;
    _initialAutoRefreshHours = _autoRefreshHours;
  }

  static List<ModelEntry> _copyModels(List<ModelEntry> models) => [
    for (final m in models)
      ModelEntry(
        publicName: m.publicName,
        target: m.target,
        enabled: m.enabled,
        fallbacks: List<String>.of(m.fallbacks),
        contextLength: m.contextLength,
        maxOutputTokens: m.maxOutputTokens,
      ),
  ];

  static bool _modelsEqual(List<ModelEntry> a, List<ModelEntry> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      // fallbacks 是 List，Map 直接比会按引用不等，序列化成 JSON 再比。
      if (jsonEncode(a[i].toJson()) != jsonEncode(b[i].toJson())) return false;
    }
    return true;
  }

  /// 相对进页那一刻有没有动过任何一项（含模型子页里的增删改）。
  ///
  /// 与 [_save] 的落盘口径一致：文本 trim 后比，密钥原文比。
  bool get _isDirty =>
      _name.text.trim() != _initialName.trim() ||
      _baseUrl.text.trim() != _initialBaseUrl.trim() ||
      _apiKey.text != _initialApiKey ||
      _note.text.trim() != _initialNote.trim() ||
      _type != _initialType ||
      _modality != _initialModality ||
      _enabled != _initialEnabled ||
      !_modelsEqual(_models, _initialModels) ||
      _thinkingDefault != _initialThinkingDefault ||
      _thinkingWire != _initialThinkingWire ||
      _autoRefreshHours != _initialAutoRefreshHours;

  /// 返回（系统返回手势与顶栏返回键都汇到 maybePop）：改过任何一项就先弹
  /// 「未保存的更改」，保存 / 不保存 / 取消。没改过直接走。
  Future<void> _handleBack() async {
    if (!_isDirty) {
      Navigator.of(context).pop();
      return;
    }
    if (_confirmingLeave) return;
    _confirmingLeave = true;
    final l10n = AppLocalizations.of(context);
    final action = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l10n.unsavedChangesTitle),
        content: Text(l10n.unsavedChangesMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, 'cancel'),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, 'discard'),
            child: Text(l10n.unsavedDiscard),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, 'save'),
            child: Text(l10n.unsavedSave),
          ),
        ],
      ),
    );
    _confirmingLeave = false;
    if (!mounted || action == null || action == 'cancel') return;
    if (action == 'save') {
      // _save 校验不过只会 toast（名称必填、URL 格式），页面留着不 pop。
      await _save();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    _note.dispose();
    super.dispose();
  }

  ProxyServer get _server => widget.controller.server;

  String _typeLabel(AppLocalizations l10n, UpstreamType type) => switch (type) {
    UpstreamType.llamacpp => l10n.typeLlamacpp,
    UpstreamType.ollama => l10n.typeOllama,
    UpstreamType.openai => l10n.typeOpenai,
    UpstreamType.anthropic => l10n.typeAnthropic,
    UpstreamType.localTts => l10n.typeLocalTts,
  };

  String _modalityLabel(AppLocalizations l10n, UpstreamModality m) =>
      switch (m) {
        UpstreamModality.chat => l10n.modalityChat,
        UpstreamModality.audio => l10n.modalityAudio,
      };

  /// 某一项没填时行里显示的占位文本（对应 CMFA 图里那行灰字）。
  String get _notFilled => AppLocalizations.of(context).notFilled;

  /// 点行开编辑器改一个文本字段（共享抽屉，见 showTextEditorSheet）。
  /// 值直接写回父页持有的那个 [TextEditingController]，所以「保存」时
  /// `_save()` 读到的就是最新的一份。
  Future<void> _editText({
    required String label,
    required TextEditingController target,
    String? hint,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) async {
    final result = await showTextEditorSheet(
      context,
      label: label,
      initial: target.text,
      hint: hint,
      keyboardType: keyboardType,
      maxLines: maxLines,
    );
    if (result == null) return;
    setState(() => target.text = result);
  }

  /// 「模式」行：选上游类型。新建时顺手把地址换成该类型的默认值。
  Future<void> _pickMode() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showAppBottomSheet<UpstreamType>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  l10n.pickModeTitle,
                  style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final t in const [
                UpstreamType.llamacpp,
                UpstreamType.ollama,
                UpstreamType.openai,
                UpstreamType.anthropic,
              ])
                ListTile(
                  title: Text(_typeLabel(l10n, t)),
                  trailing: t == _type
                      ? Icon(
                          Icons.check,
                          color: Theme.of(sheetCtx).colorScheme.primary,
                        )
                      : null,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                  ),
                  selected: t == _type,
                  onTap: () => Navigator.pop(sheetCtx, t),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || picked == _type) return;
    setState(() {
      _type = picked;
      // 编辑已有上游时不动地址：那是用户自己填的。
      if (widget.upstream == null) _baseUrl.text = picked.defaultBaseUrl;
    });
  }

  /// 「模态」行：选这个上游对外服务哪类请求（chat / audio）。
  Future<void> _pickModality() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showAppBottomSheet<UpstreamModality>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  l10n.modalityLabel,
                  style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final m in const [
                UpstreamModality.chat,
                UpstreamModality.audio,
              ])
                ListTile(
                  title: Text(_modalityLabel(l10n, m)),
                  subtitle: m == UpstreamModality.audio
                      ? Text(
                          l10n.modalityAudioHint,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  trailing: m == _modality
                      ? Icon(
                          Icons.check,
                          color: Theme.of(sheetCtx).colorScheme.primary,
                        )
                      : null,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                  ),
                  selected: m == _modality,
                  onTap: () => Navigator.pop(sheetCtx, m),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || picked == _modality) return;
    setState(() => _modality = picked);
  }

  /// 默认思考档位的行文案（顺序与 [kThinkingDefaultIds] 一致）。
  String _thinkingDefaultLabel(AppLocalizations l10n, String id) =>
      switch (id) {
        'none' => l10n.thinkingLevelNone,
        'minimal' => l10n.thinkingLevelMinimal,
        'low' => l10n.thinkingLevelLow,
        'medium' => l10n.thinkingLevelMedium,
        'high' => l10n.thinkingLevelHigh,
        'xhigh' => l10n.thinkingLevelXhigh,
        'max' => l10n.thinkingLevelMax,
        _ => l10n.thinkingDefaultOff,
      };

  /// 档位下发形状的行文案。
  String _thinkingWireLabel(AppLocalizations l10n, ThinkingWireFormat w) =>
      switch (w) {
        ThinkingWireFormat.budget => l10n.thinkingWireBudget,
        ThinkingWireFormat.effort => l10n.thinkingWireEffort,
        ThinkingWireFormat.thinking => l10n.thinkingWireThinking,
        ThinkingWireFormat.both => l10n.thinkingWireBoth,
      };

  /// 通用单选抽屉（档位 / 下发形状共用一套行样式，与「模式」「模态」一致）。
  Future<T?> _pickOption<T>({
    required String title,
    required List<(T, String)> options,
    required T current,
  }) async {
    return showAppBottomSheet<T>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  title,
                  style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final (value, label) in options)
                ListTile(
                  title: Text(label),
                  trailing: value == current
                      ? Icon(
                          Icons.check,
                          color: Theme.of(sheetCtx).colorScheme.primary,
                        )
                      : null,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                  ),
                  selected: value == current,
                  onTap: () => Navigator.pop(sheetCtx, value),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 「默认思考档位」行：不下发 / 关 / 极轻 / 精简 / 均衡 / 深思 / 极深 / 最重。
  Future<void> _pickThinkingDefault() async {
    final l10n = AppLocalizations.of(context);
    final picked = await _pickOption<String>(
      title: l10n.thinkingDefaultLabel,
      current: _thinkingDefault,
      options: [
        for (final id in kThinkingDefaultIds)
          (id, _thinkingDefaultLabel(l10n, id)),
      ],
    );
    if (picked == null || picked == _thinkingDefault) return;
    setState(() => _thinkingDefault = picked);
  }

  /// 「档位下发格式」行：只压预算 / reasoning_effort / thinking / 两者。
  Future<void> _pickThinkingWire() async {
    final l10n = AppLocalizations.of(context);
    final picked = await _pickOption<ThinkingWireFormat>(
      title: l10n.thinkingWireLabel,
      current: _thinkingWire,
      options: [
        (ThinkingWireFormat.budget, l10n.thinkingWireBudget),
        (ThinkingWireFormat.effort, l10n.thinkingWireEffort),
        (ThinkingWireFormat.thinking, l10n.thinkingWireThinking),
        (ThinkingWireFormat.both, l10n.thinkingWireBoth),
      ],
    );
    if (picked == null || picked == _thinkingWire) return;
    setState(() => _thinkingWire = picked);
  }

  /// 自动更新间隔的文案（选项与 [kAutoRefreshHourChoices] 一一对应）。
  String _autoRefreshLabel(AppLocalizations l10n, int hours) =>
      switch (hours) {
        0 => l10n.autoRefreshOff,
        24 => l10n.autoRefreshEvery1d,
        72 => l10n.autoRefreshEvery3d,
        168 => l10n.autoRefreshEvery7d,
        720 => l10n.autoRefreshEvery30d,
        _ => l10n.autoRefreshEvery7d,
      };

  /// 行尾的「上次 / 下次」提示（没开自动更新时给说明，开了但没刷过给「还没刷新过」）。
  String _autoRefreshStatus(AppLocalizations l10n) {
    if (_autoRefreshHours <= 0) return l10n.autoRefreshDesc;
    if (_refreshedAtMs <= 0) return l10n.autoRefreshNever;
    final left = DateTime.fromMillisecondsSinceEpoch(
      _refreshedAtMs + _autoRefreshHours * 3600 * 1000,
    ).difference(DateTime.now());
    if (left.isNegative) return l10n.autoRefreshJustNow;
    return l10n.autoRefreshNextIn(_humanDuration(left));
  }

  static String _humanDuration(Duration d) {
    if (d.inDays >= 1) return '${d.inDays} 天';
    if (d.inHours >= 1) return '${d.inHours} 小时';
    final m = d.inMinutes < 1 ? 1 : d.inMinutes;
    return '$m 分钟';
  }

  /// 「自动更新模型」行：选间隔。
  Future<void> _pickAutoRefresh() async {
    final l10n = AppLocalizations.of(context);
    final picked = await _pickOption<int>(
      title: l10n.autoRefreshTitle,
      current: _autoRefreshHours,
      options: [
        for (final h in kAutoRefreshHourChoices) (h, _autoRefreshLabel(l10n, h)),
      ],
    );
    if (picked == null || picked == _autoRefreshHours) return;
    setState(() => _autoRefreshHours = picked);
  }

  /// 「立即刷新」：拿当前草稿去拉一次清单，结果就地合并进 [_models]。
  ///
  /// 注意这里不走 ModelAutoRefresh 的落盘路径 —— 页面上还没保存的东西不能
  /// 被一次刷新偷偷写进配置。合并完只是把 `_models` 换掉，用户点保存才生效。
  ///
  /// 合并口径与后台自动更新同一个函数（[ModelAutoRefresh.mergeCatalog]）：
  /// 路由条目（Zen 的 `zen-free`）不会被当成「上游没有的模型」删掉。
  Future<void> _refreshNow() async {
    final l10n = AppLocalizations.of(context);
    if (_refreshing) return;
    final url = _baseUrl.text.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      _toast(l10n.baseUrlInvalid);
      return;
    }
    setState(() => _refreshing = true);
    try {
      final probe = _probe()..models = _copyModels(_models);
      final catalog = await _server.fetchUpstreamModels(probe);
      if (!mounted) return;
      final result = ModelAutoRefresh.mergeCatalog(probe, catalog);
      if (!result.ok) {
        setState(() => _refreshing = false);
        _toast(l10n.fetchFailed(result.error ?? ''));
        return;
      }
      setState(() {
        _models = probe.models;
        // 手动刷过也算「上次刷新时间」，否则保存后下次启动还会再刷一遍。
        _refreshedAtMs = DateTime.now().millisecondsSinceEpoch;
        _refreshing = false;
      });
      _toast(
        result.changed
            ? l10n.autoRefreshDone(
                '${result.added.length}',
                '${result.removed.length}',
              )
            : l10n.autoRefreshNoChange,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _refreshing = false);
      _toast(l10n.fetchFailed(_shortError(e)));
    }
  }

  /// 「模型」行：进独立的一页管理对外模型。列表对象传过去，那页原地改。
  /// 峰谷策略能作用的模型（这个上游的对外名）。
  List<String> get _schedulePool => [
    for (final m in _models)
      if (m.publicName.trim().isNotEmpty) m.publicName.trim(),
  ];

  /// 这个上游自己的策略条数（含老数据里按 managedBy 匹配的组级规则）。
  int get _scheduleCount => scheduleRulesOfUpstream(
    widget.controller.config,
    modelNames: _schedulePool,
    managedBy: widget.upstream?.managedBy,
  ).length;

  /// 打开峰谷策略页：只列 / 只让配这个上游的模型。
  Future<void> _openSchedule() async {
    await pushPage(
      context,
      SchedulePolicyPage(
        controller: widget.controller,
        targetPool: _schedulePool,
        managedBy: widget.upstream?.managedBy,
      ),
    );
    // 回来后刷新「N 条策略」那个值
    if (mounted) setState(() {});
  }

  void _openModels() {
    pushPage(
      context,
      UpstreamModelsPage(
        controller: widget.controller,
        models: _models,
        probe: () => Upstream(
          id: '',
          name: _name.text,
          type: _type,
          baseUrl: _baseUrl.text.trim(),
          apiKey: _apiKey.text,
        ),
        onChanged: () {
          if (mounted) setState(() {});
        },
      ),
    );
  }

  /// 余额页：查的是**当前草稿**的地址 + 密钥（`_probe()`），所以没点保存
  /// 也能先看一眼。各家余额接口口径不同，见 [UpstreamBalanceService]。
  void _openBalance() {
    pushPage(
      context,
      UpstreamBalancePage(
        probe: _probe,
        upstreamName: _name.text.trim(),
      ),
    );
  }

  Future<void> _testConnection() async {
    final l10n = AppLocalizations.of(context);
    if (_baseUrl.text.trim().isEmpty) {
      _toast(l10n.baseUrlInvalid);
      return;
    }
    setState(() => _busy = true);
    try {
      await _server.testUpstream(_probe());
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(l10n.testOk);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(l10n.testFailed(_shortError(e)));
    }
  }

  Upstream _probe() => Upstream(
    id: '',
    name: _name.text,
    type: _type,
    baseUrl: _baseUrl.text.trim(),
    apiKey: _apiKey.text,
  );

  /// 二维码要编码的「当前草稿」上游：弹窗自己会抹掉 apiKey，
  /// 这里照实带上正在编辑的名称 / 地址 / 备注 / 模型。
  Upstream get _qrDraft => Upstream(
    id: widget.upstream?.id ?? '',
    name: _name.text.trim().isEmpty ? 'upstream' : _name.text.trim(),
    type: _type,
    baseUrl: _baseUrl.text.trim(),
    note: _note.text.trim(),
    models: _models,
  );

  String _shortError(Object e) {
    var s = e.toString();
    s = s.replaceFirst(RegExp(r'^(Exception:\s*)+'), '');
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }

  void _toast(String msg) => showAppToast(context, msg);

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (_name.text.trim().isEmpty) {
      _toast(l10n.upstreamNameRequired);
      return;
    }
    final local = _type.isLocal;
    final url = _baseUrl.text.trim();
    if (!local && !url.startsWith('http://') && !url.startsWith('https://')) {
      _toast(l10n.baseUrlInvalid);
      return;
    }
    // 本地 TTS 天然是语音上游；远端上游模态跟用户选的走。
    final modality = local ? UpstreamModality.audio : _modality;
    final store = widget.controller.store;
    final existing = widget.upstream;
    if (existing != null) {
      existing
        ..name = _name.text.trim()
        ..type = _type
        ..baseUrl = local ? '' : url
        ..apiKey = _apiKey.text
        ..modality = modality
        ..note = _note.text.trim()
        ..enabled = _enabled
        ..thinkingDefault = _thinkingDefault
        ..thinkingWire = _thinkingWire
        ..autoRefreshHours = _autoRefreshHours
        ..modelsRefreshedAtMs = _refreshedAtMs
        ..models = _models;
      store.update(widget.controller.config);
    } else {
      final u = Upstream(
        id: NetworkUtils.newId(),
        name: _name.text.trim(),
        type: _type,
        baseUrl: local ? '' : url,
        apiKey: _apiKey.text,
        modality: modality,
        note: _note.text.trim(),
        enabled: _enabled,
        thinkingDefault: _thinkingDefault,
        thinkingWire: _thinkingWire,
        autoRefreshHours: _autoRefreshHours,
        modelsRefreshedAtMs: _refreshedAtMs,
        models: _models,
      );
      final config = widget.controller.config;
      config.upstreams.add(u);
      store.update(config);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final u = widget.upstream!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l10n.deleteUpstreamConfirm(u.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(l10n.deleteBtn),
          ),
        ],
      ),
    );
    if (ok == true) {
      widget.controller.config.upstreams.remove(u);
      widget.controller.store.update(widget.controller.config);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final enabledCount = _models.where((m) => m.enabled).length;
    return PopScope(
      // 拦下系统返回，交给 [_handleBack] 判断要不要弹「未保存」。
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: FrostedBarPage(
        title: widget.upstream == null ? l10n.newUpstream : l10n.editUpstream,
        // 保存挪到右上角（CMFA 那张图的软盘位置）；编辑态再多一个删除，
        // 二维码随时可弹（分享的就是正在编辑的草稿）。
        actions: [
          MorphIconButton(
            icon: Icons.qr_code_2,
            tooltip: l10n.upstreamQrTitle,
            transparent: true,
            onTap: () => showUpstreamQrDialog(context, _qrDraft),
          ),
          if (widget.upstream != null)
            MorphIconButton(
              icon: Icons.delete_outline,
              tooltip: l10n.deleteBtn,
              transparent: true,
              onTap: _delete,
            ),
          MorphIconButton(
            icon: Icons.save_outlined,
            tooltip: l10n.saveBtn,
            transparent: true,
            onTap: _save,
          ),
        ],
        child: ListView(
          padding: EdgeInsets.only(
            top: frostedPageBarInset(context) + 8,
            bottom: 32,
          ),
          children: [
            _HintRow(icon: Icons.info_outline, text: l10n.upstreamEditHint),
            const SizedBox(height: 6),
            _FieldRow(
              icon: Icons.label_outline,
              label: l10n.upstreamNameLabel,
              value: _name.text.trim().isEmpty ? _notFilled : _name.text,
              valueIsHint: _name.text.trim().isEmpty,
              onTap: () => _editText(
                label: l10n.upstreamNameLabel,
                target: _name,
                hint: 'llama-server / Ollama / vLLM',
              ),
            ),
            _FieldRow(
              icon: Icons.category_outlined,
              label: l10n.upstreamModeLabel,
              value: _typeLabel(l10n, _type),
              onTap: _pickMode,
            ),
            // 模态：只对 OpenAI 兼容上游有意义（audio = MiMo TTS 那类
            // 「chat.completions 语音」上游）；本地 TTS 天然是 audio。
            if (_type == UpstreamType.openai)
              _FieldRow(
                icon: Icons.graphic_eq,
                label: l10n.modalityLabel,
                value: _modalityLabel(l10n, _modality),
                onTap: _pickModality,
              ),
            // 本地 TTS 没有远端：不出 URL / 密钥行。
            if (!_type.isLocal) ...[
              _FieldRow(
                icon: Icons.monitor_outlined,
                label: 'URL',
                value: _baseUrl.text.trim().isEmpty
                    ? _notFilled
                    : _baseUrl.text,
                valueIsHint: _baseUrl.text.trim().isEmpty,
                onTap: () => _editText(
                  label: l10n.baseUrlLabel,
                  target: _baseUrl,
                  hint: l10n.baseUrlHint,
                  keyboardType: TextInputType.url,
                ),
              ),
              _FieldRow(
                icon: Icons.key_outlined,
                label: l10n.upstreamKeyLabel,
                // 密钥不明文显示，只给一长短点；要看要点铅笔。
                value: _apiKey.text.isEmpty
                    ? _notFilled
                    : '•' * _apiKey.text.length.clamp(6, 14),
                valueIsHint: _apiKey.text.isEmpty,
                onTap: () =>
                    _editText(label: l10n.upstreamKeyLabel, target: _apiKey),
              ),
            ],
            _FieldRow(
              icon: Icons.note_add_outlined,
              label: l10n.upstreamNoteLabel,
              value: _note.text.trim().isEmpty ? _notFilled : _note.text,
              valueIsHint: _note.text.trim().isEmpty,
              onTap: () => _editText(
                label: l10n.upstreamNoteLabel,
                target: _note,
                hint: l10n.upstreamNoteHint,
                maxLines: 4,
              ),
            ),
            // 默认思考档位：客户端自己没发档位时由网关补一个。第三方 agent
            // （pi-ai 那类）对自定义端点的模型常常一个思考字段都不发，而
            // DeepSeek 这类模型默认就是不思考 —— 症状即「模型不 think 了」。
            if (!_type.isLocal) ...[
              _FieldRow(
                icon: Icons.psychology_outlined,
                label: l10n.thinkingDefaultLabel,
                value: _thinkingDefaultLabel(l10n, _thinkingDefault),
                onTap: _pickThinkingDefault,
              ),
              // 补档时往上游下发的形状：各家认的字段不同，发错轻则被忽略、
              // 重则 400，所以让它可挑。只在真补档时才有意义。
              if (_thinkingDefault.isNotEmpty)
                _FieldRow(
                  icon: Icons.alt_route,
                  label: l10n.thinkingWireLabel,
                  value: _thinkingWireLabel(l10n, _thinkingWire),
                  onTap: _pickThinkingWire,
                ),
            ],
            // 峰谷时段：跟其它字段完全同构（行尾同样是铅笔），点进去配这个上游的窗口
            // 自动更新模型列表：按间隔去上游对一次清单（补新、删下架）。
            // 内置 Zen / MiMo 默认 7 天一次；0 = 关。
            if (!_type.isLocal)
              _FieldRow(
                icon: Icons.sync,
                label: l10n.autoRefreshTitle,
                value: _autoRefreshLabel(l10n, _autoRefreshHours),
                onTap: _pickAutoRefresh,
              ),
            if (!_type.isLocal && _autoRefreshHours > 0)
              _FieldRow(
                icon: Icons.update,
                label: l10n.autoRefreshRefreshNow,
                value: _refreshing
                    ? l10n.autoRefreshRefreshing
                    : _autoRefreshStatus(l10n),
                valueIsHint: !_refreshing,
                control: _refreshing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: LoadingIndicatorM3E(
                          constraints: BoxConstraints.tightFor(
                            width: 22,
                            height: 22,
                          ),
                        ),
                      )
                    : const Icon(Icons.refresh),
                onTap: _refreshing ? null : _refreshNow,
              ),
            _FieldRow(
              icon: Icons.schedule_outlined,
              label: l10n.scheduleTitle,
              value: _scheduleCount == 0
                  ? _notFilled
                  : l10n.scheduleStatus('$_scheduleCount'),
              valueIsHint: _scheduleCount == 0,
              onTap: _schedulePool.isEmpty ? null : _openSchedule,
            ),
            _FieldRow(
              icon: Icons.power_outlined,
              label: l10n.enabledLabel,
              // 整行可点 = 跟开关同一个动作（MiuixSwitchPreference 也是这么做的）
              onTap: () => setState(() => _enabled = !_enabled),
              control: Switch(
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
            ),
            _FieldRow(
              icon: Icons.folder_open_outlined,
              label: l10n.exposedModelsTitle,
              value: enabledCount == 0
                  ? l10n.noExposedModels
                  : l10n.modelCountLabel('$enabledCount'),
              valueIsHint: enabledCount == 0,
              endIcon: Icons.chevron_right,
              onTap: _openModels,
            ),
            // 连通性测试只对远端上游有意义。
            if (!_type.isLocal)
              _FieldRow(
                icon: Icons.network_check,
                label: l10n.testConnectionTitle,
                value: _busy ? l10n.testing : l10n.testConnectionDesc,
                valueIsHint: !_busy,
                control: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: LoadingIndicatorM3E(
                          constraints: BoxConstraints.tightFor(
                            width: 22,
                            height: 22,
                          ),
                        ),
                      )
                    : const Icon(Icons.play_arrow),
                onTap: _busy ? null : _testConnection,
              ),
            // 余额：连通性测试的邻居 —— 都是「拿这份草稿去问上游」，
            // 只是问的是账户里还剩多少钱。本地 TTS 没有远端，不出这一行。
            if (!_type.isLocal)
              _FieldRow(
                icon: Icons.account_balance_wallet_outlined,
                label: l10n.balanceTitle,
                value: l10n.balanceEntryDesc,
                valueIsHint: true,
                endIcon: Icons.chevron_right,
                onTap: _openBalance,
              ),
          ],
        ),
      ),
    );
  }
}

/// 顶部说明行（CMFA 那张图最上面那行 ⓘ）：只有图标 + 一句话，不可点。
/// 顶部说明行（CMFA 那张图最上面那行 ⓘ）：只有图标 + 一句话，不可点。
class _HintRow extends StatelessWidget {
  const _HintRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 26, color: cs.onSurface),
          const SizedBox(width: 18),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 行组件挪到了共享的 `ui/widgets/field_row.dart`（角色卡编辑页同用）；
/// 这里留个同名薄壳，页面内的调用点不用动。
class _FieldRow extends FieldRow {
  const _FieldRow({
    required super.icon,
    required super.label,
    super.value,
    super.valueIsHint,
    super.onTap,
    super.control,
    super.endIcon,
  });
}
