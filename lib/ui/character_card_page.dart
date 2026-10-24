import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/chat_simulation.dart';
import 'package:local2api/services/character_store.dart';
import 'package:local2api/services/character_voice.dart';
import 'package:local2api/ui/widgets/field_row.dart';
import 'package:local2api/ui/widgets/text_editor_sheet.dart';
import 'package:local2api/ui/widgets/common.dart';
import 'package:local2api/widgets/app_toast.dart';
import 'package:local2api/widgets/expressive_app_bar.dart';
import 'package:local2api/widgets/metro_tilt_interaction.dart';
import 'package:local2api/widgets/native_text_context_menu.dart';
import 'package:provider/provider.dart';

/// 「应用默认场景」的哨兵卡：id 为空。角色卡页 pop 回对话模拟页时，
/// null = 什么都没选（仅返回），这张 = 回到默认场景。
const CharacterCard kDefaultCharacterCard = CharacterCard(
  id: '',
  name: '',
  prompt: ChatSimController.defaultSystemPrompt,
  builtin: true,
);

/// 角色卡页（Material 版，对应 miuix 版 `MiuixCharacterCardPage`）。
///
/// 「对话模拟」换场景的入口：每张卡是一份「人设提示词 + 预制问答」，
/// 点卡即应用并返回模拟页（pop 出卡片，由模拟页调用
/// [ChatSimController.applyCharacter] 重铺对话）。内置卡（流萤/蕾姆）由
/// 代码生成、不可改；用户卡可以编辑/删除，FAB 创建新角色。
class CharacterCardPage extends StatelessWidget {
  const CharacterCardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final store = context.watch<CharacterStore>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.characterTitle)),
      floatingActionButton: FloatingActionButton.extended(
        tooltip: l10n.characterCreate,
        onPressed: () => pushPage(context, CharacterEditPage(store: store)),
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(l10n.characterCreate),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(
              l10n.characterIntro,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          _DefaultSceneCard(
            onTap: () => Navigator.of(context).pop(kDefaultCharacterCard),
          ),
          for (final c in store.cards)
            _CharacterCardTile(
              card: c,
              onTap: () => Navigator.of(context).pop(c),
              // 内置卡也能编辑（人设微调 / 配音色）：改动存成覆盖，
              // 覆盖过的内置卡多一颗「重置」回原文。
              onEdit: () => pushPage(
                context,
                CharacterEditPage(store: store, existing: c),
              ),
              onReset: store.isOverridden(c.id)
                  ? () async {
                      await store.resetBuiltin(c.id);
                      if (!context.mounted) return;
                      showAppToast(context, l10n.characterOverrideReset);
                    }
                  : null,
              onDelete: c.builtin
                  ? null
                  : () async {
                      final l10n = AppLocalizations.of(context);
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(l10n.characterDeleteConfirm(c.name)),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: Text(l10n.cancel),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: Text(l10n.deleteBtn),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) store.remove(c.id);
                    },
            ),
        ],
      ),
    );
  }
}

/// 「默认场景」卡：不带人设的原始状态（默认 system 提示词）。
class _DefaultSceneCard extends StatelessWidget {
  const _DefaultSceneCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      // naviflashv2 视频卡片同款的按压倾斜（只倾斜不缩放、无描边）。
      child: MetroTileInteraction(
        showBorder: false,
        pressScale: 1.0,
        child: Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            onTap: onTap,
            leading: CircleAvatar(
              backgroundColor: cs.surfaceContainerHighest,
              foregroundColor: cs.onSurfaceVariant,
              child: const Icon(Icons.block_outlined),
            ),
            title: Text(l10n.characterDefault),
            subtitle: Text(
              l10n.characterDefaultDesc,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

/// 一张角色卡：头像 + 名字（内置徽标）+ 人设预览 + 预制对话数 +
/// 编辑按钮（内置卡也有，改的是覆盖）+ 重置（覆盖过的内置卡）+ 删除。
class _CharacterCardTile extends StatelessWidget {
  const _CharacterCardTile({
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      // naviflashv2 视频卡片同款的按压倾斜：按下绕触点 3D 倾斜、
      // 随手指实时跟随，松手回弹（只倾斜不缩放、无描边）。
      child: MetroTileInteraction(
        showBorder: false,
        pressScale: 1.0,
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CharacterAvatar(name: card.name, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          card.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
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
                          decoration: BoxDecoration(
                            color: cs.secondaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            l10n.characterBuiltin,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSecondaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (onReset != null)
                        IconButton(
                          tooltip: l10n.characterOverrideReset,
                          onPressed: onReset,
                          icon: const Icon(Icons.restart_alt, size: 20),
                        ),
                      if (onEdit != null)
                        IconButton(
                          tooltip: l10n.characterEditTitle,
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined, size: 20),
                        ),
                      if (onDelete != null)
                        IconButton(
                          tooltip: l10n.deleteBtn,
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline, size: 20),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    card.prompt,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.characterPresetCount(card.presets.length),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
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

/// 角色头像：名字首字符 + 按名字取的底色（内置卡固定主题色）。
/// [glyph]/[color] 可以覆盖显示内容与配色（编辑页里当「用户/助手」点用）。
class CharacterAvatar extends StatelessWidget {
  const CharacterAvatar({
    super.key,
    required this.name,
    this.size = 40,
    this.glyph,
    this.color,
  });

  final String name;
  final double size;
  final String? glyph;
  final Color? color;

  static const List<Color> _palette = [
    Color(0xFFEF8A65), // 流萤（萨姆的暖橙）
    Color(0xFF6D9EEB), // 蕾姆（蓝发）
    Color(0xFF8BC34A),
    Color(0xFFAB7DF6),
    Color(0xFFF4B400),
  ];

  Color _colorOf(String name) {
    if (name == '流萤') return _palette[0];
    if (name == '蕾姆') return _palette[1];
    var h = 0;
    for (final r in name.runes) {
      h = (h * 31 + r) & 0x7FFFFFFF;
    }
    return _palette[2 + h % (_palette.length - 2)];
  }

  @override
  Widget build(BuildContext context) {
    final g = glyph ?? (name.isEmpty ? '?' : name.characters.first);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color ?? _colorOf(name),
        shape: BoxShape.circle,
      ),
      child: Text(
        g,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}

/// 新建 / 编辑角色卡（Material 版）。[existing] 为空 = 新建。
///
/// 与上游编辑页同一套「一行一个字段」（[FieldRow]）：名称 / 人设提示词 /
/// 音色样本点行开编辑抽屉，预制问答是一组组的卡片输入。内置卡也能进
/// 这页（改动存成覆盖，列表页可一键重置回原文）。保存时名字必填。
class CharacterEditPage extends StatefulWidget {
  const CharacterEditPage({super.key, required this.store, this.existing});

  final CharacterStore store;
  final CharacterCard? existing;

  @override
  State<CharacterEditPage> createState() => _CharacterEditPageState();
}

class _CharacterEditPageState extends State<CharacterEditPage> {
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

  @override
  void initState() {
    super.initState();
    _voicePath = widget.existing?.voiceSamplePath ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    for (final (u, a) in _pairs) {
      u.dispose();
      a.dispose();
    }
    super.dispose();
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

  /// 返回（系统返回与顶栏返回键都汇到 maybePop）：改过任何一项就先弹
  /// 「未保存的更改」，保存 / 不保存 / 取消。没改过直接走。
  Future<void> _handleBack() async {
    if (!_isDirty) {
      Navigator.of(context).pop();
      return;
    }
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
    if (!mounted || action == null || action == 'cancel') return;
    if (action == 'save') {
      _save();
    } else {
      Navigator.of(context).pop();
    }
  }

  /// 人设行里显示的预览：首行 + 省略号（多行提示词压缩成一行）。
  String get _promptPreview {
    final text = _prompt.text.trim();
    if (text.isEmpty) return '';
    final first = text.split('\n').first.trim();
    return text.contains('\n') ? '$first…' : first;
  }

  Future<void> _editName() async {
    final l10n = AppLocalizations.of(context);
    final draft = await showTextEditorSheet(
      context,
      label: l10n.characterNameLabel,
      initial: _name.text,
      hint: l10n.characterNameHint,
    );
    if (draft == null || !mounted) return;
    setState(() => _name.text = draft);
  }

  Future<void> _editPrompt() async {
    final l10n = AppLocalizations.of(context);
    final draft = await showTextEditorSheet(
      context,
      label: l10n.characterPromptLabel,
      initial: _prompt.text,
      hint: l10n.characterPromptHint,
      maxLines: 8,
    );
    if (draft == null || !mounted) return;
    setState(() => _prompt.text = draft);
  }

  Future<void> _pickVoice() async {
    try {
      final path = await CharacterVoice.pickAndStore(
        existingPath: _voicePath,
      );
      if (path == null || !mounted) return;
      setState(() => _voicePath = path);
    } catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        '$e'.replaceFirst(RegExp(r'^(Exception:\s*)+'), ''),
      );
    }
  }

  Future<void> _removeVoice() async {
    await CharacterVoice.deleteStored(_voicePath);
    if (!mounted) return;
    setState(() => _voicePath = '');
  }

  void _save() {
    final l10n = AppLocalizations.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      showAppToast(context, l10n.characterNeedName);
      return;
    }
    final card = CharacterCard(
      id:
          widget.existing?.id ??
          'user.${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      prompt: _prompt.text.trim(),
      voiceSamplePath: _voicePath,
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final notFilled = l10n.notFilled;

    return PopScope(
      // 拦下系统返回，交给 [_handleBack] 判断要不要弹「未保存」。
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.existing == null
                ? l10n.characterNewTitle
                : l10n.characterEditTitle,
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              // 保存动作跟上游编辑页同一套：右上角一颗 save 图标，不是文字按钮
              child: MorphIconButton(
                icon: Icons.save_outlined,
                tooltip: l10n.saveBtn,
                transparent: true,
                onTap: _save,
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            FieldRow(
              icon: Icons.label_outline,
              label: l10n.characterNameLabel,
              value: _name.text.trim().isEmpty ? notFilled : _name.text,
              valueIsHint: _name.text.trim().isEmpty,
              onTap: _editName,
            ),
            FieldRow(
              icon: Icons.note_add_outlined,
              label: l10n.characterPromptLabel,
              value: _promptPreview.isEmpty ? notFilled : _promptPreview,
              valueIsHint: _promptPreview.isEmpty,
              onTap: _editPrompt,
            ),
            // 音色样本（可选）：行尾「移除」，点行选文件，行下提示
            FieldRow(
              icon: Icons.record_voice_over_outlined,
              label: l10n.characterVoiceLabel,
              value: _voicePath.isEmpty
                  ? notFilled
                  : CharacterVoice.displayName(_voicePath),
              valueIsHint: _voicePath.isEmpty,
              onTap: _pickVoice,
              control: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_voicePath.isNotEmpty)
                    IconButton(
                      tooltip: l10n.characterVoiceRemove,
                      onPressed: _removeVoice,
                      icon: const Icon(Icons.delete_outline, size: 20),
                    ),
                  IconButton(
                    tooltip: l10n.characterVoicePick,
                    onPressed: _pickVoice,
                    icon: const Icon(Icons.folder_open_outlined, size: 20),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.characterPresetsLabel,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.characterAddPreset,
                  onPressed: () => setState(
                    () => _pairs.add((
                      TextEditingController(),
                      TextEditingController(),
                    )),
                  ),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _pairs.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
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
                            Text(
                              l10n.characterPresetUser,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            if (_pairs.length > 1)
                              IconButton(
                                tooltip: l10n.deleteBtn,
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () {
                                  setState(() {
                                    _pairs[i].$1.dispose();
                                    _pairs[i].$2.dispose();
                                    _pairs.removeAt(i);
                                  });
                                },
                              ),
                          ],
                        ),
                        TextField(
                          controller: _pairs[i].$1,
                          contextMenuBuilder: textContextMenuBuilder,
                          minLines: 1,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                        const Divider(height: 12),
                        Row(
                          children: [
                            CharacterAvatar(
                              name: '',
                              glyph: 'A',
                              color: const Color(0xFF2F7FE0),
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.characterPresetAssistant,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        TextField(
                          controller: _pairs[i].$2,
                          contextMenuBuilder: textContextMenuBuilder,
                          minLines: 1,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            OutlinedButton.icon(
              onPressed: () => setState(
                () => _pairs.add((
                  TextEditingController(),
                  TextEditingController(),
                )),
              ),
              icon: const Icon(Icons.add),
              label: Text(l10n.characterAddPreset),
            ),
          ],
        ),
      ),
    );
  }
}
