import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/models/config_profile.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/profile_export.dart';
import 'package:local2api/services/profile_service.dart';

/// 「查看 JSON」展示的是**有效档案**：用户更新模型后 JSON 要跟着变，
/// 不能一直停在第一次导入时的文档上；没装过（未激活）时才退回文档模板。
void main() {
  const source = ProfileSource(ProfileSourceKind.inline);
  final doc = jsonEncode({
    'id': 'demo',
    'name': 'DEMO',
    'upstreams': [
      {
        'id': 'u-demo',
        'name': 'Demo',
        'baseUrl': 'https://a.example/v1',
        'models': [
          {'publicName': 'm1', 'target': 'm1'},
        ],
      },
    ],
  });

  Map<String, dynamic> firstUpstream(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    return (j['upstreams'] as List).first as Map<String, dynamic>;
  }

  test('JSON 跟着已装上游走：更新模型后不再是首导入的内容', () {
    final profile = parseConfigProfile(doc, source: source);
    final config = ProxyConfig();
    ProfileService.installProfile(config, profile, addedEnabled: true);

    // 像「模型」页那样改掉已装上游的模型列表
    final installed = ProfileService.upstreamOf(config, 'u-demo')!;
    installed.models
      ..clear()
      ..add(ModelEntry(publicName: 'm2', target: 'm2'));
    installed.apiKey = 'sk-secret';

    final u = firstUpstream(profileJsonText(profile, config));
    final models = u['models'] as List;
    expect(models, hasLength(1));
    expect((models.first as Map<String, dynamic>)['publicName'], 'm2');
    // 看/分享用的 JSON 不能把用户填的密钥带出去
    expect(u['apiKey'], '');
  });

  test('没装过（未激活）时退回文档模板', () {
    final profile = parseConfigProfile(doc, source: source);
    final u = firstUpstream(profileJsonText(profile, ProxyConfig()));
    expect(
      ((u['models'] as List).first as Map<String, dynamic>)['publicName'],
      'm1',
    );
  });
}
