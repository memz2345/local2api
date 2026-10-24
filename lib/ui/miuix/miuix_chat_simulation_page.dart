import 'dart:async' show unawaited;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField, MiuixTextFieldColors;
import 'package:local2api/widgets/context_ring.dart';
import 'package:local2api/widgets/miuix/miuix_text_field.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';
import 'package:local2api/l10n/app_localizations.dart';
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
import 'package:local2api/ui/miuix/miuix_call_page.dart' show pushMiuixCallPage;
import 'package:local2api/ui/miuix/miuix_character_card_page.dart'
    show pushMiuixCharacterCardPicker;
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/widgets/miuix/miuix_dialog.dart';
import 'package:local2api/widgets/miuix/miuix_page_popup_host.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';
import 'package:local2api/widgets/miuix/miuix_voice_record_sheet.dart';
import 'package:local2api/services/chat_avatar_store.dart';
import 'package:local2api/ui/miuix/miuix_chat_settings_page.dart';
import 'package:local2api/widgets/miuix/miuix_bottom_sheet.dart';

/// miuix 风格的「对话模拟」页（对应 Material 版 `ChatSimulationPage`）。
///
/// 与 Chatbox 的消息编辑体验对齐：三种角色（系统 / 用户 / 助手）都能改，
/// 点消息进编辑弹层（角色下拉 + 正文 + 取消 / 保存 / 保存并发送），
/// 发出去的请求体就是界面上这串消息（历史自动带上）。
///
/// 请求走本机代理：路由、容灾回退、Zen 指纹、请求日志全过一遍，
/// 模拟器里通了就等于真客户端能通。服务没跑就给提示 + 一键启动。
class MiuixChatSimulationPage extends StatefulWidget {
  const MiuixChatSimulationPage({
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

  /// 组名，仅用于标题上的副标题。
  final String? groupName;

  /// 这段对话存在哪一格（给模型组的 id）。空串 = 不落盘。
  final String scope;

  /// 组内可选的具体模型（「换模型」选择器的候选，不含 [model] 本身）。
  final List<String> groupModels;

  @override
  State<MiuixChatSimulationPage> createState() =>
      _MiuixChatSimulationPageState();
}

class _MiuixChatSimulationPageState extends State<MiuixChatSimulationPage> {
  /// 顶栏折叠行为（与组详情页同款）。
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();

  late final ChatSimController _sim = ChatSimController(
    model: widget.model,
    config: widget.controller.config,
    scope: widget.scope,
    groupModels: widget.groupModels,
  );

  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  /// 底部输入框以哪个角色发（默认用户）。
  ChatRole _inputRole = ChatRole.user;

  /// 发送模式：false = 正常发送（等回复）；true = 发送（模型不响应）。
  /// 点按执行当前模式，长按切换；只在当前页面内记住，不持久化。
  bool _sendOnlyMode = false;

  /// 待发附件：随下一条消息一起挂上（仅展示，不进请求上下文）。
  final List<ChatAttachment> _pending = [];

  @override
  void initState() {
    super.initState();
    // 默认接着上次聊（历史存本机）
    _sim.restore();
    _sim.addListener(_onSimChanged);
    widget.controller.server.state.addListener(_onServerChanged);
    // 自动播放要读 TtsSettings.autoPlay：这页可能比 TTS 设置页先打开，
    // load 幂等（_loaded 门），多调一次没成本。
    unawaited(TtsSettings.instance.load());
  }

  @override
  void dispose() {
    _sim.removeListener(_onSimChanged);
    widget.controller.server.state.removeListener(_onServerChanged);
    _behavior.state.dispose();
    _sim.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSimChanged() {
    if (mounted) setState(() {});
  }

  void _onServerChanged() {
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

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isNotEmpty || _pending.isNotEmpty) {
      _sim.add(_inputRole, text, List.of(_pending));
      _inputController.clear();
      _consumePending();
    }
    _scrollToBottom();
    // 发送时会自动带上历史（messages 全量）。
    await _sim.send();
    _scrollToBottom();
    _autoSpeakIfEnabled();
  }

  /// 只发不等：请求照样过本机代理（日志 / 统计都算），但不取回复。
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
    showMiuixToast(context, l10n.chatSimSentOnly);
    _scrollToBottom();
  }

  /// 附件直选（底栏工具行）：文件 / 相册图片 / 拍照。图片压成 ≤1024px
  /// JPEG 随消息发给模型，文件只取元信息纯展示。
  /// 附件只挂在用户消息上 —— 其他角色点了给个提示。
  Future<void> _attach(_AttachRequest request) async {
    final l10n = AppLocalizations.of(context);
    if (_inputRole != ChatRole.user) {
      showMiuixToast(context, l10n.chatSimAttachUserOnly);
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
      showMiuixToast(context, l10n.chatSimAttachFailed(a.error!));
    }
  }

  Future<void> _attachFile() => _attach(const _AttachRequest.file());

  Future<void> _attachImage() => _attach(const _AttachRequest.gallery());

  Future<void> _attachCamera() => _attach(const _AttachRequest.camera());

  /// 语音输入：弹出「按住说话」录音层，识别文本接在输入框已有内容后面。
  Future<void> _startVoiceRecord() async {
    final text = await showMiuixVoiceRecordSheet(
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
  /// 优先当前选中模型，再扫组对外名与组内模型 —— 与发现页入口的
  /// 「omniModelOf(upstream) ?? 主模型」语义一致，只是这里拿不到
  /// Upstream 对象，按模型名扫。
  String? get _omniModel {
    for (final name in [_sim.activeModel, widget.model, ...widget.groupModels]) {
      if (isOmniModelName(name)) return name;
    }
    return null;
  }

  /// 通话对端显示名：当前应用的角色卡名字优先（「和小语通话」，
  /// 不是「和 opencodezen 通话」），没有角色卡回落组名。
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
    await showMiuixBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MiuixText(
                l10n.callTitleAction,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              const SizedBox(height: 8),
              MiuixArrowPreference(
                title: l10n.callTitleVoice,
                summary: l10n.chatSimCallPeer(_callPeerName),
                startAction: const Icon(Icons.call_outlined),
                onClick: () {
                  Navigator.of(sheetCtx).pop();
                  _openCall(video: false);
                },
              ),
              const SizedBox(height: 8),
              MiuixArrowPreference(
                title: l10n.callTitleVideo,
                summary: omni == null ? l10n.callVideoNeedOmni : null,
                startAction: const Icon(Icons.videocam_outlined),
                enabled: omni != null,
                onClick: omni == null
                    ? null
                    : () {
                        Navigator.of(sheetCtx).pop();
                        _openCall(video: true);
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 推通话页：语音用当前选中的模型；视频用组内 Omni 模型（入口已保证
  /// 有 omni 才放行）。两边共用同一格聊天记录（scope）。
  void _openCall({required bool video}) {
    final omni = _omniModel;
    pushMiuixCallPage(
      context,
      controller: widget.controller,
      model: video ? (omni ?? _sim.activeModel) : _sim.activeModel,
      groupName: widget.groupName,
      displayName: _callPeerName,
      // 与对话模拟共用同一格聊天记录
      scope: widget.scope,
      startVideo: video,
    );
  }

  void _consumePending() {
    if (_pending.isEmpty) return;
    setState(() => _pending.clear());
  }

  Future<void> _saveAndSend(int index, ChatRole role, String content) async {
    // 改了中间某条就把它之后的都丢掉，再按这个前缀重发 —— 与「编辑历史后重发」
    // 的直觉一致（后面那些回答是旧前缀的产物，留着只会串味）。
    _sim.edit(index, role, content, truncateAfter: true);
    _scrollToBottom();
    await _sim.send();
    _scrollToBottom();
    _autoSpeakIfEnabled();
  }

  Future<void> _openEditor(int index) async {
    final l10n = AppLocalizations.of(context);
    final msg = _sim.messages[index];
    final textCtrl = TextEditingController(text: msg.content);
    var role = msg.role;

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MiuixTheme.of(context).colors.surface,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MiuixText(
                    l10n.chatSimEditTitle,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  const SizedBox(height: 12),
                  // 角色选择：系统 / 用户 / 助手（对应 Chatbox 那个角色切换）。
                  //
                  // 这里刻意用胶囊片而不是 MiuixOverlayDropdownPreference：
                  // 抽屉是挂在 Navigator 上的路由，不在页面那套 popup 宿主
                  // 作用域里，下拉菜单注册完没人渲染（点了没反应）；
                  // 而给抽屉单独套宿主会因为坐标系是抽屉那一块而把菜单弹歪。
                  Row(
                    children: [
                      _RoleAvatar(role: role, size: 40),
                      const SizedBox(width: 10),
                      for (final r in ChatRole.values) ...[
                        Expanded(
                          child: _RoleChip(
                            label: _roleLabel(l10n, r),
                            selected: role == r,
                            onTap: () => setSheet(() => role = r),
                          ),
                        ),
                        if (r != ChatRole.values.last) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  MiuixTextField(
                    controller: textCtrl,
                    label: l10n.chatSimEditTitle,
                    useLabelAsPlaceholder: true,
                    minLines: 4,
                    maxLines: 12,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      MiuixTextButton(
                        l10n.cancel,
                        onPressed: () => Navigator.of(sheetCtx).pop(),
                      ),
                      const SizedBox(width: 8),
                      MiuixTextButton(
                        l10n.chatSimSave,
                        onPressed: () => Navigator.of(sheetCtx).pop(_kSaveOnly),
                      ),
                      const SizedBox(width: 8),
                      MiuixTextButton(
                        l10n.chatSimSaveAndSend,
                        onPressed: () =>
                            Navigator.of(sheetCtx).pop(_kSaveAndSend),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final content = textCtrl.text;
    textCtrl.dispose();
    if (!mounted || action == null) return;
    if (action == _kSaveAndSend) {
      await _saveAndSend(index, role, content);
    } else {
      _sim.edit(index, role, content);
    }
  }

  Future<void> _addMessage() async {
    final l10n = AppLocalizations.of(context);
    final chosen = await showModalBottomSheet<ChatRole>(
      context: context,
      backgroundColor: MiuixTheme.of(context).colors.surface,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MiuixText(
                l10n.chatSimAddMessage,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              const SizedBox(height: 8),
              for (final r in ChatRole.values)
                MiuixArrowPreference(
                  title: _roleLabel(l10n, r),
                  startAction: _RoleAvatar(role: r, size: 28),
                  onClick: () => Navigator.of(sheetCtx).pop(r),
                ),
            ],
          ),
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

  Future<void> _clear() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showMiuixDialog<bool>(
      context: context,
      title: l10n.chatSimClear,
      message: l10n.chatSimClearConfirm,
      actions: [
        MiuixDialogAction(
          label: l10n.cancel,
          onPressed: (ctx) => Navigator.of(ctx).pop(false),
        ),
        MiuixDialogAction(
          label: l10n.confirm,
          primary: true,
          onPressed: (ctx) => Navigator.of(ctx).pop(true),
        ),
      ],
    );
    if (ok == true) _sim.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;

    // 弹层宿主罩在 Scaffold 外面（理由同 token 统计页）
    return MiuixPagePopupHost(
      child: Material(
        type: MaterialType.transparency,
        child: MiuixScaffold(
          containerColor: colors.surface,
          topBar: MiuixBlurTopBar(
            scrollBehavior: _behavior,
            title: _barTitle,
            navigationIcon: MiuixIconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const MiuixAppIcon(
                AppIconNames.back,
                fallback: Icons.arrow_back,
              ),
            ),
            actions: [
              // 角色卡：换一个更贴合的场景（人设 system + 预制问答）。
              MiuixIconButton(
                onPressed: _pickCharacter,
                child: const Icon(Icons.face_retouching_natural),
              ),
              // 其余动作收进「三个点」（同主题页：miuix 没有命令式菜单，
              // 用底部抽屉当菜单）。
              MiuixIconButton(
                onPressed: _showMoreSheet,
                child: const MiuixAppIcon(
                  AppIconNames.more,
                  fallback: Icons.more_vert,
                ),
              ),
            ],
          ),
          // 底部输入行放底栏，脚手架把它的高度算进内容 padding.bottom。
          bottomBar: _buildComposer(l10n, colors),
          // 页面顶部有固定说明条（不可滚动），正文落在顶栏与输入行之间：
          // 顶栏高度垫进 padding.top；padding.bottom 不用在根部吃掉 ——
          // 消息列表铺到底栏下面穿过，底部输入台的毛玻璃才有东西可糊。
          content: (padding) => MiuixScrollBehaviorListener(
            behavior: _behavior,
            child: _buildBody(l10n, colors, padding),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    AppLocalizations l10n,
    MiuixColors colors,
    EdgeInsets contentPadding,
  ) {
    return Column(
      children: [
        if (!_serverRunning)
          Padding(
            padding: EdgeInsets.fromLTRB(16, contentPadding.top + 10, 16, 6),
            child: MiuixGroupCard(
              insideMargin: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              colors: MiuixCardColors(
                color: colors.tertiaryContainer,
                contentColor: colors.onTertiaryContainer,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: MiuixText(l10n.chatSimServerOff, fontSize: 13),
                  ),
                  const SizedBox(width: 8),
                  MiuixTextButton(
                    l10n.chatSimStartServer,
                    onPressed: widget.controller.toggle,
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            // 顶部垫出顶栏高度；底部垫出输入台高度 —— 列表从玻璃下面穿过。
            padding: EdgeInsets.fromLTRB(
              16,
              contentPadding.top + (_serverRunning ? 10 : 6),
              16,
              contentPadding.bottom + 16,
            ),
            itemCount: _sim.messages.length + (_sim.sending ? 1 : 0),
            itemBuilder: (context, i) {
              if (i >= _sim.messages.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: MiuixText(
                    l10n.chatSimSending,
                    fontSize: 13,
                    color: colors.onSurfaceVariantSummary,
                  ),
                );
              }
              return _MiuixMessageBubble(
                message: _sim.messages[i],
                onTap: () => _openEditor(i),
                // 助手消息长按弹菜单（复制 / 删除 / 朗读 / 重新回答 / 下载）；
                // 其余角色保持原来的「长按直接删这条」—— 沙盒里删错了重发就是。
                onLongPress: () {
                  if (_sim.messages[i].role == ChatRole.assistant) {
                    _showMessageMenu(i);
                    return;
                  }
                  _sim.removeAt(i);
                  showMiuixToast(context, l10n.chatSimRemoved);
                },
                onCopy: () async {
                  Clipboard.setData(
                    ClipboardData(text: _sim.messages[i].content),
                  );
                  showMiuixToast(context, l10n.copied);
                },
                onSpeak: () => _speakMessage(_sim.messages[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 朗读这条助手消息：按「对话设置 → 默认 TTS 服务商」路由
  /// （本地直接合成，云端走本机代理 /v1/audio/speech）。
  /// 当前角色卡配了音色样本就带上（本地克隆 / 云端 voiceclone）。
  Future<void> _speakMessage(ChatMsg msg) async {
    final tag = 'msg:${identityHashCode(msg)}';
    final voice =
        characterStore
                .cardOf(_sim.appliedCharacterId ?? '')
                ?.voiceSamplePath ??
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
      showMiuixToast(
        context,
        '$e'.replaceFirst(RegExp(r'^(Exception:\s*)+'), ''),
        error: true,
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
  /// 与顶栏「三个点」同一套做法 —— miuix 没有命令式菜单入口，用底部抽屉
  /// 当菜单（对话框留给确认 / 表单，五项塞进去会挤成一条）。
  /// 「下载」只在编了原生编码器的平台（Android）上出现。
  Future<void> _showMessageMenu(int index) async {
    if (index < 0 || index >= _sim.messages.length) return;
    final l10n = AppLocalizations.of(context);
    final msg = _sim.messages[index];
    final tag = 'msg:${identityHashCode(msg)}';
    // 正在朗读这条 → 菜单里那一项变成「停止朗读」（与气泡上的喇叭按钮
    // 同一条口径）。
    final speaking = TtsSpeechService.instance.isActive(tag);

    await showMiuixBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MiuixText(
                l10n.chatSimMsgMenuTitle,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              const SizedBox(height: 8),
              MiuixArrowPreference(
                title: l10n.copy,
                startAction: const Icon(Icons.copy_rounded),
                onClick: () {
                  Navigator.of(sheetCtx).pop();
                  Clipboard.setData(ClipboardData(text: msg.content));
                  if (!mounted) return;
                  showMiuixToast(context, l10n.copied);
                },
              ),
              const SizedBox(height: 8),
              MiuixArrowPreference(
                title: l10n.commonDelete,
                startAction: const Icon(Icons.delete_outline_rounded),
                onClick: () {
                  Navigator.of(sheetCtx).pop();
                  // 无确认弹窗 —— 沙盒里删错了重发就是（与原来长按即删一致）。
                  _sim.removeAt(index);
                  if (!mounted) return;
                  showMiuixToast(context, l10n.chatSimRemoved);
                },
              ),
              const SizedBox(height: 8),
              MiuixArrowPreference(
                title: speaking
                    ? l10n.chatSimMsgStopSpeak
                    : l10n.chatSimMsgSpeak,
                startAction: Icon(
                  speaking ? Icons.stop_rounded : Icons.volume_up_outlined,
                ),
                onClick: () {
                  Navigator.of(sheetCtx).pop();
                  _speakMessage(msg);
                },
              ),
              const SizedBox(height: 8),
              MiuixArrowPreference(
                title: l10n.chatSimMsgRegenerate,
                startAction: const Icon(Icons.refresh_rounded),
                onClick: () {
                  Navigator.of(sheetCtx).pop();
                  _regenerateFrom(index);
                },
              ),
              if (TtsMessageExport.isSupported) ...[
                const SizedBox(height: 8),
                MiuixArrowPreference(
                  title: l10n.chatSimMsgDownload,
                  summary: 'MP3 / SILK / SLK',
                  startAction: const Icon(Icons.download_outlined),
                  onClick: () {
                    Navigator.of(sheetCtx).pop();
                    _downloadMessage(msg);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
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

  /// 「下载」：先用 [showMiuixDialog] 选格式（MP3 / SILK / SLK，SILK 系带
  /// -tencent 开关），再合成 → 转码 → 系统「另存为」。
  Future<void> _downloadMessage(ChatMsg msg) async {
    final l10n = AppLocalizations.of(context);
    // 草稿写在调用方的局部变量里，「下载」按钮 pop 时才打包 —— 与上游编辑页
    // 那几个对话框同一条口径（content 自己的 State 不许被调用方 dispose）。
    var format = TtsExportFormat.mp3;
    var tencent = TtsMessageExport.defaultTencent;
    final picked = await showMiuixDialog<_MiuixExportChoice>(
      context: context,
      title: l10n.chatSimDownloadTitle,
      content: _MiuixExportFormatDialogBody(
        formatLabelOf: (f) => f.label,
        formatDescOf: (f) => switch (f) {
          TtsExportFormat.mp3 => l10n.chatSimDownloadMp3Desc,
          TtsExportFormat.silk => l10n.chatSimDownloadSilkDesc,
          TtsExportFormat.slk => l10n.chatSimDownloadSlkDesc,
        },
        tencentTitle: l10n.chatSimDownloadTencent,
        tencentDesc: l10n.chatSimDownloadTencentDesc,
        initialFormat: format,
        initialTencent: tencent,
        onChanged: (f, t) {
          format = f;
          tencent = t;
        },
      ),
      actions: [
        MiuixDialogAction(
          label: l10n.cancel,
          onPressed: (ctx) => Navigator.of(ctx).pop(),
        ),
        MiuixDialogAction(
          label: l10n.chatSimDownloadAction,
          primary: true,
          onPressed: (ctx) =>
              Navigator.of(ctx).pop(_MiuixExportChoice(format, tencent)),
        ),
      ],
    );
    if (picked == null || !mounted) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    final fileName = TtsExportService.fileNameFor(
      picked.format,
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
      showMiuixDialog<void>(
        context: context,
        barrierDismissible: false,
        content: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: MiuixCircularProgressIndicator(),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: MiuixText(l10n.chatSimDownloadBusy, fontSize: 15),
            ),
          ],
        ),
      ),
    );

    try {
      final voice =
          characterStore.cardOf(_sim.appliedCharacterId ?? '')
              ?.voiceSamplePath ??
          '';
      final bytes = await TtsMessageExport.render(
        text: msg.content,
        config: widget.controller.config,
        voiceSamplePath: voice.isEmpty ? null : voice,
        format: picked.format,
        tencent: picked.tencent,
      );
      // 合成 / 转码做完就收掉转圈：接下来的系统「另存为」要用户自己操作，
      // 上面不该再压一层模态。
      closeBusy();
      final path = await TtsMessageExport.save(
        bytes: bytes,
        fileName: fileName,
        format: picked.format,
      );
      if (!mounted) return;
      showMiuixToast(
        context,
        path == null
            ? l10n.chatSimDownloadCanceled
            : l10n.chatSimDownloadSaved(path),
      );
    } catch (e) {
      closeBusy();
      if (!mounted) return;
      showMiuixToast(
        context,
        l10n.chatSimDownloadFailed(
          '$e'.replaceFirst(RegExp(r'^(Exception:\s*)+'), ''),
        ),
        error: true,
      );
    }
  }

  /// 模型选择弹层：第一项固定「全部（整组共享）」，下面是组内具体模型。
  /// 打开角色卡页挑一个场景：选中即整段重铺（人设 system + 预制问答）。
  /// 返回 null = 只是看了看没选；哨兵卡（id 空）= 回默认场景。
  Future<void> _pickCharacter() async {
    final l10n = AppLocalizations.of(context);
    final card = await pushMiuixCharacterCardPicker(context);
    if (!mounted || card == null) return;
    if (card.id.isEmpty) {
      _sim.resetCharacter();
      showMiuixToast(context, l10n.characterResetDone);
    } else {
      _sim.applyCharacter(card);
      showMiuixToast(context, l10n.characterApplied(card.name));
    }
    _scrollToBottom();
  }

  /// 顶栏「三个点」：添加消息 / 重新生成 / 头像设置 / 清空 / 对话设置。
  /// miuix 没有命令式菜单入口，用底部抽屉当菜单（同主题页做法）。
  Future<void> _showMoreSheet() async {
    final l10n = AppLocalizations.of(context);
    await showMiuixBottomSheet<void>(
      context: context,
      // 五个菜单项 + 标题在小屏上会超默认 9/16 高度上限，放开自由高度。
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MiuixText(
                l10n.chatSimMore,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              const SizedBox(height: 8),
              MiuixArrowPreference(
                title: l10n.chatSimAddMessage,
                startAction: const Icon(Icons.add_comment_outlined),
                onClick: () {
                  Navigator.of(sheetCtx).pop();
                  _addMessage();
                },
              ),
              if (!_sim.sending)
                MiuixArrowPreference(
                  title: l10n.chatSimRegenerate,
                  startAction: const Icon(Icons.refresh),
                  onClick: () {
                    Navigator.of(sheetCtx).pop();
                    _sim.regenerate();
                  },
                ),
              MiuixArrowPreference(
                title: l10n.chatSimAvatarTitle,
                startAction: const Icon(Icons.account_circle_outlined),
                onClick: () {
                  Navigator.of(sheetCtx).pop();
                  _openAvatarSheet();
                },
              ),
              MiuixArrowPreference(
                title: l10n.chatSimClear,
                startAction: const Icon(Icons.delete_sweep_outlined),
                onClick: () {
                  Navigator.of(sheetCtx).pop();
                  _clear();
                },
              ),
              MiuixArrowPreference(
                title: l10n.chatSettingsTitle,
                startAction: const Icon(Icons.settings_outlined),
                onClick: () {
                  Navigator.of(sheetCtx).pop();
                  _openChatSettings();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 打开「对话设置」二级页（本地 TTS / 角色卡管理）。
  void _openChatSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MiuixChatSettingsPage(controller: widget.controller),
      ),
    );
  }

  /// 「头像设置」抽屉：用户 / 助手两个圆形头像，各自可换图 / 恢复默认。
  Future<void> _openAvatarSheet() async {
    final l10n = AppLocalizations.of(context);
    // 启动时已 load 过；这里补一次（幂等），冷启动直达本页也不虚。
    await chatAvatarStore.load();
    if (!mounted) return;
    await showMiuixBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MiuixText(
                l10n.chatSimAvatarTitle,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              const SizedBox(height: 8),
              _MiuixAvatarSettingRow(
                role: ChatRole.user,
                label: l10n.chatSimAvatarUser,
                onPickGallery: () => _pickAvatar(sheetCtx, ChatRole.user),
                onPickCamera: () =>
                    _pickAvatar(sheetCtx, ChatRole.user, fromCamera: true),
                onReset: () => chatAvatarStore.setAvatar(ChatRole.user, null),
              ),
              _MiuixAvatarSettingRow(
                role: ChatRole.assistant,
                label: l10n.chatSimAvatarAssistant,
                onPickGallery: () => _pickAvatar(sheetCtx, ChatRole.assistant),
                onPickCamera: () =>
                    _pickAvatar(sheetCtx, ChatRole.assistant, fromCamera: true),
                onReset: () =>
                    chatAvatarStore.setAvatar(ChatRole.assistant, null),
              ),
            ],
          ),
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
      showMiuixToast(context, l10n.chatSimAvatarUpdated);
    } else if (r == AttachmentPick.failed) {
      showMiuixToast(
        context,
        l10n.chatSimAvatarFailed(ChatAvatarStore.lastPickError ?? '–'),
        error: true,
      );
    }
  }

  Future<void> _pickModel() async {
    final l10n = AppLocalizations.of(context);
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MiuixTheme.of(context).colors.surface,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MiuixText(
                l10n.chatSimModelPicker,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    MiuixArrowPreference(
                      title: l10n.chatSimModelAll,
                      summary: l10n.chatSimModelAllDesc,
                      startAction: const Icon(Icons.hub_outlined),
                      onClick: () => Navigator.of(sheetCtx).pop(widget.model),
                    ),
                    for (final name in widget.groupModels)
                      MiuixArrowPreference(
                        title: name,
                        summary: l10n.chatSimModelSpecificDesc,
                        startAction: const Icon(Icons.memory_outlined),
                        onClick: () => Navigator.of(sheetCtx).pop(name),
                      ),
                    // 「发送图片 / 仅发文字」开关：图片默认随消息发给模型；
                    // 纯文本车道收到多模态 content 会直接 400。
                    MiuixArrowPreference(
                      title: _sim.sendImages
                          ? l10n.chatSimSendImages
                          : l10n.chatSimSendTextOnly,
                      startAction: Icon(
                        _sim.sendImages
                            ? Icons.image_outlined
                            : Icons.text_fields,
                      ),
                      onClick: () {
                        Navigator.of(sheetCtx).pop();
                        final now = _sim.toggleSendImages();
                        showMiuixToast(
                          context,
                          now ? l10n.chatSimImagesOn : l10n.chatSimImagesOff,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    _sim.setActiveModel(chosen);
  }

  /// 底部输入台（毛玻璃，对齐主页底栏）：第一行「角色头像 + 输入框 +
  /// 占用环 + 发送」，第二行工具行「模型 / 文件 / 语音 / 图片 / 拍照」。
  /// 整块（含手势条区域）都罩在 BackdropFilter 里，消息列表从下面穿过。
  Widget _buildComposer(AppLocalizations l10n, MiuixColors colors) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10.8, sigmaY: 10.8),
        child: Container(
          color: colors.surface.withValues(alpha: 0.62),
          child: SafeArea(
            top: false,
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
                            _MiuixAttachmentChip(
                              attachment: _pending[i],
                              onRemove: () =>
                                  setState(() => _pending.removeAt(i)),
                            ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      // 输入角色：点按在 系统 / 用户 / 助手 之间循环。
                      MiuixIconButton(
                        onPressed: _cycleInputRole,
                        child: _RoleAvatar(role: _inputRole, size: 32),
                      ),
                      // 输入框本体也是毛玻璃（嵌套 BackdropFilter）。
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(
                              sigmaX: 10.8,
                              sigmaY: 10.8,
                            ),
                            child: MiuixTextField(
                              controller: _inputController,
                              label: l10n.chatSimHintInput,
                              useLabelAsPlaceholder: true,
                              minLines: 1,
                              maxLines: 5,
                              insideMargin: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              colors: MiuixTextFieldColors(
                                backgroundColor: colors.secondaryContainer
                                    .withValues(alpha: 0.5),
                                labelColor: colors.onSurfaceVariantSummary,
                                borderColor: colors.primary,
                              ),
                              onSubmitted: (_) => _sendCurrentMode(),
                            ),
                          ),
                        ),
                      ),
                      // 上下文占用环：点开看详情。
                      _ctxRing(l10n),
                      // 发送（两态）：点按执行当前模式，长按在「发送」与
                      // 「发送（模型不响应）」之间切换。
                      GestureDetector(
                        onLongPress: _sim.sending ? null : _toggleSendMode,
                        child: MiuixGroupCard(
                          cornerRadius: 16,
                          insideMargin: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 12,
                          ),
                          feedbackType: MiuixPressFeedbackType.sink,
                          colors: MiuixCardColors(
                            color: colors.primary,
                            contentColor: colors.onPrimary,
                          ),
                          onPressed: _sim.sending ? null : _sendCurrentMode,
                          child: Icon(
                            _sendOnlyMode
                                ? Icons.flight_takeoff
                                : Icons.send_outlined,
                            size: 20,
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
                      Tooltip(
                        message: l10n.chatSimModelPicker,
                        child: MiuixIconButton(
                          onPressed: widget.groupModels.isEmpty
                              ? null
                              : _pickModel,
                          child: const Icon(Icons.memory_outlined),
                        ),
                      ),
                      Tooltip(
                        message: l10n.chatSimAttachFile,
                        child: MiuixIconButton(
                          onPressed: _attachFile,
                          child: const Icon(Icons.insert_drive_file_outlined),
                        ),
                      ),
                      Tooltip(
                        message: l10n.chatSimVoiceInput,
                        child: MiuixIconButton(
                          onPressed: _startVoiceRecord,
                          child: const Icon(Icons.mic_none),
                        ),
                      ),
                      Tooltip(
                        message: l10n.chatSimAttachImage,
                        child: MiuixIconButton(
                          onPressed: _attachImage,
                          child: const Icon(Icons.image_outlined),
                        ),
                      ),
                      Tooltip(
                        message: l10n.chatSimAttachCamera,
                        child: MiuixIconButton(
                          onPressed: _attachCamera,
                          child: const Icon(Icons.photo_camera_outlined),
                        ),
                      ),
                      Tooltip(
                        message: l10n.callTitleAction,
                        child: MiuixIconButton(
                          onPressed: _showCallSheet,
                          child: const Icon(Icons.call_outlined),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
    showMiuixToast(
      context,
      _sendOnlyMode ? l10n.chatSimSendModeOnly : l10n.chatSimSend,
    );
  }

  /// 上下文占用环：点开看详情弹窗（百分比 / 用量与上限 / 精确还是估算 /
  /// 输出上限 / 请求模型 / 消息与图片数）。以前挂在 tooltip 上，
  /// 手机上根本看不清，数字又多。
  Widget _ctxRing(AppLocalizations l10n) {
    final d = _sim.contextDetails();
    final colors = MiuixTheme.of(context).colors;
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
            trackColor: colors.onSurfaceVariantActions,
          ),
        ),
      ),
    );
  }

  Future<void> _showContextDetails(AppLocalizations l10n) async {
    final d = _sim.contextDetails();
    final colors = MiuixTheme.of(context).colors;
    final hot = d.percent >= 90;
    await showMiuixDialog<void>(
      context: context,
      title: l10n.contextDetailTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MiuixText(
            l10n.contextDetailPercent(d.label),
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: hot ? colors.error : colors.primary,
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (d.percent / 100).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: colors.secondaryContainer,
              color: hot ? colors.error : colors.primary,
            ),
          ),
          const SizedBox(height: 16),
          _DetailLine(
            text: l10n.contextDetailUsed('${d.used}', '${d.limit}'),
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
                ? l10n.contextDetailOutput('${d.maxOutput}')
                : l10n.contextDetailOutputNone,
            muted: true,
          ),
          const SizedBox(height: 6),
          _DetailLine(text: l10n.contextDetailModel(d.model), mono: true),
          _DetailLine(
            text: l10n.contextDetailMessages('${d.messages}', '${d.images}'),
            muted: true,
          ),
        ],
      ),
      actions: [
        MiuixDialogAction(
          label: l10n.contextDetailClose,
          onPressed: (ctx) => Navigator.of(ctx).pop(),
        ),
      ],
    );
  }

  /// 底部输入角色循环：用户 → 系统 → 助手 → 用户。
  void _cycleInputRole() {
    final next =
        (ChatRole.values.indexOf(_inputRole) + 1) % ChatRole.values.length;
    setState(() => _inputRole = ChatRole.values[next]);
  }
}

const String _kSaveOnly = 'save';
const String _kSaveAndSend = 'saveAndSend';

/// miuix 气泡里的附件区：图片渲染缩略图（它也是发出去的那份字节），
/// 文件渲染成「图标 + 文件名 + 大小」胶囊（文件只展示，不进请求体）。
class _MiuixBubbleAttachments extends StatelessWidget {
  const _MiuixBubbleAttachments({required this.attachments});

  final List<ChatAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
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
                color: colors.onSurfaceVariantActions.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.insert_drive_file,
                    size: 18,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: MiuixText(
                      a.name,
                      fontSize: 12,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (formatAttachmentSize(a.sizeBytes).isNotEmpty) ...[
                    const SizedBox(width: 6),
                    MiuixText(
                      formatAttachmentSize(a.sizeBytes),
                      fontSize: 11,
                      color: colors.onSurfaceVariantSummary,
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
class _MiuixAttachmentChip extends StatelessWidget {
  const _MiuixAttachmentChip({
    required this.attachment,
    required this.onRemove,
  });

  final ChatAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final sizeText = formatAttachmentSize(attachment.sizeBytes);
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
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
            color: colors.onSurfaceVariantActions,
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: MiuixText(
              sizeText.isEmpty
                  ? attachment.name
                  : '${attachment.name} · $sizeText',
              fontSize: 12,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            onTap: onRemove,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.close,
                size: 14,
                color: colors.onSurfaceVariantActions,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 消息气泡：头像 + 角色名 + 附件 + 正文 + 页脚（字数 / 耗时）。
///
/// 点整条进编辑（三种角色都能改）；长按助手消息弹操作菜单，长按其余角色
/// **立即删除**（无确认弹窗）。助手那条多一个复制按钮。
class _MiuixMessageBubble extends StatelessWidget {
  const _MiuixMessageBubble({
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
    final colors = MiuixTheme.of(context).colors;
    final isUser = message.role == ChatRole.user;

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
            child: MiuixGroupCard(
              insideMargin: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              feedbackType: MiuixPressFeedbackType.sink,
              onPressed: onTap,
              onLongPress: onLongPress,
              colors: message.error
                  ? MiuixCardColors(
                      color: colors.errorContainer,
                      contentColor: colors.onErrorContainer,
                    )
                  : MiuixCardColors(
                      color: colors.secondaryContainer,
                      contentColor: colors.onSecondaryContainer,
                    ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MiuixText(
                    switch (message.role) {
                      ChatRole.system => l10n.chatSimRoleSystem,
                      ChatRole.user => l10n.chatSimRoleUser,
                      ChatRole.assistant => l10n.chatSimRoleAssistant,
                    },
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurfaceVariantSummary,
                  ),
                  const SizedBox(height: 4),
                  // 附件：图片渲染缩略图（发请求时带的就是它），
                  // 文件渲染成名称胶囊（只展示）。
                  if (message.attachments.isNotEmpty) ...[
                    _MiuixBubbleAttachments(attachments: message.attachments),
                    const SizedBox(height: 6),
                  ],
                  MiuixText(
                    message.content.isEmpty ? '（空）' : message.content,
                    fontSize: 14,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: MiuixText(
                          l10n.chatSimMeta(
                            chatWordCount(message.content),
                            formatElapsed(message.elapsedMs),
                          ),
                          fontSize: 11,
                          color: colors.onSurfaceVariantSummary,
                        ),
                      ),
                      if (message.role == ChatRole.assistant) ...[
                        _SpeakButton(
                          tag: 'msg:${identityHashCode(message)}',
                          onSpeak: onSpeak,
                        ),
                        MiuixIconButton(
                          onPressed: onCopy,
                          child: const Icon(Icons.copy, size: 16),
                        ),
                      ],
                    ],
                  ),
                  // 响应模型：走容灾路由时「真实车道 + 请求的对外名」一起标。
                  if (message.role == ChatRole.assistant &&
                      message.servedModel != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.memory,
                          size: 12,
                          color: colors.onSurfaceVariantSummary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: MiuixText(
                            message.routed
                                ? l10n.chatSimServedModelVia(
                                    message.lane!,
                                    message.model!,
                                  )
                                : l10n.chatSimServedModel(message.servedModel!),
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: colors.onSurfaceVariantSummary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
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
    return AnimatedBuilder(
      animation: TtsSpeechService.instance,
      builder: (context, _) {
        final svc = TtsSpeechService.instance;
        final mine = svc.activeTag == tag && !svc.isIdle;
        if (mine && svc.status != TtsSpeechStatus.playing) {
          return const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        return MiuixIconButton(
          onPressed: onSpeak,
          child: Icon(
            mine ? Icons.stop : Icons.volume_up_outlined,
            size: 16,
          ),
        );
      },
    );
  }
}

/// 角色选择片：用 MiuixCard 当胶囊（与 token 统计页的范围片同一套做法）。
class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixGroupCard(
      cornerRadius: 999,
      insideMargin: const EdgeInsets.symmetric(vertical: 10),
      feedbackType: MiuixPressFeedbackType.sink,
      onPressed: onTap,
      colors: selected
          ? MiuixCardColors(
              color: colors.primary,
              contentColor: colors.onPrimary,
            )
          : null,
      child: Center(
        child: MiuixText(
          label,
          fontSize: 13,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
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
        final colors = MiuixTheme.of(context).colors;
        final (icon, tint) = switch (role) {
          ChatRole.system => (Icons.settings, const Color(0xFFF07C1E)),
          ChatRole.user => (Icons.person, const Color(0xFF9E9E9E)),
          ChatRole.assistant => (Icons.smart_toy, const Color(0xFF2F7FE0)),
        };
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
          child: Icon(icon, size: size * 0.55, color: colors.onPrimary),
        );
      },
    );
  }
}

/// 「头像设置」抽屉里的一行：当前头像 + 角色名 + 「从相册选择 / 拍照 /
/// 恢复默认（没配过头像时不显示）」。头像变化靠 ListenableBuilder 即时刷新。
class _MiuixAvatarSettingRow extends StatelessWidget {
  const _MiuixAvatarSettingRow({
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
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _RoleAvatar(role: role, size: 48),
                const SizedBox(width: 14),
                Expanded(child: MiuixText(label, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                MiuixTextButton(
                  l10n.chatSimAvatarPick,
                  onPressed: onPickGallery,
                ),
                MiuixTextButton(
                  l10n.chatSimAvatarCamera,
                  onPressed: onPickCamera,
                ),
                if (chatAvatarStore.hasAvatarOf(role))
                  MiuixTextButton(
                    l10n.chatSimAvatarReset,
                    onPressed: onReset,
                  ),
              ],
            ),
          ],
        ),
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
    final colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: MiuixText(
        text,
        fontSize: muted ? 12 : 13,
        fontWeight: emphasis ? FontWeight.w700 : FontWeight.w500,
        fontFamily: mono ? 'monospace' : null,
        color: muted ? colors.onSurfaceVariantSummary : colors.onSurface,
      ),
    );
  }
}

/// 组详情页入口：挑了模型就推这一页。
Future<void> pushMiuixChatSimulation(
  BuildContext context, {
  required ServerController controller,
  required String model,
  String? groupName,
  String scope = '',
  List<String> groupModels = const [],
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => MiuixChatSimulationPage(
      controller: controller,
      model: model,
      groupName: groupName,
      scope: scope,
      groupModels: groupModels,
    ),
  ),
);

/// 车道页顶栏那个「对话模拟」按钮。
Widget buildMiuixChatSimulationAction({
  required BuildContext context,
  required ServerController controller,
  required String model,
  String? groupName,
  String scope = '',
  List<String> groupModels = const [],
}) => MiuixIconButton(
  onPressed: () => pushMiuixChatSimulation(
    context,
    controller: controller,
    model: model,
    groupName: groupName,
    scope: scope,
    groupModels: groupModels,
  ),
  child: const MiuixAppIcon(
    AppIconNames.recent,
    fallback: Icons.forum_outlined,
  ),
);

/// 「下载音频」的选择结果：格式 + SILK 的 -tencent 开关。
class _MiuixExportChoice {
  const _MiuixExportChoice(this.format, this.tencent);

  final TtsExportFormat format;
  final bool tencent;
}

/// 「下载」对话框的正文：三种格式单选，选中 SILK 系时再露出
/// 「腾讯兼容（-tencent）」开关（默认开 —— 下 silk/slk 基本就是为了发微信/QQ）。
///
/// 自己的状态自己管，改动经 [onChanged] 回写给调用方的局部变量；「下载」
/// 按钮在对话框动作行上，pop 时把当前草稿打包成 [_MiuixExportChoice]。
class _MiuixExportFormatDialogBody extends StatefulWidget {
  const _MiuixExportFormatDialogBody({
    required this.formatLabelOf,
    required this.formatDescOf,
    required this.tencentTitle,
    required this.tencentDesc,
    required this.initialFormat,
    required this.initialTencent,
    required this.onChanged,
  });

  final String Function(TtsExportFormat) formatLabelOf;
  final String Function(TtsExportFormat) formatDescOf;
  final String tencentTitle;
  final String tencentDesc;
  final TtsExportFormat initialFormat;
  final bool initialTencent;
  final void Function(TtsExportFormat format, bool tencent) onChanged;

  @override
  State<_MiuixExportFormatDialogBody> createState() =>
      _MiuixExportFormatDialogBodyState();
}

class _MiuixExportFormatDialogBodyState
    extends State<_MiuixExportFormatDialogBody> {
  late TtsExportFormat _format = widget.initialFormat;
  late bool _tencent = widget.initialTencent;

  void _emit() => widget.onChanged(_format, _tencent);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in TtsExportFormat.values)
          MiuixRadioButtonPreference(
            title: widget.formatLabelOf(f),
            summary: widget.formatDescOf(f),
            selected: f == _format,
            insideMargin: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            onClick: () => setState(() {
              _format = f;
              _emit();
            }),
          ),
        if (_format.isSilk)
          MiuixSwitchPreference(
            title: widget.tencentTitle,
            summary: widget.tencentDesc,
            value: _tencent,
            insideMargin: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            onChanged: (v) => setState(() {
              _tencent = v;
              _emit();
            }),
          ),
      ],
    );
  }
}
