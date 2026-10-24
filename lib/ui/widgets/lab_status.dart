// lib/ui/widgets/lab_status.dart
//
// 实验室 Node.js 运行时的状态文案（Material / miuix 两套 UI 共用）。
//
// 状态行与错误码映射写一遍，实验室首页（两张风格）与 ST / dsh 的
// 「更多设置」页（四张）都用这里，免得各写一份漂移。

import '../../l10n/app_localizations.dart';
import '../../services/lab/node_runtime_service.dart';
import '../../services/lab/silly_tavern_service.dart' show LabServicePhase;

/// Node 运行时的单行状态（「Node.js」状态行的 subtitle）。
String labNodeStatusLine(AppLocalizations l10n, NodeRuntimeService node) {
  if (node.busy) {
    return node.phase == LabServicePhase.downloading
        ? l10n.labDownloading
        : l10n.labExtracting;
  }
  if (node.nodeAvailable) {
    final version = node.nodeVersion ?? '';
    final npm = node.npmVersion;
    return 'v${version.startsWith('v') ? version.substring(1) : version}'
        '${npm == null ? '' : ' · npm $npm'}';
  }
  if (node.nodeError == 'execBlocked') return l10n.labExecBlocked;
  if (node.nodeError == null ||
      node.nodeError == 'notInstalled' ||
      node.nodeError == 'test') {
    return l10n.labNodeRuntimeNotInstalled;
  }
  // shizukuUnavailable / shizukuNotGranted / nodeExitN / unknown 等内部码
  // 直接透出（Node 运行时卡下面有完整错误行，这里帮助二级页定位）。
  return '${l10n.labNodeRuntimeNotInstalled} (${node.nodeError})';
}

/// 二级页「Node.js」行的通用副标题：桌面看系统 Node；Android 看应用内
/// 运行时；其余移动平台维持「需要 Termux」的说明。
String labNodeLineForService(
  AppLocalizations l10n, {
  required bool isDesktop,
  required bool isAndroid,
  required bool nodeAvailable,
  required String? nodeVersion,
  required String? npmVersion,
}) {
  if (isDesktop) {
    return nodeAvailable
        ? '${nodeVersion ?? ''}${npmVersion == null ? '' : ' · npm $npmVersion'}'
        : l10n.labNodeMissing;
  }
  if (isAndroid) {
    return labNodeStatusLine(l10n, NodeRuntimeService.instance);
  }
  return l10n.labMobileNoRun;
}
