import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/proxy_config.dart';
import 'chat_sim_store.dart';
import 'character_store.dart';
import 'proxy_server.dart';

/// 对话里的一条消息。角色与 OpenAI 的 `role` 一一对应。
enum ChatRole {
  system,
  user,
  assistant;

  String get wire => name;
}

/// 图片附件的粗估 token 开销（只在拿不到上游 usage 时兜底用）。
/// 选图时就压到 ≤1024px，按 Anthropic 的 (宽×高)/750 折算大约是 1400，
/// 各家「低细节」档又要便宜得多（OpenAI 固定 85）—— 取个中间值，
/// 宁可略微高估，也别让用户以为还有大量余量。
const int kImageTokenEstimate = 600;

/// 对话消息上的附件（图片 / 文件）。
///
/// **图片会进请求体**：带图片的用户消息按 OpenAI 多模态形状发出去
/// （`content: [{type:'text'}, {type:'image_url':{url:'data:...'}}]`，
/// 见 [ChatMsg.toWire]）。图片字节就是选图时压好的缩略图（≤1024px JPEG），
/// 展示与发送共用一份，不再多存一份原图。
/// ⚠️ 纯文本车道收到多模态 content 会直接 400，所以页面留了
/// [ChatSimController.sendImages] 这个退路（关掉就只发文字，图只在界面上）。
///
/// 文件附件仍然**只做界面展示**（只取名字和大小，内容不读）。
class ChatAttachment {
  ChatAttachment({
    required this.name,
    required this.isImage,
    this.sizeBytes,
    this.thumbnail,
  });

  /// 展示名（文件原名 / 图片截图名）。
  final String name;

  /// 图片附件：气泡里渲染缩略图；文件附件：渲染成图标 + 名称 + 大小。
  final bool isImage;

  /// 原始大小（字节），可能拿不到（选图器不回大小）。
  final int? sizeBytes;

  /// 压缩缩略图（PNG/JPEG 字节，仅图片有）。UI 直接 Image.memory 它，
  /// 发请求时也用它当图片字节（不再单独留一份原图）。
  Uint8List? thumbnail;

  /// 是不是「真能发出去」的图片附件（有字节才算，只有元信息的不算）。
  bool get hasImageData =>
      isImage && thumbnail != null && thumbnail!.isNotEmpty;

  /// 图片的 MIME，从字节头嗅探（image_picker 压完一般是 JPEG，
  /// 但截图 / 某些 ROM 会给 PNG）。认不出来时按 JPEG 报 ——
  /// 各家车道对 MIME 的容忍度都比分类型差好。
  String get mime => sniffImageMime(thumbnail);

  /// 从字节头认图片类型（不是图片返回空串）。静态方法，WebUI 侧也能复用。
  static String sniffImageMime(List<int>? b) {
    if (b == null || b.length < 12) return '';
    if (b[0] == 0xFF && b[1] == 0xD8) return 'image/jpeg';
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      return 'image/png';
    }
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'image/gif';
    final riff = String.fromCharCodes(b.sublist(0, 4));
    final webp = String.fromCharCodes(b.sublist(8, 12));
    if (riff == 'RIFF' && webp == 'WEBP') return 'image/webp';
    if (b[0] == 0x42 && b[1] == 0x4D) return 'image/bmp';
    return '';
  }

  /// OpenAI `image_url.url` 要的那个 data URL。不是图片时返回 null。
  String? get dataUrl {
    if (!hasImageData) return null;
    final m = mime.isEmpty ? 'image/jpeg' : mime;
    return 'data:$m;base64,${base64Encode(thumbnail!)}';
  }

  Map<String, dynamic> toJson({bool includeThumbnail = true}) => {
    'name': name,
    'image': isImage,
    'size': ?sizeBytes,
    // 缩略图 base64；超出预算时由 ChatSimStore 关掉（只留元信息）。
    'thumb': (includeThumbnail && thumbnail != null)
        ? base64Encode(thumbnail!)
        : null,
  };

  static ChatAttachment fromJson(Map<String, dynamic> j) {
    Uint8List? thumb;
    final raw = j['thumb'];
    if (raw is String && raw.isNotEmpty) {
      try {
        thumb = base64Decode(raw);
      } catch (_) {}
    }
    return ChatAttachment(
      name: (j['name'] as String?) ?? '',
      isImage: (j['image'] as bool?) ?? false,
      sizeBytes: (j['size'] as num?)?.toInt(),
      thumbnail: thumb,
    );
  }

  ChatAttachment copy() =>
      ChatAttachment(
        name: name,
        isImage: isImage,
        sizeBytes: sizeBytes,
        thumbnail: thumbnail == null ? null : Uint8List.fromList(thumbnail!),
      );
}

/// 附件大小的人类可读格式（KB / MB）。
String formatAttachmentSize(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// 对话模拟里的一条消息（可变：可编辑内容与角色）。
class ChatMsg {
  ChatMsg(
    this.role,
    this.content, {
    this.elapsedMs,
    this.error = false,
    this.model,
    this.lane,
    this.usageTokens = 0,
    this.attachments = const [],
  });

  ChatRole role;
  String content;

  /// assistant 回答的耗时（毫秒）—— 卡片页脚那个「time」。
  int? elapsedMs;

  /// 这条是失败提示而不是模型回答（渲染成错误色，且不参与后续请求）。
  bool error;

  /// 响应体里回显的模型名（通常就是客户端请求的那个对外名）。
  String? model;

  /// 真正接住这次请求的车道（响应头 [kServedLaneHeader] 带回来的）。
  ///
  /// 走容灾路由时 [model] 是路由名（如 `zen-free`），这里才是实际答话的
  /// 上游模型（如 `space-bunny-free`）。没走路由时为空。
  String? lane;

  /// 随消息挂上的附件：图片会进请求体（见 [toWire]），文件只展示。
  List<ChatAttachment> attachments;

  /// 这条回答响应里的上下文占用（usage 的 prompt + completion，也就是
  /// 下一轮请求要带的总量）。0 = 上游没给 usage（界面退回字数估算）。
  /// 只有 assistant 消息会带；上下文占用环按它取「精确值」。
  int usageTokens = 0;

  /// 界面上要显示的「响应模型」：优先真实车道，其次回显的模型名。
  String? get servedModel => (lane != null && lane!.isNotEmpty) ? lane : model;

  /// 走的是容灾路由：真实车道与响应体回显的对外名不是同一个
  /// （`zen-free` → `space-bunny-free`）。此时两个名字都要给用户看。
  bool get routed =>
      lane != null &&
      lane!.isNotEmpty &&
      model != null &&
      model!.isNotEmpty &&
      lane != model;

  /// 这条上的图片附件（真有字节的才算 —— 落盘超预算被丢掉缩略图的
  /// 那些只剩元信息，发不出去）。
  List<ChatAttachment> get imageAttachments => [
    for (final a in attachments)
      if (a.hasImageData) a,
  ];

  /// 有没有能发出去的图片。
  bool get hasImage => imageAttachments.isNotEmpty;

  /// 这条有没有「值得发」的内容：有文字，或者（[includeImages] 时）有图片。
  bool sendable({bool includeImages = true}) =>
      !error && (content.trim().isNotEmpty || (includeImages && hasImage));

  /// 请求体里的这一条：
  /// - 没有图片（或页面关了「发送图片」）→ `content` 是字符串，纯文本车道照收；
  /// - 有图片 → `content` 换成 OpenAI 多模态 parts（text 段 + 每图一个
  ///   `image_url`，图是 data URL）。文本为空时只发图片段，不塞空 text。
  Map<String, dynamic> toWire({bool includeImages = true}) {
    final images = includeImages ? imageAttachments : const <ChatAttachment>[];
    if (images.isEmpty) {
      return {'role': role.wire, 'content': content};
    }
    return {
      'role': role.wire,
      'content': [
        if (content.trim().isNotEmpty)
          {'type': 'text', 'text': content},
        for (final a in images)
          {'type': 'image_url', 'image_url': {'url': a.dataUrl}},
      ],
    };
  }

  /// 落盘用（比 [toWire] 多存耗时、「这条是失败提示」与响应模型）。
  /// [includeAttachmentThumbs] 关掉时附件只存元信息（预算控制用）。
  Map<String, dynamic> toJson({bool includeAttachmentThumbs = true}) => {
    'role': role.wire,
    'content': content,
    'elapsedMs': ?elapsedMs,
    'error': error,
    'model': ?model,
    'lane': ?lane,
    if (usageTokens > 0) 'usageTokens': usageTokens,
    'attachments': [
      for (final a in attachments) a.toJson(includeThumbnail: includeAttachmentThumbs),
    ],
  };

  factory ChatMsg.fromJson(Map<String, dynamic> j) => ChatMsg(
    ChatRole.values.firstWhere(
      (r) => r.wire == j['role'],
      orElse: () => ChatRole.user,
    ),
    (j['content'] as String?) ?? '',
    elapsedMs: (j['elapsedMs'] as num?)?.toInt(),
    error: (j['error'] as bool?) ?? false,
    model: j['model'] as String?,
    lane: j['lane'] as String?,
    usageTokens: (j['usageTokens'] as num?)?.toInt() ?? 0,
    attachments: [
      if (j['attachments'] is List)
        for (final a in (j['attachments'] as List))
          if (a is Map<String, dynamic>) ChatAttachment.fromJson(a),
    ],
  );
}

/// 一次请求的结果。
class ChatSimResult {
  const ChatSimResult({
    required this.ok,
    required this.content,
    this.model,
    this.lane,
    this.elapsedMs,
    this.status,
    this.usageTokens = 0,
  });

  final bool ok;
  final String content;

  /// 上游实际回答的模型名（网关回显的就是真正接住请求的那条车道）。
  final String? model;

  /// 真正接住请求的车道（网关转译时回显的是对外名，路由场景下两者不同，
  /// 靠响应头 [kServedLaneHeader] 补回来）。没走路由时为空。
  final String? lane;
  final int? elapsedMs;
  final int? status;

  /// 响应 usage 里的上下文占用（prompt + completion）。0 = 上游没给。
  final int usageTokens;
}

/// 「对话模拟」：把界面里攒出来的对话当成下游客户端发过来的一条请求。
///
/// 走**本机代理**（`127.0.0.1:<listenPort>/v1/chat/completions`）而不是直连上游：
/// 这样路由、容灾回退、Zen 指纹门、请求日志全都真的过一遍 —— 模拟器里跑通
/// 就等于真客户端能跑通。代价是服务得在跑（UI 负责提示 + 一键启动）。
class ChatSimulator {
  ChatSimulator._();

  static const Duration defaultTimeout = Duration(minutes: 3);

  /// 本机代理的 base url。listenHost 是 0.0.0.0 时得自己换成回环地址，
  /// 不能拿通配地址去连。
  static Uri endpoint(ProxyConfig config) => Uri(
    scheme: 'http',
    host: config.listenHost == '0.0.0.0' ? '127.0.0.1' : config.listenHost,
    port: config.listenPort,
    path: '/v1/chat/completions',
  );

  /// 模拟请求要用的密钥：本机自己调自己，取第一个启用的即可。
  /// 没配密钥时留空 —— 服务没设防，本来就该放行。
  static String apiKeyOf(ProxyConfig config) {
    for (final k in config.apiKeys) {
      if (k.enabled && k.key.trim().isNotEmpty) return k.key.trim();
    }
    return '';
  }

  /// 「换模型」选择器里能给的具体模型名：这一组（上游）已启用条目的对外名，
  /// 去重保序，排除 [routeName]（那是「全部」的请求目标，本身就是组对外名）。
  static List<String> groupModelNamesOf(Upstream upstream, String routeName) =>
      <String>{
        for (final m in upstream.models)
          if (m.enabled &&
              m.publicName.trim().isNotEmpty &&
              m.publicName != routeName)
            m.publicName,
      }.toList();

  /// 请求体：界面上这串消息按顺序整串带出去，失败提示那条不算历史。
  /// [includeImages] = false 时图片附件不进请求体（只留文字），
  /// 给「这条车道是纯文本的」那种情况当退路。
  static String bodyOf({
    required String model,
    required List<ChatMsg> messages,
    double? temperature,
    bool includeImages = true,
  }) => jsonEncode({
    'model': model,
    'messages': [
      for (final m in messages)
        if (m.sendable(includeImages: includeImages))
          m.toWire(includeImages: includeImages),
    ],
    'stream': false,
    'temperature': ?temperature,
  });

  /// 把 headers 装好（鉴权用本机第一个启用的密钥；没配密钥就裸发）。
  ///
  /// 额外带上 [kSimRequestHeader]：这是「我是模拟请求」的唯一身份，
  /// 峰谷时段这类限流门禁靠它放行 —— 模拟器本来就是自己调试用的窗口，
  /// 不该被自己配的策略挡在门外。
  static void _applyHeaders(HttpClientRequest req, ProxyConfig config) {
    req.headers.contentType = ContentType.json;
    req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    req.headers.set(kSimRequestHeader, '1');
    final key = apiKeyOf(config);
    if (key.isNotEmpty) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
    }
  }

  static Future<ChatSimResult> send({
    required ProxyConfig config,
    required String model,
    required List<ChatMsg> messages,
    double? temperature,
    bool includeImages = true,
    Duration timeout = defaultTimeout,
  }) async {
    final body = bodyOf(
      model: model,
      messages: messages,
      temperature: temperature,
      includeImages: includeImages,
    );

    final sw = Stopwatch()..start();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..autoUncompress = false;
    try {
      final req = await client.postUrl(endpoint(config)).timeout(timeout);
      _applyHeaders(req, config);
      req.add(utf8.encode(body));
      final res = await req.close().timeout(timeout);
      // 真实车道在响应头里（响应体的 model 只会回显对外名）。
      // 必须在读取 body 之前拿，读完 header 就关了。
      final lane = res.headers.value(kServedLaneHeader);
      final text = await res
          .transform(utf8.decoder)
          .join()
          .timeout(timeout, onTimeout: () => '');
      final elapsed = sw.elapsedMilliseconds;
      return _parse(res.statusCode, text, elapsed, lane: lane);
    } on SocketException catch (e) {
      return ChatSimResult(
        ok: false,
        content: '连不上本机代理：${e.osError?.message ?? e.message}',
        elapsedMs: sw.elapsedMilliseconds,
      );
    } on TimeoutException {
      return ChatSimResult(
        ok: false,
        content: '等待超时（${timeout.inSeconds}s）',
        elapsedMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      return ChatSimResult(
        ok: false,
        content: _brief('$e'),
        elapsedMs: sw.elapsedMilliseconds,
      );
    } finally {
      client.close(force: true);
    }
  }

  /// **只发不等**：把请求发给本机代理就返回，不解析回复、也不追加 assistant。
  ///
  /// 请求照样真的过一遍链路（请求日志 / token 统计 / 车道容灾全都算），
  /// 适合「就想发一条看看通不通、不想把模型跑满」的情况。与 [send] 的差别
  /// 只在**等不等正文**：这里连上、把 body 交出去就返回。
  ///
  /// ⚠️ 返回时**不能**顺手 `client.close(force: true)` —— 掐连接等于把刚发出去
  /// 的那次生成一起取消，那就成了「没发」而不是「不等」。所以连接交给后台那条
  /// 链，响应真到了再把正文抽干（drain，让网关正常收尾）并关掉。
  ///
  /// 只有「连不上 / 连接超时」这类**发送本身**的失败会同步报回来（那时确实
  /// 什么都没发出去）；状态码是多少、模型答了什么，这一路一概不管。
  static Future<ChatSimResult> sendOnly({
    required ProxyConfig config,
    required String model,
    required List<ChatMsg> messages,
    double? temperature,
    bool includeImages = true,
    Duration connectTimeout = const Duration(seconds: 10),
  }) async {
    final body = bodyOf(
      model: model,
      messages: messages,
      temperature: temperature,
      includeImages: includeImages,
    );

    final sw = Stopwatch()..start();
    final client = HttpClient()
      ..connectionTimeout = connectTimeout
      ..autoUncompress = false;
    try {
      final req = await client
          .postUrl(endpoint(config))
          .timeout(connectTimeout);
      _applyHeaders(req, config);
      req.add(utf8.encode(body));
      // close() 的 future 丢后台：调用它才真正把 body 冲出去，
      // 但这里不等它完成。
      unawaited(
        req
            .close()
            .then((res) => res.drain<void>())
            .catchError((Object _) {})
            .whenComplete(() => client.close(force: true)),
      );
      return ChatSimResult(
        ok: true,
        content: '',
        model: model,
        elapsedMs: sw.elapsedMilliseconds,
      );
    } on SocketException catch (e) {
      client.close(force: true);
      return ChatSimResult(
        ok: false,
        content: '连不上本机代理：${e.osError?.message ?? e.message}',
        elapsedMs: sw.elapsedMilliseconds,
      );
    } on TimeoutException {
      client.close(force: true);
      return ChatSimResult(
        ok: false,
        content: '连接超时（${connectTimeout.inSeconds}s）',
        elapsedMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      client.close(force: true);
      return ChatSimResult(
        ok: false,
        content: _brief('$e'),
        elapsedMs: sw.elapsedMilliseconds,
      );
    }
  }

  static ChatSimResult _parse(
    int status,
    String text,
    int elapsedMs, {
    String? lane,
  }) {
    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) json = decoded;
    } catch (_) {}

    if (status == 200 && json != null) {
      final choices = json['choices'];
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        if (first is Map<String, dynamic>) {
          final message = first['message'];
          final content = message is Map<String, dynamic>
              ? _contentOf(message['content'])
              : null;
          if (content != null) {
            return ChatSimResult(
              ok: true,
              content: content,
              model: json['model']?.toString(),
              lane: lane,
              elapsedMs: elapsedMs,
              status: status,
              usageTokens: _usageTokensOf(json),
            );
          }
        }
      }
      return ChatSimResult(
        ok: false,
        content: '响应里没有 choices[0].message.content',
        elapsedMs: elapsedMs,
        status: status,
      );
    }

    // 非 200：把网关/上游那句话原样带出来，别自己吞掉。
    final err = json?['error'];
    final message = err is Map<String, dynamic>
        ? (err['message']?.toString() ?? text)
        : (json?['message']?.toString() ?? text);
    return ChatSimResult(
      ok: false,
      content: message.trim().isEmpty ? 'HTTP $status' : _brief(message),
      elapsedMs: elapsedMs,
      status: status,
    );
  }

  /// 响应体 usage → 上下文占用（prompt + completion，即下一轮请求要带的
  /// 总量）。上游没给 usage 返回 0，界面退回字数估算。
  static int _usageTokensOf(Map<String, dynamic> json) {
    final usage = json['usage'];
    if (usage is! Map<String, dynamic>) return 0;
    final prompt = (usage['prompt_tokens'] as num?)?.toInt() ?? 0;
    final completion = (usage['completion_tokens'] as num?)?.toInt() ?? 0;
    return prompt + completion;
  }

  /// content 既可能是字符串，也可能是多段 [{'type':'text','text':...}]。
  static String? _contentOf(Object? raw) {
    if (raw is String) return raw;
    if (raw is List) {
      final parts = <String>[];
      for (final p in raw) {
        if (p is String) {
          parts.add(p);
        } else if (p is Map<String, dynamic>) {
          final t = p['text'];
          if (t is String) parts.add(t);
        }
      }
      return parts.isEmpty ? null : parts.join();
    }
    return null;
  }

  static String _brief(String s) {
    s = s.replaceAll('\n', ' ').trim();
    return s.length > 300 ? '${s.substring(0, 300)}…' : s;
  }
}

/// 一次对话模拟的会话状态（消息、发送中、错误）。
///
/// 刻意只活在页面里、不持久化：这是「拿这组模型试一把」的沙盒，
/// 不是聊天记录本 —— 退出页面就丢掉，免得攒一堆没用的历史。
/// 粗估 token 数。opencode 的思路是 chars/4；对 CJK 按 ~0.6 token/字
/// 折算，不然中文会被低估到没法看。只在拿不到上游 usage 时兜底用。
int estimateContextTokens(String text) {
  if (text.isEmpty) return 0;
  var cjk = 0;
  for (final rune in text.runes) {
    if ((rune >= 0x3400 && rune <= 0x9FFF) ||
        (rune >= 0xF900 && rune <= 0xFAFF) ||
        (rune >= 0x3040 && rune <= 0x30FF) ||
        (rune >= 0xFF00 && rune <= 0xFFEF)) {
      cjk++;
    }
  }
  final other = text.length - cjk;
  return (cjk * 0.6 + other / 4).ceil();
}

class ChatSimController extends ChangeNotifier {
  ChatSimController({
    required this.model,
    required this.config,
    this.scope = '',
    this.groupModels = const [],
  }) : messages = [ChatMsg(ChatRole.system, defaultSystemPrompt)],
       activeModel = model {
    // 接着上次的模拟模型（校验一下还在可选集合里，模型被删了就回落对外名）
    final saved = chatSimStore.selectedModelOf(scope);
    if (saved != null && (saved == model || groupModels.contains(saved))) {
      activeModel = saved;
    }
    // 上次应用的角色卡 id（只管显示；场景本体在 restore() 里跟着消息回来）
    appliedCharacterId = chatSimStore.characterOf(scope);
  }

  /// 默认系统提示词（第一次进来就有一个能直接发的对话）。
  static const String defaultSystemPrompt = 'You are a helpful assistant.';

  /// 对外模型名（走路由就填路由名，如 zen-free）。选「全部」时就是请求目标。
  final String model;

  /// 本组内可选的具体模型（对外名，去重保序，不含 [model] 本身）。
  /// 对话模拟页的「换模型」选择器只能从这里挑 —— 换到别的组没有意义。
  final List<String> groupModels;

  /// 当前请求实际要用的模型名：[model]（= 全部/整组）或 groupModels 之一。
  /// 选「全部」时请求打组的对外名，组内哪个模型接住都带着这段上下文；
  /// 选具体模型时只有它收到这段上下文。
  String activeModel;

  final ProxyConfig config;

  /// 这段对话存在哪一格（一般给模型组的 id）。空串 = 不落盘。
  final String scope;

  final List<ChatMsg> messages;

  bool _sending = false;
  bool get sending => _sending;

  /// 是不是从本地恢复出来的（页面上提一句「接着上次聊」）。
  bool restored = false;

  /// 当前应用的角色卡 id（null = 默认场景）。只做界面展示与回显，
  /// 场景本身跟着 messages 走；手动改过 system 消息后这里照旧显示，
  /// 因为「角色卡」只是铺设场景的入口，铺设完就交给用户折腾了。
  String? appliedCharacterId;

  /// 应用角色卡：整段对话重铺成「人设 system + 预制问答」。
  ///
  /// 这是「给模拟器换个场景」的语义，不是追加——旧对话（含旧 system）
  /// 与新场景混在一起只会串味，所以直接替换并覆盖存档。
  /// [characterId] 传 null 等价于 [clear]：回到默认场景。
  void applyCharacter(CharacterCard character) {
    messages
      ..clear()
      ..add(ChatMsg(ChatRole.system, character.prompt));
    for (final p in character.presets) {
      if (p.user.trim().isNotEmpty) messages.add(ChatMsg(ChatRole.user, p.user));
      if (p.assistant.trim().isNotEmpty) {
        messages.add(ChatMsg(ChatRole.assistant, p.assistant));
      }
    }
    appliedCharacterId = character.id;
    chatSimStore.setCharacter(scope, character.id);
    restored = false;
    // 场景是「整段换掉」的，立刻压进存档：别指望页面退出时的兜底
    // （进程被直接杀掉时 dispose 不会跑，新场景就丢了）。
    _persist();
    _notify();
  }

  /// 回到默认场景（与应用角色卡互为反操作，入口在角色卡页的「默认」）。
  void resetCharacter() {
    clear();
  }

  bool _disposed = false;

  /// 当前请求目标对应的模型条目（上下文占用环拿它的
  /// effectiveContextLength / maxOutputTokens 当分母）。
  ModelEntry? get activeModelEntry {
    for (final u in config.upstreams) {
      for (final m in u.models) {
        if (m.publicName == activeModel) return m;
      }
    }
    return null;
  }

  /// 现在选中的是不是「全部 / 整组」。
  bool get isAllModel => activeModel == model;

  /// 图片要不要真的随消息发出去（默认发）。
  ///
  /// 关掉的场景是「这条车道只会吃纯文本」：多模态 content 打过去直接 400，
  /// 这时把图留在界面上展示、只发文字。只在当前页面内记住，不持久化。
  bool sendImages = true;

  /// 切换「发送图片 / 仅发文字」，返回切换后的值（页面据此 toast 一声）。
  bool toggleSendImages() {
    sendImages = !sendImages;
    _notify();
    return sendImages;
  }

  /// 这段对话里能发出去的图片总数（关了开关时请求体里就没有它们了）。
  int get imageCount {
    var n = 0;
    for (final m in messages) {
      if (!m.error) n += m.imageAttachments.length;
    }
    return n;
  }

  /// 有没有「发得出去」的内容：至少一条不空的文字，或（开着带图时）一张图。
  bool get hasSendable =>
      messages.any((m) => m.sendable(includeImages: sendImages));

  /// 上下文占用（token）：精确值 = 上一轮响应 usage 的 prompt+completion
  /// （对齐 opencode 的「最后一次带用量的助手消息」—— 那正好是下一轮
  /// 请求要带的总量）；没有 usage 就按字数粗估（图片按张粗估）。
  /// 返回 (tokens, 是否估算)。
  (int, bool) contextUsage() {
    for (final m in messages.reversed) {
      if (m.role == ChatRole.assistant && m.usageTokens > 0) {
        return (m.usageTokens, false);
      }
    }
    var sum = 0;
    for (final m in messages) {
      if (m.error) continue;
      sum += estimateContextTokens(m.content);
      if (sendImages) sum += m.imageAttachments.length * kImageTokenEstimate;
    }
    return (sum, true);
  }

  /// 占用环的分母：当前请求目标的对外声明上下文（没配回退默认 1M）。
  int get contextLimit =>
      activeModelEntry?.effectiveContextLength ?? kDefaultContextLength;

  /// 上下文详情弹窗要的那组数字（两套 UI 共用算法、各自排版）。
  /// [percent] 0..100（未截断，界面自己 clamp）；
  /// [label] 已经是给人看的百分比字符串（小于 1% 带一位小数）。
  ({
    double percent,
    String label,
    int used,
    int limit,
    bool estimated,
    int images,
    int messages,
    int maxOutput,
    String model,
  }) contextDetails() {
    final (used, estimated) = contextUsage();
    final limit = contextLimit;
    final raw = limit > 0 ? used / limit * 100 : 0.0;
    // 上下文动辄 1M：小于 1% 显示一位小数，不然小对话永远 0%
    final label = raw < 1 && used > 0
        ? raw.toStringAsFixed(1)
        : raw.round().toString();
    var n = 0;
    for (final m in messages) {
      if (!m.error) n++;
    }
    return (
      percent: raw,
      label: label,
      used: used,
      limit: limit,
      estimated: estimated,
      images: imageCount,
      messages: n,
      maxOutput: activeModelEntry?.maxOutputTokens ?? 0,
      model: activeModel,
    );
  }

  /// 换模拟模型（只允许组对外名或组内模型名）。选择按 scope 记住，
  /// 下次进页面还是它；对话本身不动 —— 换模型接着同一份历史聊。
  void setActiveModel(String name) {
    if (name != model && !groupModels.contains(name)) return;
    if (name == activeModel) return;
    activeModel = name;
    chatSimStore.setSelectedModel(scope, isAllModel ? null : name);
    _notify();
  }

  @override
  void dispose() {
    // 退出前把最后的状态压进 store（store 自己防抖落盘）
    _persist();
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 把这段对话同步进本地存档。
  void _persist() {
    if (scope.isEmpty) return;
    chatSimStore.save(scope, messages);
  }

  /// 打开页面时调：有存档就接着上次的对话，没有就留默认那条系统提示词。
  ///
  /// 这一步是「下游能带上历史」的前提 —— 历史只活在内存里的话，重进页面
  /// 就是一条空对话，发出去的请求跟第一次一样。
  void restore() {
    if (scope.isEmpty) return;
    final saved = chatSimStore.messagesOf(scope);
    if (saved.isEmpty) return;
    // 只有一条默认系统提示词 == 等于没聊过（清空后就是这状态），别当成「恢复」
    if (saved.length == 1 &&
        saved.single.role == ChatRole.system &&
        saved.single.content == defaultSystemPrompt) {
      return;
    }
    messages
      ..clear()
      ..addAll([
        for (final m in saved)
          ChatMsg(
            m.role,
            m.content,
            elapsedMs: m.elapsedMs,
            error: m.error,
            model: m.model,
            lane: m.lane,
            usageTokens: m.usageTokens,
            attachments: [for (final a in m.attachments) a.copy()],
          ),
      ]);
    restored = true;
    _notify();
  }

  /// 发一轮：把当前消息列表（含历史）整条发给本机代理，回答追加为 assistant。
  ///
  /// 历史天然跟着走 —— 这就是「模拟下游客户端」的意义：请求体里带的就是
  /// 界面上这串消息。
  Future<void> send() async {
    if (_sending) return;
    if (!hasSendable) return;
    _sending = true;
    _notify();
    try {
      final result = await ChatSimulator.send(
        config: config,
        model: activeModel,
        messages: messages,
        includeImages: sendImages,
      );
      messages.add(
        ChatMsg(
          ChatRole.assistant,
          result.content,
          elapsedMs: result.elapsedMs,
          error: !result.ok,
          model: result.model,
          lane: result.lane,
          usageTokens: result.usageTokens,
        ),
      );
      _persist();
    } finally {
      _sending = false;
      _notify();
    }
  }

  /// 只发不等：请求发出去就完事，**不追加** assistant 回答。
  ///
  /// 与 [send] 共用同一套前置检查（正在发就不重复发、空对话不发）。连不上本机
  /// 代理时仍然留一条错误提示 —— 不然点了像没反应。成功时什么都不加，这正是
  /// 「不请求模型回复」的意思；反馈由页面那条 toast 给，所以这里把「到底发出去
  /// 没有」返回给调用方。
  Future<bool> sendOnly() async {
    if (_sending) return false;
    if (!hasSendable) return false;
    _sending = true;
    _notify();
    try {
      final result = await ChatSimulator.sendOnly(
        config: config,
        model: activeModel,
        messages: messages,
        includeImages: sendImages,
      );
      if (!result.ok) {
        messages.add(
          ChatMsg(
            ChatRole.assistant,
            result.content,
            elapsedMs: result.elapsedMs,
            error: true,
          ),
        );
      }
      _persist();
      return result.ok;
    } finally {
      _sending = false;
      _notify();
    }
  }

  /// 追加一条消息；[content] 为空则只占位。[attachments] 里的图片会随这条
  /// 消息进请求体（除非页面关了「发送图片」），文件只展示。
  void add(
    ChatRole role, [
    String content = '',
    List<ChatAttachment> attachments = const [],
  ]) {
    messages.add(ChatMsg(role, content, attachments: List.of(attachments)));
    _persist();
    _notify();
  }

  /// 编辑某条；改完该条之后的都丢掉（重发时的历史就是这个前缀）。
  void edit(
    int index,
    ChatRole role,
    String content, {
    bool truncateAfter = false,
  }) {
    if (index < 0 || index >= messages.length) return;
    messages[index]
      ..role = role
      ..content = content
      // 手改过就不再是「模型的失败回答」，参与后续请求。
      ..error = false
      // 也不再是那个模型的回答了，页脚别挂着错的名字。
      ..model = null
      ..lane = null;
    if (truncateAfter && index + 1 < messages.length) {
      messages.removeRange(index + 1, messages.length);
    }
    _persist();
    _notify();
  }

  void removeAt(int index) {
    if (index < 0 || index >= messages.length) return;
    messages.removeAt(index);
    _persist();
    _notify();
  }

  /// 重新生成：丢掉最后一条 assistant（失败的提示也算），再发一次。
  Future<void> regenerate() async {
    while (messages.isNotEmpty && messages.last.role == ChatRole.assistant) {
      messages.removeLast();
    }
    _notify();
    await send();
  }

  /// 「重新回答」某一条助手消息：从第 [index] 条（含）起整段丢掉，再发一次。
  ///
  /// 与 [edit] 的 `truncateAfter` 一个口径 —— 重发的历史就是 index 之前那段
  /// 前缀。丢掉后若末尾还挂着 assistant（index 指到了 user 消息上），一并剥掉，
  /// 保证请求以 user 轮结尾；前缀里没有 user 消息就什么也不做（没东西可问）。
  Future<void> regenerateFrom(int index) async {
    if (index < 0 || index >= messages.length) return;
    messages.removeRange(index, messages.length);
    while (messages.isNotEmpty && messages.last.role == ChatRole.assistant) {
      messages.removeLast();
    }
    if (!messages.any((m) => m.role == ChatRole.user)) {
      _persist();
      _notify();
      return;
    }
    _persist();
    _notify();
    await send();
  }

  void clear() {
    messages
      ..clear()
      ..add(ChatMsg(ChatRole.system, defaultSystemPrompt));
    restored = false;
    // 清空 = 回到默认场景，角色标记一并摘掉（不然页头上还挂着旧角色名）
    appliedCharacterId = null;
    // 清空 = 把存档也删掉（不是存一份"默认状态"）：否则下次进来又会
    // 「恢复」出刚被清掉的对话
    if (scope.isNotEmpty) chatSimStore.remove(scope);
    chatSimStore.setCharacter(scope, null);
    _notify();
  }
}

/// 字数统计，照 Chatbox 页脚那个「word count」：CJK 按字算，其余按词算。
int chatWordCount(String text) {
  var count = 0;
  var inWord = false;
  for (final rune in text.runes) {
    final isCjk =
        (rune >= 0x3040 && rune <= 0x30FF) || // 日文假名
        (rune >= 0x3400 && rune <= 0x4DBF) || // 扩展 A
        (rune >= 0x4E00 && rune <= 0x9FFF) || // 基本汉字
        (rune >= 0xAC00 && rune <= 0xD7AF) || // 谚文
        (rune >= 0xF900 && rune <= 0xFAFF); // 兼容汉字
    if (isCjk) {
      count++;
      inWord = false;
      continue;
    }
    final ch = String.fromCharCode(rune);
    if (RegExp(r'\s').hasMatch(ch)) {
      inWord = false;
      continue;
    }
    if (!inWord) {
      count++;
      inWord = true;
    }
  }
  return count;
}

/// 耗时格式化：<1s 给 0.47s，其余给 12.3s / 1m03s。
String formatElapsed(int? ms) {
  if (ms == null) return '–';
  if (ms < 1000) return '${(ms / 1000).toStringAsFixed(2)}s';
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
  final total = ms ~/ 1000;
  return '${total ~/ 60}m${(total % 60).toString().padLeft(2, '0')}s';
}
