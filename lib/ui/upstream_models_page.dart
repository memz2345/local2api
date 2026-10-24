import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/widgets/native_text_context_menu.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/models_sort_store.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/widgets/app_toast.dart';
import 'package:local2api/widgets/az_index_bar.dart';
import 'package:local2api/widgets/expressive_app_bar.dart';
import 'package:local2api/widgets/frosted_page_bar.dart';
import 'package:local2api/widgets/predictive_back_sheet.dart';

/// 上游的「模型」页 —— 从上游编辑页的「模型」行进来的独立一页。
///
/// 以前拉模型 / 别名 / 勾选暴露哪几个都挤在上游编辑页的表单里，字段一多就
/// 挤成一团；CMFA 的做法是「模型」自成一行、点进去单独一页，这里照它做。
///
/// ⚠️ [models] 传的是父页那条列表**对象本身**，这一页原地增删改，再用
/// [onChanged] 让父页刷新「N 个模型」那行。真正写盘仍然只在父页右上角
/// 「保存」时发生，所以这一页返回键退出 = 放弃改动？不 —— 改动留在父页的
/// 草稿里，父页不保存就一起丢，语义和别的字段一致。
class UpstreamModelsPage extends StatefulWidget {
  const UpstreamModelsPage({
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
  State<UpstreamModelsPage> createState() => _UpstreamModelsPageState();
}

class _UpstreamModelsPageState extends State<UpstreamModelsPage> {
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

  void _toast(String msg) => showAppToast(context, msg);

  /// 滚动时算出「当前顶部停在哪个字母」，驱动索引条高亮。
  void _onScroll() {
    if (!mounted || _sort != ModelsSortMode.alphabet) return;
    final threshold =
        MediaQuery.paddingOf(context).top + kFrostedPageBarHeight + 8;
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
    final targetTop =
        MediaQuery.paddingOf(context).top + kFrostedPageBarHeight + 8;
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

  /// 排序方式选择面板。
  Future<void> _pickSort() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showAppBottomSheet<ModelsSortMode>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
              child: Text(
                l10n.modelsSortTitle,
                style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final mode in ModelsSortMode.values)
              ListTile(
                title: Text(switch (mode) {
                  ModelsSortMode.natural => l10n.modelsSortNatural,
                  ModelsSortMode.alphabet => l10n.modelsSortAlphabet,
                }),
                trailing: mode == _sort
                    ? Icon(
                        Icons.check,
                        color: Theme.of(sheetCtx).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.pop(sheetCtx, mode),
              ),
            const SizedBox(height: 12),
          ],
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
    final selected = {
      for (final m in widget.models)
        if (m.enabled) m.publicName,
    };
    final ok = await showAppBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.fetchedModels('${fetched.length}'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final name in fetched)
                            CheckboxListTile(
                              dense: true,
                              value: selected.contains(name),
                              title: Text(
                                name,
                                style: const TextStyle(fontSize: 14),
                              ),
                              onChanged: (v) => setSheet(
                                () => v == true
                                    ? selected.add(name)
                                    : selected.remove(name),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () => Navigator.pop(sheetCtx, true),
                      child: Text(l10n.confirm),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (ok != true) return;
    final list = widget.models;
    // 已存在的保留，不重复加
    final existing = {for (final m in list) m.publicName};
    for (final name in fetched) {
      if (selected.contains(name) && !existing.contains(name)) {
        list.add(
          ModelEntry(publicName: name, contextLength: contexts[name] ?? 0),
        );
      }
    }
    // 取消勾选的从暴露列表移除（只影响这次拉回来的那批名字）
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
  ///
  /// ⚠️ 抽屉里那两个 controller 归 [_ModelEditorSheet] 自己管：在调用方
  /// `await` 完就 dispose 的话，bottom sheet 的**退场动画还在跑**，
  /// TextField 会再去读一次已释放的 controller → 「used after being
  /// disposed」。路由真正 dispose 时动画已经结束，在那儿释放才安全。
  Future<void> _addManually() async {
    final l10n = AppLocalizations.of(context);
    final added = await showAppBottomSheet<ModelEntry>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ModelEditorSheet(title: l10n.addModelBtn),
    );
    if (added == null) return;
    widget.models.add(added);
    _changed();
  }

  /// 改一个对外模型：对外名 + 上游模型名（别名映射）+ 上下文长度。
  Future<void> _edit(int index) async {
    final l10n = AppLocalizations.of(context);
    final m = widget.models[index];
    final next = await showAppBottomSheet<ModelEntry>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          _ModelEditorSheet(title: l10n.modelAliasLabel, initial: m),
    );
    if (next == null) return;
    setState(() {
      m.publicName = next.publicName;
      m.target = next.target;
      m.contextLength = next.contextLength;
      m.maxOutputTokens = next.maxOutputTokens;
    });
    widget.onChanged?.call();
  }

  void _remove(int index) {
    widget.models.removeAt(index);
    _changed();
  }

  void _toggle(int index, bool value) {
    setState(() => widget.models[index].enabled = value);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final list = widget.models;
    final enabledCount = list.where((m) => m.enabled).length;

    // 首字母正序：分组渲染 + 右侧 A-Z 条。
    final grouped = _sort == ModelsSortMode.alphabet && list.isNotEmpty;
    final groups = grouped ? groupModelIndices(list) : const <ModelGroup>[];
    final letters = [for (final g in groups) g.letter];
    final azPad = grouped ? 24.0 : 0.0;

    return FrostedBarPage(
      title: l10n.exposedModelsTitle,
      actions: [
        MorphIconButton(
          icon: Icons.sort_by_alpha,
          tooltip: l10n.modelsSortTitle,
          transparent: true,
          onTap: _pickSort,
        ),
        MorphIconButton(
          icon: _busy
              ? Icons.hourglass_top_outlined
              : Icons.cloud_download_outlined,
          tooltip: _busy ? l10n.fetchingModels : l10n.fetchModelsBtn,
          transparent: true,
          onTap: _busy ? null : _fetch,
        ),
        MorphIconButton(
          icon: Icons.add,
          tooltip: l10n.addModelBtn,
          transparent: true,
          onTap: _addManually,
        ),
      ],
      child: Stack(
        children: [
          SingleChildScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            padding: EdgeInsets.only(
              top: frostedPageBarInset(context) + 8,
              bottom: 32,
            ),
            child: Padding(
              padding: EdgeInsets.only(right: azPad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HintRow(icon: Icons.info_outline, text: l10n.modelsPageHint),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.exposedModelsTitle,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          l10n.modelCountLabel('$enabledCount'),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: Text(
                        l10n.noExposedModels,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    )
                  else if (!grouped)
                    for (var i = 0; i < list.length; i++)
                      _ModelRow(
                        model: list[i],
                        onToggle: (v) => _toggle(i, v),
                        onEdit: () => _edit(i),
                        onRemove: () => _remove(i),
                      )
                  else
                    for (final group in groups)
                      _GroupBlock(
                        groupKey: _groupKeys.putIfAbsent(
                          group.letter,
                          () => GlobalKey(),
                        ),
                        letter: group.letter,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final i in group.indices)
                              _ModelRow(
                                model: list[i],
                                onToggle: (v) => _toggle(i, v),
                                onEdit: () => _edit(i),
                                onRemove: () => _remove(i),
                              ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
          if (grouped)
            Positioned(
              right: 2,
              top: frostedPageBarInset(context) + 56,
              bottom: 20,
              child: AzIndexBar(
                letters: letters,
                active: _activeLetter,
                onSelected: _jumpToLetter,
                color: cs.onSurfaceVariant,
                activeColor: cs.primary,
                bubbleColor: cs.primary,
                bubbleTextColor: cs.onPrimary,
              ),
            ),
        ],
      ),
    );
  }
}

/// 首字母正序下的一个分组：字母小标题 + 该组的模型行。
class _GroupBlock extends StatelessWidget {
  const _GroupBlock({
    required this.groupKey,
    required this.letter,
    required this.child,
  });

  final GlobalKey groupKey;
  final String letter;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: groupKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
          child: Text(
            letter,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// 顶部说明行：只有图标 + 一句话，不可点。
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

/// 一行一个对外模型：勾选 = 是否暴露，点行改别名，右端删除。
///
/// 同 [_FieldRow] / `CreateConfigPage` 那两行：墨迹要落在行自己的透明
/// Material 上，否则被 [FrostedBarPage] 的页面背景盖住。
class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.model,
    required this.onToggle,
    required this.onEdit,
    required this.onRemove,
  });

  final ModelEntry model;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  static const BorderRadius _shape = BorderRadius.all(Radius.circular(16));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: _shape,
        child: InkWell(
          onTap: onEdit,
          borderRadius: _shape,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
            child: Row(
              children: [
                Checkbox(
                  value: model.enabled,
                  onChanged: (v) => onToggle(v ?? true),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.publicName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (model.target != model.publicName)
                        Text(
                          '→ ${model.target}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                // 配了上下文长度的顺手露一眼（1M / 128K），没配不占位。
                if (model.contextLength > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(10),
                      ),
                    ),
                    child: Text(
                      l10n.modelContextShort(model.contextLabel),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.drive_file_rename_outline, size: 20),
                ),
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 「对外名称 + 上游模型」两栏编辑器，新增和改别名共用。
///
/// 确定时弹回一个 [ModelEntry]，取消弹 null。两个 controller 由这个 State
/// 自己建、自己释放，原因见 [_addManually] 的注释。
class _ModelEditorSheet extends StatefulWidget {
  const _ModelEditorSheet({required this.title, this.initial});

  final String title;
  final ModelEntry? initial;

  @override
  State<_ModelEditorSheet> createState() => _ModelEditorSheetState();
}

class _ModelEditorSheetState extends State<_ModelEditorSheet> {
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
  }

  @override
  void dispose() {
    _public.dispose();
    _target.dispose();
    _context.dispose();
    _output.dispose();
    super.dispose();
  }

  void _submit() {
    final publicName = _public.text.trim();
    if (publicName.isEmpty) return;
    final target = _target.text.trim();
    // 「1,000,000」这种带分隔符的粘贴也认：只取数字部分。
    final digits = _context.text.replaceAll(RegExp(r'[^0-9]'), '');
    final ctxLen = int.tryParse(digits) ?? 0;
    if (digits.isNotEmpty && ctxLen <= 0) return;
    final outDigits = _output.text.replaceAll(RegExp(r'[^0-9]'), '');
    final outLen = int.tryParse(outDigits) ?? 0;
    if (outDigits.isNotEmpty && outLen <= 0) return;
    Navigator.pop(
      context,
      ModelEntry(
        publicName: publicName,
        target: target.isEmpty ? publicName : target,
        contextLength: ctxLen,
        maxOutputTokens: outLen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextField(
                // Windows 上右键弹原生编辑菜单
                contextMenuBuilder: textContextMenuBuilder,
                controller: _public,
                autofocus: true,
                decoration: InputDecoration(labelText: l10n.modelAliasLabel),
              ),
              const SizedBox(height: 12),
              TextField(
                // Windows 上右键弹原生编辑菜单
                contextMenuBuilder: textContextMenuBuilder,
                controller: _target,
                decoration: InputDecoration(labelText: l10n.modelTargetLabel),
              ),
              const SizedBox(height: 12),
              TextField(
                // Windows 上右键弹原生编辑菜单
                contextMenuBuilder: textContextMenuBuilder,
                controller: _context,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.modelContextLabel,
                  hintText: '1000000',
                  helperText: l10n.modelContextHelper,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                // Windows 上右键弹原生编辑菜单
                contextMenuBuilder: textContextMenuBuilder,
                controller: _output,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.modelOutputLabel,
                  hintText: '32000',
                  helperText: l10n.modelOutputHelper,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _submit, child: Text(l10n.confirm)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
