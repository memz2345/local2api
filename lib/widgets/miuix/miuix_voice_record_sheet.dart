// 语音输入弹层（miuix 版）：点麦克风弹出，**按住**大麦克风说话，松手结束。
// 之前的「点一下开始、再点一下停止」太隐晦 —— 没有任何提示告诉用户
// 麦克风已经开着，也没有「说完了」的动作；弹层 + 长按把这两件事都说清。
//
// 识别逻辑在共享的 [VoiceRecordSession]（Material 版弹层同款），这里只管渲染。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' hide MiuixTextField, MiuixTextFieldColors;

import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/speech_input_service.dart';
import 'package:local2api/services/voice_record_session.dart';
import 'package:local2api/widgets/miuix/miuix_bottom_sheet.dart';
import 'package:local2api/widgets/miuix/miuix_dialog.dart';

/// 按住不足这个时长视为误触，不启动引擎。
const Duration _kMinHold = Duration(milliseconds: 350);

/// 弹出「按住说话」录音层。返回识别出的文本（没听到 / 取消返回 null）。
Future<String?> showMiuixVoiceRecordSheet(
  BuildContext context, {
  String? localeTag,
}) => showMiuixBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (sheetCtx) => _MiuixVoiceRecordSheet(localeTag: localeTag),
);

class _MiuixVoiceRecordSheet extends StatefulWidget {
  const _MiuixVoiceRecordSheet({this.localeTag});

  final String? localeTag;

  @override
  State<_MiuixVoiceRecordSheet> createState() => _MiuixVoiceRecordSheetState();
}

class _MiuixVoiceRecordSheetState extends State<_MiuixVoiceRecordSheet> {
  late final VoiceRecordSession _session = VoiceRecordSession(
    localeTag: widget.localeTag,
  );

  DateTime? _pressAt;

  /// 上一轮说了但没识别出东西：文案区提示「没听清」，下次按下清掉。
  bool _nothingHeard = false;

  bool _busy = false;
  Timer? _pulseTimer;
  bool _pulseOn = false;

  bool get _holding => _session.phase == VoiceRecordPhase.holding;

  @override
  void dispose() {
    _pulseTimer?.cancel();
    // 弹层关了，收音必须停（松手路径已经停过也无妨，幂等）。
    _session.abort().ignore();
    _session.dispose();
    super.dispose();
  }

  Future<void> _onPressDown() async {
    if (_busy) return;
    _pressAt = DateTime.now();
    _nothingHeard = false;
    _startPulse();
    setState(() {});
    final ready = await _session.begin();
    if (!mounted) return;
    if (ready == SpeechReady.noPermission) {
      _stopPulse();
      _showPermissionDialog();
    }
    setState(() {});
    // 不可用：session 已把 phase 置为 error，文案区会说明原因。
  }

  Future<void> _onPressUp() async {
    if (_busy) return;
    _stopPulse();
    final at = _pressAt;
    _pressAt = null;
    if (_session.phase != VoiceRecordPhase.holding) {
      // 没按住过（引擎没起来）或者刚出错：收掉这次按压即可。
      setState(() {});
      return;
    }
    if (at == null || DateTime.now().difference(at) < _kMinHold) {
      // 误触：取消这一轮，回到「按住说话」。
      await _session.abort();
      if (mounted) setState(() {});
      return;
    }
    _busy = true;
    final text = await _session.finish();
    _busy = false;
    if (!mounted) return;
    if (text == null || text.trim().isEmpty) {
      // 没听清：留在弹层里让用户再按一次，别悄悄关掉像「坏了」。
      setState(() => _nothingHeard = true);
      return;
    }
    Navigator.of(context).pop(text);
  }

  void _onPressCancel() {
    _stopPulse();
    if (_session.phase == VoiceRecordPhase.holding ||
        _session.phase == VoiceRecordPhase.finishing) {
      _session.abort().ignore();
    }
    if (mounted) setState(() {});
  }

  /// 收音中的呼吸提示：小红点亮一下灭一下（引擎没有增量事件时，这是
  /// 唯一的「在录」反馈，必须有）。
  void _startPulse() {
    _pulseTimer?.cancel();
    _pulseOn = true;
    _pulseTimer = Timer.periodic(const Duration(milliseconds: 620), (_) {
      if (!mounted) return;
      setState(() => _pulseOn = !_pulseOn);
    });
  }

  void _stopPulse() {
    _pulseTimer?.cancel();
    _pulseTimer = null;
    _pulseOn = false;
  }

  void _showPermissionDialog() {
    final l10n = AppLocalizations.of(context);
    showMiuixDialog<void>(
      context: context,
      title: l10n.chatSimVoiceInput,
      message: l10n.chatSimVoiceNoPermission,
      actions: [
        MiuixDialogAction(
          label: l10n.cancel,
          onPressed: (ctx) => Navigator.of(ctx).pop(),
        ),
        MiuixDialogAction(
          label: l10n.chatSimVoiceOpenSettings,
          primary: true,
          onPressed: (ctx) {
            Navigator.of(ctx).pop();
            _session.openSettings().ignore();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MiuixText(
              l10n.chatSimVoiceInput,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            // 大麦克风：按住说话，松手结束（Listener = 按下即刻开录，
            // 不用 onLongPress 的 500ms 门槛）。
            Center(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => _onPressDown(),
                onPointerUp: (_) => _onPressUp(),
                onPointerCancel: (_) => _onPressCancel(),
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _holding
                        ? colors.primary
                        : colors.secondaryContainer,
                  ),
                  child: Icon(
                    Icons.mic,
                    size: 40,
                    color: _holding
                        ? colors.onPrimary
                        : colors.onSecondaryContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 状态 / 实时文本区（固定最小高度，状态切换不跳布局）。
            AnimatedBuilder(
              animation: _session,
              builder: (context, _) {
                final phase = _session.phase;
                final err = _session.errorMessage;
                final liveText = _session.liveText;
                final isError = phase == VoiceRecordPhase.error;
                final String? status;
                if (isError) {
                  status = switch (err) {
                    'no-permission' => l10n.chatSimVoiceNoPermission,
                    'preparing' => l10n.chatSimVoicePreparing,
                    'unavailable' => l10n.chatSimVoiceUnavailable,
                    _ => l10n.chatSimVoiceFailed(err ?? ''),
                  };
                } else if (phase == VoiceRecordPhase.finishing) {
                  status = liveText.isEmpty ? l10n.voiceRecognizing : null;
                } else if (phase == VoiceRecordPhase.holding) {
                  status = liveText.isEmpty ? l10n.voiceListeningHint : null;
                } else if (_nothingHeard) {
                  status = l10n.voiceNothingHeard;
                } else {
                  status = null;
                }
                return Column(
                  children: [
                    SizedBox(
                      height: 48,
                      child: Center(
                        child: liveText.isNotEmpty
                            ? MiuixText(
                                liveText,
                                fontSize: 15,
                                height: 1.4,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              )
                            : (status == null
                                  ? const SizedBox.shrink()
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_pulseOn) ...[
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Colors.redAccent,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        Flexible(
                                          child: MiuixText(
                                            status,
                                            fontSize: 14,
                                            color: isError || _nothingHeard
                                                ? colors.error
                                                : colors
                                                      .onSurfaceVariantSummary,
                                          ),
                                        ),
                                      ],
                                    )),
                      ),
                    ),
                    const SizedBox(height: 6),
                    MiuixText(
                      _holding || phase == VoiceRecordPhase.finishing
                          ? l10n.voiceReleaseToSend
                          : l10n.voiceHoldToTalk,
                      fontSize: 12,
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
