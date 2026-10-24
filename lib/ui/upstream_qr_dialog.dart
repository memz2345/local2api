import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' show MiuixText, MiuixTheme;
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/src/enums.dart' show UiStyleX;
import 'package:local2api/widgets/app_toast.dart';
import 'package:local2api/widgets/miuix/miuix_dialog.dart';
import 'package:local2api/widgets/miuix/miuix_toast.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// 上游 JSON 的紧凑序列化（抹掉 apiKey，原则与 `upstreamJsonText` 一致：
/// 这是分享用的元数据，不能把密钥带出去）。
///
/// 用紧凑而非缩进格式 —— QR 容量就那么点，缩进全是白烧的字符。
String upstreamQrPayload(Upstream upstream) => jsonEncode(
  Upstream.fromJson({...upstream.toJson(), 'apiKey': ''}).toJson(),
);

/// QR 数据量护栏。QR 版本 40 + 纠错 L 的字节上限是 2953，但摄像头对高版本
/// 密码的分辨率余量很紧，这里按 2400 字节兜底，超了直接提示生成不了。
const int _kMaxQrBytes = 2400;

bool _isMiuix(BuildContext context) =>
    context.read<SettingsService>().uiStyle.isMiuix;

/// 「编辑上游」顶栏二维码按钮的弹窗：把当前上游的 JSON 元数据渲染成二维码，
/// 另一台装了本应用的设备扫一扫就能把这个上游加进它的规则。
///
/// 剪辑草稿（输入框里还没保存的值）通过 [draft] 传进来 —— 弹的是用户正在
/// 编辑的内容，不是落盘的那份。超出 QR 容量时提示并放弃，不弹半成品。
Future<void> showUpstreamQrDialog(BuildContext context, Upstream draft) async {
  final l10n = AppLocalizations.of(context);
  final payload = upstreamQrPayload(draft);
  if (utf8.encode(payload).length > _kMaxQrBytes) {
    if (_isMiuix(context)) {
      showMiuixToast(context, l10n.upstreamQrTooLong, error: true);
    } else {
      showAppToast(context, l10n.upstreamQrTooLong, error: true);
    }
    return;
  }
  final body = _UpstreamQrBody(payload: payload, hint: l10n.upstreamQrHint);
  if (_isMiuix(context)) {
    await showMiuixDialog<void>(
      context: context,
      title: l10n.upstreamQrTitle,
      content: body,
      actions: [
        MiuixDialogAction(
          label: l10n.confirm,
          primary: true,
          onPressed: (ctx) => Navigator.of(ctx).pop(),
        ),
      ],
    );
  } else {
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l10n.upstreamQrTitle),
        content: body,
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
  }
}

class _UpstreamQrBody extends StatelessWidget {
  const _UpstreamQrBody({required this.payload, required this.hint});

  final String payload;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final miuix = _isMiuix(context);
    final hintColor = miuix
        ? MiuixTheme.of(context).colors.onSurfaceVariantSummary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final hintWidget = miuix
        ? MiuixText(hint, fontSize: 12, color: hintColor)
        : Text(
            hint,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: hintColor, height: 1.35),
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            // 白底 + 12 的静默区：深色主题下弹窗是深色的，QR 必须压一块白
            // 才有对比度，扫起来才稳。
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            child: SizedBox(
              width: 240,
              height: 240,
              // 用 QrPainter 而不是 QrImageView：后者内部是 LayoutBuilder，
              // 而 AlertDialog / miuix 对话框都按 intrinsic 尺寸量内容，
              // LayoutBuilder 不支持 intrinsic 计算 → debug 包直接抛异常。
              child: CustomPaint(
                painter: QrPainter(
                  data: payload,
                  version: QrVersions.auto,
                  gapless: true,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        hintWidget,
      ],
    );
  }
}
