import 'dart:convert';

import 'proxy_config.dart';

/// 当前档案文档格式版本。解析时只认这一版，别的直接拒。
const int kProfileSchema = 1;

/// 档案从哪来。决定「更新」这个动作对它意味着什么。
enum ProfileSourceKind {
  /// 随包内置，不落盘、不可删，跟着版本自更新。
  builtin,

  /// 远程订阅地址，可反复拉取。
  url,

  /// 从本地文件导入，导入后内容就固定了。
  file,

  /// 用户直接粘贴的 JSON。
  inline,
}

class ProfileSource {
  const ProfileSource(this.kind, {this.url = '', this.fileName});

  const ProfileSource.builtin() : this(ProfileSourceKind.builtin);

  final ProfileSourceKind kind;

  /// kind == url 时的订阅地址。
  final String url;

  /// kind == file 时的原始文件名（只用于展示）。
  final String? fileName;

  bool get isRemote => kind == ProfileSourceKind.url;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    if (url.isNotEmpty) 'url': url,
    if (fileName != null) 'fileName': fileName,
  };

  factory ProfileSource.fromJson(Map<String, dynamic> j) {
    final kind = switch (j['kind'] as String?) {
      'url' => ProfileSourceKind.url,
      'file' => ProfileSourceKind.file,
      'inline' => ProfileSourceKind.inline,
      _ => ProfileSourceKind.builtin,
    };
    return ProfileSource(
      kind,
      url: (j['url'] as String?) ?? '',
      fileName: j['fileName'] as String?,
    );
  }
}

/// 一份配置档案文档：只描述「模型从哪来」，即一批上游模板。
///
/// 刻意不含 listenPort / listenHost / apiKeys / cidrRules / corsEnabled /
/// autoStart —— 那些是本机的服务身份与安全边界，不是可分享的内容。
/// 让一个粘贴进来的或远程拉来的 JSON 能改监听地址、能删 CIDR 拒绝规则，
/// 等于给订阅源开了个静默的口子。解析器只读它认识的键，其余一律忽略。
class ConfigProfile {
  const ConfigProfile({
    required this.schema,
    required this.id,
    required this.name,
    required this.source,
    required this.upstreams,
    this.description = '',
  });

  final int schema;

  /// 稳定 slug，全局唯一。内置那份是 `opencodezen`。
  final String id;

  final String name;

  /// 这个模型组的说明（用户新建时自己填的，展示在发现页卡片上）。
  ///
  /// 空串表示没写。独立于 [name]：名字是「这一组叫什么」，说明是「这一组
  /// 是什么 / 从哪来 / 有什么注意事项」。
  final String description;

  final ProfileSource source;

  /// 上游模板。装进 ProxyConfig 时按 id 认领，见 ProfileService。
  final List<Upstream> upstreams;

  /// 换个名字 / 说明（重命名组时用）。其余字段原样保留。
  ConfigProfile withLabel({String? name, String? description}) => ConfigProfile(
    schema: schema,
    id: id,
    name: (name == null || name.trim().isEmpty) ? this.name : name.trim(),
    description: description ?? this.description,
    source: source,
    upstreams: upstreams,
  );

  /// 文档里引用到的上游真实模型名（跨上游去重）。
  ///
  /// 取 [ModelEntry.attempts] 而不是 publicName：路由条目的 publicName 是对外
  /// 暴露名（比如 `zen-free`），真正的车道藏在它的 target + fallbacks 里。
  /// 卡片摘要与探测都用这一份。
  List<String> get lanes => <String>{
    for (final u in upstreams)
      for (final m in u.models) ...m.attempts,
  }.toList();

  Map<String, dynamic> toJson() => {
    'schema': schema,
    'id': id,
    'name': name,
    if (description.trim().isNotEmpty) 'description': description,
    'source': source.toJson(),
    'upstreams': [for (final u in upstreams) u.toJson()],
  };
}

/// 档案的运行时状态，与文档分开存：文档是可重新拉取的内容，
/// 状态是本机对它的处置（激活了没、上次什么时候更新、报了什么错）。
class ProfileState {
  ProfileState({
    required this.profileId,
    this.active = false,
    this.lastUpdateMs,
    this.lastError,
    this.etag,
    this.customized = false,
    this.updateIntervalHours,
    this.updateAvailable = false,
  });

  final String profileId;

  bool active;

  int? lastUpdateMs;

  /// 上次更新失败的原因（已按用户可读形式收敛过，不是堆栈）。
  String? lastError;

  /// 远程档案的条件请求标记。
  String? etag;

  /// 用户手改过归属上游（比如换了 baseUrl），更新时不要覆盖他的改动。
  bool customized;

  /// null = 只手动更新。
  int? updateIntervalHours;

  /// 未激活的远程档案拉到了新内容，等用户决定要不要用上。
  bool updateAvailable;

  Map<String, dynamic> toJson() => {
    'profileId': profileId,
    'active': active,
    if (lastUpdateMs != null) 'lastUpdateMs': lastUpdateMs,
    if (lastError != null) 'lastError': lastError,
    if (etag != null) 'etag': etag,
    'customized': customized,
    if (updateIntervalHours != null) 'updateIntervalHours': updateIntervalHours,
    'updateAvailable': updateAvailable,
  };

  factory ProfileState.fromJson(Map<String, dynamic> j) => ProfileState(
    profileId: (j['profileId'] as String?) ?? '',
    active: (j['active'] as bool?) ?? false,
    lastUpdateMs: (j['lastUpdateMs'] as num?)?.toInt(),
    lastError: j['lastError'] as String?,
    etag: j['etag'] as String?,
    customized: (j['customized'] as bool?) ?? false,
    updateIntervalHours: (j['updateIntervalHours'] as num?)?.toInt(),
    updateAvailable: (j['updateAvailable'] as bool?) ?? false,
  );
}

/// 解析失败的原因码。UI 按码取本地化文案，别把 jsonDecode 的堆栈甩给用户。
enum ProfileFormatError {
  /// 空串 / 全空白。
  empty,

  /// 不是合法 JSON。用户填了个 Clash YAML 订阅地址时最常见。
  notJson,

  /// 是 JSON 但顶层不是对象（比如给了个数组）。
  notObject,

  /// schema 字段不认识。
  unsupportedSchema,

  /// 推不出 id（既没写 id 也没写 name）。
  missingId,

  /// 一个上游都没有，装上去什么也不会发生。
  noUpstreams,

  /// 声明的 id 和已有档案（含内置）撞了。
  duplicateId,
}

class ProfileFormatException implements Exception {
  const ProfileFormatException(this.code, [this.detail]);

  final ProfileFormatError code;

  /// 原始异常的描述，只进日志不进 UI。
  final String? detail;

  @override
  String toString() => 'ProfileFormatException(${code.name}: $detail)';
}

/// 把一段档案文本解析成 [ConfigProfile]。
///
/// [source] 由调用方给定（导入渠道是调用方知道的，文档里写了也不采信），
/// 这样文档自己没法谎报来源。
ConfigProfile parseConfigProfile(String raw, {required ProfileSource source}) {
  final text = raw.trim();
  if (text.isEmpty) {
    throw const ProfileFormatException(ProfileFormatError.empty);
  }

  final dynamic decoded;
  try {
    decoded = jsonDecode(text);
  } catch (e) {
    throw ProfileFormatException(ProfileFormatError.notJson, '$e');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const ProfileFormatException(ProfileFormatError.notObject);
  }

  // 未知顶层键（含 listenPort / apiKeys / cidrRules 这些）在这里被自然忽略：
  // 只取认识的字段，剩下的连读都不读。
  final schema = switch (decoded['schema']) {
    null => kProfileSchema,
    final num n => n.toInt(),
    _ => throw const ProfileFormatException(
      ProfileFormatError.unsupportedSchema,
    ),
  };
  if (schema != kProfileSchema) {
    throw ProfileFormatException(
      ProfileFormatError.unsupportedSchema,
      'schema=$schema',
    );
  }

  final id = _slug(
    (decoded['id'] as String?) ?? (decoded['name'] as String?) ?? '',
  );
  if (id.isEmpty) {
    throw const ProfileFormatException(ProfileFormatError.missingId);
  }

  final rawUpstreams = decoded['upstreams'];
  if (rawUpstreams is! List || rawUpstreams.isEmpty) {
    throw const ProfileFormatException(ProfileFormatError.noUpstreams);
  }

  final upstreams = <Upstream>[];
  for (final entry in rawUpstreams) {
    if (entry is! Map<String, dynamic>) continue;
    final u = Upstream.fromJson(entry);
    if (u.id.isEmpty || u.baseUrl.isEmpty) continue;
    // 可分享的档案文档里不该带密钥：真需要 Key 的端点装好之后在「模型」页填。
    u.apiKey = '';
    upstreams.add(u);
  }
  if (upstreams.isEmpty) {
    throw const ProfileFormatException(ProfileFormatError.noUpstreams);
  }

  final rawName = ((decoded['name'] as String?) ?? '').trim();
  final rawDesc = ((decoded['description'] as String?) ?? '').trim();
  return ConfigProfile(
    schema: schema,
    id: id,
    name: rawName.isEmpty ? id : rawName,
    description: rawDesc,
    source: source,
    upstreams: upstreams,
  );
}

/// 档案 id 要能当持久化键的一部分用，所以只留安全字符。
String _slug(String input) {
  final s = input
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return s.length > 64 ? s.substring(0, 64) : s;
}
