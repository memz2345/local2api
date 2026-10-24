// lib/ui/widgets/log_filter_bar.dart
//
// 请求日志页的状态筛选（全部 / 通过 / 失败）的**文案与判定入口**。
//
// 判定逻辑在 `lib/services/proxy_server.dart`（`logEntryMatches`），这里只
// 负责把枚举翻成本地化标签 —— 两份 UI 各自的皮肤，业务口径共用一份。
//
// Material 侧原来是一排悬浮在内容上的 FilterChip（`LogFilterBar`），现已改成
// NaviFlash「分区 / 搜索」那种**顶栏自带 tab 行**（见 `logs_page.dart` 里的
// `FrostedBarPage.bottom` + `NaviOvalTabRow`），所以这里的 chip 组件删掉了，
// 只留标签函数；miuix 侧仍是内容区的 `MiuixLogFilterBar`。

import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/proxy_server.dart';

/// 筛选片的标题（本地化在这里做，页面不用各写一遍）。
String logFilterLabel(AppLocalizations l10n, LogStatusFilter f) => switch (f) {
  LogStatusFilter.all => l10n.logsFilterAll,
  LogStatusFilter.passed => l10n.logsFilterPassed,
  LogStatusFilter.failed => l10n.logsFilterFailed,
};
