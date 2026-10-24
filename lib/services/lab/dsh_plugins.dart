// lib/services/lab/dsh_plugins.dart
//
// dsh 插件管理：把社区里的几个 bundle 装进 web profile 并开关。
//
//   · 编辑消息：`@xt765/dsh-message-edit`（xt765/dsh-message-edit）
//     在用户消息气泡旁加铅笔按钮，改完从上一轮分叉重发。
//   · 电脑操作：`dsh-computer-use-mode`（EvangeliMo/dsh-computer-use-mode）
//     给 dsh 加「电脑操作模式」：截屏 + 鼠标键盘控制，Windows 专用。
//   · 手机操作：`@zseven-w/dsh-android`（ZSeven-W/dsh-android）
//     20 个 adb 工具：截图 / 点按 / 滑动 / UI 树 / OCR / logcat / 进程。
//     安卓独占 —— 靠 Node 运行时暂存 bin 里的 adb shim 把 adb 命令翻译给
//     本机 shell（见 NodeRuntimeService 的 _adbShimCommand）。
//
// 三者都是自带 `dsh.bundle.patch` 的 bundle：装到
// `$DSH_HOME/profiles/web/node_modules` 后，把包名写进
// `profiles/web/package.json` 的 `dsh.profile.bundles` 就生效。
//
// 不依赖 pnpm（dsh 官方的 `dsh plugin` 只是 pnpm 的转发器）：这里直接
// `npm install --no-save` 到 profile，再自己维护依赖与 bundles —— 用户机器
// 上通常只有 npm。开关只动 bundles，不卸载包，关掉即时生效、再开不用重下。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'dsh_service.dart';
import 'lab_process.dart';
import 'node_runtime_service.dart';

/// 本应用认识的 dsh 插件。
enum DshPluginId { messageEdit, computerUse, androidControl }

/// 插件能跑的宿主平台；[any] 表示不限（web 客户端插件，桌面 / 安卓都能用）。
enum DshPluginHost { any, windows, android }

/// 平台名（给「只支持 Windows」这类提示用，不进 l10n：是专有名词）。
String dshPluginHostLabel(DshPluginHost host) => switch (host) {
  DshPluginHost.any => '',
  DshPluginHost.windows => 'Windows',
  DshPluginHost.android => 'Android',
};

/// 宿主平台是否满足 [host]（抽成纯函数，平台门控的回归测试不碰真机）。
bool dshPluginHostSupports(
  DshPluginHost host, {
  required bool isWindows,
  required bool isAndroid,
}) => switch (host) {
  DshPluginHost.any => true,
  DshPluginHost.windows => isWindows,
  DshPluginHost.android => isAndroid,
};

class DshPluginSpec {
  const DshPluginSpec({
    required this.id,
    required this.package,
    required this.url,
    required this.minVersion,
    this.host = DshPluginHost.any,
  });

  final DshPluginId id;

  /// npm 包名，同时也是 `dsh.profile.bundles` 里的名字。
  final String package;

  /// 给用户看的来源（GitHub 仓库）。
  final String url;

  /// dsh 低于这个版本就不给装（插件按新版的客户端插槽写的）。
  final String minVersion;

  /// 宿主平台限制。默认不限 —— dsh 的 web 客户端插件在手机和桌面是同一份。
  final DshPluginHost host;
}

const List<DshPluginSpec> kDshPlugins = [
  DshPluginSpec(
    id: DshPluginId.messageEdit,
    package: '@xt765/dsh-message-edit',
    url: 'https://github.com/xt765/dsh-message-edit',
    minVersion: '0.1.0',
  ),
  DshPluginSpec(
    id: DshPluginId.computerUse,
    package: 'dsh-computer-use-mode',
    url: 'https://github.com/EvangeliMo/dsh-computer-use-mode',
    minVersion: '0.1.0',
    // 截屏 + 鼠标键盘合成走 koffi 的 win32 原生模块，只有 Windows 装得上。
    host: DshPluginHost.windows,
  ),
  // 20 个工具：截图 / 点按 / 滑动 / uiautomator 树 / OCR / logcat / 进程 /
  // meminfo / Gradle 构建。插件本身按 `adb` CLI 写死（假设 DSH 在电脑上、
  // 手机挂 USB），但 `NodeRuntimeService` 会往暂存 bin 里放一个 adb shim
  // 把命令翻译给本机 shell —— 于是同一套工具在「DSH 跑在手机里」这个形状
  // 下也能用，不用维护自己的一套 Android 操作工具。
  DshPluginSpec(
    id: DshPluginId.androidControl,
    package: '@zseven-w/dsh-android',
    url: 'https://github.com/ZSeven-W/dsh-android',
    minVersion: '0.1.0',
    // adb shim 只在安卓宿主上存在（见 NodeRuntimeService 的 _adbShimCommand）。
    host: DshPluginHost.android,
  ),
];

DshPluginSpec dshPluginSpec(DshPluginId id) =>
    kDshPlugins.firstWhere((spec) => spec.id == id);

/// npm 包名 → 内置插件（第三方插件返回 null）。
DshPluginSpec? specForPackage(String package) {
  for (final spec in kDshPlugins) {
    if (spec.package == package) return spec;
  }
  return null;
}

/// UI 上一个插件条目的全部信息（内置推荐 + 已装的第三方都走这里）。
class ManagedDshPlugin {
  const ManagedDshPlugin({
    required this.package,
    required this.version,
    required this.description,
    required this.homepage,
    required this.installed,
    required this.enabled,
    required this.busy,
    required this.recommended,
    required this.supportedOnThisHost,
    this.requiredHost,
    this.displayName,
    this.error,
  });

  /// npm 包名（scoped 包带前缀），也是 bundles 里的名字。
  final String package;

  /// 展示名：内置插件用本地化标题，第三方就是包名。
  final String? displayName;

  final String version;
  final String description;
  final String? homepage;
  final bool installed;
  final bool enabled;
  final bool busy;
  final bool recommended;
  final bool supportedOnThisHost;

  /// 平台不支持时该插件要求的宿主（`Windows` / `Android`），否则 null。
  final String? requiredHost;
  final String? error;

  /// 不属于内置推荐清单的，就是从 npm 装进来的第三方包。
  bool get isThirdParty => !recommended;

  /// 搜索匹配：包名 + 描述 + 展示名，大小写无关。
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return package.toLowerCase().contains(q) ||
        description.toLowerCase().contains(q) ||
        (displayName ?? '').toLowerCase().contains(q);
  }
}

/// 一个插件在 UI 上要显示的状态。
class DshPluginState {
  const DshPluginState({
    this.installed = false,
    this.enabled = false,
    this.busy = false,
    this.error,
  });

  final bool installed;
  final bool enabled;
  final bool busy;
  final String? error;

  DshPluginState copyWith({
    bool? installed,
    bool? enabled,
    bool? busy,
    String? error,
    bool clearError = false,
  }) =>
      DshPluginState(
        installed: installed ?? this.installed,
        enabled: enabled ?? this.enabled,
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
      );
}

class DshPluginsService extends ChangeNotifier {
  DshPluginsService._();

  static final DshPluginsService instance = DshPluginsService._();

  DshService? _dsh;
  bool _loaded = false;

  final Map<DshPluginId, DshPluginState> _states = {
    for (final spec in kDshPlugins) spec.id: const DshPluginState(),
  };

  // 第三方包的服务状态没法塞进上面那张表（key 是枚举），单独存。
  final Map<String, bool> _busy = <String, bool>{};
  final Map<String, String> _errors = <String, String>{};

  void _setPackage(
    String package, {
    bool? busy,
    String? error,
    bool clearError = false,
  }) {
    if (busy != null) _busy[package] = busy;
    if (clearError) {
      _errors.remove(package);
    } else if (error != null) {
      _errors[package] = error;
    }
    notifyListeners();
  }

  DshPluginState stateOf(DshPluginId id) =>
      _states[id] ?? const DshPluginState();

  /// 某个包最近一次失败的原因（内置 / 第三方统一取值）。
  String? errorOf(String package) {
    final spec = specForPackage(package);
    return spec != null ? _states[spec.id]?.error : _errors[package];
  }

  /// [spec] 在这台机器上能不能用（第三方包一律可用）。
  bool supported(DshPluginId id) {
    final dsh = _dsh;
    if (dsh == null || !dsh.installed) return false;
    final host = dshPluginSpec(id).host;
    return dshPluginHostSupports(
      host,
      isWindows: Platform.isWindows,
      isAndroid: Platform.isAndroid,
    );
  }

  /// 平台不支持时该显示的平台名（如 `Windows`）；dsh 没装或支持则 null。
  String? unsupportedHostLabel(DshPluginId id) {
    final dsh = _dsh;
    if (dsh == null || !dsh.installed) return null;
    if (supported(id)) return null;
    final host = dshPluginSpec(id).host;
    if (host == DshPluginHost.any) return null;
    return dshPluginHostLabel(host);
  }

  /// 这台机器上能用的内置插件 id 列表（决定设置页要不要列出这些行）。
  List<DshPluginId> supportedIds() => [
    for (final spec in kDshPlugins)
      if (supported(spec.id)) spec.id,
  ];

  /// npm 包名在这台机器上能不能用：内置插件走 [supported]，第三方不限制平台。
  bool supportedPackage(String package) {
    final spec = specForPackage(package);
    if (spec == null) return _dsh != null && _dsh!.installed;
    return supported(spec.id);
  }

  // ---- 统一管理视图（内置推荐 + 已装的第三方）----

  /// 插件管理页的完整清单：先按 npm 包去重，再排好顺序。
  ///
  /// [nameOf] 给内置插件填本地化标题（服务不该依赖 l10n）。
  Future<List<ManagedDshPlugin>> managed({
    String Function(DshPluginSpec spec)? nameOf,
  }) async {
    if (_dsh == null) return const <ManagedDshPlugin>[];
    final bundles = _bundlesOf(await _readManifest());
    final discovered = await _discoverInstalled();
    final seen = <String>{};
    final list = <ManagedDshPlugin>[];

    ManagedDshPlugin build(String package, Map<String, dynamic> meta) {
      final spec = specForPackage(package);
      final busy = spec != null
          ? (_states[spec.id]?.busy ?? false)
          : (_busy[package] ?? false);
      final error = spec != null
          ? _states[spec.id]?.error
          : _errors[package];
      final installed = spec != null
          ? (_states[spec.id]?.installed ?? false)
          : true;
      return ManagedDshPlugin(
        package: package,
        displayName: nameOf == null || spec == null ? null : nameOf(spec),
        version: (meta['version'] ?? '').toString(),
        description: (meta['description'] ?? '').toString(),
        homepage: (meta['homepage'] ?? meta['repository'])?.toString(),
        installed: installed,
        enabled: bundles.contains(package),
        busy: busy,
        // 不在推荐清单里、也没被启用过的，属于用户自己装进来的第三方包。
        recommended: spec != null,
        supportedOnThisHost: supportedPackage(package),
        requiredHost: spec == null ? null : unsupportedHostLabel(spec.id),
        error: error,
      );
    }

    for (final spec in kDshPlugins) {
      final meta = discovered[spec.package];
      list.add(build(spec.package, meta ?? const <String, dynamic>{
        // 没装也列出来（推荐库里点「安装」就装），描述由 UI 补。
      }));
      seen.add(spec.package);
    }
    final extras = discovered.keys.toList()..sort();
    for (final package in extras) {
      if (seen.contains(package)) continue;
      list.add(build(package, discovered[package]!));
    }
    return list;
  }

  /// 装一个 npm 包并挂进 bundles（第三方插件入口，也兜住「开关直接打开」）。
  Future<bool> installPackage(String package) async {
    final dsh = _dsh;
    final name = package.trim();
    final spec = specForPackage(name);
    if (dsh == null || !dsh.installed || name.isEmpty) {
      if (name.isNotEmpty) {
        // 内置插件的错误存在枚举表里，第三方在 _errors 里 —— 别写错表，
        // 否则 UI 拿到的是 null，只剩一句「失败」。
        const reason = 'dsh 还没装好，先装 dsh';
        if (spec != null) {
          _set(spec.id, stateOf(spec.id).copyWith(error: reason));
        } else {
          _setPackage(name, error: reason);
        }
      }
      return false;
    }
    if (spec != null) {
      // 内置插件的「下载」就是启用：先 npm install，再写 bundles。
      final host = unsupportedHostLabel(spec.id);
      if (host != null) {
        _set(spec.id, stateOf(spec.id).copyWith(error: '这个插件只支持 $host'));
        return false;
      }
      return await setEnabled(spec.id, true);
    }
    _setPackage(name, busy: true, clearError: true);
    try {
      await _npmInstall(<String>[name], ignoreScripts: true);
      if (!await _installedPackage(name)) {
        throw Exception('安装后找不到 $name');
      }
      if (!await _declaresDsh(name)) {
        // 装了个普通 npm 包：挂进 bundles 会让 dsh 启动就报
        // "cannot resolve profile bundle"。先挡住，比事后排查便宜。
        throw Exception('$name 不是 dsh 插件（package.json 里没有 dsh 字段）');
      }
      await _writePackageBundle(name, enabled: true);
      if (Platform.isAndroid) {
        await NodeRuntimeService.instance.makeLabReadable(sub: '.dsh');
      }
      await refresh();
      dsh.addLog('已安装 dsh 插件 $name');
      await dsh.restartIfRunning();
      return true;
    } catch (e) {
      _setPackage(name, busy: false, error: '$e');
      dsh.addLog('安装 $name 失败：$e');
      return false;
    } finally {
      _setPackage(name, busy: false);
    }
  }

  /// 启/停任意一个包（按包名，第三方插件走这条路）。
  Future<bool> setPackageEnabled(String package, bool enabled) async {
    final spec = specForPackage(package);
    if (spec != null) return await setEnabled(spec.id, enabled);
    final dsh = _dsh;
    if (dsh == null || !dsh.installed) {
      _setPackage(package, error: 'dsh 还没装好，先装 dsh');
      return false;
    }
    // 没下载过的包直接把开关拨开 = 安装。早先这里只写 bundles，包不在
    // node_modules 里，dsh 下次启动直接 `cannot resolve profile bundle`，
    // 开关还会自己弹回去 —— 用户看到的就是「打不开、也没原因」。
    if (!await _installedPackage(package)) {
      if (!enabled) return true;
      return installPackage(package);
    }
    _setPackage(package, busy: true, clearError: true);
    try {
      await _writePackageBundle(package, enabled: enabled);
      await refresh();
      dsh.addLog('${enabled ? '已启用' : '已停用'} dsh 插件 $package');
      await dsh.restartIfRunning();
      return true;
    } catch (e) {
      _setPackage(package, busy: false, error: '$e');
      return false;
    } finally {
      _setPackage(package, busy: false);
    }
  }

  /// 卸载：退出 bundles，再让 npm 把包删掉。
  Future<bool> uninstallPackage(String package) async {
    final dsh = _dsh;
    if (dsh == null) return false;
    final spec = specForPackage(package);
    if (spec != null) {
      await setEnabled(spec.id, false);
      await _npmUninstall(package);
      // setEnabled 在「平台不支持」时会写一条错误（用户从另一个平台看这份
      // 配置时很常见）；包都删了，别再留着那句红字。
      _states[spec.id] = stateOf(spec.id).copyWith(busy: false, clearError: true);
    } else {
      _setPackage(package, busy: true, clearError: true);
      try {
        await _writePackageBundle(package, enabled: false);
        await _npmUninstall(package);
      } catch (e) {
        _setPackage(package, busy: false, error: '$e');
        return false;
      } finally {
        _setPackage(package, busy: false);
      }
    }
    _errors.remove(package);
    await refresh();
    dsh.addLog('已卸载 dsh 插件 $package');
    await dsh.restartIfRunning();
    return true;
  }

  Future<void> _npmUninstall(String package) async {
    final dsh = _dsh!;
    final android = Platform.isAndroid;
    final node = NodeRuntimeService.instance;
    if (android) {
      // 卸载也要写 node_modules，先放权（同 _npmInstall）。
      await node.makeLabDirWritable(profileDir);
    }
    final process = await startLabProcess(
      executable: android ? await node.nodeBinPath() : 'npm',
      args: [
        if (android) await node.npmCliPath(),
        'uninstall',
        package,
        '--prefix',
        profileDir,
        '--no-save',
        '--no-package-lock',
        '--no-audit',
        '--no-fund',
        '--loglevel=error',
      ],
      workingDirectory: dsh.isDesktop ? profileDir : null,
      environment: android ? await dsh.buildProcessEnv() : null,
      runInShell: !android,
    );
    await process.stdout.drain<void>();
    await process.stderr.drain<void>();
    final code = await process.exitCode;
    if (code != 0) throw Exception('npm 退出码 $code');
  }

  /// 扫一遍 profile 的 node_modules，捞出所有声明了 `dsh` 字段的包。
  ///
  /// dsh 自己发的 `@deepseek-ai/*`（base / web-app / 终端等）是 profile 的
  /// 骨架，不是「插件」，排除掉；`dependencies` 里被顺带装进来的普通 npm 包
  /// 没有 `dsh` 字段，自然也被过滤。
  Future<Map<String, Map<String, dynamic>>> _discoverInstalled() async {
    final out = <String, Map<String, dynamic>>{};
    final root = Directory(p.join(profileDir, 'node_modules'));
    if (profileDir.isEmpty || !await root.exists()) return out;
    final candidates = <String>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('@')) {
        await for (final child in entity.list(followLinks: false)) {
          if (child is Directory) {
            candidates.add('$name/${p.basename(child.path)}');
          }
        }
        continue;
      }
      if (name == '.bin' || name.startsWith('.')) continue;
      candidates.add(name);
    }
    for (final package in candidates) {
      final meta = _readPackageMeta(package);
      if (meta == null) continue;
      if (!_isDshPackage(meta)) continue;
      out[package] = meta;
    }
    return out;
  }

  Map<String, dynamic>? _readPackageMeta(String package) {
    final file = File(
      p.joinAll([
        profileDir,
        'node_modules',
        ...package.split('/'),
        'package.json',
      ]),
    );
    if (!file.existsSync()) return null;
    try {
      final doc = jsonDecode(file.readAsStringSync());
      if (doc is Map<String, dynamic>) return doc;
    } catch (_) {
      // 手写坏的 manifest：当作没有，别把整个列表搞崩。
    }
    return null;
  }

  /// 「这是个 dsh 插件」的判据：package.json 里有 `dsh` 对象。
  /// 官方自己的 bundle 除外 —— 那是 profile 骨架，不该出现在插件列表里。
  bool _isDshPackage(Map<String, dynamic> meta) {
    final name = (meta['name'] ?? '').toString();
    if (name.startsWith('@deepseek-ai/')) return false;
    return meta['dsh'] is Map;
  }

  Future<bool> _installedPackage(String package) async {
    if (profileDir.isEmpty) return false;
    return File(
      p.joinAll([
        profileDir,
        'node_modules',
        ...package.split('/'),
        'package.json',
      ]),
    ).exists();
  }

  Future<bool> _declaresDsh(String package) async {
    final meta = _readPackageMeta(package);
    return meta != null && _isDshPackage(meta);
  }

  Future<void> _writePackageBundle(
    String package, {
    required bool enabled,
  }) async {
    final manifest = await _readManifest();
    final dependencies = manifest['dependencies'];
    final deps = dependencies is Map<String, dynamic>
        ? dependencies
        : <String, dynamic>{};
    if (enabled) {
      deps[package] = '*';
    } else {
      deps.remove(package);
    }
    manifest['dependencies'] = deps;

    final dshMap = manifest['dsh'] is Map<String, dynamic>
        ? manifest['dsh'] as Map<String, dynamic>
        : <String, dynamic>{};
    final profileMap = dshMap['profile'] is Map<String, dynamic>
        ? dshMap['profile'] as Map<String, dynamic>
        : <String, dynamic>{};
    final bundles = _bundlesOf(manifest);
    if (enabled && !bundles.contains(package)) {
      bundles.add(package);
    } else if (!enabled) {
      bundles.remove(package);
    }
    profileMap['bundles'] = bundles;
    dshMap['profile'] = profileMap;
    manifest['dsh'] = dshMap;
    await _writeManifest(manifest);
  }

  String get profileDir {
    final dsh = _dsh;
    if (dsh == null) return '';
    return p.join(dsh.dshHome, 'profiles', 'web');
  }

  /// 读一次现状（幂等）。
  Future<void> init(DshService dsh) async {
    _dsh = dsh;
    if (_loaded) {
      await refresh();
      return;
    }
    _loaded = true;
    await refresh();
  }

  Future<void> refresh() async {
    final dsh = _dsh;
    if (dsh == null) return;
    // 1.1.0 的插件在 apply 里直接读 `ctx.locale`，但没声明 inject，
    // cordis 会在加载时抛 "cannot get property locale without inject"，
    // 整条 bundle 变成「1 entry did not activate」。装好后补一行声明。
    for (final spec in kDshPlugins) {
      if (await _installed(spec)) {
        if (spec.id == DshPluginId.messageEdit) await _patchMessageEdit();
        if (spec.id == DshPluginId.computerUse) await _patchComputerUse();
      }
    }
    final manifest = await _readManifest();
    final bundles = _bundlesOf(manifest);
    for (final spec in kDshPlugins) {
      final installed = await _installed(spec);
      _states[spec.id] = DshPluginState(
        installed: installed,
        enabled: bundles.contains(spec.package),
        busy: _states[spec.id]?.busy ?? false,
        error: _states[spec.id]?.error,
      );
    }
    notifyListeners();
  }

  /// 打开 / 关闭一个插件。打开时若没装会先 npm install。
  Future<bool> setEnabled(DshPluginId id, bool enabled) async {
    final dsh = _dsh;
    final host = unsupportedHostLabel(id);
    // 关掉永远允许：换个平台看同一份 dsh 配置时，用户得能把它摘掉。
    if (dsh == null || !dsh.installed || (host != null && enabled)) {
      _set(
        id,
        stateOf(id).copyWith(
          busy: false,
          error: host != null ? '这个插件只支持 $host' : 'dsh 还没装好，先装 dsh',
        ),
      );
      return false;
    }
    final spec = dshPluginSpec(id);
    final current = stateOf(id);
    if (current.busy) return false;
    _set(id, current.copyWith(busy: true, clearError: true));
    try {
      if (enabled) {
        if (!await _installed(spec)) {
          await _install(spec);
        }
        if (spec.id == DshPluginId.messageEdit) await _patchMessageEdit();
        if (spec.id == DshPluginId.computerUse) await _patchComputerUse();
        await _repairComputerUseNative(spec);
        await _writeBundle(spec, enabled: true);
      } else {
        // 只摘 bundles，保留已下载的包；下次打开不用重新下载。
        await _writeBundle(spec, enabled: false);
      }
      await refresh();
      dsh.addLog(
        '${enabled ? '已启用' : '已停用'} dsh 插件 ${spec.package}',
      );
      // 插件层在启动时装载：运行中的 dsh 要重启一次才生效。
      await dsh.restartIfRunning();
      return true;
    } catch (e) {
      _set(
        id,
        stateOf(id).copyWith(
          busy: false,
          error: '$e',
        ),
      );
      dsh.addLog('dsh 插件 ${spec.package} 操作失败：$e');
      return false;
    } finally {
      _set(id, stateOf(id).copyWith(busy: false));
    }
  }

  void _set(DshPluginId id, DshPluginState state) {
    _states[id] = state;
    notifyListeners();
  }

  Future<bool> _installed(DshPluginSpec spec) async {
    final dir = profileDir;
    if (dir.isEmpty) return false;
    final pkg = File(
      p.joinAll([
        dir,
        'node_modules',
        ...spec.package.split('/'),
        'package.json',
      ]),
    );
    return pkg.exists();
  }

  /// 给 `@xt765/dsh-message-edit` 的 host `apply` 打一个兼容补丁。
  ///
  /// 插件直接读 `ctx.locale`，但 host 进程里没有 `locale` 服务；cordis 4
  /// 对未声明 inject 的服务访问直接抛错，导致整条 bundle 不激活
  /// （DSH 日志：`message-edit (...) Error: cannot get property "locale"
  /// without inject`）。这里把访问包进 try/catch：有 locale 服务就照旧
  /// 注册文案，没有就跳过 —— 客户端 bundle 自带中英文案，不影响按钮。
  Future<void> _patchMessageEdit() async {
    final file = File(
      p.joinAll([
        profileDir,
        'node_modules',
        '@xt765',
        'dsh-message-edit',
        'lib',
        'index.js',
      ]),
    );
    if (!await file.exists()) return;
    try {
      final source = await file.readAsString();
      if (source.contains('localeService')) return;
      const oldGuard =
          "  if (ctx?.locale && typeof ctx.locale.register === 'function') {";
      const newGuard =
          "  let localeService = null;\n"
          "  try { localeService = ctx?.locale; } catch { /* no host locale service */ }\n"
          "  if (localeService && typeof localeService.register === 'function') {";
      const oldRegister =
          "      ctx.locale.register('plugin-config.message-edit', {";
      const newRegister =
          "      localeService.register('plugin-config.message-edit', {";
      if (!source.contains(oldGuard) || !source.contains(oldRegister)) {
        return;
      }
      final patched = source
          .replaceFirst(oldGuard, newGuard)
          .replaceFirst(oldRegister, newRegister);
      await file.writeAsString(patched, flush: true);
      _dsh?.addLog('已给 dsh-message-edit 补 host locale 兼容补丁');
    } catch (e) {
      _dsh?.addLog('补 dsh-message-edit 兼容补丁失败：$e');
    }
  }

  /// `dsh-computer-use-mode` 的 preset 里写了 `{{cwd}}`，但 0.2.1-rc.2 的
  /// 模板只注册了 provider / model 两个变量 —— 一开轮就
  /// `unknown prompt variable "{{cwd}}" in section "deployment:persona-suffix"`，
  /// 这一轮直接失败，computer 工具一次都调不到。把占位符换成字面描述。
  Future<void> _patchComputerUse() async {
    final patchFile = File(
      p.joinAll([
        profileDir,
        'node_modules',
        'dsh-computer-use-mode',
        'cordis.patch.yml',
      ]),
    );
    if (await patchFile.exists()) {
      try {
        final source = await patchFile.readAsString();
        if (source.contains('{{cwd}}')) {
          await patchFile.writeAsString(
            source.replaceAll('{{cwd}}', 'the session workspace'),
            flush: true,
          );
          _dsh?.addLog('已去掉 dsh-computer-use-mode 里未注册的 {{cwd}} 变量');
        }
      } catch (e) {
        _dsh?.addLog('修 dsh-computer-use-mode 的 {{cwd}} 失败：$e');
      }
    }

    // 截图结果里 `changed` 在第一次截某个区域时是显式 undefined；DSH 的
    // lossless-JSON 校验（util-values 的 snapshotJsonValue）遇到 undefined
    // 直接判整份 tool output 非法 —— 表现就是
    // `invalid output: value is not lossless JSON`，图也送不进模型。
    // 首次没有对比基线时干脆不写这个键。
    final jsFile = File(
      p.joinAll([
        profileDir,
        'node_modules',
        'dsh-computer-use-mode',
        'lib',
        'index.js',
      ]),
    );
    if (!await jsFile.exists()) return;
    try {
      final source = await jsFile.readAsString();
      final line = RegExp(
        r'shot\.meta\.changed\s*=\s*before === undefined \? undefined : before !== shot\.meta\.signature;',
      );
      if (!line.hasMatch(source)) return;
      await jsFile.writeAsString(
        source.replaceFirst(
          line,
          'if (before === undefined) { delete shot.meta.changed; } '
              'else { shot.meta.changed = before !== shot.meta.signature; }',
        ),
        flush: true,
      );
      _dsh?.addLog('已修 dsh-computer-use-mode 截图结果的 undefined（lossless JSON）');
    } catch (e) {
      _dsh?.addLog('修 dsh-computer-use-mode 截图结果失败：$e');
    }
  }

  /// koffi 是 `dsh-computer-use-mode` 的原生依赖（截屏 + 鼠标键盘合成），
  /// 只随桌面版安装包分发，npm 装的 dsh 里没有 —— 缺了它 `src/win32.cjs`
  /// 的 `requireFromInstall('koffi', ...)` 会失败，模式能选但 computer /
  /// computer_batch 两个工具不注册。loader 会回退到插件自己的
  /// `<plugin>/../node_modules`（正是 profile 的 node_modules），补到这里就行。
  ///
  /// **必须和插件同一条 npm 命令装**：分开装时，第二条 `npm install koffi`
  /// 会把不在 package.json 里的插件当成无关包 prune 掉（实测
  /// "added 2 packages, and removed 1 package"），DSH 随即报
  /// `cannot resolve profile bundle "dsh-computer-use-mode"`。
  bool _needsKoffi(DshPluginSpec spec) => spec.id == DshPluginId.computerUse;

  /// 插件已装但 koffi 被别的 npm 操作清掉了：整包重装一次（还是同一条命令）。
  Future<void> _repairComputerUseNative(DshPluginSpec spec) async {
    if (!_needsKoffi(spec)) return;
    final koffi = Directory(p.joinAll([profileDir, 'node_modules', 'koffi']));
    if (await koffi.exists()) return;
    await _npmInstall(<String>[spec.package, 'koffi'], ignoreScripts: false);
    _dsh?.addLog('已给电脑操作模式补装原生依赖 koffi');
  }

  /// `npm install --no-save` 到 profile 目录（不写 package.json / lock）。
  Future<void> _install(DshPluginSpec spec) async {
    await _npmInstall(
      <String>[
        spec.package,
        if (_needsKoffi(spec)) 'koffi',
      ],
      // koffi 的预编译二进制靠它自己的 install 脚本，不能禁。
      ignoreScripts: !_needsKoffi(spec),
    );
    if (!await _installed(spec)) {
      throw Exception('安装后找不到 ${spec.package}');
    }
    if (Platform.isAndroid) {
      // profile 里混着应用写的 package.json（0600）和 shell 写的 node_modules，
      // dsh 是 shell 身份，得整棵放权；放权完凭据文件会被收回去。
      await NodeRuntimeService.instance.makeLabReadable(sub: '.dsh');
    }
  }

  Future<void> _npmInstall(
    List<String> packages, {
    bool ignoreScripts = true,
  }) async {
    final dsh = _dsh!;
    final dir = Directory(profileDir);
    await dir.create(recursive: true);
    // profile 还没初始化时先放一份和 dsh 模板一致的 manifest，bundles 里
    // 保留 dsh 自带的两个 bundle。
    if (!await File(p.join(profileDir, 'package.json')).exists()) {
      await _writeManifest(_defaultManifest());
    }
    final node = NodeRuntimeService.instance;
    final android = Platform.isAndroid;
    if (android) {
      // npm 是 Shizuku 的 shell 身份，profile 目录却是应用建的（0700）：
      // 不放权的话 `mkdir node_modules` 直接 EACCES，npm 以 243 退出 ——
      // 表现就是「下载失败」，而且日志里只有一句 npm 退出码。
      await node.makeLabDirWritable(profileDir);
    }
    final process = await startLabProcess(
      // Android：暂存 bin 里的 `npm` 是 termux 包自带的脚本，shebang 指向
      // /data/data/com.termux/...（设备上没这个目录，直接 ENOENT），只能
      // 让 node 显式跑 npm-cli.js。
      executable: android ? await node.nodeBinPath() : 'npm',
      args: [
        if (android) await node.npmCliPath(),
        'install',
        ...packages,
        '--prefix',
        profileDir,
        '--no-save',
        '--no-package-lock',
        // koffi 的预编译二进制靠它自己的 install 脚本，不能禁。
        if (ignoreScripts) '--ignore-scripts',
        '--no-audit',
        '--no-fund',
        '--loglevel=error',
      ],
      workingDirectory: dsh.isDesktop ? profileDir : null,
      environment: android ? await dsh.buildProcessEnv() : null,
      runInShell: !android,
    );
    final tail = <String>[];
    void collect(String line) {
      final text = line.trimRight();
      if (text.isEmpty) return;
      tail.add(text);
      if (tail.length > 20) tail.removeAt(0);
    }

    final out = process.stdout.listen(collect);
    final err = process.stderr.listen(collect);
    final code = await process.exitCode.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        unawaited(process.kill());
        return -1;
      },
    );
    await out.cancel();
    await err.cancel();
    if (code != 0) {
      throw Exception(
        tail.isEmpty ? 'npm 退出码 $code' : 'npm 退出码 $code：${tail.last}',
      );
    }
  }

  Future<Map<String, dynamic>> _readManifest() async {
    final file = File(p.join(profileDir, 'package.json'));
    if (!await file.exists()) return _defaultManifest();
    try {
      final raw = await file.readAsString();
      final doc = jsonDecode(raw);
      if (doc is Map<String, dynamic>) return doc;
    } catch (_) {}
    return _defaultManifest();
  }

  Map<String, dynamic> _defaultManifest() => <String, dynamic>{
    'name': 'dsh-profile-web',
    'private': true,
    'dependencies': <String, dynamic>{},
    'dsh': <String, dynamic>{
      'profile': <String, dynamic>{
        'bundles': <String>[
          '@deepseek-ai/dsh-base',
          '@deepseek-ai/dsh-web-app',
        ],
      },
    },
  };

  List<String> _bundlesOf(Map<String, dynamic> manifest) {
    final dsh = manifest['dsh'];
    final profile = dsh is Map ? dsh['profile'] : null;
    final bundles = profile is Map ? profile['bundles'] : null;
    if (bundles is! List) return <String>[];
    return [
      for (final item in bundles)
        if (item is String && item.trim().isNotEmpty) item.trim(),
    ];
  }

  Future<void> _writeBundle(DshPluginSpec spec, {required bool enabled}) async {
    final manifest = await _readManifest();
    final dependencies = manifest['dependencies'];
    final deps = dependencies is Map<String, dynamic>
        ? dependencies
        : <String, dynamic>{};
    if (enabled && !deps.containsKey(spec.package)) {
      deps[spec.package] = '*';
    }
    manifest['dependencies'] = deps;

    final dsh = manifest['dsh'];
    final dshMap = dsh is Map<String, dynamic>
        ? dsh
        : <String, dynamic>{};
    final profile = dshMap['profile'];
    final profileMap = profile is Map<String, dynamic>
        ? profile
        : <String, dynamic>{};
    final bundles = _bundlesOf(manifest);
    if (enabled && !bundles.contains(spec.package)) {
      bundles.add(spec.package);
    } else if (!enabled) {
      bundles.remove(spec.package);
    }
    profileMap['bundles'] = bundles;
    dshMap['profile'] = profileMap;
    manifest['dsh'] = dshMap;
    await _writeManifest(manifest);
  }

  /// 手写 JSON（不用 `WriteAsString` 的默认编码之外的任何 BOM）：dsh-host
  /// 用裸 `JSON.parse()` 读这份 manifest，文件头有 BOM 会直接启动失败。
  Future<void> _writeManifest(Map<String, dynamic> manifest) async {
    final file = File(p.join(profileDir, 'package.json'));
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(manifest)}\n', flush: true);
  }
}
