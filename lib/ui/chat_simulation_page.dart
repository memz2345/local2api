import 'dart:async' show unawaited;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/widgets/native_text_context_menu.dart';
import 'package:local2api/services/call_settings.dart';
import 'package:local2api/services/chat_attachment.dart';
import 'package:local2api/services/chat_simulation.dart';
import 'package:local2api/services/character_store.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/tts/tts_chat_speak.dart';
import 'package:local2api/services/tts/tts_export_service.dart';
import 'package:local2api/services/tts/tts_message_export.dart';
import 'package:local2api/services/tts/tts_settings.dart';
import 'package:local2api/services/tts/tts_speech_service.dart';
import 'package:local2api/ui/call_page.dart';
import 'package:local2api/ui/character_card_page.dart';
import 'package:local2api/ui/widgets/common.dart' show pushPage;
import 'package:local2api/widgets/app_toast.dart';
import 'package:local2api/widgets/context_ring.dart';
import 'package:local2api/widgets/expressive_app_bar.dart';
import 'package:local2api/widgets/frosted_page_bar.dart';
import 'package:local2api/services/chat_avatar_store.dart';
import 'package:local2api/ui/chat_settings_page.dart';
import 'package:local2api/widgets/glass_menu_action.dart';
import 'package:local2api/widgets/liquid_glass_menu_button.dart';
import 'package:local2api/widgets/more_menu_sheet.dart';
import 'package:local2api/widgets/predictive_back_sheet.dart';
import 'package:local2api/widgets/voice_record_sheet.dart';

/// 「对话模拟」页（Material 版，与 miuix 版行为一致）。
///
/// 三种角色（系统 / 用户 / 助手）都能改：点消息进编辑弹层（角色下拉 +
/// 正文 + 取消 / 保存 / 保存并发送），发出去的请求体就是界面上这串消息，
/// 历史自动带上；请求走本机代理，真实过一遍路由 / 回退 / 指纹 / 日志。
class ChatSimulationPage extends StatefulWidget {
  const ChatSimulationPage({
    super.key,
    required this.controller,
    required this.model,
    this.groupName,
    this.scope = '',
    this.groupModels = const [],
  });

  final ServerController controller;

  /// 要请求的对外模型名（组的对外名 / 车道名）。选「全部」时的请求目标。
  final String model;
  final String? groupName;

  /// 这段对话存在哪一格（给模型组的 id）。空串 = 不落盘。
  final String scope;

  /// 组内可选的具体模型（「换模型」选择器的候选，不含 [model] 本身）。
  final List<String> groupModels;

  @override
  State<ChatSimulationPage> createState() => _ChatSimulationPageState();
}

class _ChatSimulationPageState extends State<ChatSimulationPage> {
  late final ChatSimController _sim = ChatSimController(
    model: widget.model,
    config: widget.controller.config,
    scope: widget.scope,
    groupModels: widget.groupModels,
  );

  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  ChatRole _inputRole = ChatRole.user;

  /// 发送模式：false = 正常发送（等回复）；true = 发送（模型不响应）。
  /// 点按执行当前模式，长按切换；只在当前页面内记住，不持久化。
  bool _sendOnlyMode = false;

  /// 待发附件：随下一条消息一起挂上（仅展示，不进请求上下文）。
  final List<ChatAttachment> _pending = [];

  @override
  void initState() {
    super.initState();
    // 默认接着上次聊：历史存本机，进来就有（否则发出去的请求等于没历史）
    _sim.restore();
    _sim.addListener(_onChanged);
    widget.controller.server.state.addListener(_onChanged);
    // 自动播放要读 TtsSettings.autoPlay：这页可能比 TTS 设置页先打开，
    // load 幂等（_loaded 门），多调一次没成本。
    unawaited(TtsSettings.instance.load());
  }

  @override
  void dispose() {
    _sim.removeListener(_onChanged);
    widget.controller.server.state.removeListener(_onChanged);
    _sim.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  bool get _serverRunning =>
      widget.controller.server.state.value == ServerState.running;

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// 「换模型」清单：第一项固定「全部（整组共享）」，下面是组内具体模型；
  /// 选谁，这段上下文就只给谁带（选全部 = 组内任意模型都带）。
  Future<void> _pickModel() async {
    final l10n = AppLocalizations.of(context);
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.chatSimModelPicker,
                  style: Theme.of(sheetCtx).textTheme.titleMedium,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.hub_outlined),
              title: Text(l10n.chatSimModelAll),
              subtitle: Text(l10n.chatSimModelAllDesc),
              selected: _sim.isAllModel,
              trailing: _sim.isAllModel
                  ? Icon(
                      Icons.check,
                      color: Theme.of(sheetCtx).colorScheme.primary,
                    )
                  : null,
              onTap: () => Navigator.of(sheetCtx).pop(widget.model),
            ),
            for (final name in widget.groupModels)
              ListTile(
                leading: const Icon(Icons.memory_outlined),
                title: Text(name),
                subtitle: Text(l10n.chatSimModelSpecificDesc),
                selected: _sim.activeModel == name,
                trailing: _sim.activeModel == name
                    ? Icon(
                        Icons.check,
                        color: Theme.of(sheetCtx).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.of(sheetCtx).pop(name),
              ),
            const Divider(height: 1),
            // 「发送图片 / 仅发文字」开关：图片默认随消息发给模型；纯文本
            // 车道收到多模态 content 会直接 400，这时切到「仅发文字」。
            ListTile(
              leading: Icon(
                _sim.sendImages ? Icons.image_outlined : Icons.text_fields,
              ),
              title: Text(
                _sim.sendImages
                    ? l10n.chatSimSendImages
                    : l10n.chatSimSendTextOnly,
              ),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                final now = _sim.toggleSendImages();
                showAppToast(
                  context,
                  now ? l10n.chatSimImagesOn : l10n.chatSimImagesOff,
                );
              },
            ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => _sim.setActiveModel(chosen));
  }

  /// 打开角色卡页挑一个场景：选中即整段重铺（人设 system + 预制问答）。
  /// 返回 null = 只是看了看没选（页头「当前角色」也可能在角色卡页被
  /// 改名/删除，所以无论选没选都要刷一次）。
  Future<void> _pickCharacter() async {
    final l10n = AppLocalizations.of(context);
    final card = await pushPage<CharacterCard>(
      context,
      const CharacterCardPage(),
    );
    if (!mounted) return;
    if (card == null) {
      setState(() {});
      return;
    }
    if (card.id.isEmpty) {
      _sim.resetCharacter();
      showAppToast(context, l10n.characterResetDone);
    } else {
      _sim.applyCharacter(card);
      showAppToast(context, l10n.characterApplied(card.name));
    }
    setState(() {});
    _scrollToBottom();
  }

  /// 打开「对话设置」二级页（本地 TTS / 角色卡管理）。
  Future<void> _openChatSettings() async {
    await pushPage<void>(
      context,
      ChatSettingsPage(controller: widget.controller),
    );
  }

  /// 「头像设置」抽屉：用户 / 助手两个圆形头像，各自可换图 / 恢复默认。
  Future<void> _openAvatarSheet() async {
    final l10n = AppLocalizations.of(context);
    // 启动时已 load 过；这里补一次（幂等），冷启动直达本页也不虚。
    await chatAvatarStore.load();
    if (!mounted) return;
    await showAppBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                l10n.chatSimAvatarTitle,
                style: Theme.of(sheetCtx).textTheme.titleMedium,
              ),
            ),
            _AvatarSettingRow(
              role: ChatRole.user,
              label: l10n.chatSimAvatarUser,
              onPickGallery: () => _pickAvatar(sheetCtx, ChatRole.user),
              onPickCamera: () =>
                  _pickAvatar(sheetCtx, ChatRole.user, fromCamera: true),
              onReset: () => chatAvatarStore.setAvatar(ChatRole.user, null),
            ),
            _AvatarSettingRow(
              role: ChatRole.assistant,
              label: l10n.chatSimAvatarAssistant,
              onPickGallery: () => _pickAvatar(sheetCtx, ChatRole.assistant),
              onPickCamera: () =>
                  _pickAvatar(sheetCtx, ChatRole.assistant, fromCamera: true),
              onReset: () =>
                  chatAvatarStore.setAvatar(ChatRole.assistant, null),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 选头像：先关抽屉、再拉起选图器（同附件选取的坑 —— 抽屉挂在后面
  /// 要再点一次才收得掉）。选完压到 ≤512px 存下，失败 toast 原因。
  Future<void> _pickAvatar(
    BuildContext sheetCtx,
    ChatRole role, {
    bool fromCamera = false,
  }) async {
    final l10n = AppLocalizations.of(context);
    Navigator.of(sheetCtx).pop();
    final r = await chatAvatarStore.pickAvatar(role, fromCamera: fromCamera);
    if (!mounted) return;
    if (r == AttachmentPick.ok) {
      showAppToast(context, l10n.chatSimAvatarUpdated);
    } else if (r == AttachmentPick.failed) {
      showAppToast(
        context,
        l10n.chatSimAvatarFailed(ChatAvatarStore.lastPickError ?? '–'),
      );
    }
  }

  /// 按当前发送模式执行：正常发送 / 只发不等。
  Future<void> _sendCurrentMode() async {
    if (_sendOnlyMode) {
      await _sendOnly();
    } else {
      await _send();
    }
  }

  /// 长按切换发送模式，toast 报一声新模式（按钮图标也会跟着换）。
  void _toggleSendMode() {
    final l10n = AppLocalizations.of(context);
    setState(() => _sendOnlyMode = !_sendOnlyMode);
    showAppToast(
      context,
      _sendOnlyMode ? l10n.chatSimSendModeOnly : l10n.chatSimSend,
    );
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isNotEmpty || _pending.isNotEmpty) {
      _sim.add(_inputRole, text, List.of(_pending));
      _inputController.clear();
      _consumePending();
    }
    _scrollToBottom();
    await _sim.send();
    _scrollToBottom();
    _autoSpeakIfEnabled();
  }

  Future<void> _sendOnly() async {
    final l10n = AppLocalizations.of(context);
    final text = _inputController.text.trim();
    if (text.isNotEmpty || _pending.isNotEmpty) {
      _sim.add(_inputRole, text, List.of(_pending));
      _inputController.clear();
      _consumePending();
    }
    _scrollToBottom();
    final sent = await _sim.sendOnly();
    if (!mounted || !sent) return;
    // 只发不等 = 不会多出一条回答，不给个提示用户会以为没点到
    showAppToast(context, l10n.chatSimSentOnly);
    _scrollToBottom();
  }

  Future<void> _saveAndSend(int index, ChatRole role, String content) async {
    // 改了中间某条就把它之后的丢掉，按这个前缀重发（后面那些回答是旧前缀
    // 的产物，留着只会串味）。
    _sim.edit(index, role, content, truncateAfter: true);
    _scrollToBottom();
    await _sim.send();
    _scrollToBottom();
    _autoSpeakIfEnabled();
  }

  /// 朗读这条助手消息：按「对话设置 → 默认 TTS 服务商」路由
  /// （本地直接合成，云端走本机代理 /v1/audio/speech）。
  /// 当前角色卡配了音色样本就带上（本地克隆 / 云端 voiceclone）。
  Future<void> _speakMessage(ChatMsg msg) async {
    final tag = 'msg:${identityHashCode(msg)}';
    final voice =
        characterStore.cardOf(_sim.appliedCharacterId ?? '')?.voiceSamplePath ??
        '';
    try {
      await ChatTts.speakMessage(
        tag: tag,
        text: msg.content,
        config: widget.controller.config,
        voiceSamplePath: voice.isEmpty ? null : voice,
      );
    } catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        '$e'.replaceFirst(RegExp(r'^(Exception:\s*)+'), ''),
      );
    }
  }

  /// 自动播放（对话设置里那个开关）：一轮回复落地后直接朗读最后一条助手消息。
  ///
  /// 只在开关开着、且确实选了 TTS 服务商时才动手 —— 服务商没配时
  /// [_speakMessage] 会抛「未选择 TTS 服务商」，每条回复都弹一次 toast 太吵。
  /// 失败的回答（error 气泡）与空文本跳过；正在播同一条也不重复触发。
  void _autoSpeakIfEnabled() {
    final target = ChatTts.autoPlayTarget(_sim.messages, TtsSettings.instance);
    if (target == null) return;
    if (TtsSpeechService.instance.isActive('msg:${identityHashCode(target)}')) {
      return;
    }
    unawaited(_speakMessage(target));
  }

  /// 助手消息的长按菜单：复制 / 删除 / 朗读 / 重新回答 / 下载。
  ///
  /// 用顶栏「三个点」那同一套底部抽屉（[showMoreMenuSheet]），观感一致。
  /// 「下载」只在编了原生编码器的平台（Android）上出现，见
  /// [TtsMessageExport.isSupported]。
  Future<void> _showMessageMenu(int index) async {
    if (index < 0 || index >= _sim.messages.length) return;
    final l10n = AppLocalizations.of(context);
    final msg = _sim.messages[index];
    final tag = 'msg:${identityHashCode(msg)}';
    // 正在朗读这条 → 菜单里那一项变成「停止朗读」（与气泡上的喇叭按钮
    // 同一条口径）。
    final speaking = TtsSpeechService.instance.isActive(tag);

    await showMoreMenuSheet(
      context: context,
      title: l10n.chatSimMsgMenuTitle,
      actions: [
        MoreMenuAction(
          icon: Icons.copy_rounded,
          label: l10n.copy,
          onTap: () {
            if (!mounted) return;
            Clipboard.setData(ClipboardData(text: msg.content));
            showAppToast(context, l10n.copied);
          },
        ),
        MoreMenuAction(
          icon: Icons.delete_outline_rounded,
          label: l10n.commonDelete,
          onTap: () {
            if (!mounted) return;
            // 无确认弹窗 —— 沙盒里删错了重发就是（与原来长按即删一致）。
            _sim.removeAt(index);
            showAppToast(context, l10n.chatSimRemoved);
          },
        ),
        MoreMenuAction(
          icon: speaking ? Icons.stop_rounded : Icons.volume_up_outlined,
          label: speaking ? l10n.chatSimMsgStopSpeak : l10n.chatSimMsgSpeak,
          onTap: () {
            if (!mounted) return;
            _speakMessage(msg);
          },
        ),
        MoreMenuAction(
          icon: Icons.refresh_rounded,
          label: l10n.chatSimMsgRegenerate,
          onTap: () {
            if (!mounted) return;
            _regenerateFrom(index);
          },
        ),
        if (TtsMessageExport.isSupported)
          MoreMenuAction(
            icon: Icons.download_outlined,
            label: l10n.chatSimMsgDownload,
            subtitle: 'MP3 / SILK / SLK',
            onTap: () {
              if (!mounted) return;
              _downloadMessage(msg);
            },
          ),
      ],
    );
  }

  /// 「重新回答」：从这条起把后面的都丢掉，按剩下的前缀重发一次。
  Future<void> _regenerateFrom(int index) async {
    _scrollToBottom();
    await _sim.regenerateFrom(index);
    if (!mounted) return;
    _scrollToBottom();
    _autoSpeakIfEnabled();
  }

  /// 「下载」：先弹窗选格式（MP3 / SILK / SLK，SILK 系带 -tencent 开关），
  /// 再合成 → 转码 → 系统「另存为」。
  Future<void> _downloadMessage(ChatMsg msg) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showDialog<_ExportChoice>(
      context: context,
      builder: (_) => const _ExportFormatDialog(),
    );
    if (choice == null || !mounted) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    final fileName = TtsExportService.fileNameFor(
      choice.format,
      label: _callPeerName,
    );

    // 合成可能几十秒（本地引擎首次要加载 1.4GB 模型），必须给个不可取消的
    // 转圈，不然用户以为没点上会连着点。unawaited：这里要的是「弹出来」，
    // 不是「等它关掉」。
    var busyOpen = true;
    void closeBusy() {
      if (!busyOpen) return;
      busyOpen = false;
      navigator.pop();
    }

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 18),
                Expanded(child: Text(l10n.chatSimDownloadBusy)),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final voice =
          characterStore.cardOf(_sim.appliedCharacterId ?? '')?.voiceSamplePath ??
          '';
      final bytes = await TtsMessageExport.render(
        text: msg.content,
        config: widget.controller.config,
        voiceSamplePath: voice.isEmpty ? null : voice,
        format: choice.format,
        tencent: choice.tencent,
      );
      // 合成 / 转码做完就收掉转圈：接下来的系统「另存为」要用户自己操作，
      // 上面不该再压一层模态。
      closeBusy();
      final path = await TtsMessageExport.save(
        bytes: bytes,
        fileName: fileName,
        format: choice.format,
      );
      if (!mounted) return;
      showAppToast(
        context,
        path == null
            ? l10n.chatSimDownloadCanceled
            : l10n.chatSimDownloadSaved(path),
      );
    } catch (e) {
      closeBusy();
      if (!mounted) return;
      showAppToast(context, l10n.chatSimDownloadFailed(_flatError(e)), error: true);
    }
  }

  /// 错误文案抹掉 Dart 默认的 `Exception: ` 前缀（本页其它提示同款处理）。
  static String _flatError(Object e) =>
      '$e'.replaceFirst(RegExp(r'^(Exception:\s*)+'), '');

  Future<void> _openEditor(int index) async {
    final l10n = AppLocalizations.of(context);
    final msg = _sim.messages[index];
    final textCtrl = TextEditingController(text: msg.content);
    var role = msg.role;
    var action = 'cancel';

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(l10n.chatSimEditTitle),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _RoleAvatar(role: role, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<ChatRole>(
                        initialValue: role,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          for (final r in ChatRole.values)
                            DropdownMenuItem(
                              value: r,
                              child: Text(_roleLabel(l10n, r)),
                            ),
                        ],
                        onChanged: (v) =>
                            setDialog(() => role = v ?? ChatRole.user),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  // Windows 上右键弹原生编辑菜单
                  contextMenuBuilder: textContextMenuBuilder,
                  controller: textCtrl,
                  minLines: 4,
                  maxLines: 10,
                  autofocus: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                action = 'cancel';
                Navigator.of(ctx).pop();
              },
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () {
                action = 'save';
                Navigator.of(ctx).pop();
              },
              child: Text(l10n.chatSimSave),
            ),
            FilledButton(
              onPressed: () {
                action = 'saveAndSend';
                Navigator.of(ctx).pop();
              },
              child: Text(l10n.chatSimSaveAndSend),
            ),
          ],
        ),
      ),
    );

    final content = textCtrl.text;
    textCtrl.dispose();
    if (!mounted || action == 'cancel') return;
    if (action == 'saveAndSend') {
      await _saveAndSend(index, role, content);
    } else {
      _sim.edit(index, role, content);
    }
  }

  Future<void> _addMessage() async {
    final l10n = AppLocalizations.of(context);
    final chosen = await showModalBottomSheet<ChatRole>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.chatSimAddMessage,
                  style: Theme.of(sheetCtx).textTheme.titleMedium,
                ),
              ),
            ),
            for (final r in ChatRole.values)
              ListTile(
                leading: _RoleAvatar(role: r, size: 32),
                title: Text(_roleLabel(l10n, r)),
                onTap: () => Navigator.of(sheetCtx).pop(r),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    _sim.add(chosen);
    _scrollToBottom();
  }

  String _roleLabel(AppLocalizations l10n, ChatRole role) => switch (role) {
    ChatRole.system => l10n.chatSimRoleSystem,
    ChatRole.user => l10n.chatSimRoleUser,
    ChatRole.assistant => l10n.chatSimRoleAssistant,
  };

  /// 底部输入角色循环：用户 → 系统 → 助手 → 用户。
  /// 上下文占用环：数字太多，悬停 tooltip 看不清 —— 点一下弹详情
  /// （百分比 / 用量与上限 / 是 usage 精确值还是本地估算 / 输出上限 /
  /// 当前请求模型 / 消息与图片数）。
  /// 分母 = 当前请求目标声明的最大上下文（没配回退 1M），
  /// 分子 = 上一轮响应 usage（没有就按字数与图片粗估）。
  Widget _ctxRing(AppLocalizations l10n) {
    final d = _sim.contextDetails();
    return Tooltip(
      message: l10n.contextRingTap,
      child: InkWell(
        onTap: () => _showContextDetails(l10n),
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: ContextRing(
            percent: d.percent.clamp(0.0, 100.0),
            label: '${d.label}%',
          ),
        ),
      ),
    );
  }

  Future<void> _showContextDetails(AppLocalizations l10n) async {
    final d = _sim.contextDetails();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    String fmt(int n) => n.toString();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.contextDetailTitle),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.contextDetailPercent(d.label),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: d.percent >= 90 ? cs.error : cs.primary,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: (d.percent / 100).clamp(0.0, 1.0),
                  minHeight: 6,
                  color: d.percent >= 90 ? cs.error : cs.primary,
                ),
              ),
              const SizedBox(height: 14),
              _DetailLine(
                text: l10n.contextDetailUsed(fmt(d.used), fmt(d.limit)),
                emphasis: true,
              ),
              _DetailLine(
                text: d.estimated
                    ? l10n.contextDetailEstimated
                    : l10n.contextDetailFromUsage,
                muted: true,
              ),
              _DetailLine(
                text: d.maxOutput > 0
                    ? l10n.contextDetailOutput(fmt(d.maxOutput))
                    : l10n.contextDetailOutputNone,
                muted: true,
              ),
              const Divider(height: 22),
              _DetailLine(text: l10n.contextDetailModel(d.model), mono: true),
              _DetailLine(
                text: l10n.contextDetailMessages(
                  '${d.messages}',
                  '${d.images}',
                ),
                muted: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.contextDetailClose),
          ),
        ],
      ),
    );
  }

  void _cycleInputRole() {
    final next =
        (ChatRole.values.indexOf(_inputRole) + 1) % ChatRole.values.length;
    setState(() => _inputRole = ChatRole.values[next]);
  }

  /// 附件直选（底栏工具行）：文件 / 相册图片 / 拍照。图片压成 ≤1024px
  /// JPEG 随消息发给模型，文件只取元信息纯展示。
  /// 附件只挂在用户消息上 —— 其他角色点了给个提示。
  Future<void> _attach(_AttachRequest request) async {
    final l10n = AppLocalizations.of(context);
    if (_inputRole != ChatRole.user) {
      showAppToast(context, l10n.chatSimAttachUserOnly);
      return;
    }
    final a = await request.run();
    if (!mounted) return;
    if (a.attachment != null) {
      setState(() => _pending.add(a.attachment!));
      return;
    }
    // 取消不吭声；真失败了把原因报出来（以前直接吞掉，看着就是「没反应」）。
    if (a.error != null) {
      showAppToast(context, l10n.chatSimAttachFailed(a.error!));
    }
  }

  Future<void> _attachFile() => _attach(const _AttachRequest.file());

  Future<void> _attachImage() => _attach(const _AttachRequest.gallery());

  Future<void> _attachCamera() => _attach(const _AttachRequest.camera());

  /// 语音输入：弹出「按住说话」录音层，识别文本接在输入框已有内容后面。
  Future<void> _startVoiceRecord() async {
    final text = await showVoiceRecordSheet(
      context,
      localeTag: _voiceLocaleTag(),
    );
    if (!mounted || text == null || text.trim().isEmpty) return;
    // 识别结果接在原有文本后面，别把用户已经打的字冲掉。
    final base = _inputController.text.trimRight();
    final joined = base.isEmpty ? text.trim() : '$base ${text.trim()}';
    _inputController.value = TextEditingValue(
      text: joined,
      selection: TextSelection.collapsed(offset: joined.length),
    );
  }

  /// 识别语言：把应用 locale 摆成引擎认的 'zh_CN' 形态。
  String? _voiceLocaleTag() {
    final locale = Localizations.localeOf(context);
    final region = (locale.countryCode ?? '').toUpperCase();
    return region.isEmpty ? locale.languageCode : '${locale.languageCode}_$region';
  }

  // ---- 通话（底栏电话按钮）----

  /// 组内可用的 Omni 模型（视频通话的前提）；没有返回 null。
  /// 优先当前选中模型，再扫组对外名与组内模型。
  String? get _omniModel {
    for (final name in [_sim.activeModel, widget.model, ...widget.groupModels]) {
      if (isOmniModelName(name)) return name;
    }
    return null;
  }

  /// 通话对端显示名：当前应用的角色卡名字优先，没有角色卡回落组名。
  String get _callPeerName {
    final card = characterStore.cardOf(_sim.appliedCharacterId ?? '');
    final name = card?.name.trim() ?? '';
    if (name.isNotEmpty) return name;
    return widget.groupName ?? widget.model;
  }

  /// 顶栏标题：加载了角色卡就顶角色名（跟「和小语通话」一个口径），
  /// 没加载就用固定的「对话模拟」。
  ///
  /// 换角色走 `_sim.applyCharacter` → notify → setState，build 里现算就能跟上。
  String get _barTitle {
    final name =
        characterStore.cardOf(_sim.appliedCharacterId ?? '')?.name.trim() ?? '';
    return name.isNotEmpty ? name : AppLocalizations.of(context).chatSimTitle;
  }

  /// 底栏「通话」：弹层二选一 —— 语音通话 / 视频通话。视频需要组里有
  /// Omni 模型，没有就置灰并说明原因。
  Future<void> _showCallSheet() async {
    final l10n = AppLocalizations.of(context);
    final omni = _omniModel;
    await showAppBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  l10n.callTitleAction,
                  style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _CallOptionTile(
                icon: Icons.call_outlined,
                title: l10n.callTitleVoice,
                subtitle: l10n.chatSimCallPeer(_callPeerName),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _openCall(video: false);
                },
              ),
              const SizedBox(height: 8),
              _CallOptionTile(
                icon: Icons.videocam_outlined,
                title: l10n.callTitleVideo,
                subtitle: omni == null ? l10n.callVideoNeedOmni : null,
                enabled: omni != null,
                onTap: omni == null
                    ? null
                    : () {
                        Navigator.of(sheetCtx).pop();
                        _openCall(video: true);
                      },
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  /// 推通话页：语音用当前选中的模型；视频用组内 Omni 模型。
  void _openCall({required bool video}) {
    final omni = _omniModel;
    pushPage(
      context,
      CallPage(
        controller: widget.controller,
        model: video ? (omni ?? _sim.activeModel) : _sim.activeModel,
        groupName: widget.groupName,
        displayName: _callPeerName,
        // 与对话模拟共用同一格聊天记录
        scope: widget.scope,
        startVideo: video,
      ),
    );
  }

  void _consumePending() {
    if (_pending.isEmpty) return;
    setState(() => _pending.clear());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // 顶栏与「请求日志」页同一套（FrostedBarPage + MorphIconButton）。
    // 消息列表铺到整页、从底部输入台下面穿过 —— 底栏毛玻璃才有东西可糊
    // （对齐主页底栏的透明玻璃观感）。
    return FrostedBarPage(
      title: _barTitle,
      actions: [
        // 角色卡：换一个更贴合的场景（人设 system + 预制问答）。
        MorphIconButton(
          icon: Icons.face_retouching_natural,
          tooltip: l10n.characterTitle,
          transparent: true,
          onTap: _pickCharacter,
        ),
        // 其余动作收进「三个点」：添加消息 / 重新生成 / 头像 / 清空 / 对话设置。
        LiquidGlassMenuButton(
          icon: Icons.more_vert,
          tooltip: l10n.chatSimMore,
          menuWidth: 230,
          transparent: true,
          actions: [
            GlassMenuAction(
              icon: Icons.add_comment_outlined,
              text: l10n.chatSimAddMessage,
              onTap: _addMessage,
            ),
            GlassMenuAction(
              icon: Icons.refresh,
              text: l10n.chatSimRegenerate,
              isEnabled: !_sim.sending,
              onTap: _sim.regenerate,
            ),
            GlassMenuAction(
              icon: Icons.account_circle_outlined,
              text: l10n.chatSimAvatarTitle,
              onTap: _openAvatarSheet,
            ),
            GlassMenuAction(
              icon: Icons.delete_sweep_outlined,
              text: l10n.chatSimClear,
              onTap: _sim.clear,
            ),
            GlassMenuAction(
              icon: Icons.settings_outlined,
              text: l10n.chatSettingsTitle,
              onTap: _openChatSettings,
            ),
          ],
        ),
      ],
      child: Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                SizedBox(height: frostedPageBarInset(context) + 10),
                if (!_serverRunning)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Material(
                      color: cs.tertiaryContainer,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.chatSimServerOff,
                                style: TextStyle(color: cs.onTertiaryContainer),
                              ),
                            ),
                            TextButton(
                              onPressed: widget.controller.toggle,
                              child: Text(l10n.chatSimStartServer),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    // 底部垫出输入台的高度，最后一条消息不被玻璃挡住。
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 190),
                    itemCount: _sim.messages.length + (_sim.sending ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i >= _sim.messages.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            l10n.chatSimSending,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        );
                      }
                      return _MessageBubble(
                        message: _sim.messages[i],
                        onTap: () => _openEditor(i),
                        // 助手消息长按弹菜单（复制 / 删除 / 朗读 / 重新回答 /
                        // 下载）；其余角色保持原来的「长按直接删这条」
                        // —— 沙盒里删错了重发就是。
                        onLongPress: () {
                          if (_sim.messages[i].role == ChatRole.assistant) {
                            _showMessageMenu(i);
                            return;
                          }
                          _sim.removeAt(i);
                          showAppToast(context, l10n.chatSimRemoved);
                        },
                        onCopy: () {
                          // 不 await：剪贴板写入是即时的，await 之后再用 context
                          // 会踩 async gap 的 lint，而这里本来也不需要等。
                          Clipboard.setData(
                            ClipboardData(text: _sim.messages[i].content),
                          );
                          showAppToast(context, l10n.copied);
                        },
                        onSpeak: () => _speakMessage(_sim.messages[i]),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildComposer(l10n),
          ),
        ],
      ),
    );
  }

  /// 底部输入台（悬浮毛玻璃）：第一行是「角色头像 + 输入框 + 占用环 + 发送」，
  /// 第二行是工具行「模型 / 文件 / 语音 / 图片 / 拍照」。
  Widget _buildComposer(AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: FrostedPanel(
        opacity: 0.72,
        blurSigma: 12,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 待发附件条：随下一条消息挂上，× 立即移除。
              if (_pending.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (var i = 0; i < _pending.length; i++)
                        _AttachmentChip(
                          attachment: _pending[i],
                          onRemove: () => setState(() => _pending.removeAt(i)),
                        ),
                    ],
                  ),
                ),
              Row(
                children: [
                  // 输入角色：点按在 系统 / 用户 / 助手 之间循环。
                  IconButton(
                    tooltip: _roleLabel(l10n, _inputRole),
                    onPressed: _cycleInputRole,
                    icon: _RoleAvatar(role: _inputRole, size: 34),
                  ),
                  const SizedBox(width: 2),
                  // 输入框本体也是毛玻璃（嵌套 BackdropFilter）。
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          color: cs.surfaceContainerHighest.withValues(
                            alpha: 0.55,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: TextField(
                            // Windows 上右键弹原生编辑菜单
                            contextMenuBuilder: textContextMenuBuilder,
                            controller: _inputController,
                            minLines: 1,
                            maxLines: 5,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendCurrentMode(),
                            decoration: InputDecoration(
                              hintText: l10n.chatSimHintInput,
                              border: InputBorder.none,
                              filled: false,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 上下文占用环：点开看详情（对齐 opencode 的上下文指示器）。
                  _ctxRing(l10n),
                  // 发送（两态）：点按执行当前模式，长按在「发送」与
                  // 「发送（模型不响应）」之间切换（切换时 toast 报一声）。
                  GestureDetector(
                    onLongPress: _sim.sending ? null : _toggleSendMode,
                    child: IconButton.filled(
                      onPressed: _sim.sending ? null : _sendCurrentMode,
                      icon: Icon(
                        _sendOnlyMode
                            ? Icons.flight_takeoff
                            : Icons.send_outlined,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // 工具行：模型 / 文件 / 语音 / 图片 / 拍照 / 通话。
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _ComposerAction(
                    icon: Icons.memory_outlined,
                    tooltip: l10n.chatSimModelPicker,
                    onTap: widget.groupModels.isEmpty ? null : _pickModel,
                  ),
                  _ComposerAction(
                    icon: Icons.insert_drive_file_outlined,
                    tooltip: l10n.chatSimAttachFile,
                    onTap: _attachFile,
                  ),
                  _ComposerAction(
                    icon: Icons.mic_none,
                    tooltip: l10n.chatSimVoiceInput,
                    onTap: _startVoiceRecord,
                  ),
                  _ComposerAction(
                    icon: Icons.image_outlined,
                    tooltip: l10n.chatSimAttachImage,
                    onTap: _attachImage,
                  ),
                  _ComposerAction(
                    icon: Icons.photo_camera_outlined,
                    tooltip: l10n.chatSimAttachCamera,
                    onTap: _attachCamera,
                  ),
                  _ComposerAction(
                    icon: Icons.call_outlined,
                    tooltip: l10n.callTitleAction,
                    onTap: _showCallSheet,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 输入台工具行的一颗按钮。
class _ComposerAction extends StatelessWidget {
  const _ComposerAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, size: 22),
    );
  }
}

/// 消息气泡：头像 + 角色名 + 附件 + 正文 + 页脚（字数 / 耗时）+ 响应模型 +
/// 复制（助手）。点整条进编辑；长按助手消息弹操作菜单，长按其余角色
/// **立即删除**（无确认弹窗）。
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.onTap,
    required this.onCopy,
    required this.onLongPress,
    required this.onSpeak,
  });

  final ChatMsg message;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final VoidCallback onLongPress;

  /// 朗读（仅助手消息；按「对话设置 → 默认 TTS 服务商」路由）。
  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isUser = message.role == ChatRole.user;
    final bubbleColor = message.error
        ? cs.errorContainer
        : cs.surfaceContainerHighest;
    final textColor = message.error ? cs.onErrorContainer : cs.onSurface;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            _RoleAvatar(role: message.role, size: 32),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      switch (message.role) {
                        ChatRole.system => l10n.chatSimRoleSystem,
                        ChatRole.user => l10n.chatSimRoleUser,
                        ChatRole.assistant => l10n.chatSimRoleAssistant,
                      },
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // 附件：图片渲染缩略图（发请求时带的就是这份字节），
                    // 文件渲染成名称胶囊（只展示，不进请求体）。
                    if (message.attachments.isNotEmpty) ...[
                      _BubbleAttachments(attachments: message.attachments),
                      const SizedBox(height: 6),
                    ],
                    // 正文**不可选**：SelectableText 的长按会被「选词」手势
                    // 吃掉，气泡的 onLongPress 就再也收不到 —— 而长按弹菜单
                    // 正是这条气泡的主操作（复制 / 删除 / 朗读 / 重新回答 /
                    // 下载）。要整段文字有菜单里的「复制」，要局部选字有
                    // 编辑弹层（点气泡进去，里面是可编辑的 TextField）。
                    // miuix 版一直是普通文本，两边手感一致。
                    Text(
                      message.content.isEmpty ? '（空）' : message.content,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.chatSimMeta(
                              chatWordCount(message.content),
                              formatElapsed(message.elapsedMs),
                            ),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (message.role == ChatRole.assistant) ...[
                          _SpeakButton(
                            tag: 'msg:${identityHashCode(message)}',
                            onSpeak: onSpeak,
                          ),
                          InkWell(
                            onTap: onCopy,
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                Icons.copy,
                                size: 15,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    // 响应模型：走容灾路由时把「真实车道 + 请求的对外名」
                    // 一起标出来，否则只标模型本身。
                    if (message.role == ChatRole.assistant &&
                        message.servedModel != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          children: [
                            Icon(
                              Icons.memory,
                              size: 12,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                message.routed
                                    ? l10n.chatSimServedModelVia(
                                        message.lane!,
                                        message.model!,
                                      )
                                    : l10n.chatSimServedModel(
                                        message.servedModel!,
                                      ),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            _RoleAvatar(role: message.role, size: 32),
          ],
        ],
      ),
    );
  }
}

/// 气泡上的朗读按钮：空闲是喇叭，这条正在合成/播放时变停止键
/// （合成中转圈）。状态来自全局 [TtsSpeechService]，离开页面照常播。
class _SpeakButton extends StatelessWidget {
  const _SpeakButton({required this.tag, required this.onSpeak});

  final String tag;
  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: TtsSpeechService.instance,
      builder: (context, _) {
        final svc = TtsSpeechService.instance;
        final mine = svc.activeTag == tag && !svc.isIdle;
        if (mine && svc.status != TtsSpeechStatus.playing) {
          return Padding(
            padding: const EdgeInsets.all(3),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return InkWell(
          onTap: onSpeak,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(
              mine ? Icons.stop : Icons.volume_up_outlined,
              size: 15,
              color: cs.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }
}

/// 角色头像：配了自定义图（用户 / 助手）就圆形裁切显示它；
/// 否则回默认图标 —— 系统=齿轮、用户=人、助手=机器人（对齐 Chatbox）。
class _RoleAvatar extends StatelessWidget {
  const _RoleAvatar({required this.role, required this.size});

  final ChatRole role;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: chatAvatarStore,
      builder: (context, _) {
        final custom = chatAvatarStore.avatarOf(role);
        if (custom != null && custom.isNotEmpty) {
          return SizedBox(
            width: size,
            height: size,
            child: ClipOval(
              child: Image.memory(
                custom,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
          );
        }
        final (icon, tint) = switch (role) {
          ChatRole.system => (Icons.settings, const Color(0xFFF07C1E)),
          ChatRole.user => (Icons.person, const Color(0xFF9E9E9E)),
          ChatRole.assistant => (Icons.smart_toy, const Color(0xFF2F7FE0)),
        };
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
          child: Icon(icon, size: size * 0.55, color: Colors.white),
        );
      },
    );
  }
}

/// 「头像设置」抽屉里的一行：当前头像 + 角色名 + 「从相册选择 / 拍照 /
/// 恢复默认（没配过头像时不显示）」。头像变化靠 ListenableBuilder 即时刷新。
class _AvatarSettingRow extends StatelessWidget {
  const _AvatarSettingRow({
    required this.role,
    required this.label,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onReset,
  });

  final ChatRole role;
  final String label;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: chatAvatarStore,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _RoleAvatar(role: role, size: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: onPickGallery,
                  icon: const Icon(Icons.photo_library_outlined, size: 16),
                  label: Text(l10n.chatSimAvatarPick),
                ),
                OutlinedButton.icon(
                  onPressed: onPickCamera,
                  icon: const Icon(Icons.photo_camera_outlined, size: 16),
                  label: Text(l10n.chatSimAvatarCamera),
                ),
                if (chatAvatarStore.hasAvatarOf(role))
                  TextButton.icon(
                    onPressed: onReset,
                    icon: const Icon(Icons.restart_alt, size: 16),
                    label: Text(l10n.chatSimAvatarReset),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 气泡里的附件区：图片渲染缩略图（只带一份压缩字节，发请求也用同一份），
/// 文件渲染成「图标 + 文件名 + 大小」胶囊（文件只展示，不进请求体）。
class _BubbleAttachments extends StatelessWidget {
  const _BubbleAttachments({required this.attachments});

  final List<ChatAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in attachments)
          if (a.isImage && a.thumbnail != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(
                a.thumbnail!,
                height: 140,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.insert_drive_file, size: 18, color: cs.primary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (formatAttachmentSize(a.sizeBytes).isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      formatAttachmentSize(a.sizeBytes),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
      ],
    );
  }
}

/// 输入框上方的待发附件胶囊（× 立即移除）。
class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.attachment, required this.onRemove});

  final ChatAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sizeText = formatAttachmentSize(attachment.sizeBytes);
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            attachment.isImage
                ? Icons.image_outlined
                : Icons.description_outlined,
            size: 16,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              sizeText.isEmpty
                  ? attachment.name
                  : '${attachment.name} · $sizeText',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            onTap: onRemove,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close, size: 14, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// 附件清单里选中的那一项。
///
/// 先关抽屉、再拉起选图器：以前是在抽屉里 await 选图器，相册盖回来时
/// 抽屉还挂在后面，选完要再点一次才收得掉。
class _AttachRequest {
  const _AttachRequest.gallery() : fromCamera = false, isFile = false;
  const _AttachRequest.camera() : fromCamera = true, isFile = false;
  const _AttachRequest.file() : fromCamera = false, isFile = true;

  final bool fromCamera;
  final bool isFile;

  /// 跑选择器。`(attachment, error)` 两个都为 null = 用户取消。
  Future<({ChatAttachment? attachment, String? error})> run() async {
    if (isFile) {
      final r = await ChatAttachmentPicker.pickFile();
      return (
        attachment: r.file,
        error: r.pick == AttachmentPick.failed
            ? (ChatAttachmentPicker.lastError ?? '–')
            : null,
      );
    }
    final r = await ChatAttachmentPicker.pickImage(fromCamera: fromCamera);
    return (
      attachment: r.image,
      error: r.pick == AttachmentPick.failed
          ? (ChatAttachmentPicker.lastError ?? '–')
          : null,
    );
  }
}

/// 上下文详情弹窗里的一行说明。
class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.text,
    this.muted = false,
    this.mono = false,
    this.emphasis = false,
  });

  final String text;
  final bool muted;
  final bool mono;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: (muted ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)
            ?.copyWith(
              color: muted ? cs.onSurfaceVariant : cs.onSurface,
              fontFamily: mono ? 'monospace' : null,
              fontWeight: emphasis ? FontWeight.w600 : null,
            ),
      ),
    );
  }
}

/// 通话选择弹层里的一行选项（语音 / 视频）。
class _CallOptionTile extends StatelessWidget {
  const _CallOptionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = enabled ? cs.onSurface : cs.onSurface.withValues(alpha: 0.38);
    return Material(
      color: enabled ? cs.surfaceContainerLow : cs.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: fg),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: enabled
                                    ? cs.onSurfaceVariant
                                    : cs.onSurface.withValues(alpha: 0.38),
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「下载音频」的选择结果：格式 + SILK 的 -tencent 开关。
class _ExportChoice {
  const _ExportChoice(this.format, this.tencent);

  final TtsExportFormat format;
  final bool tencent;
}

/// 「下载」的格式选择弹窗：MP3 / SILK / SLK 三选一；选了 SILK 系再露出
/// 「腾讯兼容（-tencent）」开关 —— 默认开，下 silk/slk 基本就是为了发微信/QQ。
class _ExportFormatDialog extends StatefulWidget {
  const _ExportFormatDialog();

  @override
  State<_ExportFormatDialog> createState() => _ExportFormatDialogState();
}

class _ExportFormatDialogState extends State<_ExportFormatDialog> {
  TtsExportFormat _format = TtsExportFormat.mp3;
  bool _tencent = TtsMessageExport.defaultTencent;

  static String _descOf(AppLocalizations l10n, TtsExportFormat f) =>
      switch (f) {
        TtsExportFormat.mp3 => l10n.chatSimDownloadMp3Desc,
        TtsExportFormat.silk => l10n.chatSimDownloadSilkDesc,
        TtsExportFormat.slk => l10n.chatSimDownloadSlkDesc,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.chatSimDownloadTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                l10n.chatSimDownloadFormat,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            // RadioGroup 是新写法：RadioListTile 的 groupValue / onChanged
            // 在 3.32 之后已废弃，选中态由这个祖先统一管。
            RadioGroup<TtsExportFormat>(
              groupValue: _format,
              onChanged: (v) => setState(() => _format = v ?? _format),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final f in TtsExportFormat.values)
                    RadioListTile<TtsExportFormat>(
                      value: f,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(f.label),
                      subtitle: Text(_descOf(l10n, f)),
                    ),
                ],
              ),
            ),
            if (_format.isSilk)
              SwitchListTile(
                value: _tencent,
                onChanged: (v) => setState(() => _tencent = v),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.chatSimDownloadTencent),
                subtitle: Text(l10n.chatSimDownloadTencentDesc),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_ExportChoice(_format, _tencent)),
          child: Text(l10n.chatSimDownloadAction),
        ),
      ],
    );
  }
}
