import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// trycloudflare 快速隧道（cloudflared）的运行时状态。
enum CloudflaredState { stopped, starting, running, error }

/// Cloudflare Tunnel（trycloudflare 快速隧道）的内建管理：
///
/// 起一个 `cloudflared tunnel --url http://127.0.0.1:<port>` 子进程，
/// 从日志里抓 `https://*.trycloudflare.com` 的临时公网地址。
/// cloudflared 二进制从 PATH / 常见安装位找，找不到就进 [error] 态
/// （内建隧道目前只对桌面端现实可用 —— Android 的 W^X 限制不允许
/// 应用目录里的可执行文件，`Process.start` 会直接失败并落进同一错误态）。
///
/// 启用前的 Cloudflare 服务条款同意流程在 UI 层（网络页）：
/// [fetchCloudflareTermsText] 拉条款全文，用户同意后写进
/// `ProxyConfig.cloudflaredAgreedMs`，这里不管同意与否。
class CloudflaredTunnelService extends ChangeNotifier {
  Process? _process;
  CloudflaredState _state = CloudflaredState.stopped;
  String? _url;
  String? _error;

  /// 当前隧道转发到的本地端口（启动时记录；配置里的端口变了要重连）。
  int? forwardedPort;
  Timer? _startTimeout;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  StreamSubscription<Object>? _exitSub;
  bool _stoppingByUser = false;

  CloudflaredState get state => _state;
  String? get url => _url;
  String? get error => _error;
  bool get isBusy => _state == CloudflaredState.starting;

  /// cloudflared 日志里临时隧道的地址形如
  /// `https://xxxx-xxxx-xxxx-xxxx.trycloudflare.com`。
  static final RegExp _urlPattern = RegExp(
    r'https://[a-zA-Z0-9-]+\.trycloudflare\.com',
  );

  /// Cloudflare 服务条款（trycloudflare 受其约束）。
  static const String termsUrl = 'https://www.cloudflare.com/terms/';

  /// 把条款页拉成纯文本（剥掉 HTML 标签与脚本样式）。失败抛异常，
  /// 由调用方映射成「拉取失败」提示。
  static Future<String> fetchCloudflareTermsText() async {
    final client = HttpClient()..userAgent = 'Local2API/0.1';
    try {
      final request = await client.getUrl(Uri.parse(termsUrl));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final html = await response.transform(utf8.decoder).join();
      return _htmlToText(html);
    } finally {
      client.close(force: true);
    }
  }

  /// 极简 HTML → 文本：去掉 script/style/head，块级标签换行，压空白。
  static String _htmlToText(String html) {
    var text = html.replaceAllMapped(
      RegExp(r'<(script|style|head|svg)[\s\S]*?</\1>', caseSensitive: false),
      (m) => '',
    );
    text = text
        .replaceAllMapped(
          RegExp(r'<(br|/p|/div|/h[1-6]|/li|/tr)\s*/?>', caseSensitive: false),
          (_) => '\n',
        )
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    // 按行压空白、去连续空行，控制篇幅。
    final lines = text
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return lines.join('\n');
  }

  /// 探测本机的 Tailscale IPv4（CGNAT 网段 100.64.0.0/10，即
  /// 100.64.0.0 – 100.127.255.255）。没有返回 null。
  static Future<String?> detectTailscaleIpV4() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type != InternetAddressType.IPv4) continue;
          final octets = addr.address.split('.');
          if (octets.length != 4) continue;
          final second = int.tryParse(octets[1]);
          if (octets[0] == '100' &&
              second != null &&
              second >= 64 &&
              second <= 127) {
            return addr.address;
          }
        }
      }
    } catch (_) {
      // 接口枚举失败（个别平台权限）：当没装 Tailscale 处理。
    }
    return null;
  }

  /// 找 cloudflared 可执行文件：PATH（where/which）→ 返回路径；没有就 null。
  Future<String?> findBinary() async {
    if (Platform.isWindows) {
      try {
        final result = await Process.run('where', ['cloudflared']);
        if (result.exitCode == 0) {
          final lines = (result.stdout as String)
              .trim()
              .split('\n')
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty)
              .toList();
          if (lines.isNotEmpty) return lines.first;
        }
      } catch (_) {}
      // 与可执行文件同目录的 cloudflared.exe（绿色部署常见放法）。
      try {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final candidate = '$exeDir\\cloudflared.exe';
        if (File(candidate).existsSync()) return candidate;
      } catch (_) {}
      return null;
    }
    try {
      final result = await Process.run('which', ['cloudflared']);
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim();
        if (path.isNotEmpty) return path;
      }
    } catch (_) {}
    return null;
  }

  /// 启动快速隧道，转发到 `127.0.0.1:[port]`。
  Future<void> start(int port) async {
    if (_state == CloudflaredState.starting ||
        _state == CloudflaredState.running) {
      return;
    }
    _stoppingByUser = false;
    _url = null;
    _error = null;
    forwardedPort = port;
    _setState(CloudflaredState.starting);

    final binary = await findBinary();
    if (binary == null) {
      _fail('cloudflared not found');
      return;
    }
    try {
      _process = await Process.start(binary, [
        'tunnel',
        '--no-autoupdate',
        '--url',
        'http://127.0.0.1:$port',
      ]);
    } catch (e) {
      _fail('$e');
      return;
    }

    final process = _process!;
    _stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLogLine, onError: (Object _) {});
    _stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLogLine, onError: (Object _) {});
    _exitSub = process.exitCode.asStream().listen(_onExit);

    // 快速隧道一般几秒内出地址；40 秒还不出视为起不来。
    _startTimeout = Timer(const Duration(seconds: 40), () {
      if (_state == CloudflaredState.starting) {
        _fail('trycloudflare timeout');
        unawaited(stop());
      }
    });
  }

  void _onLogLine(String line) {
    if (_state == CloudflaredState.running) return;
    final match = _urlPattern.firstMatch(line);
    if (match == null) return;
    _startTimeout?.cancel();
    _startTimeout = null;
    _url = match.group(0);
    _error = null;
    _setState(CloudflaredState.running);
  }

  void _onExit(Object code) {
    _startTimeout?.cancel();
    _startTimeout = null;
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _exitSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _exitSub = null;
    _process = null;
    if (_stoppingByUser) {
      _setState(CloudflaredState.stopped);
      return;
    }
    // 没人叫停自己退了：如果还没拿到地址，按错误态收场。
    _url = null;
    if (_state == CloudflaredState.running) {
      _setState(CloudflaredState.stopped);
    } else {
      _fail('cloudflared exited ($code)');
    }
  }

  void _fail(String message) {
    _startTimeout?.cancel();
    _startTimeout = null;
    _error = message;
    _setState(CloudflaredState.error);
  }

  Future<void> stop() async {
    _stoppingByUser = true;
    _startTimeout?.cancel();
    _startTimeout = null;
    final process = _process;
    _process = null;
    if (process != null) {
      process.kill();
      // 等退场收尾（_onExit 会把订阅清掉），别留着僵尸。
      await process.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () => -1,
      );
    }
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _exitSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _exitSub = null;
    _url = null;
    _setState(CloudflaredState.stopped);
  }

  void _setState(CloudflaredState value) {
    if (_state == value) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _stoppingByUser = true;
    _startTimeout?.cancel();
    unawaited(stop());
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _exitSub?.cancel();
    super.dispose();
  }
}
