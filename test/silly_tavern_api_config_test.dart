// SillyTavern API 配置的纯逻辑/文件层回归：
//   · resolveApiConfig 只挑「选中组里启用中的模型」，密钥取第一个启用的；
//   · applyApiConfig 按 ST 1.19 的格式写 settings.json + secrets.json
//     （secrets 是 [{id,value,label,active}] 数组，不是扁平字符串）；
//   · 写之前留 *.l2a.bak 备份。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/models/proxy_config.dart';
import 'package:local2api/services/lab/silly_tavern_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory userDir;
  final st = SillyTavernService.instance;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('l2a_st_api_test');
    // 假的 ST 安装目录（init 只检查 server.js 在不在）
    await File(p.join(root.path, 'server.js')).writeAsString('// fake');
    userDir = Directory(p.join(root.path, 'data', 'default-user'));
    await userDir.create(recursive: true);
    await File(p.join(userDir.path, 'settings.json')).writeAsString(
      '{"main_api": "koboldhorde", "custom_url": "old"}',
    );
    await File(p.join(userDir.path, 'secrets.json')).writeAsString('{}');

    SharedPreferences.setMockInitialValues({
      'lab.sillytavern.dir': root.path,
    });
    await st.init();
  });

  tearDownAll(() async {
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  ProxyConfig buildConfig() => ProxyConfig(
    listenPort: 9292,
    apiKeys: [
      ApiKeyEntry(id: 'k1', name: 'off', key: 'sk-off', enabled: false),
      ApiKeyEntry(id: 'k2', name: 'on', key: 'sk-live'),
    ],
    upstreams: [
      Upstream(
        id: 'u1',
        name: '组一',
        baseUrl: 'http://a/v1',
        managedBy: 'g1',
        models: [
          ModelEntry(publicName: 'm-a'),
          ModelEntry(publicName: 'm-b', enabled: false),
        ],
      ),
      Upstream(
        id: 'u2',
        name: '组二',
        baseUrl: 'http://b/v1',
        managedBy: 'g2',
        models: [ModelEntry(publicName: 'm-c')],
      ),
    ],
  );

  test('resolveApiConfig：按组挑模型、取第一个启用密钥', () async {
    await st.setApiSelection(groupId: 'g1');
    final cfg = st.resolveApiConfig(buildConfig(), groupName: '组一');
    expect(cfg, isNotNull);
    expect(cfg!.baseUrl, 'http://127.0.0.1:9292/v1');
    expect(cfg.model, 'm-a'); // m-b 没启用，跳过
    expect(cfg.apiKey, 'sk-live');
    expect(cfg.groupName, '组一');
  });

  test('resolveApiConfig：选了别的模型就用它，失效则回退到第一个', () async {
    await st.setApiSelection(groupId: 'g1', model: 'm-c'); // 不在组里
    expect(st.resolveApiConfig(buildConfig(), groupName: '组一')!.model, 'm-a');
    await st.setApiSelection(groupId: 'g1', model: 'm-a');
    expect(st.resolveApiConfig(buildConfig(), groupName: '组一')!.model, 'm-a');
  });

  test('resolveApiConfig：没选组 / 组里没模型都返回 null', () async {
    await st.setApiSelection(groupId: null);
    expect(st.resolveApiConfig(buildConfig(), groupName: ''), isNull);
    await st.setApiSelection(groupId: 'g-unknown');
    expect(st.resolveApiConfig(buildConfig(), groupName: ''), isNull);
  });

  test('applyApiConfig：写入 settings.json（custom 源）', () async {
    final result = await st.applyApiConfig(
      const StApiConfig(
        baseUrl: 'http://127.0.0.1:9292/v1',
        apiKey: 'sk-live',
        model: 'm-a',
        groupId: 'g1',
        groupName: '组一',
      ),
    );
    expect(result.ok, isTrue, reason: result.error);

    final doc =
        jsonDecode(
              await File(p.join(userDir.path, 'settings.json')).readAsString(),
            )
            as Map<String, dynamic>;
    expect(doc['main_api'], 'openai');
    expect(doc['chat_completion_source'], 'custom');
    expect(doc['custom_url'], 'http://127.0.0.1:9292/v1');
    expect(doc['custom_model'], 'm-a');
    expect(doc['reverse_proxy'], '');

    // 写之前留了备份
    expect(
      await File(p.join(userDir.path, 'settings.json.l2a.bak')).exists(),
      isTrue,
    );
  });

  test('applyApiConfig：secrets.json 写成 ST 1.19 的数组格式', () async {
    final doc =
        jsonDecode(
              await File(p.join(userDir.path, 'secrets.json')).readAsString(),
            )
            as Map<String, dynamic>;
    final list = doc['api_key_custom'] as List;
    final active = list.whereType<Map>().where((e) => e['active'] == true);
    expect(active, hasLength(1));
    expect(active.first['value'], 'sk-live');
    expect(active.first['id'], isA<String>());
    // 再写一次不会堆重复条目
    await st.applyApiConfig(
      const StApiConfig(
        baseUrl: 'http://127.0.0.1:9292/v1',
        apiKey: 'sk-live',
        model: 'm-a',
        groupId: 'g1',
        groupName: '组一',
      ),
    );
    final again =
        jsonDecode(
              await File(p.join(userDir.path, 'secrets.json')).readAsString(),
            )
            as Map<String, dynamic>;
    expect((again['api_key_custom'] as List), hasLength(1));
  });
}
