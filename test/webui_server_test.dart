import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/character_store.dart';
import 'package:local2api/services/config_store.dart';
import 'package:local2api/services/server_controller.dart';
import 'package:local2api/services/webui_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // 同 proxy_server_test.dart：不要 ensureInitialized()，
  // 它会把测试里所有 HttpClient 请求劫持成 400。

  group('WebUiServer 独立端口', () {
    test('起在 webUiPort 上，与 listenPort 互不干扰', () async {
      final config = ProxyConfig(
        listenHost: '127.0.0.1',
        listenPort: 19296, // 转发口：故意不起
        webUiEnabled: true,
        webUiPort: 19297, // 网页口
        webUiHost: '127.0.0.1',
      );
      final webUi = WebUiServer(configProvider: () => config);
      await webUi.start();
      addTearDown(() async => webUi.stop());

      expect(webUi.isRunning, isTrue);
      expect(webUi.boundPort, 19297);
      expect(webUi.url.toString(), 'http://127.0.0.1:19297/');

      // 转发口没起：连不上才是对的
      final http = HttpClient();
      var apiDown = false;
      try {
        final req = await http
            .getUrl(Uri.parse('http://127.0.0.1:19296/v1/models'))
            .timeout(const Duration(seconds: 2));
        await req.close();
      } catch (_) {
        apiDown = true;
      } finally {
        http.close(force: true);
      }
      expect(apiDown, isTrue);

      // 网页口活着
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:19297/'));
      final res = await req.close();
      final html = await res.transform(utf8.decoder).join();
      client.close();
      expect(res.statusCode, 200);
      expect(html, contains('<title>local2api'));
      expect(res.headers.contentType.toString(), contains('text/html'));
      expect(webUi.isRunning, isTrue);
    });

    test('页面是单文件：任意路径都回同一份 HTML，/healthz 给 JSON', () async {
      final config = ProxyConfig(
        webUiEnabled: true,
        webUiPort: 19298,
        webUiHost: '127.0.0.1',
      );
      final webUi = WebUiServer(configProvider: () => config);
      await webUi.start();
      addTearDown(() async => webUi.stop());

      Future<String> get(String path) async {
        final client = HttpClient();
        final req = await client.getUrl(
          Uri.parse('http://127.0.0.1:19298$path'),
        );
        final res = await req.close();
        final text = await res.transform(utf8.decoder).join();
        client.close();
        return text;
      }

      expect(await get('/whatever'), contains('<title>local2api'));
      expect(await get('/healthz'), contains('{"status":"ok","ui":true}'));
    });

    test('停掉后端口释放，状态回到 stopped', () async {
      final config = ProxyConfig(
        webUiEnabled: true,
        webUiPort: 19299,
        webUiHost: '127.0.0.1',
      );
      final webUi = WebUiServer(configProvider: () => config);
      await webUi.start();
      await webUi.stop();
      expect(webUi.isRunning, isFalse);
      expect(webUi.url, isNull);

      // 端口确实空了：再起一次应当成功
      final again = WebUiServer(configProvider: () => config);
      await again.start();
      addTearDown(() async => again.stop());
      expect(again.boundPort, 19299);
    });
  });

  group('ServerController 的 WebUI 旁路', () {
    late ConfigStore store;
    late ServerController controller;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = ConfigStore();
      await store.load();
      controller = ServerController(store);
    });

    tearDown(() => controller.dispose());

    test('setWebUiEnabled(true) 起网页、关掉就停，转发服务不受影响', () async {
      final cfg = store.config;
      cfg.webUiHost = '127.0.0.1';
      cfg.webUiPort = 19300;
      store.update(cfg);

      await controller.setWebUiEnabled(true);
      expect(controller.webUi.isRunning, isTrue);
      expect(controller.webUi.boundPort, 19300);
      // 转发服务没被顺手拉起来：WebUI 是旁路
      expect(controller.isRunning, isFalse);

      await controller.setWebUiEnabled(false);
      expect(controller.webUi.isRunning, isFalse);
    });

    test('配置里改端口：开着的 WebUI 跟着重启', () async {
      final cfg = store.config;
      cfg.webUiHost = '127.0.0.1';
      cfg.webUiPort = 19301;
      cfg.webUiEnabled = true;
      store.update(cfg);
      await controller.setWebUiEnabled(true);
      expect(controller.webUi.boundPort, 19301);

      cfg.webUiPort = 19302;
      store.update(cfg);
      // 防抖 + 异步重启
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(controller.webUi.isRunning, isTrue);
      expect(controller.webUi.boundPort, 19302);
      await controller.webUi.stop();
    });

    test('发现页能拿到内置预制卡（注入不过滤 builtin）', () async {
      final cfg = store.config;
      cfg.webUiHost = '127.0.0.1';
      cfg.webUiPort = 19305;
      store.update(cfg);
      await controller.setWebUiEnabled(true);
      addTearDown(() async => controller.webUi.stop());

      final client = HttpClient();
      final req = await client.getUrl(
        Uri.parse('http://127.0.0.1:19305/api/characters'),
      );
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      client.close();

      final json = jsonDecode(text) as Map<String, dynamic>;
      final list = (json['characters'] as List).cast<Map<String, dynamic>>();
      final names = [for (final c in list) c['name']];
      expect(names, containsAll(['流萤', '蕾姆']));
      final firefly = list.firstWhere((c) => c['name'] == '流萤');
      expect(firefly['builtin'], isTrue);
    });

    test('主服务停止时 WebUI 一起收摊', () async {
      final cfg = store.config;
      cfg.listenHost = '127.0.0.1';
      cfg.listenPort = 19303;
      cfg.webUiHost = '127.0.0.1';
      cfg.webUiPort = 19304;
      cfg.webUiEnabled = true;
      store.update(cfg);
      await controller.start();
      expect(controller.webUi.isRunning, isTrue);
      await controller.stop();
      expect(controller.webUi.isRunning, isFalse);
      expect(controller.isRunning, isFalse);
    });
  });

  group('WebUI 反代与启动信息', () {
    Future<String> getText(int port, String path) async {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      client.close();
      return text;
    }

    test('/api/bootstrap 列出「已配置的对外模型」+ 同源基址', () async {
      final config = ProxyConfig(
        listenHost: '127.0.0.1',
        listenPort: 19310,
        webUiEnabled: true,
        webUiPort: 19311,
        webUiHost: '127.0.0.1',
      );
      config.upstreams.add(
        Upstream(
          id: 'u1',
          name: 'u1',
          baseUrl: 'http://x/v1',
          models: [
            ModelEntry(publicName: 'alpha'),
            ModelEntry(publicName: 'beta'),
            // 没勾选暴露的不该出现
            ModelEntry(publicName: 'hidden', enabled: false),
          ],
        ),
      );
      config.upstreams.add(
        Upstream(
          id: 'u2',
          name: 'u2',
          baseUrl: 'http://y/v1',
          enabled: false, // 整个上游停用
          models: [ModelEntry(publicName: 'gamma')],
        ),
      );
      final webUi = WebUiServer(configProvider: () => config);
      await webUi.start();
      addTearDown(() async => webUi.stop());

      final json =
          jsonDecode(await getText(19311, '/api/bootstrap'))
              as Map<String, dynamic>;
      expect(json['base'], '/v1');
      expect(json['apiPort'], 19310);
      expect(json['models'], ['alpha', 'beta']);
      expect(json['hasKey'], isFalse);
    });

    test('/v1/* 反代到转发口并自动补上第一条启用的密钥', () async {
      // 假 API 口：记下收到的路径与 Authorization。
      final api = await HttpServer.bind(InternetAddress.loopbackIPv4, 19312);
      String? seenAuth;
      String? seenPath;
      api.listen((r) {
        seenAuth = r.headers.value('authorization');
        seenPath = r.uri.path;
        r.response.headers.contentType = ContentType.json;
        r.response.write('{"object":"list","data":[]}');
        r.response.close();
      });
      addTearDown(() async => api.close(force: true));

      final config = ProxyConfig(
        listenHost: '127.0.0.1',
        listenPort: 19312,
        webUiEnabled: true,
        webUiPort: 19313,
        webUiHost: '127.0.0.1',
      );
      config.apiKeys.add(
        ApiKeyEntry(id: 'k1', name: 'test', key: 'sk-webui-test'),
      );
      final webUi = WebUiServer(configProvider: () => config);
      await webUi.start();
      addTearDown(() async => webUi.stop());

      final client = HttpClient();
      final req = await client.getUrl(
        Uri.parse('http://127.0.0.1:19313/v1/models'),
      );
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      client.close();

      expect(res.statusCode, 200);
      expect(body, contains('"object":"list"'));
      expect(seenPath, '/v1/models');
      expect(seenAuth, 'Bearer sk-webui-test');
    });

    test('转发口没起时 /v1/* 回 502，而不是把网页 HTML 当成响应', () async {
      final config = ProxyConfig(
        listenHost: '127.0.0.1',
        listenPort: 19314, // 故意不起
        webUiEnabled: true,
        webUiPort: 19315,
        webUiHost: '127.0.0.1',
      );
      final webUi = WebUiServer(configProvider: () => config);
      await webUi.start();
      addTearDown(() async => webUi.stop());

      final client = HttpClient();
      final req = await client.getUrl(
        Uri.parse('http://127.0.0.1:19315/v1/models'),
      );
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      client.close();

      expect(res.statusCode, 502);
      expect(body, contains('API 口连不上'));
    });

    test('页面内嵌 Qwen 风选择器与圆角输入台的关键节点', () async {
      final config = ProxyConfig(
        webUiEnabled: true,
        webUiPort: 19316,
        webUiHost: '127.0.0.1',
      );
      final webUi = WebUiServer(configProvider: () => config);
      await webUi.start();
      addTearDown(() async => webUi.stop());

      final html = await getText(19316, '/');
      for (final id in [
        // 顶栏
        'btnMenu',
        'modelDd',
        'modelName',
        'modelMenu',
        'modelSearch',
        'modelList',
        'barTitle',
        'laneTag',
        'btnSettings',
        // 侧栏
        'side',
        'btnRail',
        'btnNew',
        'navChat',
        'navDiscover',
        'conv',
        // 连接设置
        'settingsPanel',
        'base',
        'key',
        // 对话
        'viewChat',
        'stream',
        'input',
        'hero',
        'roleChip',
        'btnVoice',
        'btnSend',
        // 发现
        'viewDiscover',
        'cards',
        // 消息条
        'snack',
      ]) {
        expect(html, contains('id="$id"'), reason: '页面缺节点 #$id');
      }
      // 圆角输入台只有 class
      expect(html, contains('class="composer"'));
      // 侧栏折叠是「宽度过渡到图标栏」，不是 display:none
      expect(html, contains('#side.rail'));
      // 侧栏骨架移植自 NaviFlash：menu ⇄ menu_open、方形「+」→「新对话」、
      // 导航项空心/实心随选中切
      expect(html, contains('menu_open'));
      expect(html, contains('新对话'));
      expect(html, contains('chat_bubble_outline'));
      expect(html, contains('travel_explore'));
      expect(html, contains('class="side-item'));
      // 内容区圆角卡片 + 消息头像/气泡（对齐 App「对话模拟」）
      expect(html, contains('shell-card'));
      expect(html, contains('ROLE_AVATAR'));
      expect(html, contains('#side.rail .side-item.active .lbl'));
      expect(html, contains('mavatar'));
      // 语音键（从 chat.qwen.ai 扒的声波四竖条）+ 空态问候 + 居中布局
      expect(html, contains('语音输入'));
      expect(html, contains('有什么可以帮您的吗'));
      expect(html, contains('M192 320v384H64V320h128z'));
      expect(html, contains('chat-empty'));
      // 上下文占用环（对齐 opencode 的 ProgressCircle）
      expect(html, contains('ctxBox'));
      expect(html, contains('ctxArc'));
      expect(html, contains('estimateTokens'));
      expect(html, contains('strokeDashoffset'));
      // 顶栏去背景
      expect(html, contains('mdui-top-app-bar[scrolling]'));
      // UI 是 mdui 2（Web Components），资源走 /assets/*
      expect(html, contains('mdui-top-app-bar'));
      expect(html, contains('mdui-text-field'));
      expect(html, contains('mdui-list-item'));
      expect(html, contains('mdui-card'));
      expect(html, contains('mdui-snackbar'));
      expect(html, contains('/assets/mdui.css'));
      expect(html, contains('/assets/mdui.global.js'));
      expect(html, contains('/assets/material-icons.woff2'));
      // 默认同源走 WebUI 自己的代理，并调 bootstrap 取已配置的对外模型
      expect(html, contains('/api/bootstrap'));
      expect(html, contains('/api/characters'));
      expect(html, contains('/chat/completions'));
      expect(html, contains("'/v1'"));
    });

    test('/api/characters 把人设卡原样给网页（含预制问答与 builtin 标记）', () async {
      final config = ProxyConfig(
        webUiEnabled: true,
        webUiPort: 19317,
        webUiHost: '127.0.0.1',
      );
      final webUi = WebUiServer(
        configProvider: () => config,
        charactersProvider: () => const [
          CharacterCard(
            id: 'builtin.demo',
            name: '预制角色',
            prompt: '你是预制角色。',
            builtin: true,
          ),
          CharacterCard(
            id: 'c1',
            name: '测试角色',
            prompt: '你是一个测试角色。',
            presets: [ChatPresetPair(user: '在吗', assistant: '在的')],
          ),
        ],
      );
      await webUi.start();
      addTearDown(() async => webUi.stop());

      final json =
          jsonDecode(await getText(19317, '/api/characters'))
              as Map<String, dynamic>;
      final list = json['characters'] as List;
      expect(list, hasLength(2));
      final builtin = list.first as Map<String, dynamic>;
      expect(builtin['id'], 'builtin.demo');
      expect(builtin['builtin'], isTrue);
      final card = list.last as Map<String, dynamic>;
      expect(card['id'], 'c1');
      expect(card['name'], '测试角色');
      expect(card['prompt'], '你是一个测试角色。');
      expect(card['builtin'], isFalse);
      final presets = card['presets'] as List;
      expect(presets, hasLength(1));
      expect((presets.first as Map)['user'], '在吗');
      expect((presets.first as Map)['assistant'], '在的');
    });

    test('/api/characters 没注入 provider 时回空列表（发现页显示空态）', () async {
      final config = ProxyConfig(
        webUiEnabled: true,
        webUiPort: 19318,
        webUiHost: '127.0.0.1',
      );
      final webUi = WebUiServer(configProvider: () => config);
      await webUi.start();
      addTearDown(() async => webUi.stop());

      final json =
          jsonDecode(await getText(19318, '/api/characters'))
              as Map<String, dynamic>;
      expect(json['characters'], isEmpty);
    });

    test('/assets/* 按名吐打包的前端资源，并挡住路径穿越', () async {
      final config = ProxyConfig(
        webUiEnabled: true,
        webUiPort: 19319,
        webUiHost: '127.0.0.1',
      );
      var loads = 0;
      final webUi = WebUiServer(
        configProvider: () => config,
        assetLoader: (name) async {
          loads++;
          return utf8.encode('/* $name */');
        },
      );
      await webUi.start();
      addTearDown(() async => webUi.stop());

      final client = HttpClient();
      Future<HttpClientResponse> get(String path) async {
        final req = await client.getUrl(
          Uri.parse('http://127.0.0.1:19319$path'),
        );
        return req.close();
      }

      final res = await get('/assets/mdui.css');
      final css = await res.transform(utf8.decoder).join();
      expect(res.statusCode, 200);
      expect(res.headers.contentType?.mimeType, 'text/css');
      expect(css, contains('/* mdui.css */'));

      // 第二次命中内存缓存，不再打 loader
      await (await get('/assets/mdui.css')).drain<void>();
      expect(loads, 1);

      final js = await get('/assets/mdui.global.js');
      expect(js.statusCode, 200);
      expect(js.headers.contentType?.mimeType, 'application/javascript');
      await js.drain<void>();

      final font = await get('/assets/material-icons.woff2');
      expect(font.headers.contentType?.mimeType, 'font/woff2');
      await font.drain<void>();

      // 子目录 / 路径穿越一律 404
      expect((await get('/assets/a/b')).statusCode, 404);
      expect((await get('/assets/%2e%2e%2fsecret')).statusCode, 404);

      client.close();
    });

    test('没注入 assetLoader 时 /assets/* 回 404（页面只有自带样式）', () async {
      final config = ProxyConfig(
        webUiEnabled: true,
        webUiPort: 19320,
        webUiHost: '127.0.0.1',
      );
      final webUi = WebUiServer(configProvider: () => config);
      await webUi.start();
      addTearDown(() async => webUi.stop());

      final client = HttpClient();
      final req = await client.getUrl(
        Uri.parse('http://127.0.0.1:19320/assets/mdui.css'),
      );
      final res = await req.close();
      await res.drain<void>();
      client.close();
      expect(res.statusCode, 404);
    });
  });
}
