// lib/ui/dsh_plugins_page.dart
//
// dsh 插件管理（Material 版）。与 miuix 版同一份数据、同一套分组 / 搜索 /
// 折叠行为（布局照 KernelSU 的模块页）：搜索框 → 可折叠分组 → 一卡一插件，
// 卡片里描述默认两行、点开看全部，右侧开关，底部是安装 / 卸载。
// miuix 版在 `ui/miuix/miuix_dsh_plugins_page.dart`。

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/lab/dsh_plugins.dart';
import '../services/lab/dsh_service.dart';
import '../widgets/app_toast.dart';
import '../widgets/expressive_app_bar.dart' show MorphIconButton;
import '../widgets/frosted_page_bar.dart';

class DshPluginsPage extends StatefulWidget {
  const DshPluginsPage({super.key, @visibleForTesting this.debugItems});

  /// 测试用：直接给定列表，跳过 npm / 文件系统（布局与折叠的回归用）。
  @visibleForTesting
  final List<ManagedDshPlugin>? debugItems;

  @override
  State<DshPluginsPage> createState() => _DshPluginsPageState();
}

class _DshPluginsPageState extends State<DshPluginsPage> {
  final DshPluginsService _plugins = DshPluginsService.instance;
  final TextEditingController _search = TextEditingController();
  List<ManagedDshPlugin> _items = const <ManagedDshPlugin>[];
  bool _loading = true;
  bool _ready = false;

  final Set<String> _collapsed = <String>{};
  final Set<String> _expanded = <String>{};
  final Set<String> _working = <String>{};

  @override
  void initState() {
    super.initState();
    final debug = widget.debugItems;
    if (debug != null) {
      _items = _sorted(debug);
      _ready = true;
      _loading = false;
      return;
    }
    _plugins.init(DshService.instance).then((_) => _load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool spinner = false}) async {
    final l10n = AppLocalizations.of(context);
    if (spinner) setState(() => _loading = true);
    _ready = DshService.instance.installed;
    if (_ready) await _plugins.refresh();
    final items = _ready
        ? await _plugins.managed(nameOf: (spec) => _title(l10n, spec))
        : const <ManagedDshPlugin>[];
    if (!mounted) return;
    setState(() {
      _items = _sorted(items);
      _loading = false;
    });
  }

  String _title(AppLocalizations l10n, DshPluginSpec spec) =>
      switch (spec.id) {
        DshPluginId.messageEdit => l10n.labDshPluginMessageEdit,
        DshPluginId.computerUse => l10n.labDshPluginComputerUse,
        DshPluginId.androidControl => l10n.labDshPluginAndroid,
      };

  String _desc(AppLocalizations l10n, DshPluginSpec spec) =>
      switch (spec.id) {
        DshPluginId.messageEdit => l10n.labDshPluginMessageEditDesc,
        DshPluginId.computerUse => l10n.labDshPluginComputerUseDesc,
        DshPluginId.androidControl => l10n.labDshPluginAndroidDesc,
      };

  static List<ManagedDshPlugin> _sorted(List<ManagedDshPlugin> items) {
    int rank(ManagedDshPlugin p) => p.installed ? (p.enabled ? 0 : 1) : 2;
    return [...items]..sort((a, b) {
      final delta = rank(a).compareTo(rank(b));
      return delta != 0 ? delta : a.package.compareTo(b.package);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final query = _search.text.trim();
    final matched = [
      for (final item in _items)
        if (item.matches(query)) item,
    ];
    final official = [
      for (final item in matched)
        if (!item.isThirdParty) item,
    ];
    final thirdParty = [
      for (final item in matched)
        if (item.isThirdParty) item,
    ];
    final enabledCount = [
      for (final item in _items)
        if (item.enabled) item,
    ].length;

    return AnimatedBuilder(
      animation: _plugins,
      builder: (context, _) => FrostedBarPage(
        title: l10n.pluginManagerTitle,
        actions: [
          MorphIconButton(
            icon: Icons.refresh,
            iconSize: 22,
            tooltip: l10n.pluginManagerRefresh,
            transparent: true,
            onTap: _loading ? null : () => _load(spinner: true),
          ),
          MorphIconButton(
            icon: Icons.add_circle_outline,
            iconSize: 22,
            tooltip: l10n.pluginManagerInstallTitle,
            transparent: true,
            onTap: _ready ? _showInstall : null,
          ),
        ],
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            frostedPageBarInset(context) + 8,
            16,
            32,
          ),
          children: [
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: l10n.pluginManagerSearchClear,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                      ),
                hintText: l10n.pluginManagerSearch,
                isDense: true,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (!_ready) ...[
              _Placeholder(text: l10n.pluginManagerNotReady),
            ] else if (_loading) ...[
              const SizedBox(height: 60),
              const Center(child: CircularProgressIndicator()),
            ] else if (matched.isEmpty) ...[
              _Placeholder(
                text: query.isEmpty
                    ? l10n.pluginManagerEmpty
                    : l10n.pluginManagerNoMatch,
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
                child: Text(
                  l10n.pluginManagerOverview('$enabledCount', '${_items.length}'),
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
              // 空分组不占位：只装了一个内置插件时不该冒出「第三方」这个空标题。
              if (official.isNotEmpty) ...[
                _sectionHeader('builtin', l10n.pluginManagerOfficial, official.length),
                _sectionBody('builtin', official, query),
              ],
              if (thirdParty.isNotEmpty) ...[
                _sectionHeader(
                  'third',
                  l10n.pluginManagerDescTitle,
                  thirdParty.length,
                ),
                _sectionBody('third', thirdParty, query),
              ],
              const SizedBox(height: 12),
              Text(
                l10n.pluginManagerRestartHint,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String key, String title, int count) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final collapsed = _collapsed.contains(key);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() {
          if (!_collapsed.remove(key)) _collapsed.add(key);
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Row(
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: cs.onSecondaryContainer,
                  ),
                ),
              ),
              const Spacer(),
              AnimatedRotation(
                turns: collapsed ? 0 : 0.5,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: Icon(
                  Icons.expand_more,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionBody(
    String key,
    List<ManagedDshPlugin> items,
    String query,
  ) {
    // 搜索时强制展开：结果藏在折叠里等于没有搜索。
    final collapsed = query.isEmpty && _collapsed.contains(key);
    return IgnorePointer(
      // 收起时高度为 0，但子树还在：不挡点击、不进读屏。
      ignoring: collapsed,
      child: ExcludeSemantics(
        excluding: collapsed,
        child: ClipRect(
          child: AnimatedAlign(
            alignment: Alignment.topCenter,
            heightFactor: collapsed ? 0 : 1,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: Column(
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildCard(item),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(ManagedDshPlugin plugin) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final title = plugin.displayName ?? plugin.package;
    final spec = specForPackage(plugin.package);
    final description = plugin.description.isNotEmpty
        ? plugin.description
        : (spec == null ? '' : _desc(l10n, spec));
    final expanded = _expanded.contains(plugin.package);
    final working = plugin.busy || _working.contains(plugin.package);

    void toggleExpanded() {
      setState(() {
        if (!_expanded.remove(plugin.package)) _expanded.add(plugin.package);
      });
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: plugin.enabled
                        ? cs.primary
                        : cs.secondaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    plugin.enabled
                        ? Icons.check_rounded
                        : (plugin.recommended
                              ? Icons.layers_outlined
                              : Icons.extension_outlined),
                    size: 19,
                    color: plugin.enabled ? cs.onPrimary : cs.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: toggleExpanded,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (plugin.version.isNotEmpty) 'v${plugin.version}',
                            plugin.recommended
                                ? l10n.pluginManagerOfficial
                                : l10n.pluginManagerCustom,
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (working)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch(
                    value: plugin.enabled,
                    onChanged: plugin.supportedOnThisHost
                        ? (v) => _toggle(plugin, v)
                        : null,
                  ),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              _ExpandableDescription(
                text: description,
                expanded: expanded,
                onToggle: toggleExpanded,
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.45,
                  color: cs.onSurfaceVariant,
                ),
                linkColor: cs.primary,
                expandLabel: l10n.pluginManagerExpand,
                collapseLabel: l10n.pluginManagerCollapse,
              ),
            ],
            if (plugin.displayName != null) ...[
              const SizedBox(height: 6),
              Text(
                plugin.package,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
            if (plugin.error != null) ...[
              const SizedBox(height: 6),
              Text(
                plugin.error!,
                style: TextStyle(fontSize: 12, height: 1.4, color: cs.error),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _statusLine(l10n, plugin, working),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: plugin.requiredHost != null
                          ? cs.error
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ),
                if (!plugin.installed && plugin.supportedOnThisHost)
                  _action(
                    l10n.pluginManagerInstall,
                    working ? null : () => _install(plugin),
                  ),
                if (plugin.installed)
                  _action(
                    l10n.pluginManagerUninstall,
                    working ? null : () => _confirmUninstall(plugin),
                    destructive: true,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(String label, VoidCallback? onPressed, {bool destructive = false}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          foregroundColor: destructive ? cs.error : cs.primary,
          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
        ),
        child: Text(label),
      ),
    );
  }

  String _statusLine(
    AppLocalizations l10n,
    ManagedDshPlugin plugin,
    bool working,
  ) {
    if (working) return l10n.pluginManagerInstalling;
    final host = plugin.requiredHost;
    if (host != null) return l10n.pluginManagerOnlyOn(host);
    if (!plugin.installed) return l10n.pluginManagerNotInstalled;
    if (!plugin.enabled) return l10n.pluginManagerDisabled;
    return l10n.pluginManagerEnabledState;
  }

  Future<void> _toggle(ManagedDshPlugin plugin, bool value) async {
    if (value && !plugin.installed) {
      await _install(plugin);
      return;
    }
    await _run(plugin.package, () {
      return _plugins.setPackageEnabled(plugin.package, value);
    });
  }

  Future<void> _install(ManagedDshPlugin plugin) =>
      _run(plugin.package, () => _plugins.installPackage(plugin.package));

  Future<void> _run(String package, Future<bool> Function() action) async {
    if (_working.contains(package)) return;
    setState(() => _working.add(package));
    final ok = await action();
    if (!mounted) return;
    setState(() => _working.remove(package));
    if (!ok) {
      final l10n = AppLocalizations.of(context);
      final reason = _plugins.errorOf(package);
      showAppToast(
        context,
        reason == null
            ? l10n.labDshPluginFailed
            : '${l10n.labDshPluginFailed}：$reason',
        error: true,
      );
    }
    await _load();
  }

  Future<void> _showInstall() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.pluginManagerInstallTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.pluginManagerPackageHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(l10n.pluginManagerInstall),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return; // 取消
    if (name.isEmpty) {
      if (!mounted) return;
      showAppToast(context, l10n.pluginManagerPackageEmpty);
      return;
    }
    if (!mounted) return;
    await _run(name, () => _plugins.installPackage(name));
  }

  Future<void> _confirmUninstall(ManagedDshPlugin plugin) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.pluginManagerUninstall),
        content: Text(l10n.pluginManagerUninstallConfirm(plugin.package)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.pluginManagerUninstall),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(plugin.package, () {
      return _plugins.uninstallPackage(plugin.package);
    });
  }
}

/// 描述文字：默认两行，**量出来真的放不下时**才露「展开」（按字符数猜会在
/// 中英文混排上翻车）；展开后给「收起」。
class _ExpandableDescription extends StatelessWidget {
  const _ExpandableDescription({
    required this.text,
    required this.expanded,
    required this.onToggle,
    required this.style,
    required this.linkColor,
    required this.expandLabel,
    required this.collapseLabel,
  });

  final String text;
  final bool expanded;
  final VoidCallback onToggle;
  final TextStyle? style;
  final Color linkColor;
  final String expandLabel;
  final String collapseLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: 2,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: overflows ? onToggle : null,
              child: AnimatedSize(
                alignment: Alignment.topLeft,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: Text(
                  text,
                  style: style,
                  maxLines: expanded ? null : 2,
                  overflow: expanded ? TextOverflow.clip : TextOverflow.ellipsis,
                ),
              ),
            ),
            if (overflows || expanded)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    expanded ? collapseLabel : expandLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: linkColor,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          text,
          style: TextStyle(height: 1.5, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}
