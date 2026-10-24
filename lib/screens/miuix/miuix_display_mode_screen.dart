import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/widgets/miuix/miuix_group_card.dart';
import 'package:local2api/widgets/miuix/miuix_scroll_behavior.dart';
import 'package:provider/provider.dart';

/// miuix 风格的屏幕帧率选择页（对应 Material 版 `DisplayModeScreen`，
/// 自 NaviFlash `DisplayModeScreen` 移植）。
///
/// - FlutterDisplayMode.supported → 系统支持的帧率列表（首项为「自动」）
/// - 选中后 setPreferredMode，再回读 active / preferred 更新 UI 与持久化
/// - 仅 Android 可用，其他平台显示不支持提示
class MiuixDisplayModeScreen extends StatefulWidget {
  const MiuixDisplayModeScreen({super.key});

  @override
  State<MiuixDisplayModeScreen> createState() => _MiuixDisplayModeScreenState();
}

class _MiuixDisplayModeScreenState extends State<MiuixDisplayModeScreen> {
  /// 二级页统一的可折叠大标题行为；`MiuixBlurTopBar` 读它，
  /// `MiuixScrollBehaviorListener` 在外层把滚动通知喂给它。
  final MiuixShortPageScrollBehavior _behavior = MiuixShortPageScrollBehavior();

  List<DisplayMode> _modes = [];
  DisplayMode? _active;
  DisplayMode? _preferred;
  bool _loaded = false;
  late final bool _isAndroid = Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _behavior.state.dispose();
    super.dispose();
  }

  // 初始化：拉取支持模式 → 应用上次偏好 → 回读当前状态
  Future<void> _init() async {
    if (!_isAndroid) {
      if (mounted) setState(() => _loaded = true);
      return;
    }

    final settings = context.read<SettingsService>();

    try {
      _modes = await FlutterDisplayMode.supported;
    } catch (e) {
      if (kDebugMode) debugPrint('获取屏幕帧率失败: $e');
    }

    final saved = settings.displayMode;
    DisplayMode? preferred;
    if (saved.isNotEmpty) {
      for (final mode in _modes) {
        if (mode.toString() == saved) {
          preferred = mode;
          break;
        }
      }
    }
    preferred ??= DisplayMode.auto;

    try {
      await FlutterDisplayMode.setPreferredMode(preferred);
    } catch (e) {
      if (kDebugMode) debugPrint('设置屏幕帧率失败: $e');
    }
    await _fetchCurrent(settings);

    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _fetchCurrent(SettingsService settings) async {
    try {
      final active = await FlutterDisplayMode.active;
      final preferred = await FlutterDisplayMode.preferred;
      if (!mounted) return;
      setState(() {
        _active = active;
        _preferred = preferred;
      });
      await settings.setDisplayMode(preferred.toString());
    } catch (e) {
      if (kDebugMode) debugPrint('获取当前屏幕帧率失败: $e');
    }
  }

  Future<void> _onSelect(DisplayMode mode) async {
    final settings = context.read<SettingsService>();
    try {
      await FlutterDisplayMode.setPreferredMode(mode);
    } catch (e) {
      if (kDebugMode) debugPrint('设置屏幕帧率失败: $e');
    }
    await _fetchCurrent(settings);
  }

  String _modeTitle(DisplayMode mode, AppLocalizations l10n) {
    if (mode == DisplayMode.auto) return l10n.displayModeAuto;
    final title = '${mode.width}×${mode.height} @ ${mode.refreshRate.toInt()}Hz';
    if (_active != null && mode == _active) {
      return '$title  ${l10n.displayModeSystemTag}';
    }
    return title;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = MiuixTheme.of(context).colors;

    return Material(
      type: MaterialType.transparency,
      child: MiuixScaffold(
        containerColor: colors.surface,
        topBar: MiuixBlurTopBar(
          scrollBehavior: _behavior,
          title: l10n.displayModeTitle,
          navigationIcon: MiuixIconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const MiuixAppIcon(
              AppIconNames.back,
              fallback: Icons.arrow_back,
            ),
          ),
        ),
        content: (padding) => MiuixScrollBehaviorListener(
          behavior: _behavior,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(16, padding.top + 8, 16, 48),
            children: [
              if (!_isAndroid) ...[
                MiuixGroupCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.speed_outlined),
                        const SizedBox(width: 12),
                        Expanded(child: MiuixText(l10n.displayModeUnsupported)),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                  child: MiuixText(
                    l10n.displayModeHint,
                    fontSize: 12,
                    color: colors.onSurfaceVariantSummary,
                  ),
                ),
                if (!_loaded)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      children: [
                        const MiuixCircularProgressIndicator(),
                        const SizedBox(height: 16),
                        MiuixText(
                          l10n.displayModeLoading,
                          fontSize: 13,
                          color: colors.onSurfaceVariantSummary,
                        ),
                      ],
                    ),
                  )
                else if (_modes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: MiuixText(
                        l10n.displayModeEmpty,
                        fontSize: 13,
                        color: colors.onSurfaceVariantSummary,
                      ),
                    ),
                  )
                else
                  MiuixGroupCard(
                    child: Column(
                      children: [
                        for (final mode in _modes)
                          MiuixRadioButtonPreference(
                            title: _modeTitle(mode, l10n),
                            selected: _preferred != null && mode == _preferred,
                            radioButtonLocation: MiuixRadioButtonLocation.end,
                            startAction: Icon(
                              mode == DisplayMode.auto
                                  ? Icons.autorenew
                                  : Icons.monitor_outlined,
                            ),
                            onClick: () => _onSelect(mode),
                          ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
