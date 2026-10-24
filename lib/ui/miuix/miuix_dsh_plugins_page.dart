// lib/ui/miuix/miuix_dsh_plugins_page.dart
//
// dsh 插件管理（miuix 版），布局照 KernelSU 的模块页（ModuleMiuix.kt）：
//   搜索框 → 可折叠的分组标题（内置 / 第三方）→ 一卡一插件。
// 卡片 = 名称 + 版本/来源 + 描述（默认两行，点卡片展开）+ 右侧开关，
// 底部一行是状态与安装 / 卸载。分组标题点一下就收起，搜索时强制展开
// （不然搜出来的东西藏在折叠里，等于没有搜索）。
//
// 插件服务的理解（见 `services/lab/dsh_plugins.dart`）：
//   · 开关写的是 `profiles/web/package.json` 的 `dsh.profile.bundles`，
//     改完会重启 dsh（插件树是启动时装载的）；
//   · 卸载才是真删包；停用不动磁盘上的 node_modules，下次启用不用重下；
//   · 没下载过的包把开关拨开 = 安装一次，不是只写个名字进 bundles。
// 排序：启用 → 已装停用 → 未装，同级按包名 —— 装了才可控。

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField;

import '../../l10n/app_localizations.dart';
import '../../services/lab/dsh_plugins.dart';
import '../../services/lab/dsh_service.dart';
import '../../widgets/miuix/miuix_app_icon.dart';
import '../../widgets/miuix/miuix_blur_top_bar.dart';
import '../../widgets/miuix/miuix_dialog.dart';
import '../../widgets/miuix/miuix_group_card.dart';
import '../../widgets/miuix/miuix_text_field.dart';
import '../../widgets/miuix/miuix_toast.dart';

class MiuixDshPluginsPage extends StatefulWidget {
  const MiuixDshPluginsPage({super.key, @visibleForTesting this.debugItems});

  /// 测试用：直接给定列表，跳过 npm / 文件系统（布局与折叠的回归用）。
  @visibleForTesting
  final List<ManagedDshPlugin>? debugItems;

  @override
  State<MiuixDshPluginsPage> createState() => _MiuixDshPluginsPageState();
}

class _MiuixDshPluginsPageState extends State<MiuixDshPluginsPage> {
  final DshPluginsService _plugins = DshPluginsService.instance;
  final TextEditingController _search = TextEditingController();
  List<ManagedDshPlugin> _items = const <ManagedDshPlugin>[];
  bool _loading = true;
  bool _ready = false;

  /// 已收起的分组键（`builtin` / `third`）。
  final Set<String> _collapsed = <String>{};

  /// 描述已展开的包名。
  final Set<String> _expanded = <String>{};

  /// 正在跑 npm 的包：服务里的 busy 要等这次快照刷新后才看得到，
  /// 本地先记一份，卡片上的转圈立刻就能出来。
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
    final colors = MiuixTheme.of(context).colors;
    final query = _search.text.trim();
    final matched = [
      for (final item in _items)
        if (item.matches(query)) item,
    ];
    final groups = <_PluginGroup>[
      _PluginGroup(
        key: 'builtin',
        title: l10n.pluginManagerOfficial,
        items: [
          for (final item in matched)
            if (!item.isThirdParty) item,
        ],
      ),
      _PluginGroup(
        key: 'third',
        title: l10n.pluginManagerDescTitle,
        items: [
          for (final item in matched)
            if (item.isThirdParty) item,
        ],
      ),
    ];
    final enabledCount = [
      for (final item in _items)
        if (item.enabled) item,
    ].length;

    return AnimatedBuilder(
      animation: _plugins,
      builder: (context, _) => Material(
        type: MaterialType.transparency,
        child: MiuixScaffold(
          containerColor: colors.surface,
          topBar: MiuixBlurTopBar(
            // 计数放在下面那行统计里：标题行放大后带一长串数字会被截成
            // 「dsh 插件 · 1 个…」，反而更难看。
            title: l10n.pluginManagerTitle,
            navigationIcon: MiuixIconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const MiuixAppIcon(
                AppIconNames.back,
                fallback: Icons.arrow_back,
              ),
            ),
            actions: [
              MiuixIconButton(
                onPressed: _loading ? null : () => _load(spinner: true),
                child: const MiuixAppIcon(
                  AppIconNames.refresh,
                  fallback: Icons.refresh,
                ),
              ),
              MiuixIconButton(
                onPressed: _ready ? _showInstall : null,
                child: const MiuixAppIcon(
                  AppIconNames.addCircle,
                  fallback: Icons.add_circle_outline,
                ),
              ),
            ],
          ),
          content: (padding) => ListView(
            padding: EdgeInsets.only(
              top: padding.top,
              left: 16,
              right: 16,
              bottom: 28 + padding.bottom,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 6),
                child: MiuixTextField(
                  controller: _search,
                  label: l10n.pluginManagerSearch,
                  useLabelAsPlaceholder: true,
                  singleLine: true,
                  textInputAction: TextInputAction.search,
                  leadingIcon: const MiuixAppIcon(
                    AppIconNames.search,
                    fallback: Icons.search,
                    size: 20,
                  ),
                  trailingIcon: query.isEmpty
                      ? null
                      : MiuixIconButton(
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                          child: const MiuixAppIcon(
                            AppIconNames.close,
                            fallback: Icons.close,
                            size: 18,
                          ),
                        ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (!_ready) ...[
                const SizedBox(height: 10),
                _Placeholder(text: l10n.pluginManagerNotReady),
              ] else if (_loading) ...[
                const SizedBox(height: 80),
                const Center(child: CircularProgressIndicator()),
              ] else if (matched.isEmpty) ...[
                const SizedBox(height: 10),
                _Placeholder(
                  text: query.isEmpty
                      ? l10n.pluginManagerEmpty
                      : l10n.pluginManagerNoMatch,
                ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
                  child: MiuixText(
                    l10n.pluginManagerOverview(
                      '$enabledCount',
                      '${_items.length}',
                    ),
                    fontSize: 12,
                    color: colors.onSurfaceVariantSummary,
                  ),
                ),
                for (final group in groups)
                  if (group.items.isNotEmpty) ...[
                    _sectionHeader(
                      group,
                      // 搜索时强制展开：结果藏在折叠里等于没有搜索。
                      collapsed: query.isEmpty && _collapsed.contains(group.key),
                      colors: colors,
                    ),
                    IgnorePointer(
                      // 收起时高度为 0，但子树还在：不挡点击、不进读屏，
                      // 否则折叠起来的卡片还能被 tab 到。
                      ignoring: query.isEmpty &&
                          _collapsed.contains(group.key),
                      child: ExcludeSemantics(
                        excluding: query.isEmpty &&
                            _collapsed.contains(group.key),
                        child: ClipRect(
                          child: AnimatedAlign(
                            alignment: Alignment.topCenter,
                            heightFactor:
                                query.isEmpty &&
                                    _collapsed.contains(group.key)
                                ? 0
                                : 1,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            child: Column(
                              children: [
                                for (final plugin in group.items)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _buildCard(plugin),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                  child: MiuixText(
                    l10n.pluginManagerRestartHint,
                    fontSize: 12,
                    color: colors.onSurfaceVariantSummary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 分组标题：标题 + 数量胶囊 + 展开/收起箭头，整行可点。
  Widget _sectionHeader(
    _PluginGroup group, {
    required bool collapsed,
    required MiuixColors colors,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          if (!_collapsed.remove(group.key)) _collapsed.add(group.key);
        }),
        child: Row(
          children: [
            MiuixText(
              group.title,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariantSummary,
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: ShapeDecoration(
                color: colors.secondaryContainer,
                shape: const MiuixSquircleBorder(cornerRadius: 8),
              ),
              child: MiuixText(
                '${group.items.length}',
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: colors.onSecondaryContainer,
              ),
            ),
            const Spacer(),
            AnimatedRotation(
              // chevronForward 本来是「>」：展开时转到「∧」、收起时转到「∨」。
              turns: collapsed ? 0.25 : -0.25,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: MiuixAppIcon(
                AppIconNames.forward,
                fallback: Icons.chevron_right,
                size: 18,
                color: colors.onSurfaceVariantSummary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(ManagedDshPlugin plugin) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final title = plugin.displayName ?? plugin.package;
    final showPackage = plugin.displayName != null;
    final spec = specForPackage(plugin.package);
    final description = plugin.description.isNotEmpty
        ? plugin.description
        : (spec == null ? '' : _desc(l10n, spec));
    final expanded = _expanded.contains(plugin.package);
    final working = plugin.busy || _working.contains(plugin.package);

    void toggleExpanded() => setState(() {
      if (!_expanded.remove(plugin.package)) _expanded.add(plugin.package);
    });

    return MiuixGroupCard(
      insideMargin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MiuixBasicComponent(
            insideMargin: const EdgeInsets.fromLTRB(16, 12, 12, 8),
            title: title,
            summary: _metaLine(l10n, plugin),
            startAction: Padding(
              padding: const EdgeInsets.only(right: 2),
              child: _glyph(plugin, colors),
            ),
            endActions: [
              if (working)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                MiuixSwitch(
                  value: plugin.enabled,
                  enabled: plugin.supportedOnThisHost,
                  onChanged: (v) => _toggle(plugin, v),
                ),
            ],
          ),
          if (description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _ExpandableDescription(
                text: description,
                expanded: expanded,
                onToggle: toggleExpanded,
                color: colors.onSurfaceVariantSummary,
                linkColor: colors.primary,
                expandLabel: l10n.pluginManagerExpand,
                collapseLabel: l10n.pluginManagerCollapse,
              ),
            ),
          if (showPackage)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: MiuixText(
                plugin.package,
                fontSize: 11,
                color: colors.onSurfaceVariantSummary,
              ),
            ),
          if (plugin.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: MiuixText(
                plugin.error!,
                fontSize: 12,
                height: 1.4,
                color: colors.error,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: MiuixText(
                    _statusLine(l10n, plugin, working),
                    fontSize: 12,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    color: plugin.requiredHost != null
                        ? colors.error
                        : colors.onSurfaceVariantSummary,
                  ),
                ),
                if (!plugin.installed && plugin.supportedOnThisHost)
                  _actionButton(
                    l10n.pluginManagerInstall,
                    working ? null : () => _install(plugin),
                  ),
                if (plugin.installed)
                  _actionButton(
                    l10n.pluginManagerUninstall,
                    working ? null : () => _confirmUninstall(plugin),
                    destructive: true,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 卡片左侧的小方块图标：启用先蓝，停用/未装用中性色。
  Widget _glyph(ManagedDshPlugin plugin, MiuixColors colors) {
    final on = plugin.enabled;
    return Container(
      width: 34,
      height: 34,
      decoration: ShapeDecoration(
        color: on ? colors.primary : colors.secondaryContainer,
        shape: const MiuixSquircleBorder(cornerRadius: 10),
      ),
      child: Center(
        child: MiuixAppIcon(
          on
              ? AppIconNames.check
              : (plugin.recommended ? AppIconNames.layers : AppIconNames.store),
          fallback: on ? Icons.check_rounded : Icons.extension_outlined,
          size: 19,
          color: on ? colors.onPrimary : colors.onSecondaryContainer,
        ),
      ),
    );
  }

  Widget _actionButton(
    String label,
    VoidCallback? onPressed, {
    bool destructive = false,
  }) {
    final colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: MiuixTextButton(
        label,
        onPressed: onPressed,
        enabled: onPressed != null,
        minWidth: 0,
        minHeight: 30,
        cornerRadius: 10,
        insideMargin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
        colors: destructive
            ? MiuixButtonColors(
                color: colors.errorContainer,
                disabledColor: colors.secondaryContainer,
                contentColor: colors.onErrorContainer,
                disabledContentColor: colors.disabledOnSecondaryVariant,
              )
            : null,
      ),
    );
  }

  /// 副标题：版本 · 来源（内置 / 第三方）。
  String _metaLine(AppLocalizations l10n, ManagedDshPlugin plugin) {
    final head = <String>[
      if (plugin.version.isNotEmpty) 'v${plugin.version}',
      plugin.recommended ? l10n.pluginManagerOfficial : l10n.pluginManagerCustom,
    ].join(' · ');
    return head;
  }

  /// 底部左侧的状态文案（右对齐按钮的那一列）。
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
    // 没下载过的包拨开开关 = 装一次（服务里也做了这个兜底）。
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

  /// 跑一次会改磁盘的操作：卡片上转圈、失败弹原因、完事重新读一遍现状。
  Future<void> _run(String package, Future<bool> Function() action) async {
    if (_working.contains(package)) return;
    setState(() => _working.add(package));
    final ok = await action();
    if (!mounted) return;
    setState(() => _working.remove(package));
    if (!ok) {
      final l10n = AppLocalizations.of(context);
      final reason = _plugins.errorOf(package);
      showMiuixToast(
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
    final name = await showMiuixDialog<String>(
      context: context,
      title: l10n.pluginManagerInstallTitle,
      content: MiuixTextField(
        controller: controller,
        label: l10n.pluginManagerPackageHint,
        useLabelAsPlaceholder: true,
        singleLine: true,
        autofocus: true,
      ),
      actions: [
        MiuixDialogAction(
          label: l10n.commonCancel,
          onPressed: (ctx) => Navigator.of(ctx).pop(),
        ),
        MiuixDialogAction(
          label: l10n.pluginManagerInstall,
          primary: true,
          onPressed: (ctx) => Navigator.of(ctx).pop(controller.text.trim()),
        ),
      ],
    );
    controller.dispose();
    if (name == null) return; // 取消
    if (name.isEmpty) {
      // 名字都没填就点安装：别静默什么都不发生
      if (!mounted) return;
      showMiuixToast(context, l10n.pluginManagerPackageEmpty);
      return;
    }
    if (!mounted) return;
    await _run(name, () => _plugins.installPackage(name));
  }

  Future<void> _confirmUninstall(ManagedDshPlugin plugin) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showMiuixDialog<bool>(
      context: context,
      title: l10n.pluginManagerUninstall,
      content: Text(
        l10n.pluginManagerUninstallConfirm(plugin.package),
      ),
      actions: [
        MiuixDialogAction(
          label: l10n.commonCancel,
          onPressed: (ctx) => Navigator.of(ctx).pop(false),
        ),
        MiuixDialogAction(
          label: l10n.pluginManagerUninstall,
          destructive: true,
          onPressed: (ctx) => Navigator.of(ctx).pop(true),
        ),
      ],
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
    required this.color,
    required this.linkColor,
    required this.expandLabel,
    required this.collapseLabel,
  });

  final String text;
  final bool expanded;
  final VoidCallback onToggle;
  final Color color;
  final Color linkColor;
  final String expandLabel;
  final String collapseLabel;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 13, height: 1.45, color: color);
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
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
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
              ),
          ],
        );
      },
    );
  }
}

/// 一个分组（标题 + 成员），渲染时会跳过空组。
class _PluginGroup {
  const _PluginGroup({
    required this.key,
    required this.title,
    required this.items,
  });

  final String key;
  final String title;
  final List<ManagedDshPlugin> items;
}

/// 空态 / 不可用态：一张卡里一行说明文字。
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixGroupCard(
      insideMargin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: MiuixText(
          text,
          fontSize: 14,
          height: 1.5,
          color: colors.onSurfaceVariantSummary,
        ),
      ),
    );
  }
}
