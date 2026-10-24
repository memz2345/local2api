import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField;
import 'package:local2api/widgets/miuix/miuix_text_field.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';
import 'package:local2api/widgets/miuix/miuix_bottom_sheet.dart';
import 'package:local2api/widgets/miuix/miuix_dialog.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/widgets/miuix/miuix_info_card.dart';
import 'package:local2api/widgets/az_index_bar.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/models_sort_store.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';

/// 上游的「模型」页（miuix 版，对应 Material 版 `UpstreamModelsPage`）。
///
/// 从 miuix 上游编辑页的「对外模型」那一行进：拉取 / 手动加 / 改别名 /
/// 勾选暴露哪几个都在这页做。
///
/// ⚠️ [models] 是父页那条列表**对象本身**，这一页原地改，再用 [onChanged]
/// 让父页刷新那行的「N 个模型」。写盘仍然只在父页右上角 ✔ 时发生。
class MiuixUpstreamModelsPage extends StatefulWidget {
  const MiuixUpstreamModelsPage({
    super.key,
    required this.controller,
    required this.models,
    required this.probe,
    this.onChanged,
  });

  final ServerController controller;

  /// 父页的对外模型列表（同一个 List 对象）。
  final List<ModelEntry> models;

  /// 用父页当前表单值现造一个探测用的上游（拉模型要地址 / 类型 / 密钥）。
  final Upstream Function() probe;

  /// 列表变了，通知父页刷新。
  final VoidCallback? onChanged;

  @override
  State<MiuixUpstreamModelsPage> createState() =>
      _MiuixUpstreamModelsPageState();
}

class _MiuixUpstreamModelsPageState extends State<MiuixUpstreamModelsPage> {
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();
  bool _busy = false;

  /// 当前排序方式；首字母正序时右侧挂 A-Z 索引条。
  ModelsSortMode _sort = ModelsSortMode.natural;

  /// 索引条上高亮的字母（跟着滚动位置变）。
  String? _activeLetter;

  final ScrollController _scroll = ScrollController();

  /// 每个字母分组一个 key，供索引条跳转定位。
  final Map<String, GlobalKey> _groupKeys = {};

  ProxyServer get _server => widget.controller.server;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    ModelsSortStore.load().then((mode) {
      if (mounted && mode != _sort) setState(() => _sort = mode);
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _behavior.state.dispose();
    super.dispose();
  }

  void _changed() {
    setState(() {});
    widget.onChanged?.call();
  }

  String _shortError(Object e) {
    var s = e.toString();
    s = s.replaceFirst(RegExp(r'^(Exception:\s*)+'), '');
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }

  void _toast(String msg) => showMiuixToast(context, msg);

  /// 滚动时算出「当前顶部停在哪个字母」，驱动索引条高亮。
  void _onScroll() {
    if (!mounted || _sort != ModelsSortMode.alphabet) return;
    final threshold = MediaQuery.paddingOf(context).top + 72;
    String? current;
    for (final entry in _groupKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is! RenderBox) continue;
      if (box.localToGlobal(Offset.zero).dy <= threshold) {
        current = entry.key;
      } else {
        break;
      }
    }
    if (current != _activeLetter) setState(() => _activeLetter = current);
  }

  /// 索引条点击 / 划过：把目标分组滚到顶栏下方。
  void _jumpToLetter(String letter) {
    final box = _groupKeys[letter]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !_scroll.hasClients) return;
    final targetTop = MediaQuery.paddingOf(context).top + 72;
    final delta = box.localToGlobal(Offset.zero).dy - targetTop;
    final max = _scroll.position.maxScrollExtent;
    final target = (_scroll.offset + delta).clamp(0.0, max);
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  void _setSort(ModelsSortMode mode) {
    if (mode == _sort) return;
    setState(() {
      _sort = mode;
      _activeLetter = null;
    });
    ModelsSortStore.save(mode);
  }

  /// 排序方式选择面板（miuix 底部抽屉）。
  Future<void> _pickSort() async {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final picked = await showMiuixBottomSheet<ModelsSortMode>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: MiuixText(
                  l10n.modelsSortTitle,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              MiuixGroupCard(
                insideMargin: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < ModelsSortMode.values.length; i++) ...[
                      if (i > 0) const MiuixHorizontalDivider(),
                      MiuixBasicComponent(
                        title: switch (ModelsSortMode.values[i]) {
                          ModelsSortMode.natural => l10n.modelsSortNatural,
                          ModelsSortMode.alphabet => l10n.modelsSortAlphabet,
                        },
                        onClick: () =>
                            Navigator.of(sheetCtx).pop(ModelsSortMode.values[i]),
                        endActions:
                            ModelsSortMode.values[i] == _sort
                            ? [
                                MiuixAppIcon(
                                  AppIconNames.check,
                                  fallback: Icons.check,
                                  color: colors.primary,
                                ),
                              ]
                            : null,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) _setSort(picked);
  }

  /// 从上游拉模型列表，勾完并回 [_models]。
  Future<void> _fetch() async {
    final l10n = AppLocalizations.of(context);
    final probe = widget.probe();
    final url = probe.baseUrl;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      _toast(l10n.baseUrlInvalid);
      return;
    }
    setState(() => _busy = true);
    try {
      final catalog = await _server.fetchUpstreamModels(probe);
      if (!mounted) return;
      setState(() => _busy = false);
      if (catalog.ids.isEmpty) {
        _toast(l10n.fetchFailed('empty'));
        return;
      }
      await _pickFetched(catalog.ids, catalog.contexts, catalog.outputs);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(l10n.fetchFailed(_shortError(e)));
    }
  }

  /// 拉回来的模型勾选面板：勾上的加进对外列表，取消勾的从列表摘掉。
  ///
  /// [contexts] / [outputs] 是上游顺带给的上下文长度与输出上限（有才有），
  /// 提交时**只补空位**：已经配过值的条目不动，自动获取不覆盖用户手填。
  Future<void> _pickFetched(
    List<String> fetched,
    Map<String, int> contexts,
    Map<String, int> outputs,
  ) async {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final selected = <String>{
      for (final m in widget.models)
        if (m.enabled) m.publicName,
    };
    final ok = await showMiuixBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: MiuixText(
                    l10n.fetchedModels('${fetched.length}'),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final name in fetched)
                        MiuixCheckboxPreference(
                          title: name,
                          value: selected.contains(name),
                          onChanged: (v) => setSheet(
                            () =>
                                v ? selected.add(name) : selected.remove(name),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: MiuixButton(
                    onPressed: () => Navigator.of(sheetCtx).pop(true),
                    colors: MiuixButtonColors(
                      color: colors.primary,
                      contentColor: colors.onPrimary,
                      disabledColor: colors.disabledPrimaryButton,
                      disabledContentColor: colors.disabledOnPrimaryButton,
                    ),
                    child: MiuixText(l10n.confirm),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true) return;
    final list = widget.models;
    final existing = {for (final m in list) m.publicName};
    for (final name in fetched) {
      if (selected.contains(name) && !existing.contains(name)) {
        list.add(
          ModelEntry(publicName: name, contextLength: contexts[name] ?? 0),
        );
      }
    }
    list.removeWhere(
      (m) => fetched.contains(m.publicName) && !selected.contains(m.publicName),
    );
    // 上游顺带给了上下文长度 / 输出上限的，把没配过的补上（配过的不动）。
    var filled = 0;
    for (final m in list) {
      final ctx = contexts[m.publicName];
      if (ctx != null && ctx > 0 && m.contextLength <= 0) {
        m.contextLength = ctx;
        filled++;
      }
      final out = outputs[m.publicName];
      if (out != null && out > 0 && m.maxOutputTokens <= 0) {
        m.maxOutputTokens = out;
      }
    }
    if (filled > 0) _toast(l10n.contextAutoFilled('$filled'));
    _changed();
  }

  /// 手动加一个对外模型（上游没提供 /v1/models 时用）。
  Future<void> _addManually() async {
    final l10n = AppLocalizations.of(context);
    final added = await _modelDialog(title: l10n.addModelBtn);
    if (added == null) return;
    widget.models.add(added);
    _changed();
  }

  /// 改一个对外模型：对外名 + 上游模型名（别名映射）+ 上下文长度。
  Future<void> _edit(int index) async {
    final l10n = AppLocalizations.of(context);
    final m = widget.models[index];
    final next = await _modelDialog(title: l10n.modelAliasLabel, initial: m);
    if (next == null) return;
    setState(() {
      m.publicName = next.publicName;
      m.target = next.target;
      m.contextLength = next.contextLength;
      m.maxOutputTokens = next.maxOutputTokens;
    });
    widget.onChanged?.call();
  }

  /// 「对外名称 + 上游模型」两栏对话框，新增和改别名共用。
  ///
  /// 用 [showMiuixDialog]（HyperOS 居中大圆角卡），跟上游编辑页那些弹窗一套；
  /// 拉回来的**模型清单**仍然用底部抽屉，那种长列表塞进对话框会顶满屏。
  ///
  /// ⚠️ 两个 controller 归 [_MiuixModelDialogBody] 自己管，草稿通过回调回写：
  /// 调用方 `await` 完就去 dispose 的话，对话框的退场动画还在跑，TextField
  /// 会再读一次已释放的 controller → 「used after being disposed」。
  Future<ModelEntry?> _modelDialog({
    required String title,
    ModelEntry? initial,
  }) {
    final l10n = AppLocalizations.of(context);
    var publicName = initial?.publicName ?? '';
    var target = initial?.target ?? '';
    var contextText = (initial?.contextLength ?? 0) > 0
        ? '${initial!.contextLength}'
        : '';
    var outputText = (initial?.maxOutputTokens ?? 0) > 0
        ? '${initial!.maxOutputTokens}'
        : '';
    return showMiuixDialog<ModelEntry>(
      context: context,
      title: title,
      content: _MiuixModelDialogBody(
        initial: initial,
        onPublicChanged: (v) => publicName = v,
        onTargetChanged: (v) => target = v,
        onContextChanged: (v) => contextText = v,
        onOutputChanged: (v) => outputText = v,
      ),
      actions: [
        MiuixDialogAction(
          label: l10n.cancel,
          onPressed: (ctx) => Navigator.of(ctx).pop(),
        ),
        MiuixDialogAction(
          label: l10n.confirm,
          primary: true,
          onPressed: (ctx) {
            final name = publicName.trim();
            // 对外名是这一条的主键，空着就不关窗，让用户回去补
            if (name.isEmpty) return;
            final t = target.trim();
            // 「1,000,000」这种带分隔符的粘贴也认：只取数字部分。
            final digits = contextText.replaceAll(RegExp(r'[^0-9]'), '');
            final ctxLen = int.tryParse(digits) ?? 0;
            if (digits.isNotEmpty && ctxLen <= 0) return;
            final outDigits = outputText.replaceAll(RegExp(r'[^0-9]'), '');
            final outLen = int.tryParse(outDigits) ?? 0;
            if (outDigits.isNotEmpty && outLen <= 0) return;
            Navigator.of(ctx).pop(
              ModelEntry(
                publicName: name,
                target: t.isEmpty ? name : t,
                contextLength: ctxLen,
                maxOutputTokens: outLen,
              ),
            );
          },
        ),
      ],
    );
  }

  void _remove(int index) {
    widget.models.removeAt(index);
    _changed();
  }

  void _toggle(int index, bool value) {
    setState(() => widget.models[index].enabled = value);
    widget.onChanged?.call();
  }

  /// 一行一个对外模型（miuix 版）：勾选 = 暴露，点行改别名，右端改名 / 删除。
  Widget _row(int i, List<ModelEntry> list) {
    final l10n = AppLocalizations.of(context);
    final m = list[i];
    // 副标题：别名映射 + 配过的上下文长度，都没有就 null。
    final parts = [
      if (m.target != m.publicName) '→ ${m.target}',
      if (m.contextLength > 0) l10n.modelContextShort(m.contextLabel),
    ];
    return MiuixBasicComponent(
      title: m.publicName,
      summary: parts.isEmpty ? null : parts.join(' · '),
      startAction: MiuixCheckbox(
        value: list[i].enabled,
        onChanged: (v) => _toggle(i, v ?? true),
      ),
      onClick: () => _edit(i),
      // 行本体 = 改别名；删除要单独一个按钮，不能蹭行的 onClick。
      endActions: [
        MiuixIconButton(
          onPressed: () => _edit(i),
          child: const MiuixAppIcon(
            AppIconNames.rename,
            fallback: Icons.drive_file_rename_outline,
            size: 20,
          ),
        ),
        MiuixIconButton(
          onPressed: () => _remove(i),
          child: const MiuixAppIcon(
            AppIconNames.delete,
            fallback: Icons.close,
            size: 20,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final list = widget.models;
    final enabledCount = list.where((m) => m.enabled).length;

    // 首字母正序：分组渲染 + 右侧 A-Z 条。
    final grouped = _sort == ModelsSortMode.alphabet && list.isNotEmpty;
    final groups = grouped ? groupModelIndices(list) : const <ModelGroup>[];
    final letters = [for (final g in groups) g.letter];

    return Material(
      type: MaterialType.transparency,
      child: MiuixScaffold(
        containerColor: colors.surface,
        topBar: MiuixBlurTopBar(
          scrollBehavior: _behavior,
          title: l10n.exposedModelsTitle,
          navigationIcon: MiuixIconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const MiuixAppIcon(
              AppIconNames.back,
              fallback: Icons.arrow_back,
            ),
          ),
          actions: [
            // 排序 / 拉取 / 手动加：顶栏三个动作。
            MiuixIconButton(
              onPressed: _pickSort,
              child: const MiuixAppIcon(
                AppIconNames.sort,
                fallback: Icons.sort_by_alpha,
              ),
            ),
            MiuixIconButton(
              onPressed: _busy ? null : _fetch,
              child: _busy
                  ? const MiuixCircularProgressIndicator(
                      size: 20,
                      strokeWidth: 2,
                    )
                  : const MiuixAppIcon(
                      AppIconNames.download,
                      fallback: Icons.cloud_download_outlined,
                    ),
            ),
            MiuixIconButton(
              onPressed: _addManually,
              child: const MiuixAppIcon(AppIconNames.add, fallback: Icons.add),
            ),
          ],
        ),
        content: (padding) => MiuixScrollBehaviorListener(
          behavior: _behavior,
          child: Stack(
            children: [
              SingleChildScrollView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(
                  16,
                  padding.top + 8,
                  16 + (grouped ? 24 : 0),
                  40,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MiuixInfoCard(text: l10n.modelsPageHint),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: MiuixSmallTitle(
                              l10n.exposedModelsTitle,
                              insideMargin: EdgeInsets.zero,
                            ),
                          ),
                          MiuixText(
                            l10n.modelCountLabel('$enabledCount'),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurfaceVariantSummary,
                          ),
                        ],
                      ),
                    ),
                    if (list.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: MiuixText(
                          l10n.noExposedModels,
                          fontSize: 13,
                          color: colors.onSurfaceVariantSummary,
                        ),
                      )
                    else if (!grouped)
                      MiuixGroupCard(
                        insideMargin: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (var i = 0; i < list.length; i++) ...[
                              if (i > 0) const MiuixHorizontalDivider(),
                              _row(i, list),
                            ],
                          ],
                        ),
                      )
                    else
                      for (final group in groups)
                        Padding(
                          key: _groupKeys.putIfAbsent(
                            group.letter,
                            () => GlobalKey(),
                          ),
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                                child: MiuixText(
                                  group.letter,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: colors.primary,
                                ),
                              ),
                              MiuixGroupCard(
                                insideMargin: EdgeInsets.zero,
                                child: Column(
                                  children: [
                                    for (
                                      var k = 0;
                                      k < group.indices.length;
                                      k++
                                    ) ...[
                                      if (k > 0)
                                        const MiuixHorizontalDivider(),
                                      _row(group.indices[k], list),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
              if (grouped)
                Positioned(
                  right: 0,
                  top: padding.top + 60,
                  bottom: 24,
                  child: AzIndexBar(
                    letters: letters,
                    active: _activeLetter,
                    onSelected: _jumpToLetter,
                    color: colors.onSurfaceVariantSummary,
                    activeColor: colors.primary,
                    bubbleColor: colors.primary,
                    bubbleTextColor: colors.onPrimary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 对话框里的「对外名称 + 上游模型」两栏输入（miuix 版），新增和改别名共用。
///
/// 两个 controller 由这个 State 自己建、自己释放，草稿通过回调回写给调用方，
/// 见 [MiuixUpstreamModelsPage._modelDialog] 的注释。
class _MiuixModelDialogBody extends StatefulWidget {
  const _MiuixModelDialogBody({
    this.initial,
    required this.onPublicChanged,
    required this.onTargetChanged,
    required this.onContextChanged,
    required this.onOutputChanged,
  });

  final ModelEntry? initial;
  final ValueChanged<String> onPublicChanged;
  final ValueChanged<String> onTargetChanged;
  final ValueChanged<String> onContextChanged;
  final ValueChanged<String> onOutputChanged;

  @override
  State<_MiuixModelDialogBody> createState() => _MiuixModelDialogBodyState();
}

class _MiuixModelDialogBodyState extends State<_MiuixModelDialogBody> {
  late final TextEditingController _public;
  late final TextEditingController _target;
  late final TextEditingController _context;
  late final TextEditingController _output;

  @override
  void initState() {
    super.initState();
    _public = TextEditingController(text: widget.initial?.publicName ?? '');
    _target = TextEditingController(text: widget.initial?.target ?? '');
    final n = widget.initial?.contextLength ?? 0;
    _context = TextEditingController(text: n > 0 ? '$n' : '');
    final o = widget.initial?.maxOutputTokens ?? 0;
    _output = TextEditingController(text: o > 0 ? '$o' : '');
    // 一进来先把初始值交出去：用户不动输入框直接点确定时草稿才是对的。
    widget.onPublicChanged(_public.text);
    widget.onTargetChanged(_target.text);
    widget.onContextChanged(_context.text);
    widget.onOutputChanged(_output.text);
  }

  @override
  void dispose() {
    _public.dispose();
    _target.dispose();
    _context.dispose();
    _output.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MiuixTextField(
          controller: _public,
          label: l10n.modelAliasLabel,
          autofocus: true,
          singleLine: true,
          onChanged: widget.onPublicChanged,
        ),
        const SizedBox(height: 12),
        MiuixTextField(
          controller: _target,
          label: l10n.modelTargetLabel,
          singleLine: true,
          onChanged: widget.onTargetChanged,
        ),
        const SizedBox(height: 12),
        MiuixTextField(
          controller: _context,
          label: l10n.modelContextLabel,
          singleLine: true,
          keyboardType: TextInputType.number,
          onChanged: widget.onContextChanged,
        ),
        // MiuixTextField 没有 helper 槽位，说明文字单起一行小字。
        const SizedBox(height: 6),
        MiuixText(
          l10n.modelContextHelper,
          fontSize: 12,
          color: colors.onSurfaceVariantSummary,
        ),
        const SizedBox(height: 12),
        MiuixTextField(
          controller: _output,
          label: l10n.modelOutputLabel,
          singleLine: true,
          keyboardType: TextInputType.number,
          onChanged: widget.onOutputChanged,
        ),
        const SizedBox(height: 6),
        MiuixText(
          l10n.modelOutputHelper,
          fontSize: 12,
          color: colors.onSurfaceVariantSummary,
        ),
      ],
    );
  }
}
