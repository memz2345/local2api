// lib/widgets/browser_error_pages.dart
//
// 内置浏览器初始化 / 加载失败时的整页错误视图，自 NaviFlash
// `screens/browser_page.dart` 的四套错误页原样搬来：
//
//   · Windows  → BSOD（WebView2 运行库缺失 / 加载失败）
//   · Android  → 挂掉的安卓机器人（系统 WebView 太老或没装）
//   · iOS/macOS→ Apple 风（WKWebView 初始化失败）
//   · 其它平台 → kernel panic（压根没有 webview 实现）
//
// 这几页是刻意「不跟主题走」的：BSOD 就该是那个蓝、错误页就该丑得显眼。
// Material / miuix 两个页面共用这一份，免得各画一套还画不一样。

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';

/// 错误页样式。
enum BrowserErrorStyle { bsod, android, apple, generic }

class BrowserErrorPage extends StatelessWidget {
  const BrowserErrorPage({
    super.key,
    required this.style,
    required this.onBack,
    this.detail,
  });

  final BrowserErrorStyle style;

  /// 返回上一页（错误页唯一能做的事）。
  final VoidCallback onBack;

  /// 具体错误信息（可选，Android / Apple 两页当作「报告」内容）。
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return switch (style) {
      BrowserErrorStyle.bsod => _BsodPage(onBack: onBack),
      BrowserErrorStyle.android => _AndroidPage(onBack: onBack, detail: detail),
      BrowserErrorStyle.apple => _ApplePage(onBack: onBack, detail: detail),
      BrowserErrorStyle.generic => _GenericPage(onBack: onBack),
    };
  }
}

Future<void> _openExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } catch (_) {}
}

// ---------------------------------------------------------------------------
// Windows：蓝屏
// ---------------------------------------------------------------------------

class _BsodPage extends StatelessWidget {
  const _BsodPage({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final bgColor = cs.primary;
    final textColor = cs.onPrimary;
    return Container(
      color: bgColor,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(40, 40, 40, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ':(',
                style: TextStyle(
                  color: textColor,
                  fontSize: 100,
                  fontWeight: FontWeight.w300,
                  height: 1,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.browserBsodMessage,
                style: TextStyle(color: textColor, fontSize: 22, height: 1.4),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.browserBsodNoRestart,
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.8),
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.browserBsodComplete,
                style: TextStyle(color: textColor, fontSize: 22),
              ),
              const SizedBox(height: 32),
              Text(
                l10n.browserBsodSolutions,
                style: TextStyle(color: textColor, fontSize: 16),
              ),
              const SizedBox(height: 8),
              _BsodLink(
                text: l10n.browserBsodDownload,
                url: 'https://developer.microsoft.com/microsoft-edge/webview2/',
                color: textColor,
              ),
              _BsodLink(
                text: l10n.browserBsodWinUpdate,
                url: 'ms-settings:windowsupdate',
                color: textColor,
              ),
              const SizedBox(height: 32),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    color: Colors.white,
                    margin: const EdgeInsets.only(right: 16),
                    padding: const EdgeInsets.all(4),
                    child: QrImageView(
                      data:
                          'https://developer.microsoft.com/microsoft-edge/webview2/',
                      version: QrVersions.auto,
                      size: 72,
                      backgroundColor: Colors.white,
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.browserBsodScanQr,
                          style: TextStyle(
                            color: textColor.withValues(alpha: 0.9),
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.browserBsodStopCode,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              TextButton.icon(
                onPressed: onBack,
                icon: Icon(Icons.arrow_back, size: 18, color: textColor),
                label: Text(
                  l10n.commonBack,
                  style: TextStyle(color: textColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BsodLink extends StatelessWidget {
  const _BsodLink({required this.text, required this.url, required this.color});

  final String text;
  final String url;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openExternal(url),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 15,
            decoration: TextDecoration.underline,
            decorationColor: color,
            height: 1.6,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Android：死掉的安卓机器人
// ---------------------------------------------------------------------------

class _AndroidPage extends StatelessWidget {
  const _AndroidPage({required this.onBack, this.detail});

  final VoidCallback onBack;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: const Color(0xFF1B1B1B),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 30, 32, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              SizedBox(
                width: 120,
                height: 120,
                child: CustomPaint(
                  painter: _DeadAndroidPainter(
                    color: cs.error.withValues(alpha: 0.85),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                l10n.browserAndroidErrorTitle,
                style: TextStyle(
                  color: cs.error.withValues(alpha: 0.85),
                  fontSize: 28,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'No command.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 36),
              _ErrorInfoBlock(
                label: l10n.browserAndroidErrorCause,
                content: detail?.isNotEmpty == true
                    ? detail!
                    : l10n.browserAndroidErrorDetail,
              ),
              const SizedBox(height: 18),
              _ErrorLink(
                text: l10n.browserUpdateWebview,
                url:
                    'https://play.google.com/store/apps/details?id=com.google.android.webview',
              ),
              const SizedBox(height: 8),
              _ErrorLink(text: l10n.browserOpenDevOptions, url: '#'),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: onBack,
                icon: const Icon(
                  Icons.arrow_back,
                  size: 18,
                  color: Colors.white70,
                ),
                label: Text(
                  l10n.commonBack,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// iOS / macOS：Apple 风
// ---------------------------------------------------------------------------

class _ApplePage extends StatelessWidget {
  const _ApplePage({required this.onBack, this.detail});

  final VoidCallback onBack;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final textColor = isDark ? Colors.white : Colors.black;
    return Container(
      color: bgColor,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.error_outline,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  l10n.browserAppleErrorTitle,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'WebView initialization failed',
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 36),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: textColor.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: textColor.withValues(alpha: 0.1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.browserAppleErrorReport,
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.6),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        detail?.isNotEmpty == true
                            ? detail!
                            : l10n.browserAppleErrorDetail,
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.5),
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.tonalIcon(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: Text(l10n.commonBack),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 其它平台：kernel panic
// ---------------------------------------------------------------------------

class _GenericPage extends StatelessWidget {
  const _GenericPage({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Kernel panic - not syncing',
                  style: TextStyle(
                    color: cs.error,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '[  0.000000] WebView Initialization Failed',
                        style: TextStyle(
                          color: Colors.red[300],
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const Text(
                        '[  0.004000] CPU: Flutter/Dart Unsupported',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const Text(
                        '[  0.008000] Attempted to init native browser',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const Text(
                        '[  0.012000] ---[ end Kernel panic - not syncing ]---',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.tonalIcon(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: Text(l10n.commonBack),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 公共零件
// ---------------------------------------------------------------------------

class _ErrorInfoBlock extends StatelessWidget {
  const _ErrorInfoBlock({required this.label, required this.content});

  final String label;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            content,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorLink extends StatelessWidget {
  const _ErrorLink({required this.text, required this.url});

  final String text;
  final String url;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: url == '#' ? null : () => _openExternal(url),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 14,
            decoration: url == '#' ? null : TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}

/// Android 那个「躺平的机器人」：机器人体 + × 眼 + 天线 + 胸口警示三角。
class _DeadAndroidPainter extends CustomPainter {
  _DeadAndroidPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, cy + 12),
          width: w * 0.28,
          height: h * 0.38,
        ),
        const Radius.circular(12),
      ),
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );

    final headRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, cy - 22),
        width: w * 0.34,
        height: h * 0.22,
      ),
      const Radius.circular(14),
    );
    canvas.drawRRect(
      headRect,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );

    paint.strokeWidth = 3;
    canvas.drawLine(Offset(cx - 10, cy - 36), Offset(cx - 16, cy - 52), paint);
    canvas.drawLine(Offset(cx + 10, cy - 36), Offset(cx + 16, cy - 52), paint);

    paint.strokeWidth = 3.5;
    const eyeW = 10.0;
    canvas.drawLine(
      Offset(cx - 14 - eyeW, cy - 28),
      Offset(cx - 14 + eyeW, cy - 18),
      paint,
    );
    canvas.drawLine(
      Offset(cx - 14 + eyeW, cy - 28),
      Offset(cx - 14 - eyeW, cy - 18),
      paint,
    );
    canvas.drawLine(
      Offset(cx + 14 - eyeW, cy - 28),
      Offset(cx + 14 + eyeW, cy - 18),
      paint,
    );
    canvas.drawLine(
      Offset(cx + 14 + eyeW, cy - 28),
      Offset(cx + 14 - eyeW, cy - 18),
      paint,
    );

    final triPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final triPath = Path()
      ..moveTo(cx, cy + 42)
      ..lineTo(cx - 10, cy + 30)
      ..lineTo(cx + 10, cy + 30)
      ..close();
    canvas.drawPath(triPath, triPaint);
    canvas.drawLine(Offset(cx, cy + 34), Offset(cx, cy + 38), paint);
    canvas.drawCircle(Offset(cx, cy + 40.5), 1.2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
