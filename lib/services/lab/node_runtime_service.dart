// lib/services/lab/node_runtime_service.dart
//
// 实验室的 Node.js 运行时管家 —— 安卓端专用（桌面用系统 Node，不走这里）。
//
// 背景：targetSdk 29+ 的应用不允许执行数据目录里的二进制（W^X），而官方
// Node 又不发布 Android 构建。方案：
//   1. 从 Termux 软件仓库下载 bionic 兼容的 node（+npm 与运行库依赖，
//      共 9 个 deb 包，约 25 MB）；
//   2. deb = ar 头 + control.tar.xz + data.tar.xz，archive 包自带
//      XZDecoder，纯 Dart 解包（ar 切片 → XZ → Tar → 抽 usr/bin、usr/lib）；
//   3. 运行时设 LD_LIBRARY_PATH=<nodeDir>/lib 指向解出来的 so
//      （LD_LIBRARY_PATH 优先于二进制里指向 Termux 路径的 RUNPATH）；
//   4. 执行通道分「直连」与「Shizuku」两种（见 lab_process.dart）：
//      debug 构建可以直接 exec；release 必须走 Shizuku（shell 域不受
//      W^X 限制）。
//
// 安装位置：<实验室根>/node/，结构：
//   bin/node                    主二进制（755）
//   lib/*.so*                   运行库
//   lib/node_modules/npm/       npm（npm-cli.js 由 node 直接执行）
//
// 实验室根目录在 Android 上是**应用外部目录**（见 [labRootPath]）：未 root 的
// Shizuku 是 shell 身份，SELinux 与属主都让它进不了 `/data/data/<pkg>`
// （实测 `ls /data/user/0/<pkg>` 直接 Permission denied，报出来就是
// `Cannot run program ...`）。外部目录 shell 可读，但它是 noexec 且不支持
// symlink / hardlink，所以真正拿去执行的那份 node + .so 还要经 Shizuku 暂存到
// `/data/local/tmp`（见 [stageForShell]）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/network_utils.dart';
import 'silly_tavern_service.dart' show LabServicePhase;
import 'shizuku_service.dart';

/// Node 进程的执行通道。
enum NodeRunnerMode { direct, shizuku }

/// 实验室资源下载镜像（Node 运行时 deb 源 + npm registry）。
///
/// 境内直连官方源实测只有 ~30KB/s（packages.termux.dev / registry.npmjs.org
/// 都慢），镜像实测 2-3MB/s，所以给个开关而不是默默换 —— 企业内网 / 已有
/// 代理的设备走官方源更稳。
enum NodeDownloadMirror { official, cn }

/// 实验室各服务（Node 运行时 / SillyTavern / dsh）共用的根目录。
///
/// Android 落在**应用外部目录**（`/sdcard/Android/data/<pkg>/files/lab`）：
/// 未 root 的 Shizuku 以 shell 身份运行，而 shell 既进不了 `/data/data/<pkg>`
/// （SELinux + 属主双重拦死），也读不到里面任何文件 —— 表现就是
/// `PlatformException(start_failed, Cannot run program ".../files/lab/...")`。
/// 外部目录 shell 能读（前提是我们把读位放开，见 [NodeRuntimeService] 的 chmod
/// 一步），但它 noexec 且不支持 symlink/hardlink，所以可执行那份要靠
/// [NodeRuntimeService.stageForShell] 暂存到 `/data/local/tmp`。
Future<String> labRootPath() async {
  if (Platform.isAndroid) {
    try {
      final ext = await getExternalStorageDirectory();
      final path = ext?.path.trim() ?? '';
      if (path.isNotEmpty) return p.join(path, 'lab');
    } catch (_) {
      // 拿不到外部目录（极少数 ROM / 存储未就绪）：退回内部目录，
      // 至少 root 通道的设备仍然可用。
    }
  }
  final support = await getApplicationSupportDirectory();
  return p.join(support.path, 'lab');
}

/// Node.js 运行时（Android）安装 / 检测 / 卸载管家。
class NodeRuntimeService extends ChangeNotifier {
  NodeRuntimeService._();

  static final NodeRuntimeService instance = NodeRuntimeService._();

  static const String _prefVersion = 'lab.node.version';
  static const String _prefRunner = 'lab.node.runner';
  static const String _prefMirror = 'lab.node.mirror';

  /// Termux 官方仓库（node 的 bionic 构建唯一稳定来源）。
  static const String repoBaseOfficial =
      'https://packages.termux.dev/apt/termux-main/';

  /// Termux 国内镜像（清华 TUNA，同步官方 main 仓库）。
  static const String repoBaseCn =
      'https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main/';

  /// npm 国内镜像（[NodeDownloadMirror.cn] 时经 npm_config_registry 注入）。
  static const String npmRegistryCn = 'https://registry.npmmirror.com';

  /// 当前生效的 apt 仓库根（下载地址都从它拼出来）。
  String get repoBase =>
      _mirror == NodeDownloadMirror.cn ? repoBaseCn : repoBaseOfficial;

  /// 当前设备对应的 Termux 架构名（缓存；桌面 / iOS 返回 null）。
  ///
  /// Android 设备有两种世界：真机基本是 arm64（Termux 叫 aarch64），
  /// 模拟器是 x86_64 —— Termux 池里两个架构的包都有，装的时候按
  /// [androidAbi] 动态选，别写死。
  String? _archCache;
  Future<String?> debArch() async {
    if (_archCache != null) return _archCache;
    if (!Platform.isAndroid) return null;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final abis = info.supportedAbis;
      String? arch;
      for (final abi in abis) {
        final mapped = switch (abi) {
          'arm64-v8a' => 'aarch64',
          'armeabi-v7a' => 'arm',
          'x86_64' => 'x86_64',
          'x86' => 'i686',
          _ => null,
        };
        if (mapped != null) {
          arch = mapped;
          break;
        }
      }
      return _archCache = arch;
    } catch (_) {
      return _archCache = 'aarch64';
    }
  }

  /// apt 索引地址（跟随设备架构）。
  Future<String> packagesUrl() async {
    final arch = await debArch() ?? 'aarch64';
    return '$repoBase/dists/stable/main/binary-$arch/Packages';
  }

  /// nodejs 的运行库依赖（deb 包名）。ca-certificates / resolv-conf 这类
  /// 数据包对 node 没用，不下载。
  ///
  /// `ripgrep`/`pcre2`：dsh 的 glob/grep 工具固定 spawn 打包的 ripgrep
  /// （@vscode/ripgrep），Android 上没有对应平台的包，只能靠 PATH 里的
  /// `rg`。放这儿随 Node 一起装，暂存后 `<stage>/bin/rg` 就能被找到
  /// （libpcre2-8.so 进 `<stage>/lib`，由 LD_LIBRARY_PATH 覆盖）。
  static const List<String> wantedPackages = [
    'nodejs',
    'npm',
    'libc++',
    'openssl',
    'c-ares',
    'libicu',
    'libsqlite',
    'zlib',
    'libffi',
    'ripgrep',
    'pcre2',
  ];

  /// 找不到就跳过（不影响 Node 本体）：个别架构的源里没有这些包。
  static const Set<String> optionalPackages = {'ripgrep', 'pcre2'};

  static const int _maxLogLines = 300;

  SharedPreferences? _prefs;
  bool _initialized = false;
  Future<void>? _initFuture;
  Future<void>? _refreshing;

  LabServicePhase _phase = LabServicePhase.idle;
  double? _progress;
  String? _error;
  final List<String> _logs = <String>[];

  String? _installedVersion;
  String? _runtimeNodeVersion;
  String? _runtimeNpmVersion;
  bool _nodeAvailable = false;
  String? _nodeError;

  NodeRunnerMode _runnerMode = NodeRunnerMode.direct;
  NodeDownloadMirror _mirror = NodeDownloadMirror.official;

  String? _nodeDirCache;

  // ---- 只读状态 ----

  bool get initialized => _initialized;
  bool get isAndroid => Platform.isAndroid;
  LabServicePhase get phase => _phase;
  double? get progress => _progress;
  String? get error => _error;
  List<String> get logs => List.unmodifiable(_logs);
  String? get installedVersion => _installedVersion;

  /// 已安装（应用目录里有 node 二进制且记录过版本）。
  bool get installed => _installedVersion != null;
  String? get nodeVersion => _runtimeNodeVersion ?? _installedVersion;
  String? get npmVersion => _runtimeNpmVersion;
  bool get nodeAvailable => _nodeAvailable;
  String? get nodeError => _nodeError;
  bool get busy =>
      _phase == LabServicePhase.downloading ||
      _phase == LabServicePhase.extracting;

  NodeRunnerMode get runnerMode => _runnerMode;

  /// 当前下载镜像（apt 源与 npm registry 跟随它）。
  NodeDownloadMirror get mirror => _mirror;

  /// 是否显示 Shizuku 相关 UI（Android 才有意义）。
  bool get shizukuRelevant => isAndroid;

  Future<String> _resolveNodeDir() async {
    final cached = _nodeDirCache;
    if (cached != null) return cached;
    final dir = p.join(await labRootPath(), 'node');
    _nodeDirCache = dir;
    return dir;
  }

  /// shell 身份下真正拿去执行的那份 node 的存放处（`/data/local/tmp` 有完整
  /// POSIX 语义：可执行、可 symlink / hardlink）。
  static const String stageRoot = '/data/local/tmp/local2api-node';

  bool _staged = false;

  /// 是否需要暂存：只有 Android + Shizuku 通道要（root 通道能直接进应用目录，
  /// 但为了少一条分支，root 与非 root 走同一条暂存路径）。
  bool get needsStaging =>
      Platform.isAndroid && _runnerMode == NodeRunnerMode.shizuku;

  /// 暂存完成的哨兵文件（复制链最后一步 touch；有它才认为 lib 也拷全了 ——
  /// 只查主二进制大小会漏掉「bin 拷完、lib 拷一半僵死」的情况）。
  static const String _stageSentinel = '$stageRoot/.l2a_stage_ok';

  /// 暂存副本的「签名」函数：主二进制大小 + lib 体积（KB）+ bin 里的文件数。
  ///
  /// 为什么不能只比 `bin/node` 的大小：同版本重装 Node 时二进制大小一模一样，
  /// 但 `lib/` 可能多出/少了 .so，`bin/` 也可能多出配套工具（rg / pcre2-config
  /// —— 它们是随 Node 一起装的 termux 包）。只看 node 大小会认为「暂存还是
  /// 新的」，结果 dsh 的 ripgrep 在暂存副本里找不到，模型直接「没有命令行」。
  ///
  /// `grep -v '^bash$'`：暂存 bin 里有个 bash shim（见 [_bashShimCommand]），
  /// 源目录没有，得排除掉，否则永远不相等。adb shim 同理。
  static const String _stageSigFn = r'''
stage_sig() { echo "$(stat -c %s "$1/bin/node"):$(du -s "$1/lib" 2>/dev/null | cut -f1):$(ls "$1/bin" | grep -vE '^(bash|adb)$' | wc -l | tr -d ' ')"; }
''';

  /// 把 `<lab>/node/{bin,lib}` 整份复制到 [stageRoot]，返回暂存后的可执行路径；
  /// 不需要暂存（或源文件不在）时返回 null。
  ///
  /// 幂等：哨兵在且签名一致（[`_stageSigFn`]：node 大小 + lib 体积 + bin 文件数）
  /// 时直接复用（不再 rm+cp）—— FUSE→f2fs 整棵复制实测要几十 KB/s 到十几 MB/s
  /// 不等（弱板子 f2fs 还会 checkpoint 僵死），应用每次重启都无脑复制一遍就是
  /// 把存储往死里折腾。换过 Node 版本 / 重装后 lib 或 bin 变了 /
  /// 调用 [resetStaging] 后才真正重拷。
  Future<String?> stageForShell() async {
    if (!needsStaging) return null;
    final stagedBin = p.join(stageRoot, 'bin', 'node');
    if (_staged) return stagedBin;
    final nodeDir = await _resolveNodeDir();
    final bin = p.join(nodeDir, 'bin', 'node');
    if (!await File(bin).exists()) return null;
    final shizuku = ShizukuService.instance;
    // 1) 探测暂存副本：哨兵在 + 签名一致（node 大小 / lib 体积 / bin 文件数）→ 复用。
    try {
      final probe = await _runAndCollect(
        shizuku,
        [
          '/system/bin/sh',
          '-c',
          "$_stageSigFn"
              "test -f '$_stageSentinel' && test -f '$stagedBin' && "
              "echo \"\$(stage_sig '$nodeDir')|\$(stage_sig '$stageRoot')\"",
        ],
        '/data/local/tmp',
        null,
        timeout: const Duration(seconds: 20),
      );
      final parts = probe.output.trim().split('|');
      if (probe.exitCode == 0 &&
          parts.length == 2 &&
          parts[0].isNotEmpty &&
          parts[0] == parts[1]) {
        _staged = true;
        _log('暂存副本已就绪：$stageRoot（跳过重复复制）');
        await _ensureBashShim(shizuku);
        return stagedBin;
      }
    } catch (_) {
      // 探测失败（Shizuku 抖动等）就继续走完整复制路径。
    }
    // 2) 完整复制。112MB 级别在慢存储上可能远超一分钟，超时放宽到 10 分钟；
    //    真 f2fs 僵死的话 10 分钟也救不了（那是设备层故障，重启才能解）。
    final cmd =
        "mkdir -p '$stageRoot' && "
        "rm -rf '$stageRoot/bin' '$stageRoot/lib' '$_stageSentinel' && "
        "cp -fRL '$nodeDir/bin' '$stageRoot/bin' && "
        "cp -fRL '$nodeDir/lib' '$stageRoot/lib' && "
        "chmod -R u+rwx '$stageRoot' && "
        "${_stageShimsCommand()} && "
        "touch '$_stageSentinel' && echo staged";
    final result = await _runAndCollect(
      shizuku,
      ['/system/bin/sh', '-c', cmd],
      '/data/local/tmp',
      null,
      timeout: const Duration(minutes: 10),
    );
    if (result.exitCode != 0 || !result.output.contains('staged')) {
      _log('暂存 Node 失败（${result.exitCode}）：${result.output.trim()}');
      return null;
    }
    _staged = true;
    _log('已暂存可执行副本：$stageRoot');
    return stagedBin;
  }

  /// 重装 / 换运行模式后要重新暂存一次。
  void resetStaging() => _staged = false;

  /// 往暂存目录的 `bin/` 写一个 `bash` shim（幂等，几十字节）。
  ///
  /// Android 只有 mksh（`/system/bin/sh`），没有 bash。dsh 的 bash 工具
  /// 直接 `spawn('bash')` → ENOENT，模型会得到「这台设备没有 shell」的
  /// 结论，整个命令行能力废掉（已实测）。[processEnv] 把暂存 `bin/`
  /// 放在 PATH 最前，同名 shim 就能接管：本质是 `exec sh "$@"`。
  /// 只能放暂存目录 —— lab 在 FUSE 上（noexec），脚本放那儿执行不了。
  static String _bashShimCommand() {
    const body = "#!/system/bin/sh\\nexec /system/bin/sh \"\$@\"\\n";
    return "printf '$body' > '$stageRoot/bin/bash' && "
        "chmod 755 '$stageRoot/bin/bash'";
  }

  /// 往暂存目录的 `bin/` 写一个 `adb` 替身（参数翻译成本机 shell）。
  ///
  /// DSH 生态里所有「操作 Android」的插件都按 `adb` CLI 写死
  /// （`@zseven-w/dsh-android` 的 20 个工具、`@huanlin/dsh-plugin-android-use`
  /// 的 10 个工具），前提是 DSH 跑在电脑上、手机挂在 USB 上。我们的 DSH
  /// 就住在手机里（Shizuku 给的 shell 身份），既没有 adb 二进制，也没有
  /// 第二台设备可连。
  ///
  /// 但两边要做的事完全重合：screencap / input / uiautomator dump / pm /
  /// dumpsys / logcat / ps —— 全是 shell 命令，而 node 进程本身就是 shell
  /// 身份（实测 `screencap -p` 出的是完整 PNG，`uiautomator dump` 也能写）。
  /// 所以一个参数翻译脚本就把 adb 顶掉了，插件一行不用改。
  ///
  /// 语义固定为「本机单设备」：serial 一律忽略，`devices -l` 只报一个假设备。
  /// 用 base64 下发，避开 shell 引号地狱。
  static String _adbShimCommand() {
    final body = base64Encode(utf8.encode(_adbShimScript));
    return "printf '%s' '$body' | base64 -d > '$stageRoot/bin/adb' && "
        "chmod 755 '$stageRoot/bin/adb'";
  }

  /// bash + adb 两个 shim（幂等，几十行纯 shell）。
  static String _stageShimsCommand() =>
      '${_bashShimCommand()} && ${_adbShimCommand()}';

  Future<void> _ensureBashShim(ShizukuService shizuku) async {
    try {
      await _runAndCollect(
        shizuku,
        ['/system/bin/sh', '-c', "${_stageShimsCommand()} && echo shim-ok"],
        '/data/local/tmp',
        null,
        timeout: const Duration(seconds: 15),
      );
    } catch (_) {
      // shim 写不进去不致命：只是 dsh 的 bash 工具会继续不可用。
    }
  }

  /// 给实验室目录放开读/写位（`a+rwX`：目录与已有执行位的文件再加 x）。
  ///
  /// FUSE（/sdcard/Android/data）上的文件默认是 `0600 <app>`，Shizuku 的
  /// shell 身份既读不到也写不进去：
  ///   · 只读 → 暂存 node 的 `cp` 每个文件都 Permission denied；
  ///   · 不可写 → npm install 在 `mkdir node_modules` 直接 EACCES 退出 243，
  ///     服务运行时也写不了自己的数据目录（ST 的 data/default-user、
  ///     dsh 的 profile/session）。
  /// 所以 Shizuku 通道下整棵 lab 必须 a+rwX。
  /// [sub] 给定时只处理那个子树（整棵 lab 有几百 MB / 几十万文件，
  /// 全量 chmod 要几分钟）。
  Future<void> makeLabReadable({String sub = ''}) async {
    if (!Platform.isAndroid) return;
    final root = await labRootPath();
    final target = sub.isEmpty ? root : p.join(root, sub);
    if (!await Directory(target).exists()) return;
    // 只放开读位对「直连」通道够了；Shizuku 通道子进程是 shell 身份，
    // 必须连写位一起开。
    final mode = _runnerMode == NodeRunnerMode.shizuku ? 'a+rwX' : 'a+rX';
    try {
      await Process.run('/system/bin/chmod', [
        '-R',
        mode,
        target,
      ], runInShell: false);
    } catch (_) {
      // chmod 不可用（个别 ROM 精简了 toybox）：不致命，状态检测会给出原因。
    }
    await tightenLabSecrets(root);
  }

  /// 递归放权会把 lab 里的敏感文件一起放宽，这里把它们收回属主可读写。
  ///
  /// 现在只有一个：dsh 的 `.dsh/.credentials.yaml`。`@deepseek-ai/dsh-
  /// credentials-local` 启动时会 `assertOwnerOnly`——只要 group/other 还有
  /// 读位就整块插件不激活，dsh 直接 `startup failed: 1 required plugin did
  /// not activate`（connection/authorization 等 10 个插件全跟着挂）。
  /// 所以任何一次 [makeLabReadable] 之后都必须补这一刀；文件属主是 shell，
  /// 600 不影响它自己读写，应用本身也不需要读它。
  Future<void> tightenLabSecrets(String root) async {
    if (!Platform.isAndroid) return;
    final cred = File(p.join(root, '.dsh', '.credentials.yaml'));
    try {
      if (!await cred.exists()) return;
      await Process.run('/system/bin/chmod', ['600', cred.path],
          runInShell: false);
    } catch (_) {}
  }

  /// 放开单个目录及其**顶层子项**的写位（不递归）。
  ///
  /// npm install 前必须调：shell 身份要在目标目录里 `mkdir node_modules`、
  /// **改写 package-lock.json**（应用建的 0600 文件，只 chmod 目录罩不到它）、
  /// 还要往 `<lab>/.npm` 写缓存 —— 无 root 时只能应用自己 chmod。
  /// 只放开到第一层就够：node_modules 一旦由 shell 建出来，整棵新树都是
  /// shell 自己的；递归 chmod 几十万文件纯属浪费。
  Future<void> makeLabDirWritable(String dir) async {
    if (!Platform.isAndroid) return;
    try {
      // 一条 sh 搞定目录 + 顶层子项（glob 展开给 chmod）；个别条目失败
      // （被占用的临时文件之类）不该拖死 npm，`true` 兜底吃掉非零退出。
      await Process.run('/system/bin/sh', [
        '-c',
        "chmod a+rwX '$dir' 2>/dev/null; "
            "chmod a+rwX '$dir'/* 2>/dev/null; true",
      ], runInShell: false);
    } catch (_) {}
  }

  /// 已安装时（或按默认布局）的 node 二进制绝对路径。
  ///
  /// Shizuku 通道返回的是 [stageRoot] 里的暂存副本 —— 外部目录 noexec，
  /// 直接 exec 那份会 `can't execute: Permission denied`。
  Future<String> nodeBinPath() async =>
      await stageForShell() ?? p.join(await _resolveNodeDir(), 'bin', 'node');

  /// npm 的真实入口（termux 的 bin/npm 是 symlink，我们用 node 直接跑
  /// npm-cli.js，绕开 shebang 与 symlink）。
  Future<String> npmCliPath() async => p.join(
    await _resolveNodeDir(),
    'lib',
    'node_modules',
    'npm',
    'bin',
    'npm-cli.js',
  );

  /// node 运行库目录（LD_LIBRARY_PATH 指这里）。暂存过就指暂存副本那份，
  /// 与 [nodeBinPath] 保持同一棵树。
  Future<String> libDir() async => _staged
      ? p.join(stageRoot, 'lib')
      : p.join(await _resolveNodeDir(), 'lib');

  /// Node 进程需要的环境变量（LD_LIBRARY_PATH / HOME / PATH / TMPDIR）。
  ///
  /// Android 上补 HTTP(S)_PROXY（npm 要显式代理变量才会走代理，它不认
  /// Android 的全局代理设置）；NO_PROXY 放行本机回环，否则 ST/dsh 运行时
  /// 会把发往 127.0.0.1 的 API 请求也塞给代理。
  Future<Map<String, String>> processEnv() async {
    final nodeDir = await _resolveNodeDir();
    final lab = p.dirname(nodeDir); // .../lab
    final env = Map<String, String>.from(Platform.environment);
    final libs = await libDir();
    // 暂存过就把暂存副本的 bin 放在 PATH 最前（node 自己 fork 子进程时也要能找到它）。
    final binDir = p.dirname(await nodeBinPath());
    env['LD_LIBRARY_PATH'] = libs;
    env['HOME'] = lab;
    // Termux 的 node 把 OpenSSL 配置文件路径编译死在
    // /data/data/com.termux/files/usr/etc/tls/openssl.cnf；设备上没装 Termux
    // 时这个路径不可读，node 一初始化 crypto（npm 必碰）就报
    // "OpenSSL configuration error" 并以退出码 13 硬退。指到 /dev/null
    // （空配置）跳过加载 —— 我们不需要 engine/证书目录定制。
    env['OPENSSL_CONF'] = '/dev/null';
    // TMPDIR 必须是 shell 写得进去的地方：应用内部 cache 目录（getTemporaryDirectory）
    // 对 Shizuku 的 shell 身份是关掉的，npm / node 一写临时文件就 EACCES。
    final tmp = p.join(lab, 'tmp');
    if (Platform.isAndroid) {
      try {
        await Directory(tmp).create(recursive: true);
      } catch (_) {}
      // tmp 是应用建的（0700），shell 身份的 node 要在里面写临时文件。
      //
      // 只放 tmp **自己**，不碰已有子项：dsh 的 spill-local 会逐个校验
      // 「这个目录属主是我、且 group/other 不可写」，而 makeLabDirWritable
      // 的 `chmod a+rwX $dir/*` 会把上一轮留下的 `dsh-spill-*` 一并刷成 777，
      // 于是全部被判 unsafe 跳过（日志：'spill-local: skipped unsafe root'）。
      // dsh 自己 mkdtemp 出来的新目录是 700 属 shell，本来就合规。
      try {
        await Process.run('/system/bin/chmod', ['777', tmp],
            runInShell: false);
      } catch (_) {}
    }
    env['TMPDIR'] = tmp;
    env['PATH'] = '$binDir:${env['PATH'] ?? ''}';
    env['NODE_PATH'] = p.join(nodeDir, 'lib', 'node_modules');
    // 镜像模式下让子进程里的 npm 也走 npmmirror（npm 只认自己的
    // npm_config_registry，不认 Android 的全局代理）。
    if (_mirror == NodeDownloadMirror.cn) {
      env['npm_config_registry'] = npmRegistryCn;
    }
    if (!env.containsKey('HTTPS_PROXY')) {
      final proxy = await NetworkUtils.systemHttpProxy();
      if (proxy != null) {
        env['HTTP_PROXY'] = 'http://$proxy';
        env['HTTPS_PROXY'] = 'http://$proxy';
        env['http_proxy'] = env['HTTP_PROXY']!;
        env['https_proxy'] = env['HTTPS_PROXY']!;
        env['NO_PROXY'] = 'localhost,127.0.0.1,::1';
        env['no_proxy'] = env['NO_PROXY']!;
      }
    }
    return env;
  }

  Future<void> init() async {
    // 并发守卫：LabPage 的 _st.init / _node.init 会同时把这里拉进来，
    // 不锁的话 init 里的 refreshNodeStatus 会并发跑两份。
    final inFlight = _initFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final completer = Completer<void>();
    _initFuture = completer.future;
    try {
      await _initOnce();
    } finally {
      completer.complete();
      _initFuture = null;
    }
  }

  Future<void> _initOnce() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _installedVersion = _prefs!.getString(_prefVersion);
    final rawRunner = _prefs!.getString(_prefRunner);
    _runnerMode = rawRunner == 'shizuku'
        ? NodeRunnerMode.shizuku
        : NodeRunnerMode.direct;
    _mirror = _prefs!.getString(_prefMirror) == 'cn'
        ? NodeDownloadMirror.cn
        : NodeDownloadMirror.official;
    // 记录过版本但文件没了（清了数据 / 手动删了）：视为未装。
    final bin = File(await nodeBinPath());
    if (_installedVersion != null && !await bin.exists()) {
      _installedVersion = null;
      await _prefs!.remove(_prefVersion);
    }
    _initialized = true;
    notifyListeners();
    if (isAndroid && _installedVersion != null) {
      await refreshNodeStatus();
    }
  }

  Future<void> setRunnerMode(NodeRunnerMode mode) async {
    if (mode == _runnerMode) return;
    _runnerMode = mode;
    resetStaging();
    await _prefs?.setString(
      _prefRunner,
      mode == NodeRunnerMode.shizuku ? 'shizuku' : 'direct',
    );
    notifyListeners();
    // 切到 Shizuku 通道：之前按「直连」只放开了读位，shell 身份还需要写位
    // （npm install / 服务运行时都要往 lab 里写），补一次全树 chmod。
    if (isAndroid && mode == NodeRunnerMode.shizuku) {
      await makeLabReadable();
    }
    if (isAndroid && _installedVersion != null) await refreshNodeStatus();
  }

  /// 切换下载镜像（只影响之后的下载，不动已装内容）。
  Future<void> setMirror(NodeDownloadMirror mirror) async {
    if (mirror == _mirror) return;
    _mirror = mirror;
    await _prefs?.setString(
      _prefMirror,
      mirror == NodeDownloadMirror.cn ? 'cn' : 'official',
    );
    _log(
      mirror == NodeDownloadMirror.cn
          ? '下载镜像：中国大陆（TUNA · npmmirror）'
          : '下载镜像：官方源',
    );
    notifyListeners();
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

  // ---- 检测 ----

  /// 实测 node 能不能跑（单飞：并发调用共享同一次检测结果）。
  Future<void> refreshNodeStatus() async {
    final inFlight = _refreshing;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final completer = Completer<void>();
    _refreshing = completer.future;
    try {
      await _refreshOnce();
    } finally {
      completer.complete();
      _refreshing = null;
    }
  }

  Future<void> _refreshOnce() async {
    if (!isAndroid) {
      _nodeAvailable = false;
      _nodeError = 'notAndroid';
      notifyListeners();
      return;
    }
    if (_installedVersion == null) {
      _nodeAvailable = false;
      _runtimeNodeVersion = null;
      _runtimeNpmVersion = null;
      _nodeError = 'notInstalled';
      notifyListeners();
      return;
    }
    final inTest =
        Platform.environment['FLUTTER_TEST'] == 'true' ||
        const bool.fromEnvironment('FLUTTER_TEST');
    if (inTest) {
      _nodeAvailable = false;
      _nodeError = 'test';
      notifyListeners();
      return;
    }
    if (_runnerMode == NodeRunnerMode.shizuku) {
      await _refreshViaShizuku();
      notifyListeners();
      return;
    }
    try {
      final bin = await nodeBinPath();
      final env = await processEnv();
      final result = await Process.run(
        bin,
        ['--version'],
        environment: env,
        runInShell: false,
      ).timeout(const Duration(seconds: 15));
      if (result.exitCode == 0) {
        _runtimeNodeVersion = '${result.stdout}'.trim();
        _nodeAvailable = true;
        _nodeError = null;
        // npm 版本（node npm-cli.js --version）
        try {
          final npm = await Process.run(
            bin,
            [await npmCliPath(), '--version'],
            environment: env,
            runInShell: false,
          ).timeout(const Duration(seconds: 15));
          if (npm.exitCode == 0) _runtimeNpmVersion = '${npm.stdout}'.trim();
        } catch (_) {}
      } else {
        _nodeAvailable = false;
        _nodeError = 'nodeExit${result.exitCode}';
        _log('node --version 退出码 ${result.exitCode}');
      }
    } on ProcessException catch (e) {
      _nodeAvailable = false;
      // errno 13 = 系统禁止 exec 数据目录里的文件（release 构建）。
      _nodeError = e.errorCode == 13 ? 'execBlocked' : 'processException';
      _log('无法直接执行 node：$e');
    } catch (e) {
      _nodeAvailable = false;
      _nodeError = 'unknown';
      _log('检测 node 失败：$e');
    }
    notifyListeners();
  }

  /// Shizuku 模式的版本检测：经 Shizuku 以 shell 身份跑 `node --version`。
  Future<void> _refreshViaShizuku() async {
    final shizuku = ShizukuService.instance;
    if (!await shizuku.ping()) {
      _nodeAvailable = false;
      _nodeError = 'shizukuUnavailable';
      notifyListeners();
      return;
    }
    if (!await shizuku.isGranted()) {
      _nodeAvailable = false;
      _nodeError = 'shizukuNotGranted';
      notifyListeners();
      return;
    }
    try {
      final bin = await nodeBinPath();
      final env = await processEnv();
      final nodeDir = await _resolveNodeDir();
      var lines = await _runAndCollect(
        shizuku,
        [bin, '--version'],
        nodeDir,
        env,
      );
      // 有些 ROM（Android 11+ 收紧了 /sdcard/Android/data）连 shell 都进不去
      // 外部目录，chdir 就是 EACCES —— 换「不指定 cwd」再试一次。
      if (lines.exitCode != 0) {
        lines = await _runAndCollect(
          shizuku,
          [bin, '--version'],
          '/data/local/tmp',
          env,
        );
        if (lines.exitCode == 0) _labCwdBlocked = true;
      }
      if (lines.exitCode == 0) {
        _runtimeNodeVersion = lines.output.trim();
        _nodeAvailable = true;
        _nodeError = null;
        // 先亮结果：npm 版本是次要信息，异步补（npm-cli 首跑可能偏慢，
        // 别让它把 nodeAvailable 的刷新一起拖住）。
        notifyListeners();
        unawaited(
          _runAndCollect(
                shizuku,
                [bin, await npmCliPath(), '--version'],
                _labCwdBlocked ? '/data/local/tmp' : nodeDir,
                env,
              )
              .then((npm) {
                if (npm.exitCode == 0) _runtimeNpmVersion = npm.output.trim();
                notifyListeners();
              })
              .catchError((Object _) {
                notifyListeners();
              }),
        );
      } else {
        _nodeAvailable = false;
        _nodeError = 'nodeExit${lines.exitCode}';
        _log('node --version（Shizuku）退出码 ${lines.exitCode}：${lines.output}');
      }
    } catch (e) {
      _nodeAvailable = false;
      // 带上异常摘要方便定位（Channel error / SecurityException 等）。
      final summary = '$e'.replaceAll('\n', ' ');
      var brief = summary.length > 90 ? summary.substring(0, 90) : summary;
      // 光看这条异常分不清是「进不去外部目录」还是「执行不了暂存的 node」，
      // 再探一次把两者拆开报（Android 11+ 的 user build 上 shell 摸不到
      // /sdcard/Android/data，chdir 就是 EACCES）。
      if (isPermissionDeniedError(e)) {
        brief = '$brief | ${await diagnoseShizukuAccess()}';
      }
      _nodeError = 'unknown:$brief';
      _log('Shizuku 检测 node 失败：$e');
    }
  }

  /// 外部目录能不能当 cwd（探出来一次就记住，后续命令直接跳过注定失败的尝试）。
  bool _labCwdBlocked = false;
  bool get labCwdBlocked => _labCwdBlocked;

  /// 由调用方在「带 cwd 失败、不带 cwd 成功」时回记一次。
  void noteLabCwdBlocked() => _labCwdBlocked = true;

  /// 是不是「权限不够」这一类失败（Java 的 ProcessBuilder 把 errno 放在消息里）。
  static bool isPermissionDeniedError(Object error) {
    final text = '$error';
    return text.contains('error=13') ||
        text.contains('Permission denied') ||
        text.contains('EACCES');
  }

  /// 三步自检：shell 能不能进外部目录、能不能读暂存的 node、能不能把它跑起来。
  ///
  /// 结果拼成一行给状态文案用 —— 用户截图里那条 `error=13` 光看分不清是哪一步。
  Future<String> diagnoseShizukuAccess() async {
    final shizuku = ShizukuService.instance;
    final lab = await labRootPath();
    final staged = p.join(stageRoot, 'bin', 'node');
    final out = <String>[];
    Future<void> probe(String name, List<String> cmd) async {
      try {
        final r = await _runAndCollect(
          shizuku,
          cmd,
          '/data/local/tmp',
          null,
          timeout: const Duration(seconds: 12),
        );
        final tail = r.exitCode == 0
            ? (r.output.trim().isEmpty ? 'ok' : r.output.trim())
            : 'exit${r.exitCode}';
        out.add('$name=$tail');
      } catch (e) {
        final text = '$e'.replaceAll('\n', ' ');
        out.add('$name=${text.length > 40 ? text.substring(0, 40) : text}');
      }
    }

    await probe('cd', ['/system/bin/sh', '-c', 'cd "$lab" && echo ok']);
    await probe('read', [
      '/system/bin/sh',
      '-c',
      'test -r "$staged" && echo ok',
    ]);
    await probe('exec', [staged, '--version']);
    return out.join(' ');
  }

  /// 经 Shizuku 跑一条命令并收集 stdout / 退出码（版本检测、暂存复制用）。
  static Future<({int exitCode, String output})> _runAndCollect(
    ShizukuService shizuku,
    List<String> command,
    String workingDirectory,
    Map<String, String>? environment, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final pid = await shizuku.start(
      command: command,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    final out = StringBuffer();
    final completer = Completer<int>();
    late final StreamSubscription<ShizukuProcEvent> sub;
    sub = shizuku.events(pid).listen((event) {
      if (event.isExit) {
        if (!completer.isCompleted) completer.complete(event.exitCode ?? -1);
      } else if (!event.isError) {
        out.writeln(event.line ?? '');
      }
    });
    int code;
    try {
      code = await completer.future.timeout(
        timeout,
        onTimeout: () => throw StateError(
          'Shizuku 进程 ${timeout.inSeconds}s 未退出（waitFor 无返回）',
        ),
      );
    } finally {
      await sub.cancel();
      await shizuku.kill(pid);
    }
    return (exitCode: code, output: out.toString());
  }

  // ---- 安装 ----

  /// 下载并安装 Node.js 运行时（Termux 仓库的 9 个 deb）。
  Future<void> install() async {
    if (!isAndroid || busy) return;
    _error = null;
    _progress = 0;
    _phase = LabServicePhase.downloading;
    notifyListeners();
    try {
      // 1) 解析 apt 索引 → 每个包的 deb 路径与大小
      _log('获取软件源索引…');
      final index = await _fetchPackagesIndex();
      final entries = <_PkgEntry>[];
      for (final name in wantedPackages) {
        final e = index[name];
        if (e == null) {
          if (optionalPackages.contains(name)) {
            _log('软件源里没有 $name（跳过）');
            continue;
          }
          throw Exception('软件源里找不到包 $name');
        }
        entries.add(
          _PkgEntry(
            name: name,
            url: '$repoBase${e['Filename']!}',
            size: int.tryParse(e['Size'] ?? '') ?? 0,
            version: e['Version'] ?? '',
          ),
        );
      }
      final totalBytes = entries.fold<int>(0, (s, e) => s + e.size);
      _log(
        '共 ${entries.length} 个包，约 ${(totalBytes / 1048576).toStringAsFixed(1)} MB',
      );

      // 2) 并行下载（3 路）
      final tempDir = await getTemporaryDirectory();
      final debDir = Directory(p.join(tempDir.path, 'lab_node_debs'));
      if (await debDir.exists()) await debDir.delete(recursive: true);
      await debDir.create(recursive: true);
      var downloadedBytes = 0;
      final downloaded = <String, String>{}; // name -> deb path
      var next = 0;
      Future<void> worker() async {
        while (true) {
          final i = next++;
          if (i >= entries.length) return;
          final entry = entries[i];
          final file = File(p.join(debDir.path, '${entry.name}.deb'));
          await _downloadTo(entry.url, file, (delta) {
            downloadedBytes += delta;
            if (totalBytes > 0) {
              final nextProgress = downloadedBytes / totalBytes;
              if (nextProgress - (_progress ?? 0) >= 0.01 ||
                  nextProgress >= 1) {
                _progress = nextProgress;
                notifyListeners();
              }
            }
          });
          downloaded[entry.name] = file.path;
          _log('已下载 ${entry.name} ${entry.version}');
        }
      }

      await Future.wait([worker(), worker(), worker()]);

      // 3) 逐个解包（串行，控制内存峰值）
      _phase = LabServicePhase.extracting;
      _progress = null;
      notifyListeners();
      final nodeDir = await _resolveNodeDir();
      final target = Directory(nodeDir);
      if (await target.exists()) await target.delete(recursive: true);
      await target.create(recursive: true);
      for (final name in wantedPackages) {
        final debPath = downloaded[name];
        if (debPath == null) continue; // 可选包缺失（已在上一步记日志）
        final stats = await _extractOne(debPath, nodeDir);
        _log('解包 $name：${stats.files} 个文件');
      }

      // 4) 权限：node 主二进制要可执行（应用对自己的文件可以 chmod），并且
      //    整棵实验室目录要放开读位，Shizuku 的 shell 身份才读得动。
      final bin = p.join(await _resolveNodeDir(), 'bin', 'node');
      await Process.run('chmod', ['755', bin], runInShell: false);
      await makeLabReadable();
      resetStaging();

      // 5) 记录版本 + 实测
      final nodeEntry = entries.firstWhere((e) => e.name == 'nodejs');
      _installedVersion = nodeEntry.version;
      await _prefs?.setString(_prefVersion, nodeEntry.version);
      _log('Node.js ${nodeEntry.version} 安装完成');
      _phase = LabServicePhase.idle;
      _progress = null;
      notifyListeners();
      await refreshNodeStatus();
      // 清理 deb 缓存
      try {
        await debDir.delete(recursive: true);
      } catch (_) {}
    } catch (e) {
      _phase = LabServicePhase.idle;
      _progress = null;
      _error = '$e';
      _log('安装失败：$e');
      notifyListeners();
    }
  }

  /// 在短命 isolate 里解一个 deb。
  ///
  /// 必须是 static：实例方法里直接 `Isolate.run(() => extractDebSync(...))`
  /// 会把闭包所在的整条 context 链（含 this / 渲染树引用）一起序列化，
  /// 直接报 "object is unsendable"（ST 的 _extractZip 同款规避）。
  static Future<DebExtractStats> _extractOne(String debPath, String destDir) =>
      Isolate.run(() => extractDebSync(debPath, destDir));

  Future<Map<String, Map<String, String>>> _fetchPackagesIndex() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    // Android 上走系统全局代理（模拟器/内网必备），桌面跟随环境变量。
    await NetworkUtils.configureDownloadProxy(client);
    try {
      final req = await client.getUrl(Uri.parse(await packagesUrl()));
      req.headers.set(HttpHeaders.userAgentHeader, 'Local2API');
      final res = await req.close();
      if (res.statusCode != 200) {
        throw Exception('获取软件源索引失败：HTTP ${res.statusCode}');
      }
      final text = await utf8.decoder.bind(res).join();
      return parsePackagesIndex(text);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _downloadTo(
    String url,
    File file,
    void Function(int delta) onDelta,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    await NetworkUtils.configureDownloadProxy(client);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, 'Local2API');
      final res = await req.close();
      if (res.statusCode != 200) {
        throw Exception('下载失败 HTTP ${res.statusCode}: $url');
      }
      await file.parent.create(recursive: true);
      final sink = file.openWrite();
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          onDelta(chunk.length);
        }
      } finally {
        await sink.close();
      }
    } finally {
      client.close(force: true);
    }
  }

  // ---- 卸载 ----

  Future<void> uninstall() async {
    if (!isAndroid) return;
    final nodeDir = await _resolveNodeDir();
    try {
      final dir = Directory(nodeDir);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      _error = '$e';
      notifyListeners();
      return;
    }
    _installedVersion = null;
    _runtimeNodeVersion = null;
    _runtimeNpmVersion = null;
    _nodeAvailable = false;
    _nodeError = 'notInstalled';
    await _prefs?.remove(_prefVersion);
    _logs.clear();
    _log('已卸载 Node.js 运行时');
    notifyListeners();
  }
}

class _PkgEntry {
  const _PkgEntry({
    required this.name,
    required this.url,
    required this.size,
    required this.version,
  });

  final String name;
  final String url;
  final int size;
  final String version;
}

// ---- 纯函数（可被 isolate / 测试复用） ----

/// 解析 Termux 的 Packages 索引文本：包名 -> 字段表。
Map<String, Map<String, String>> parsePackagesIndex(String text) {
  final out = <String, Map<String, String>>{};
  for (final block in text.split('\n\n')) {
    String? pkg;
    final fields = <String, String>{};
    for (final line in block.split('\n')) {
      final m = RegExp('^([A-Za-z][A-Za-z0-9-]*): (.*)\$').firstMatch(line);
      if (m == null) continue;
      fields[m.group(1)!] = m.group(2)!;
      if (m.group(1) == 'Package') pkg = m.group(2);
    }
    if (pkg != null) out[pkg] = fields;
  }
  return out;
}

/// 从 deb 的 ar 归档里切出成员（deb 是普通 Unix ar）。
Map<String, Uint8List> extractArMembers(Uint8List deb) {
  final magic = '!<arch>\n'.codeUnits;
  if (deb.length < 8) throw const FormatException('文件太小，不是 deb');
  for (var i = 0; i < 8; i++) {
    if (deb[i] != magic[i]) throw const FormatException('不是合法的 deb 包');
  }
  final out = <String, Uint8List>{};
  var off = 8;
  while (off + 60 <= deb.length) {
    final name = String.fromCharCodes(
      deb.sublist(off, off + 16),
    ).trim().replaceAll(RegExp(r'/+$'), '');
    final size = int.parse(
      String.fromCharCodes(deb.sublist(off + 48, off + 58)).trim(),
    );
    final start = off + 60;
    if (start + size > deb.length) throw const FormatException('deb 损坏');
    out[name] = Uint8List.sublistView(deb, start, start + size);
    off = start + size + (size % 2);
  }
  return out;
}

class DebExtractStats {
  const DebExtractStats({required this.files});
  final int files;
}

/// 把一个 Termux deb 解包到 [destDir]（在 isolate 里跑的同步实现）。
///
/// 只抽 `usr/bin/` 与 `usr/lib/` 两个子树（node 主程序 + 运行库 + npm），
/// 跳过 include / share；路径前缀 `data/data/com.termux/files/usr/` 会被
/// 剥掉。**symlink 必须重建**（zlib 的 libz.so.1 → libz.so.1.3.2、libicu
/// 的 libicuuc.so.78 → libicuuc.so.78.3 都是 symlink，而 bionic linker
/// 按 DT_NEEDED 的名字找库，缺了 symlink 就 "library not found"）。
DebExtractStats extractDebSync(String debPath, String destDir) {
  final deb = File(debPath).readAsBytesSync();
  final members = extractArMembers(deb);
  final dataTarXz = members['data.tar.xz'];
  if (dataTarXz == null) {
    throw const FormatException('deb 里没有 data.tar.xz');
  }
  final tarBytes = XZDecoder().decodeBytes(dataTarXz);
  final archive = TarDecoder().decodeBytes(tarBytes);

  const usrPrefix = 'data/data/com.termux/files/usr/';
  var files = 0;
  // symlink 留到第二遍处理：Termux 的 deb 里 `libz.so.1 -> libz.so.1.3.2` 这类
  // 条目常常排在目标实体文件**前面**，当场复制会找不到源而整个丢掉（丢了就
  // "library not found"，bionic linker 只按 DT_NEEDED 的名字找库）。
  final links = <List<String>>[];
  for (final entry in archive) {
    if (entry.isDirectory) continue;
    var name = entry.name.replaceAll('\\', '/');
    while (name.startsWith('./')) {
      name = name.substring(2);
    }
    if (!name.startsWith(usrPrefix)) continue;
    final rel = name.substring(usrPrefix.length);
    // 只要 bin/ 与 lib/ 子树
    if (!(rel.startsWith('bin/') || rel.startsWith('lib/'))) continue;
    if (rel.isEmpty) continue;
    final outPath = p.normalize(p.join(destDir, rel));
    if (!p.isWithin(destDir, outPath)) continue; // zip-slip 防御
    if (entry.isSymbolicLink) {
      final target = entry.symbolicLink;
      if (target == null || target.isEmpty) continue;
      Directory(p.dirname(outPath)).createSync(recursive: true);
      links.add(<String>[outPath, target]);
      continue;
    }
    final out = File(outPath);
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(entry.content as List<int>, flush: false);
    files++;
  }

  for (final pair in links) {
    final outPath = pair[0];
    final target = pair[1];
    final link = Link(outPath);
    if (link.existsSync()) link.deleteSync();
    try {
      // 首选原样重建 symlink：相对 target（termux 包内一律相对同目录）。
      link.createSync(target);
      files++;
      continue;
    } catch (_) {
      // 外部存储（FUSE / sdcardfs）不支持 symlink，退化成把目标复制成同名实体
      // 文件 —— 与 deepseek-harness-android-app 按 LINKS.txt 复制 soname 同法。
    }
    final source = File(p.normalize(p.join(p.dirname(outPath), target)));
    if (!source.existsSync()) continue;
    File(outPath).writeAsBytesSync(source.readAsBytesSync(), flush: false);
    files++;
  }
  return DebExtractStats(files: files);
}

/// 「本机单设备」的 adb 替身脚本（见 [NodeRuntimeService._adbShimCommand]）。
///
/// 只翻译 DSH 插件真正会用的子命令；`exec` 替换进程保证 exit code 与
/// 二进制输出（screencap 的 PNG）原样透传。serial 全部忽略 —— 本来就只有
/// 一台设备（就是这台）。
const String _adbShimScript = r'''#!/system/bin/sh
# local2api adb shim: 把 adb 命令翻译成本机 shell 执行。
# 由 local2api 的 Node 运行时写入（幂等覆盖），DSH 的 Android 操作插件靠它跑通。

# 系统二进制（app_process / uiautomator / monkey / am / pm）绝对不能继承
# termux 的 LD_LIBRARY_PATH：linker 会去 termux lib 里找同名 .so，然后报
#   CANNOT LINK EXECUTABLE "app_process": cannot find "libz.so" from ...
# 我们自己的 node 用不到 adb，所以这里直接清掉，让每条被翻译的命令都在
# 一个干净的 Android 环境里跑。
unset LD_LIBRARY_PATH

SERIAL=local2api

while [ $# -gt 0 ]; do
  case "$1" in
    -s) [ $# -ge 2 ] && SERIAL="$2"; shift; [ $# -gt 0 ] && shift ;;
    -d|-e|-t|-T) shift ;;
    -P|-H) shift; [ $# -gt 0 ] && shift ;;
    *) break ;;
  esac
done

CMD="$1"
if [ $# -gt 0 ]; then shift; fi

sh_quote() {
  case "$1" in
    *\'*) printf '"%s"' "$1" ;;
    ''|*[!A-Za-z0-9_./:=@%+,-]*) printf "'%s'" "$1" ;;
    *) printf '%s' "$1" ;;
  esac
}

build_cmd() {
  _c=
  for _a in "$@"; do
    _c="$_c $(sh_quote "$_a")"
  done
  printf '%s' "${_c# }"
}

run_shell() {
  if [ $# -eq 0 ]; then exec /system/bin/sh -i; fi
  if [ $# -eq 1 ]; then _rcmd="$1"; else _rcmd="$(build_cmd "$@")"; fi
  case "$_rcmd" in
    *"/dev/tty"*)
      # 我们是通过 socket 起的 shell，没有控制终端；`uiautomator dump /dev/tty`
      # 会直接失败（插件报 "could not dump the window hierarchy"）。
      # 改写成临时文件，跑完把内容回吐到 stdout。
      _tty=/data/local/tmp/.l2a_tty.$$
      _rcmd=$(printf '%s' "$_rcmd" | sed "s|/dev/tty|$_tty|g")
      /system/bin/sh -c "$_rcmd" >/dev/null 2>&1
      cat "$_tty" 2>/dev/null
      rm -f "$_tty"
      exit 0
      ;;
  esac
  exec /system/bin/sh -c "$_rcmd"
}

case "$CMD" in
devices)
  if [ "$1" = "-l" ]; then
    printf 'List of devices attached\n%s\tdevice product:local2api model:local2api device:local2api transport_id:1\n' "$SERIAL"
  else
    printf 'List of devices attached\n%s\tdevice\n' "$SERIAL"
  fi
  ;;
shell)
  while [ $# -gt 0 ]; do
    case "$1" in
      -t|-T|-n|-e) shift ;;
      *) break ;;
    esac
  done
  run_shell "$@"
  ;;
exec-out|exec-in)
  run_shell "$@"
  ;;
install)
  APK=
  for _a in "$@"; do
    case "$_a" in
      -*) ;;
      *) APK="$_a" ;;
    esac
  done
  if [ -z "$APK" ]; then echo "adb: install needs an apk path" >&2; exit 1; fi
  exec /system/bin/pm install -r "$APK"
  ;;
uninstall)
  PKG=
  for _a in "$@"; do
    case "$_a" in
      -*) ;;
      *) PKG="$_a" ;;
    esac
  done
  if [ -z "$PKG" ]; then echo "adb: uninstall needs a package" >&2; exit 1; fi
  exec /system/bin/pm uninstall "$PKG"
  ;;
push)
  if [ $# -lt 2 ]; then echo "adb: push needs <local> <remote>" >&2; exit 1; fi
  exec /system/bin/cp -f "$1" "$2"
  ;;
pull)
  while [ $# -gt 0 ]; do
    case "$1" in
      -*) shift ;;
      *) break ;;
    esac
  done
  if [ $# -lt 1 ]; then echo "adb: pull needs <remote> [local]" >&2; exit 1; fi
  if [ $# -lt 2 ]; then exec /system/bin/cat "$1"; fi
  exec /system/bin/cp -f "$1" "$2"
  ;;
logcat)
  exec /system/bin/logcat "$@"
  ;;
wait-for-device|start-server|kill-server|reconnect|root|unroot|remount|forward|reverse|tcpip|usb|disable-verity|enable-verity)
  exit 0
  ;;
emu)
  exit 0
  ;;
get-state)
  echo device
  ;;
get-serialno|get-devpath)
  echo "$SERIAL"
  ;;
version)
  echo "Android Debug Bridge version 1.0.41"
  echo "Version 34.0.5-local2api-shim"
  ;;
"")
  exit 0
  ;;
*)
  exec /system/bin/sh -c "$CMD $(build_cmd "$@")"
  ;;
esac
''';
