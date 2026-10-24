// dsh 配置合并的纯函数回归：
//   · 写入不能把用户已有的 provider（deepseek / lol …）冲掉；
//   · 空配置文件（`[]` + 注释头）也能正确追加；
//   · 重复写入不会产生第二条 llm-pi-ai 行。
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/services/lab/dsh_android_patches.dart';
import 'package:local2api/services/lab/dsh_config.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('readDshProviders', () {
    test('空配置返回空表', () {
      expect(readDshProviders('# comment\n[]\n'), isEmpty);
    });

    test('读出现有 provider', () {
      const source = '''
- id: llm-pi-ai
  name: "@deepseek-ai/dsh-llm-pi-ai"
  config:
    providers:
      lol:
        api: openai-completions
        baseURL: http://192.168.3.34:9292/v1
        models:
          - id: zen-free
''';
      final providers = readDshProviders(source);
      expect(providers.keys, contains('lol'));
      expect(
        (providers['lol'] as Map)['baseURL'],
        'http://192.168.3.34:9292/v1',
      );
    });
  });

  group('upsertEntry', () {
    test('空文档写入后只有一条入口', () {
      final next = upsertEntry(
        '# header\n[]\n',
        'llm-pi-ai',
        buildLlmpiAiEntry({
          kDshProviderId: buildLocal2ApiProvider(
            baseUrl: 'http://127.0.0.1:8787/v1',
            models: const ['gpt-4o', 'claude-3'],
          ),
        }),
      );
      expect(RegExp('id: llm-pi-ai').allMatches(next).length, 1);
      expect(next, contains('http://127.0.0.1:8787/v1'));
      final doc = loadYaml(next);
      expect(doc, isA<YamlList>());
      expect((doc as YamlList).length, 1);
    });

    test('保留其它 provider 与其它插件行', () {
      const source = '''
- id: ui-chat
  config:
    transcriptView: standard
- id: llm-pi-ai
  name: "@deepseek-ai/dsh-llm-pi-ai"
  config:
    providers:
      lol:
        api: openai-completions
        baseURL: http://192.168.3.34:9292/v1
        models:
          - id: zen-free
- id: agent-default-model
  config:
    provider: lol
    model: zen-free
''';
      final providers = readDshProviders(source);
      providers[kDshProviderId] = buildLocal2ApiProvider(
        baseUrl: 'http://127.0.0.1:8787/v1',
        models: const ['m1'],
      );
      var next = upsertEntry(source, 'llm-pi-ai', buildLlmpiAiEntry(providers));
      next = upsertEntry(
        next,
        'agent-default-model',
        buildDefaultModelEntry(provider: kDshProviderId, model: 'm1'),
      );

      expect(next, contains('ui-chat'));
      expect(next, contains('transcriptView: standard'));
      final doc = loadYaml(next) as YamlList;
      expect(doc.length, 3);
      final merged = readDshProviders(next);
      expect(merged.keys, containsAll(['lol', kDshProviderId]));
      expect((merged[kDshProviderId] as Map)['models'], isA<List>());
    });

    test('重复写入不会堆第二条 llm-pi-ai', () {
      var source = upsertEntry(
        '',
        'llm-pi-ai',
        buildLlmpiAiEntry({
          kDshProviderId: buildLocal2ApiProvider(
            baseUrl: 'http://127.0.0.1:8787/v1',
            models: const ['a'],
          ),
        }),
      );
      source = upsertEntry(
        source,
        'llm-pi-ai',
        buildLlmpiAiEntry({
          kDshProviderId: buildLocal2ApiProvider(
            baseUrl: 'http://127.0.0.1:8787/v1',
            models: const ['a', 'b'],
          ),
        }),
      );
      expect(RegExp('id: llm-pi-ai').allMatches(source).length, 1);
      final route = readDshProviders(source)[kDshProviderId] as Map;
      final models = route['models'] as List;
      final efforts = (models.first as Map)['reasoningEfforts'] as Map;
      // `off:` 必须写成「有键无值」—— JSON 的 null 会被 dsh 拒绝。
      expect(efforts.containsKey('off'), isTrue);
      expect(efforts['off'], isNull);
      expect(source, isNot(contains('"off"')));
      expect(source, contains('off:'));
    });
  });

  test('provider 配置形状符合 dsh 的 pi-ai schema', () {
    final provider = buildLocal2ApiProvider(
      baseUrl: 'http://127.0.0.1:8787/v1',
      models: const ['m1'],
    );
    expect(provider['apiKeyEnv'], kDshApiKeyEnv);
    expect(provider['api'], 'openai-completions');
    final models = provider['models'] as List;
    expect((models.first as Map)['id'], 'm1');
    expect((models.first as Map)['contextWindow'], kDshContextWindow);
    // 不声明 = dsh 回落到 provider 的 defaultInput（["text"]），图片发不进去。
    // 注意 pi-ai 的字段名是 `input`（deepseek 官方 provider 才叫 inputModalities）。
    expect((models.first as Map)['input'], kDshInputModalities);
    expect(provider['defaultInput'], kDshInputModalities);
  });

  test('provider 写进 YAML 后带着 image 输入模态', () {
    final source = buildLlmpiAiEntry({
      kDshProviderId: buildLocal2ApiProvider(
        baseUrl: 'http://127.0.0.1:8787/v1',
        models: const ['m1'],
      ),
    });
    // 发射器对非空列表走块式，不是 [text, image]。
    expect(source, contains('defaultInput:'));
    expect(source, contains('input:'));
    expect(source, contains('- text'));
    expect(source, contains('- image'));
    // 读回来还是那两个模态：写歪了 dsh 会按默认当成纯文本模型。
    final providers = readDshProviders(source);
    final models = (providers[kDshProviderId] as Map)['models'] as List;
    expect((models.first as Map)['input'], kDshInputModalities);
  });

  group('Android 兼容层', () {
    test('空文件写入：带标记、该禁的都禁了', () {
      final text = upsertAndroidCompatPatch('');
      expect(hasAndroidCompatPatch(text), isTrue);
      for (final id in const [
        'bash-sandbox',
        'pwsh-sandbox',
        'permission',
        'session-log-download',
        'session-telemetry-otel',
      ]) {
        expect(text, contains('- id: $id\n  disabled: true'));
      }
      expect(text, contains('- id: bash-local'));
    });

    test('sandbox 与 llm-pi-ai 绝不能被我们禁掉', () {
      // 上游实测：禁 sandbox → ptcRuntime 永挂 → 所有 preset 会话创建失败；
      // 禁 llm-pi-ai → 模型 provider 目录没了 →「添加提供方」置灰。
      final text = upsertAndroidCompatPatch('');
      expect(
        RegExp(r'^- id: sandbox$', multiLine: true).hasMatch(text),
        isFalse,
      );
      expect(text, isNot(contains('llm-pi-ai')));
    });

    test('兼容层是合法 YAML，且补了终端后端', () {
      // `!!js (...)` 是 dsh 自己的 tag，yaml 包不认：验结构前先换成字符串。
      final text = upsertAndroidCompatPatch('').replaceAllMapped(
        RegExp(r'!!js \(.*\)$', multiLine: true),
        (_) => '"expr"',
      );
      final doc = loadYaml(text);
      expect(doc, isA<YamlList>());
      final rows = (doc as YamlList).toList();
      final ids = rows.map((row) => (row as YamlMap)['id']).toList();
      expect(ids, contains('bash-sandbox'));
      // `insert` 里的补充行：bash-local 管 shell 工具，terminal-bash 管 ctx.terminals。
      final inserted = rows
          .where((row) => (row as YamlMap).containsKey('insert'))
          .expand((row) => (row as YamlMap)['insert'] as YamlList)
          .map((row) => (row as YamlMap)['id'])
          .toList();
      expect(inserted, containsAll(['bash-local', 'terminal-bash']));
      final terminal = (rows
              .where((row) => (row as YamlMap).containsKey('insert'))
              .expand((row) => (row as YamlMap)['insert'] as YamlList)
              .firstWhere((row) => (row as YamlMap)['id'] == 'terminal-bash')
              as YamlMap)['config'] as YamlMap;
      // 上游默认是 /bin/bash + --noprofile --norc，Android 上两个都不成立。
      expect(terminal['shellPath'], '/system/bin/sh');
      expect(terminal['shellArgs'], ['-i']);
    });

    test('重写两次只留一段', () {
      final once = upsertAndroidCompatPatch('');
      final twice = upsertAndroidCompatPatch(once);
      expect(
        RegExp(kDshAndroidPatchMarker).allMatches(twice).length,
        1,
      );
      expect(twice, once);
    });

    test('保留用户写在兼容层前面的条目，撤掉时也只删我们那段', () {
      final merged = upsertAndroidCompatPatch(
        '# 我的\r\n- id: tool-web\r\n  disabled: true\r\n',
      );
      expect(merged, contains('- id: tool-web'));
      expect(
        merged.indexOf('tool-web'),
        lessThan(merged.indexOf(kDshAndroidPatchMarker)),
      );
      final stripped = removeAndroidCompatPatch(merged);
      expect(stripped, contains('- id: tool-web'));
      expect(hasAndroidCompatPatch(stripped), isFalse);
    });

    test('撤掉后重写：不能把 [] 和列表块拼在一起', () {
      // 关→开这条路径上，文件里只剩 dsh 的空文档标记 `[]`；
      // 直接追加会让 dsh-app-boot 的 parsePatchList 报错、引擎起不来。
      final cleared = removeAndroidCompatPatch(upsertAndroidCompatPatch(''));
      expect(cleared.trim(), isEmpty);
      final rewritten = upsertAndroidCompatPatch('$cleared\n');
      expect(rewritten.trim().startsWith('[]'), isFalse);
      expect(rewritten, startsWith('# $kDshAndroidPatchMarker'));
      // 用户留着的 `[]` 同样要被摘掉。
      expect(
        upsertAndroidCompatPatch('# 我的\n[]\n').contains('[]'),
        isFalse,
      );
    });

    test('没写过时撤掉是空操作', () {
      expect(removeAndroidCompatPatch('[]\n'), '[]\n');
    });
  });

  group('extractDshTokenUrl', () {
    test('从启动行里取出带令牌的地址', () {
      const line =
          'dsh web: http://127.0.0.1:3080/?token=9m-XpkwztA4IoIz6'
          'opPaDX5fJl-cdn91XpV1YmymfZw';
      expect(
        extractDshTokenUrl(line),
        'http://127.0.0.1:3080/?token=9m-XpkwztA4IoIz6opPaDX5fJl-cdn91XpV1YmymfZw',
      );
    });

    test('普通日志行返回 null', () {
      expect(
        extractDshTokenUrl('dsh: warning: 1 entry did not activate'),
        isNull,
      );
      expect(extractDshTokenUrl('已就绪：http://127.0.0.1:3080'), isNull);
    });
  });

  group('parseAskValue', () {
    test('没有选项时整行都是问题（安卓旧行为）', () {
      final parsed = parseAskValue(' 要不要现在部署？ ');
      expect(parsed.question, '要不要现在部署？');
      expect(parsed.options, isEmpty);
    });

    test('竖线后面拆成选项（Windows 提示词）', () {
      final parsed = parseAskValue('选哪个方案？ | 方案 A | 方案 B | 方案 C');
      expect(parsed.question, '选哪个方案？');
      expect(parsed.options, ['方案 A', '方案 B', '方案 C']);
    });

    test('全角竖线与空段也能处理', () {
      final parsed = parseAskValue('选一个｜ ｜甲｜乙');
      expect(parsed.question, '选一个');
      expect(parsed.options, ['甲', '乙']);
    });
  });

  group('Android 文件补丁', () {
    test('四处原生依赖都有回退，且都带标记', () {
      expect(kDshAndroidFilePatches.keys, [
        'node-addon-require-builtin/lib/index.js',
        '@deepseek-ai/node-addon-system/lib/flock.js',
        '@vscode/ripgrep/lib/index.js',
        'node-pty/lib/index.js',
      ]);
      for (final patch in kDshAndroidFilePatches.values) {
        expect(patch, contains(kDshAndroidFilePatchMarker));
      }
      // require-builtin 的回退靠 --expose-internals 下的普通 require。
      expect(
        kDshAndroidFilePatches['node-addon-require-builtin/lib/index.js'],
        contains('createRequire'),
      );
      // flock 的空锁回退必须仍然导出 tryLockExclusive。
      expect(
        kDshAndroidFilePatches['@deepseek-ai/node-addon-system/lib/flock.js'],
        contains('export async function tryLockExclusive'),
      );
      // node-pty 的回退必须仍然导出 spawn/kill 面（dsh 的行程句柄要用）。
      expect(
        kDshAndroidFilePatches['node-pty/lib/index.js'],
        contains('exports.spawn = spawn;'),
      );
    });

    test('补丁清单与映射表一致（UI 展示用）', () {
      // 整文件补丁 + 定点替换补丁都在清单里（UI 只按文件名展示）。
      expect(kDshAndroidPatchFiles, [
        ...kDshAndroidFilePatches.keys,
        ...kDshAndroidReplacements.keys,
      ]);
      expect(
        kDshAndroidPatchFiles,
        contains('@deepseek-ai/dsh-session-persistence-jsonl/lib/index.js'),
      );
    });
  });
}
