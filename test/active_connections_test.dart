import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/proxy_server.dart';
import 'package:local2api/services/usage_stats.dart';
import 'package:local2api/ui/active_connections_page.dart'
    show formatActiveDuration;

void main() {
  group('请求日志筛选', () {
    RequestLogEntry entry({int status = 200, String? error}) => RequestLogEntry(
      time: DateTime(2026, 10, 16, 10),
      method: 'POST',
      path: '/v1/chat/completions',
      model: 'gpt-alias',
      upstream: 'mock',
      status: status,
      durationMs: 12,
      client: '127.0.0.1',
      error: error,
    );

    test('口径与仪表盘的失败计数一致：4xx/5xx 与带 error 的都算失败', () {
      expect(logEntryFailed(entry(status: 200)), isFalse);
      expect(logEntryFailed(entry(status: 204)), isFalse);
      expect(logEntryFailed(entry(status: 302)), isFalse);
      expect(logEntryFailed(entry(status: 400)), isTrue);
      expect(logEntryFailed(entry(status: 502)), isTrue);
      // 上游连不上时被兜底成 502 并带 error；只有 error 没有码也算失败。
      expect(logEntryFailed(entry(status: 200, error: 'boom')), isTrue);
    });

    test('三种筛选的命中', () {
      final ok = entry(status: 200);
      final bad = entry(status: 502);
      expect(logEntryMatches(ok, LogStatusFilter.all), isTrue);
      expect(logEntryMatches(bad, LogStatusFilter.all), isTrue);
      expect(logEntryMatches(ok, LogStatusFilter.passed), isTrue);
      expect(logEntryMatches(bad, LogStatusFilter.passed), isFalse);
      expect(logEntryMatches(ok, LogStatusFilter.failed), isFalse);
      expect(logEntryMatches(bad, LogStatusFilter.failed), isTrue);
    });
  });

  group('活跃连接明细', () {
    late HttpServer mockUpstream;
    late ProxyServer proxy;
    late ProxyConfig config;

    /// 上游在响应前挂多久（用来在「连接还没结束」时看一眼明细）。
    Duration upstreamDelay = Duration.zero;

    setUp(() async {
      upstreamDelay = Duration.zero;
      mockUpstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      mockUpstream.listen((req) async {
        // 停服务时代理会先掐断客户端连接，mock 这边还在读 body 就会
        // HttpException；这是预期内的收尾竞态，不能让 listen 回调把它
        // 抛成未处理异常（CI 上偶发把「停服务清空明细」判红）。
        try {
          final body =
              jsonDecode(await utf8.decoder.bind(req).join())
                  as Map<String, dynamic>;
          req.response.headers.contentType = ContentType.json;
          if (upstreamDelay > Duration.zero) {
            await Future<void>.delayed(upstreamDelay);
          }
          req.response.write(
            jsonEncode({
              'id': 'cmpl-1',
              'object': 'chat.completion',
              'model': body['model'],
              'choices': [
                {
                  'index': 0,
                  'message': {'role': 'assistant', 'content': 'hi'},
                },
              ],
            }),
          );
          await req.response.close();
        } on HttpException {
          // 客户端（代理）已经关了，什么都不用回。
        } catch (_) {
          try {
            await req.response.close();
          } catch (_) {}
        }
      });

      config = ProxyConfig(listenHost: '127.0.0.1', listenPort: 19293)
        ..upstreams.add(
          Upstream(
            id: 'u1',
            name: 'mock',
            type: UpstreamType.openai,
            baseUrl: 'http://127.0.0.1:${mockUpstream.port}/v1',
            apiKey: 'sk-upstream',
            models: [ModelEntry(publicName: 'gpt-alias', target: 'qwen2.5-7b')],
          ),
        )
        ..apiKeys.add(ApiKeyEntry(id: 'k1', name: 'test', key: 'sk-client'));

      proxy = ProxyServer(configProvider: () => config);
      await proxy.start();
    });

    tearDown(() async {
      await proxy.stop();
      await mockUpstream.close(force: true);
    });

    Future<void> postChat() async {
      final client = HttpClient();
      final req = await client.openUrl(
        'POST',
        Uri.parse('http://127.0.0.1:19293/v1/chat/completions'),
      );
      req.headers.set('authorization', 'Bearer sk-client');
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'model': 'gpt-alias', 'stream': false}));
      final res = await req.close();
      await res.drain<void>();
      client.close();
    }

    /// 发出请求但不等它回来（要看「请求进行中」的状态）。
    ///
    /// 必须自己吞掉异常：服务被停掉 / 响应被掐断时客户端侧会抛
    /// HttpException，不接住的未处理 Future 会被算成测试失败。
    void postChatInBackground() {
      unawaited(postChat().catchError((Object _) {}));
    }

    Future<void> waitFor(
      bool Function() cond, {
      Duration timeout = const Duration(seconds: 5),
    }) async {
      final sw = Stopwatch()..start();
      while (!cond() && sw.elapsed < timeout) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    test('请求期间能查到客户端 IP 与模型，结束后归零', () async {
      upstreamDelay = const Duration(milliseconds: 400);
      expect(proxy.activeSessions.value, isEmpty);

      postChatInBackground();
      // 会话是「一进来就登记」，模型要等请求体解析完（转发给上游之前）才回填
      // —— 中间有个很短的窗口，等模型到位再断言，否则会撞出一条假失败。
      await waitFor(
        () => proxy.activeSessions.value.any((s) => s.model == 'gpt-alias'),
      );

      final session = proxy.activeSessions.value.single;
      expect(session.clientIp, '127.0.0.1');
      expect(session.method, 'POST');
      expect(session.path, '/v1/chat/completions');
      // 模型在转发给上游之前就回填了：SSE 挂着时页面上也看得到。
      expect(session.model, 'gpt-alias');
      // 明细与仪表盘那个计数保持同步。
      expect(proxy.activeConnections.value, 1);

      await waitFor(() => proxy.activeSessions.value.isEmpty);
      expect(proxy.activeConnections.value, 0);
    });

    test('并发请求各自一条，互不影响', () async {
      upstreamDelay = const Duration(milliseconds: 400);
      postChatInBackground();
      postChatInBackground();
      await waitFor(() => proxy.activeSessions.value.length == 2);
      expect(proxy.activeConnections.value, 2);

      await waitFor(() => proxy.activeSessions.value.isEmpty);
      expect(proxy.activeConnections.value, 0);
    });

    test('停服务清空明细', () async {
      upstreamDelay = const Duration(milliseconds: 400);
      postChatInBackground();
      await waitFor(() => proxy.activeSessions.value.isNotEmpty);
      await proxy.stop();
      expect(proxy.activeSessions.value, isEmpty);
      expect(proxy.activeConnections.value, 0);
      // 服务停掉时那条请求会被掐断 —— 客户端侧的异常与断言无关，等它落地
      // 再结束测试，否则未处理的 Future 会算测试失败。
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
  });

  group('活跃连接时长显示', () {
    test('不足一小时只给 分:秒', () {
      expect(formatActiveDuration(const Duration(seconds: 7)), '0:07');
      expect(
        formatActiveDuration(const Duration(minutes: 12, seconds: 7)),
        '12:07',
      );
    });

    test('超过一小时才带小时，分钟补两位', () {
      expect(
        formatActiveDuration(const Duration(hours: 1, minutes: 5, seconds: 3)),
        '1:05:03',
      );
    });
  });

  group('当月判定', () {
    test('startOfMonth 只留年月', () {
      expect(
        UsageStats.startOfMonth(DateTime(2026, 10, 16, 23, 59)),
        DateTime(2026, 10),
      );
    });

    test('isCurrentMonth 认年月，跨年也分得开', () {
      final now = DateTime(2026, 10, 16);
      expect(UsageStats.isCurrentMonth(DateTime(2026, 10), now: now), isTrue);
      expect(UsageStats.isCurrentMonth(DateTime(2026, 9), now: now), isFalse);
      expect(UsageStats.isCurrentMonth(DateTime(2025, 10), now: now), isFalse);
    });
  });
}
