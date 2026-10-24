import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';
import 'package:local2api/widgets/miuix/miuix_blur_top_bar.dart';
import 'package:local2api/widgets/qr_scanner_core.dart';

/// 扫码页（miuix 版，对应 Material 版 `QrScannerPage`）。
///
/// 顶栏仍是 miuix 那套样式（返回键 / 标题 / 动作的排布与动效），但底色
/// **全透明**（`backgroundColor: Colors.transparent`）—— 浮在取景画面上，
/// 毛玻璃与大标题模糊一并关掉，不然像糊了一层在镜头上。
class MiuixQrScannerPage extends StatefulWidget {
  const MiuixQrScannerPage({super.key});

  @override
  State<MiuixQrScannerPage> createState() => _MiuixQrScannerPageState();
}

class _MiuixQrScannerPageState extends State<MiuixQrScannerPage> {
  final GlobalKey<QrScannerCoreState> _coreKey = GlobalKey();

  /// 识别到内容 → 带值 pop，由打开这一页的调用方（创建配置页）处理结果。
  void _onDetected(String value) {
    if (mounted) Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final core = QrScannerCore(
      key: _coreKey,
      onDetected: _onDetected,
      // 轮盘变焦的强调色跟主题：miuix 分支用 MiuixTheme 主色。
      accentColor: MiuixTheme.of(context).colors.primary,
    );
    return Material(
      type: MaterialType.transparency,
      child: MiuixScaffold(
        // 镜头没起来（权限页 / 不支持页）时底色是黑的，跟取景画面一致。
        containerColor: Colors.black,
        topBar: MiuixBlurTopBar(
          title: l10n.qrScannerTitle,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          navigationIcon: MiuixIconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const MiuixAppIcon(
              AppIconNames.back,
              fallback: Icons.arrow_back,
              color: Colors.white,
            ),
          ),
          actions: [
            MiuixIconButton(
              onPressed: () => _coreKey.currentState?.switchCamera(),
              child: const MiuixAppIcon(
                'camera',
                fallback: Icons.cameraswitch_outlined,
                color: Colors.white,
              ),
            ),
            MiuixIconButton(
              onPressed: () => _coreKey.currentState?.pickFromGallery(),
              child: const MiuixAppIcon(
                AppIconNames.album,
                fallback: Icons.photo_library_outlined,
                color: Colors.white,
              ),
            ),
          ],
        ),
        content: (padding) => core,
      ),
    );
  }
}
