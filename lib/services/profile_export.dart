import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../models/config_profile.dart';
import '../models/proxy_config.dart';

/// 组的 JSON 文本（格式化）——「查看 JSON / 导出」共用这一份。
///
/// 用**有效档案**而不是原始订阅文档：用户起过的名字、写过的说明都在里面，
/// 上游更以配置里**已装**的那条为准 —— 「模型」页改过的模型列表、车道页
/// 调过的开关与回退链、刷新出来的实时车道都体现得出来，看到的就是这一组
/// 现在的真实样子（没装过（未激活）时才退回文档模板）。
/// 序列化前抹掉 apiKey：这一份是看/分享用的，不能把用户填的密钥带出去。
String profileJsonText(ConfigProfile profile, ProxyConfig config) =>
    const JsonEncoder.withIndent(
      '  ',
    ).convert(_effectiveProfile(profile, config).toJson());

/// 有效档案：已装上游（managedBy == profile.id）顶替文档模板里同 id 的那条。
ConfigProfile _effectiveProfile(ConfigProfile profile, ProxyConfig config) {
  final installed = [
    for (final u in config.upstreams)
      if (u.managedBy == profile.id) u,
  ];
  final src = installed.isEmpty ? profile.upstreams : installed;
  return ConfigProfile(
    schema: profile.schema,
    id: profile.id,
    name: profile.name,
    description: profile.description,
    source: profile.source,
    upstreams: [
      for (final u in src) Upstream.fromJson({...u.toJson(), 'apiKey': ''}),
    ],
  );
}

/// 单个上游的 JSON 文本（格式化）——「查看 JSON / 导出」共用这一份。
///
/// 序列化前抹掉 apiKey：这一份是看/分享用的，不能把用户填的密钥带出去。
/// 与 [profileJsonText] 同一个原则。
String upstreamJsonText(Upstream upstream) => const JsonEncoder.withIndent(
  '  ',
).convert(Upstream.fromJson({...upstream.toJson(), 'apiKey': ''}).toJson());

/// 导出文本成文件。返回落盘路径；用户取消返回 null。
///
/// 移动端走系统「另存为」（SAF，bytes 交给系统写），桌面端先问路径再自己写。
Future<String?> exportTextFile({
  required String fileName,
  required String text,
}) async {
  final bytes = Uint8List.fromList(utf8.encode(text));
  if (Platform.isAndroid || Platform.isIOS) {
    return FilePicker.platform.saveFile(
      fileName: fileName,
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
  }
  final path = await FilePicker.platform.saveFile(
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );
  if (path == null) return null;
  await File(path).writeAsString(text);
  return path;
}

/// 组名 → 安全的文件名（去路径分隔符与保留字符）。
String jsonFileNameFor(String name) {
  final safe = name
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
      .replaceAll(RegExp(r'_+'), '_');
  final base = safe.isEmpty ? 'profile' : safe;
  return '${base.length > 48 ? base.substring(0, 48) : base}.json';
}
