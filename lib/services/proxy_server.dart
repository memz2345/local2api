import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'network_utils.dart';
import 'model_schedule.dart';
import '../models/proxy_config.dart';
import '../models/thinking_level.dart';
import 'anthropic/anthropic_upstream.dart';
import 'usage_stats.dart';
import 'zen/zen_ids.dart';
import 'zen/zen_plan.dart';
import 'zen/zen_protocol.dart';
import 'zen/zen_stream.dart';
import 'tts/tts_engine.dart';
import 'tts/tts_model_kind.dart';
import 'tts/tts_settings.dart';
import 'tts/tts_speech_service.dart';

/// 一条请求日志。
class RequestLogEntry {
  final DateTime time;
  final String method;
  final String path;
  final String model;
  final String upstream;
  final int status;
  final int durationMs;
  final String client;
  final String? error;

  RequestLogEntry({
    required this.time,
    required this.method,
    required this.path,
    required this.model,
    required this.upstream,
    required this.status,
    required this.durationMs,
    required this.client,
    this.error,
  });
}

/// 请求日志的筛选口径。
///
/// 「失败」与仪表盘的 `totalErrors` 自增口径对齐：`_reject` / 上游错误 /
/// 异常兜底都算，只有真正返回出去的（含 204 预检、3xx）算「通过」。
enum LogStatusFilter { all, passed, failed }

/// 一条请求是不是「失败」。
bool logEntryFailed(RequestLogEntry e) => e.status >= 400 || e.error != null;

/// 筛选判定：[LogStatusFilter.all] 不过滤。
bool logEntryMatches(RequestLogEntry e, LogStatusFilter f) => switch (f) {
  LogStatusFilter.all => true,
  LogStatusFilter.passed => !logEntryFailed(e),
  LogStatusFilter.failed => logEntryFailed(e),
};

/// 正在处理中的连接（活跃连接页的一行）。
///
/// 以前只有一个「当前有几个连接」的计数，看不出是谁在连、在跑哪个模型。
/// 这里在 `_handle` 的进出两端各挂一次，把客户端 IP / 方法 / 路径记下来；
/// `model` 要等 body 解析完才知道，所以是可变字段 —— 请求体解析出模型
/// 的那一刻回填，SSE 长连接挂着时页面上就能看到模型名。
class ActiveConnection {
  ActiveConnection({
    required this.clientIp,
    required this.method,
    required this.path,
    required this.startedAt,
  });

  /// 客户端 IP（已剥掉 `::ffff:` 前缀）。
  final String clientIp;
  final String method;
  final String path;
  final DateTime startedAt;

  /// 请求里的模型名；`/health`、`/v1/models` 这类没有模型的用 `-`。
  String model = '-';
}

/// 服务运行状态。
enum ServerState { stopped, starting, running, error }

/// 响应头：本次请求**真正接住**的那条车道（上游模型名）。
///
/// 为什么需要：容灾路由（如 `zen-free`）对外是一个名字、对内是一串候选，
/// 响应体里的 `model` 回显的仍是那个对外名（转译器按 publicName 填的），
/// 所以客户端从响应体里看不出到底是谁在答。这个头把真实车道透出来，
/// 对话模拟页据此显示「响应模型」，真客户端也能自己读。
///
/// 不带 `x-` 之外的语义、也不进 body：不改动任何响应字节，
/// 老客户端的解析完全不受影响。
const String kServedLaneHeader = 'x-local2api-lane';

/// 入站标记：这条请求是 App 内的「对话模拟」发出的。
///
/// 模拟器走的是真实 HTTP（要连路由、回退、日志一起过一遍），所以在代理
/// 侧它跟外部客户端长得一模一样 —— 峰谷策略这类「限制外部使用」的门禁
/// 必须靠这个头把它摘出来，否则调试窗口一开就自己把自己挡在门外了。
/// CIDR 与鉴权不受它影响：模拟请求本来就带正确密钥、也来自回环地址。
const String kSimRequestHeader = 'x-local2api-sim';

/// 代理服务器：把 OpenAI 兼容请求按模型路由到上游并转发。
class ProxyServer {
  HttpServer? _server;
  HttpClient? _client;

  /// 每次处理请求时取最新配置（UI 改完立即生效，不用重启）。
  final ProxyConfig Function() configProvider;
  final void Function(RequestLogEntry)? onLog;

  final ValueNotifier<ServerState> state = ValueNotifier(ServerState.stopped);
  final ValueNotifier<String?> lastError = ValueNotifier(null);
  final ValueNotifier<int> totalRequests = ValueNotifier(0);
  final ValueNotifier<int> totalErrors = ValueNotifier(0);
  final ValueNotifier<int> activeConnections = ValueNotifier(0);
  final ValueNotifier<List<RequestLogEntry>> logs = ValueNotifier([]);

  /// 活跃连接的**明细**（IP / 模型 / 已持续时长）。`activeConnections`
  /// 这个计数保留不动（仪表盘的卡片、别处的语义都还在用），每次
  /// [activeSessions] 变动时同步成它的长度。
  final ValueNotifier<List<ActiveConnection>> activeSessions = ValueNotifier(
    const [],
  );

  static const int _maxLogs = 300;
  static const int _maxBodyBytes = 64 * 1024 * 1024;

  /// 取「现在」的钩子：峰谷策略按本地时间判定，测试要能钉住钟点。
  DateTime Function() nowProvider = DateTime.now;

  ProxyServer({required this.configProvider, this.onLog});

  bool get isRunning => state.value == ServerState.running;

  /// 当前实际绑定的地址与端口（热重启判断用）。
  String _boundHost = '';
  int _boundPort = 0;

  String get boundHost => _boundHost;
  int get boundPort => _boundPort;

  Future<void> start() async {
    if (isRunning || state.value == ServerState.starting) return;
    state.value = ServerState.starting;
    lastError.value = null;
    final config = configProvider();
    try {
      _client?.close(force: true);
      _client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15)
        ..autoUncompress = false;
      final server = await HttpServer.bind(
        InternetAddress(config.listenHost),
        config.listenPort,
        shared: false,
      );
      _server = server;
      _boundHost = config.listenHost;
      _boundPort = config.listenPort;
      server.listen(_handle, cancelOnError: false);
      state.value = ServerState.running;
    } catch (e) {
      state.value = ServerState.error;
      lastError.value = e.toString();
      rethrow;
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    state.value = ServerState.stopped;
    try {
      await server?.close(force: true);
    } catch (_) {}
    _client?.close(force: true);
    _client = null;
    _clearSessions();
  }

  // ------------------------------------------------------------------

  Future<void> _handle(HttpRequest req) async {
    final sw = Stopwatch()..start();
    // 活跃连接明细：进站建条目、出站移除。SSE 的响应流在 `_dispatch`
    // 里一直挂着，所以这条目会活到客户端断开为止。
    final session = ActiveConnection(
      clientIp: _clientIp(req),
      method: req.method,
      path: req.uri.path,
      startedAt: DateTime.now(),
    );
    _addSession(session);
    RequestLogEntry log = RequestLogEntry(
      time: DateTime.now(),
      method: req.method,
      path: req.uri.path,
      model: '-',
      upstream: '-',
      status: HttpStatus.badGateway,
      durationMs: 0,
      client: _clientIp(req),
      error: null,
    );
    try {
      log = await _dispatch(
        req,
        sw,
        onModel: (m) => _setSessionModel(session, m),
      );
    } catch (e) {
      totalErrors.value++;
      try {
        req.response.statusCode = HttpStatus.badGateway;
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          _errorJson('Upstream request failed: $e', type: 'api_error'),
        );
        await req.response.close();
      } catch (_) {}
      log = RequestLogEntry(
        time: DateTime.now(),
        method: req.method,
        path: req.uri.path,
        model: '-',
        upstream: '-',
        status: HttpStatus.badGateway,
        durationMs: sw.elapsedMilliseconds,
        client: _clientIp(req),
        error: e.toString(),
      );
    } finally {
      _removeSession(session);
      final next = [log, ...logs.value];
      if (next.length > _maxLogs) next.removeRange(_maxLogs, next.length);
      logs.value = next;
      onLog?.call(log);
    }
  }

  // ------------------------------------------------------------------
  // 活跃连接明细
  //
  // 列表按 [ActiveConnection.startedAt] 升序（老的在前），页面直接按序渲染。
  // 三个入口都往 [activeConnections] 同步长度，计数与明细不会对不上。

  void _addSession(ActiveConnection session) {
    activeSessions.value = [...activeSessions.value, session];
    activeConnections.value = activeSessions.value.length;
  }

  void _removeSession(ActiveConnection session) {
    final next = activeSessions.value
        .where((s) => !identical(s, session))
        .toList();
    if (next.length == activeSessions.value.length) return;
    activeSessions.value = next;
    activeConnections.value = next.length;
  }

  void _setSessionModel(ActiveConnection session, String model) {
    if (session.model == model) return;
    session.model = model;
    // 改的是条目内部字段，得换一次列表实例才会通知出去。
    activeSessions.value = [...activeSessions.value];
  }

  /// 服务停了就不该再有「活跃连接」。
  void _clearSessions() {
    activeSessions.value = const [];
    activeConnections.value = 0;
  }

  /// [onModel]：请求体解析出模型名的那一刻回调（活跃连接页要显示它）。
  /// 转发给上游之前一定会走到，SSE 挂着时也能看到模型。
  Future<RequestLogEntry> _dispatch(
    HttpRequest req,
    Stopwatch sw, {
    ValueChanged<String>? onModel,
  }) async {
    final config = configProvider();
    final clientIp = _clientIp(req);
    final path = req.uri.path;
    final clientAddr = req.connectionInfo?.remoteAddress;

    // CORS 预检直接放行
    if (req.method == 'OPTIONS' && config.corsEnabled) {
      _applyCors(req.response, config);
      req.response.statusCode = HttpStatus.noContent;
      await req.response.close();
      return _log(req, '-', '-', HttpStatus.noContent, sw, clientIp, null);
    }

    // IP 访问规则（先命中先生效；为空=全部放行）
    if (!_allowedByRules(config, clientAddr)) {
      totalErrors.value++;
      return _reject(
        req,
        sw,
        clientIp,
        HttpStatus.forbidden,
        'Access denied for $clientIp',
        'permission_error',
        '-',
      );
    }

    // 健康检查免鉴权
    if (path == '/health') {
      _applyCors(req.response, config);
      req.response.headers.contentType = ContentType.json;
      req.response.write('{"status":"ok"}');
      await req.response.close();
      return _log(req, '-', '-', HttpStatus.ok, sw, clientIp, null);
    }

    // 鉴权：已配置的密钥里必须命中一个；没配置密钥 = 不设防（UI 有提醒）
    final keys = [
      for (final k in config.apiKeys)
        if (k.enabled && k.key.isNotEmpty) k.key,
    ];
    if (keys.isNotEmpty && !_authorized(req, keys)) {
      totalErrors.value++;
      return _reject(
        req,
        sw,
        clientIp,
        HttpStatus.unauthorized,
        'Invalid or missing API key',
        'authentication_error',
        '-',
      );
    }

    if (!path.startsWith('/v1/')) {
      totalErrors.value++;
      return _reject(
        req,
        sw,
        clientIp,
        HttpStatus.notFound,
        'Only /v1/* endpoints are proxied',
        'invalid_request_error',
        '-',
      );
    }

    // 模型列表：聚合所有启用上游的暴露模型
    if (path == '/v1/models' && req.method == 'GET') {
      return _serveModels(req, sw, clientIp, config);
    }

    // 其余 /v1/* 转发。需要先读 body 才能知道 model 归哪个上游。
    final Uint8List body;
    try {
      body = await _readBody(req);
    } catch (_) {
      totalErrors.value++;
      return _reject(
        req,
        sw,
        clientIp,
        HttpStatus.badRequest,
        'Failed to read request body',
        'invalid_request_error',
        '-',
      );
    }

    // 解析 model 字段 + 路由
    String model = '-';
    Map<String, dynamic>? json;
    final contentType = req.headers.contentType;
    if (contentType != null &&
        contentType.primaryType == 'application' &&
        contentType.subType.contains('json') &&
        body.isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(body));
        if (decoded is Map<String, dynamic>) json = decoded;
      } catch (_) {}
    }
    if (json?.containsKey('model') == true) {
      model = '${json!['model']}';
    }
    onModel?.call(model);

    final _Route? route = _resolveRoute(config, model);
    if (route == null) {
      totalErrors.value++;
      final msg = model == '-'
          ? 'No enabled upstream available'
          : 'Model "$model" is not exposed by this proxy';
      return _reject(
        req,
        sw,
        clientIp,
        HttpStatus.notFound,
        msg,
        model == '-' ? 'api_error' : 'invalid_request_error',
        model,
      );
    }
    // 峰谷时段：模型级 / 模型组级的「星期 + 小时」窗口。
    // 对话模拟自带 [kSimRequestHeader]，一律放行 —— 调试窗口不能被自己挡住。
    final isSim = req.headers.value(kSimRequestHeader) != null;
    if (!isSim) {
      final decision = scheduleAllows(
        rules: config.scheduleRules,
        model: model,
        groupId: route.upstream.managedBy,
        now: nowProvider(),
      );
      if (!decision.allowed) {
        totalErrors.value++;
        return _reject(
          req,
          sw,
          clientIp,
          HttpStatus.forbidden,
          decision.reason,
          'permission_error',
          model,
        );
      }
    }
    final (upstream, targets) = route.asPair();

    // 本地 TTS 上游只接 /v1/audio/speech：在设备上直接合成，不转发。
    if (upstream.type == UpstreamType.localTts) {
      if (path != '/v1/audio/speech') {
        totalErrors.value++;
        return _reject(
          req,
          sw,
          clientIp,
          HttpStatus.badRequest,
          'Local TTS upstream only serves /v1/audio/speech',
          'invalid_request_error',
          model,
        );
      }
      final input = json?['input'];
      if (input is! String || input.trim().isEmpty) {
        totalErrors.value++;
        return _reject(
          req,
          sw,
          clientIp,
          HttpStatus.badRequest,
          'Missing "input" text for /v1/audio/speech',
          'invalid_request_error',
          model,
        );
      }
      return _serveLocalTts(req, sw, clientIp, model, upstream, input.trim());
    }

    // audio 模态上游（MiMo TTS 等）：/v1/audio/speech 翻译成
    // chat.completions 语音请求。入参必须带 input 文本。
    if (path == '/v1/audio/speech' &&
        upstream.modality == UpstreamModality.audio) {
      final input = json?['input'];
      if (input is! String || input.trim().isEmpty) {
        totalErrors.value++;
        return _reject(
          req,
          sw,
          clientIp,
          HttpStatus.badRequest,
          'Missing "input" text for /v1/audio/speech',
          'invalid_request_error',
          model,
        );
      }
    }

    // 每个候选车道改写出一份转发方案；不回退时就是单元素列表，行为与原来一致。
    final hops = _planHops(req, upstream, json, targets, body, model);
    if (hops == null) {
      // 只剩判定模型那类车道：它们不产文本，打过来也是白打。
      totalErrors.value++;
      final reasons = targets
          .map(zenLaneRejection)
          .whereType<String>()
          .toList();
      return _reject(
        req,
        sw,
        clientIp,
        HttpStatus.badRequest,
        reasons.isEmpty ? 'No usable lane for model "$model"' : reasons.first,
        'invalid_request_error',
        model,
      );
    }

    final outcome = await _forwardWithFallback(req, config, upstream, hops);
    if (!outcome.served) {
      // 所有候选都在拿到响应头之前就失败了：客户端还没收到任何字节
      totalErrors.value++;
      return _reject(
        req,
        sw,
        clientIp,
        outcome.status,
        outcome.error ?? 'upstream unavailable',
        'api_error',
        model,
      );
    }
    if (outcome.status >= 400) totalErrors.value++;
    // 命中回退时把真正服务的车道标出来，日志里能看出是哪条免费车道接的
    final lane = outcome.lane == null || outcome.lane == model
        ? upstream.name
        : '${upstream.name} · ${outcome.lane}';
    return _log(req, model, lane, outcome.status, sw, clientIp, outcome.error);
  }

  // ------------------------------------------------------------------

  RequestLogEntry _log(
    HttpRequest req,
    String model,
    String upstream,
    int status,
    Stopwatch sw,
    String client,
    String? error,
  ) {
    return RequestLogEntry(
      time: DateTime.now(),
      method: req.method,
      path: req.uri.path,
      model: model,
      upstream: upstream,
      status: status,
      durationMs: sw.elapsedMilliseconds,
      client: client,
      error: error,
    );
  }

  String _clientIp(HttpRequest req) {
    final addr = req.connectionInfo?.remoteAddress;
    if (addr == null) return '-';
    var a = addr.address;
    if (a.startsWith('::ffff:')) a = a.substring(7);
    return a;
  }

  bool _allowedByRules(ProxyConfig config, InternetAddress? addr) {
    final rules = [
      for (final r in config.cidrRules)
        if (r.enabled) r,
    ];
    if (rules.isEmpty) return true;
    if (addr == null) return false;
    // 先命中先生效
    for (final r in rules) {
      if (NetworkUtils.cidrMatches(r.cidr, addr)) return r.allow;
    }
    return false;
  }

  bool _authorized(HttpRequest req, List<String> keys) {
    final token = _clientToken(req);
    if (token == null) return false;
    return keys.contains(token);
  }

  /// 请求里带的那个密钥（`Authorization: Bearer xxx` 或 `x-api-key`）。
  /// 两个都没有返回 null。
  String? _clientToken(HttpRequest req) {
    final auth = req.headers.value(HttpHeaders.authorizationHeader);
    if (auth != null) {
      final raw = auth.toLowerCase().startsWith('bearer ')
          ? auth.substring(7)
          : auth;
      final token = raw.trim();
      if (token.isNotEmpty) return token;
    }
    final xKey = req.headers.value('x-api-key')?.trim();
    if (xKey != null && xKey.isNotEmpty) return xKey;
    return null;
  }

  /// 这次调用拿的是哪一把本机 API Key —— 只把它对到某一把，
  /// 记账里存的是 id / 备注名 / 脱敏串，**完整密钥不进账本**。
  ///
  /// 没配鉴权、或请求压根没带密钥 → 全空，统计页算作「未鉴权」那一档。
  _CallerKey _callerKey(HttpRequest req, ProxyConfig config) {
    final token = _clientToken(req);
    if (token == null) return const _CallerKey();
    for (final k in config.apiKeys) {
      if (k.key.isNotEmpty && k.key.trim() == token) {
        return _CallerKey(
          id: k.id,
          name: k.name,
          label: UsageStats.maskKey(token),
        );
      }
    }
    // 到得了这儿说明鉴权是关着的（空 key 列表）——没有可以归属的身份，
    // 就别把陌生 token 的形状也记下来，统一按未鉴权归。
    return const _CallerKey();
  }

  /// 找到 model 对应的 (上游, 依次尝试的上游模型名 + 命中的模型条目)。
  /// 峰谷策略要按它的归属模型组（[Upstream.managedBy]）判定。
  _Route? _resolveRoute(ProxyConfig config, String model) {
    final enabled = [
      for (final u in config.upstreams)
        if (u.enabled && (u.type.isLocal || u.baseUrl.trim().isNotEmpty)) u,
    ];
    if (enabled.isEmpty) return null;
    if (model == '-') {
      // 无 model 字段的请求（如 /v1/files）走第一个启用的上游，不改写
      return _Route(enabled.first, const [], null);
    }
    for (final u in enabled) {
      for (final m in u.models) {
        if (!m.enabled) continue;
        if (m.publicName == model) return _Route(u, m.attempts, m);
      }
    }
    // 大小写兜底
    for (final u in enabled) {
      for (final m in u.models) {
        if (!m.enabled) continue;
        if (m.publicName.toLowerCase() == model.toLowerCase()) {
          return _Route(u, m.attempts, m);
        }
      }
    }
    return null;
  }

  Future<Uint8List> _readBody(HttpRequest req) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in req) {
      builder.add(chunk);
      if (builder.length > _maxBodyBytes) {
        throw Exception('Request body too large');
      }
    }
    return builder.takeBytes();
  }

  /// 归一化：把 baseUrl 末尾的 /v1 与请求路径里的 /v1 对齐。
  ///
  /// baseUrl 以 /v1 结尾时转发「去掉 /v1 的路径」，
  /// 否则原样转发完整 /v1/... 路径。
  static Uri buildUpstreamUri(Upstream u, String requestPath, String query) {
    var base = u.baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final baseEndsWithV1 = base.toLowerCase().endsWith('/v1');
    final rel = baseEndsWithV1
        ? requestPath.substring(3)
        : requestPath; // 去掉"/v1"
    final url = '$base${rel.isEmpty ? '/' : rel}';
    return Uri.parse(query.isEmpty ? url : '$url?$query');
  }

  static const int _maxFallbackLanes = 8;

  /// 这条对外模型声明的输出上限（0 = 没配）。思考档位按它折算预算。
  static int _outputCapacityOf(Upstream u, String publicName) {
    for (final m in u.models) {
      if (m.publicName == publicName) return m.maxOutputTokens;
    }
    return 0;
  }

  /// 为每个候选车道算出「怎么发、回来怎么译」。
  ///
  /// 逐条车道单独算，混合线协议的回退链才能成立：同一个 `zen-free` 里
  /// chat / responses / messages 三种车道各自要打到自己的端点、发自己的体、
  /// 用自己的方式回译，链上不需要知道彼此说哪种线。
  ///
  /// 返回 null 表示这些车道全都接不了聊天请求（System One 那类判定模型）。
  List<_Hop>? _planHops(
    HttpRequest req,
    Upstream upstream,
    Map<String, dynamic>? json,
    List<String> targets,
    Uint8List rawBody,
    String publicName,
  ) {
    if (json == null || targets.isEmpty) {
      // 没有 model 字段可改写（如 /v1/files）：原样转发。
      return [
        _Hop(
          lane: null,
          path: req.uri.path,
          body: rawBody,
          publicName: publicName,
        ),
      ];
    }
    final inboundSession = req.headers.value('x-opencode-session');
    // 这条对外模型声明的输出上限：思考档位要拿它当「深思」档的预算。
    final capacity = _outputCapacityOf(upstream, publicName);
    // 上游配了「默认思考档位」且客户端自己没发 → 在这儿补上（含按上游认的
    // 形状写字段 / 钳预算）。没配就等于完全按客户端的意思走。
    // 只碰聊天形状的请求：/v1/audio/speech 那套会被翻译器另建一份 body，
    // 往它身上塞 reasoning_effort 没有任何意义。
    final thinking =
        upstream.thinkingDefault.isNotEmpty &&
                req.uri.path != '/v1/audio/speech' &&
                json['messages'] is List
            ? applyThinkingDefaults(
                json,
                defaultLevelId: upstream.thinkingDefault,
                wire: upstream.thinkingWire,
                capacity: capacity,
              )
            : thinkingLevelOf(json);
    final hops = <_Hop>[];
    for (final target in targets) {
      if (zenLaneRejection(target) != null) continue;

      // audio 模态上游的 TTS：把 OpenAI /v1/audio/speech 请求翻译成
      // chat.completions 语音请求（MiMo TTS 的调用形态），回包在
      // _attemptHop 里把 base64 音频解成原始字节。
      if (req.uri.path == '/v1/audio/speech' &&
          upstream.modality == UpstreamModality.audio) {
        final translated = _translateOpenAiTtsToChat(json, target);
        if (translated == null) continue;
        hops.add(
          _Hop(
            lane: target,
            publicName: publicName,
            path: '/v1/chat/completions',
            body: Uint8List.fromList(utf8.encode(jsonEncode(translated))),
            audioDecodeFormat: '${(translated['audio'] as Map)['format']}',
          ),
        );
        continue;
      }

      // Anthropic Messages 上游（DeepSeek /anthropic、Claude 官方）：
      // 把 chat.completions 请求重编码成 Messages，回包由转译器回译。
      // 只接 chat 入口 —— embeddings 之类不做反向适配。
      if (upstream.type == UpstreamType.anthropic &&
          req.uri.path == '/v1/chat/completions' &&
          json['messages'] is List) {
        final hop = buildAnthropicHop(
          upstream: upstream,
          lane: target,
          publicName: publicName,
          clientJson: json,
          level: thinking,
          capacity: capacity,
        );
        hops.add(
          _Hop(
            lane: target,
            publicName: publicName,
            path: hop.path,
            body: hop.body,
            headers: hop.headers,
            translator: hop.translator,
          ),
        );
        continue;
      }

      final plan = zenPlan(
        upstream: upstream,
        lane: target,
        publicName: publicName,
        requestPath: req.uri.path,
        clientJson: json,
        inboundSession: inboundSession,
        outputCapacity: capacity,
        // 上面算好的生效档位（客户端发的，或上游默认档补的）。
        level: thinking,
      );
      if (plan == null) {
        // 不是 Zen 网关：只改写 model，其余原样透传，与适配层无关。
        final copy = Map<String, dynamic>.of(json)..['model'] = target;
        hops.add(
          _Hop(
            lane: target,
            publicName: publicName,
            path: req.uri.path,
            body: Uint8List.fromList(utf8.encode(jsonEncode(copy))),
            // 降级重试要按新档位重打一份 body（形状不变，只换档位字段）。
            thinkingLevel: thinking,
            thinkingWire: upstream.thinkingWire,
            thinkingCapacity: capacity,
            rebuildBody: (level) {
              final retry = Map<String, dynamic>.of(json)
                ..['model'] = target;
              writeThinkingLevel(
                retry,
                level,
                wire: upstream.thinkingWire,
                capacity: capacity,
              );
              return Uint8List.fromList(utf8.encode(jsonEncode(retry)));
            },
          ),
        );
        continue;
      }
      hops.add(
        _Hop(
          lane: target,
          publicName: publicName,
          path: plan.path,
          body: plan.body,
          headers: plan.headers,
          translator: plan.translator,
        ),
      );
    }
    return hops.isEmpty ? null : hops;
  }

  /// OpenAI `/v1/audio/speech` 请求体 → MiMo 风格 chat.completions 语音请求。
  ///
  /// MiMo 的 TTS 走聊天补全协议：要合成的文本放 `role: assistant` 的
  /// content，风格指令（OpenAI 的 `instructions`）放 `role: user`，
  /// 音色/格式放顶层 `audio` 对象。返回 null 表示入参不合法（没有 input）。
  ///
  /// 三种模型对 user 消息的要求不同（MiMo 官方文档 + 2026-10 实测）：
  /// - `mimo-v2.5-tts`：user 消息可选（风格指令）；
  /// - `mimo-v2.5-tts-voicedesign`：user 消息**必填且不能为空**——它就是
  ///   音色描述，缺了 / 空串直接 400「user message content must not be
  ///   empty for voice design model」，所以没给指令时兜底一条默认描述；
  /// - `mimo-v2.5-tts-voiceclone`：user 消息要存在、可为空串（官方示例
  ///   就是 `"content": ""`），音色靠 `audio.voice` 携带样本 data URI。
  static Map<String, dynamic>? _translateOpenAiTtsToChat(
    Map<String, dynamic>? client,
    String target,
  ) {
    if (client == null) return null;
    final input = client['input'];
    if (input is! String || input.trim().isEmpty) return null;
    final kind = ttsModelKindOf(target);
    final instructions = client['instructions'];
    final instructionText =
        instructions is String ? instructions.trim() : '';

    final messages = <Map<String, dynamic>>[];
    switch (kind) {
      case TtsModelKind.voiceDesign:
        // 必填：没有指令就用默认音色描述顶上，绝不能空。
        messages.add({
          'role': 'user',
          'content': instructionText.isNotEmpty
              ? instructionText
              : TtsSettings.defaultDesignPrompt,
        });
      case TtsModelKind.voiceClone:
        // 要存在、可为空串：没指令时带上官方示例同款空 user 消息。
        messages.add({'role': 'user', 'content': instructionText});
      case TtsModelKind.basic:
        if (instructionText.isNotEmpty) {
          messages.add({'role': 'user', 'content': instructionText});
        }
    }
    messages.add({'role': 'assistant', 'content': input});
    // OpenAI response_format: mp3/opus/aac/flac/wav/pcm；MiMo 文档只给了
    // wav / pcm16。除 pcm（原始采样）外都按 wav 要 —— 回给客户端时
    // Content-Type 会如实标注真实格式。
    final upstreamFormat = client['response_format'] == 'pcm' ? 'pcm16' : 'wav';
    final audio = <String, dynamic>{'format': upstreamFormat};
    // 音色克隆（MiMo voiceclone）：客户端可以把样本塞进 `voice_sample`
    // （data:audio/wav|mpeg;base64,... 的 data URI），有它就直接顶掉
    // `voice` 字段 —— 上游靠 audio.voice 携带样本。
    final voiceSample = client['voice_sample'];
    if (voiceSample is String && voiceSample.trim().startsWith('data:')) {
      audio['voice'] = voiceSample.trim();
    } else {
      final voice = client['voice'];
      if (voice is String && voice.trim().isNotEmpty) {
        audio['voice'] = voice.trim();
      }
    }
    // voicedesign 不认任何预置音色 / 样本（文档：不支持预置音色与音色
    // 复刻），带上反而可能被上游打回，剥掉。
    if (kind == TtsModelKind.voiceDesign) {
      audio.remove('voice');
    }
    return {
      'model': target,
      'messages': messages,
      'audio': audio,
      // 拉全量 JSON：/v1/audio/speech 本来就是阻塞式端点，没有流式协议。
      'stream': false,
    };
  }

  /// 按候选顺序尝试同一上游的多个模型车道。
  ///
  /// 关键约束：在确定「本次就是要保留的那次」之前，一个字节都不能写给客户端，
  /// 否则回退就变成给客户端吐半截响应。所以中间候选失败时只读响应头、
  /// 丢弃错误体；最后一条候选无论什么状态都照实回传。
  Future<_ForwardOutcome> _forwardWithFallback(
    HttpRequest req,
    ProxyConfig config,
    Upstream upstream,
    List<_Hop> hops,
  ) async {
    final capped = hops.length > _maxFallbackLanes
        ? hops.sublist(0, _maxFallbackLanes)
        : hops;
    _ForwardOutcome last = const _ForwardOutcome(
      HttpStatus.badGateway,
      'server not running',
      null,
      false,
    );
    for (var i = 0; i < capped.length; i++) {
      final hop = capped[i];
      final r = await _attemptHop(
        req,
        config,
        upstream,
        hop,
        relayToClient: i == capped.length - 1,
      );
      last = _ForwardOutcome(r.status, r.error, hop.lane, r.served);
      if (r.served) return last;
      // 免费额度按 session 计：一条 429 就是整条链 429，往下试只是白烧延迟。
      if (r.status == HttpStatus.tooManyRequests) {
        last = _ForwardOutcome(
          r.status,
          r.error ?? 'free quota exhausted for this session',
          hop.lane,
          false,
        );
        return last;
      }
    }
    return last;
  }

  /// 档位降级最多退几档（`max → xhigh → high`，三跳足够覆盖绝大多数上游）。
  static const int _maxThinkingDowngrades = 3;

  /// 上游回 400 时，判断是不是「不认这一档」并给出下一档。
  ///
  /// 判据是错误体里出现 reasoning / thinking / effort 相关字样 —— 别的
  /// 400（坏 body、模型不存在、超上下文）跟档位无关，原样上交，别乱降。
  /// 返回 null = 不用降（含「已经退无可退」）。
  static Future<ThinkingLevel?> _downgradeFor(
    HttpClientResponse ures,
    ThinkingLevel level,
    ThinkingWireFormat wire,
    Uint8List Function(ThinkingLevel level)? rebuildBody,
  ) async {
    if (rebuildBody == null || !wire.sendsLevel) return null;
    String text;
    try {
      text = await utf8.decoder
          .bind(ures)
          .join()
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      return null;
    }
    final lower = text.toLowerCase();
    final mentions = lower.contains('reasoning') ||
        lower.contains('thinking') ||
        lower.contains('effort') ||
        lower.contains('unsupported value') ||
        lower.contains('invalid value');
    if (!mentions) return null;
    return downgradeThinkingLevel(level);
  }

  Future<_HopResult> _attemptHop(
    HttpRequest req,
    ProxyConfig config,
    Upstream upstream,
    _Hop hop, {
    required bool relayToClient,
  }) async {
    final client = _client;
    if (client == null) {
      return const _HopResult(HttpStatus.badGateway, 'server not running');
    }

    final uri = buildUpstreamUri(upstream, hop.path, req.uri.query);
    // 透传内容类型；避免上游压缩：identity。
    final inCt = req.headers.contentType;
    final upstreamKey = upstream.apiKey.trim();

    /// 发一次请求（[body] 为空 = 不带 body，GET 那类）。
    Future<HttpClientResponse> send(Uint8List body) async {
      final r = await client.openUrl(req.method, uri);
      if (inCt != null) r.headers.contentType = inCt;
      r.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (upstreamKey.isNotEmpty) {
        r.headers.set(HttpHeaders.authorizationHeader, 'Bearer $upstreamKey');
      }
      // 指纹头最后盖上去：Zen 网关靠这一组头认客户端，缺一个就整条车道 403。
      hop.headers?.forEach((name, value) => r.headers.set(name, value));
      // body 被适配层重写过，长度必须按改写后的算，不能沿用入站那一份。
      if (body.isNotEmpty) {
        r.headers.contentLength = body.length;
        r.add(body);
      }
      try {
        return await r.close();
      } catch (e) {
        throw _UpstreamSendFailed('upstream read failed: $e');
      }
    }

    var body = hop.body;
    var level = hop.thinkingLevel;
    HttpClientResponse ures;
    try {
      ures = await send(body);
      // 档位降级：上游因为不认这一档回 400 时，按 max→xhigh→…→off 逐级退，
      // 退到 off 就是彻底不写字段（交给上游默认）。只在这一跳还没给客户端
      // 写过任何字节时发生，所以客户端看到的仍然是一次完整响应。
      if (ures.statusCode == 400 &&
          level != null &&
          hop.thinkingWire != null) {
        for (var i = 0; i < _maxThinkingDowngrades; i++) {
          final next = await _downgradeFor(
            ures,
            level!,
            hop.thinkingWire!,
            hop.rebuildBody,
          );
          if (next == null) break;
          // 错误体已经在 _downgradeFor 里读完了，不能再 drain
          // （单订阅流重复听会抛 StateError，整跳就没了）。
          level = next;
          body = hop.rebuildBody!(next);
          ures = await send(body);
          if (ures.statusCode != 400) break;
        }
      }
    } on _UpstreamSendFailed catch (e) {
      return _HopResult(HttpStatus.badGateway, e.message);
    }

    if (ures.statusCode >= 400 && !relayToClient) {
      // 还有下一条候选：丢掉这次的错误体，不碰客户端响应
      await ures.drain<void>();
      return _HopResult(ures.statusCode, 'upstream ${ures.statusCode}');
    }

    final resp = req.response;
    if (config.corsEnabled) _applyCors(resp, config);
    final translator = hop.translator;
    if (translator != null) {
      _markServedLane(resp, hop);
      // 换线协议了，状态码、Content-Type 与每一帧都由转译器自己定。
      await translator.relay(ures, resp);
      try {
        await resp.close();
      } catch (_) {}
      // 转译器顺手把上游的用量归一成了 OpenAI 形状，直接记账。
      final usage = translator.usageDoc;
      if (usage != null) {
        _recordUsage(
          req,
          config,
          hop,
          upstream,
          UsageTotals.fromUsage(usage),
          stream: translator.stream,
          status: resp.statusCode,
        );
      }
      return _HopResult(
        resp.statusCode,
        resp.statusCode >= 400 ? 'upstream ${ures.statusCode}' : null,
        served: true,
      );
    }

    resp.statusCode = ures.statusCode;
    _markServedLane(resp, hop);
    final ct = ures.headers.contentType;

    // audio 模态的 TTS 回包：chat.completions JSON 里的 base64 音频。
    // 解成原始字节再给客户端 —— OpenAI 客户端期望直接拿到音频流。
    if (hop.audioDecodeFormat != null) {
      final resp = req.response;
      if (config.corsEnabled) _applyCors(resp, config);
      try {
        final builder = BytesBuilder(copy: false);
        await for (final chunk in ures) {
          builder.add(chunk);
        }
        final bytes = builder.takeBytes();
        resp.statusCode = ures.statusCode;
        _markServedLane(resp, hop);
        if (ures.statusCode >= 400) {
          // 上游错误体原样透传（JSON error），客户端能看到真实原因
          resp.headers.contentType = ct ?? ContentType.json;
          resp.headers.contentLength = bytes.length;
          resp.add(bytes);
          await resp.close();
          return _HopResult(
            ures.statusCode,
            'upstream ${ures.statusCode}',
            served: true,
          );
        }
        final doc = jsonDecode(utf8.decode(bytes));
        String? b64;
        if (doc is Map<String, dynamic>) {
          final choices = doc['choices'];
          if (choices is List && choices.isNotEmpty) {
            final first = choices.first;
            if (first is Map<String, dynamic>) {
              final message = first['message'];
              if (message is Map<String, dynamic>) {
                final audio = message['audio'];
                if (audio is Map<String, dynamic> && audio['data'] is String) {
                  b64 = audio['data'] as String;
                }
              }
            }
          }
        }
        if (b64 == null || b64.isEmpty) {
          throw Exception('upstream response has no audio data');
        }
        final audioBytes = base64Decode(b64);
        resp.headers.contentType = ContentType.parse(
          hop.audioDecodeFormat == 'pcm16' ? 'audio/pcm' : 'audio/wav',
        );
        resp.headers.contentLength = audioBytes.length;
        resp.add(audioBytes);
        await resp.close();
        return _HopResult(HttpStatus.ok, null, served: true);
      } catch (e) {
        try {
          resp.statusCode = HttpStatus.badGateway;
          resp.headers.contentType = ContentType.json;
          resp.write(_errorJson('TTS audio decode failed: $e', type: 'api_error'));
          await resp.close();
        } catch (_) {}
        return _HopResult(HttpStatus.badGateway, 'tts decode failed: $e',
            served: true);
      }
    }

    final isEventStream = ct != null && ct.subType.contains('event-stream');
    if (ct != null) resp.headers.contentType = ct;
    if (isEventStream) {
      resp.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      resp.bufferOutput = false;
    }

    // 透传的同时抠 `usage`：非流式在顶层对象里，流式在最后一帧里。
    // 只扫字节、不改字节，转发路径一个字节都不动。用完就丢。
    final extractor = UsageExtractor();
    try {
      await resp.addStream(
        ures.map((chunk) {
          extractor.addBytes(chunk);
          return chunk;
        }),
      );
      await resp.close();
      final totals = extractor.extract();
      if (totals != null) {
        _recordUsage(
          req,
          config,
          hop,
          upstream,
          totals,
          stream: isEventStream,
          status: ures.statusCode,
        );
      }
    } catch (_) {
      // 客户端提前断开属正常情况
      try {
        await resp.close();
      } catch (_) {}
      return _HopResult(
        ures.statusCode,
        ures.statusCode >= 400 ? 'upstream ${ures.statusCode}' : null,
        served: true,
      );
    }
    return _HopResult(
      ures.statusCode,
      ures.statusCode >= 400 ? 'upstream ${ures.statusCode}' : null,
      served: true,
    );
  }

  /// 把「真正接住本次请求的车道」写进响应头。
  ///
  /// 车道与对外模型名一致（单车道、没走路由回退）时不写：响应体里的 `model`
  /// 已经就是它，没必要再加一个头。只有路由 / 回退改变了答案归属时才补这一笔 ——
  /// 比如 `zen-free` 最终由 `space-bunny-free` 接住，响应体说的还是 `zen-free`。
  void _markServedLane(HttpResponse resp, _Hop hop) {
    final lane = hop.lane;
    if (lane == null || lane.isEmpty || lane == hop.publicName) return;
    resp.headers.set(kServedLaneHeader, lane);
  }

  /// 本地 Qwen3-TTS：把 /v1/audio/speech 的文本在设备上直接合成。
  ///
  /// 首次调用会先加载 1.4GB 级模型（可能要十几秒），之后走常驻引擎；
  /// 空闲 5 分钟自动卸载（见 TtsEngineManager）。
  Future<RequestLogEntry> _serveLocalTts(
    HttpRequest req,
    Stopwatch sw,
    String clientIp,
    String model,
    Upstream upstream,
    String input,
  ) async {
    try {
      final result = await TtsEngineManager.instance.speak(input);
      final wav = TtsSpeechService.encodeWav(result.samples, result.sampleRate);
      final resp = req.response;
      _applyCors(resp, configProvider());
      resp.statusCode = HttpStatus.ok;
      resp.headers.contentType = ContentType.parse('audio/wav');
      resp.headers.contentLength = wav.length;
      resp.add(wav);
      await resp.close();
      return _log(
        req,
        model,
        upstream.name.isEmpty ? 'local-tts' : upstream.name,
        HttpStatus.ok,
        sw,
        clientIp,
        null,
      );
    } catch (e) {
      totalErrors.value++;
      return _reject(
        req,
        sw,
        clientIp,
        HttpStatus.badGateway,
        'Local TTS failed: $e',
        'api_error',
        model,
      );
    }
  }

  /// 记一条 token 用量。
  ///
  /// 按「客户端请求的对外模型名」归集（统计页上看到的就是客户端认识的名字），
  /// 同时把真正接住请求的车道一起留着，便于回退链里排查是谁在吃额度。
  /// 只在响应里真出现过 `usage` 时才记：非聊天端点（/v1/files 之类）本来
  /// 就没有用量可言，不该往账本里灌一堆零；而 `usage` 存在但字段全零
  /// （有些网关流式只给空对象）照样记 —— 页面上会显示成「上游未给用量」，
  /// 这本身是有信息量的。
  void _recordUsage(
    HttpRequest req,
    ProxyConfig config,
    _Hop hop,
    Upstream upstream,
    UsageTotals totals, {
    required bool stream,
    required int status,
  }) {
    final caller = _callerKey(req, config);
    usageStats.add(
      TokenUsage(
        timeMs: DateTime.now().millisecondsSinceEpoch,
        model: hop.publicName ?? hop.lane ?? '-',
        upstream: upstream.name.isEmpty ? upstream.id : upstream.name,
        lane: hop.lane ?? '',
        input: totals.input,
        output: totals.output,
        cacheHit: totals.cacheHit,
        cacheMiss: totals.cacheMiss,
        reasoning: totals.reasoning,
        stream: stream,
        status: status,
        apiKeyId: caller.id,
        apiKeyName: caller.name,
        apiKeyLabel: caller.label,
      ),
    );
  }

  Future<RequestLogEntry> _serveModels(
    HttpRequest req,
    Stopwatch sw,
    String clientIp,
    ProxyConfig config,
  ) async {
    final now = nowProvider();
    // 同样的模拟请求旁路：列表也照常给全，模拟器不用来回改策略
    final isSim = req.headers.value(kSimRequestHeader) != null;
    bool scheduleOk(String model, String? groupId) => isSim
        ? true
        : scheduleAllows(
            rules: config.scheduleRules,
            model: model,
            groupId: groupId,
            now: now,
          ).allowed;
    final data = <Map<String, dynamic>>[];
    for (final u in config.upstreams) {
      if (!u.enabled) continue;
      for (final m in u.models) {
        if (!m.enabled) continue;
        // 列表与转发必须同一口径：窗口外不该在 /v1/models 里出现，
        // 否则客户端看得到、打出去却 403。
        if (!scheduleOk(m.publicName, u.managedBy)) continue;
        data.add({
          'id': m.publicName,
          'object': 'model',
          'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'owned_by': u.name,
          // 对外声明的上下文长度：客户端（opencode 这类 agent）拿它决定
          // 何时自动压缩历史。没配的模型回退默认 1M，别让客户端把它
          // 当"未知"一路聊到撞墙。
          'context_length': m.effectiveContextLength,
          // 输出上限：配了才带（不替没配的模型编数字）。
          if (m.maxOutputTokens > 0) 'max_output_tokens': m.maxOutputTokens,
          // 思考档位：上游（Zen）不声明、也不认 reasoning_effort，
          // 档位是我们用**输出预算**强制执行的 —— 对任何模型都真实生效，
          // 所以这里如实对外声明，让 agent 的模型选择器直接给出档位
          // （opencode / DeepSeek Harness 读的就是这两个字段）。
          // 声明按各家交集：OpenAI 的 minimal/low/medium/high/xhigh
          // + DeepSeek 的 max（none 各家都认，放最前）。
          'reasoning': true,
          'supported_reasoning_levels': const [
            'none',
            'minimal',
            'low',
            'medium',
            'high',
            'xhigh',
            'max',
          ],
        });
      }
    }
    _applyCors(req.response, config);
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode({'object': 'list', 'data': data}));
    await req.response.close();
    return _log(req, '-', '-', HttpStatus.ok, sw, clientIp, null);
  }

  void _applyCors(HttpResponse resp, ProxyConfig config) {
    if (!config.corsEnabled) return;
    resp.headers.set('Access-Control-Allow-Origin', '*');
    resp.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    resp.headers.set(
      'Access-Control-Allow-Headers',
      'Authorization, Content-Type, x-api-key',
    );
  }

  Future<RequestLogEntry> _reject(
    HttpRequest req,
    Stopwatch sw,
    String clientIp,
    int status,
    String message,
    String type,
    String model,
  ) async {
    try {
      final resp = req.response;
      final config = configProvider();
      _applyCors(resp, config);
      resp.statusCode = status;
      resp.headers.contentType = ContentType.json;
      resp.write(_errorJson(message, type: type));
      await resp.close();
    } catch (_) {}
    return _log(req, model, '-', status, sw, clientIp, message);
  }

  static String _errorJson(String message, {required String type}) {
    final safe = message.replaceAll('"', "'");
    return '{"error":{"message":"$safe","type":"$type","code":null}}';
  }

  // ------------------------------------------------------------------
  // 上游探测（供 UI：拉模型列表 / 连通性测试）

  /// 从上游拉取模型列表。Ollama 优先走原生 /api/tags，其余走 /models。
  ///
  /// 真正的实现在静态的 [fetchModelCatalog]：发现页刷新可用模型列表要在
  /// 服务没启动时也能跑，不能依赖 ProxyServer 实例。
  Future<ModelCatalog> fetchUpstreamModels(Upstream u) => fetchModelCatalog(u);

  /// 拉一个上游的可用模型清单（静态，不需要服务在跑）。
  ///
  /// 三态：OpenAI 兼容 `/v1/models`、Ollama `/api/tags`、Zen 免密网关
  /// （同一个 `/v1/models` 但要过指纹门，且只留免密车道）。
  ///
  /// 顺带收「上游自己声明的上下文长度」（OpenRouter 的 `context_length`、
  /// vLLM 的 `max_model_len` 之类，有就带上）——模型编辑里自动回填用。
  static Future<ModelCatalog> fetchModelCatalog(Upstream u) async {
    // 本地 TTS：没有远端清单，固定给 Qwen3-TTS 这一个模型名；
    // target 只是占位（本地合成不看 target）。
    if (u.type == UpstreamType.localTts) {
      return const ModelCatalog(['qwen3-tts']);
    }
    final client = _catalogClient();
    if (u.type == UpstreamType.ollama) {
      try {
        return ModelCatalog(await _fetchOllamaTags(client, u));
      } catch (_) {
        // 老版本 Ollama 没有 /api/tags 时回退 OpenAI 兼容端点
        return _fetchOpenAIModels(client, u);
      }
    }
    if (u.type == UpstreamType.anthropic) {
      return _fetchAnthropicModels(client, u);
    }
    return _fetchOpenAIModels(client, u);
  }

  /// 探测用的 HttpClient 全局共用一个：拉清单是低频动作，每次新建会留一堆
  /// 处于 TIME_WAIT 的连接（服务启停频繁时尤其明显）。
  static HttpClient _catalogClient() => _probeClient ??= HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..autoUncompress = false;

  static HttpClient? _probeClient;

  /// 关掉共用的探测客户端（进程退出前调用）。
  static void closeCatalogClient() {
    _probeClient?.close(force: true);
    _probeClient = null;
  }

  static Future<ModelCatalog> _fetchOpenAIModels(
    HttpClient client,
    Upstream u,
  ) async {
    final uri = buildUpstreamUri(u, '/v1/models', '');
    final req = await client.getUrl(uri);
    final key = u.apiKey.trim();
    if (key.isNotEmpty) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
    }
    req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    // 清单也要过指纹门：缺 UA 与 x-opencode-* 时拿到的集合不完整。
    final zen = u.isZenGateway;
    if (zen) {
      final session = zenSessionFor('catalog');
      final headers = zenHeaders(
        session: session,
        requestId: zenRequestIdFor(session, 'models'),
        stream: false,
        accept: 'application/json',
      )..remove(HttpHeaders.contentTypeHeader);
      if (key.isNotEmpty) {
        headers[HttpHeaders.authorizationHeader] = 'Bearer $key';
      }
      headers.forEach((name, value) => req.headers.set(name, value));
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${_brief(text)}');
    }
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic>) throw Exception('Bad response');
    final data = json['data'];
    if (data is! List) throw Exception('Bad response');
    final ids = <String>[];
    final contexts = <String, int>{};
    final outputs = <String, int>{};
    for (final m in data) {
      if (m is! Map<String, dynamic> || m['id'] is! String) continue;
      final id = m['id'] as String;
      ids.add(id);
      final ctx = _contextLengthOfModel(m);
      if (ctx != null) contexts[id] = ctx;
      final out = _outputTokensOfModel(m);
      if (out != null) outputs[id] = out;
    }
    // Zen 的清单混着付费 id 与判定模型，只留能被普通客户端当聊天模型用的。
    if (!zen) return ModelCatalog(ids, contexts: contexts, outputs: outputs);
    final kept = zenFilterUsableLanes(ids);
    return ModelCatalog(kept, contexts: {
      for (final lane in kept)
        if (contexts.containsKey(lane)) lane: contexts[lane]!,
    }, outputs: {
      for (final lane in kept)
        if (outputs.containsKey(lane)) lane: outputs[lane]!,
    });
  }

  /// Anthropic Messages 上游的模型清单。
  ///
  /// 官方（以及大多数兼容网关）在 `/v1/models` 上给 `{"data":[{"id":…}]}`，
  /// 鉴权是 `x-api-key` + `anthropic-version`。DeepSeek 的 Anthropic 入口
  /// 只代理 `/v1/messages`，清单仍挂在去掉 `/anthropic` 的 OpenAI 兼容端点上，
  /// 所以第一次 404/401 时按 [anthropicCatalogFallbackBase] 再问一次。
  static Future<ModelCatalog> _fetchAnthropicModels(
    HttpClient client,
    Upstream u,
  ) async {
    final attempts = <({Uri uri, bool anthropicAuth})>[
      (uri: buildUpstreamUri(u, '/v1/models', ''), anthropicAuth: true),
    ];
    final fallback = anthropicCatalogFallbackBase(u.baseUrl);
    if (fallback != null) {
      attempts.add((
        uri: Uri.parse('$fallback/v1/models'),
        anthropicAuth: false,
      ));
    }

    Object? lastError;
    for (final attempt in attempts) {
      try {
        final req = await client.getUrl(attempt.uri);
        if (attempt.anthropicAuth) {
          anthropicCatalogHeaders(u.apiKey)
              .forEach((k, v) => req.headers.set(k, v));
          final key = u.apiKey.trim();
          // 兼容只认 Bearer 的第三方 Anthropic 网关（两者同时带不冲突）。
          if (key.isNotEmpty) {
            req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
          }
        } else {
          final key = u.apiKey.trim();
          if (key.isNotEmpty) {
            req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
          }
          req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        }
        final res = await req.close();
        final text = await res.transform(utf8.decoder).join();
        if (res.statusCode != 200) {
          lastError = Exception('HTTP ${res.statusCode}: ${_brief(text)}');
          continue;
        }
        final json = jsonDecode(text);
        if (json is! Map<String, dynamic>) throw Exception('Bad response');
        final data = json['data'];
        if (data is! List) throw Exception('Bad response');
        final ids = <String>[];
        final contexts = <String, int>{};
        final outputs = <String, int>{};
        for (final m in data) {
          if (m is! Map<String, dynamic> || m['id'] is! String) continue;
          final id = m['id'] as String;
          ids.add(id);
          final ctx = _contextLengthOfModel(m);
          if (ctx != null) contexts[id] = ctx;
          final out = _outputTokensOfModel(m);
          if (out != null) outputs[id] = out;
        }
        if (ids.isEmpty) throw Exception('Empty model list');
        return ModelCatalog(ids, contexts: contexts, outputs: outputs);
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? Exception('Bad response');
  }

  /// 从 /models 的单条记录里挖上下文长度：各家字段名不一样，能认的都认。
  ///
  /// - OpenRouter：`context_length`（真实的挂在 `top_provider` 下也认）
  /// - vLLM：`max_model_len`
  /// - llama.cpp / 其它：`n_ctx`、`context_window`
  ///
  /// 从 /models 的单条记录里挖最大输出：OpenAI 系 `max_completion_tokens`、
  /// OpenRouter 的 `max_output_tokens`（`top_provider.max_completion_tokens`
  /// 也认）。返回 null 表示上游没说。
  static int? _outputTokensOfModel(Map<String, dynamic> m) {
    for (final key in const ['max_completion_tokens', 'max_output_tokens']) {
      final v = m[key];
      if (v is num && v > 0) return v.toInt();
    }
    final top = m['top_provider'];
    if (top is Map<String, dynamic>) {
      final v = top['max_completion_tokens'];
      if (v is num && v > 0) return v.toInt();
    }
    return null;
  }

  static int? _contextLengthOfModel(Map<String, dynamic> m) {
    for (final key in const [
      'context_length',
      'max_model_len',
      'context_window',
      'n_ctx',
    ]) {
      final v = m[key];
      if (v is num && v > 0) return v.toInt();
    }
    final top = m['top_provider'];
    if (top is Map<String, dynamic>) {
      final v = top['context_length'];
      if (v is num && v > 0) return v.toInt();
    }
    return null;
  }

  static Future<List<String>> _fetchOllamaTags(
    HttpClient client,
    Upstream u,
  ) async {
    final base = u.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final root = base.toLowerCase().endsWith('/v1')
        ? base.substring(0, base.length - 3)
        : base;
    final uri = Uri.parse('$root/api/tags');
    final req = await client.getUrl(uri);
    req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${_brief(text)}');
    }
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic>) throw Exception('Bad response');
    final models = json['models'];
    if (models is! List) throw Exception('Bad response');
    return [
      for (final m in models)
        if (m is Map<String, dynamic> && m['name'] is String)
          m['name'] as String,
    ];
  }

  /// 快速连通性测试：能拉到模型列表即认为成功。
  Future<void> testUpstream(Upstream u) async {
    await fetchUpstreamModels(u);
  }

  static String _brief(String s) {
    s = s.trim();
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }

  Future<void> dispose() async {
    await stop();
    // 探测客户端是全局共用的（静态），服务停了不关它 —— 发现页刷新清单还要用。
    // 真要关在进程退出前调 closeCatalogClient()。
  }
}

/// 一次「从上游拉模型清单」的结果：模型 id 列表 + 上游顺带给的
/// 上下文长度与输出上限。
///
/// [contexts] / [outputs] 只在对方 /models 响应里带了才有值，键是上游
/// 模型名（target 名）。模型编辑页拿它们自动回填，配过的不覆盖。
class ModelCatalog {
  const ModelCatalog(this.ids, {this.contexts = const {}, this.outputs = const {}});

  final List<String> ids;
  final Map<String, int> contexts;
  final Map<String, int> outputs;
}

/// 一条车道的转发方案。[headers] 与 [translator] 只有 Zen 免密车道才非空 ——
/// 其余上游保持「原样透传」，字节与接入适配层之前完全一致。
/// 一次模型路由的结果：上游 + 尝试车道 + 命中的模型条目（峰谷策略看它归属的组）。
class _Route {
  final Upstream upstream;
  final List<String> targets;
  final ModelEntry? entry;

  const _Route(this.upstream, this.targets, this.entry);

  (Upstream, List<String>) asPair() => (upstream, targets);
}

/// 这次调用归属的那一把本机 API Key（见 [ProxyServer] 的记账）。
/// 全空 = 未鉴权；只有 id / 备注名 / 脱敏串，完整密钥不留在这里。
class _CallerKey {
  const _CallerKey({this.id = '', this.name = '', this.label = ''});

  final String id;
  final String name;
  final String label;
}

class _Hop {
  const _Hop({
    required this.lane,
    required this.path,
    required this.body,
    this.headers,
    this.translator,
    this.publicName,
    this.audioDecodeFormat,
    this.thinkingLevel,
    this.thinkingWire,
    this.thinkingCapacity = 0,
    this.rebuildBody,
  });

  /// 实际服务的上游模型名，日志里标出来；未改写时为 null。
  final String? lane;

  /// 客户端请求的那个对外模型名 —— token 统计按它归集，
  /// 客户端看到的模型名与它一致（车道名是内部实现细节）。
  final String? publicName;
  final String path;
  final Uint8List body;
  final Map<String, String>? headers;
  final ZenTranslator? translator;

  /// audio 模态 TTS 车道的回包解码格式（'wav' / 'pcm16'）：
  /// 非空时 `_attemptHop` 不透传上游字节，而是把 chat.completions 回包里
  /// 的 base64 音频解成原始字节写给客户端。
  final String? audioDecodeFormat;

  /// 这一跳实际下发的思考档位（null = 没下发）。降级重试时逐级下调。
  final ThinkingLevel? thinkingLevel;

  /// 档位的下发形状（跟 [thinkingLevel] 一起决定重写请求体时写什么字段）。
  final ThinkingWireFormat? thinkingWire;

  /// 这条对外模型声明的输出上限，重写预算时要用。
  final int thinkingCapacity;

    /// 按新档位重打一份请求体（plan 阶段按上游形状建好的闭包）。
    /// 为 null 表示这一跳不支持降级（如 audio TTS、Zen 车道）。
    final Uint8List Function(ThinkingLevel level)? rebuildBody;
}

/// 一次上游尝试的结果。[served] = false 表示客户端还没收到任何字节，可以再试下一条车道。
class _HopResult {
  final int status;
  final String? error;
  final bool served;

  const _HopResult(this.status, this.error, {this.served = false});
}

/// 发给上游失败（连接 / 读取出错）：让 [_attemptHop] 转成 502 结果。
class _UpstreamSendFailed implements Exception {
  _UpstreamSendFailed(this.message);

  final String message;
}

class _ForwardOutcome {
  final int status;
  final String? error;

  /// 实际服务的上游模型名；未改写或与请求一致时为 null。
  final String? lane;
  final bool served;

  const _ForwardOutcome(this.status, this.error, this.lane, this.served);
}
