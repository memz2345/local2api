import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/widgets/miuix/miuix_field_editor.dart';
import 'package:local2api/widgets/miuix/miuix_field_row.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';
import 'package:local2api/widgets/miuix/miuix_dialog.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/widgets/miuix/miuix_info_card.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/models/thinking_level.dart';
import 'package:local2api/services/model_auto_refresh.dart';
import 'package:local2api/services/network_utils.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';

import 'miuix_schedule_policy_page.dart';
import 'miuix_upstream_balance_page.dart';
import 'miuix_upstream_models_page.dart';
import '../upstream_qr_dialog.dart';

/// 上游编辑页（miuix 版，对应 Material 版 `UpstreamEditPage`）。
///
/// 信息架构和 Material 版一致：参考 ClashMetaForAndroid 的「配置」页，
/// **一行一个字段**（图标 + 字段名 + 当前值 + 行尾铅笔），点行开编辑器改
/// 那一项，「模型」单独一页，保存动作在右上角 —— 只是 miuix 这边右上角放
/// ✔（HyperOS 的确认符号），行用偏好卡而不是下划线。
class MiuixUpstreamEditPage extends StatefulWidget {
  const MiuixUpstreamEditPage({
    super.key,
    required this.controller,
    this.upstream,
  });

  final ServerController controller;
  final Upstream? upstream; // null = 新建

  @override
  State<MiuixUpstreamEditPage> createState() => _MiuixUpstreamEditPageState();
}

class _MiuixUpstreamEditPageState extends State<MiuixUpstreamEditPage> {
  /// 二级页统一的可折叠大标题行为；`MiuixBlurTopBar` 读它，
  /// `MiuixScrollBehaviorListener` 在外层把滚动通知喂给它。
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();
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

  @override
  void dispose() {
    _behavior.state.dispose();
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

  /// 点行改一个文本字段：值写回父页持有的 controller，保存时一起落盘。
  /// 弹窗是共享的 [showMiuixFieldEditor]（上游/角色卡编辑页同一套）。
  Future<void> _editText({
    required String label,
    required TextEditingController target,
    String? hint,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) async {
    final draft = await showMiuixFieldEditor(
      context,
      label: label,
      initial: target.text,
      hint: hint,
      keyboardType: keyboardType,
      maxLines: maxLines,
    );
    if (draft == null) return;
    setState(() => target.text = draft);
  }

  /// 「模式」行：选上游类型（同样是对话框，四档单选）。
  /// 新建时顺手把地址换成该类型的默认值。
  Future<void> _pickMode() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showMiuixDialog<UpstreamType>(
      context: context,
      title: l10n.pickModeTitle,
      content: _MiuixModeDialogBody(
        current: _type,
        labelOf: (t) => _typeLabel(l10n, t),
      ),
      actions: [
        MiuixDialogAction(
          label: l10n.cancel,
          onPressed: (ctx) => Navigator.of(ctx).pop(),
        ),
      ],
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
    final picked = await showMiuixDialog<UpstreamModality>(
      context: context,
      title: l10n.modalityLabel,
      content: _MiuixModalityDialogBody(
        current: _modality,
        labelOf: (m) => _modalityLabel(l10n, m),
      ),
      actions: [
        MiuixDialogAction(
          label: l10n.cancel,
          onPressed: (ctx) => Navigator.of(ctx).pop(),
        ),
      ],
    );
    if (picked == null || picked == _modality) return;
    setState(() => _modality = picked);
  }

  /// 默认思考档位的行文案。
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

  /// 通用单选对话框（档位 / 下发形状共用，与「模式」「模态」同一套样式）。
  Future<T?> _pickOption<T>({
    required String title,
    required List<(T, String)> options,
    required T current,
  }) async {
    final l10n = AppLocalizations.of(context);
    return showMiuixDialog<T>(
      context: context,
      title: title,
      content: _MiuixOptionDialogBody<T>(
        current: current,
        options: options,
      ),
      actions: [
        MiuixDialogAction(
          label: l10n.cancel,
          onPressed: (ctx) => Navigator.of(ctx).pop(),
        ),
      ],
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
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MiuixSchedulePolicyPage(
          controller: widget.controller,
          targetPool: _schedulePool,
          managedBy: widget.upstream?.managedBy,
        ),
      ),
    );
    // 回来后刷新「N 条策略」那个值
    if (mounted) setState(() {});
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

  /// 行尾的「上次 / 下次」提示。
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
  /// 页面上还没保存的东西不会被偷偷写进配置 —— 用户点保存才生效。
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

  void _openModels() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MiuixUpstreamModelsPage(
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
      ),
    );
  }

  /// 余额页：查的是**当前草稿**的地址 + 密钥（`_probe()`），没点保存也能先看。
  /// 各家余额接口口径不同，见 [UpstreamBalanceService]。
  void _openBalance() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MiuixUpstreamBalancePage(
          probe: _probe,
          upstreamName: _name.text.trim(),
        ),
      ),
    );
  }

  Future<void> _testConnection() async {
    final l10n = AppLocalizations.of(context);
    final url = _baseUrl.text.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
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

  void _toast(String msg) => showMiuixToast(context, msg);

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

  /// 删除这个上游：确认框走 [confirmDeleteUpstream]（HyperOS 居中大圆角卡 +
  /// 左取消右红色删除），与发现页那份是同一份 —— 同一个动作不再两个长相。
  Future<void> _delete() async {
    final u = widget.upstream!;
    final ok = await confirmDeleteUpstream(context, u.name);
    if (ok) {
      widget.controller.config.upstreams.remove(u);
      widget.controller.store.update(widget.controller.config);
      if (mounted) Navigator.pop(context);
    }
  }

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
    final action = await showMiuixDialog<String>(
      context: context,
      title: l10n.unsavedChangesTitle,
      message: l10n.unsavedChangesMessage,
      actions: [
        MiuixDialogAction(
          label: l10n.unsavedDiscard,
          onPressed: (ctx) => Navigator.of(ctx).pop('discard'),
        ),
        MiuixDialogAction(
          label: l10n.unsavedSave,
          primary: true,
          onPressed: (ctx) => Navigator.of(ctx).pop('save'),
        ),
      ],
    );
    _confirmingLeave = false;
    if (!mounted || action == null) return; // 取消 / 点弹窗外 = 留在页面
    if (action == 'save') {
      // _save 校验不过只会 toast（名称必填、URL 格式），页面留着不 pop。
      await _save();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final enabledCount = _models.where((m) => m.enabled).length;

    return Material(
      type: MaterialType.transparency,
      child: PopScope(
        // 拦下系统返回，交给 [_handleBack] 判断要不要弹「未保存」。
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _handleBack();
        },
        child: MiuixScaffold(
          containerColor: colors.surface,
          topBar: MiuixBlurTopBar(
            scrollBehavior: _behavior,
            title: widget.upstream == null
                ? l10n.newUpstream
                : l10n.editUpstream,
            navigationIcon: MiuixIconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const MiuixAppIcon(
                AppIconNames.back,
                fallback: Icons.arrow_back,
              ),
            ),
            // 保存 = ✔（HyperOS 的确认符号），放右上角；编辑态再多一个删除，
            // 二维码随时可弹（分享的就是正在编辑的草稿）。
            actions: [
              MiuixIconButton(
                onPressed: () => showUpstreamQrDialog(context, _qrDraft),
                child: const MiuixAppIcon('qrCode', fallback: Icons.qr_code_2),
              ),
              if (widget.upstream != null)
                MiuixIconButton(
                  onPressed: _delete,
                  child: const MiuixAppIcon(
                    AppIconNames.delete,
                    fallback: Icons.delete_outline,
                  ),
                ),
              MiuixIconButton(
                onPressed: _save,
                child: const MiuixAppIcon(
                  AppIconNames.check,
                  fallback: Icons.check,
                ),
              ),
            ],
          ),
          // 内容铺满整页、顶栏画在其上；顶栏高度垫进 padding，从栏下穿过。
          content: (padding) => MiuixScrollBehaviorListener(
            behavior: _behavior,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(16, padding.top + 8, 16, 40),
              children: [
                MiuixInfoCard(text: l10n.upstreamEditHint),
                const SizedBox(height: 16),
                MiuixGroupCard(
                  insideMargin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _field(
                        iconName: AppIconNames.rename,
                        fallback: Icons.label_outline,
                        title: l10n.upstreamNameLabel,
                        value: _name.text.trim().isEmpty
                            ? l10n.notFilled
                            : _name.text,
                        isHint: _name.text.trim().isEmpty,
                        onClick: () => _editText(
                          label: l10n.upstreamNameLabel,
                          target: _name,
                          hint: 'llama-server / Ollama / vLLM',
                        ),
                      ),
                      const MiuixHorizontalDivider(),
                      _field(
                        iconName: AppIconNames.tune,
                        fallback: Icons.category_outlined,
                        title: l10n.upstreamModeLabel,
                        value: _typeLabel(l10n, _type),
                        onClick: _pickMode,
                      ),
                      // 模态：只对 OpenAI 兼容上游有意义（audio = MiMo TTS
                      // 那类「chat.completions 语音」上游）；本地 TTS 天然
                      // 是 audio，不重复出这一行。
                      if (_type == UpstreamType.openai) ...[
                        const MiuixHorizontalDivider(),
                        _field(
                          iconName: AppIconNames.tune,
                          fallback: Icons.graphic_eq,
                          title: l10n.modalityLabel,
                          value: _modalityLabel(l10n, _modality),
                          onClick: _pickModality,
                        ),
                      ],
                      // 本地 TTS 没有远端：不出 URL / 密钥行。
                      if (!_type.isLocal) ...[
                        const MiuixHorizontalDivider(),
                        _field(
                          iconName: AppIconNames.link,
                          fallback: Icons.link,
                          title: 'URL',
                          value: _baseUrl.text.trim().isEmpty
                              ? l10n.notFilled
                              : _baseUrl.text,
                          isHint: _baseUrl.text.trim().isEmpty,
                          onClick: () => _editText(
                            label: l10n.baseUrlLabel,
                            target: _baseUrl,
                            hint: l10n.baseUrlHint,
                            keyboardType: TextInputType.url,
                          ),
                        ),
                        const MiuixHorizontalDivider(),
                        _field(
                          iconName: AppIconNames.lock,
                          fallback: Icons.key_outlined,
                          title: l10n.upstreamKeyLabel,
                          // 密钥不明文显示，只给一长短点；要看要点铅笔。
                          value: _apiKey.text.isEmpty
                              ? l10n.notFilled
                              : '•' * _apiKey.text.length.clamp(6, 14),
                          isHint: _apiKey.text.isEmpty,
                          onClick: () => _editText(
                            label: l10n.upstreamKeyLabel,
                            target: _apiKey,
                          ),
                        ),
                      ],
                      const MiuixHorizontalDivider(),
                      _field(
                        iconName: AppIconNames.note,
                        fallback: Icons.note_add_outlined,
                        title: l10n.upstreamNoteLabel,
                        value: _note.text.trim().isEmpty
                            ? l10n.notFilled
                            : _note.text,
                        isHint: _note.text.trim().isEmpty,
                        onClick: () => _editText(
                          label: l10n.upstreamNoteLabel,
                          target: _note,
                          hint: l10n.upstreamNoteHint,
                          maxLines: 4,
                        ),
                      ),
                      const MiuixHorizontalDivider(),
                      // 默认思考档位：客户端自己没发档位时由网关补一个。第三方
                      // agent（pi-ai 那类）对自定义端点的模型常常一个思考字段都
                      // 不发，而 DeepSeek 这类模型默认就是不思考 —— 症状即「模型
                      // 不 think 了」。本地 TTS 没有聊天请求，不出这两行。
                      if (!_type.isLocal) ...[
                        _field(
                          iconName: AppIconNames.tune,
                          fallback: Icons.psychology_outlined,
                          title: l10n.thinkingDefaultLabel,
                          value: _thinkingDefaultLabel(
                            l10n,
                            _thinkingDefault,
                          ),
                          onClick: _pickThinkingDefault,
                        ),
                        // 补档时往上游下发的形状：各家认的字段不同，发错轻则
                        // 被忽略、重则 400，所以让它可挑。
                        if (_thinkingDefault.isNotEmpty) ...[
                          const MiuixHorizontalDivider(),
                          _field(
                            iconName: AppIconNames.translate,
                            fallback: Icons.alt_route,
                            title: l10n.thinkingWireLabel,
                            value: _thinkingWireLabel(l10n, _thinkingWire),
                            onClick: _pickThinkingWire,
                          ),
                        ],
                        const MiuixHorizontalDivider(),
                        // 自动更新模型列表：按间隔去上游对一次清单
                        //（补新、删下架）。内置 Zen / MiMo 默认 7 天一次。
                        _field(
                          iconName: AppIconNames.refresh,
                          fallback: Icons.sync,
                          title: l10n.autoRefreshTitle,
                          value: _autoRefreshLabel(l10n, _autoRefreshHours),
                          onClick: _pickAutoRefresh,
                        ),
                        const MiuixHorizontalDivider(),
                        _field(
                          iconName: AppIconNames.update,
                          fallback: Icons.update,
                          title: l10n.autoRefreshRefreshNow,
                          value: _refreshing
                              ? l10n.autoRefreshRefreshing
                              : _autoRefreshStatus(l10n),
                          isHint: !_refreshing,
                          onClick: _refreshing ? null : _refreshNow,
                        ),
                        const MiuixHorizontalDivider(),
                      ],
                      // 峰谷时段：跟上面这些字段同一张卡、同一套行外观（行尾也是铅笔）
                      _field(
                        iconName: AppIconNames.recent,
                        fallback: Icons.schedule_outlined,
                        title: l10n.scheduleTitle,
                        value: _scheduleCount == 0
                            ? l10n.notFilled
                            : l10n.scheduleStatus('$_scheduleCount'),
                        isHint: _scheduleCount == 0,
                        onClick: _schedulePool.isEmpty ? null : _openSchedule,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                MiuixGroupCard(
                  insideMargin: EdgeInsets.zero,
                  child: MiuixSwitchPreference(
                    title: l10n.enabledLabel,
                    // closeCircle 渲染出来是电源符号 ⏻（见 AppIconNames 注释），
                    // 跟 Material 版那颗 power 图标同一语义。
                    startAction: const MiuixAppIcon(
                      AppIconNames.closeCircle,
                      fallback: Icons.power_outlined,
                      size: 24,
                    ),
                    value: _enabled,
                    onChanged: (v) => setState(() => _enabled = v),
                  ),
                ),
                const SizedBox(height: 16),
                MiuixGroupCard(
                  insideMargin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      MiuixArrowPreference(
                        title: l10n.exposedModelsTitle,
                        summary: enabledCount == 0
                            ? l10n.noExposedModels
                            : l10n.modelCountLabel('$enabledCount'),
                        startAction: const MiuixAppIcon(
                          AppIconNames.list,
                          fallback: Icons.folder_open_outlined,
                          size: 24,
                        ),
                        onClick: _openModels,
                      ),
                      // 余额：连通性测试的邻居 —— 都是「拿这份草稿去问上游」，
                      // 只是问的是账户里还剩多少钱。本地 TTS 没有远端，不出这行。
                      if (!_type.isLocal) ...[
                        const MiuixHorizontalDivider(),
                        MiuixArrowPreference(
                          title: l10n.balanceTitle,
                          summary: l10n.balanceEntryDesc,
                          startAction: const MiuixAppIcon(
                            AppIconNames.report,
                            fallback: Icons.account_balance_wallet_outlined,
                            size: 24,
                          ),
                          onClick: _openBalance,
                        ),
                      ],
                    ],
                  ),
                ),
                // 连通性测试只对远端上游有意义。
                if (!_type.isLocal) ...[
                  const SizedBox(height: 16),
                  MiuixGroupCard(
                    insideMargin: EdgeInsets.zero,
                    child: MiuixBasicComponent(
                      title: l10n.testConnectionTitle,
                      summary: _busy ? l10n.testing : l10n.testConnectionDesc,
                      // 行首用「探测」，行尾才是「跑一次」的播放键，两头都放播放键会重复。
                      startAction: const MiuixAppIcon(
                        AppIconNames.scan,
                        fallback: Icons.network_check,
                        size: 24,
                      ),
                      onClick: _busy ? null : _testConnection,
                      endActions: [
                        if (_busy)
                          const MiuixCircularProgressIndicator(
                            size: 20,
                            strokeWidth: 2,
                          )
                        else
                          const MiuixAppIcon(
                            AppIconNames.play,
                            fallback: Icons.play_arrow,
                            size: 20,
                            color: null,
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// CMFA 式的一行字段（miuix 渲染）：图标 + 字段名 + 当前值 + 行尾铅笔。
  Widget _field({
    required String iconName,
    required IconData fallback,
    required String title,
    required String value,
    required VoidCallback? onClick,
    bool isHint = false,
  }) {
    return MiuixFieldRow(
      iconName: iconName,
      fallbackIcon: fallback,
      title: title,
      value: value,
      valueIsHint: isHint,
      onTap: onClick,
    );
  }
}

class _MiuixModeDialogBody extends StatelessWidget {
  const _MiuixModeDialogBody({required this.current, required this.labelOf});

  final UpstreamType current;
  final String Function(UpstreamType) labelOf;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final t in const [
          UpstreamType.llamacpp,
          UpstreamType.ollama,
          UpstreamType.openai,
          UpstreamType.anthropic,
        ])
          MiuixRadioButtonPreference(
            title: labelOf(t),
            selected: t == current,
            insideMargin: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            onClick: () => Navigator.of(context).pop(t),
          ),
      ],
    );
  }
}

/// 对话框里的「模态」单选（chat / audio）。
class _MiuixModalityDialogBody extends StatelessWidget {  const _MiuixModalityDialogBody({required this.current, required this.labelOf});

  final UpstreamModality current;
  final String Function(UpstreamModality) labelOf;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in const [UpstreamModality.chat, UpstreamModality.audio])
          MiuixRadioButtonPreference(
            title: labelOf(m),
            selected: m == current,
            insideMargin: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            onClick: () => Navigator.of(context).pop(m),
          ),
      ],
    );
  }
}

/// 通用单选对话框体（默认思考档位 / 档位下发格式用）。
class _MiuixOptionDialogBody<T> extends StatelessWidget {
  const _MiuixOptionDialogBody({required this.current, required this.options});

  final T current;
  final List<(T, String)> options;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (value, label) in options)
          MiuixRadioButtonPreference(
            title: label,
            selected: value == current,
            insideMargin: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            onClick: () => Navigator.of(context).pop(value),
          ),
      ],
    );
  }
}
