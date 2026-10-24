import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/proxy_config.dart';
import 'character_store.dart';
import 'cloudflared_tunnel.dart';
import 'config_store.dart';
import 'network_utils.dart';
import 'proxy_server.dart';
import 'webui_server.dart';

/// 服务开关 + 配置联动的总控。
///
/// UI 只跟这个类打交道：
/// - `toggle()` 一键启停
/// - 配置改动时若正在运行，自动热重启让端口/监听地址生效
///   （密钥/规则/上游列表的改动无需重启，处理请求时实时读取）。
///
/// 临时 WebUI 是**旁路**：它有自己的开关与端口（[ProxyConfig.webUiPort]），
/// 起停都不影响转发服务，所以状态、热重启判据全都单独一套。
class ServerController extends ChangeNotifier {
  final ConfigStore store;
  late final ProxyServer server;

  /// 临时 WebUI（独立端口的网页控制台）。默认关，开了才占端口。
  late final WebUiServer webUi;

  /// Cloudflare Tunnel（trycloudflare）内建隧道的进程管理。
  /// 生命周期独立于 HTTP 服务本身（隧道转发到 127.0.0.1:port，
  /// 服务没起时隧道照样能挂着）。
  final CloudflaredTunnelService tunnel = CloudflaredTunnelService();

  /// 本机局域网/VPN IPv4 地址（构造时异步获取）。
  List<String> lanAddresses = const [];

  /// WebUI 是否随配置联动自动起停。只在测试里关掉：
  /// widget test 的假时钟不允许 `HttpServer.bind` 留下的空闲计时器活着。
  bool webUiAutoStart = true;

  ServerController(this.store) {
    server = ProxyServer(configProvider: () => store.config);
    webUi = WebUiServer(
      configProvider: () => store.config,
      // 「发现」页的人设卡：预制 + 自建都给，网页侧只读（带 builtin 标记，
      // 页面上分开显示）。改动只影响这次注入，不落到 App 的存档里。
      charactersProvider: () => [for (final c in characterStore.cards) c],
      // 前端资源（mdui 组件库 / 图标字体）跟着 App 打包，页面离线可用。
      assetLoader: (name) async {
        final data = await rootBundle.load('assets/webui/$name');
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      },
    );
    store.addListener(_onConfigChanged);
    _loadLanAddresses();
  }

  Future<void> _loadLanAddresses() async {
    try {
      lanAddresses = await NetworkUtils.localLanAddresses();
      notifyListeners();
    } catch (_) {}
  }

  ProxyConfig get config => store.config;

  ServerState get state => server.state.value;
  bool get isRunning => server.isRunning;

  void _onConfigChanged() {
    notifyListeners();
    final cfg = store.config;
    if (server.isRunning &&
        (server.boundHost != cfg.listenHost ||
            server.boundPort != cfg.listenPort)) {
      // 端口/监听地址变了：热重启
      restart();
    }
    _syncWebUi(cfg);
    // 隧道开着但配置的端口变了：转发目标跟着重连。
    if (cfg.cloudflaredEnabled &&
        tunnel.state == CloudflaredState.running &&
        tunnel.forwardedPort != cfg.listenPort) {
      unawaited(tunnel.stop().then((_) => tunnel.start(cfg.listenPort)));
    }
  }

  /// WebUI 的三态联动：开关变了立刻起停，开着时端口/地址变了就重启。
  void _syncWebUi(ProxyConfig cfg) {
    if (!webUiAutoStart) return;
    if (!cfg.webUiEnabled) {
      if (webUi.isRunning) unawaited(webUi.stop());
      return;
    }
    if (!webUi.isRunning) {
      unawaited(_startWebUi());
      return;
    }
    if (webUi.boundHost != cfg.webUiHost || webUi.boundPort != cfg.webUiPort) {
      unawaited(_restartWebUi());
    }
  }

  Future<void> _startWebUi() async {
    if (!webUiAutoStart) {
      notifyListeners();
      return;
    }
    try {
      await webUi.start();
    } catch (_) {
      // state / lastError 已由 WebUiServer 更新
    }
    notifyListeners();
  }

  Future<void> _restartWebUi() async {
    await webUi.stop();
    await _startWebUi();
  }

  /// 手动开关 WebUI（UI 上的开关行走这里，不经过配置联动）。
  Future<void> setWebUiEnabled(bool on) async {
    final cfg = config;
    cfg.webUiEnabled = on;
    store.update(cfg);
    if (on) {
      await _startWebUi();
    } else {
      await webUi.stop();
      notifyListeners();
    }
  }

  Future<void> start() async {
    try {
      await server.start();
    } catch (_) {
      // state/lastError 已由 ProxyServer 更新
    }
    _syncWebUi(config);
    notifyListeners();
  }

  Future<void> stop() async {
    await server.stop();
    // WebUI 是临时旁路：主服务停了它也跟着收摊，避免留一个孤儿端口。
    await webUi.stop();
    notifyListeners();
  }

  Future<void> toggle() async {
    if (isRunning) {
      await stop();
    } else {
      await start();
    }
  }

  Future<void> restart() async {
    await server.stop();
    await start();
  }

  @override
  void dispose() {
    store.removeListener(_onConfigChanged);
    webUi.dispose();
    server.dispose();
    tunnel.dispose();
    super.dispose();
  }
}
