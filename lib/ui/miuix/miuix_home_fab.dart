import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';

import 'miuix_create_config_page.dart';
import 'miuix_theme_quick_sheet.dart';

/// miuix 风格的首页 FAB：按当前 tab 给不同动作，与 Material 版一一对应。
///
/// MiuixFloatingActionButton 只有圆形一种形状（没有 extended 变体），
/// 所以启停那颗不再带文字标签，用 [MiuixTooltipBox] 承载语义
/// （对应 InstallerX 的 miuix 页面一律用 miuix 自己的 Tooltip/Dialog 而不混 Material）。
Widget? buildMiuixHomeFab(
  BuildContext context, {
  required int index,
  required ServerController controller,
}) {
  switch (index) {
    case 0:
      // 启停服务：状态实时变化，所以 FAB 自己监听，不等整页重建
      return _MiuixFab(
        key: const ValueKey<int>(0),
        state: controller.server.state,
        labelOf: (context, state) {
          final l10n = AppLocalizations.of(context);
          return _isBusy(state) ? l10n.stopServer : l10n.startServer;
        },
        // 运行中给「暂停」（miuix 图标集里有 pause，语义即"停"）；
        // 未运行给「播放」。两者都留了 Material 回落以防图标名拼错。
        iconOf: (context, state) => MiuixAppIcon(
          _isBusy(state) ? AppIconNames.pause : AppIconNames.play,
          fallback: _isBusy(state) ? Icons.stop : Icons.play_arrow,
          size: 26,
        ),
        onPressed: controller.toggle,
      );
    case 1:
      return _MiuixFab(
        key: const ValueKey<int>(1),
        // 加号 = 创建配置：从文件导 JSON，或直接进「新建上游」。
        labelOf: (context, _) =>
            AppLocalizations.of(context).createConfigTitle,
        iconOf: (context, _) =>
            const MiuixAppIcon(AppIconNames.add, fallback: Icons.add),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MiuixCreateConfigPage(controller: controller),
          ),
        ),
      );
    case 2:
      return _MiuixFab(
        key: const ValueKey<int>(2),
        labelOf: (context, _) => AppLocalizations.of(context).fabAppearance,
        iconOf: (context, _) =>
            const MiuixAppIcon(AppIconNames.theme, fallback: Icons.palette),
        onPressed: () => showMiuixThemeQuickSheet(context),
      );
  }
  return null;
}

/// 服务是不是「正在跑或正在起」——FAB 的两态判据。
bool _isBusy(ServerState? state) =>
    state == ServerState.running || state == ServerState.starting;

/// FAB + miuix 提示气泡。
///
/// ## 为什么把 MiuixTooltipBox 的 widget 实例缓存起来
///
/// flutter_miuix 1.3.0 的 `_MiuixTooltipBoxState.didUpdateWidget` 在气泡
/// **还开着**的时候会直接对 `OverlayEntry` 调 `markNeedsBuild()`，而父级重建
/// 发生在 build 阶段内 —— 于是桌面端（有鼠标 hover，气泡开着）点一下 FAB：
/// 服务状态变了 / 推了一条路由 → 外壳重建 → 这句 markNeedsBuild 撞进 build
/// 阶段 → `setState() or markNeedsBuild() called during build`，整屏红块，
/// 正在 build 的正是 `_MiuixFab`。触屏没有 hover，所以只有
/// Windows / macOS / Linux 上看得见这个坑。
///
/// `Element.updateChild` 对「父级这次给的还是同一个 widget 实例」走快路径
/// （不调 `element.update`，也就没有 didUpdateWidget），所以这里缓存实例
/// 就绕开了库的那句调用。代价是**不能再用「换 widget」来表达状态变化** ——
/// 文案与图标改成在闭包里现算，并用 [ValueListenableBuilder] 让气泡内部和
/// 按钮自己跟着 `server.state` 重建。
///
/// 另外 `onPressed` 里先 [_tip.dismiss]：万一还是收到 didUpdateWidget
/// （比如上层换了 key），气泡已关就不会触发那句 markNeedsBuild。
class _MiuixFab extends StatefulWidget {
  const _MiuixFab({
    super.key,
    required this.labelOf,
    required this.iconOf,
    required this.onPressed,
    this.state,
  });

  /// 气泡文案（在气泡自己的子树里求值，所以拿得到 l10n 与最新状态）。
  final String Function(BuildContext context, ServerState? state) labelOf;

  /// 按钮图标。
  final Widget Function(BuildContext context, ServerState? state) iconOf;

  final VoidCallback onPressed;

  /// 状态源；null = 静态 FAB（加号 / 外观）。
  final ValueListenable<ServerState>? state;

  @override
  State<_MiuixFab> createState() => _MiuixFabState();
}

class _MiuixFabState extends State<_MiuixFab> {
  final MiuixTooltipState _tip = MiuixTooltipState();

  /// 缓存的气泡实例：见 [_MiuixFab] 的文档。
  Widget? _cached;

  @override
  void dispose() {
    _tip.dispose();
    super.dispose();
  }

  /// 有状态源时套一层 ValueListenableBuilder，让子树自己重建。
  Widget _watch(
    Widget Function(BuildContext context, ServerState? state) build,
  ) {
    final source = widget.state;
    if (source == null) return build(context, null);
    return ValueListenableBuilder<ServerState>(
      valueListenable: source,
      builder: (context, state, _) => build(context, state),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _cached ??= MiuixTooltipBox(
      state: _tip,
      positioning: MiuixTooltipAnchorPosition.above,
      tooltip: (tipContext, scope) => _watch(
        (context, state) => MiuixPlainTooltip(
          scope: scope,
          showCaret: true,
          child: MiuixText(widget.labelOf(context, state), fontSize: 12),
        ),
      ),
      child: _watch(
        (context, state) => MiuixFloatingActionButton(
          onPressed: () {
            _tip.dismiss();
            widget.onPressed();
          },
          child: widget.iconOf(context, state),
        ),
      ),
    );
  }
}
