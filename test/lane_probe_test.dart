import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/lane_probe.dart';
import 'package:local2api/services/zen/zen_protocol.dart';

/// 一次被假上游收到的探测请求。
class _Recorded {
  _Recorded(this.method, this.path, this.headers, this.body);

  final String method;
  final String path;
  final HttpHeaders headers;
  final String body;

  Map<String, dynamic> get json =>
      (jsonDecode(body) as Map<String, dynamic>);

  String? header(String name) => headers.value(name);
}

/// 回环假上游。探测的可用性判定必须由真实客户端行为驱动，
/// 所以这里要能按车道名分别回不同状态码与错误体。
class _FakeUpstream {
  final List<_Recorded> requests = [];

  /// 车道名 → (状态码, 响应体)。没配的车道走 [fallback]。
  final Map<String, (int, String)> respond = {};

  (int, String) fallback = (200, '{"id":"chatcmpl-1","choices":[]}');

  /// 只接连接、不应答就掐断，用来验证「连不上就提前停」。
  bool destroyWithoutReply = false;

  HttpServer? _server;
  int _accepted = 0;

  int get accepted => _accepted;

  /// isZenGateway 要求路径首段是 zen，否则探测请求不会带客户端指纹。
  String get baseUrl => 'http://127.0.0.1:${_server!.port}/zen/v1';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((req) async {
      _accepted++;
      if (destroyWithoutReply) {
        // 服务端没有 destroy()：先脱离 HTTP 层拿到裸 socket 再粗暴关掉，
        // 客户端就拿不到任何合法响应头，正好落进「连不上」那一档。
        final socket = await req.response.detachSocket(writeHeaders: false);
        socket.destroy();
        return;
      }
      final body = await utf8.decoder.bind(req).join();
      requests.add(_Recorded(req.method, req.uri.path, req.headers, body));
      final lane = switch (jsonDecode(body)) {
        final Map<String, dynamic> m => '${m['model'] ?? ''}',
        _ => '',
      };
      final (status, payload) = respond[lane] ?? fallback;
      req.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(payload);
      await req.response.close();
    });
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}

/// 找一个没人监听的端口，用来模拟设备根本连不上端点。
Future<int> _deadPort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  await s.close();
  return port;
}

/// 指纹四件套在 body.tools 里有三种形状：claude / flat 把 name 放顶层，
/// chat 线嵌在 function.name 下面。三种都得认，否则读出来的是 type 值。
String _toolName(Object? tool) {
  if (tool is! Map<String, dynamic>) return '';
  final direct = tool['name'];
  if (direct is String && direct.isNotEmpty) return direct;
  final fn = tool['function'];
  if (fn is Map<String, dynamic> && fn['name'] is String) return fn['name'];
  return '';
}

void main() {
  // 注意：不要调用 TestWidgetsFlutterBinding.ensureInitialized()，
  // 它会装上 HttpOverrides，把测试里所有 HttpClient 请求短路成 400，
  // 假上游一个字节都收不到（proxy_server_test.dart 里记着同一条坑）。
  late _FakeUpstream upstream;

  setUp(() async {
    upstream = _FakeUpstream();
    await upstream.start();
    // 让回环 host 被当成 Zen 免密网关，探测才会补齐桌面客户端指纹。
    zenGatewayHosts.add('127.0.0.1');
  });

  tearDown(() async {
    await upstream.stop();
    zenGatewayHosts.remove('127.0.0.1');
    laneProbeResults.clear();
  });

  Future<List<LaneProbe>> probe(List<String> lanes) =>
      LaneProbeService.probeLanes(
        baseUrl: upstream.baseUrl,
        lanes: lanes,
      );

  _Recorded only(String lane) =>
      upstream.requests.firstWhere((r) => r.json['model'] == lane);

  group('拒绝原因分档', () {
    test('缺指纹 / 地区受限 / 额度打满 / 模型坏了不是一回事', () async {
      upstream.respond['restricted-free'] = (
        403,
        '{"error":{"name":"FreeTierError","message":"only within OpenCode"}}',
      );
      upstream.respond['region-free'] = (
        403,
        '{"error":{"name":"RegionError","message":"not available in your country"}}',
      );
      upstream.respond['throttled-free'] = (
        429,
        '{"error":{"name":"FreeUsageLimitError","message":"usage limit reached"}}',
      );
      upstream.respond['broken-free'] = (
        404,
        '{"error":{"name":"ModelError","message":"model is unavailable"}}',
      );
      upstream.respond['boom-free'] = (500, 'upstream exploded');

      final probes = await probe([
        'restricted-free',
        'region-free',
        'throttled-free',
        'broken-free',
        'boom-free',
      ]);

      // 这四档在 UI 上必须是四种颜色：额度打满会自己恢复，地区受限换个出口就好，
      // 只有「模型没了」才该把车道从选择器里摘掉。糊成同一个红色等于没分类。
      expect(
        probes.map((p) => p.verdict),
        [
          LaneVerdict.restricted,
          LaneVerdict.regionBlocked,
          LaneVerdict.throttled,
          LaneVerdict.unavailable,
          LaneVerdict.failed,
        ],
      );
      expect(probes.every((p) => p.status != null), isTrue);
      expect(probes.every((p) => (p.detail ?? '').isNotEmpty), isTrue);
    });

    test('200 判可用并记下往返耗时', () async {
      final probes = await probe(['ok-free']);
      expect(probes.single.verdict, LaneVerdict.usable);
      expect(probes.single.status, 200);
      expect(probes.single.delayMs, isNotNull);
      expect(probes.single.delayMs, greaterThanOrEqualTo(0));
    });

    test('每条车道都要有结论，不能因为中途出错就少给', () async {
      upstream.respond['bad-free'] = (500, 'x');
      final lanes = ['bad-free', 'ok-free', 'region-free'];
      upstream.respond['region-free'] = (403, 'RegionError');

      final probes = await probe(lanes);
      expect(probes.length, lanes.length);
      expect(probes.map((p) => p.model), lanes);
    });
  });

  group('探测请求自己就带客户端指纹', () {
    test('指纹头齐活：public bearer + opencode UA + 三个 x-opencode-*', () async {
      await probe(['space-bunny-free']);

      final r = only('space-bunny-free');
      expect(r.method, 'POST');
      expect(r.header(HttpHeaders.authorizationHeader), 'Bearer public');
      expect(r.header(HttpHeaders.userAgentHeader), kZenClientUa);
      expect(r.header('x-opencode-client'), 'desktop');
      expect(r.header('x-opencode-project'), 'global');
      expect(r.header('x-opencode-session'), isNotNull);
      expect(r.header('x-opencode-session'), isNotEmpty);
      expect(r.header('x-opencode-request'), isNotNull);
      expect(r.header('x-opencode-request'), isNotEmpty);
    });

    test('body.tools 声明了免费档指纹门要的四件套', () async {
      await probe(['space-bunny-free']);

      final tools = only('space-bunny-free').json['tools'] as List?;
      expect(tools, isNotNull, reason: '缺 tools 会被上游当伪造客户端 403');
      final names = <String>{for (final t in tools!) _toolName(t)};
      expect(names, containsAll(kZenFingerprintTools));
    });

    test('按线协议打到各自端点：chat / responses / messages', () async {
      await probe([
        'space-bunny-free',
        'muse-spark-1.2-contributor-free',
        'union-alpha',
      ]);

      expect(only('space-bunny-free').path, endsWith('/zen/v1/chat/completions'));
      expect(
        only('muse-spark-1.2-contributor-free').path,
        endsWith('/zen/v1/responses'),
      );
      expect(only('union-alpha').path, endsWith('/zen/v1/messages'));
    });
  });

  group('判定模型', () {
    test('System One 那类不出网就给结论', () async {
      // jev* 是判定模型，只在自己的端点上回答结构化决策，
      // 拿聊天请求打过去只会收到莫名的状态码 —— 干脆别打。
      final probes = await probe(['jev-1']);

      expect(probes.single.verdict, LaneVerdict.unavailable);
      expect(probes.single.status, isNull);
      expect(probes.single.detail, contains('判定模型'));
      expect(upstream.requests, isEmpty, reason: '不该发出任何请求');
    });

    test('同一批里判定模型不出网，其余照常探', () async {
      final probes = await probe(['jev-1', 'ok-free']);
      expect(probes[0].verdict, LaneVerdict.unavailable);
      expect(probes[1].verdict, LaneVerdict.usable);
      expect(upstream.requests.length, 1);
    });
  });

  group('连不上端点时的探测', () {
    test('每条车道都有结论，并提前停止不拖满超时', () async {
      // 只接连接、不应答就掐断：每条都是「连响应头都没拿到」。
      // 6 条车道但只该真打 3 次 —— 连着 3 次拿不到响应头就判定设备
      // 根本连不上端点，剩下的直接标 unreachable，不然要白等 6×25 秒。
      upstream.destroyWithoutReply = true;
      const lanes = ['a-free', 'b-free', 'c-free', 'd-free', 'e-free', 'f-free'];

      final probes = await LaneProbeService.probeLanes(
        baseUrl: upstream.baseUrl,
        lanes: lanes,
      );

      expect(probes.length, lanes.length);
      expect(
        probes.every((p) => p.verdict == LaneVerdict.unreachable),
        isTrue,
      );
      expect(probes.every((p) => p.status == null), isTrue);
      expect(upstream.accepted, 3, reason: '连不上就该提前停，别一条条等超时');
    });

    test('端口根本没人听：也是 unreachable 而不是崩掉', () async {
      final port = await _deadPort();
      final probes = await LaneProbeService.probeLanes(
        baseUrl: 'http://127.0.0.1:$port/zen/v1',
        lanes: const ['a-free', 'b-free'],
      );
      expect(probes.length, 2);
      expect(probes.every((p) => p.verdict == LaneVerdict.unreachable), isTrue);
    });
  });

  group('共享结果存储', () {
    test('probe() 把结果写进共享存储，探测中状态自己收干净', () async {
      var sawTesting = false;
      laneProbeResults.addListener(() {
        if (laneProbeResults.isTesting('demo')) sawTesting = true;
      });

      await LaneProbeService.probe(
        key: 'demo',
        baseUrl: upstream.baseUrl,
        lanes: const ['ok-free'],
      );

      expect(sawTesting, isTrue, reason: 'UI 要靠它显示「探测中」');
      expect(laneProbeResults.isTesting('demo'), isFalse);
      expect(laneProbeResults.of('ok-free')?.verdict, LaneVerdict.usable);
      expect(
        laneProbeResults.forLanes(['ok-free', 'never-probed'])[1],
        isNull,
        reason: '没测过的位置要留空，不能拿旧结果顶上',
      );
    });

    test('车道列表是空的就什么都不做', () async {
      await LaneProbeService.probe(
        key: 'demo',
        baseUrl: upstream.baseUrl,
        lanes: const [],
      );
      expect(upstream.accepted, 0);
      expect(laneProbeResults.isTesting('demo'), isFalse);
    });
  });
}
