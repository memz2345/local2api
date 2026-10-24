// 上游余额查询的离线回归：一只「假上游」当转发代理，验路由表 + 各家响应解析。
//
// 怎么做到不碰真网络：给 HttpClient 设 `findProxy = PROXY 127.0.0.1:<port>`，
// 于是打到 `http://api.deepseek.com/user/balance` 这类**厂商域名**的请求会
// 以绝对 URI 的形式落到本地这只 HttpServer 上 —— 既能按 host 认厂（路由表
// 走真实分支），又完全离线。上游实测（真密钥）由用户在设备上做。
//
// 注意：本文件刻意不调 `TestWidgetsFlutterBinding.ensureInitialized()` ——
// 它会把测试里所有 HttpClient 请求劫持成 400（同 proxy_server_test.dart）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/upstream_balance.dart';

/// 一条桩响应：状态码 + 要回的 JSON（[body]），或原样回一段文本（[raw]，
/// 用来造「200 但回的不是 JSON」）。
class _Stub {
  const _Stub(this.status, this.body, {this.raw});

  final int status;
  final Object? body;
  final String? raw;
}

/// 离线假上游：按 `host + path` 查桩，并记下收到的请求（含 Authorization 头）。
class _FakeGateway {
  _FakeGateway();

  final Map<String, _Stub> routes = {};

  /// 同一 key 的第 N 次调用回第 N 个桩（次数用完就固定回最后一个）。
  /// one-api 的「Bearer 先 401、裸 token 才 200」要靠它造。
  final Map<String, List<_Stub>> sequences = {};

  /// 收到的请求，形如 `GET api.deepseek.com/user/balance`。
  final List<String> requests = [];

  /// 收到的 Authorization 头原值（null = 没带）。
  final List<String?> authHeaders = [];

  HttpServer? _server;
  int get port => _server!.port;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// 打到这只假上游的 HttpClient（厂商域名靠代理转发进来，不出网）。
  HttpClient client() {
    // 不用级联写：`..findProxy = (uri) => ...` 的箭头体会把后面的
    // `..autoUncompress` 一起吃掉（编译器报的是 String 上没有这个 setter）。
    final c = HttpClient();
    c.findProxy = (uri) => 'PROXY 127.0.0.1:$port';
    c.autoUncompress = false;
    return c;
  }

  void on(String hostPath, _Stub stub) => routes[hostPath] = stub;

  void onFlaky(String hostPath, List<_Stub> stubs) {
    sequences[hostPath] = stubs;
    routes.remove(hostPath);
  }

  final Map<String, int> _hits = {};

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    final query = req.uri.query;
    final key = '${req.uri.host}$path';
    requests.add('${req.method} $key${query.isEmpty ? '' : '?$query'}');
    authHeaders.add(req.headers.value(HttpHeaders.authorizationHeader));
    final seq = sequences[key];
    _Stub? stub;
    if (seq != null && seq.isNotEmpty) {
      final n = _hits.update(key, (v) => v + 1, ifAbsent: () => 1);
      stub = seq[(n - 1).clamp(0, seq.length - 1)];
    } else {
      stub = routes[key];
    }
    req.response.statusCode = stub?.status ?? 404;
    if (stub?.raw != null) {
      req.response.headers.contentType = ContentType.html;
      req.response.write(stub!.raw);
    } else if (stub?.body != null) {
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(stub!.body));
    }
    await req.response.close();
  }
}

Upstream remote(String baseUrl, {String apiKey = 'sk-test'}) => Upstream(
  id: 'u1',
  name: '测试上游',
  baseUrl: baseUrl,
  apiKey: apiKey,
);

void main() {
  final gateway = _FakeGateway();

  setUp(() async {
    gateway.routes.clear();
    gateway.sequences.clear();
    gateway._hits.clear();
    gateway.requests.clear();
    gateway.authHeaders.clear();
    await gateway.start();
  });

  tearDown(() async {
    await gateway.stop();
  });

  group('余额路由表', () {
    test('认出厂家的 host 只走自家接口', () {
      expect(
        UpstreamBalanceService.endpointIdsFor('api.deepseek.com'),
        ['deepseek'],
      );
      expect(UpstreamBalanceService.endpointIdsFor('api.moonshot.cn'), [
        'moonshot',
      ]);
      expect(UpstreamBalanceService.endpointIdsFor('api.kimi.com'), [
        'moonshot',
      ]);
      expect(UpstreamBalanceService.endpointIdsFor('api.stepfun.com'), [
        'stepfun',
      ]);
      expect(UpstreamBalanceService.endpointIdsFor('api.siliconflow.cn'), [
        'siliconFlow',
      ]);
      expect(UpstreamBalanceService.endpointIdsFor('openrouter.ai'), [
        'openRouter',
      ]);
      expect(UpstreamBalanceService.endpointIdsFor('api.novita.ai'), [
        'novita',
      ]);
    });

    test('认不出的走通用链：自建网关 → OpenAI dashboard → DeepSeek 形状', () {
      expect(
        UpstreamBalanceService.endpointIdsFor('gw.example.com'),
        ['selfHosted', 'openAiBilling', 'deepseekMimic'],
      );
      // host 判定不看大小写
      expect(UpstreamBalanceService.endpointIdsFor('API.DeepSeek.COM'), [
        'deepseek',
      ]);
    });

    test('通用链的 DeepSeek 形状探针打部署前缀，不是站点根', () async {
      // 自建网关装在 /napi 下：`/napi/user/balance` 才是它的地址。
      gateway.on(
        'gw.example.com/napi/user/balance',
        const _Stub(
          200,
          {
            'is_available': true,
            'balance_infos': [
              {
                'currency': 'CNY',
                'total_balance': '3.00',
                'granted_balance': '1.00',
                'topped_up_balance': '2.00',
              },
            ],
          },
        ),
      );
      final b = await UpstreamBalanceService.fetch(
        remote('http://gw.example.com/napi/v1'),
        client: gateway.client(),
      );
      expect(b.available, 3.0);
      expect(
        gateway.requests,
        contains('GET gw.example.com/napi/user/balance'),
      );
    });
  });

  group('取地址与鉴权', () {
    test('没填密钥直接拒，不发请求', () async {
      await expectLater(
        UpstreamBalanceService.fetch(
          remote('http://api.deepseek.com/v1', apiKey: ''),
          client: gateway.client(),
        ),
        throwsA(
          isA<BalanceException>().having(
            (e) => e.kind,
            'kind',
            BalanceFailure.noKey,
          ),
        ),
      );
      expect(gateway.requests, isEmpty);
    });

    test('baseUrl 尾部的 /v1 要剥掉：余额打的是站点根', () async {
      gateway.on(
        'api.deepseek.com/user/balance',
        const _Stub(
          200,
          {
            'is_available': true,
            'balance_infos': [
              {
                'currency': 'CNY',
                'total_balance': '1.00',
                'granted_balance': '0.00',
                'topped_up_balance': '1.00',
              },
            ],
          },
        ),
      );
      await UpstreamBalanceService.fetch(
        remote('http://api.deepseek.com/v1/'),
        client: gateway.client(),
      );
      expect(gateway.requests, ['GET api.deepseek.com/user/balance']);
      expect(gateway.authHeaders, ['Bearer sk-test']);
    });
  });

  group('各家解析', () {
    test('DeepSeek：字符串金额、币种、is_available 与赠送/充值明细', () async {
      gateway.on(
        'api.deepseek.com/user/balance',
        const _Stub(
          200,
          {
            'is_available': true,
            'balance_infos': [
              {
                'currency': 'CNY',
                'total_balance': '110.00',
                'granted_balance': '10.00',
                'topped_up_balance': '100.00',
              },
            ],
          },
        ),
      );
      final b = await UpstreamBalanceService.fetch(
        remote('http://api.deepseek.com'),
        client: gateway.client(),
      );
      expect(b.available, 110.0);
      expect(b.currency, 'CNY');
      expect(b.amountDisplay, '¥110.00');
      expect(b.accountUsable, isTrue);
      expect(b.quotaConverted, isFalse);
      // 单币种时余额行不重复出现，明细只给赠送 / 充值
      expect(b.details.map((d) => d.kind), [
        BalanceDetailKind.granted,
        BalanceDetailKind.toppedUp,
      ]);
      expect(b.details.first.valueText, '¥10.00');
      expect(b.source, 'DeepSeek /user/balance');
    });

    test('DeepSeek 多币种：每种币种各一行余额', () async {
      gateway.on(
        'api.deepseek.com/user/balance',
        const _Stub(
          200,
          {
            'is_available': false,
            'balance_infos': [
              {
                'currency': 'CNY',
                'total_balance': '8.50',
                'granted_balance': '0.00',
                'topped_up_balance': '8.50',
              },
              {
                'currency': 'USD',
                'total_balance': '2.00',
                'granted_balance': '0.00',
                'topped_up_balance': '2.00',
              },
            ],
          },
        ),
      );
      final b = await UpstreamBalanceService.fetch(
        remote('http://api.deepseek.com'),
        client: gateway.client(),
      );
      expect(b.available, 8.5);
      expect(b.accountUsable, isFalse);
      expect(b.details.first.kind, BalanceDetailKind.balance);
      expect(b.details.map((d) => d.valueText), [
        '¥8.50',
        r'$2.00',
        '¥0.00',
        r'$0.00',
        '¥8.50',
        r'$2.00',
      ]);
    });

    test('Kimi / Moonshot：数字金额、赠送与充值分开', () async {
      gateway.on(
        'api.moonshot.cn/v1/users/me/balance',
        const _Stub(
          200,
          {
            'code': 0,
            'data': {
              'available_balance': 49.58894,
              'voucher_balance': 46.58893,
              'cash_balance': 3.00001,
            },
            'scode': '0x0',
            'status': true,
          },
        ),
      );
      final b = await UpstreamBalanceService.fetch(
        remote('http://api.moonshot.cn/v1'),
        client: gateway.client(),
      );
      expect(b.available, closeTo(49.58894, 1e-6));
      expect(b.currency, 'CNY');
      expect(b.details.map((d) => d.kind), [
        BalanceDetailKind.granted,
        BalanceDetailKind.toppedUp,
      ]);
    });

    test('硅基流动：camelCase 字段与人民币', () async {
      gateway.on(
        'api.siliconflow.cn/v1/user/info',
        const _Stub(
          200,
          {
            'code': 0,
            'data': {
              'totalBalance': 12.34,
              'cashBalance': 10.00,
              'giftBalance': 2.34,
            },
          },
        ),
      );
      final b = await UpstreamBalanceService.fetch(
        remote('http://api.siliconflow.cn'),
        client: gateway.client(),
      );
      expect(b.available, 12.34);
      expect(b.currency, 'CNY');
    });

    test('阶跃星辰：/v1/accounts 的 balance', () async {
      gateway.on(
        'api.stepfun.com/v1/accounts',
        const _Stub(
          200,
          {
            'object': 'account',
            'type': 'normal',
            'balance': 5.0,
            'total_cash_balance': 4.0,
            'total_voucher_balance': 1.0,
          },
        ),
      );
      final b = await UpstreamBalanceService.fetch(
        remote('http://api.stepfun.com/v1'),
        client: gateway.client(),
      );
      expect(b.available, 5.0);
      expect(b.currency, 'USD');
    });

    test('OpenRouter：余额 = 累计充值 - 已用', () async {
      gateway.on(
        'openrouter.ai/api/v1/credits',
        const _Stub(200, {'data': {'total_credits': 20.0, 'total_usage': 6.5}}),
      );
      final b = await UpstreamBalanceService.fetch(
        remote('http://openrouter.ai/api/v1'),
        client: gateway.client(),
      );
      expect(b.available, 13.5);
      expect(b.details.single.kind, BalanceDetailKind.used);
      expect(b.details.single.valueText, r'$6.50');
    });

    test('Novita：单位是 0.0001 美元', () async {
      gateway.on(
        'api.novita.ai/v3/user/balance',
        const _Stub(200, {'availableBalance': 15000}),
      );
      final b = await UpstreamBalanceService.fetch(
        remote('http://api.novita.ai'),
        client: gateway.client(),
      );
      expect(b.available, 1.5);
      expect(b.amountDisplay, r'$1.50');
    });

    test('new-api：/api/status 认门 + Bearer 打 /api/user/self + quota 折算', () async {
      gateway.on(
        'gw.example.com/api/status',
        const _Stub(200, {'success': true, 'data': {'system_name': 'My GW'}}),
      );
      gateway.on(
        'gw.example.com/api/user/self',
        const _Stub(
          200,
          {
            'success': true,
            'data': {
              'username': 'me',
              'status': 1,
              'quota': 1500000,
              'used_quota': 500000,
              'request_count': 42,
              'group': 'default',
            },
          },
        ),
      );
      final b = await UpstreamBalanceService.fetch(
        remote('http://gw.example.com/v1'),
        client: gateway.client(),
      );
      // 1 美元 = 500000 quota
      expect(b.available, 3.0);
      expect(b.quotaConverted, isTrue);
      expect(b.accountUsable, isTrue);
      expect(b.details.map((d) => d.kind), [
        BalanceDetailKind.used,
        BalanceDetailKind.requests,
        BalanceDetailKind.group,
      ]);
      expect(b.details[0].valueText, r'$1.00');
      expect(b.details[1].valueText, '42');
      expect(b.details[2].valueText, 'default');
      // 认门那一枪不带鉴权头，第二枪才是 Bearer
      expect(gateway.authHeaders, [null, 'Bearer sk-test']);
    });

    test('one-api：Bearer 吃 401 后改用裸 token 重试', () async {
      gateway.on(
        'old.example.com/api/status',
        const _Stub(200, {'success': true, 'data': {'system_name': 'One'}}),
      );
      gateway.onFlaky('old.example.com/api/user/self', const [
        _Stub(401, {'error': 'unauthorized'}),
        _Stub(
          200,
          {
            'success': true,
            'data': {'quota': 500000, 'used_quota': 0, 'request_count': 7},
          },
        ),
      ]);
      final b = await UpstreamBalanceService.fetch(
        remote('http://old.example.com'),
        client: gateway.client(),
      );
      expect(b.available, 1.0);
      expect(b.source, 'New API /api/user/self');
      expect(
        gateway.requests.where((r) => r.endsWith('/api/user/self')).length,
        2,
      );
      // 第一枪带 Bearer（new-api 的习惯），第二枪是裸值（one-api 认这个）
      expect(gateway.authHeaders[1], 'Bearer sk-test');
      expect(gateway.authHeaders[2], 'sk-test');
    });

    test('OpenAI dashboard：上限是美元、usage 是美元分', () async {
      gateway.on(
        'relay.example.com/v1/dashboard/billing/subscription',
        const _Stub(
          200,
          {'object': 'billing_subscription', 'system_hard_limit_usd': 18.0},
        ),
      );
      gateway.on(
        'relay.example.com/v1/dashboard/billing/usage',
        const _Stub(200, {'object': 'bill', 'total_usage': 250.0}),
      );
      final b = await UpstreamBalanceService.fetch(
        remote('http://relay.example.com/v1'),
        client: gateway.client(),
        now: DateTime(2026, 10, 16),
      );
      expect(b.available, 15.5);
      expect(b.details.map((d) => d.kind), [
        BalanceDetailKind.limit,
        BalanceDetailKind.used,
      ]);
      // 时间窗：subscription 没给 start_date → 本月 1 号到今天
      expect(gateway.requests, contains(
        'GET relay.example.com/v1/dashboard/billing/usage'
        '?start_date=2026-10-01&end_date=2026-10-16',
      ));
    });
  });

  group('失败种类', () {
    test('所有接口都 404：该上游没有余额查询接口', () async {
      await expectLater(
        UpstreamBalanceService.fetch(
          remote('http://nothing.example.com/v1'),
          client: gateway.client(),
        ),
        throwsA(
          isA<BalanceException>().having(
            (e) => e.kind,
            'kind',
            BalanceFailure.unsupported,
          ),
        ),
      );
    });

    test('密钥被拒：unauthorized（不是「没有接口」）', () async {
      gateway.on(
        'api.deepseek.com/user/balance',
        const _Stub(401, {'error': 'unauthorized'}),
      );
      await expectLater(
        UpstreamBalanceService.fetch(
          remote('http://api.deepseek.com'),
          client: gateway.client(),
        ),
        throwsA(
          isA<BalanceException>().having(
            (e) => e.kind,
            'kind',
            BalanceFailure.unauthorized,
          ),
        ),
      );
    });

    test('回了非 JSON：badResponse', () async {
      gateway.on(
        'api.deepseek.com/user/balance',
        const _Stub(200, null, raw: '<html>登录网关后台</html>'),
      );
      await expectLater(
        UpstreamBalanceService.fetch(
          remote('http://api.deepseek.com'),
          client: gateway.client(),
        ),
        throwsA(
          isA<BalanceException>().having(
            (e) => e.kind,
            'kind',
            BalanceFailure.badResponse,
          ),
        ),
      );
    });

    test('端口没人听：network（可重试），不谎报「没有接口」', () async {
      // 起一只再关掉，拿到一个确定没人听的端口
      final dead = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = dead.port;
      await dead.close(force: true);
      await expectLater(
        UpstreamBalanceService.fetch(
          remote('http://api.deepseek.com'),
          client: HttpClient()
            ..findProxy = (uri) => 'PROXY 127.0.0.1:$deadPort',
        ),
        throwsA(
          isA<BalanceException>().having(
            (e) => e.kind,
            'kind',
            BalanceFailure.network,
          ),
        ),
      );
    });

    test('本地 TTS 这类没有远端的上游：unsupported', () async {
      await expectLater(
        UpstreamBalanceService.fetch(
          Upstream(id: 'u', name: '本地 TTS', type: UpstreamType.localTts, baseUrl: ''),
          client: gateway.client(),
        ),
        throwsA(
          isA<BalanceException>().having(
            (e) => e.kind,
            'kind',
            BalanceFailure.unsupported,
          ),
        ),
      );
    });
  });
}
