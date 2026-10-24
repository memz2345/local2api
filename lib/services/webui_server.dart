import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/proxy_config.dart';
import 'character_store.dart';

/// 临时 WebUI：一个**独立端口**的本机网页控制台。
///
/// 为什么另起一个端口而不是挂在转发口上：
/// - 转发口（[ProxyConfig.listenPort]）往往是客户端里写死的地址，
///   给它塞一个 `/` 页面会让「连上就是 API」的假设破掉；
/// - WebUI 是「临时拉起来看一眼」的旁路，默认监听 127.0.0.1，
///   起停都不该动到转发链路（连 `shared` 都不共用）。
///
/// 页面本身是零依赖的单文件：HTML/CSS/JS 全内联在 [kWebUiHtml] 里，
/// 不注册 asset、不加 pubspec 依赖。
///
/// **页面怎么跟 API 说话**：网页与 API 转发口不同源，直接 fetch 会踩 CORS；
/// 而且 API 口可能配了密钥。所以 WebUI 自己当一层反代：`/v1/*` 一律转发到
/// `127.0.0.1:<listenPort>`，并顺手补上第一条启用的密钥 —— 于是页面
/// **不用填地址、也不用填密钥**就能直接对话，密钥也不落进浏览器。
class WebUiServer {
  WebUiServer({
    required this.configProvider,
    this.charactersProvider,
    this.assetLoader,
  });

  final ProxyConfig? Function() configProvider;

  /// 给网页「发现」页读的人设卡（只读）。
  ///
  /// 预制 + 自建都收；序列化时带 `builtin` 标记，页面靠它分开显示。
  /// 为 null 时发现页显示空态。
  final List<CharacterCard> Function()? charactersProvider;

  /// 读打包进来的静态资源（mdui 的 css/js、Material Icons 字体）。
  ///
  /// 由 `ServerController` 注入 `rootBundle` 读 —— 这样页面**离线可用**，
  /// 不去 CDN 拉；测试里可以注入一份假的。null = 静态资源 404。
  final Future<List<int>> Function(String name)? assetLoader;

  /// 静态资源内存缓存：一次读出来，之后直接吐。
  final Map<String, List<int>> _assets = {};

  HttpServer? _server;
  String _boundHost = '';
  int _boundPort = 0;
  String? _lastError;

  /// 反代用的长连接客户端（懒建）。
  HttpClient? _client;

  /// 跳过头：这些要么跟本次连接绑定，要么由 Dart 自己重算。
  static const Set<String> _skipHeaders = {
    'host',
    'connection',
    'keep-alive',
    'proxy-authenticate',
    'proxy-authorization',
    'te',
    'trailer',
    'transfer-encoding',
    'upgrade',
    'content-length',
  };

  /// WebUI 自己的运行状态（与转发服务 [ServerState] 无关，独立成枚举值回传）。
  final ValueNotifier<WebUiState> state = ValueNotifier(WebUiState.stopped);

  bool get isRunning => state.value == WebUiState.running;
  String get boundHost => _boundHost;
  int get boundPort => _boundPort;
  String? get lastError => _lastError;

  /// 页面地址（运行中才有意义）。
  Uri? get url => _server == null
      ? null
      : Uri(
          scheme: 'http',
          host: _boundHost == '0.0.0.0' ? '127.0.0.1' : _boundHost,
          port: _boundPort,
          path: '/',
        );

  Future<void> start() async {
    if (isRunning || state.value == WebUiState.starting) return;
    final config = configProvider();
    if (config == null) return;
    state.value = WebUiState.starting;
    _lastError = null;
    try {
      final server = await HttpServer.bind(
        InternetAddress(config.webUiHost),
        config.webUiPort,
        shared: false,
      );
      _server = server;
      _boundHost = config.webUiHost;
      _boundPort = config.webUiPort;
      server.listen(_handle, cancelOnError: false);
      state.value = WebUiState.running;
    } catch (e) {
      state.value = WebUiState.error;
      _lastError = e.toString();
      rethrow;
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    state.value = WebUiState.stopped;
    _client?.close(force: true);
    _client = null;
    try {
      await server?.close(force: true);
    } catch (_) {}
  }

  void dispose() {
    unawaited(stop());
    state.dispose();
  }

  Future<void> _handle(HttpRequest req) async {
    final resp = req.response;
    try {
      final path = req.uri.path;
      if (path == '/healthz') {
        resp.headers.contentType = ContentType.json;
        resp.write('{"status":"ok","ui":true}');
        await resp.close();
        return;
      }
      // 启动信息：网页拿它填模型选择器（已配置的对外模型）+ 确认代理可用。
      if (path == '/api/bootstrap') {
        final config = configProvider();
        resp.headers.contentType = ContentType.json;
        resp.headers.set('Cache-Control', 'no-store');
        resp.write(jsonEncode(_bootstrap(config)));
        await resp.close();
        return;
      }
      // 「发现」页读人设卡：只读，不提供增删改。
      if (path == '/api/characters') {
        resp.headers.contentType = ContentType.json;
        resp.headers.set('Cache-Control', 'no-store');
        resp.write(jsonEncode(_characters()));
        await resp.close();
        return;
      }
      // 打包进来的前端资源（mdui 的 css/js + Material Icons 字体）。
      if (path.startsWith('/assets/')) {
        await _serveAsset(req, path.substring('/assets/'.length));
        return;
      }
      // `/v1/*` 反代到真正的 API 口，顺手补密钥（页面因此不用填 key）。
      if (path.startsWith('/v1/')) {
        await _proxy(req);
        return;
      }
      // 其余一律回同一份单文件页面（SPA 只有一页，刷新也落在根路径）
      resp.statusCode = HttpStatus.ok;
      resp.headers.contentType = ContentType.html;
      resp.headers.set('Cache-Control', 'no-store');
      resp.write(kWebUiHtml);
      await resp.close();
    } catch (_) {
      try {
        await resp.close();
      } catch (_) {}
    }
  }

  /// 给网页的启动信息：已配置的对外模型 + 代理基址 + 是否配了密钥。
  Map<String, Object?> _bootstrap(ProxyConfig? config) {
    final models = <String>[];
    var hasKey = false;
    if (config != null) {
      for (final u in config.upstreams) {
        if (!u.enabled) continue;
        for (final m in u.models) {
          if (!m.enabled) continue;
          if (!models.contains(m.publicName)) models.add(m.publicName);
        }
      }
      hasKey = config.apiKeys.any((k) => k.enabled && k.key.isNotEmpty);
    }
    return {
      // 同源相对路径：请求打回 WebUI 自己，由 _proxy 转给 API 口。
      'base': '/v1',
      'apiPort': config?.listenPort,
      'models': models,
      'hasKey': hasKey,
    };
  }

  /// 发现页的人设卡清单（只读）。
  ///
  /// 形状与 App 里的 `CharacterCard` 对齐（名字 / 人设提示词 / 预制问答 /
  /// 是否预制），页面拿它「应用」到当前对话：system 换成 prompt、预制
  /// 问答铺成历史；`builtin` 只影响展示（打「预制」徽标、分组）。
  Map<String, Object?> _characters() {
    final cards = charactersProvider?.call() ?? const <CharacterCard>[];
    return {
      'characters': [
        for (final c in cards)
          {
            'id': c.id,
            'name': c.name,
            'prompt': c.prompt,
            'builtin': c.builtin,
            'presets': [
              for (final p in c.presets)
                {'user': p.user, 'assistant': p.assistant},
            ],
          },
      ],
    };
  }

  /// 把打包进来的静态资源吐给浏览器（带内存缓存 + 长缓存头）。
  Future<void> _serveAsset(HttpRequest req, String name) async {
    final resp = req.response;
    // 只认单层文件名：挡掉 `../` 与子目录，别让它变成任意文件读。
    if (name.isEmpty ||
        name.contains('/') ||
        name.contains('\\') ||
        name.contains('..')) {
      await _fail(resp, HttpStatus.notFound, 'bad asset path');
      return;
    }
    final loader = assetLoader;
    if (loader == null) {
      await _fail(resp, HttpStatus.notFound, 'assets unavailable');
      return;
    }
    var bytes = _assets[name];
    if (bytes == null) {
      try {
        bytes = await loader(name);
        _assets[name] = bytes;
      } catch (_) {
        await _fail(resp, HttpStatus.notFound, 'no such asset: $name');
        return;
      }
    }
    resp.headers.contentType = _assetContentType(name);
    // 资源跟着 App 打包，版本不会偷偷变，放心让浏览器缓存一天。
    resp.headers.set('Cache-Control', 'public, max-age=86400');
    resp.add(bytes);
    await resp.close();
  }

  static ContentType _assetContentType(String name) {
    if (name.endsWith('.css')) {
      return ContentType('text', 'css', charset: 'utf-8');
    }
    if (name.endsWith('.js')) {
      return ContentType('application', 'javascript', charset: 'utf-8');
    }
    if (name.endsWith('.woff2')) return ContentType('font', 'woff2');
    if (name.endsWith('.woff')) return ContentType('font', 'woff');
    if (name.endsWith('.svg')) return ContentType('image', 'svg+xml');
    if (name.endsWith('.png')) return ContentType('image', 'png');
    return ContentType.binary;
  }

  /// 把 `/v1/*` 的请求转到本机转发口，并补上第一条启用的密钥。
  Future<void> _proxy(HttpRequest req) async {
    final resp = req.response;
    final config = configProvider();
    final port = config?.listenPort;
    if (port == null) {
      await _fail(resp, HttpStatus.serviceUnavailable, 'API 端口未知');
      return;
    }
    final client = _client ??= HttpClient()..autoUncompress = false;
    // SSE 要边收边发，别等整包。
    resp.bufferOutput = false;
    try {
      final target = Uri.parse(
        'http://127.0.0.1:$port${req.uri.toString()}',
      );
      final preq = await client.openUrl(req.method, target);
      req.headers.forEach((name, values) {
        if (_skipHeaders.contains(name.toLowerCase())) return;
        preq.headers.set(name, values);
      });
      final key = _firstKey(config);
      if (key != null && preq.headers.value('authorization') == null) {
        preq.headers.set('authorization', 'Bearer $key');
      }
      await preq.addStream(req);
      final pres = await preq.close();
      resp.statusCode = pres.statusCode;
      pres.headers.forEach((name, values) {
        if (_skipHeaders.contains(name.toLowerCase())) return;
        resp.headers.set(name, values);
      });
      resp.headers.set('Cache-Control', 'no-store');
      await resp.addStream(pres);
    } catch (e) {
      await _fail(resp, HttpStatus.badGateway, 'API 口连不上：$e');
      return;
    }
    try {
      await resp.close();
    } catch (_) {}
  }

  String? _firstKey(ProxyConfig? config) {
    if (config == null) return null;
    for (final k in config.apiKeys) {
      if (k.enabled && k.key.isNotEmpty) return k.key;
    }
    return null;
  }

  Future<void> _fail(HttpResponse resp, int status, String message) async {
    try {
      resp.statusCode = status;
      resp.headers.contentType = ContentType.json;
      resp.write(jsonEncode({'error': {'message': message}}));
      await resp.close();
    } catch (_) {}
  }
}

/// WebUI 的运行状态。刻意不与转发的 [ServerState] 合并：
/// 它是旁路，起停不该影响主服务的心跳显示。
enum WebUiState { stopped, starting, running, error }

/// 单文件网页控制台。
///
/// UI 用 **mdui 2**（Material Design 3 的 Web Components 库，MIT）：
/// 顶栏 `mdui-top-app-bar`、侧栏 `mdui-list-item`、模型选择器 `mdui-dropdown` +
/// `mdui-menu`、卡片 `mdui-card`、消息条 `mdui-snackbar`。
/// 输入台里那格是**裸 `<textarea>`**：mdui-text-field 的 outlined 框会和
/// 外层圆角台套成「框中框」，所以输入区不画任何边框，只留底色。
/// 库文件和 Material Icons 字体**跟着 App 打包**，由 `/assets/*` 提供 ——
/// 所以页面离线也能用，不去 CDN 拉。
///
/// 骨架：侧栏移植 NaviFlash 的 CollapsibleSideBar（展开 224 ⇄ 折叠 80 图标栏，
/// 宽度带动画；顶部 menu ⇄ menu_open 圆钮、方形「+」新建对话、导航项空心/实心
/// 随选中切换）+ 中部消息流 + 底部圆角输入台。配色一律走 mdui 的主题 token
/// （`rgb(var(--mdui-color-*))`），深浅色自动跟随。
const String kWebUiHtml = r'''<!DOCTYPE html>
<html lang="zh-CN" class="mdui-theme-auto">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>local2api · 临时控制台</title>
<link rel="stylesheet" href="/assets/mdui.css">
<style>
  /* Material Icons 字体（本地打包，离线可用） */
  @font-face {
    font-family: 'Material Icons';
    font-style: normal;
    font-weight: 400;
    font-display: block;
    src: url('/assets/material-icons.woff2') format('woff2');
  }
  .material-icons {
    font-family: 'Material Icons';
    font-weight: normal; font-style: normal;
    font-size: 24px; line-height: 1;
    letter-spacing: normal; text-transform: none;
    display: inline-block; white-space: nowrap; word-wrap: normal;
    direction: ltr; -webkit-font-feature-settings: 'liga'; font-feature-settings: 'liga';
  }

  * , *::before, *::after { box-sizing: border-box; }
  html, body { height: 100%; margin: 0; }
  body {
    display: flex; overflow: hidden;
    /* 画布色 = 侧栏底色：内容卡片四周的空隙露出它 —— 对齐 App 的
       SideBarShell（侧栏与内容卡片之间不画分隔线，靠空隙分界） */
    background: rgb(var(--mdui-color-surface-container-low));
    color: rgb(var(--mdui-color-on-surface));
    font-family: Roboto, "PingFang SC", "Microsoft YaHei", system-ui, sans-serif;
  }
  .spacer { flex: 1; }

  /* ================= 侧栏：展开 224 ⇄ 折叠 80（宽度带动画） =================
     骨架照 NaviFlash 的 CollapsibleSideBar 搬：顶部 menu 圆钮（menu ⇄ menu_open，
     两种状态同位不跳）→ 方形「+」新建对话（展开长成「新对话」胶囊）→ 导航项
     （空心/实心随选中切）→ 会话列表（折叠时整块隐去）。 */
  /* 侧栏不画自己的边框：与内容卡片之间靠空隙分界（App 同款） */
  #side {
    width: 224px; flex: 0 0 224px;
    background: rgb(var(--mdui-color-surface-container-low));
    display: flex; flex-direction: column;
    overflow: hidden;
    transition: width .26s cubic-bezier(.645,.045,.355,1),
                flex-basis .26s cubic-bezier(.645,.045,.355,1);
  }
  #side.rail { width: 80px; flex-basis: 80px; }
  /* 折叠时别让子项的 min-width 把栏撑宽 */
  #side > * { min-width: 0; }

  /* 顶部：menu 圆钮（左 18 / 上 8，收起展开都在同一列） */
  .side-top { display: flex; align-items: center; gap: 4px;
    padding: 8px 12px 0 18px; height: 60px; flex: none; }
  .side-icon-btn {
    width: 44px; height: 44px; border-radius: 50%; flex: none; padding: 0;
    display: flex; align-items: center; justify-content: center;
    background: transparent; border: none; cursor: pointer;
    color: rgb(var(--mdui-color-on-surface-variant));
  }
  .side-icon-btn:hover { background: rgb(var(--mdui-color-surface-container-high)); }
  .side-icon-btn .material-icons { font-size: 22px; }

  .side-brand {
    font-size: 15px; font-weight: 600; white-space: nowrap; overflow: hidden;
    max-width: 140px; opacity: 1; color: rgb(var(--mdui-color-on-surface));
    transition: max-width .26s cubic-bezier(.645,.045,.355,1), opacity .14s ease;
  }
  #side.rail .side-brand { max-width: 0; opacity: 0; }

  /* 新建对话：收起 = 56×56 方圆块（图标中心 x=40）；展开 = 全宽胶囊 + 「新对话」。
     两种状态图标都钉在同一列（左 12 + 内边距 15），宽度动画只向右长。 */
  #btnNew {
    flex: none; margin: 4px 12px 12px;
    width: 56px; height: 56px; border-radius: 18px; padding: 0 15px;
    display: flex; align-items: center; justify-content: flex-start; gap: 12px;
    background: rgb(var(--mdui-color-primary-container));
    color: rgb(var(--mdui-color-on-primary-container));
    border: none; cursor: pointer; overflow: hidden; white-space: nowrap;
    transition: width .26s cubic-bezier(.645,.045,.355,1),
                border-radius .26s cubic-bezier(.645,.045,.355,1);
  }
  /* 折叠只裁窄容器：padding 恒定 -> 图标 x 恒 40，不随动画漂移 */
  #side:not(.rail) #btnNew { width: calc(100% - 24px); border-radius: 16px; }
  #btnNew .material-icons { font-size: 26px; }
  #btnNew .lbl { font-size: 16px; font-weight: 600; line-height: 1; letter-spacing: .2px; }

  /* 折叠时收掉文字：宽度 + 透明度一起过渡，别用 display:none（没动画） */
  .lbl {
    white-space: nowrap; overflow: hidden; max-width: 200px; opacity: 1;
    transition: max-width .26s cubic-bezier(.645,.045,.355,1), opacity .14s ease;
  }
  #side.rail .lbl { max-width: 0; opacity: 0; }

  /* 导航项：展开 = 胶囊（图标 + 文字）；收起 = 56 宽居中图标块 */
  .side-nav { display: flex; flex-direction: column; gap: 4px;
    padding: 2px 12px; flex: none; }
  .side-item {
    display: flex; align-items: center; gap: 16px; height: 48px;
    padding: 0 16px; border-radius: 24px; border: none; cursor: pointer;
    background: transparent; text-align: left;
    color: rgb(var(--mdui-color-on-surface-variant));
    font-size: 14px; font-weight: 500; white-space: nowrap;
    transition: background-color .18s ease, color .18s ease,
                gap .26s cubic-bezier(.645,.045,.355,1),
                padding .26s cubic-bezier(.645,.045,.355,1),
                border-radius .26s cubic-bezier(.645,.045,.355,1);
  }
  .side-item:hover { background: rgb(var(--mdui-color-surface-container-high)); }
  .side-item.active {
    background: rgb(var(--mdui-color-primary-container));
    color: rgb(var(--mdui-color-on-primary-container));
    font-weight: 600;
  }
  .side-item { position: relative; }
  .side-item .material-icons { font-size: 24px; flex: none; }
  /* 折叠 = 图标在上、文字在下的竖排（对齐 App 竖向导航栏）：
     选中项胶囊只包图标（::before 画胶囊，图标 x 恒 40 不漂移），
     文字只给当前导航项露出来。 */
  #side.rail .side-item {
    flex-direction: column; gap: 2px;
    width: 56px; height: auto; padding: 4px 6px 2px;
    border-radius: 0; background: transparent;
  }
  #side.rail .side-item::before {
    content: ''; position: absolute; left: 6px; top: 4px;
    width: 44px; height: 32px; border-radius: 16px;
    background: transparent; transition: background-color .18s ease;
  }
  #side.rail .side-item:hover { background: transparent; }
  #side.rail .side-item:hover::before {
    background: rgb(var(--mdui-color-surface-container-high));
  }
  #side.rail .side-item.active { background: transparent; }
  #side.rail .side-item.active::before {
    background: rgb(var(--mdui-color-primary-container));
  }
  #side.rail .side-item .material-icons {
    position: relative; z-index: 1;
    width: 44px; height: 32px; line-height: 32px; text-align: center;
  }
  #side.rail .side-item .lbl {
    max-width: none; max-height: 0; opacity: 0;
    font-size: 11px; font-weight: 600; line-height: 1.2;
    transition: max-height .18s ease, opacity .18s ease;
  }
  #side.rail .side-item.active .lbl {
    max-height: 14px; opacity: 1;
    color: rgb(var(--mdui-color-on-surface));
  }

  #side mdui-divider { margin: 6px 14px; transition: opacity .14s ease; }
  #side.rail mdui-divider { opacity: 0; }

  .side-conv {
    flex: 1; overflow: auto; display: flex; flex-direction: column; gap: 1px;
    padding: 2px 8px; transition: opacity .14s ease;
  }
  #side.rail .side-conv { opacity: 0; visibility: hidden; }
  .side-conv mdui-list-item { --shape-corner: 12px; }


  /* ================= 主区 ================= */
  /* 内容区是圆角卡片（24px）：四周留空隙露出画布色，形成外向圆角 ——
     与 App 的 SideBarShell（fromLTRB(12, 8, 8, 8) + ClipRRect(24)）同一手法 */
  #main { flex: 1; display: flex; flex-direction: column; min-width: 0;
    padding: 8px 8px 8px 12px; }
  .shell-card {
    flex: 1; min-width: 0; min-height: 0;
    display: flex; flex-direction: column;
    background: rgb(var(--mdui-color-surface-container));
    border-radius: 24px;
    overflow: hidden;
  }

  mdui-top-app-bar {
    position: static;
    --shape-corner: 0;
    /* 去掉顶栏底色：和内容卡片融为一体，只留一条分隔细线
       （页面样式能盖过组件 :host 的 surface-container 背景） */
    background: transparent;
    box-shadow: none;
    border-bottom: 1px solid rgb(var(--mdui-color-outline-variant));
  }
  mdui-top-app-bar[scrolling] { background: transparent; box-shadow: none; }
  mdui-top-app-bar-title { font-weight: 600; }

  /* 模型选择器：按钮 + 带搜索的弹出菜单 */
  .menu-search { padding: 8px 8px 4px; min-width: 260px; }
  .menu-search mdui-text-field { width: 100%; }
  #modelMenu { max-height: 52vh; overflow: auto; }
  .model-empty {
    padding: 18px 14px; font-size: 13px; text-align: center;
    color: rgb(var(--mdui-color-on-surface-variant));
  }

  /* 连接设置（默认收起） */
  #settingsPanel {
    display: flex; flex-direction: column; gap: 10px;
    padding: 14px 20px 16px;
    background: rgb(var(--mdui-color-surface-container-low));
    border-bottom: 1px solid rgb(var(--mdui-color-outline-variant));
  }
  #settingsPanel[hidden] { display: none; }
  #settingsPanel .row { display: flex; gap: 12px; flex-wrap: wrap; }
  #settingsPanel mdui-text-field { flex: 1; min-width: 220px; }

  /* ================= 视图 ================= */
  .view { flex: 1; display: flex; flex-direction: column; min-height: 0; }
  .view[hidden] { display: none; }

  /* 消息流 */
  #stream { flex: 1; overflow: auto; padding: 24px 20px 8px; }
  /* 新对话空态：和 Qwen 一样 —— 一句问候 + 输入台整体居中 */
  #viewChat.chat-empty #stream { display: none; }
  #viewChat.chat-empty .composer-wrap {
    flex: 1; display: flex; flex-direction: column; justify-content: center;
    padding-bottom: 10vh;
  }
  .hero { margin: 0 0 22px; text-align: center;
    font-size: 24px; font-weight: 600;
    color: rgb(var(--mdui-color-on-surface)); }
  .hero[hidden] { display: none; }
  /* 发送键 / 语音键二选一 */
  .hide { display: none !important; }
  /* 消息 = 头像 + 对话气泡（对齐 App「对话模拟」：助手/系统/用户三色头像，
     角色名在气泡内，用户消息靠右） */
  .msg { display: flex; align-items: flex-start; gap: 10px;
    max-width: 860px; margin: 0 auto 14px; }
  .msg.me { flex-direction: row-reverse; }
  .mavatar {
    flex: none; width: 32px; height: 32px; border-radius: 50%;
    display: flex; align-items: center; justify-content: center; color: #fff;
  }
  .mavatar .material-icons { font-size: 18px; }
  .bubble {
    flex: 0 1 auto; max-width: min(640px, calc(100% - 42px));
    background: rgb(var(--mdui-color-surface-container-highest));
    border-radius: 14px; padding: 10px 14px 8px;
    word-break: break-word; line-height: 1.65;
  }
  .bubble .role {
    font-size: 11px; font-weight: 700; letter-spacing: .04em;
    color: rgb(var(--mdui-color-on-surface-variant)); margin-bottom: 4px;
  }
  .bubble .mtext { white-space: pre-wrap; }
  /* 消息里的图片：随消息发给模型的那份（点一下开原图） */
  .bubble .imgs { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 6px; }
  .bubble .imgs img {
    max-width: 220px; max-height: 180px; display: block;
    border-radius: 12px; cursor: zoom-in;
  }
  .bubble .mfoot {
    display: flex; align-items: center; gap: 4px; margin-top: 6px;
    font-size: 11px;
    font-family: ui-monospace, "Cascadia Mono", Consolas, monospace;
    color: rgb(var(--mdui-color-on-surface-variant));
  }
  .bubble .mfoot .material-icons { font-size: 12px; }
  .bubble.err { background: rgb(var(--mdui-color-error-container));
    color: rgb(var(--mdui-color-on-error-container)); }
  .caret {
    display: inline-block; width: 7px; height: 15px; vertical-align: -2px;
    margin-left: 2px; background: rgb(var(--mdui-color-primary));
    animation: blink 1s steps(2) infinite;
  }
  @keyframes blink { 50% { opacity: 0; } }

  /* 输入台：整块只有一层底色，Qwen 式单行 —— 占用环 / 加号 / 输入区 /
     角色 / 语音（发送）全在一行，输入长了往上长。 */
  .composer-wrap { padding: 6px 20px 16px; }
  .composer {
    width: 100%; max-width: 860px; margin: 0 auto;
    background: rgb(var(--mdui-color-surface-container-low));
    border-radius: 24px; padding: 6px 8px 6px 4px;
  }
  .composer-row { display: flex; align-items: flex-end; gap: 2px; }
  .composer textarea {
    display: block; flex: 1; min-width: 0; box-sizing: border-box;
    border: none; outline: none; background: transparent;
    resize: none; overflow-y: auto; max-height: 160px;
    font: inherit; font-size: 15px; line-height: 1.55;
    padding: 10px 6px;
    color: rgb(var(--mdui-color-on-surface));
  }
  .composer textarea::placeholder {
    color: rgb(var(--mdui-color-on-surface-variant));
  }
  /* 待发图片：缩略图 + 右上角 × */
  .pending { display: flex; flex-wrap: wrap; gap: 10px; padding: 8px 10px 4px; }
  .pending[hidden] { display: none; }
  .pending .thumb { position: relative; }
  .pending .thumb img {
    width: 58px; height: 58px; object-fit: cover; display: block;
    border-radius: 12px;
  }
  .pending .thumb button {
    position: absolute; top: -6px; right: -6px; width: 20px; height: 20px;
    border: none; border-radius: 50%; cursor: pointer; padding: 0;
    background: rgb(var(--mdui-color-error));
    color: rgb(var(--mdui-color-on-error));
    font-size: 14px; line-height: 1;
    display: flex; align-items: center; justify-content: center;
  }
  /* 上下文占用环（对齐 opencode 的 ProgressCircle：16px 双圆、
     -90° 起笔、进度弧带缓动；≥90% 换 error 色提醒快满）。
     数字多，悬停 title 看不清 —— 改成点开弹层。 */
  .ctx-wrap { position: relative; flex: none; }
  .ctx {
    display: flex; align-items: center; flex: none;
    padding: 8px 8px 9px; border: none; border-radius: 999px;
    background: transparent; color: inherit; font: inherit; cursor: pointer;
  }
  .ctx:hover { background: rgb(var(--mdui-color-surface-container-high)); }
  .ctx-ring { transform: rotate(-90deg); }
  .ctx-bg { stroke: rgb(var(--mdui-color-outline-variant)); }
  .ctx-fg {
    stroke: rgb(var(--mdui-color-primary));
    transition: stroke-dashoffset .35s cubic-bezier(.65, 0, .35, 1);
  }
  .ctx.hot .ctx-fg { stroke: rgb(var(--mdui-color-error)); }
  .ctx-pop {
    position: absolute; left: 0; bottom: calc(100% + 10px); z-index: 30;
    width: 270px; padding: 14px 16px;
    background: rgb(var(--mdui-color-surface-container-highest));
    color: rgb(var(--mdui-color-on-surface));
    border-radius: 16px;
    box-shadow: 0 6px 24px rgba(0,0,0,.28);
    font-size: 12px; line-height: 1.7;
  }
  .ctx-pop[hidden] { display: none; }
  .ctx-pop .pct { font-size: 24px; font-weight: 700; line-height: 1.2; }
  .ctx-pop.hot .pct { color: rgb(var(--mdui-color-error)); }
  .ctx-pop .bar {
    height: 5px; border-radius: 999px; margin: 8px 0 10px; overflow: hidden;
    background: rgb(var(--mdui-color-surface-container-high));
  }
  .ctx-pop .bar i {
    display: block; height: 100%;
    background: rgb(var(--mdui-color-primary));
    transition: width .35s cubic-bezier(.65, 0, .35, 1);
  }
  .ctx-pop.hot .bar i { background: rgb(var(--mdui-color-error)); }
  .ctx-pop .mut { color: rgb(var(--mdui-color-on-surface-variant)); }
  .ctx-pop .mono {
    font-family: ui-monospace, "Cascadia Mono", Consolas, monospace;
    word-break: break-all;
  }
  /* 拖图片进来时给一层主色描边（松手就没了） */
  .composer.drop { box-shadow: 0 0 0 2px rgb(var(--mdui-color-primary)) inset; }
  /* 正在收音：语音键变红 */
  #btnVoice.listening { color: rgb(var(--mdui-color-error)); }
  /* 点缩略图看原图的全屏遮罩 */
  .lightbox {
    position: fixed; inset: 0; z-index: 80; cursor: zoom-out;
    background: rgba(0,0,0,.72);
    display: flex; align-items: center; justify-content: center;
  }
  .lightbox img { max-width: 92vw; max-height: 92vh; border-radius: 12px; }

  /* ================= 发现：人设卡 ================= */
  .discover-head { padding: 22px 26px 8px; }
  .discover-head h1 { margin: 0 0 6px; font-size: 22px; font-weight: 600; }
  .discover-head p { margin: 0; font-size: 13px; line-height: 1.7;
    color: rgb(var(--mdui-color-on-surface-variant)); }
  .cards {
    flex: 1; overflow: auto; padding: 14px 26px 26px;
    display: grid; gap: 14px; align-content: start;
    grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
  }
  mdui-card { --shape-corner: 20px; display: flex; flex-direction: column; }
  .card-body { padding: 16px; display: flex; flex-direction: column; gap: 10px; flex: 1; }
  .card-body .ctitle { font-size: 16px; font-weight: 600; }
  .card-body .cprompt {
    font-size: 13px; line-height: 1.6;
    color: rgb(var(--mdui-color-on-surface-variant));
    display: -webkit-box; -webkit-line-clamp: 4; -webkit-box-orient: vertical;
    overflow: hidden;
  }
  .card-body .cfoot { display: flex; align-items: center; gap: 8px; margin-top: auto; }
  .empty-cards {
    grid-column: 1 / -1; padding: 26px 2px; font-size: 13px; line-height: 1.8;
    color: rgb(var(--mdui-color-on-surface-variant));
  }
  .cards-head {
    grid-column: 1 / -1; padding: 6px 2px 0; font-size: 13px; font-weight: 700;
    color: rgb(var(--mdui-color-on-surface-variant));
  }
  .ctitle .cbadge {
    margin-left: 8px; padding: 2px 8px; border-radius: 999px;
    font-size: 11px; font-weight: 600; vertical-align: 2px;
    background: rgb(var(--mdui-color-secondary-container));
    color: rgb(var(--mdui-color-on-secondary-container));
  }

  @media (max-width: 720px) {
    #main { padding: 8px; }
    #side { position: fixed; inset: 0 auto 0 0; z-index: 40; height: 100%; }
    /* 打开抽屉时 JS 会强制去掉 rail（完整形态），这里不用再兜 rail */
    #side:not(.open) { width: 0; flex-basis: 0; }
    #btnMenu { display: inline-flex !important; }
  }
</style>
</head>
<body>
<aside id="side">
  <div class="side-top">
    <button class="side-icon-btn" id="btnRail" title="展开侧边栏">
      <span class="material-icons">menu</span>
    </button>
    <span class="side-brand">local2api</span>
  </div>
  <button id="btnNew" title="新建对话">
    <span class="material-icons">add</span><span class="lbl">新对话</span>
  </button>
  <nav class="side-nav">
    <button class="side-item active" id="navChat">
      <span class="material-icons">chat_bubble</span><span class="lbl">对话</span>
    </button>
    <button class="side-item" id="navDiscover">
      <span class="material-icons">travel_explore</span><span class="lbl">发现</span>
    </button>
  </nav>
  <mdui-divider></mdui-divider>
  <div class="side-conv" id="conv"></div>
</aside>

<div id="main">
  <div class="shell-card">
  <mdui-top-app-bar>
    <mdui-button-icon id="btnMenu" icon="menu" style="display:none"></mdui-button-icon>
    <mdui-dropdown placement="bottom-start" id="modelDd">
      <mdui-button slot="trigger" variant="text" end-icon="arrow_drop_down">
        <span id="modelName">选择模型</span>
      </mdui-button>
      <mdui-menu id="modelMenu">
        <div class="menu-search">
          <mdui-text-field id="modelSearch" variant="outlined"
            placeholder="搜索模型" clearable></mdui-text-field>
        </div>
        <div id="modelList"></div>
      </mdui-menu>
    </mdui-dropdown>
    <mdui-top-app-bar-title id="barTitle"></mdui-top-app-bar-title>
    <mdui-chip id="laneTag" variant="suggestion" icon="bolt">—</mdui-chip>
    <div class="spacer"></div>
    <mdui-button-icon id="btnSettings" icon="settings"></mdui-button-icon>
  </mdui-top-app-bar>

  <div id="settingsPanel" hidden>
    <div class="row">
      <mdui-text-field id="base" variant="outlined" label="API 基址"
        helper="默认走本机 WebUI 代理（自动补密钥），要指向别处才改"></mdui-text-field>
      <mdui-text-field id="key" variant="outlined" label="API Key（可选）"
        clearable></mdui-text-field>
    </div>
  </div>

  <section class="view" id="viewChat">
    <div id="stream"></div>
    <div class="composer-wrap">
      <h1 class="hero" id="hero" hidden>有什么可以帮您的吗？</h1>
      <div class="composer">
        <div class="pending" id="pending" hidden></div>
        <div class="composer-row">
          <div class="ctx-wrap">
            <button class="ctx" id="ctxBox" type="button" title="点击查看上下文详情">
              <svg class="ctx-ring" viewBox="0 0 16 16" width="16" height="16" fill="none">
                <circle class="ctx-bg" cx="8" cy="8" r="7" stroke-width="2"></circle>
                <circle class="ctx-fg" id="ctxArc" cx="8" cy="8" r="7" stroke-width="2"
                  stroke-linecap="round" stroke-dasharray="43.9823"
                  stroke-dashoffset="43.9823"></circle>
              </svg>
            </button>
            <div class="ctx-pop" id="ctxPop" hidden></div>
          </div>
          <mdui-button-icon id="btnAttach" icon="add" title="添加图片（可直接 Ctrl+V 粘贴 / 拖进来）"></mdui-button-icon>
          <textarea id="input" rows="1" placeholder="询问 local2api"></textarea>
          <mdui-chip id="roleChip" variant="filter" icon="person" title="用户（点击切换）"></mdui-chip>
          <mdui-button-icon id="btnVoice" variant="filled" title="语音输入">
            <svg viewBox="0 0 1024 1024" width="20" height="20" fill="currentColor" aria-hidden="true">
              <path d="M192 320v384H64V320h128zM448 64v896H320V64h128zM704 256v512H576V256h128zM960 320v384h-128V320h128z"></path>
            </svg>
          </mdui-button-icon>
          <mdui-button-icon id="btnSend" icon="arrow_upward" variant="filled"></mdui-button-icon>
        </div>
        <input type="file" id="filePick" accept="image/*" multiple style="display:none">
      </div>
    </div>
  </section>

  <section class="view" id="viewDiscover" hidden>
    <div class="discover-head">
      <h1>发现 · 人设卡</h1>
      <p>预制角色卡和 App 里自建的人设卡都在这儿（本页只读，改不了）。点「应用」会把当前对话换成这张卡的场景：人设提示词 + 预制问答。</p>
    </div>
    <div class="cards" id="cards"></div>
  </section>
  </div>
</div>

<mdui-snackbar id="snack" placement="top"></mdui-snackbar>

<script src="/assets/mdui.global.js"></script>
<script>
const $ = (id) => document.getElementById(id);
const store = {
  get(k, d) { try { return localStorage.getItem('l2a.' + k) ?? d; } catch (_) { return d; } },
  set(k, v) { try { localStorage.setItem('l2a.' + k, v); } catch (_) {} }
};
let convs = [], cur = 0;
let models = [];              // 可选模型名
let model = '';               // 当前选中
let modelMeta = {};           // 对外声明的元数据（context_length / max_output_tokens）
let defaultModels = [];       // 配置里的对外模型（bootstrap 给的兜底列表）
let characters = [];          // 发现页的人设卡（App 里自建的，只读）
let inputRole = 'user';       // 这条消息以什么角色发
let pendingImgs = [];         // 待发图片（data URL），随下一条消息一起发出去
let view = 'chat';
const ROLES = ['user', 'assistant', 'system'];
const ROLE_LABEL = { user: '用户', assistant: '助手', system: '系统' };
const ROLE_ICON = { user: 'person', assistant: 'smart_toy', system: 'settings_suggest' };
/* 气泡头像：与 App「对话模拟」同款 —— 系统=齿轮(橙)、用户=人(灰)、助手=机器人(蓝) */
const ROLE_AVATAR = {
  system: { icon: 'settings', tint: '#F07C1E' },
  user: { icon: 'person', tint: '#9E9E9E' },
  assistant: { icon: 'smart_toy', tint: '#2F7FE0' },
};

function toast(msg) {
  const sb = $('snack');
  sb.textContent = msg;
  sb.open = true;
}

/* ---------- 会话 ---------- */
function newConv() {
  convs.push({ title: '新对话 ' + (convs.length + 1), msgs: [] });
  cur = convs.length - 1;
  render();
}
function renderConvList() {
  const box = $('conv');
  box.innerHTML = '';
  convs.forEach((c, i) => {
    const it = document.createElement('mdui-list-item');
    it.setAttribute('rounded', '');
    it.textContent = c.title;
    if (i === cur) it.setAttribute('active', '');
    it.addEventListener('click', () => { cur = i; render(); });
    box.appendChild(it);
  });
}
function render() {
  renderConvList();
  const c = convs[cur];
  const box = $('stream');
  // 空对话 = Qwen 式居中输入台（一句问候），有消息才铺消息流
  const empty = !c || c.msgs.length === 0;
  $('viewChat').classList.toggle('chat-empty', empty);
  $('hero').hidden = !empty;
  box.innerHTML = '';
  if (empty) return;
  for (const m of c.msgs) {
    const av = ROLE_AVATAR[m.role] || ROLE_AVATAR.assistant;
    const wrap = document.createElement('div');
    wrap.className = 'msg' + (m.role === 'user' ? ' me' : '');
    const avatar = document.createElement('div');
    avatar.className = 'mavatar';
    avatar.style.background = av.tint;
    avatar.insertAdjacentHTML('afterbegin',
      '<span class="material-icons">' + av.icon + '</span>');
    const bubble = document.createElement('div');
    bubble.className = 'bubble' + (m.error ? ' err' : '');
    const role = document.createElement('div');
    role.className = 'role';
    role.textContent = ROLE_LABEL[m.role] || m.role;
    const text = document.createElement('div');
    text.className = 'mtext';
    text.textContent = m.content;
    if (m.streaming) text.insertAdjacentHTML('beforeend', '<span class="caret"></span>');
    bubble.appendChild(role);
    // 图片：随这条消息发给模型的那份，点开看原图
    if (m.images && m.images.length) {
      const imgs = document.createElement('div');
      imgs.className = 'imgs';
      for (const url of m.images) {
        const im = document.createElement('img');
        im.alt = '';
        im.src = url;
        im.addEventListener('click', () => openLightbox(url));
        imgs.appendChild(im);
      }
      bubble.appendChild(imgs);
    }
    bubble.appendChild(text);
    if (m.role === 'assistant' && m.lane) {
      const foot = document.createElement('div');
      foot.className = 'mfoot';
      foot.insertAdjacentHTML('afterbegin', '<span class="material-icons">memory</span>');
      foot.appendChild(document.createTextNode(m.lane));
      bubble.appendChild(foot);
    }
    wrap.appendChild(avatar);
    wrap.appendChild(bubble);
    box.appendChild(wrap);
  }
  box.scrollTop = box.scrollHeight;
  updateCtxRing();
}
function push(role, content, lane, error, images) {
  if (!convs[cur]) newConv();
  const c = convs[cur];
  c.msgs.push({
    role, content, lane, error: !!error, streaming: false,
    images: images || [],
  });
  if (role === 'user' && c.msgs.length === 1) {
    c.title = (content || (images && images.length ? '（图片）' : '')).slice(0, 24);
  }
  render();
}

/* ---------- 图片 ---------- */
/* 点开缩略图看原图（点任意处关闭） */
function openLightbox(url) {
  const box = document.createElement('div');
  box.className = 'lightbox';
  const im = document.createElement('img');
  im.alt = '';
  im.src = url;
  box.appendChild(im);
  box.addEventListener('click', () => box.remove());
  document.body.appendChild(box);
}
/* 待发图片条：缩略图 + × 移除 */
function renderPending() {
  const box = $('pending');
  box.innerHTML = '';
  box.hidden = pendingImgs.length === 0;
  pendingImgs.forEach((url, i) => {
    const t = document.createElement('div');
    t.className = 'thumb';
    const im = document.createElement('img');
    im.alt = '';
    im.src = url;
    const x = document.createElement('button');
    x.type = 'button';
    x.textContent = '×';
    x.title = '移除这张图';
    x.addEventListener('click', () => {
      pendingImgs.splice(i, 1);
      renderPending();
      syncSendBtn();
    });
    t.appendChild(im);
    t.appendChild(x);
    box.appendChild(t);
  });
  syncSendBtn();
}
/* 图片压到 ≤1024px 再转 data URL：原图动辄几 MB，base64 后进请求体
   既慢又容易被上游按体积拒掉；视觉模型本来也只看得到 ~1024px。 */
function addImageFiles(files) {
  const list = Array.from(files || []).filter((f) => f.type.startsWith('image/'));
  if (!list.length) return;
  let left = list.length;
  for (const f of list) {
    const reader = new FileReader();
    reader.onload = async () => {
      try {
        pendingImgs.push(await shrinkDataUrl(String(reader.result), f.type));
      } catch (_) {
        // 解码失败（HEIC 之类浏览器不认的格式）：原样带上，让上游去判
        pendingImgs.push(String(reader.result));
      }
      if (--left === 0) renderPending();
    };
    reader.onerror = () => { if (--left === 0) renderPending(); };
    reader.readAsDataURL(f);
  }
}
async function shrinkDataUrl(dataUrl, type) {
  if (type === 'image/gif' || type === 'image/svg+xml') return dataUrl;
  const img = await createImageBitmap(await (await fetch(dataUrl)).blob()).catch(() => null);
  if (!img) return dataUrl;
  const scale = Math.min(1, 1024 / Math.max(img.width, img.height));
  const w = Math.max(1, Math.round(img.width * scale));
  const h = Math.max(1, Math.round(img.height * scale));
  const cv = document.createElement('canvas');
  cv.width = w; cv.height = h;
  cv.getContext('2d').drawImage(img, 0, 0, w, h);
  img.close && img.close();
  return cv.toDataURL('image/jpeg', 0.85);
}

/* ---------- 模型选择器 ---------- */
function setModel(id) {
  model = id || '';
  store.set('model', model);
  $('modelName').textContent = model || '选择模型';
  renderModelList();
  updateCtxRing();
}
function renderModelList() {
  const q = ($('modelSearch').value || '').trim().toLowerCase();
  const box = $('modelList');
  box.innerHTML = '';
  const shown = models.filter((m) => !q || m.toLowerCase().includes(q));
  if (!shown.length) {
    const tip = document.createElement('div');
    tip.className = 'model-empty';
    tip.textContent = models.length
      ? '没有匹配的模型'
      : '还没有可用的对外模型，先去 App 里启用几个';
    box.appendChild(tip);
    return;
  }
  for (const m of shown) {
    const it = document.createElement('mdui-menu-item');
    it.setAttribute('value', m);
    it.textContent = m;
    if (m === model) it.setAttribute('selected', '');
    it.addEventListener('click', () => {
      setModel(m);
      $('modelDd').open = false;
    });
    box.appendChild(it);
  }
}
function applyModels(ids) {
  models = ids.slice();
  if (!models.includes(model)) model = models[0] || '';
  setModel(model);
}

/* ---------- 模型清单 ---------- */
async function loadModels() {
  const base = $('base').value.trim() || '/v1';
  const key = $('key').value.trim();
  try {
    const res = await fetch(base + '/models', { headers: key ? { Authorization: 'Bearer ' + key } : {} });
    const txt = await res.text();
    if (!res.ok) throw new Error(txt.slice(0, 200));
    const data = JSON.parse(txt);
    const ids = (data.data || []).map((m) => m.id);
    // 顺手记下每个模型对外声明的上下文 / 输出上限（占用环的分母）
    modelMeta = {};
    for (const m of (data.data || [])) {
      if (m && m.id) {
        modelMeta[m.id] = { ctx: m.context_length || 0, out: m.max_output_tokens || 0 };
      }
    }
    applyModels(ids.length ? ids : defaultModels);
  } catch (_) {
    // 转发口没开 / 出错时，退回配置里的对外模型，页面照样能用
    applyModels(defaultModels);
  }
}
async function bootstrap() {
  try {
    const res = await fetch('/api/bootstrap');
    const j = await res.json();
    defaultModels = j.models || [];
    $('base').value = store.get('base', j.base || '/v1');
  } catch (_) {
    $('base').value = store.get('base', '/v1');
  }
  $('key').value = store.get('key', '');
  await loadModels();
  await loadCharacters();
}

/* ---------- 发现：人设卡（只读） ---------- */
async function loadCharacters() {
  try {
    const res = await fetch('/api/characters');
    const j = await res.json();
    characters = j.characters || [];
  } catch (_) {
    characters = [];
  }
  renderCards();
}
function renderCards() {
  const box = $('cards');
  box.innerHTML = '';
  if (!characters.length) {
    const tip = document.createElement('div');
    tip.className = 'empty-cards';
    tip.textContent = '还没有人设卡。到 App 的「对话模拟 → 人设卡」里建一张，这里就能选（本页只读）。';
    box.appendChild(tip);
    return;
  }
  const builtins = characters.filter((c) => c.builtin);
  const mine = characters.filter((c) => !c.builtin);
  // 两类都有时给个小标题分开；只有一类就裸排，不摆多余的分组头。
  const both = builtins.length > 0 && mine.length > 0;
  if (builtins.length) {
    if (both) box.appendChild(cardHead('预制角色'));
    for (const c of builtins) box.appendChild(buildCard(c));
  }
  if (mine.length) {
    if (both) box.appendChild(cardHead('我的角色'));
    for (const c of mine) box.appendChild(buildCard(c));
  }
}
function cardHead(title) {
  const h = document.createElement('div');
  h.className = 'cards-head';
  h.textContent = title;
  return h;
}
function buildCard(c) {
  const card = document.createElement('mdui-card');
  card.setAttribute('variant', 'filled');
  const body = document.createElement('div');
  body.className = 'card-body';
  const t = document.createElement('div');
  t.className = 'ctitle';
  t.textContent = c.name || '未命名';
  if (c.builtin) {
    const badge = document.createElement('span');
    badge.className = 'cbadge';
    badge.textContent = '预制';
    t.appendChild(badge);
  }
  const p = document.createElement('div');
  p.className = 'cprompt';
  p.textContent = c.prompt || '';
  const foot = document.createElement('div');
  foot.className = 'cfoot';
  const chip = document.createElement('mdui-chip');
  chip.setAttribute('variant', 'assist');
  chip.setAttribute('icon', 'forum');
  chip.textContent = (c.presets || []).length + ' 条预制问答';
  const btn = document.createElement('mdui-button');
  btn.setAttribute('variant', 'filled');
  btn.textContent = '应用';
  btn.addEventListener('click', () => applyCharacter(c));
  foot.appendChild(chip);
  foot.appendChild(btn);
  body.appendChild(t);
  body.appendChild(p);
  body.appendChild(foot);
  card.appendChild(body);
  return card;
}
// 把当前对话换成这张卡的场景（与 App 的「对话模拟 → 应用人设」同一套语义）。
function applyCharacter(c) {
  if (!convs[cur]) newConv();
  const conv = convs[cur];
  if (conv.msgs.length && !confirm('把当前对话替换成「' + (c.name || '未命名') + '」的场景？')) return;
  conv.msgs = [];
  conv.character = { id: c.id, name: c.name };
  conv.title = c.name || conv.title;
  conv.msgs.push({ role: 'system', content: c.prompt || '' });
  for (const pair of (c.presets || [])) {
    conv.msgs.push({ role: 'user', content: pair.user || '' });
    conv.msgs.push({ role: 'assistant', content: pair.assistant || '' });
  }
  setView('chat');
  render();
  toast('已应用人设：' + (c.name || '未命名'));
}

/* ---------- 视图 / 侧栏 ---------- */
/* 导航项：选中 = 实心图标 + 胶囊，未选中 = 空心图标（与 NaviFlash 侧栏一致） */
function setNavState(el, active, filled, outlined) {
  el.classList.toggle('active', active);
  const icon = el.querySelector('.material-icons');
  if (icon) icon.textContent = active ? filled : outlined;
}
function setView(v) {
  view = v;
  $('viewChat').hidden = v !== 'chat';
  $('viewDiscover').hidden = v !== 'discover';
  $('modelDd').style.display = v === 'chat' ? '' : 'none';
  $('laneTag').style.display = v === 'chat' ? '' : 'none';
  $('barTitle').textContent = v === 'discover' ? '发现' : '';
  setNavState($('navChat'), v === 'chat', 'chat_bubble', 'chat_bubble_outline');
  setNavState($('navDiscover'), v === 'discover', 'explore', 'travel_explore');
  if (v === 'discover') loadCharacters();
}
function setRail(on, persist) {
  $('side').classList.toggle('rail', on);
  // menu ⇄ menu_open：收起显示汉堡（点开），展开显示展开杠（点收）
  const icon = $('btnRail').querySelector('.material-icons');
  if (icon) icon.textContent = on ? 'menu' : 'menu_open';
  $('btnRail').title = on ? '展开侧边栏' : '收起侧边栏';
  if (persist !== false) store.set('rail', on ? '1' : '0');
}
function toggleMobileSide() {
  const side = $('side');
  const open = !side.classList.contains('open');
  side.classList.toggle('open', open);
  // 手机抽屉打开时强制完整形态（收缩偏好只管桌面那一栏小图标）；
  // 关抽屉后恢复偏好，都不写 localStorage。
  setRail(open ? false : store.get('rail', '0') === '1', false);
}

/* ---------- 上下文占用环 ---------- */
// 粗估 token：opencode 的 chars/4 思路，CJK 按 ~0.6 token/字折算，
// 不然中文会被低估到没法看。只在拿不到上游 usage 时兜底。
function estimateTokens(text) {
  if (!text) return 0;
  let cjk = 0;
  for (const ch of text) {
    const code = ch.codePointAt(0);
    if ((code >= 0x3400 && code <= 0x9fff) || (code >= 0xf900 && code <= 0xfaff) ||
        (code >= 0x3040 && code <= 0x30ff) || (code >= 0xff00 && code <= 0xffef)) cjk++;
  }
  return Math.ceil(cjk * 0.6 + (text.length - cjk) / 4);
}
// 一张 ≤1024px 的图粗略按 600 token 计（各家差异很大，只是别让带图对话
// 看起来跟纯文字一样轻）。与 App 侧 kImageTokenEstimate 同一个数。
const IMG_TOKENS = 600;
// 当前对话的占用：精确值 = 上一轮带 usage 的助手回答（prompt+completion
// 正好是下一轮请求要带的总量，对齐 opencode 的 getSessionContext）；
// 没有就按字数 + 图片张数粗估。
function convTokens() {
  const c = convs[cur];
  if (!c) return { total: 0, estimated: true };
  for (let i = c.msgs.length - 1; i >= 0; i--) {
    const m = c.msgs[i];
    if (m.role === 'assistant' && m.usage > 0) return { total: m.usage, estimated: false };
  }
  let sum = 0;
  for (const m of c.msgs) {
    if (m.error) continue;
    sum += estimateTokens(m.content);
    if (m.images) sum += m.images.length * IMG_TOKENS;
  }
  return { total: sum, estimated: true };
}
// 占用环与详情弹层共用这一组数字（弹层是点开时才渲染的）。
let ctxInfo = { pct: 0, label: '0', total: 0, limit: 1000000, estimated: true, out: 0, imgs: 0, msgs: 0 };
function updateCtxRing() {
  const meta = modelMeta[model] || {};
  const limit = meta.ctx > 0 ? meta.ctx : 1000000;
  const { total, estimated } = convTokens();
  const pct = Math.max(0, Math.min(100, total / limit * 100));
  const C = 43.9823;
  $('ctxArc').style.strokeDashoffset = (C * (1 - pct / 100)).toFixed(2);
  // 环上不再挂数字（细节点开弹层看）；<1% 的一位小数留给弹层用
  const label = pct < 1 && total > 0 ? pct.toFixed(1) : String(Math.round(pct));
  $('ctxBox').classList.toggle('hot', pct >= 90);
  const c = convs[cur] || { msgs: [] };
  let imgs = 0;
  for (const m of c.msgs) if (!m.error && m.images) imgs += m.images.length;
  ctxInfo = {
    pct, label, total, limit, estimated,
    out: meta.out || 0,
    imgs,
    msgs: c.msgs.filter((m) => !m.error).length,
  };
  if (!$('ctxPop').hidden) renderCtxPop();
}
/* 点开占用环才出现的详情弹层（悬停 tooltip 看不清这堆数字） */
function renderCtxPop() {
  const i = ctxInfo;
  const pop = $('ctxPop');
  const wasHot = pop.classList.contains('hot');
  pop.innerHTML = '';
  const pct = document.createElement('div');
  pct.className = 'pct';
  pct.textContent = i.label + '%';
  const bar = document.createElement('div');
  bar.className = 'bar';
  const fill = document.createElement('i');
  fill.style.width = Math.min(100, i.pct) + '%';
  bar.appendChild(fill);
  pop.appendChild(pct);
  pop.appendChild(bar);
  const line = (text, muted, mono) => {
    const d = document.createElement('div');
    if (muted) d.className = 'mut';
    if (mono) d.className = 'mono';
    d.textContent = text;
    pop.appendChild(d);
  };
  line(i.total.toLocaleString() + ' / ' + i.limit.toLocaleString() + ' tokens', false);
  line(i.estimated ? '按字数与图片粗估（上游没回 usage）' : '取自上一轮响应的 usage（精确值）', true);
  line(i.out > 0 ? '最大输出 ' + i.out.toLocaleString() + ' tokens' : '最大输出未声明', true);
  line('请求模型 ' + (model || '未选'), false, true);
  line(i.msgs + ' 条消息 · ' + i.imgs + ' 张图片', true);
  pop.classList.toggle('hot', wasHot || i.pct >= 90);
}
function toggleCtxPop(show) {
  const pop = $('ctxPop');
  const next = show === undefined ? pop.hidden : show;
  pop.hidden = !next;
  if (next) renderCtxPop();
}

/* ---------- 发送 ---------- */
/* 请求体里的一条：没图（或关了「带图」）时 content 仍是字符串，纯文本车道
   照收；有图换成 OpenAI 多模态 parts（text 段 + 每图一个 image_url）。 */
function wireMsg(m) {
  const urls = (m.images || [])
      .filter((u) => u && (u.startsWith('data:') || u.startsWith('http')));
  if (!urls.length) return { role: m.role, content: m.content };
  const parts = [];
  if (m.content) parts.push({ type: 'text', text: m.content });
  for (const u of urls) parts.push({ type: 'image_url', image_url: { url: u } });
  return { role: m.role, content: parts };
}
/* 这条要不要进请求体：有文字，或有图片 */
function sendable(m) {
  if (m.error) return false;
  return !!m.content || !!(m.images && m.images.length);
}
function autosizeInput() {
  const el = $('input');
  el.style.height = 'auto';
  el.style.height = Math.min(el.scrollHeight, 200) + 'px';
}
async function send() {
  const text = ($('input').value || '').trim();
  const imgs = pendingImgs.slice();
  if (!text && !imgs.length) return;
  if (!model) { toast('先选一个模型'); $('modelDd').open = true; return; }
  const base = $('base').value.trim() || '/v1';
  const key = $('key').value.trim();
  $('input').value = '';
  autosizeInput();
  pendingImgs = [];
  renderPending();
  syncSendBtn();
  push(inputRole, text, null, false, imgs);
  $('btnSend').disabled = true;
  try {
    const msgs = convs[cur].msgs.filter(sendable).map(wireMsg);
    const res = await fetch(base + '/chat/completions', {
      method: 'POST',
      headers: Object.assign({ 'Content-Type': 'application/json' }, key ? { Authorization: 'Bearer ' + key } : {}),
      body: JSON.stringify({ model, messages: msgs, stream: true })
    });
    const lane = res.headers.get('x-local2api-lane');
    $('laneTag').textContent = lane || '—';
    if (!res.ok) {
      const t = await res.text();
      push('assistant', 'HTTP ' + res.status + '\n' + t.slice(0, 400), lane, true);
      return;
    }
    const idx = convs[cur].msgs.length;
    push('assistant', '', lane);
    convs[cur].msgs[idx].streaming = true;
    render();
    const reader = res.body.getReader();
    const dec = new TextDecoder();
    let buf = '';
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buf += dec.decode(value, { stream: true });
      const lines = buf.split('\n');
      buf = lines.pop();
      for (const line of lines) {
        if (!line.startsWith('data:')) continue;
        const payload = line.slice(5).trim();
        if (payload === '[DONE]') continue;
        try {
          const j = JSON.parse(payload);
          // usage 在最后一个 chunk（include_usage），记到这条回答上
          if (j.usage) {
            convs[cur].msgs[idx].usage =
              (j.usage.prompt_tokens || 0) + (j.usage.completion_tokens || 0);
          }
          const d = j.choices && j.choices[0] && j.choices[0].delta;
          if (d && d.content) {
            convs[cur].msgs[idx].content += d.content;
            const texts = document.querySelectorAll('#stream .mtext');
            const last = texts[texts.length - 1];
            last.textContent = convs[cur].msgs[idx].content;
            last.insertAdjacentHTML('beforeend', '<span class="caret"></span>');
            $('stream').scrollTop = $('stream').scrollHeight;
          }
        } catch (_) {}
      }
    }
    convs[cur].msgs[idx].streaming = false;
    render();
  } catch (e) {
    push('assistant', '请求出错：' + e.message, null, true);
  } finally {
    $('btnSend').disabled = false;
  }
}

/* ---------- 事件绑定 ---------- */
/* 发送键 / 语音键二选一：没内容显示语音键，有内容换成发送键
   （正在收音时语音键一直留着，否则字一出来它就消失、没法停）。 */
function syncSendBtn() {
  const hasText = ($('input').value || '').trim().length > 0;
  const has = hasText || pendingImgs.length > 0;
  $('btnVoice').classList.toggle('hide', has && !voiceOn);
  $('btnSend').classList.toggle('hide', !has);
}
function cycleRole() {
  inputRole = ROLES[(ROLES.indexOf(inputRole) + 1) % ROLES.length];
  const chip = $('roleChip');
  // 只换图标不摆文字（气泡里已经有角色名了）
  chip.setAttribute('icon', ROLE_ICON[inputRole]);
  chip.title = ROLE_LABEL[inputRole] + '（点击切换）';
  if (inputRole === 'user') chip.removeAttribute('selected');
  else chip.setAttribute('selected', '');
}
/* 语音输入：浏览器的 Web Speech API（Chrome / Edge 可用）。
   识别结果接在已有文字后面，再点一次结束。 */
let recog = null;
let voiceOn = false;
function toggleVoice() {
  if (voiceOn && recog) { try { recog.stop(); } catch (_) {} return; }
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SR) { toast('这个浏览器不支持语音输入（换 Chrome / Edge 试试）'); return; }
  const before = ($('input').value || '').trim();
  const r = new SR();
  r.lang = navigator.language || 'zh-CN';
  r.continuous = true;
  r.interimResults = true;
  r.onresult = (ev) => {
    let txt = '';
    for (let i = 0; i < ev.results.length; i++) txt += ev.results[i][0].transcript;
    $('input').value = (before ? before + ' ' : '') + txt;
    autosizeInput();
    syncSendBtn();
  };
  r.onerror = (ev) => toast('语音输入失败：' + (ev.error || '未知错误'));
  r.onend = () => { voiceOn = false; $('btnVoice').classList.remove('listening'); syncSendBtn(); };
  try {
    r.start();
    recog = r;
    voiceOn = true;
    $('btnVoice').classList.add('listening');
    syncSendBtn();
    toast('正在聆听，再点一次结束');
  } catch (_) {
    voiceOn = false;
  }
}

$('input').addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) { e.preventDefault(); send(); }
});
$('input').addEventListener('input', () => { autosizeInput(); syncSendBtn(); });
// 粘贴图片：截图直接 Ctrl+V。输入框和 document 各挂一份 —— 焦点不在
// 输入框里（刚截完图没点进去）也能粘上；输入框那份先 preventDefault，
// document 这份看到 defaultPrevented 就跳过，不会重复收图。
const pasteImages = (e) => {
  if (e.defaultPrevented) return;
  const files = e.clipboardData && e.clipboardData.files;
  if (files && files.length) { e.preventDefault(); addImageFiles(files); }
};
$('input').addEventListener('paste', pasteImages);
document.addEventListener('paste', pasteImages);
// 拖图进输入台
const composer = document.querySelector('.composer');
composer.addEventListener('dragover', (e) => { e.preventDefault(); composer.classList.add('drop'); });
composer.addEventListener('dragleave', () => composer.classList.remove('drop'));
composer.addEventListener('drop', (e) => {
  e.preventDefault();
  composer.classList.remove('drop');
  if (e.dataTransfer && e.dataTransfer.files) addImageFiles(e.dataTransfer.files);
});
$('btnAttach').addEventListener('click', () => $('filePick').click());
$('filePick').addEventListener('change', (e) => {
  addImageFiles(e.target.files);
  e.target.value = '';
});
$('btnVoice').addEventListener('click', toggleVoice);
// 上下文占用环：点开 / 再点收起；点别处关掉
$('ctxBox').addEventListener('click', (e) => { e.stopPropagation(); toggleCtxPop(); });
$('ctxPop').addEventListener('click', (e) => e.stopPropagation());
document.addEventListener('click', () => toggleCtxPop(false));
document.addEventListener('keydown', (e) => { if (e.key === 'Escape') toggleCtxPop(false); });
$('modelSearch').addEventListener('input', renderModelList);
$('btnNew').addEventListener('click', () => { setView('chat'); newConv(); });
$('btnSend').addEventListener('click', send);
$('btnRail').addEventListener('click', () => setRail(!$('side').classList.contains('rail')));
$('btnMenu').addEventListener('click', toggleMobileSide);
$('navChat').addEventListener('click', () => setView('chat'));
$('navDiscover').addEventListener('click', () => setView('discover'));
$('roleChip').addEventListener('click', cycleRole);
$('btnSettings').addEventListener('click', () => {
  $('settingsPanel').hidden = !$('settingsPanel').hidden;
});
$('base').addEventListener('change', () => { store.set('base', $('base').value.trim()); loadModels(); });
$('key').addEventListener('change', () => { store.set('key', $('key').value.trim()); loadModels(); });

// 侧栏折叠状态跟着上次走；启动落在对话视图
setRail(store.get('rail', '0') === '1');
setView('chat');
newConv();
autosizeInput();
syncSendBtn();
bootstrap();
</script>
</body>
</html>
''';

