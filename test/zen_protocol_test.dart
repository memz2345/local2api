import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/models/builtin_profiles.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:local2api/services/zen/zen_protocol.dart';

void main() {
  group('车道归属', () {
    test('带 -free 的、以及不带后缀但确实免密的那条都算免费车道', () {
      expect(zenIsFreeLane('mimo-v2.6-flash-free'), isTrue);
      expect(zenIsFreeLane('space-bunny-free'), isTrue);
      // union-alpha 不带 -free 后缀，上游确认它也免密 —— 早先的目录就是漏了它。
      expect(zenIsFreeLane('union-alpha'), isTrue);
      expect(zenIsFreeLane('gpt-5'), isFalse);
    });

    test('alwaysFree 白名单含 big-pickle（上游实时清单确认免密）', () {
      // 2026-10-22 上游 /zen/v1/models 里 big-pickle 仍然在；之前因为
      // zen-gate 目录缺它被误摘，冷启动会漏掉一条可用车道。
      expect(zenIsFreeLane('big-pickle'), isTrue);
      // 后缀判定仍然覆盖所有真正带 free 的 id，不依赖白名单。
      expect(zenIsFreeLane('ling-3.0-flash-fin-free'), isTrue);
      expect(zenIsFreeLane('nemotron-3.5-lightning-free'), isTrue);
      expect(zenIsFreeLane('muse-spark-1.2-contributor-free'), isTrue);
    });

    test('内置兜底目录里的每一条都被自己认成可用免密车道', () {
      // 目录与白名单必须自洽：兜底表里出现一条 zenIsFreeLane 判 false 的 id，
      // 探测阶段就会被 zenFilterUsableLanes 摘掉，等于白占一个回退位。
      expect(kZenFreeLanes, isNotEmpty);
      for (final lane in kZenFreeLanes) {
        expect(zenIsFreeLane(lane), isTrue, reason: lane);
        expect(zenFilterUsableLanes([lane]), [lane], reason: lane);
      }
      // muse-spark 系走 responses，其余走 chat；没有一条是判定模型。
      expect(zenWireFor('mimo-v2.6-flash-free'), ZenWire.chat);
      expect(zenWireFor('space-bunny-free'), ZenWire.chat);
      expect(
        zenWireFor('muse-spark-1.3-contributor-free'),
        ZenWire.responses,
      );
      for (final lane in kZenFreeLanes) {
        expect(zenWireFor(lane), isNot(ZenWire.systemone), reason: lane);
      }
    });

    test('(档位) 后缀不参与判定', () {
      expect(zenBaseId('mimo-v2.6-flash-free (high)'), 'mimo-v2.6-flash-free');
      expect(zenIsFreeLane('mimo-v2.6-flash-free (high)'), isTrue);
      expect(zenWireFor('union-alpha (deep)'), ZenWire.messages);
    });

    test('上游清单 → 只剩能当聊天模型用的车道，并按基础 id 去重', () {
      final filtered = zenFilterUsableLanes([
        'gpt-5',
        'mimo-v2.6-flash-free',
        'union-alpha',
        'jev-1.13-free',
        'mimo-v2.6-flash-free (high)',
        ' muse-spark-1.3-contributor-free ',
      ]);
      expect(filtered, [
        'mimo-v2.6-flash-free',
        'union-alpha',
        'muse-spark-1.3-contributor-free',
      ]);
    });
  });

  group('按模型分流的线协议', () {
    test('多数车道走 chat，muse-spark 走 responses，union-alpha 走 messages', () {
      expect(zenWireFor('space-bunny-free'), ZenWire.chat);
      expect(zenWireFor('deepseek-v4-flash-free'), ZenWire.chat);
      expect(zenWireFor('muse-spark-1.3-contributor-free'), ZenWire.responses);
      // 同系新车道靠名字前缀就能认出来，不用每加一条改一次代码。
      expect(zenWireFor('muse-spark-1.4-contributor-free'), ZenWire.responses);
      expect(zenWireFor('union-alpha'), ZenWire.messages);
      expect(zenWireFor('jev-1.13-free'), ZenWire.systemone);
    });

    test('判定模型不该接聊天请求', () {
      expect(zenWireFor('jev-2-free'), ZenWire.systemone);
    });

    test('线协议拼出的端点确实是 /zen/v1/{responses,messages}', () {
      final u = Upstream(
        id: 'z',
        name: 'zen',
        baseUrl: 'https://opencode.ai/zen/v1',
      );
      expect(
        ProxyServer.buildUpstreamUri(
          u,
          zenClientPathFor(ZenWire.responses),
          '',
        ).toString(),
        'https://opencode.ai/zen/v1/responses',
      );
      expect(
        ProxyServer.buildUpstreamUri(
          u,
          zenClientPathFor(ZenWire.messages),
          '',
        ).toString(),
        'https://opencode.ai/zen/v1/messages',
      );
      expect(
        ProxyServer.buildUpstreamUri(
          u,
          zenClientPathFor(ZenWire.chat),
          '',
        ).toString(),
        'https://opencode.ai/zen/v1/chat/completions',
      );
    });
  });

  group('网关认出桌面客户端的那组头', () {
    test('六个指纹头一个都不能少', () {
      final headers = zenHeaders(
        session: 'ses_x',
        requestId: 'msg_y',
        stream: true,
      );
      expect(headers['authorization'], 'Bearer public');
      expect(headers['user-agent'], kZenClientUa);
      expect(headers['x-opencode-client'], 'desktop');
      expect(headers['x-opencode-session'], 'ses_x');
      expect(headers['x-opencode-request'], 'msg_y');
      expect(headers['x-opencode-project'], 'global');
      expect(headers['accept'], 'text/event-stream');
    });

    test('非流式时 accept 跟着换', () {
      final headers = zenHeaders(
        session: 'ses_x',
        requestId: 'msg_y',
        stream: false,
      );
      expect(headers['accept'], '*/*');
      expect(
        zenHeaders(
          session: 's',
          requestId: 'r',
          stream: false,
          accept: 'application/json',
        )['accept'],
        'application/json',
      );
    });

    test('UA 版本号不能低于网关下限', () {
      final version = kZenClientUa.split('/').last.split('.').map(int.parse).toList();
      expect(version[0], 1);
      expect(version[1], greaterThanOrEqualTo(17));
    });
  });

  group('上游拒绝的归类', () {
    test('免密指纹缺失 ≠ 地区受限 ≠ 额度打满 ≠ 模型坏了', () {
      expect(
        zenClassify(403, '{"error":{"message":"FreeTierError: usage within OpenCode only"}}').code,
        ZenFailureCode.restricted,
      );
      expect(
        zenClassify(403, '{"error":{"message":"RegionError: not available in your country"}}').code,
        ZenFailureCode.region,
      );
      expect(
        zenClassify(429, '{"error":{"message":"FreeUsageLimitError"}}').code,
        ZenFailureCode.throttled,
      );
      expect(
        zenClassify(400, '{"error":{"message":"Model is unavailable"}}').code,
        ZenFailureCode.unavailable,
      );
      expect(zenClassify(401, 'nope').code, ZenFailureCode.credential);
      expect(zenClassify(503, 'bad gateway').code, ZenFailureCode.server);
    });

    test('payload 模式先于状态码：前置代理那句通用 503 不该被读成模型没了', () {
      expect(
        zenClassify(503, 'Service Unavailable').code,
        ZenFailureCode.server,
      );
      // 5xx 是服务端故障，不是这个模型的判决 —— 不该因此摘掉车道。
      expect(
        zenClassify(500, '{"error":{"message":"model is unavailable"}}').code,
        ZenFailureCode.server,
      );
      expect(
        zenClassify(404, '{"error":{"message":"Endpoint is unavailable"}}').code,
        ZenFailureCode.unavailable,
      );
    });

    test('车道下架（401 ModelError / 410 deprecated）算不可用，不算凭据问题', () {
      // 免密车道上下架很频繁：这两个都是「这个 id 没了」，
      // 归到 unavailable 才能被探测摘掉、被路由跳过去。
      expect(
        zenClassify(
          401,
          '{"type":"error","error":{"type":"ModelError",'
              '"message":"Model mimo-v2.5-free is not supported"}}',
        ).code,
        ZenFailureCode.unavailable,
      );
      expect(
        zenClassify(
          410,
          '{"error":{"type":"ModelDeprecated","message":"Model exo-free has been deprecated."}}',
        ).code,
        ZenFailureCode.unavailable,
      );
      // 没点名模型的 401 仍然是凭据问题。
      expect(zenClassify(401, 'nope').code, ZenFailureCode.credential);
      expect(
        zenClassify(403, '{"error":{"message":"FreeTierError"}}').code,
        ZenFailureCode.restricted,
      );
    });

    test('429 没带 Retry-After 时只冷却 10 秒，不是 60 秒', () {
      // Bearer public 是全球共享凭据，429 只代表此刻拥挤（zen-gate
      // internal/lane/throttle.go:29-46：92 次 throttle 事件里最短 0.6 秒
      // 恢复）。冷却 60 秒会让整条 zen-free 显示成一分钟不可用 —— 那就是
      // 用户体感的「又失效了」。
      expect(zenClassify(429, 'slow down').retryAfterSec, 10);
      expect(
        zenClassify(429, 'slow down').retryAfterSec,
        kZenThrottleDefaultSec,
      );
      // 上游给了 Retry-After 就听它的。
      expect(
        zenClassify(429, 'slow down', retryAfterSec: 12).retryAfterSec,
        12,
      );
      expect(
        zenClassify(429, 'FreeUsageLimitError', retryAfterSec: 120)
            .retryAfterSec,
        120,
      );
    });

    test('前置代理的 HTML 错误页归 client 类，优先于 401/403 判定', () {
      // WAF 的 HTML 403 不是凭据失效：请求根本没被送到任何模型面前。
      // 若按状态码判就会误读成 credential，把整条车道标红。
      const page = '<!doctype html>\n<html><head><title>403 Forbidden</title>'
          '</head><body>nginx</body></html>';
      final waf = zenClassify(403, page);
      expect(waf.code, ZenFailureCode.client);
      expect(waf.message, contains('HTML'));
      expect(waf.message, contains('WAF'));
      expect(waf.message, contains('403'), reason: '要点名状态码');
      expect(waf.message, isNot(contains('nginx')), reason: '页面本身是噪音，不许回灌');

      // 413（请求体过大）同样归 client，且文案要提示很可能是体积。
      final tooBig = zenClassify(
        413,
        '<html>\n<head><title>413 Request Entity Too Large</title></head></html>',
      );
      expect(tooBig.code, ZenFailureCode.client);
      expect(tooBig.message, contains('请求体大小'));

      // `<html …>` 开头的变体、以及前置代理自己那句转述都认。
      expect(
        zenClassify(502, '  <html lang="en"><body>bad gw</body></html>').code,
        ZenFailureCode.client,
      );
      expect(
        zenClassify(
          502,
          '{"error":"upstream responded with an HTML error page"}',
        ).code,
        ZenFailureCode.client,
      );
      // 但 region / quota 的 payload 判定仍然优先（它们说的是更具体的事）。
      expect(
        zenClassify(
          403,
          '<html><body>RegionError: not available in your country</body></html>',
        ).code,
        ZenFailureCode.region,
      );
      expect(
        zenClassify(429, '<html><body>rate limit exceeded</body></html>').code,
        ZenFailureCode.throttled,
      );
    });

    test('其余 4xx 归 client 类，不落 server —— 否则会在整条回退链上连环重试', () {
      // 重放同一份 body 必然得到同一句拒绝，换道只是白烧延迟。
      for (final status in [405, 406, 409, 411, 413, 415, 418, 428, 451]) {
        expect(
          zenClassify(status, 'some refusal').code,
          ZenFailureCode.client,
          reason: 'HTTP $status',
        );
      }
      // 408 / 425 是例外：网关自己的时序问题，重发可能给出不同结果。
      expect(zenClassify(408, 'request timeout').code, ZenFailureCode.server);
      expect(zenClassify(425, 'too early').code, ZenFailureCode.server);
      // 5xx 仍然是 server。
      expect(zenClassify(500, 'boom').code, ZenFailureCode.server);
      expect(zenClassify(502, 'bad gateway').code, ZenFailureCode.server);
      // 没有状态码（流内错误帧）不乱归 client。
      expect(zenClassify(null, 'mid-stream error').code, ZenFailureCode.server);
    });

    test('既有的分档不被新分支抢走', () {
      // 404/400/422 仍然是 unavailable（车道下架要能被探测摘掉），
      // 401/403 仍然是 credential，403+FreeTierError 仍然是 restricted。
      expect(zenClassify(404, 'not found').code, ZenFailureCode.unavailable);
      expect(zenClassify(400, 'bad json').code, ZenFailureCode.unavailable);
      expect(zenClassify(422, 'unprocessable').code, ZenFailureCode.unavailable);
      expect(zenClassify(401, 'nope').code, ZenFailureCode.credential);
      expect(zenClassify(403, 'nope').code, ZenFailureCode.credential);
      expect(
        zenClassify(403, '{"error":{"message":"FreeTierError"}}').code,
        ZenFailureCode.restricted,
      );
    });
  });

  group('Zen 网关识别', () {
    test('host 命中且路径首段是 zen 才算', () {
      expect(
        Upstream(
          id: 'a',
          name: 'a',
          baseUrl: 'https://opencode.ai/zen/v1',
        ).isZenGateway,
        isTrue,
      );
      expect(
        Upstream(
          id: 'b',
          name: 'b',
          baseUrl: 'https://opencode.ai/v1',
        ).isZenGateway,
        isFalse,
      );
      expect(
        Upstream(
          id: 'c',
          name: 'c',
          baseUrl: 'http://192.168.1.10:8080/v1',
        ).isZenGateway,
        isFalse,
      );
    });

    test('测试白名单把回环 mock 变成网关', () {
      zenGatewayHosts.add('127.0.0.1');
      addTearDown(() => zenGatewayHosts.remove('127.0.0.1'));
      expect(
        Upstream(
          id: 'd',
          name: 'd',
          baseUrl: 'http://127.0.0.1:9/zen/v1',
        ).isZenGateway,
        isTrue,
      );
    });
  });
}
