// 上游余额查询：把各家「查账户余额」的接口收成一份结构化结果。
//
// 为什么不是「一个接口打天下」：这个 app 的上游可能是 DeepSeek 官方、
// 自建 new-api/one-api 中转站、OpenAI 口径的 dashboard，也可能是硅基流动
// / Kimi 这类国产站 —— 它们的**路径、认证头、金额单位**全都不一样：
// - DeepSeek：`/user/balance`（注意不在 `/v1` 下），金额是**字符串**、按币种分组；
// - new-api：`/api/user/self`，`Bearer <access token>`，金额是 `quota`，
//   按 `1 美元 = 500000 quota` 折算；one-api 同一路径但**不剥 `Bearer ` 前缀**，
//   只认裸 token —— 所以这里先 Bearer、401 再裸值重试一次；
// - OpenAI 口径：`/v1/dashboard/billing/subscription`（美元）+
//   `/v1/dashboard/billing/usage`（**美元分**，要 /100）两枪拼出余额；
// - Kimi / 阶跃 / 硅基流动 / OpenRouter / Novita：各一个私有路径，
//   Novita 的单位还是 0.0001 美元。
// 这些口径对照各家官方文档与 new-api、one-api 源码逐条核过，见每个方法的注释。
//
// 网络层刻意保持「只读 GET、无副作用」：探测失败不改写配置，也不像代理转发
// 那样落日志 —— 这页只是给用户看一眼账户用的。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/proxy_config.dart';

/// 余额明细一行的种类（UI 按它取 l10n 文案，服务层不碰字串）。
enum BalanceDetailKind {
  /// 某个币种的余额（多币种时每个币种一行）。
  balance,

  /// 赠送 / 试用余额（DeepSeek 的 granted_balance、Kimi 的 voucher_balance）。
  granted,

  /// 充值余额（DeepSeek 的 topped_up_balance、Kimi 的 cash_balance）。
  toppedUp,

  /// 已用额度 / 已用金额。
  used,

  /// 累计请求数（new-api / one-api 的 request_count）。
  requests,

  /// 用户分组（new-api / one-api 的 group，计费倍率按组算）。
  group,

  /// 额度上限（OpenAI 的 hard_limit_usd 那一类）。
  limit,
}

/// 一条余额明细：金额型用 [amount] + [currency]，计数型用 [count]，
/// 文本型用 [text]。三者按 [kind] 取其一。
class BalanceDetail {
  const BalanceDetail(
    this.kind, {
    this.amount,
    this.currency,
    this.count,
    this.text,
  });

  final BalanceDetailKind kind;
  final double? amount;

  /// `CNY` / `USD`；null = 上游没说币种。
  final String? currency;
  final int? count;
  final String? text;

  /// 值文本（两套风格共用，免得格式在两处跑偏）。
  String get valueText => switch (kind) {
    BalanceDetailKind.requests => '${count ?? 0}',
    BalanceDetailKind.group => text ?? '',
    _ => UpstreamBalance.amountText(amount, currency),
  };
}

/// 一次余额查询的成功结果。
class UpstreamBalance {
  const UpstreamBalance({
    required this.source,
    required this.fetchedAt,
    this.currency,
    this.available,
    this.accountUsable,
    this.quotaConverted = false,
    this.details = const [],
  });

  /// 命中了哪个接口（`DeepSeek /user/balance` / `New API /api/user/self` …）。
  /// 页面上要展示：有些口径是「猜出来的兼容探针」，用户有权看见。
  final String source;
  final DateTime fetchedAt;

  /// 主余额的币种。
  final String? currency;

  /// 可用余额（已换算成 [currency] 的金额单位）。null = 上游只给了明细。
  final double? available;

  /// 账户是否可继续调用（DeepSeek 的 `is_available`）。null = 上游没说。
  final bool? accountUsable;

  /// [available] 是由 quota 折算来的（$1 = 500000 quota），页面要标一句估算。
  final bool quotaConverted;

  /// 附加明细，按上游给了什么排。
  final List<BalanceDetail> details;

  /// 金额的显示文本：常见币种换成符号，其它币种跟上代码。
  static String amountText(double? amount, String? currency) {
    if (amount == null) return '';
    final value = amount.toStringAsFixed(2);
    return switch ((currency ?? '').toUpperCase()) {
      'CNY' || 'RMB' => '¥$value',
      'USD' => '\$$value',
      '' => value,
      final other => '$value $other',
    };
  }

  /// 主余额的显示文本；没金额时给占位（页面自己决定要不要用）。
  String get amountDisplay =>
      available == null ? '' : amountText(available, currency);
}

/// 失败种类：UI 按它决定文案（能不能重试、是不是该回去改密钥）。
enum BalanceFailure {
  /// 上游没填密钥 —— 余额接口全都要鉴权。
  noKey,

  /// 连不上 / 超时（可重试）。
  network,

  /// 401 / 403：密钥无效或没有读账户的权限。
  unauthorized,

  /// 这个上游没有可用的余额接口（404 / 不是已知网关）。
  unsupported,

  /// 接口答了但读不懂（字段变了 / 返回的不是 JSON）。
  badResponse,
}

/// 查询失败。[message] 是给 UI 兜底展示的原因，不含密钥等敏感值。
class BalanceException implements Exception {
  const BalanceException(this.kind, this.message);

  final BalanceFailure kind;
  final String message;

  @override
  String toString() => message;
}

/// 一次 HTTP 探测的结果。
class _Probe {
  const _Probe(this.status, this.json);

  final int status;
  final Object? json;

  /// 顶层是 JSON 对象才给 map，其它（数组 / 非 JSON / 空）返回 null。
  Map<String, dynamic>? get map =>
      json is Map<String, dynamic> ? json as Map<String, dynamic> : null;

  bool get ok => status >= 200 && status < 300;
}

/// 一轮探测下来的状态码记录：全都失败时用它挑「最贴真相」的原因。
class _Tally {
  final Set<int> statuses = {};
  bool badJson = false;

  void note(int status) => statuses.add(status);

  void noteBadJson() => badJson = true;

  BalanceException finalError() {
    if (statuses.contains(401) || statuses.contains(403)) {
      return const BalanceException(
        BalanceFailure.unauthorized,
        '密钥没有读取账户的权限',
      );
    }
    if (statuses.contains(429)) {
      return const BalanceException(
        BalanceFailure.network,
        '请求过于频繁，稍后再试',
      );
    }
    if (statuses.any((s) => s >= 500)) {
      return const BalanceException(BalanceFailure.network, '上游返回了错误页');
    }
    if (badJson) {
      return const BalanceException(
        BalanceFailure.badResponse,
        '余额接口返回的不是 JSON',
      );
    }
    return const BalanceException(
      BalanceFailure.unsupported,
      '该上游没有余额查询接口',
    );
  }
}

/// 余额接口打的是**站点根**，不是聊天用的 `/v1`，所以要先归一化 baseUrl：
/// 去尾斜杠、去尾部的 `/v1`、`/v1beta`，保留可能存在的子路径
/// （自建网关常部署在 `https://example.com/new-api` 这种前缀下）。
class _Site {
  const _Site({
    required this.rootOrigin,
    required this.apiOrigin,
    required this.host,
  });

  /// 站点根（`scheme://authority`，不含任何路径）。厂商专属接口用它：
  /// 例如 OpenRouter 的聊天地址是 `https://openrouter.ai/api/v1`，
  /// 而积分地址在 `https://openrouter.ai/api/v1/credits`。
  final String rootOrigin;

  /// 带部署前缀的地址根：尾部 `/v1`、`/v1beta` 与尾斜杠剥掉，其它路径留着。
  /// 通用链用它 —— 自建网关常装在 `https://example.com/new-api/v1`。
  final String apiOrigin;

  /// 小写主机名，用于认厂商。
  final String host;

  static _Site? parse(String baseUrl) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    final authority = '${uri.scheme}://${uri.authority}';
    // 先剥尾斜杠再认 /v1：`https://api.deepseek.com/v1/` 也是 v1 结尾。
    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    for (final suffix in const ['/v1beta', '/v1']) {
      if (path.toLowerCase().endsWith(suffix)) {
        path = path.substring(0, path.length - suffix.length);
        break;
      }
    }
    return _Site(
      rootOrigin: authority,
      apiOrigin: '$authority$path',
      host: uri.host.toLowerCase(),
    );
  }
}

/// 一次余额探测的打点函数：读到就回结果，读不到回 null（继续猜下一个）。
///
/// 只有网络错误（连不上 / 超时）会抛 [BalanceException] 中断整条链 ——
/// 那已经不是「这条接口没有」，接着猜只会把一次刷新变成一串无意义请求。
typedef _BalanceAttempt =
    Future<UpstreamBalance?> Function(
      HttpClient c,
      _Site site,
      String key,
      _Tally tally,
      DateTime now,
    );

class UpstreamBalanceService {
  UpstreamBalanceService._();

  /// new-api / one-api 的额度换算常数（源码 `common/constants.go`：
  /// `QuotaPerUnit = 500 * 1000.0`）。
  static const double quotaPerUsd = 500000;

  static const Duration _timeout = Duration(seconds: 10);

  /// 探测用的 HttpClient 复用一只（同 ProxyServer 的 catalog 客户端口径）：
  /// 余额页反复刷新不该每次攒一批 TIME_WAIT 连接。
  static HttpClient? _client;

  static HttpClient _httpClient() =>
      _client ??= HttpClient()
        ..connectionTimeout = _timeout
        ..autoUncompress = false;

  /// 关掉共用客户端（进程退出前调）。
  static void closeClient() {
    _client?.close(force: true);
    _client = null;
  }

  /// 认出的厂 → 该按顺序打的余额接口。纯函数，好离线单测。
  ///
  /// 命中厂商就只走它家那一条：各家余额的字段与单位互不相通，猜错邻居的
  /// 接口不如直说读不到。认不出（自建网关、OpenAI 官方、各种中转站）时
  /// 走通用链：先认 new-api/one-api 门，再试 OpenAI 口径的 dashboard，
  /// 最后试 DeepSeek 形状的 `/user/balance`（很多国产网关照抄了它）。
  static List<String> endpointIdsFor(String host) {
    final h = host.toLowerCase();
    if (h.contains('deepseek')) return const ['deepseek'];
    if (h.contains('moonshot') || h.contains('kimi')) return const ['moonshot'];
    if (h.contains('stepfun')) return const ['stepfun'];
    if (h.contains('siliconflow')) return const ['siliconFlow'];
    if (h.contains('openrouter')) return const ['openRouter'];
    if (h.contains('novita')) return const ['novita'];
    return const ['selfHosted', 'openAiBilling', 'deepseekMimic'];
  }

  /// 查一个上游的余额。失败一律抛 [BalanceException]（种类见 [BalanceFailure]）。
  ///
  /// [client] / [now] 是给单测留的注入口：离线假上游要能钉住时钟，才能验
  /// OpenAI usage 的日期窗口与 one-api 的裸 token 重试顺序。
  static Future<UpstreamBalance> fetch(
    Upstream u, {
    HttpClient? client,
    DateTime? now,
  }) async {
    final key = u.apiKey.trim();
    final site = _Site.parse(u.baseUrl);
    if (site == null) {
      throw const BalanceException(
        BalanceFailure.unsupported,
        '这个上游没有可查的远端地址',
      );
    }
    if (key.isEmpty) {
      throw const BalanceException(BalanceFailure.noKey, '上游没填密钥');
    }
    final c = client ?? _httpClient();
    final stamp = now ?? DateTime.now();
    final tally = _Tally();

    for (final id in endpointIdsFor(site.host)) {
      final result = await _endpoints[id]!(c, site, key, tally, stamp);
      if (result != null) return result;
    }
    throw tally.finalError();
  }

  /// 接口注册表：id → 打点函数（顺序由 [endpointIdsFor] 决定）。
  /// `deepseek` 与 `deepseekMimic` 共用同一份解析，打两个基准：厂商用站点根
  /// （`https://api.deepseek.com/user/balance`），通用探针用部署前缀
  /// （自建网关可能装在 `https://example.com/napi`）。
  static final Map<String, _BalanceAttempt> _endpoints = {
    'deepseek': (c, site, key, tally, now) =>
        _deepSeekAt(c, site.rootOrigin, key, tally),
    'deepseekMimic': (c, site, key, tally, now) =>
        _deepSeekAt(c, site.apiOrigin, key, tally),
    'moonshot': _moonshot,
    'stepfun': _stepFun,
    'siliconFlow': _siliconFlow,
    'openRouter': _openRouter,
    'novita': _novita,
    'selfHosted': _selfHosted,
    'openAiBilling': _openAiBilling,
  };

  /// 自建网关这一条要两枪：先用**免鉴权**的 `/api/status` 认门
  /// （new-api / one-api 都有），是网关才打 `/api/user/self`。
  /// 认不出就整条回 null，让下一家继续 —— 别在厂商站上误报「密钥无效」。
  static Future<UpstreamBalance?> _selfHosted(
    HttpClient c,
    _Site site,
    String key,
    _Tally tally,
    DateTime now,
  ) async {
    if (!await _isSelfHostedGateway(c, site, tally)) return null;
    return _selfHostedSelf(c, site, key, tally);
  }

  // ---- 各厂商实现 ----

  /// DeepSeek：`GET {root}/user/balance`（**不在 /v1 下**）。
  ///
  /// ```json
  /// {"is_available":true,
  ///  "balance_infos":[{"currency":"CNY","total_balance":"110.00",
  ///  "granted_balance":"10.00","topped_up_balance":"100.00"}]}
  /// ```
  /// 三个金额都是**字符串**，单位就是币种本身（元 / 美元）；
  /// `total_balance = granted_balance + topped_up_balance`，顶层没有总额。
  /// 多币种时每个币种各出一行，单币种时只把「赠送 / 充值」当明细
  /// （否则页面上会出现两行同样的余额）。
  static Future<UpstreamBalance?> _deepSeekAt(
    HttpClient c,
    String origin,
    String key,
    _Tally tally,
  ) async {
    final p = await _get(c, origin, '/user/balance', key, tally);
    final body = p != null && p.ok ? p.map : null;
    if (body == null) return null;
    final usable = body['is_available'] is bool
        ? body['is_available'] as bool
        : null;
    final infos = body['balance_infos'] is List
        ? (body['balance_infos'] as List).whereType<Map>().toList()
        : const <Map>[];
    if (infos.isEmpty) {
      // 只有可用性开关、没有金额行：也算读到东西了（DeepSeek 欠费时会这样）。
      return usable == null
          ? null
          : UpstreamBalance(
              source: 'DeepSeek /user/balance',
              fetchedAt: DateTime.now(),
              accountUsable: usable,
            );
    }
    final first = infos.first;
    final firstCurrency = first['currency'] is String
        ? first['currency'] as String
        : null;
    final available = _num(first['total_balance']);
    final details = <BalanceDetail>[
      // 多币种：每种币种一行余额，让用户看清「主余额只是其中一种」。
      if (infos.length > 1)
        for (final e in infos)
          BalanceDetail(
            BalanceDetailKind.balance,
            amount: _num(e['total_balance']),
            currency: e['currency'] is String ? e['currency'] as String : null,
          ),
      for (final e in infos)
        if (_num(e['granted_balance']) != null)
          BalanceDetail(
            BalanceDetailKind.granted,
            amount: _num(e['granted_balance']),
            currency: e['currency'] is String ? e['currency'] as String : null,
          ),
      for (final e in infos)
        if (_num(e['topped_up_balance']) != null)
          BalanceDetail(
            BalanceDetailKind.toppedUp,
            amount: _num(e['topped_up_balance']),
            currency: e['currency'] is String ? e['currency'] as String : null,
          ),
    ];
    return UpstreamBalance(
      source: 'DeepSeek /user/balance',
      fetchedAt: DateTime.now(),
      currency: firstCurrency,
      available: available,
      accountUsable: usable,
      details: details,
    );
  }

  /// Kimi / Moonshot：`GET {root}/v1/users/me/balance`，数字型、人民币。
  ///
  /// `{"code":0,"data":{"available_balance":49.58,"voucher_balance":46.58,
  /// "cash_balance":3.00},"scode":"0x0","status":true}`
  static Future<UpstreamBalance?> _moonshot(
    HttpClient c,
    _Site site,
    String key,
    _Tally tally,
    DateTime now,
  ) async {
    final p = await _get(c, site.rootOrigin, '/v1/users/me/balance', key, tally);
    final data = _dataOf(p);
    final available = data == null ? null : _num(data['available_balance']);
    if (data == null || available == null) return null;
    return UpstreamBalance(
      source: 'Moonshot /v1/users/me/balance',
      fetchedAt: DateTime.now(),
      currency: 'CNY',
      available: available,
      details: _pair(data, 'voucher_balance', 'cash_balance', 'CNY'),
    );
  }

  /// 阶跃星辰：`GET {root}/v1/accounts`，美元。
  static Future<UpstreamBalance?> _stepFun(
    HttpClient c,
    _Site site,
    String key,
    _Tally tally,
    DateTime now,
  ) async {
    final p = await _get(c, site.rootOrigin, '/v1/accounts', key, tally);
    final body = p != null && p.ok ? p.map : null;
    if (body == null) return null;
    final balance = _num(body['balance']);
    if (balance == null) return null;
    return UpstreamBalance(
      source: 'StepFun /v1/accounts',
      fetchedAt: DateTime.now(),
      currency: 'USD',
      available: balance,
      details: _pair(body, 'total_voucher_balance', 'total_cash_balance', 'USD'),
    );
  }

  /// 硅基流动：`GET {root}/v1/user/info`，人民币，字段是 camelCase。
  static Future<UpstreamBalance?> _siliconFlow(
    HttpClient c,
    _Site site,
    String key,
    _Tally tally,
    DateTime now,
  ) async {
    final p = await _get(c, site.rootOrigin, '/v1/user/info', key, tally);
    final data = _dataOf(p);
    final total = data == null ? null : _num(data['totalBalance']);
    if (data == null || total == null) return null;
    return UpstreamBalance(
      source: 'SiliconFlow /v1/user/info',
      fetchedAt: DateTime.now(),
      currency: 'CNY',
      available: total,
      details: _pair(data, 'giftBalance', 'cashBalance', 'CNY'),
    );
  }

  /// OpenRouter：`GET {root}/api/v1/credits`，美元，余额 = 累计充值 - 已用。
  static Future<UpstreamBalance?> _openRouter(
    HttpClient c,
    _Site site,
    String key,
    _Tally tally,
    DateTime now,
  ) async {
    final p = await _get(c, site.rootOrigin, '/api/v1/credits', key, tally);
    final data = _dataOf(p);
    if (data == null) return null;
    final credits = _num(data['total_credits']);
    final usage = _num(data['total_usage']);
    if (credits == null && usage == null) return null;
    return UpstreamBalance(
      source: 'OpenRouter /api/v1/credits',
      fetchedAt: DateTime.now(),
      currency: 'USD',
      available: credits == null ? null : credits - (usage ?? 0),
      details: [
        if (usage != null)
          BalanceDetail(BalanceDetailKind.used, amount: usage, currency: 'USD'),
      ],
    );
  }

  /// Novita：`GET {root}/v3/user/balance`，单位是 **0.0001 美元**，要 ÷10000。
  static Future<UpstreamBalance?> _novita(
    HttpClient c,
    _Site site,
    String key,
    _Tally tally,
    DateTime now,
  ) async {
    final p = await _get(c, site.rootOrigin, '/v3/user/balance', key, tally);
    final body = p != null && p.ok ? p.map : null;
    if (body == null) return null;
    final raw =
        _num(body['availableBalance']) ?? _num(body['available_balance']);
    if (raw == null) return null;
    return UpstreamBalance(
      source: 'Novita /v3/user/balance',
      fetchedAt: DateTime.now(),
      currency: 'USD',
      available: raw / 10000,
    );
  }

  /// new-api / one-api 的认门接口：`GET {root}/api/status`，免鉴权。
  ///
  /// 两家都有它且回 `{success:true, data:{...}}`；OpenAI 官方与多数厂商站
  /// 是 404 —— 拿它当「这是不是一个自建网关」的判据最省钥匙。
  static Future<bool> _isSelfHostedGateway(
    HttpClient c,
    _Site site,
    _Tally tally,
  ) async {
    final p = await _get(c, site.apiOrigin, '/api/status', null, tally);
    if (p == null || !p.ok) return false;
    final body = p.map;
    if (body == null) return false;
    final data = body['data'];
    // 光 success:true 不够（各家都爱这么回）；带 system_name 才是这类网关。
    return body['success'] == true &&
        data is Map &&
        data.containsKey('system_name');
  }

  /// new-api / one-api：`GET {root}/api/user/self`。
  ///
  /// 认证头是关键差异：new-api 会剥掉可选的 `Bearer ` 前缀，one-api 的
  /// `authHelper` 直接把 Authorization 原值丢进 `ValidateAccessToken()` ——
  /// 带前缀必 401。所以先按 new-api 的习惯发 Bearer，吃了 401/403
  /// 再发一次裸值。
  ///
  /// `data.quota / used_quota` 是**额度**不是钱：`1 美元 = 500000 quota`
  /// （源码 `QuotaPerUnit = 500 * 1000.0`）。站方可以把展示币种配成人民币，
  /// 客户端无从得知，所以按美元口径给数并标一句「换算估算」。
  static Future<UpstreamBalance?> _selfHostedSelf(
    HttpClient c,
    _Site site,
    String key,
    _Tally tally,
  ) async {
    var p = await _get(c, site.apiOrigin, '/api/user/self', key, tally);
    if (p != null && (p.status == 401 || p.status == 403)) {
      // one-api 口径：Authorization 要裸值。
      p = await _get(c, site.apiOrigin, '/api/user/self', key, tally, bareAuth: true);
    }
    final data = _dataOf(p);
    final quota = data == null ? null : _num(data['quota']);
    if (data == null || quota == null) return null;
    final used = _num(data['used_quota']);
    final requests = _int(data['request_count']);
    final group = data['group'] is String ? data['group'] as String : null;
    return UpstreamBalance(
      source: 'New API /api/user/self',
      fetchedAt: DateTime.now(),
      currency: 'USD',
      available: quota / quotaPerUsd,
      quotaConverted: true,
      accountUsable: data['status'] is num ? (data['status'] as num) >= 1 : null,
      details: [
        if (used != null)
          BalanceDetail(
            BalanceDetailKind.used,
            amount: used / quotaPerUsd,
            currency: 'USD',
          ),
        if (requests != null)
          BalanceDetail(BalanceDetailKind.requests, count: requests),
        if (group != null && group.trim().isNotEmpty)
          BalanceDetail(BalanceDetailKind.group, text: group.trim()),
      ],
    );
  }

  /// OpenAI 口径：`/v1/dashboard/billing/subscription` + `/usage`。
  ///
  /// subscription 的 `hard_limit_usd` / `system_hard_limit_usd` 单位是**美元**
  /// （巨大值 = 实际上没限），usage 的 `total_usage` 单位是**美元分**。
  /// 余额按「上限 - 已用」拼：时间窗优先用 subscription 里的 `start_date`
  /// （秒级时间戳），没有就取本月 1 号到今天 —— 这是这套未文档化接口的
  /// 通行口径，页面上会把「查询接口」标出来，不让用户误以为是官方账本。
  static Future<UpstreamBalance?> _openAiBilling(
    HttpClient c,
    _Site site,
    String key,
    _Tally tally,
    DateTime now,
  ) async {
    final sub = await _get(
      c,
      site.apiOrigin,
      '/v1/dashboard/billing/subscription',
      key,
      tally,
    );
    final subBody = sub != null && sub.ok ? sub.map : null;
    if (subBody == null) return null;
    final limit = _num(subBody['system_hard_limit_usd']) ??
        _num(subBody['hard_limit_usd']);
    final start = _dateOf(subBody['start_date']) ?? DateTime(now.year, now.month);
    final usage = await _get(
      c,
      site.apiOrigin,
      '/v1/dashboard/billing/usage'
      '?start_date=${_ymd(start)}&end_date=${_ymd(now)}',
      key,
      tally,
    );
    final usedCents = usage != null && usage.ok
        ? _num(usage.map?['total_usage'])
        : null;
    final used = usedCents == null ? null : usedCents / 100;
    if (limit == null && used == null) return null;
    return UpstreamBalance(
      source: 'OpenAI dashboard/billing',
      fetchedAt: DateTime.now(),
      currency: 'USD',
      available: limit == null ? null : limit - (used ?? 0),
      details: [
        if (limit != null)
          BalanceDetail(BalanceDetailKind.limit, amount: limit, currency: 'USD'),
        if (used != null)
          BalanceDetail(BalanceDetailKind.used, amount: used, currency: 'USD'),
      ],
    );
  }

  // ---- HTTP / 解析小工具 ----

  /// 发一次 GET 并解 JSON。
  ///
  /// 网络错误（连不上 / 超时）直接抛 —— 那不是「这条接口没有」，继续猜只会
  /// 把一次失败的刷新变成一串无意义的请求。
  static Future<_Probe?> _get(
    HttpClient c,
    String origin,
    String pathWithQuery,
    String? key,
    _Tally tally, {
    bool bareAuth = false,
  }) async {
    final HttpClientResponse res;
    try {
      final req = await c
          .getUrl(Uri.parse('$origin$pathWithQuery'))
          .timeout(_timeout);
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (key != null && key.isNotEmpty) {
        req.headers.set(
          HttpHeaders.authorizationHeader,
          bareAuth ? key : 'Bearer $key',
        );
      }
      res = await req.close().timeout(_timeout);
    } on Object catch (e) {
      throw BalanceException(BalanceFailure.network, _briefNetwork(e));
    }
    final text = await res.transform(utf8.decoder).join();
    tally.note(res.statusCode);
    if (res.statusCode != 200) return _Probe(res.statusCode, null);
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      tally.noteBadJson();
    }
    return _Probe(res.statusCode, decoded);
  }

  /// 顶层 `{success, data}` 包壳的接口取 data；没有包壳就把顶层当 data。
  static Map<String, dynamic>? _dataOf(_Probe? p) {
    if (p == null || !p.ok) return null;
    final body = p.map;
    if (body == null) return null;
    if (body['success'] == false) return null;
    final data = body['data'];
    if (data is Map<String, dynamic>) return data;
    return body;
  }

  /// 「赠送 + 充值」两行的公共构造（各家字段名不同，值没给就不出这一行）。
  static List<BalanceDetail> _pair(
    Map<String, dynamic> data,
    String grantedKey,
    String toppedKey,
    String currency,
  ) => [
    if (_num(data[grantedKey]) != null)
      BalanceDetail(
        BalanceDetailKind.granted,
        amount: _num(data[grantedKey]),
        currency: currency,
      ),
    if (_num(data[toppedKey]) != null)
      BalanceDetail(
        BalanceDetailKind.toppedUp,
        amount: _num(data[toppedKey]),
        currency: currency,
      ),
  ];

  /// 金额字段兼容数字与字符串（DeepSeek 全字符串、Kimi 全数字）。
  static double? _num(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) {
      final s = v.replaceAll(RegExp(r'[,\s]'), '');
      if (s.isEmpty) return null;
      return double.tryParse(s);
    }
    return null;
  }

  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  /// 秒级时间戳（OpenAI 的 start_date）转本地日期。
  static DateTime? _dateOf(Object? v) {
    final n = _num(v);
    if (n == null) return null;
    try {
      return DateTime.fromMillisecondsSinceEpoch((n * 1000).round());
    } catch (_) {
      return null;
    }
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _briefNetwork(Object e) {
    final s = '$e'.replaceFirst(RegExp(r'^(Exception:\s*)+'), '');
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }
}
