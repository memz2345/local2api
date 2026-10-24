import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart'
    hide MiuixTextField, MiuixTextFieldColors;

import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/call_settings.dart';
import 'package:local2api/services/character_store.dart';
import 'package:local2api/services/chat_avatar_store.dart';
import 'package:local2api/services/chat_simulation.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/speech_input_service.dart';
import 'package:local2api/services/tts/tts_chat_speak.dart';
import 'package:local2api/services/tts/tts_speech_service.dart';
import 'package:local2api/widgets/hexagon_collision_background.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';

import 'miuix_call_settings_page.dart';

/// miuix 风格的「AI 通话」页（结构参考 vivo 电话管理的 InCallUI）。
///
/// 通话链路（任何模型都能用）：
/// 用户说话 → 语音转文字 → 走本机代理发给模型 → TTS 朗读回复 →
/// 自动回到「听」——连续对话。这段对话与「对话模拟」[scope] 共用同一本
/// 账（聊天记录同步，模拟页里能回看/续接）。
///
/// Omni 全模态模型额外解锁（见 [MiuixCallSettingsPage]）：
/// - 允许打断：模型说话时可以随时插话；
/// - 允许调用摄像头：视频通话把画面发送给模型。
/// 非 Omni 模型照常能打，只是这两项置灰。
///
/// 视觉：背景是「双六边形」动态壁纸（跟随主题色），中间头像 + 名字 +
/// 状态/计时 + 实时字幕，底部一排圆形操作键（麦克风 / 免提 / 视频 / 挂断）。
class MiuixCallPage extends StatefulWidget {
  const MiuixCallPage({
    super.key,
    required this.controller,
    required this.model,
    this.groupName,
    this.scope = '',
    this.displayName,
    this.startVideo = false,
  });

  final ServerController controller;

  /// 通话对端的模型对外名 —— 名字含 omni 才解锁打断/摄像头两项高级能力。
  final String model;

  /// 对端显示名（上游组名）；没有就显示模型名。
  final String? groupName;

  /// 对端显示名的最高优先级来源：当前应用的角色卡名字。从对话模拟页
  /// 发起通话时带上 —— 通话对象是「这个角色」，不是这个模型组。
  final String? displayName;

  /// 聊天记录存哪一格（与对话模拟同一个 scope，两边共用一本账）。
  final String scope;

  /// 从「视频通话」入口进来：直接以视频模式接通（入口处已校验 omni，
  /// 这里再兜一道底，非 omni 一律回落语音态）。
  final bool startVideo;

  @override
  State<MiuixCallPage> createState() => _MiuixCallPageState();
}

/// 通话状态机。
enum _TalkState {
  /// 正在接通（进入后的短暂过渡）。
  dialing,

  /// 在听（ASR 收音中）。
  listening,

  /// 思考中（等模型回复）。
  thinking,

  /// 说话中（TTS 播放回复）。
  speaking,

  /// 已挂断（短暂展示后退出）。
  ended,
}

class _MiuixCallPageState extends State<MiuixCallPage> {
  late final bool _omni = isOmniModelName(widget.model);

  /// 与对话模拟共用同一本聊天记录（同一 scope）。
  late final ChatSimController _sim = ChatSimController(
    model: widget.model,
    config: widget.controller.config,
    scope: widget.scope,
  );

  final SpeechInputService _speech = SpeechInputService();
  late final String _ttsTag = 'call:${identityHashCode(this)}';

  _TalkState _state = _TalkState.dialing;
  bool _speaker = false;
  late bool _video = widget.startVideo && _omni;
  bool _allowInterrupt = true;
  bool _allowCamera = true;

  /// 收音引擎起不来（权限/无服务）：状态文字提示，麦克风键点击重试。
  bool _asrFail = false;

  /// 收音中的实时文本。
  String _liveText = '';

  /// 本轮用户定稿文本。
  String _userLine = '';

  /// 本轮模型回复（或错误说明）。
  String _replyLine = '';
  bool _replyFailed = false;

  DateTime? _connectedAt;
  Timer? _dialTimer;
  Timer? _tickTimer;
  Timer? _exitTimer;

  /// 轮次号：所有异步回调回来先对号（挂断 / 打断 / 新轮都会 ++）。
  int _turn = 0;

  /// TTS 是否进入过「非 idle」—— 用于把「回到 idle」识别成播放完成。
  bool _ttsRan = false;

  /// 对话记录面板是否打开（页面右滑打开）。
  bool _recordOpen = false;

  /// 页面上的水平拖动累计（判断右滑手势）。
  double _hDragDx = 0;

  /// 记录面板的滚动控制器（打开时滚到最新一条）。
  final ScrollController _recordsScroll = ScrollController();

  bool get _serverRunning =>
      widget.controller.server.state.value == ServerState.running;

  /// 通话对端的显示名：角色卡名 > 入口传入的显示名 > 组名 > 模型名。
  /// 从对话模拟页进来时带的是当前角色卡的名字（「和小语通话」，
  /// 不是「和 opencodezen 通话」）。
  String get _peerName {
    final d = widget.displayName?.trim();
    if (d != null && d.isNotEmpty) return d;
    final g = widget.groupName?.trim();
    if (g != null && g.isNotEmpty) return g;
    return widget.model;
  }

  @override
  void initState() {
    super.initState();
    // 恢复这格聊天记录：通话接着对话模拟的上下文继续。
    _sim.restore();
    _sim.addListener(_onChanged); // 记录面板要跟着新消息实时刷
    _loadPrefs();
    widget.controller.server.state.addListener(_onChanged);
    TtsSpeechService.instance.addListener(_onTtsChanged);
    _dialTimer = Timer(const Duration(milliseconds: 1200), _pickUp);
  }

  @override
  void dispose() {
    _dialTimer?.cancel();
    _tickTimer?.cancel();
    _exitTimer?.cancel();
    _turn++;
    widget.controller.server.state.removeListener(_onChanged);
    TtsSpeechService.instance.removeListener(_onTtsChanged);
    _sim.removeListener(_onChanged);
    _recordsScroll.dispose();
    // 关掉还开着的麦克风与（本页发起的）朗读。
    _speech.cancel();
    if (TtsSpeechService.instance.activeTag == _ttsTag) {
      TtsSpeechService.instance.stop().ignore();
    }
    _sim.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadPrefs() async {
    final allowInterrupt = await CallPrefs.loadAllowInterrupt();
    final allowCamera = await CallPrefs.loadAllowCamera();
    if (!mounted) return;
    setState(() {
      _allowInterrupt = allowInterrupt;
      _allowCamera = allowCamera;
    });
  }

  /// 「接通」：本地没有信令链路，1.2 秒过渡后直接进入对讲循环。
  void _pickUp() {
    if (!mounted || _state != _TalkState.dialing) return;
    _connectedAt = DateTime.now();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _scheduleNextListen();
  }

  /// 排一轮「听」。用状态当占位锁：重复回调（TTS 完成 + catch 双触发）只进一次。
  void _scheduleNextListen() {
    if (!mounted) return;
    if (_state == _TalkState.listening || _state == _TalkState.ended) return;
    _state = _TalkState.listening; // 占位（不 setState，_beginListening 会刷）
    // 让 TTS 的尾音真正停一停再开麦。
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (mounted) _beginListening();
    });
  }

  Future<void> _beginListening() async {
    if (!mounted || _state == _TalkState.ended) return;
    final turn = ++_turn;
    setState(() {
      _state = _TalkState.listening;
      _liveText = '';
    });
    final ready = await _speech.ensureReady();
    if (!mounted || turn != _turn) return;
    if (ready == SpeechReady.busy) return;
    if (ready != SpeechReady.available) {
      setState(() => _asrFail = true);
      return;
    }
    final localeId = await _speech.resolveLocale(Localizations.localeOf(context));
    if (!mounted || turn != _turn) return;
    setState(() => _asrFail = false);
    await _speech.start(
      localeId: localeId,
      // 轮次切换由引擎的「断句定稿」驱动；这里的长静音只是引擎哑火时的
      // 兜底（服务层收到流式增量会自己收紧，见 SpeechInputService）。
      pauseFor: const Duration(seconds: 30),
      onResult: (text, isFinal) {
        if (!mounted || turn != _turn) return;
        setState(() => _liveText = text);
        if (isFinal) _submitUtterance(text);
      },
      onError: (message) {
        if (!mounted || turn != _turn) return;
        setState(() => _asrFail = true);
      },
      onStatus: (status) {
        if (!mounted || turn != _turn) return;
        // 引擎把会话收掉了而我们没等到定稿（桌面端断句后即收会话、或
        // 哑火兜底触发）：直接重进收音，别把通话挂死在收音态。
        // 注意不能走 _scheduleNextListen —— 它见到「已在收音态」会拒绝。
        if (status == 'notListening' &&
            _state == _TalkState.listening &&
            !_asrFail) {
          _beginListening();
        }
      },
    );
  }

  /// 一句说完了（引擎定稿，或用户点麦克风手动提交）。
  void _submitUtterance(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    _turn++; // 这轮 ASR 的回调全部作废
    _speech.cancel().ignore();
    _sendToModel(t);
  }

  Future<void> _sendToModel(String text) async {
    final turn = ++_turn;
    setState(() {
      _state = _TalkState.thinking;
      _userLine = text;
      _liveText = '';
      _replyLine = '';
      _replyFailed = false;
    });
    // 写进对话模拟的同一本账（模拟页里能回看这段通话）。
    _sim.add(ChatRole.user, text);
    await _sim.send();
    if (!mounted || turn != _turn || _state == _TalkState.ended) return;
    final last = _sim.messages.isEmpty ? null : _sim.messages.last;
    if (last == null) {
      _scheduleNextListen();
      return;
    }
    setState(() {
      _replyLine = last.content;
      _replyFailed = last.error;
    });
    if (last.error) {
      // 请求失败（服务没跑/上游挂）：不朗读错误文本，停一拍继续听。
      _scheduleNextListen();
      return;
    }
    _speakReply(last.content, turn);
  }

  Future<void> _speakReply(String text, int turn) async {
    setState(() => _state = _TalkState.speaking);
    // 角色卡配了音色样本就带上（本地克隆 / 云端 voiceclone），没有就用默认音色。
    final voice =
        characterStore.cardOf(_sim.appliedCharacterId ?? '')?.voiceSamplePath ??
        '';
    try {
      await ChatTts.speakMessage(
        tag: _ttsTag,
        text: text,
        config: widget.controller.config,
        voiceSamplePath: voice.isEmpty ? null : voice,
      );
      // 「播放完成」由 TtsSpeechService 的 idle 通知接管（_onTtsChanged）。
    } catch (e) {
      if (!mounted || turn != _turn) return;
      showMiuixToast(
        context,
        '$e'.replaceFirst(RegExp(r'^(Exception:\s*)+'), ''),
      );
      _scheduleNextListen();
    }
  }

  void _onTtsChanged() {
    if (!mounted) return;
    final svc = TtsSpeechService.instance;
    if (!svc.isIdle) {
      _ttsRan = true;
      return;
    }
    // 回到 idle：播放完成或被打断（合成失败的路径由 _speakReply 兜底）。
    if (_state == _TalkState.speaking && _ttsRan) {
      _ttsRan = false;
      _scheduleNextListen();
    }
  }

  /// 打断（仅 Omni + 允许打断）：停掉正在播放的回复，马上回到「听」。
  void _interrupt() {
    TtsSpeechService.instance.stop().ignore();
  }

  void _toggleVideo() {
    final l10n = AppLocalizations.of(context);
    if (!_video) {
      if (!_omni) {
        showMiuixToast(context, l10n.callVideoNeedOmni);
        return;
      }
      if (!_allowCamera) {
        showMiuixToast(context, l10n.callCameraBlocked);
        return;
      }
    }
    setState(() => _video = !_video);
  }

  Future<void> _openCallSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MiuixCallSettingsPage(omni: _omni),
      ),
    );
    // 回来刷新两个开关（设置页里可能改过）。
    if (mounted) _loadPrefs();
  }

  void _hangUp() {
    _dialTimer?.cancel();
    _tickTimer?.cancel();
    _turn++; // 在途回调全部作废
    _speech.cancel().ignore();
    TtsSpeechService.instance.stop().ignore();
    if (_state == _TalkState.ended) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _state = _TalkState.ended);
    // 停一下让「通话已结束」被看到，再退出。
    _exitTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  // ---- 对话记录（左划打开）----

  void _onPageDragUpdate(DragUpdateDetails d) => _hDragDx += d.delta.dx;

  void _onPageDragEnd(DragEndDetails d) {
    final dx = _hDragDx;
    _hDragDx = 0;
    if (_recordOpen) return;
    final vx = d.velocity.pixelsPerSecond.dx;
    // 左划（向左拖一段或快速左甩）把右侧的记录面板拉出来。
    if (dx < -70 || vx < -350) _openRecords();
  }

  void _openRecords() {
    if (_recordOpen) return;
    setState(() => _recordOpen = true);
    // 打开后滚到最新一条。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_recordsScroll.hasClients) {
        _recordsScroll.jumpTo(_recordsScroll.position.maxScrollExtent);
      }
    });
  }

  void _closeRecords() {
    if (!_recordOpen) return;
    setState(() => _recordOpen = false);
  }

  /// 记录浮层：全屏遮罩（点击关闭）+ 右侧滑入的记录卡。
  Widget _buildRecordOverlay(AppLocalizations l10n, MiuixColors colors) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_recordOpen,
        child: Stack(
          children: [
            AnimatedOpacity(
              opacity: _recordOpen ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: GestureDetector(
                onTap: _closeRecords,
                child: Container(color: Colors.black.withValues(alpha: 0.32)),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedSlide(
                offset: _recordOpen ? Offset.zero : const Offset(1, 0),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: GestureDetector(
                  // 在面板上向右甩 = 推回去关闭（与「左划拉出」对称）。
                  onHorizontalDragEnd: (d) {
                    if (d.velocity.pixelsPerSecond.dx > 300) {
                      _closeRecords();
                    }
                  },
                  child: _buildRecordPanel(l10n, colors),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordPanel(AppLocalizations l10n, MiuixColors colors) {
    final width = (MediaQuery.sizeOf(context).width * 0.82).clamp(240.0, 340.0);
    final messages = _sim.messages;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 6, 2),
              child: Row(
                children: [
                  Expanded(
                    child: MiuixText(
                      l10n.callRecords,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  MiuixIconButton(
                    onPressed: _closeRecords,
                    child: MiuixAppIcon(
                      AppIconNames.close,
                      fallback: Icons.close,
                      color: colors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: colors.surfaceVariant),
            Expanded(
              child: ListView.builder(
                controller: _recordsScroll,
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                itemCount: messages.length,
                itemBuilder: (context, i) =>
                    _recordRow(l10n, colors, messages[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 记录里的一行：角色小标签（配色区分）+ 文本（系统灰、错误红）。
  Widget _recordRow(AppLocalizations l10n, MiuixColors colors, ChatMsg m) {
    final (label, labelColor) = switch (m.role) {
      ChatRole.system => (
        l10n.chatSimRoleSystem,
        colors.onSurfaceVariantSummary,
      ),
      ChatRole.user => (l10n.chatSimRoleUser, colors.primary),
      ChatRole.assistant => (l10n.chatSimRoleAssistant, colors.secondary),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MiuixText(
            label,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: labelColor,
          ),
          const SizedBox(height: 4),
          MiuixText(
            m.content.isEmpty ? '（空）' : m.content,
            fontSize: 14,
            color: m.error ? colors.error : colors.onSurface,
            height: 1.5,
          ),
        ],
      ),
    );
  }

  String get _timerText {
    final at = _connectedAt;
    if (at == null || _state == _TalkState.dialing) return '';
    final d = DateTime.now().difference(at);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  String _statusLine(AppLocalizations l10n) {
    final base = switch (_state) {
      _TalkState.dialing => l10n.callStatusCalling,
      _TalkState.listening =>
        _asrFail ? l10n.callAsrUnavailable : l10n.callStatusListening,
      _TalkState.thinking => l10n.callStatusThinking,
      _TalkState.speaking => l10n.callStatusSpeaking,
      _TalkState.ended => l10n.callStatusEnded,
    };
    final timer = _timerText;
    return timer.isEmpty ? base : '$base · $timer';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;

    return Material(
      type: MaterialType.transparency,
      child: MiuixScaffold(
        containerColor: colors.surface,
        content: (padding) => GestureDetector(
          // 「左划打开对话记录」：在通话页水平左划（或快速左甩）拉起记录面板。
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: _recordOpen ? null : _onPageDragUpdate,
          onHorizontalDragEnd: _recordOpen ? null : _onPageDragEnd,
          child: Stack(
            children: [
              // 背景层：双六边形动态壁纸（跟随主题色）。
              const Positioned.fill(child: HexagonCollisionBackground()),
              // 轻遮罩：让头像 / 文字 / 按钮从色块里浮出来（对应 vivo
              // 通话背景的 black/white mask 变体思路）。
              Positioned.fill(
                child: Container(
                  color: colors.surface.withValues(alpha: 0.16),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(
                  top: padding.top,
                  bottom: padding.bottom + 20,
                ),
                child: Column(
                  children: [
                    _buildTopBar(l10n),
                    if (!_serverRunning)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                        child: MiuixGroupCard(
                          insideMargin: const EdgeInsets.fromLTRB(
                            14,
                            12,
                            14,
                            12,
                          ),
                          colors: MiuixCardColors(
                            color: colors.tertiaryContainer,
                            contentColor: colors.onTertiaryContainer,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: MiuixText(
                                  l10n.chatSimServerOff,
                                  fontSize: 13,
                                ),
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
                    Expanded(child: _buildCenter(l10n)),
                    _buildControls(l10n),
                  ],
                ),
              ),
              // 对话记录浮层（遮罩 + 右侧滑入的记录卡）。
              _buildRecordOverlay(l10n, colors),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(AppLocalizations l10n) {
    final colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          MiuixIconButton(
            onPressed: _hangUp,
            child: MiuixAppIcon(
              AppIconNames.back,
              fallback: Icons.arrow_back,
              color: colors.onSurface,
            ),
          ),
          Expanded(
            child: Center(
              child: MiuixText(
                _video ? l10n.callTitleVideo : l10n.callTitleVoice,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          MiuixIconButton(
            onPressed: _openCallSettings,
            child: MiuixAppIcon(
              AppIconNames.settings,
              fallback: Icons.settings_outlined,
              color: colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenter(AppLocalizations l10n) {
    if (_video) return _buildVideoStage(l10n);
    return _buildVoiceStage(l10n);
  }

  /// 语音模式：呼叫波纹 + 大头像 + 名字 + 状态/计时 + 实时字幕。
  Widget _buildVoiceStage(AppLocalizations l10n) {
    final colors = MiuixTheme.of(context).colors;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _CallPulse(
          active:
              _state == _TalkState.dialing || _state == _TalkState.listening,
          child: const _CallAvatar(size: 112),
        ),
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: MiuixText(
            _peerName,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 10),
        MiuixText(
          _statusLine(l10n),
          fontSize: 15,
          color: colors.onSurfaceVariantSummary,
        ),
        const SizedBox(height: 16),
        _subtitleBox(colors),
      ],
    );
  }

  /// 视频模式：大「画面」占位区（摄像头链路后续接）+ 角标信息 + 小窗 + 字幕。
  Widget _buildVideoStage(AppLocalizations l10n) {
    final colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: colors.surfaceVariant,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.videocam_outlined,
                            size: 44,
                            color: colors.onSurfaceVariantSummary,
                          ),
                          const SizedBox(height: 14),
                          MiuixText(
                            l10n.callVideoStagePlaceholder,
                            fontSize: 14,
                            color: colors.onSurfaceVariantSummary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 画面区底部的字幕条（避开右下的小窗）。
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 116, 14),
                    child: SizedBox(
                      height: 48,
                      child: Center(child: _subtitleText(colors)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 左上角：对端 + 状态/计时。
          Positioned(
            left: 16,
            top: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(999),
              ),
              child: MiuixText(
                '$_peerName · ${_statusLine(l10n)}',
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // 右下角：本端小窗（头像）。
          const Positioned(right: 16, bottom: 16, child: _CallAvatar(size: 84)),
        ],
      ),
    );
  }

  Widget _subtitleBox(MiuixColors colors) {
    // 固定高度：状态切换时布局不跳。
    return SizedBox(
      height: 72,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Center(child: _subtitleText(colors)),
      ),
    );
  }

  /// 当前字幕：在听=实时识别；思考=用户这句；说话=模型回复；
  /// 刚失败过就把错误说明留在原地（红字）。
  Widget _subtitleText(MiuixColors colors) {
    final text = switch (_state) {
      _TalkState.listening => _liveText.isEmpty ? _replyLine : _liveText,
      _TalkState.thinking => _userLine,
      _TalkState.speaking => _replyLine,
      _ => '',
    };
    final isErr = _replyFailed && _state != _TalkState.speaking;
    if (text.isEmpty) return const SizedBox.shrink();
    return MiuixText(
      text,
      fontSize: 14,
      color: isErr ? colors.error : colors.onSurface,
      textAlign: TextAlign.center,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      height: 1.5,
    );
  }

  /// 按钮层：麦克风（听/提交/打断三态） / 免提 / 视频 / 挂断。
  Widget _buildControls(AppLocalizations l10n) {
    final String micTooltip;
    final String micIcon;
    final IconData micFallback;
    final bool micActive;
    final VoidCallback? micTap;

    if (_state == _TalkState.speaking) {
      final canInterrupt = _omni && _allowInterrupt;
      micTooltip = canInterrupt ? l10n.callInterrupt : l10n.callMic;
      micIcon = 'pause';
      micFallback = Icons.pause;
      micActive = false;
      micTap = canInterrupt ? _interrupt : null;
    } else if (_state == _TalkState.listening) {
      if (_asrFail) {
        // 引擎没起来：点一下重试。
        micTooltip = l10n.callMic;
        micIcon = 'mic';
        micFallback = Icons.mic_none_outlined;
        micActive = false;
        micTap = _beginListening;
      } else {
        micTooltip = l10n.callMicDone;
        micIcon = 'mic';
        micFallback = Icons.mic;
        micActive = true;
        micTap = _liveText.trim().isEmpty
            ? null
            : () => _submitUtterance(_liveText);
      }
    } else {
      // dialing / thinking / ended：麦克风暂时不参与。
      micTooltip = l10n.callMic;
      micIcon = 'mic';
      micFallback = Icons.mic_none_outlined;
      micActive = false;
      micTap = null;
    }

    final live = _state != _TalkState.ended;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CallActionButton(
            miuixName: micIcon,
            fallback: micFallback,
            tooltip: micTooltip,
            active: micActive,
            onTap: micTap,
          ),
          _CallActionButton(
            miuixName: _speaker ? 'volumeUp' : 'volumeOff',
            fallback: _speaker
                ? Icons.volume_up_outlined
                : Icons.volume_down_outlined,
            tooltip: _speaker ? l10n.callSpeakerOff : l10n.callSpeakerOn,
            active: _speaker,
            onTap: live ? () => setState(() => _speaker = !_speaker) : null,
          ),
          _CallActionButton(
            fallback: _video ? Icons.videocam : Icons.videocam_outlined,
            tooltip: _video ? l10n.callSwitchToVoice : l10n.callSwitchToVideo,
            active: _video,
            onTap: live ? _toggleVideo : null,
          ),
          _CallHangUpButton(onTap: _hangUp),
        ],
      ),
    );
  }
}

/// 圆形操作键：普通 = 浅色底深图标；激活 = 主题色底；禁用 = 整体压暗。
class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.fallback,
    required this.tooltip,
    required this.active,
    required this.onTap,
    this.miuixName,
  });

  final String? miuixName;
  final IconData fallback;
  final String tooltip;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final enabled = onTap != null;
    final Color bg;
    final Color fg;
    if (!enabled) {
      bg = colors.surfaceVariant;
      fg = colors.disabledOnSurface;
    } else if (active) {
      bg = colors.primary;
      fg = colors.onPrimary;
    } else {
      // 有轻遮罩+色块背景，普通态用 secondaryContainer 才从米白底上浮出来。
      bg = colors.secondaryContainer;
      fg = colors.onSecondaryContainer;
    }
    return Tooltip(
      message: tooltip,
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 58,
            height: 58,
            child: Center(
              child: miuixName != null
                  ? MiuixAppIcon(
                      miuixName!,
                      fallback: fallback,
                      size: 24,
                      color: fg,
                    )
                  : Icon(fallback, size: 24, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

/// 挂断键：红色大圆 + 听筒图标。
class _CallHangUpButton extends StatelessWidget {
  const _CallHangUpButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;
    return Tooltip(
      message: l10n.callHangUp,
      child: Material(
        color: colors.error,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 64,
            height: 64,
            child: Icon(Icons.call_end, size: 30, color: colors.onError),
          ),
        ),
      ),
    );
  }
}

/// 呼叫中 / 收音时头像外圈的扩散波（两个错相位的圆环轮流扩散渐隐）。
class _CallPulse extends StatefulWidget {
  const _CallPulse({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_CallPulse> createState() => _CallPulseState();
}

class _CallPulseState extends State<_CallPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _CallPulse old) {
    super.didUpdateWidget(old);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 192,
      height: 192,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Stack(
          alignment: Alignment.center,
          children: [
            if (widget.active)
              for (final phase in const [0.0, 0.5])
                _ring(cs.primary, (_controller.value + phase) % 1.0),
            child!,
          ],
        ),
        child: widget.child,
      ),
    );
  }

  Widget _ring(Color color, double p) {
    final size = 112 + 76 * p;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: (1 - p) * 0.32),
          width: 1.6,
        ),
      ),
    );
  }
}

/// 通话头像：有自定义助手头像就用它，否则主题色圆底 + 机器人图标。
class _CallAvatar extends StatelessWidget {
  const _CallAvatar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return ListenableBuilder(
      listenable: chatAvatarStore,
      builder: (context, _) {
        final bytes = chatAvatarStore.avatarOf(ChatRole.assistant);
        if (bytes != null && bytes.isNotEmpty) {
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: colors.surface.withValues(alpha: 0.92),
                width: 3,
              ),
            ),
            child: ClipOval(
              child: Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
          );
        }
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: colors.primary,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.smart_toy,
            size: size * 0.42,
            color: colors.onPrimary,
          ),
        );
      },
    );
  }
}

/// 组详情 / 发现页入口：挑了模型就推这一页。
Future<void> pushMiuixCallPage(
  BuildContext context, {
  required ServerController controller,
  required String model,
  String? groupName,
  String? displayName,
  String scope = '',
  bool startVideo = false,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => MiuixCallPage(
      controller: controller,
      model: model,
      groupName: groupName,
      displayName: displayName,
      scope: scope,
      startVideo: startVideo,
    ),
  ),
);
