import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:local2api/services/server_controller.dart';

import 'create_config_page.dart';
import 'theme_quick_sheet.dart';
import 'widgets/common.dart';

/// 首页 FAB：按当前 tab 给不同动作。
/// 窄屏（玻璃底栏）和宽屏（侧边栏）共用，避免两处逻辑漂移。
Widget? buildHomeFab(
  BuildContext context, {
  required int index,
  required ServerController controller,
}) {
  final l10n = AppLocalizations.of(context);
  switch (index) {
    case 0:
      // 启停服务：状态实时变化，所以 FAB 自己监听，不等整页重建
      return ValueListenableBuilder<ServerState>(
        valueListenable: controller.server.state,
        builder: (context, state, _) {
          final running =
              state == ServerState.running || state == ServerState.starting;
          return FloatingActionButton.extended(
            onPressed: controller.toggle,
            icon: Icon(running ? Icons.stop : Icons.play_arrow),
            label: Text(running ? l10n.stopServer : l10n.startServer),
          );
        },
      );
    case 1:
      return FloatingActionButton(
        // 加号 = 创建配置：从文件导 JSON，或直接进「新建上游」。
        tooltip: l10n.createConfigTitle,
        onPressed: () =>
            pushPage(context, CreateConfigPage(controller: controller)),
        child: const Icon(Icons.add),
      );
    case 2:
      return FloatingActionButton(
        tooltip: l10n.fabAppearance,
        onPressed: () => showThemeQuickSheet(context),
        child: const Icon(Icons.palette_outlined),
      );
  }
  return null;
}

/// 把 FAB 抬到底栏槽之上：extendBody 时默认 endFloat 会压在玻璃胶囊上。
/// 宽屏没有底栏，[lift] 传 0。
class HomeFabAboveBarLocation extends FloatingActionButtonLocation {
  const HomeFabAboveBarLocation(this.lift);

  /// 底栏槽高度（含手势条 inset）。
  final double lift;

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry g) => Offset(
    g.scaffoldSize.width - g.floatingActionButtonSize.width - 16,
    g.scaffoldSize.height - lift - 16 - g.floatingActionButtonSize.height,
  );
}
