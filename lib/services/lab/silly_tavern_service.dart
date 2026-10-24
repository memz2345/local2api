// lib/services/lab/silly_tavern_service.dart
//
// 实验室里的第一个「一键装到本地」服务：SillyTavern（本地 AI 角色扮演前端）。
//
// 它本身是个 Node.js 项目 —— 安装 = 下载 release 分支的 zip、解压、npm install；
// 启动 = `node server.js --port <port>`，页面用内置浏览器打开 127.0.0.1。
//
// 平台差异（按需求做的取舍）：
//   · Windows / macOS / Linux：安装位置可选（file_picker），检测 node / npm；
//   · Android / iOS：沙箱里选位置没有意义，固定装到应用支持目录；系统没有
//     Node 运行时，装完只显示文件与「需要 Termux」提示，不提供启动按钮。
//
// 状态都收在这个单例里：实验室页（Material / miuix 两套）只是渲染它，
// 进程活着、切页面、切 UI 风格都不会把安装/运行状态弄丢。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/proxy_config.dart';
import '../../services/network_utils.dart';
import 'lab_process.dart';
import 'node_runtime_service.dart';

enum LabServicePhase { idle, downloading, extracting, installing, starting }

/// 把 SillyTavern 的「自定义 OpenAI 兼容源」指向本机代理时需要的三件套。
///
/// [baseUrl] 带 `/v1`；[apiKey] 取自本机配置里第一个启用的密钥；[model] 是
/// 所选模型组里第一个对外暴露的模型（用户也可以单独改）。
@immutable
class StApiConfig {
  const StApiConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.groupId,
    required this.groupName,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final String groupId;
  final String groupName;

  bool get hasKey => apiKey.isNotEmpty;
}

/// SillyTavern 安装 / 运行管家。
class SillyTavernService extends ChangeNotifier {
  SillyTavernService._();

  static final SillyTavernService instance = SillyTavernService._();

  static const String _prefRoot = 'lab.sillytavern.root';
  static const String _prefDir = 'lab.sillytavern.dir';

  /// 主开关状态（下次进实验室页时按它自动拉起）。
  static const String _prefEnabled = 'lab.sillytavern.enabled';

  /// 绑定的模型组（[ConfigProfile.id]）与模型对外名。
  static const String _prefApiGroup = 'lab.sillytavern.api.group';
  static const String _prefApiModel = 'lab.sillytavern.api.model';

  /// 启动后是否让 SillyTavern 自己拉起系统浏览器（默认关）。
  ///
  /// ST 的 config.yaml 里 `browserLaunch.enabled` 可能被用户或发行版打开，
  /// 那样我们的进程一启动就会弹出默认浏览器；这里用命令行参数显式覆盖它。
  static const String _prefAutoOpenBrowser = 'lab.sillytavern.autoOpenBrowser';

  /// release 分支的源码包（比 master 稳）。
  static const String zipUrl =
      'https://codeload.github.com/SillyTavern/SillyTavern/zip/refs/heads/release';

  static const int defaultPort = 8000;
  static const int _maxLogLines = 400;

  SharedPreferences? _prefs;

  String? _root;
  String? _installDir;
  String? _version;
  String? _nodeVersion;
  String? _npmVersion;
  bool _nodeAvailable = false;
  bool _initialized = false;

  /// 主开关的期望状态（用户在实验室页拨过 on，就记着下次进页面自启）。
  bool _enabledWanted = false;

  /// 绑定的模型组 / 模型（给「API 配置」用）。
  String? _apiGroupId;
  String? _apiModel;

  /// 启动后自动打开系统浏览器（默认 false：由应用内的「打开」入口接管）。
  bool _autoOpenBrowser = false;

  LabServicePhase _phase = LabServicePhase.idle;
  double? _progress;
  String? _error;
  String? _nodeError;

  LabProcessHandle? _process;
  int _port = defaultPort;
  bool _running = false;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  final List<String> _logs = <String>[];
  Timer? _startProbe;

  // ---- 只读状态 ----

  bool get initialized => _initialized;
  bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  bool get canChooseLocation => isDesktop;

  /// Android 安装了 Node 运行时之后也能直接跑（桌面靠系统 Node）。
  bool get canRun => _nodeAvailable;

  String? get installDir => _installDir;
  String? get rootDir => _root;
  String? get version => _version;
  String? get nodeVersion => _nodeVersion;
  String? get npmVersion => _npmVersion;
  bool get nodeAvailable => _nodeAvailable;
  String? get nodeError => _nodeError;
  LabServicePhase get phase => _phase;
  double? get progress => _progress;
  String? get error => _error;
  bool get running => _running;

  /// 主开关的展示状态：正在启动也算「开」，不然点完开关会先弹回去再亮。
  bool get enabled => _running || _phase == LabServicePhase.starting;

  /// 上次退出前是开着的吗（进实验室页会自动拉起）。
  bool get enabledWanted => _enabledWanted;

  String? get apiGroupId => _apiGroupId;
  String? get apiModel => _apiModel;

  /// 启动后是否自动拉起系统浏览器。
  bool get autoOpenBrowser => _autoOpenBrowser;

  int get port => _port;
  List<String> get logs => List.unmodifiable(_logs);

  bool get installed => _installDir != null;

  /// 依赖是否已装（npm install 正常收尾会写 node_modules/.package-lock.json）。
  ///
  /// 「装文件」和「装依赖」是两步：文件先就位、Node 后就绪时，得靠这个
  /// 判断「安装依赖」入口要不要显示。
  bool get depsInstalled {
    final dir = _installDir;
    if (dir == null) return false;
    return File(
      p.join(dir, 'node_modules', '.package-lock.json'),
    ).existsSync();
  }
  bool get busy =>
      _phase == LabServicePhase.downloading ||
      _phase == LabServicePhase.extracting ||
      _phase == LabServicePhase.installing ||
      _phase == LabServicePhase.starting;

  String get url => 'http://127.0.0.1:$_port';

  /// 安装位置的展示文案：安装根目录（移动端是固定目录）。
  String get displayRoot => _root ?? (isDesktop ? '—' : '应用目录 · SillyTavern');

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _root = _prefs!.getString(_prefRoot);
    _installDir = _prefs!.getString(_prefDir);
    if (!isDesktop && _root != null) {
      // 实验室根目录已搬到应用外部目录；存量的内部目录记录一律作废。
      final lab = await labRootPath();
      if (!p.equals(lab, _root!) && !p.isWithin(lab, _root!)) {
        _root = null;
        await _prefs?.remove(_prefRoot);
      }
    }
    _enabledWanted = _prefs!.getBool(_prefEnabled) ?? false;
    _apiGroupId = _prefs!.getString(_prefApiGroup);
    _apiModel = _prefs!.getString(_prefApiModel);
    _autoOpenBrowser = _prefs!.getBool(_prefAutoOpenBrowser) ?? false;
    if (_installDir != null) {
      final ok = await File(p.join(_installDir!, 'server.js')).exists();
      if (!ok) {
        _installDir = null;
        _version = null;
      } else if (!isDesktop) {
        // 实验室根目录已搬到应用外部目录（未 root 的 Shizuku 读不到
        // /data/data）；存量记录指着老位置就作废，让用户重装一次。
        final root = await labRootPath();
        if (!p.isWithin(root, _installDir!)) {
          _installDir = null;
          _version = null;
          await _prefs?.remove(_prefDir);
        }
      }
      if (_installDir != null) {
        await _readVersion();
      }
    }
    await refreshNodeStatus();
    _initialized = true;
    notifyListeners();

    // 上次是开着的：进页面就自己拉起来（用户把开关拨下来会写 false，
    // 下次就不会再自启）。
    if (_enabledWanted && _installDir != null && canRun && !_running && !busy) {
      unawaited(start());
    }
  }

  Future<void> refreshNodeStatus() async {
    // Android：状态来自 NodeRuntimeService（应用内安装的 Node 运行时）。
    if (Platform.isAndroid) {
      final node = NodeRuntimeService.instance;
      await node.init();
      _nodeAvailable = node.nodeAvailable;
      _nodeVersion = node.nodeAvailable ? node.nodeVersion : null;
      _npmVersion = node.npmVersion;
      _nodeError = node.nodeAvailable ? null : (node.nodeError ?? 'notInstalled');
      notifyListeners();
      return;
    }
    if (!isDesktop) {
      _nodeAvailable = false;
      _nodeVersion = null;
      _npmVersion = null;
      _nodeError = 'mobile';
      notifyListeners();
      return;
    }
    // widget test 没有真正的进程环境：Process.run 的 8s 超时定时器会挂在
    // FakeAsync 里（测试结束时 "Timer is still pending"）。这里直接判不可用，
    // 页面照样能渲染出「未检测到 Node.js」那条分支。
    final inTest =
        Platform.environment['FLUTTER_TEST'] == 'true' ||
        const bool.fromEnvironment('FLUTTER_TEST');
    if (inTest) {
      _nodeAvailable = false;
      _nodeVersion = null;
      _npmVersion = null;
      _nodeError = 'test';
      notifyListeners();
      return;
    }
    _nodeAvailable = false;
    _nodeVersion = null;
    _npmVersion = null;
    _nodeError = null;
    try {
      final node = await Process.run('node', [
        '--version',
      ], runInShell: true).timeout(const Duration(seconds: 8));
      if (node.exitCode == 0) {
        _nodeVersion = '${node.stdout}'.trim();
        _nodeAvailable = true;
      } else {
        _nodeError = '${node.stderr}'.trim();
      }
    } catch (e) {
      _nodeError = '$e';
    }
    if (_nodeAvailable) {
      try {
        final npm = await Process.run('npm', [
          '--version',
        ], runInShell: true).timeout(const Duration(seconds: 8));
        if (npm.exitCode == 0) _npmVersion = '${npm.stdout}'.trim();
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> _readVersion() async {
    final dir = _installDir;
    if (dir == null) return;
    try {
      final pkg = File(p.join(dir, 'package.json'));
      if (!await pkg.exists()) return;
      final doc = jsonDecode(await pkg.readAsString());
      if (doc is Map<String, dynamic> && doc['version'] is String) {
        _version = doc['version'] as String;
      }
    } catch (_) {}
  }

  /// 桌面端：让用户挑安装根目录（装到 `<所选目录>/SillyTavern`）。
  Future<bool> chooseLocation() async {
    if (!canChooseLocation) return false;
    final picked = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择 SillyTavern 安装位置',
    );
    if (picked == null || picked.trim().isEmpty) return false;
    _root = picked;
    await _prefs?.setString(_prefRoot, picked);
    notifyListeners();
    return true;
  }

  /// 默认安装根目录：桌面用「文档/Local2API Lab」，Android 用应用外部目录
  /// （未 root 的 Shizuku 是 shell 身份，进不了 `/data/data/<pkg>`）。
  Future<String> _resolveRoot() async {
    final root = _root;
    if (root != null && root.trim().isNotEmpty) return root;
    if (isDesktop) {
      final docs = await getApplicationDocumentsDirectory();
      return p.join(docs.path, 'Local2API Lab');
    }
    return labRootPath();
  }

  void _log(String line) {
    final text = line.trimRight();
    if (text.isEmpty) return;
    _logs.add(text);
    if (_logs.length > _maxLogLines) {
      _logs.removeRange(0, _logs.length - _maxLogLines);
    }
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  // ---- 主开关（启动 / 停止） ----

  /// 拨动实验室主开关。返回拨完之后「是不是开着」。
  ///
  /// 没装 / 没 Node 时不会真的启动，只把错误记到 [error] 上，开关弹回去。
  Future<bool> setEnabled(bool value) async {
    if (!value) {
      _enabledWanted = false;
      await _prefs?.setBool(_prefEnabled, false);
      await stop();
      return false;
    }
    _enabledWanted = true;
    await _prefs?.setBool(_prefEnabled, true);
    if (_running) return true;
    if (_installDir == null) {
      _error = 'notInstalled';
      _enabledWanted = false;
      await _prefs?.setBool(_prefEnabled, false);
      notifyListeners();
      return false;
    }
    await start();
    // 起不来（缺 Node / 端口被占）：开关别假装自己开了。
    if (!_running) {
      _enabledWanted = false;
      await _prefs?.setBool(_prefEnabled, false);
      notifyListeners();
    }
    return _running;
  }

  // ---- API 配置（把 SillyTavern 的自定义源指到本机代理） ----

  /// 启动后自动打开系统浏览器（下次启动生效）。
  Future<void> setAutoOpenBrowser(bool value) async {
    _autoOpenBrowser = value;
    await _prefs?.setBool(_prefAutoOpenBrowser, value);
    notifyListeners();
  }

  /// 记下用户选的模型组 / 模型。`groupId` 为空 = 取消绑定。
  Future<void> setApiSelection({String? groupId, String? model}) async {
    final gid = (groupId ?? '').trim();
    final mid = (model ?? '').trim();
    _apiGroupId = gid.isEmpty ? null : gid;
    _apiModel = mid.isEmpty ? null : mid;
    if (_apiGroupId == null) {
      await _prefs?.remove(_prefApiGroup);
      await _prefs?.remove(_prefApiModel);
    } else {
      await _prefs?.setString(_prefApiGroup, _apiGroupId!);
      if (_apiModel == null) {
        await _prefs?.remove(_prefApiModel);
      } else {
        await _prefs?.setString(_prefApiModel, _apiModel!);
      }
    }
    notifyListeners();
  }

  /// 某个模型组对外暴露的模型名（去重保序；只算启用中的上游与模型）。
  List<String> modelsOfGroup(ProxyConfig config, String groupId) {
    final gid = groupId.trim();
    if (gid.isEmpty) return const [];
    final seen = <String>{};
    final out = <String>[];
    for (final u in config.upstreams) {
      if (!u.enabled || (u.managedBy ?? '') != gid) continue;
      for (final m in u.models) {
        final name = m.publicName.trim();
        if (!m.enabled || name.isEmpty) continue;
        if (seen.add(name)) out.add(name);
      }
    }
    return out;
  }

  /// 本机代理的 OpenAI 兼容基址（SillyTavern 的「自定义源」填这个）。
  String baseUrlOf(ProxyConfig config) =>
      'http://127.0.0.1:${config.listenPort}/v1';

  /// 本机代理里第一个启用的密钥（没有就 null）。
  String? apiKeyOf(ProxyConfig config) => config.apiKeys
      .where((k) => k.enabled && k.key.trim().isNotEmpty)
      .map((k) => k.key.trim())
      .firstOrNull;

  /// 解析出要写进 SillyTavern 的三件套。
  ///
  /// 返回 null = 还没选组 / 组里一个对外模型都没有（UI 会提示先去发现页启用）。
  /// 密钥取配置里第一个启用的；一个都没有时 [StApiConfig.hasKey] 为 false，
  /// UI 得让用户先建密钥，否则写进去 ST 会吃到 401。
  StApiConfig? resolveApiConfig(
    ProxyConfig config, {
    required String groupName,
  }) {
    final gid = _apiGroupId;
    if (gid == null || gid.isEmpty) return null;
    final models = modelsOfGroup(config, gid);
    if (models.isEmpty) return null;
    final preferred = _apiModel?.trim() ?? '';
    final model = models.contains(preferred) ? preferred : models.first;
    return StApiConfig(
      baseUrl: baseUrlOf(config),
      apiKey: apiKeyOf(config) ?? '',
      model: model,
      groupId: gid,
      groupName: groupName.isEmpty ? gid : groupName,
    );
  }

  /// 把三件套写进 SillyTavern 的用户配置（`settings.json` + `secrets.json`）。
  ///
  /// 走的是 ST 1.12+ 的「Custom (OpenAI-compatible)」源：
  /// `main_api=openai`、`chat_completion_source=custom`、`custom_url`、
  /// `custom_model`，密钥落 `api_key_custom`。写之前把原文件备份成
  /// `*.l2a.bak`，写坏了还能手动还原。
  Future<({bool ok, String? error})> applyApiConfig(StApiConfig cfg) async {
    final dir = _installDir;
    if (dir == null) return (ok: false, error: 'notInstalled');
    // ST 活着的时候配置在它内存里，下一次「保存设置」会把我们写的整份盖掉，
    // 所以必须先停。
    if (_running) return (ok: false, error: 'running');
    final userDir = Directory(p.join(dir, 'data', 'default-user'));
    if (!await userDir.exists()) {
      // ST 从没启动过时 data/default-user 还没生成，先让用户启动一次。
      return (ok: false, error: 'noUserData');
    }
    try {
      await _patchJsonFile(File(p.join(userDir.path, 'settings.json')), (doc) {
        doc['main_api'] = 'openai';
        doc['chat_completion_source'] = 'custom';
        doc['custom_url'] = cfg.baseUrl;
        doc['custom_model'] = cfg.model;
        // 反代是「官方 API 走代理」那一档用的，留着会把请求改投别处。
        doc['reverse_proxy'] = '';
        doc['reverse_proxy_password'] = '';
      });
      await _patchJsonFile(
        File(p.join(userDir.path, 'secrets.json')),
        (doc) => _writeSecretEntry(doc, 'api_key_custom', cfg.apiKey),
      );
      _log('已写入 SillyTavern API 配置：${cfg.baseUrl} · ${cfg.model}');
      notifyListeners();
      return (ok: true, error: null);
    } catch (e) {
      _log('写入 SillyTavern 配置失败：$e');
      return (ok: false, error: '$e');
    }
  }

  /// 读一份 JSON、交给 [patch] 改、再原样写回（缩进 2 格，方便手改）。
  Future<void> _patchJsonFile(
    File file,
    void Function(Map<String, dynamic> doc) patch,
  ) async {
    var doc = <String, dynamic>{};
    if (await file.exists()) {
      final raw = await file.readAsString();
      if (raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) doc = decoded;
      }
      await file.copy('${file.path}.l2a.bak');
    } else {
      await file.parent.create(recursive: true);
    }
    patch(doc);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(doc), flush: true);
    // ST 进程是 Shizuku 的 shell 身份，应用写的 0600 文件它读不到。
    await NodeRuntimeService.instance.makeLabReadable(sub: 'SillyTavern');
  }

  /// 往 ST 的 secrets.json 里写一条密钥。
  ///
  /// ST 1.13+ 的格式是「每个 key 一个数组，数组里 active=true 的那条生效」：
  /// `{"api_key_custom":[{"id","value","label","active"}]}`。旧版那种扁平
  /// 字符串 `{"api_key_custom":"sk-..."}` 只在**下次启动**时才会被迁移，
  /// 服务正在跑的时候读不到 —— 所以这里直接按新格式写，并保留用户已有的
  /// 其它密钥（同值复用，别每点一次「写入」就堆一条）。
  void _writeSecretEntry(Map<String, dynamic> doc, String key, String value) {
    final existing = doc[key];
    final entries = <Map<String, dynamic>>[];
    if (existing is List) {
      for (final raw in existing) {
        if (raw is Map) {
          entries.add(<String, dynamic>{
            for (final e in raw.entries) '${e.key}': e.value,
          });
        }
      }
    } else if (existing is String && existing.trim().isNotEmpty) {
      entries.add(<String, dynamic>{
        'id': _randomId(),
        'value': existing,
        'label': 'legacy',
        'active': false,
      });
    }
    final index = entries.indexWhere((e) => e['value'] == value);
    if (index >= 0) {
      for (var i = 0; i < entries.length; i++) {
        entries[i]['active'] = i == index;
      }
    } else {
      for (final e in entries) {
        e['active'] = false;
      }
      entries.insert(0, <String, dynamic>{
        'id': _randomId(),
        'value': value,
        'label': 'local2api',
        'active': true,
      });
    }
    doc[key] = entries;
  }

  /// RFC 4122 v4 UUID（不为了一个 id 引 uuid 包）。
  static String _randomId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final h = bytes.map(hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// 下载 + 解压 +（桌面）npm install。已有安装时直接返回。
  Future<void> install() async {
    if (busy) return;
    _error = null;
    _progress = null;
    final root = await _resolveRoot();
    _root = root;
    await _prefs?.setString(_prefRoot, root);

    final target = p.join(root, 'SillyTavern');
    final serverJs = File(p.join(target, 'server.js'));
    if (await serverJs.exists()) {
      _installDir = target;
      await _prefs?.setString(_prefDir, target);
      await _readVersion();
      _phase = LabServicePhase.idle;
      notifyListeners();
      return;
    }

    final tempRoot = await getTemporaryDirectory();
    final zipFile = File(p.join(tempRoot.path, 'sillytavern-release.zip'));
    final extractDir = Directory(p.join(tempRoot.path, 'sillytavern_extract'));

    try {
      await Directory(root).create(recursive: true);

      // 0) 缓存里已有完整安装包（预置过 / 上次下载完成但解压没走完）就
      //    直接复用 —— 境内直连 codeload 只有几十 KB/s，一次下不完是常态。
      var haveZip = false;
      if (await zipFile.exists()) {
        haveZip = await zipFile.length() > 1024 * 1024;
        if (!haveZip) {
          try {
            await zipFile.delete();
          } catch (_) {}
        }
      }

      // 1) 下载
      if (haveZip) {
        _log('检测到已预置的安装包（${(await zipFile.length() / 1048576).toStringAsFixed(1)} MB），跳过下载');
      } else {
        _phase = LabServicePhase.downloading;
        _progress = 0;
        notifyListeners();
        await _download(zipFile);
      }

      // 2) 解压（去掉 zip 里的顶层目录）
      _phase = LabServicePhase.extracting;
      _progress = null;
      _log('正在解压…');
      notifyListeners();
      if (await extractDir.exists()) await extractDir.delete(recursive: true);
      await extractDir.create(recursive: true);
      await _extractZip(zipFile, extractDir);

      final entries = await extractDir.list().toList();
      Directory source = extractDir;
      if (entries.length == 1 && entries.first is Directory) {
        source = entries.first as Directory;
      }
      if (await Directory(target).exists()) {
        await Directory(target).delete(recursive: true);
      }
      await Directory(p.dirname(target)).create(recursive: true);
      await _copyDirectory(source, Directory(target));

      _installDir = target;
      await _prefs?.setString(_prefDir, target);
      await _readVersion();
      // 应用解出来的文件是 0600，Shizuku 的 shell 身份读不到 —— 放开读位。
      await NodeRuntimeService.instance.makeLabReadable(sub: 'SillyTavern');
      _log('文件已就位：$target');

      // 3) 依赖
      if (isDesktop) {
        if (!_nodeAvailable) {
          _log('未检测到 Node.js，跳过 npm install；装好 Node 后点「安装依赖」。');
        } else {
          await _npmInstall(target);
        }
      } else if (Platform.isAndroid) {
        await refreshNodeStatus();
        if (_nodeAvailable) {
          await _npmInstall(target);
        } else {
          _log('还没安装 Node.js 运行时（在实验室页安装），装好后再点「安装依赖」。');
        }
      } else {
        _log('移动端已下载文件；此平台需自带 Node.js 环境，本应用不直接启动。');
      }
      _phase = LabServicePhase.idle;
      _progress = null;
      notifyListeners();
    } catch (e) {
      _phase = LabServicePhase.idle;
      _progress = null;
      _error = '$e';
      _log('安装失败：$e');
      notifyListeners();
    } finally {
      try {
        if (await zipFile.exists()) await zipFile.delete();
      } catch (_) {}
      try {
        if (await extractDir.exists()) await extractDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> _download(File target) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    // Android 上走系统全局代理（模拟器/内网必备），桌面跟随环境变量。
    await NetworkUtils.configureDownloadProxy(client);
    try {
      final req = await client.getUrl(Uri.parse(zipUrl));
      req.headers.set(HttpHeaders.userAgentHeader, 'Local2API');
      final res = await req.close();
      if (res.statusCode != 200) {
        throw Exception('下载失败：HTTP ${res.statusCode}');
      }
      final total = res.contentLength;
      await target.parent.create(recursive: true);
      final sink = target.openWrite();
      var received = 0;
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            final next = received / total;
            // 按 1% 节流：下载几十 MB 时每块都 notify 会把整页重建上千次。
            final last = _progress ?? 0;
            if (next - last >= 0.01 || next >= 1) {
              _progress = next;
              notifyListeners();
            }
          }
        }
      } finally {
        await sink.close();
      }
      _log('已下载 ${(received / 1024 / 1024).toStringAsFixed(1)} MB');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _extractZip(File zip, Directory dest) async {
    // 解压是纯 CPU 活（ST 的 zip 几十 MB、几千个文件），放主 isolate 会把
    // UI 整个冻住（Android 上就是「一点安装就卡死」）。挪进短命 isolate。
    final zipPath = zip.path;
    final destPath = dest.path;
    await Isolate.run(() => extractZipSync(zipPath, destPath));
  }

  Future<void> _copyDirectory(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final entity in from.list(recursive: false)) {
      final name = p.basename(entity.path);
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(p.join(to.path, name)));
      } else if (entity is File) {
        await entity.copy(p.join(to.path, name));
      }
    }
  }

  /// 只装依赖（用户先装了文件、后来才装 Node 时用）。
  Future<void> installDependencies() async {
    final dir = _installDir;
    if (dir == null || busy) return;
    await refreshNodeStatus();
    if (!_nodeAvailable) {
      _error = _nodeError ?? 'node not found';
      notifyListeners();
      return;
    }
    try {
      await _npmInstall(dir);
      _phase = LabServicePhase.idle;
      notifyListeners();
    } catch (e) {
      _phase = LabServicePhase.idle;
      _error = '$e';
      notifyListeners();
    }
  }

  /// npm 进程的启动方式：桌面直接 `npm`（shell）；Android 用应用内 node
  /// 跑 npm-cli.js（termux 的 bin/npm 是 symlink 且 shebang 不可用）。
  Future<({String executable, List<String> args, Map<String, String>? env})>
      _npmCommand(List<String> npmArgs) async {
    if (Platform.isAndroid) {
      final node = NodeRuntimeService.instance;
      return (
        executable: await node.nodeBinPath(),
        args: [await node.npmCliPath(), ...npmArgs],
        env: await node.processEnv(),
      );
    }
    return (executable: 'npm', args: npmArgs, env: null);
  }

  Future<void> _npmInstall(String dir) async {
    _phase = LabServicePhase.installing;
    _log('npm install（首次可能要几分钟）…');
    notifyListeners();
    final cmd = await _npmCommand([
      'install',
      '--omit=dev',
      '--no-audit',
      '--no-fund',
      // Android：没有 python/node-gyp（脚本一挂整次安装就废），外部存储
      // 也不支持 symlink，`.bin` 软链直接跳过。
      if (Platform.isAndroid) '--ignore-scripts',
      if (Platform.isAndroid) '--no-bin-links',
    ]);
    if (Platform.isAndroid) {
      // npm 以 shell 身份跑：目标目录要能 mkdir node_modules / 写
      // package-lock.json，lab 根要能建 .npm 缓存。应用自己放权（无 root）。
      final node = NodeRuntimeService.instance;
      await node.makeLabDirWritable(await labRootPath());
      await node.makeLabDirWritable(dir);
    }
    final process = await startLabProcess(
      executable: cmd.executable,
      args: cmd.args,
      workingDirectory: dir,
      environment: cmd.env,
      runInShell: !Platform.isAndroid,
    );
    _stdoutSub = process.stdout.listen(_log);
    _stderrSub = process.stderr.listen(_log);
    final code = await process.exitCode;
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    if (code != 0) throw Exception('npm install 退出码 $code');
    await NodeRuntimeService.instance.makeLabReadable(sub: 'SillyTavern');
    _log('依赖安装完成');
  }

  Future<int> _findFreePort(int start) async {
    for (var candidate = start; candidate < start + 30; candidate++) {
      try {
        final socket = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          candidate,
        );
        await socket.close();
        return candidate;
      } catch (_) {
        continue;
      }
    }
    return start;
  }

  Future<void> start() async {
    if (_running || busy) return;
    final dir = _installDir;
    if (dir == null) return;
    await refreshNodeStatus();
    if (!canRun) {
      _error = 'missingNode';
      notifyListeners();
      return;
    }
    _error = null;
    _phase = LabServicePhase.starting;
    _logs.clear();
    notifyListeners();
    try {
      _port = await _findFreePort(defaultPort);
      _log(
        '启动：node server.js --port $_port '
        '--browserLaunchEnabled=$_autoOpenBrowser',
      );
      final executable = Platform.isAndroid
          ? await NodeRuntimeService.instance.nodeBinPath()
          : 'node';
      final env = Platform.isAndroid
          ? await NodeRuntimeService.instance.processEnv()
          : null;
      if (Platform.isAndroid) {
        // shell 身份的 server.js 启动后要在安装目录里写 data/default-user
        // （首次启动生成）与日志，先放开顶层写位。
        await NodeRuntimeService.instance.makeLabDirWritable(dir);
      }
      final process = await startLabProcess(
        executable: executable,
        args: [
          'server.js',
          '--port',
          '$_port',
          // 显式覆盖 config.yaml 的 browserLaunch.enabled，避免一启动就弹浏览器。
          '--browserLaunchEnabled=$_autoOpenBrowser',
        ],
        workingDirectory: dir,
        environment: env,
        runInShell: !Platform.isAndroid,
      );
      _process = process;
      _stdoutSub = process.stdout.listen(_log);
      _stderrSub = process.stderr.listen(_log);
      unawaited(
        process.exitCode.then((code) {
          _running = false;
          _process = null;
          _phase = LabServicePhase.idle;
          _enabledWanted = false;
          unawaited(_prefs?.setBool(_prefEnabled, false));
          _log('进程退出（$code）');
          notifyListeners();
        }),
      );
      await _waitUntilReady();
      // 真正起来了才记「下次自启」，否则下次进页面又白拉一次进程。
      if (_running) {
        _enabledWanted = true;
        await _prefs?.setBool(_prefEnabled, true);
      }
    } catch (e) {
      _phase = LabServicePhase.idle;
      _error = '$e';
      _log('启动失败：$e');
      notifyListeners();
    }
  }

  Future<void> _waitUntilReady() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      for (var i = 0; i < 60; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (_process == null) break;
        try {
          final req = await client.getUrl(Uri.parse(url));
          final res = await req.close();
          await res.drain<void>();
          if (res.statusCode >= 200 && res.statusCode < 500) {
            _running = true;
            _phase = LabServicePhase.idle;
            _log('已就绪：$url');
            notifyListeners();
            return;
          }
        } catch (_) {
          // 还没起来，继续等
        }
      }
      // 超时也把进程留着：可能只是首页慢，UI 允许直接点「打开」。
      _phase = LabServicePhase.idle;
      _running = _process != null;
      if (_running) _log('服务还在启动（未在 42s 内响应，可稍后点「打开」）');
      notifyListeners();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> stop() async {
    final process = _process;
    _process = null;
    _running = false;
    _enabledWanted = false;
    await _prefs?.setBool(_prefEnabled, false);
    _startProbe?.cancel();
    _phase = LabServicePhase.idle;
    // kill 的平台细节（Windows taskkill / posix 信号 / Shizuku destroy）
    // 都收在 handle 里。
    await process?.kill();
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _log('已停止');
    notifyListeners();
  }

  /// 卸载：只删本服务记录在案的安装目录（不碰用户选中的根目录本身）。
  Future<void> uninstall() async {
    await stop();
    final dir = _installDir;
    if (dir == null) return;
    try {
      final target = Directory(dir);
      if (await target.exists()) await target.delete(recursive: true);
    } catch (e) {
      _error = '$e';
      notifyListeners();
      return;
    }
    _installDir = null;
    _version = null;
    await _prefs?.remove(_prefDir);
    _logs.clear();
    _log('已卸载');
    notifyListeners();
  }

  /// 打开安装目录（桌面端用系统文件管理器）。
  Future<void> openInstallFolder() async {
    final dir = _installDir ?? _root;
    if (dir == null) return;
    try {
      if (Platform.isWindows) {
        await Process.start('explorer', [dir], runInShell: false);
      } else if (Platform.isMacOS) {
        await Process.start('open', [dir]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [dir]);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _startProbe?.cancel();
    super.dispose();
  }
}

/// 把 [zipPath] 解压到 [destPath]（在 isolate 里跑的同步实现）。
///
/// 路径安全：不允许 zip 里的条目跳出目标目录（zip-slip）。
void extractZipSync(String zipPath, String destPath) {
  final archive = ZipDecoder().decodeStream(InputFileStream(zipPath));
  for (final file in archive) {
    final name = file.name.replaceAll('\\', '/');
    if (name.isEmpty) continue;
    final outPath = p.normalize(p.join(destPath, name));
    if (!p.isWithin(destPath, outPath) && outPath != destPath) continue;
    if (file.isFile) {
      final out = File(outPath);
      out.parent.createSync(recursive: true);
      out.writeAsBytesSync(file.content, flush: false);
    } else {
      Directory(outPath).createSync(recursive: true);
    }
  }
}
