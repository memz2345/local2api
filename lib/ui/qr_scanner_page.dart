import 'package:flutter/material.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/widgets/qr_scanner_core.dart';

/// 扫码页（Material 版，对应 miuix 版 `MiuixQrScannerPage`）。
///
/// 顶栏「透明只有样式」：背景全透明、无阴影无色染，白字白图标直接浮在
/// 取景画面上（extendBodyBehindAppBar 让预览从栏下穿过）。动作两个：
/// 切前后摄像头、相册选图识别。
class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
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
      // 轮盘变焦的强调色跟主题：Material 分支用 colorScheme 主色。
      accentColor: Theme.of(context).colorScheme.primary,
    );
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(l10n.qrScannerTitle),
        // 「透明只有样式」：无底色、无阴影、不随滚动染色。
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: l10n.qrScannerSwitchCamera,
            onPressed: () => _coreKey.currentState?.switchCamera(),
            icon: const Icon(Icons.cameraswitch_outlined),
          ),
          IconButton(
            tooltip: l10n.qrScannerGallery,
            onPressed: () => _coreKey.currentState?.pickFromGallery(),
            icon: const Icon(Icons.photo_library_outlined),
          ),
        ],
      ),
      body: core,
    );
  }
}
