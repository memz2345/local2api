import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField;
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/chat_simulation.dart';
import 'package:local2api/services/character_store.dart';
import 'package:local2api/services/character_voice.dart';
import 'package:local2api/ui/character_card_page.dart'
    show CharacterAvatar, kDefaultCharacterCard;
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/widgets/miuix/miuix_dialog.dart';
import 'package:local2api/widgets/miuix/miuix_field_editor.dart';
import 'package:local2api/widgets/miuix/miuix_field_row.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_info_card.dart';
import 'package:local2api/widgets/miuix/miuix_page_popup_host.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';
import 'package:local2api/widgets/miuix/miuix_text_field.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';
import 'package:provider/provider.dart';

/// 角色卡页（miuix 版，对应 Material 版 `CharacterCardPage`）。
///
/// 「对话模拟」换场景的入口：每张卡是一份「人设提示词 + 预制问答」，
/// 点卡即应用并返回模拟页（pop 出卡片，由模拟页调用
/// [ChatSimController.applyCharacter] 重铺对话）。内置卡（流萤/蕾姆）
/// 不可改；用户卡可以编辑/删除，FAB 创建新角色。
class MiuixCharacterCardPage extends StatefulWidget {
  const MiuixCharacterCardPage({super.key});

  @override
  State<MiuixCharacterCardPage> createState() => _MiuixCharacterCardPageState();
}

class _MiuixCharacterCardPageState extends State<MiuixCharacterCardPage> {
  /// 一级页的可折叠大标题行为（字段持有，dispose 时释放，别在 build 里建）。
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();

  @override
  void dispose() {
    _behavior.state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    final store = context.watch<CharacterStore>();

    // 弹层宿主罩在 Scaffold 外面（编辑页要弹底部抽屉，理由同对话模拟页）
    return MiuixPagePopupHost(
      child: Material(
        type: MaterialType.transparency,
        child: MiuixScaffold(
          containerColor: colors.surface,
          topBar: MiuixBlurTopBar(
            scrollBehavior: _behavior,
            title: l10n.characterTitle,
            navigationIcon: MiuixIconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const MiuixAppIcon(
                AppIconNames.back,
                fallback: Icons.arrow_back,
              ),
            ),
          ),
          floatingActionButton: MiuixFloatingActionButton(
            onPressed: () => _pushEdit(context, store, null),
            child: const MiuixAppIcon(AppIconNames.add, fallback: Icons.add),
          ),
          content: (padding) => MiuixScrollBehaviorListener(
            behavior: _behavior,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(16, padding.top + 4, 16, 120),
              children: [
                MiuixDismissibleInfoCard(
                  id: 'intro.characters',
                  text: l10n.characterIntro,
                ),
                const SizedBox(height: 6),
                // 「默认场景」卡：应用 = 回到无人设的原始状态。
                // 倾斜反馈与仪表盘大卡同款（tilt）。
                MiuixGroupCard(
                  insideMargin: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  feedbackType: MiuixPressFeedbackType.tilt,
                  onPressed: () =>
                      Navigator.of(context).pop(kDefaultCharacterCard),
                  child: Row(
                    children: [
                      CharacterAvatar(
                        name: '',
                        glyph: '·',
                        color: colors.onSurfaceVariantActions,
                        size: 40,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MiuixText(
                              l10n.characterDefault,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            const SizedBox(height: 2),
                            MiuixText(
                              l10n.characterDefaultDesc,
                              fontSize: 12,
                              color: colors.onSurfaceVariantSummary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                for (final c in store.cards) ...[
                  _MiuixCharacterCard(
                    card: c,
                    onTap: () => Navigator.of(context).pop(c),
                    // 内置卡也能编辑（人设微调 / 配音色）：改动存成覆盖，
                    // 覆盖过的内置卡多一颗「重置」回原文。
                    onEdit: () => _pushEdit(context, store, c),
                    onReset: store.isOverridden(c.id)
                        ? () => _resetOverride(context, store, c)
                        : null,
                    onDelete: c.builtin
                        ? null
                        : () => _delete(context, store, c),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static void _pushEdit(
    BuildContext context,
    CharacterStore store,
    CharacterCard? existing,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            MiuixCharacterEditPage(store: store, existing: existing),
      ),
    );
  }

  static Future<void> _resetOverride(
    BuildContext context,
    CharacterStore store,
    CharacterCard card,
  ) async {
    final l10n = AppLocalizations.of(context);
    await store.resetBuiltin(card.id);
    if (!context.mounted) return;
    showMiuixToast(context, l10n.characterOverrideReset);
  }

  static Future<void> _delete(
    BuildContext context,
    CharacterStore store,
    CharacterCard card,
  ) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showMiuixDialog<bool>(
      context: context,
      title: l10n.characterDeleteConfirm(card.name),
      actions: [
        MiuixDialogAction(
          label: l10n.cancel,
          onPressed: (ctx) => Navigator.of(ctx).pop(false),
        ),
        MiuixDialogAction(
          label: l10n.deleteBtn,
          primary: true,
          onPressed: (ctx) => Navigator.of(ctx).pop(true),
        ),
      ],
    );
    if (ok == true) store.remove(card.id);
  }
}

/// 一张角色卡：头像 + 名字（内置徽标）+ 人设预览 + 预制对话数 +
/// 编辑按钮（内置卡也有，改的是覆盖）+ 重置（覆盖过的内置卡）+ 删除。
class _MiuixCharacterCard extends StatelessWidget {
  const _MiuixCharacterCard({
    required this.card,
    required this.onTap,
    this.onEdit,
    this.onReset,
    this.onDelete,
  });

  final CharacterCard card;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onReset;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;

    return MiuixGroupCard(
      insideMargin: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      // 与仪表盘大卡同款的倾斜按压反馈（触点象限 3D 倾斜）。
      feedbackType: MiuixPressFeedbackType.tilt,
      onPressed: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CharacterAvatar(name: card.name, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: MiuixText(
                  card.name,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (card.builtin)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: ShapeDecoration(
                    color: colors.primary.withValues(alpha: 0.14),
                    shape: MiuixSquircleBorder(cornerRadius: 6),
                  ),
                  child: MiuixText(
                    l10n.characterBuiltin,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colors.primary,
                  ),
                ),
              if (onReset != null)
                MiuixIconButton(
                  onPressed: onReset,
                  child: const MiuixAppIcon(
                    'reset',
                    fallback: Icons.restart_alt,
                    size: 18,
                  ),
                ),
              if (onEdit != null)
                MiuixIconButton(
                  onPressed: onEdit,
                  child: const MiuixAppIcon(
                    AppIconNames.edit,
                    fallback: Icons.edit_outlined,
                    size: 18,
                  ),
                ),
              if (onDelete != null)
                MiuixIconButton(
                  onPressed: onDelete,
                  child: const MiuixAppIcon(
                    AppIconNames.delete,
                    fallback: Icons.delete_outline,
                    size: 18,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          MiuixText(
            card.prompt,
            fontSize: 12,
            color: colors.onSurfaceVariantSummary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          MiuixText(
            l10n.characterPresetCount(card.presets.length),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colors.primary,
          ),
        ],
      ),
    );
  }
}

/// 新建 / 编辑角色卡（miuix 版，对应 Material 版 `CharacterEditPage`）。
/// [existing] 为空 = 新建。
class MiuixCharacterEditPage extends StatefulWidget {
  const MiuixCharacterEditPage({super.key, required this.store, this.existing});

  final CharacterStore store;
  final CharacterCard? existing;

  @override
  State<MiuixCharacterEditPage> createState() => _MiuixCharacterEditPageState();
}

class _MiuixCharacterEditPageState extends State<MiuixCharacterEditPage> {
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();

  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _prompt = TextEditingController(
    text: widget.existing?.prompt ?? '',
  );

  /// 音色样本（本地路径）。编辑期间先攒着，保存时随卡写回。
  String _voicePath = '';

  /// 进页时的初值快照：返回时拿来判断「有没有改过」，改过才弹确认框。
  late final String _initialName = widget.existing?.name ?? '';
  late final String _initialPrompt = widget.existing?.prompt ?? '';
  late final String _initialVoice = widget.existing?.voiceSamplePath ?? '';
  late final List<(String, String)> _initialPairs = [
    for (final p
        in widget.existing?.presets ??
            const [ChatPresetPair(user: '', assistant: '')])
      (p.user, p.assistant),
  ];

  /// 「未保存的更改」确认框在途标记（防系统返回 + 顶栏返回连点两弹）。
  bool _confirmingLeave = false;

  @override
  void initState() {
    super.initState();
    _voicePath = widget.existing?.voiceSamplePath ?? '';
  }

  /// 相对进页那一刻有没有动过任何一项（与 _save 的落盘口径一致）。
  bool get _isDirty {
    if (_name.text.trim() != _initialName.trim()) return true;
    if (_prompt.text.trim() != _initialPrompt.trim()) return true;
    if (_voicePath != _initialVoice) return true;
    final current = [
      for (final (u, a) in _pairs)
        if (u.text.trim().isNotEmpty || a.text.trim().isNotEmpty)
          (u.text.trim(), a.text.trim()),
    ];
    final initial = [
      for (final (u, a) in _initialPairs)
        if (u.trim().isNotEmpty || a.trim().isNotEmpty) (u.trim(), a.trim()),
    ];
    if (current.length != initial.length) return true;
    for (var i = 0; i < current.length; i++) {
      if (current[i] != initial[i]) return true;
    }
    return false;
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
      // _save 校验不过只会 toast（名称必填），页面留着不 pop。
      await _save();
    } else {
      Navigator.of(context).pop();
    }
  }

  /// 每组问答两个 controller，成对增删。
  late final List<(TextEditingController, TextEditingController)> _pairs = [
    for (final p
        in widget.existing?.presets ??
            const [ChatPresetPair(user: '', assistant: '')])
      (
        TextEditingController(text: p.user),
        TextEditingController(text: p.assistant),
      ),
  ];

  Future<void> _pickVoice() async {
    try {
      final path = await CharacterVoice.pickAndStore(
        existingPath: _voicePath,
      );
      if (path == null || !mounted) return;
      setState(() => _voicePath = path);
    } catch (e) {
      if (!mounted) return;
      showMiuixToast(
        context,
        '$e'.replaceFirst(RegExp(r'^(Exception:\s*)+'), ''),
        error: true,
      );
    }
  }

  Future<void> _removeVoice() async {
    await CharacterVoice.deleteStored(_voicePath);
    if (!mounted) return;
    setState(() => _voicePath = '');
  }

  /// 人设行里显示的预览：首行 + 省略号（多行提示词压缩成一行）。
  String get _promptPreview {
    final text = _prompt.text.trim();
    if (text.isEmpty) return '';
    final first = text.split('\n').first.trim();
    return text.contains('\n') ? '$first…' : first;
  }

  /// 「名称」行：弹共享字段编辑器改完写回。
  Future<void> _editName() async {
    final l10n = AppLocalizations.of(context);
    final draft = await showMiuixFieldEditor(
      context,
      label: l10n.characterNameLabel,
      initial: _name.text,
      hint: l10n.characterNameHint,
    );
    if (draft == null || !mounted) return;
    setState(() => _name.text = draft);
  }

  /// 「人设提示词」行：多行编辑器（system 提示词整段替换）。
  Future<void> _editPrompt() async {
    final l10n = AppLocalizations.of(context);
    final draft = await showMiuixFieldEditor(
      context,
      label: l10n.characterPromptLabel,
      initial: _prompt.text,
      hint: l10n.characterPromptHint,
      maxLines: 8,
    );
    if (draft == null || !mounted) return;
    setState(() => _prompt.text = draft);
  }

  @override
  void dispose() {
    _behavior.state.dispose();
    _name.dispose();
    _prompt.dispose();
    for (final (u, a) in _pairs) {
      u.dispose();
      a.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      showMiuixToast(context, l10n.characterNeedName);
      return;
    }
    final card = CharacterCard(
      id:
          widget.existing?.id ??
          'user.${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      prompt: _prompt.text.trim(),
      voiceSamplePath: _voicePath,
      // 内置卡编辑必须保留 builtin 标记：丢了会被当作用户卡塞进普通
      // 列表，被内置原版影子掉——音色样本/人设改动全部不生效。
      builtin: widget.existing?.builtin ?? false,
      presets: [
        for (final (u, a) in _pairs)
          if (u.text.trim().isNotEmpty || a.text.trim().isNotEmpty)
            ChatPresetPair(user: u.text.trim(), assistant: a.text.trim()),
      ],
    );
    widget.store.upsert(card);
    Navigator.of(context).pop();
  }

  void _addPair() => setState(
    () => _pairs.add((TextEditingController(), TextEditingController())),
  );

  void _removePair(int i) {
    setState(() {
      _pairs[i].$1.dispose();
      _pairs[i].$2.dispose();
      _pairs.removeAt(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;

    return MiuixPagePopupHost(
      child: Material(
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
              title: widget.existing == null
                  ? l10n.characterNewTitle
                  : l10n.characterEditTitle,
            navigationIcon: MiuixIconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const MiuixAppIcon(
                AppIconNames.back,
                fallback: Icons.arrow_back,
              ),
            ),
            actions: [
              // 保存动作跟 miuix 上游编辑页同一套：右上角 ✔
              MiuixIconButton(
                onPressed: _save,
                child: const MiuixAppIcon(
                  AppIconNames.check,
                  fallback: Icons.check,
                ),
              ),
            ],
          ),
          content: (padding) => MiuixScrollBehaviorListener(
            behavior: _behavior,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(16, padding.top + 8, 16, 40),
              children: [
                // 与上游编辑页同一套「一行一个字段」：点行弹编辑器改那一项。
                MiuixGroupCard(
                  insideMargin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      MiuixFieldRow(
                        iconName: AppIconNames.rename,
                        fallbackIcon: Icons.label_outline,
                        title: l10n.characterNameLabel,
                        value: _name.text.trim().isEmpty
                            ? l10n.notFilled
                            : _name.text,
                        valueIsHint: _name.text.trim().isEmpty,
                        onTap: _editName,
                      ),
                      const MiuixHorizontalDivider(),
                      MiuixFieldRow(
                        iconName: AppIconNames.note,
                        fallbackIcon: Icons.note_add_outlined,
                        title: l10n.characterPromptLabel,
                        value: _promptPreview,
                        valueIsHint: _prompt.text.trim().isEmpty,
                        onTap: _editPrompt,
                      ),
                      const MiuixHorizontalDivider(),
                      // 音色样本（可选）：行尾是「移除」，点行选文件
                      MiuixBasicComponent(
                        title: l10n.characterVoiceLabel,
                        summary: _voicePath.isEmpty
                            ? l10n.notFilled
                            : CharacterVoice.displayName(_voicePath),
                        summaryColor: MiuixBasicComponentColors(
                          color: _voicePath.isEmpty
                              ? colors.onSurfaceVariantSummary
                                  .withValues(alpha: 0.6)
                              : colors.primary,
                          disabledColor: colors.disabledOnSecondaryVariant,
                        ),
                        startAction: MiuixAppIcon(
                          'voice',
                          fallback: Icons.record_voice_over_outlined,
                          size: 24,
                          color: colors.onSurface,
                        ),
                        endActions: [
                          if (_voicePath.isNotEmpty)
                            MiuixIconButton(
                              onPressed: _removeVoice,
                              child: const Icon(Icons.delete_outline,
                                  size: 20),
                            ),
                          MiuixIconButton(
                            onPressed: _pickVoice,
                            child: const Icon(Icons.folder_open_outlined,
                                size: 20),
                          ),
                        ],
                        onClick: _pickVoice,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
                  child: MiuixText(
                    l10n.characterPresetsLabel,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                for (var i = 0; i < _pairs.length; i++) ...[
                  _MiuixPresetPairCard(
                    user: _pairs[i].$1,
                    assistant: _pairs[i].$2,
                    canRemove: _pairs.length > 1,
                    onRemove: () => _removePair(i),
                  ),
                  const SizedBox(height: 10),
                ],
                MiuixGroupCard(
                  insideMargin: const EdgeInsets.symmetric(vertical: 12),
                  feedbackType: MiuixPressFeedbackType.sink,
                  onPressed: _addPair,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add, size: 18),
                        const SizedBox(width: 6),
                        MiuixText(l10n.characterAddPreset, fontSize: 13),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}

/// 一组预制问答：用户行 + 助手行（各自多行输入），右上角 × 删除该组。
class _MiuixPresetPairCard extends StatelessWidget {
  const _MiuixPresetPairCard({
    required this.user,
    required this.assistant,
    required this.canRemove,
    required this.onRemove,
  });

  final TextEditingController user;
  final TextEditingController assistant;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return MiuixGroupCard(
      insideMargin: const EdgeInsets.fromLTRB(12, 10, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CharacterAvatar(
                name: '',
                glyph: 'U',
                color: const Color(0xFF9E9E9E),
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MiuixText(
                  l10n.characterPresetUser,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (canRemove)
                MiuixIconButton(
                  onPressed: onRemove,
                  child: const Icon(Icons.close, size: 18),
                ),
            ],
          ),
          MiuixTextField(
            controller: user,
            label: l10n.characterPresetUser,
            useLabelAsPlaceholder: true,
            minLines: 1,
            maxLines: 5,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              CharacterAvatar(
                name: '',
                glyph: 'A',
                color: const Color(0xFF2F7FE0),
                size: 22,
              ),
              const SizedBox(width: 8),
              MiuixText(
                l10n.characterPresetAssistant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ],
          ),
          MiuixTextField(
            controller: assistant,
            label: l10n.characterPresetAssistant,
            useLabelAsPlaceholder: true,
            minLines: 1,
            maxLines: 5,
          ),
        ],
      ),
    );
  }
}

/// 车道页 / 对话模拟页通用的入口函数：推角色卡页，选中即返回。
Future<CharacterCard?> pushMiuixCharacterCardPicker(BuildContext context) =>
    Navigator.of(context).push<CharacterCard>(
      MaterialPageRoute(builder: (_) => const MiuixCharacterCardPage()),
    );
