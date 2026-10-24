import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' show MiuixText, MiuixTheme;
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/config_profile.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/network_utils.dart';
import 'package:local2api/services/profile_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/src/enums.dart' show UiStyleX;
import 'package:local2api/ui/miuix/miuix_profile_import_sheet.dart'
    show showMiuixProfileImportSheet;
import 'package:local2api/ui/profile_import_sheet.dart'
    show ProfileImportSheet, profileErrorMessage;
import 'package:local2api/widgets/app_toast.dart';
import 'package:local2api/widgets/miuix/miuix_dialog.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';
import 'package:local2api/widgets/predictive_back_sheet.dart';
import 'package:provider/provider.dart';

import 'widgets/common.dart' show copyText;

/// 扫码内容的类别。决定「扫码结果」弹窗给哪些动作：
/// - [profileJson]：本应用档案文档 → **导入到规则**（ProfileStore.importDocument）；
/// - [upstreamJson]：本应用单个上游 JSON（含编辑上游页二维码那份）→ 添加为上游；
/// - [url]：网页链接 → 复制，或带进「添加配置文件」面板当订阅地址；
/// - [text]：其余一律按纯文本展示 + 复制。
enum ScanContentKind { profileJson, upstreamJson, url, text }

/// 把一段扫码原文分类。JSON 优先（配置文档 / 单上游），其次像 URL 的链接，
/// 剩下的都算纯文本 —— 识别错档的最坏结果只是弹窗里多/少一个动作。
ScanContentKind classifyScanContent(String raw) {
  final text = raw.trim();
  if (text.startsWith('{')) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        if (decoded['upstreams'] is List) return ScanContentKind.profileJson;
        if (decoded['baseUrl'] is String) return ScanContentKind.upstreamJson;
      }
    } catch (_) {
      // 不是 JSON → 落到 URL / 纯文本判断。
    }
  }
  final uri = Uri.tryParse(text);
  if (uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty) {
    return ScanContentKind.url;
  }
  return ScanContentKind.text;
}

/// 处理一次扫码结果：分类 → 按当前 UI 风格弹「扫码结果」→ 执行用户选的动作。
///
/// 由扫码页的调用方（创建配置页）在扫码页 pop 之后调用；这里的 context 已经
/// 是风格正确的页面 context，弹窗/面板/提示都按 [SettingsService.uiStyle] 分派。
Future<void> handleScanResult(
  BuildContext context,
  ServerController controller,
  String raw,
) async {
  switch (classifyScanContent(raw)) {
    case ScanContentKind.profileJson:
      await _importProfileDocument(context, controller, raw.trim());
    case ScanContentKind.upstreamJson:
      await _addUpstream(context, controller, raw.trim());
    case ScanContentKind.url:
      await _offerUrl(context, raw.trim());
    case ScanContentKind.text:
      await _showText(context, raw.trim());
  }
}

bool _isMiuix(BuildContext context) =>
    context.read<SettingsService>().uiStyle.isMiuix;

void _toast(BuildContext context, String message, {bool error = false}) {
  if (_isMiuix(context)) {
    showMiuixToast(context, message, error: error);
  } else {
    showAppToast(context, message, error: error);
  }
}

/// 「扫码结果」弹窗本体：类别徽标 + 等宽预览。两种风格共用，
/// 文本样式从 Theme / MiuixTheme 各取各的。
class ScanResultPreview extends StatelessWidget {
  const ScanResultPreview({
    super.key,
    required this.kindLabel,
    required this.text,
  });

  final String kindLabel;
  final String text;

  @override
  Widget build(BuildContext context) {
    if (_isMiuix(context)) {
      final colors = MiuixTheme.of(context).colors;
      return _body(
        context,
        kindStyle: MiuixText(
          kindLabel,
          fontSize: 12,
          color: colors.onSurfaceVariantSummary,
        ),
        textStyle: MiuixText(
          text,
          fontSize: 13,
          maxLines: 10,
          overflow: TextOverflow.ellipsis,
          color: colors.onSurface,
        ),
      );
    }
    final cs = Theme.of(context).colorScheme;
    return _body(
      context,
      kindStyle: Text(
        kindLabel,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
      ),
      textStyle: Text(
        text,
        maxLines: 10,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          color: cs.onSurface,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context, {
    required Widget kindStyle,
    required Widget textStyle,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      kindStyle,
      const SizedBox(height: 8),
      Flexible(child: SingleChildScrollView(child: textStyle)),
    ],
  );
}

/// 按当前风格弹「扫码结果」并返回用户选的动作（弹窗动作各自 pop 这些值）。
Future<String?> _showScanResultDialog(
  BuildContext context,
  AppLocalizations l10n, {
  required ScanContentKind kind,
  required String text,
  required List<(String, String)> actions,
}) {
  Widget content = ScanResultPreview(
    kindLabel: _kindLabel(l10n, kind),
    text: text,
  );
  if (_isMiuix(context)) {
    return showMiuixDialog<String>(
      context: context,
      title: l10n.qrResultTitle,
      content: content,
      actions: [
        for (var i = 0; i < actions.length; i++)
          MiuixDialogAction(
            label: actions[i].$1,
            primary: i == actions.length - 1,
            onPressed: (ctx) => Navigator.of(ctx).pop(actions[i].$2),
          ),
      ],
    );
  }
  return showDialog<String>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: Text(l10n.qrResultTitle),
      content: content,
      actions: [
        for (var i = 0; i < actions.length; i++)
          if (i == actions.length - 1)
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(actions[i].$2),
              child: Text(actions[i].$1),
            )
          else
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(actions[i].$2),
              child: Text(actions[i].$1),
            ),
      ],
    ),
  );
}

String _kindLabel(AppLocalizations l10n, ScanContentKind kind) =>
    switch (kind) {
      ScanContentKind.profileJson => l10n.qrResultKindProfile,
      ScanContentKind.upstreamJson => l10n.qrResultKindUpstream,
      ScanContentKind.url => l10n.qrResultKindUrl,
      ScanContentKind.text => l10n.qrResultKindText,
    };

/// 应用档案 JSON → 确认后直接写进规则（ProfileStore）。
Future<void> _importProfileDocument(
  BuildContext context,
  ServerController controller,
  String text,
) async {
  final l10n = AppLocalizations.of(context);
  final action = await _showScanResultDialog(
    context,
    l10n,
    kind: ScanContentKind.profileJson,
    text: text,
    actions: [(l10n.cancel, 'cancel'), (l10n.qrResultImportProfile, 'import')],
  );
  if (action != 'import' || !context.mounted) return;
  final store = context.read<ProfileStore>();
  try {
    final profile = store.importDocument(
      text,
      const ProfileSource(ProfileSourceKind.inline),
    );
    if (!context.mounted) return;
    _toast(
      context,
      l10n.profileImported((store.profileOf(profile.id) ?? profile).name),
    );
  } catch (e) {
    if (!context.mounted) return;
    _toast(context, profileErrorMessage(l10n, e), error: true);
  }
}

/// 单个上游 JSON（编辑上游页二维码扫出来的那份）→ 确认后加进本机配置。
Future<void> _addUpstream(
  BuildContext context,
  ServerController controller,
  String text,
) async {
  final l10n = AppLocalizations.of(context);
  final action = await _showScanResultDialog(
    context,
    l10n,
    kind: ScanContentKind.upstreamJson,
    text: text,
    actions: [(l10n.cancel, 'cancel'), (l10n.qrResultAddUpstream, 'add')],
  );
  if (action != 'add' || !context.mounted) return;
  try {
    final u = Upstream.fromJson(jsonDecode(text) as Map<String, dynamic>)
      // 扫来的文档里不带密钥（导出时抹掉了），id 也不能沿用别人的。
      ..id = NetworkUtils.newId()
      ..apiKey = ''
      ..managedBy = null
      ..enabled = true;
    final config = controller.config;
    config.upstreams.add(u);
    controller.store.update(config);
    if (!context.mounted) return;
    _toast(
      context,
      l10n.qrResultUpstreamAdded(u.name.isEmpty ? u.baseUrl : u.name),
    );
  } catch (e) {
    if (!context.mounted) return;
    _toast(context, e.toString(), error: true);
  }
}

/// 网页链接 → 复制，或当订阅地址带进「添加配置文件」面板。
Future<void> _offerUrl(BuildContext context, String url) async {
  final l10n = AppLocalizations.of(context);
  final action = await _showScanResultDialog(
    context,
    l10n,
    kind: ScanContentKind.url,
    text: url,
    actions: [(l10n.copy, 'copy'), (l10n.qrResultImportUrl, 'subscribe')],
  );
  if (!context.mounted) return;
  switch (action) {
    case 'copy':
      copyText(context, url);
    case 'subscribe':
      if (_isMiuix(context)) {
        await showMiuixProfileImportSheet(context, initialUrl: url);
      } else {
        await showAppBottomSheet<ConfigProfile>(
          context: context,
          isScrollControlled: true,
          builder: (_) => ProfileImportSheet(initialUrl: url),
        );
      }
  }
}

/// 纯文本 → 展示 + 复制。
Future<void> _showText(BuildContext context, String text) async {
  final l10n = AppLocalizations.of(context);
  final action = await _showScanResultDialog(
    context,
    l10n,
    kind: ScanContentKind.text,
    text: text,
    actions: [(l10n.copy, 'copy')],
  );
  if (action == 'copy' && context.mounted) copyText(context, text);
}
