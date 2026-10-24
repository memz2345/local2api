// lib/services/lab/dsh_service.dart
//
// 实验室里的第二个「一键装到本地」服务：DeepSeek Harness（`dsh`）。
//
// 和 SillyTavern 一样是 Node.js 项目，但它从 npm 装（npx 那条官方路径的
// 本地化版本）：`npm install @deepseek-ai/dsh`，启动
// `node node_modules/@deepseek-ai/dsh/lib/bin.js web --no-open --port <port>`。
//
// 与 ST 的差异：
//   · 永远 `--no-open`（dsh 默认会拉起系统浏览器，本应用不需要）；
//   · 模型不是写进它自己的 UI，而是由本应用写 profile 的
//     `cordis.patch.yml`（provider 路由 local2api），并把 API Key 通过
//     环境变量注入 dsh 进程；
//   · 「模型」是复数：可以把模型组里的多个模型一次性加进去，再选一个默认。
//
// 状态收在单例里，实验室页 / 设置页只负责渲染。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'dsh_session_watcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/proxy_config.dart';
import 'dsh_android_patches.dart';
import 'dsh_config.dart';
import 'lab_process.dart';
import 'node_runtime_service.dart';
import 'silly_tavern_service.dart' show LabServicePhase;

/// DeepSeek Harness 安装 / 运行 / 模型配置管家。
class DshService extends ChangeNotifier {
  DshService._();

  static final DshService instance = DshService._();

  static const String _prefRoot = 'lab.dsh.root';
  static const String _prefDir = 'lab.dsh.dir';
  static const String _prefEnabled = 'lab.dsh.enabled';
  static const String _prefGroup = 'lab.dsh.api.group';
  static const String _prefModels = 'lab.dsh.api.models';
  static const String _prefDefaultModel = 'lab.dsh.api.default';
  static const String _prefApiKey = 'lab.dsh.api.key';
  static const String _prefCompat = 'lab.dsh.android.compat';
  static const String _prefTaskHint = 'lab.dsh.task.hint';

  static const int defaultPort = 3080;
  static const String packageName = '@deepseek-ai/dsh';
  static const int _maxLogLines = 400;

  SharedPreferences? _prefs;

  String? _root;
  String? _installDir;
  String? _version;
  String? _nodeVersion;
  String? _npmVersion;
  bool _nodeAvailable = false;
  bool _initialized = false;
  bool _enabledWanted = false;
  bool _androidCompat = true;
  bool _taskHint = true;

  /// 端到端测试用：flutter test 里 `FLUTTER_TEST` 会把 Node 探测直接判成
  /// 不可用；需要真跑 dsh 的测试在 init 前打开这个闸门。
  @visibleForTesting
  bool debugForceNodeAvailable = false;

  String? _apiGroupId;
  List<String> _models = const [];
  String? _defaultModel;
  String? _apiKey;

  LabServicePhase _phase = LabServicePhase.idle;
  double? _progress;
  String? _error;

  LabProcessHandle? _process;
  int _port = defaultPort;
  bool _running = false;
  String? _dshHome;
  String? _tokenUrl;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  final List<String> _logs = <String>[];

  // ---- 只读状态 ----

  bool get initialized => _initialized;
  bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  bool get isAndroid => Platform.isAndroid;
  bool get canChooseLocation => isDesktop;

  /// Android 安装了 Node 运行时之后也能直接跑（桌面靠系统 Node）。
  bool get canRun => _nodeAvailable;

  String? get installDir => _installDir;
  String? get rootDir => _root;
  String? get version => _version;
  String? get nodeVersion => _nodeVersion;
  String? get npmVersion => _npmVersion;
  bool get nodeAvailable => _nodeAvailable;
  LabServicePhase get phase => _phase;
  double? get progress => _progress;
  String? get error => _error;
  bool get running => _running;
  bool get enabled => _running || _phase == LabServicePhase.starting;
  bool get enabledWanted => _enabledWanted;

  String? get apiGroupId => _apiGroupId;
  List<String> get models => List.unmodifiable(_models);
  String? get defaultModel => _defaultModel;
  String? get apiKey => _apiKey;

  /// Android 兼容层是否随「写入 dsh 配置」一起落到 home 级配置。
  bool get androidCompatEnabled => _androidCompat;

  /// 任务模式是否给模型加「按步骤汇报」的提示词（关掉就是原样发任务）。
  bool get taskHintEnabled => _taskHint;

  int get port => _port;
  List<String> get logs => List.unmodifiable(_logs);
  bool get installed => _installDir != null;
  bool get busy =>
      _phase == LabServicePhase.downloading ||
      _phase == LabServicePhase.extracting ||
      _phase == LabServicePhase.installing ||
      _phase == LabServicePhase.starting;

  String get url => 'http://127.0.0.1:$_port';

  /// dsh 进程打印的带令牌地址；没拿到时退回裸地址（会 401，但至少有主机名）。
  String get openUrl => _tokenUrl ?? url;

  /// 令牌原样（UI 上单独一行展示，方便复制到别的浏览器里）。
  String? get webToken {
    final value = _tokenUrl;
    if (value == null) return null;
    final at = value.indexOf('token=');
    return at < 0 ? null : value.substring(at + 6);
  }

  String get displayRoot =>
      _root ?? (isDesktop ? '—' : '应用目录 · DeepSeek Harness');

  /// dsh 的用户配置目录（桌面：`$DSH_HOME` 或 `~/.dsh`；安卓：应用目录里的 `.dsh`）。
  ///
  /// 安卓侧 Dart 的 `Platform.environment` 里没有 `HOME`（那只有 Node 子进程的
  /// env 才有），所以这里必须由 [resolveDshHome] 先算好并缓存 —— 否则配置会写到
  /// 相对路径上去，写入直接失败、dsh 也读不到。
  String get dshHome => _dshHome ?? _desktopDshHome();

  /// 模型配置真正落地的地方（web profile 的用户层）。
  String get configPath =>
      p.join(dshHome, 'profiles', 'web', 'cordis.patch.yml');

  /// Android 兼容层落地的地方（home 级，profile-boot 自动加载）。
  String get compatPath => p.join(dshHome, 'cordis.patch.yml');

  /// dsh 的入口脚本：`node --expose-internals <bin.js> <profile> [...]`。
  ///
  /// 公开给任务模式（`dsh_task_runner.dart`）用：跑一次性任务也走同一个入口，
  /// `dsh headless "<task>"` 是 `bin.js` 的子命令。
  String get binPath => p.join(
    _installDir ?? '',
    'node_modules',
    '@deepseek-ai',
    'dsh',
    'lib',
    'bin.js',
  );

  /// 桌面（含测试宿主）的 dsh home：`$DSH_HOME`，否则 `~/.dsh`。
  static String _desktopDshHome() {
    final env = Platform.environment['DSH_HOME'];
    if (env != null && env.trim().isNotEmpty) return env.trim();
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    return home.isEmpty ? '.dsh' : p.join(home, '.dsh');
  }

  /// 算出并缓存 dsh home。安卓必须走这里：`HOME` 只在 Node 子进程的 env 里，
  /// Dart 侧读不到，同步 getter 只能拿到兜底值。
  Future<String> resolveDshHome() async {
    if (isDesktop) return _dshHome = _desktopDshHome();
    final root = await _resolveRoot();
    return _dshHome = p.join(root, '.dsh');
  }

  /// 传给 dsh 进程的 `DSH_AGENTS_HOME`（共享 agent 配置根，收在应用目录里）。
  Future<String> resolveAgentsHome() async {
    if (isDesktop) {
      final env = Platform.environment['DSH_AGENTS_HOME'];
      if (env != null && env.trim().isNotEmpty) return env.trim();
      final home =
          Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          '';
      return home.isEmpty ? '.agents' : p.join(home, '.agents');
    }
    return p.join(await _resolveRoot(), '.agents');
  }

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _root = _prefs!.getString(_prefRoot);
    _installDir = _prefs!.getString(_prefDir);
    if (!isDesktop && _root != null) {
      // 老版本把实验室装在应用内部目录，未 root 的 Shizuku 读不到那里；
      // 存量的 root 记录指在外部目录之外就作废，重新按外部目录走。
      final lab = await labRootPath();
      if (!p.equals(lab, _root!) && !p.isWithin(lab, _root!)) {
        _root = null;
        await _prefs?.remove(_prefRoot);
      }
    }
    _enabledWanted = _prefs!.getBool(_prefEnabled) ?? false;
    _apiGroupId = _prefs!.getString(_prefGroup);
    _apiKey = _prefs!.getString(_prefApiKey);
    _defaultModel = _prefs!.getString(_prefDefaultModel);
    _androidCompat = _prefs!.getBool(_prefCompat) ?? true;
    _taskHint = _prefs!.getBool(_prefTaskHint) ?? true;
    await resolveDshHome();
    final rawModels = _prefs!.getString(_prefModels);
    if (rawModels != null && rawModels.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawModels);
        if (decoded is List) {
          _models = [
            for (final item in decoded)
              if (item is String && item.trim().isNotEmpty) item.trim(),
          ];
        }
      } catch (_) {}
    }
    if (_installDir != null) {
      if (!await File(binPath).exists()) {
        _installDir = null;
        _version = null;
      } else if (!isDesktop) {
        // 实验室根目录搬到了应用外部目录（未 root 的 Shizuku 读不到 /data/data）。
        // 存量记录还指着老位置：认不得就当没装，让用户重装一次。
        final root = await labRootPath();
        if (!p.isWithin(root, _installDir!)) {
          _installDir = null;
          _version = null;
          await _prefs?.remove(_prefDir);
        }
      }
      if (_installDir != null) await _readVersion();
    }
    // 配置里已经有 local2api 的模型：把它当成本地选择的兜底，
    // 用户换过机器 / 清过 prefs 时也能看到已写入的模型。
    if (_models.isEmpty) {
      try {
        final file = File(configPath);
        if (await file.exists()) {
          final providers = readDshProviders(await file.readAsString());
          final route = providers[kDshProviderId];
          if (route is Map) {
            final list = route['models'];
            if (list is List) {
              _models = [
                for (final item in list)
                  if (item is Map && item['id'] != null) '${item['id']}',
              ];
            }
          }
        }
      } catch (_) {}
    }
    await refreshNodeStatus();
    _initialized = true;
    notifyListeners();

    if (_enabledWanted && _installDir != null && canRun && !_running && !busy) {
      unawaited(start());
    }
  }

  Future<void> refreshNodeStatus() async {
    if (debugForceNodeAvailable) {
      _nodeAvailable = true;
      // 测试闸门只绕过 FLUTTER_TEST 的「强制不可用」，版本号仍取真实 node，
      // 这样集成测试截图里显示的不是一个假的 "test"。
      if (_nodeVersion == null) {
        try {
          final node = await Process.run('node', [
            '--version',
          ], runInShell: true).timeout(const Duration(seconds: 8));
          if (node.exitCode == 0) _nodeVersion = '${node.stdout}'.trim();
        } catch (_) {}
        _nodeVersion ??= 'test';
      }
      notifyListeners();
      return;
    }
    // Android：状态来自 NodeRuntimeService（应用内安装的 Node 运行时）。
    if (Platform.isAndroid) {
      final node = NodeRuntimeService.instance;
      await node.init();
      _nodeAvailable = node.nodeAvailable;
      _nodeVersion = node.nodeAvailable ? node.nodeVersion : null;
      _npmVersion = node.npmVersion;
      notifyListeners();
      return;
    }
    if (!isDesktop) {
      _nodeAvailable = false;
      _nodeVersion = null;
      _npmVersion = null;
      notifyListeners();
      return;
    }
    final inTest =
        Platform.environment['FLUTTER_TEST'] == 'true' ||
        const bool.fromEnvironment('FLUTTER_TEST');
    if (inTest) {
      _nodeAvailable = false;
      _nodeVersion = null;
      _npmVersion = null;
      notifyListeners();
      return;
    }
    _nodeAvailable = false;
    _nodeVersion = null;
    _npmVersion = null;
    try {
      final node = await Process.run('node', [
        '--version',
      ], runInShell: true).timeout(const Duration(seconds: 8));
      if (node.exitCode == 0) {
        _nodeVersion = '${node.stdout}'.trim();
        _nodeAvailable = true;
      }
    } catch (_) {}
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
    try {
      final pkg = File(
        p.join(
          _installDir ?? '',
          'node_modules',
          '@deepseek-ai',
          'dsh',
          'package.json',
        ),
      );
      if (!await pkg.exists()) return;
      final doc = jsonDecode(await pkg.readAsString());
      if (doc is Map && doc['version'] is String) {
        _version = doc['version'] as String;
      }
    } catch (_) {}
  }

  Future<bool> chooseLocation() async {
    if (!canChooseLocation) return false;
    final picked = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择 DeepSeek Harness 安装位置',
    );
    if (picked == null || picked.trim().isEmpty) return false;
    _root = picked;
    await _prefs?.setString(_prefRoot, picked);
    notifyListeners();
    return true;
  }

  Future<String> _resolveRoot() async {
    final root = _root;
    if (root != null && root.trim().isNotEmpty) return root;
    if (isDesktop) {
      final docs = await getApplicationDocumentsDirectory();
      return p.join(docs.path, 'Local2API Lab');
    }
    // Android：应用外部目录（未 root 的 Shizuku 进不了 /data/data）。
    return labRootPath();
  }

  void _log(String line) {
    final text = line.trimRight();
    if (text.isEmpty) return;
    // dsh web 只在 stdout 打印一次带 token 的完整地址，错过就得重启才能再拿。
    final tokenUrl = extractDshTokenUrl(text);
    if (tokenUrl != null) _tokenUrl = tokenUrl;
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

  /// 外部模块（比如插件管理）把进度写进同一份日志。
  void addLog(String line) => _log(line);

  // ---- 安装 ----

  /// `npm install` 的参数：Android 额外跳过 install 脚本 —— 设备上没有
  /// python/node-gyp，node-pty 这类原生包的脚本一失败就会顶掉整次安装；
  /// 并且不建 `.bin` 软链（外部存储不支持 symlink，dsh 一律按路径直接执行）。
  List<String> get _npmInstallArgs => [
    'install',
    packageName,
    '--omit=dev',
    '--no-audit',
    '--no-fund',
    if (Platform.isAndroid) '--ignore-scripts',
    if (Platform.isAndroid) '--no-bin-links',
    '--loglevel=error',
  ];

  Future<void> install() async {
    if (busy) return;
    _error = null;
    _progress = null;
    final root = await _resolveRoot();
    _root = root;
    await _prefs?.setString(_prefRoot, root);
    final target = p.join(root, 'dsh');
    if (await File(
      p.join(target, 'node_modules', '@deepseek-ai', 'dsh', 'lib', 'bin.js'),
    ).exists()) {
      _installDir = target;
      await _prefs?.setString(_prefDir, target);
      await _readVersion();
      notifyListeners();
      return;
    }
    try {
      await Directory(target).create(recursive: true);
      await refreshNodeStatus();
      if (!_nodeAvailable) {
        _error = 'missingNode';
        notifyListeners();
        return;
      }
      _phase = LabServicePhase.installing;
      _log('npm install $packageName（首次可能几分钟）…');
      notifyListeners();
      final manifest = File(p.join(target, 'package.json'));
      if (!await manifest.exists()) {
        await manifest.writeAsString(
          '{"name":"local2api-dsh","private":true}\n',
          flush: true,
        );
      }
      await _npmRun(target, _npmInstallArgs);
      _installDir = target;
      await _prefs?.setString(_prefDir, target);
      await _readVersion();
      // 新解出来的整棵 node_modules 要放开读位，Shizuku 的 shell 身份才读得动。
      await NodeRuntimeService.instance.makeLabReadable(sub: 'dsh');
      await _applyFilePatches();
      await NodeRuntimeService.instance.makeLabReadable(sub: 'dsh');
      _phase = LabServicePhase.idle;
      _progress = null;
      _log('安装完成：$target');
      notifyListeners();
    } catch (e) {
      _phase = LabServicePhase.idle;
      _progress = null;
      _error = '$e';
      _log('安装失败：$e');
      notifyListeners();
    }
  }

  Future<void> installDependencies() async {
    final dir = _installDir;
    if (dir == null || busy) return;
    await refreshNodeStatus();
    if (!_nodeAvailable) {
      _error = 'missingNode';
      notifyListeners();
      return;
    }
    try {
      _phase = LabServicePhase.installing;
      notifyListeners();
      await _npmRun(dir, _npmInstallArgs);
      await _readVersion();
      await _applyFilePatches();
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

  Future<void> _npmRun(String dir, List<String> args) async {
    // 外部目录当不了 cwd（部分 ROM 的 shell 进不去 /sdcard/Android/data）时，
    // 改用 npm 的 --prefix 定位安装目录。
    final blocked = NodeRuntimeService.instance.labCwdBlocked;
    if (Platform.isAndroid) {
      // npm 以 shell 身份跑：安装目录要能 mkdir node_modules，lab 根要能
      // 建 .npm 缓存（目录是应用建的，shell 没有写位，无 root 时只能
      // 应用自己 chmod；顶层即可，node_modules 建出来就是 shell 的）。
      final node = NodeRuntimeService.instance;
      await node.makeLabDirWritable(await labRootPath());
      await node.makeLabDirWritable(dir);
    }
    final cmd = await _npmCommand(
      [if (blocked) ...['--prefix', dir], ...args],
    );
    final process = await startLabProcess(
      executable: cmd.executable,
      args: cmd.args,
      workingDirectory: blocked ? null : dir,
      environment: cmd.env,
      runInShell: !Platform.isAndroid,
    );
    final out = process.stdout.listen(_log);
    final err = process.stderr.listen(_log);
    final code = await process.exitCode;
    await out.cancel();
    await err.cancel();
    if (code != 0) throw Exception('npm 退出码 $code');
  }

  // ---- 启停 ----

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
    if (!_running) {
      _enabledWanted = false;
      await _prefs?.setBool(_prefEnabled, false);
      notifyListeners();
    }
    return _running;
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
      _tokenUrl = null;
      // npm 重装会把补丁覆盖回去，启动前再确认一次（已打过就跳过）。
      await _applyFilePatches();
      final env = await buildProcessEnv();
      // `--expose-internals`：dsh 的 HMR / cordis loader 走 node 内部模块，
      // 少了它模型列表的热更新不生效（桌面与安卓同一处理）。
      _log('启动：node bin.js web --no-open --host 127.0.0.1 --port $_port');
      final executable = Platform.isAndroid
          ? await NodeRuntimeService.instance.nodeBinPath()
          : 'node';
      await prepareRuntimeDirs();
      // 最后一道保险：上面 prepareRuntimeDirs / _applyFilePatches 都可能
      // 触发递归放权，凭据文件必须是 600 否则 dsh 拒绝启动（详见
      // NodeRuntimeService.tightenLabSecrets）。
      await _hardenCredentials();
      final process = await startLabProcess(
        executable: executable,
        args: [
          '--expose-internals',
          binPath,
          'web',
          '--no-open',
          '--host',
          '127.0.0.1',
          '--port',
          '$_port',
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
      if (_running) {
        _enabledWanted = true;
        await _prefs?.setBool(_prefEnabled, true);
        // web 会话 → 通知的桥：不 await，失败也不影响 dsh 本身。
        unawaited(DshSessionWatcher.instance.start(this));
      }
    } catch (e) {
      _phase = LabServicePhase.idle;
      _error = '$e';
      _log('启动失败：$e');
      notifyListeners();
    }
  }

  // ---- 任务模式（一次性任务，结果回通知） ----

  /// 跑 dsh 子进程要的完整环境（web 与 headless 共用）。
  ///
  /// Android 上必须显式钉死 `DSH_HOME` / `DSH_AGENTS_HOME`：Dart 侧的
  /// `Platform.environment` 里没有 `HOME`，不注入就写进相对路径。
  Future<Map<String, String>> buildProcessEnv() async {
    final home = await resolveDshHome();
    final env = Platform.isAndroid
        ? await NodeRuntimeService.instance.processEnv()
        : Map<String, String>.from(Platform.environment);
    final key = _apiKey?.trim() ?? '';
    if (key.isNotEmpty) env[kDshApiKeyEnv] = key;
    if (Platform.isAndroid) {
      env['DSH_HOME'] = home;
      env['DSH_AGENTS_HOME'] = await resolveAgentsHome();
      // dsh 的 shell 解析拿 `SHELL || userInfo().shell`，Termux 的死路径会让
      // bash 工具起不来；Android 也没有 /bin/sh 与 /usr/bin/env。
      env['SHELL'] = '/system/bin/sh';
      env['TERM'] = 'xterm-256color';
      env['PATH'] = '${env['PATH'] ?? ''}:/system/bin:/system/xbin';
    }
    return env;
  }

  /// 拉起 dsh 之前把目录放权（shell 身份要写 session / profile / data）。
  Future<void> prepareRuntimeDirs() async {
    if (!Platform.isAndroid) return;
    final node = NodeRuntimeService.instance;
    final dir = _installDir;
    if (dir != null) await node.makeLabDirWritable(dir);
    await node.makeLabDirWritable(await resolveDshHome());
    // 凭据文件必须 600（dsh-credentials-local 会校验），放权后收回来。
    await _hardenCredentials();
  }

  /// headless 任务用的临时 patch 内容：把 web profile 里写好的模型配置
  /// 原样搬过去。
  ///
  /// headless profile 有自己的 `cordis.patch.yml`，home 级只有 Android 兼容
  /// 层 —— 不带这份 patch 的话 headless 跑的是它自己的空 provider 列表，
  /// 一次请求都发不出去。用 `--patch` 传（而不是写进 headless 的 profile
  /// 文件）是为了不覆盖 dsh 自己初始化的模板。
  Future<String> buildHeadlessPatch() async {
    final file = File(configPath);
    if (!await file.exists()) throw Exception('noModels');
    final source = await file.readAsString();
    final llm = findEntryBlock(source, 'llm-pi-ai');
    if (llm == null) throw Exception('noModels');
    final def = findEntryBlock(source, 'agent-default-model');
    return def == null ? llm : '$llm\n$def';
  }

  /// 任务模式提示词开关。
  Future<void> setTaskHint(bool value) async {
    _taskHint = value;
    await _prefs?.setBool(_prefTaskHint, value);
    notifyListeners();
  }

  Future<void> _waitUntilReady() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      for (var i = 0; i < 90; i++) {
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
        } catch (_) {}
      }
      _phase = LabServicePhase.idle;
      _running = _process != null;
      if (_running) _log('服务还在启动（未在 63s 内响应，可稍后点「打开」）');
      notifyListeners();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> stop() async {
    unawaited(DshSessionWatcher.instance.stop());
    final process = _process;
    _process = null;
    _running = false;
    _tokenUrl = null;
    _enabledWanted = false;
    await _prefs?.setBool(_prefEnabled, false);
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

  // ---- 模型选择（应用内的模型 -> dsh） ----

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

  String baseUrlOf(ProxyConfig config) =>
      'http://127.0.0.1:${config.listenPort}/v1';

  String? apiKeyOf(ProxyConfig config) => config.apiKeys
      .where((k) => k.enabled && k.key.trim().isNotEmpty)
      .map((k) => k.key.trim())
      .firstOrNull;

  Future<void> setGroup(String? groupId) async {
    final gid = (groupId ?? '').trim();
    _apiGroupId = gid.isEmpty ? null : gid;
    _models = const [];
    _defaultModel = null;
    if (_apiGroupId == null) {
      await _prefs?.remove(_prefGroup);
    } else {
      await _prefs?.setString(_prefGroup, _apiGroupId!);
    }
    await _prefs?.remove(_prefModels);
    await _prefs?.remove(_prefDefaultModel);
    notifyListeners();
  }

  Future<void> setModels(List<String> models) async {
    final cleaned = <String>[];
    final seen = <String>{};
    for (final m in models) {
      final name = m.trim();
      if (name.isEmpty || !seen.add(name)) continue;
      cleaned.add(name);
    }
    _models = cleaned;
    if (_defaultModel != null && !cleaned.contains(_defaultModel)) {
      _defaultModel = cleaned.isEmpty ? null : cleaned.first;
    }
    await _prefs?.setString(_prefModels, jsonEncode(cleaned));
    if (_defaultModel == null) {
      await _prefs?.remove(_prefDefaultModel);
    } else {
      await _prefs?.setString(_prefDefaultModel, _defaultModel!);
    }
    notifyListeners();
  }

  Future<void> setDefaultModel(String? model) async {
    final value = (model ?? '').trim();
    if (value.isNotEmpty && !_models.contains(value)) return;
    _defaultModel = value.isEmpty ? null : value;
    if (_defaultModel == null) {
      await _prefs?.remove(_prefDefaultModel);
    } else {
      await _prefs?.setString(_prefDefaultModel, _defaultModel!);
    }
    notifyListeners();
  }

  /// 把选中的模型写进 dsh 的 web profile 配置。
  ///
  /// 保留配置里其它插件行与其它 provider（deepseek / lol 等），只替换
  /// `llm-pi-ai` 这一行里的 `local2api` 路由，并顺手把默认模型指过去。
  Future<({bool ok, String? error})> applyApiConfig(ProxyConfig config) async {
    final models = _models;
    if (models.isEmpty) return (ok: false, error: 'noModels');
    final key = apiKeyOf(config);
    if (key == null) return (ok: false, error: 'noKey');
    final baseUrl = baseUrlOf(config);
    try {
      final file = File(configPath);
      final source = await file.exists() ? await file.readAsString() : '';
      if (await file.exists()) {
        await file.copy('${file.path}.l2a.bak');
      } else {
        await file.parent.create(recursive: true);
      }
      final providers = readDshProviders(source);
      providers[kDshProviderId] = buildLocal2ApiProvider(
        baseUrl: baseUrl,
        models: models,
      );
      var next = upsertEntry(source, 'llm-pi-ai', buildLlmpiAiEntry(providers));
      final preferred = _defaultModel != null && models.contains(_defaultModel)
          ? _defaultModel!
          : models.first;
      next = upsertEntry(
        next,
        'agent-default-model',
        buildDefaultModelEntry(provider: kDshProviderId, model: preferred),
      );
      await file.writeAsString(next, flush: true);
      if (Platform.isAndroid) {
        // 应用写的文件默认 0600，node（shell 身份）读不到 → provider 直接消失。
        await NodeRuntimeService.instance.makeLabReadable(sub: '.dsh');
        await _hardenCredentials();
      }
      if (Platform.isAndroid && _androidCompat) await _writeCompatPatch();

      _apiKey = key;
      _defaultModel = preferred;
      await _prefs?.setString(_prefApiKey, key);
      await _prefs?.setString(_prefDefaultModel, preferred);
      _log('已写入 dsh 模型配置：$baseUrl · ${models.length} 个模型');
      notifyListeners();
      return (ok: true, error: null);
    } catch (e) {
      _log('写入 dsh 配置失败：$e');
      return (ok: false, error: '$e');
    }
  }

  /// Android 兼容层开关：开=把补丁写进 `$DSH_HOME/cordis.patch.yml`（并给 npm 树里
  /// 两处原生依赖打 JS 回退），关=从那份文件里撤掉我们那一段并还原文件。
  Future<void> setAndroidCompat(bool value) async {
    _androidCompat = value;
    await _prefs?.setBool(_prefCompat, value);
    try {
      if (value) {
        await _writeCompatPatch();
        await _applyFilePatches();
      } else {
        await _clearCompatPatch();
        await _revertFilePatches();
      }
    } catch (e) {
      _log('Android 兼容层写入失败：$e');
    }
    notifyListeners();
  }

  /// npm 树里的原生依赖补丁（只在 Android + 开关打开时）。
  Future<void> _applyFilePatches() async {
    final dir = _installDir;
    if (!Platform.isAndroid || !_androidCompat || dir == null) return;
    final applied = await applyDshAndroidPatches(dir);
    if (applied.isNotEmpty) {
      await NodeRuntimeService.instance.makeLabReadable(sub: 'dsh');
      _log('已打 Android 补丁：${applied.join('、')}');
    }
    await _ensureSharpWasm(dir);
  }

  /// 补装 sharp 的 WASM 运行时。
  ///
  /// `dsh-attachment-local` 用 sharp 读图片元数据、做归一化 —— 任何一张图
  /// 进会话都要过它。sharp 官方只发桌面/server 的预编译二进制，没有
  /// android-arm64；它自己的兜底分支会 `require("@img/sharp-wasm32/sharp.node")`，
  /// 但那个包在 npm 里带 `os: ["wasm32"]` 条件，Android 上正常 install
  /// **装不上**，于是 `read_image` 直接报
  /// `Could not load the "sharp" module using the android-arm64 runtime`。
  ///
  /// 这里按已装 sharp 的版本号显式补一次（幂等，目录已在就跳过）。装完
  /// sharp 会自己选中 wasm 实现，图片链路就通了。
  Future<void> _ensureSharpWasm(String dir) async {
    final wasm = Directory(p.join(dir, 'node_modules', '@img', 'sharp-wasm32'));
    if (await wasm.exists()) return;
    final manifest = File(p.join(dir, 'node_modules', 'sharp', 'package.json'));
    if (!await manifest.exists()) return; // 没装 sharp，无从对齐版本
    String version;
    try {
      final doc = jsonDecode(await manifest.readAsString());
      version = '${(doc as Map)['version']}';
    } catch (_) {
      return;
    }
    if (version.isEmpty || version == 'null') return;
    _log('补装 sharp wasm 运行时（$version，Android 无预编译二进制）…');
    try {
      await _npmRun(dir, [
        'install',
        '@img/sharp-wasm32@$version',
        '--no-save',
        '--no-package-lock',
        '--ignore-scripts',
        '--no-audit',
        '--no-fund',
        '--loglevel=error',
      ]);
      if (await wasm.exists()) {
        await NodeRuntimeService.instance.makeLabReadable(sub: 'dsh');
        _log('sharp wasm 就绪：图片可以进会话了');
      } else {
        _log('sharp wasm 安装后仍找不到目录');
      }
    } catch (e) {
      _log('sharp wasm 安装失败：$e');
    }
  }

  Future<void> _revertFilePatches() async {
    final dir = _installDir;
    if (!Platform.isAndroid || dir == null) return;
    final restored = await revertDshAndroidPatches(dir);
    if (restored.isNotEmpty) {
      await NodeRuntimeService.instance.makeLabReadable(sub: 'dsh');
      _log('已还原 Android 补丁：${restored.join('、')}');
    }
  }

  Future<void> _writeCompatPatch() async {
    await resolveDshHome();
    final file = File(compatPath);
    final exists = await file.exists();
    final source = exists ? await file.readAsString() : '';
    if (!exists) {
      await file.parent.create(recursive: true);
    } else if (!await File('${file.path}.l2a.bak').exists()) {
      await file.copy('${file.path}.l2a.bak');
    }
    await file.writeAsString(upsertAndroidCompatPatch(source), flush: true);
    if (Platform.isAndroid) {
      await NodeRuntimeService.instance.makeLabReadable(sub: '.dsh');
      await _hardenCredentials();
    }
    _log('已写入 Android 兼容层：$compatPath');
  }

  Future<void> _clearCompatPatch() async {
    await resolveDshHome();
    final file = File(compatPath);
    if (!await file.exists()) return;
    final source = await file.readAsString();
    if (!hasAndroidCompatPatch(source)) return;
    final next = removeAndroidCompatPatch(source);
    await file.writeAsString(next.isEmpty ? '[]\n' : '$next\n', flush: true);
    if (Platform.isAndroid) {
      await NodeRuntimeService.instance.makeLabReadable(sub: '.dsh');
      await _hardenCredentials();
    }
    _log('已撤掉 Android 兼容层');
  }

  /// 改完配置后如果 dsh 正在跑，重启一次让环境变量里的新密钥生效
  /// （模型列表本身由 HMR 热加载，密钥不会）。
  Future<void> restartIfRunning() async {
    if (!_running) return;
    await stop();
    await start();
  }

  /// 把 `$DSH_HOME/.credentials.yaml` 收回 600。
  ///
  /// dsh-credentials-local 启动/保存时会校验凭据文件「owner 之外不可读」，
  /// 看到 group/other 有读位就直接抛错（拦下密钥保存）。而我们要给 shell
  /// 放权（makeLabReadable(sub: '.dsh') 递归 a+rwX）会把这文件也放宽成
  /// 666 —— 放权后必须补一刀收回来。文件是 shell 自己建的（属主 shell），
  /// 600 不影响它读写；应用从不需要读它。
  Future<void> _hardenCredentials() async {
    if (!Platform.isAndroid) return;
    await resolveDshHome();
    await NodeRuntimeService.instance.tightenLabSecrets(
      p.dirname(dshHome),
    );
  }

  @override
  void dispose() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    super.dispose();
  }
}
