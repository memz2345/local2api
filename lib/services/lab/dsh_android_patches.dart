// lib/services/lab/dsh_android_patches.dart
//
// dsh 的 npm 干净树在 Android 上缺的两块原生能力，用纯 JS 补丁顶上。
//
// 为什么要在装完之后改文件，而不是像 cordis.patch.yml 那样只配插件：
//   这两处都是 **JS 侧 require 原生 addon**，不是插件层的开关 ——
//   配置改不到它们。参考实现（deepseek-harness-android-app，MIT）走的是同一条路：
//   打包时把 overlay 覆盖进 node_modules。我们按需在装完后写回去。
//
// 只在 Android 上应用，且 npm 重装（install / 安装依赖）之后要重打一次。
// 每个文件首次改写前留一份 `.l2a.orig`，卸载时随目录一起删掉。

import 'dart:io';

import 'package:path/path.dart' as p;

/// 补丁标记：出现在文件里就认为已经打过（幂等 + 认出我们自己改的）。
const String kDshAndroidFilePatchMarker = 'local2api-android-shim';

/// node_modules 相对路径 -> 补丁全文。
const Map<String, String> kDshAndroidFilePatches = {
  'node-addon-require-builtin/lib/index.js': _narbShim,
  '@deepseek-ai/node-addon-system/lib/flock.js': _flockShim,
  // glob/grep 工具固定 spawn `@vscode/ripgrep` 的打包二进制，Android 没有
  // 对应平台的 optionalDependency；这里改成「解析不到就走 PATH 里的 rg」
  // （rg 由 Node 运行时一并安装，暂存后在 <stage>/bin 里）。
  '@vscode/ripgrep/lib/index.js': _rgShim,
  // dsh 的终端（`terminal-bash`）走 node-pty，而它只有 darwin/linux/win32
  // 的 prebuild；Android 上没有产物也没有编译工具链。退化成管道实现。
  'node-pty/lib/index.js': _nodePtyShim,
};

/// 定点替换补丁：整文件替换装不下的场景（几千行的上游模块）用这个 ——
/// node_modules 相对路径 -> (原文锚点, 替换后文本) 列表。
/// 幂等：`to` 片段已存在就跳过；`from` 找不到视为上游变了，跳过并交给日志。
/// 会话持久化在 FUSE（/storage/emulated）上建硬链接必被拒（EACCES），
/// 两处 link 都要有 rename 回退，否则消息发出后落盘失败、回合卡死。
const Map<String, List<(String, String)>> kDshAndroidReplacements = {
  // 「用别的应用打开这个文件」：上游只认 darwin/win32/linux(WSL)，Android
  // 直接 return false + throw，Web 界面就只剩一句「没有可用的文件打开工具」。
  '@deepseek-ai/dsh-host-apiproxy/lib/index.js': [
    (_openDispatcherFrom, _openDispatcherTo),
    (_openCanFrom, _openCanTo),
    (_openHelpersFrom, _openHelpersTo),
  ],
  '@deepseek-ai/dsh-session-persistence-jsonl/lib/index.js': [
    (_spImportFrom, _spImportTo),
    (_spDefaultFsFrom, _spDefaultFsTo),
    (_spPublishFrom, _spPublishTo),
    (_spMaterializeFrom, _spMaterializeTo),
  ],
  '@deepseek-ai/dsh-attachment-local/lib/index.js': [
    (_attImportFrom, _attImportTo),
    (_attChmodFrom, _attChmodTo),
    (_attAliasLinkFrom, _attAliasLinkTo),
    (_attStagedLinkFrom, _attStagedLinkTo),
    (_attChmodStagedFrom, _attChmodStagedTo),
    (_attChmodAliasFrom, _attChmodAliasTo),
  ],
  '@deepseek-ai/dsh-fs-local/lib/index.js': [
    (_fslLinkFrom, _fslLinkTo),
  ],
};

/// 哪些文件需要打补丁（UI 展示用）。
List<String> get kDshAndroidPatchFiles => [
      ...kDshAndroidFilePatches.keys,
      ...kDshAndroidReplacements.keys,
    ];

/// 把补丁写进 [installDir] 下的 npm 树。
///
/// 返回真正被改写的相对路径（已打过 / 原文件不存在的都跳过）。
Future<List<String>> applyDshAndroidPatches(String installDir) async {
  final root = p.join(installDir, 'node_modules');
  final applied = <String>[];
  for (final entry in kDshAndroidFilePatches.entries) {
    final file = File(p.join(root, entry.key));
    if (!await file.exists()) continue;
    final source = await file.readAsString();
    if (source.contains(kDshAndroidFilePatchMarker)) continue;
    final backup = File('${file.path}.l2a.orig');
    if (!await backup.exists()) {
      await file.copy(backup.path);
    }
    await file.writeAsString(entry.value, flush: true);
    applied.add(entry.key);
  }
  for (final entry in kDshAndroidReplacements.entries) {
    final file = File(p.join(root, entry.key));
    if (!await file.exists()) continue;
    var source = await file.readAsString();
    final backup = File('${file.path}.l2a.orig');
    if (!await backup.exists()) {
      await file.copy(backup.path);
    }
    var changed = false;
    for (final (from, to) in entry.value) {
      if (source.contains(to)) continue; // 幂等
      if (!source.contains(from)) continue; // 上游变了，别硬改
      source = source.replaceFirst(from, to);
      changed = true;
    }
    if (changed) {
      await file.writeAsString(source, flush: true);
      applied.add(entry.key);
    }
  }
  return applied;
}

/// 撤掉补丁：把 `.l2a.orig` 还原回去（没有原文件就保持现状）。
Future<List<String>> revertDshAndroidPatches(String installDir) async {
  final root = p.join(installDir, 'node_modules');
  final restored = <String>[];
  for (final relative in [
    ...kDshAndroidFilePatches.keys,
    ...kDshAndroidReplacements.keys,
  ]) {
    final file = File(p.join(root, relative));
    final backup = File('${file.path}.l2a.orig');
    if (!await file.exists() || !await backup.exists()) continue;
    final current = await file.readAsString();
    if (!current.contains(kDshAndroidFilePatchMarker)) continue;
    await file.writeAsString(await backup.readAsString(), flush: true);
    restored.add(relative);
  }
  return restored;
}

/// `node-addon-require-builtin`：上游按 `platform-arch-abi` 找 `.node`，
/// Android 没有发布物；而 `dsh-app-boot` 的 internalModules() 是无 try/catch
/// 的硬依赖，加载失败连 web profile 都起不来。
///
/// 回退实现靠启动时的 `--expose-internals`：那个条件下
/// `require('internal/modules/...')` 直接可用，拿到的就是同一批内部接口。
/// 原生绑定仍然优先，桌面/服务器行为不变。
const String _narbShim = r'''
"use strict";
/* local2api-android-shim: v1
 * node-addon-require-builtin 的上游实现要按 platform-arch-abi 找 `.node`，
 * Android（process.platform === 'android'）没有任何发布物，而 dsh-app-boot 的
 * internalModules() 是无 try/catch 的硬依赖 —— 加载失败整个引擎起不来。
 * 回退：App 启动 node 时带 --expose-internals，此时 require('internal/...')
 * 直接可用。原生绑定仍优先，桌面/服务器行为不变。
 * 思路来自 deepseek-harness-android-app（MIT）的同名补丁。
 */
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.requireBuiltin = requireBuiltin;
exports.isAllowedInternalId = isAllowedInternalId;
exports.getBindingInfo = getBindingInfo;
const node_path_1 = __importDefault(require("node:path"));
const node_module_1 = require("node:module");
const requireInternal = (0, node_module_1.createRequire)(__filename);
let native = null;
let nativeFailure = null;
try {
    const { createEntryApi } = require('node-addon-native-custom-loader');
    native = createEntryApi(node_path_1.default.resolve(__dirname, '..'));
}
catch (error) {
    nativeFailure = error;
}
function requireBuiltin(moduleId) {
    if (native)
        return native.requireBuiltin(moduleId);
    return requireInternal(moduleId);
}
function isAllowedInternalId(moduleId) {
    if (native)
        return native.isAllowedInternalId(moduleId);
    // 回退路径下由 Node 自身的 --expose-internals 门禁决定可访问范围。
    return true;
}
function getBindingInfo() {
    if (native)
        return native.getBindingInfo();
    return {
        binding: 'js-fallback',
        reason: nativeFailure
            ? String((nativeFailure && nativeFailure.message) || nativeFailure)
            : 'native binding unavailable',
    };
}
exports.default = {
    requireBuiltin,
    isAllowedInternalId,
    getBindingInfo,
};
''';

/// `@deepseek-ai/node-addon-system/lib/flock.js`：会话写入路径要拿文件锁，
/// 上游在非 linux/darwin 直接抛 `ERR_FLOCK_UNSUPPORTED_PLATFORM`，
/// 而 `dsh-session-persistence-jsonl` 只把 EAGAIN/EWOULDBLOCK 当「已被占用」，
/// 这个错误会一路顶穿整条会话写入链（表现就是提示词被收下但永远不出回合）。
///
/// 退化成空锁：`tryLock` 立即回调 0（=获取成功）。代价是跨进程互斥失效，
/// 而本应用同时只跑一个引擎进程，可以接受。
const String _flockShim = r'''
/* local2api-android-shim: v1
 * 上游只在 linux/darwin 下解析平台原生包；Android 没有产物，require.resolve
 * 直接 MODULE_NOT_FOUND，错误会顶穿会话写入链。这里退化成空锁。
 * 思路来自 deepseek-harness-android-app（MIT）的同名补丁。
 */
/** Lazy POSIX flock entry; importing it does not load a native addon. */
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { getSystemErrorName } from 'node:util';
let binding;
function loadBinding() {
    if (binding)
        return binding;
    const { platform, arch } = process;
    if (platform !== 'linux' && platform !== 'darwin') {
        return (binding = noopBinding(`flock is not supported on ${platform}-${arch}`));
    }
    let filename = 'system.node';
    if (platform === 'linux') {
        // Node's report types omit the libc field supplied by Linux reports.
        const report = process.report.getReport();
        filename = join(report.header.glibcVersionRuntime ? 'glibc' : 'musl', filename);
    }
    try {
        const require = createRequire(import.meta.url);
        const manifest = require.resolve(`@deepseek-ai/node-addon-system-${platform}-${arch}/package.json`);
        binding = require(join(dirname(manifest), 'bin', filename));
    }
    catch (error) {
        return (binding = noopBinding(error?.message));
    }
    return binding;
}
/** 空锁：tryLock 一律立即回调 0（= 获取成功），语义上等价于「无锁」。 */
function noopBinding(reason) {
    if (process.env.DSH_FLOCK_DEBUG === '1') {
        console.warn(`[flock] native binding unavailable, falling back to no-op lock: ${reason}`);
    }
    return { tryLock: (_fd, callback) => callback(0) };
}
export async function tryLockExclusive(fd) {
    const errno = await new Promise((resolve) => {
        loadBinding().tryLock(fd, resolve);
    });
    if (errno === 0)
        return;
    const code = getSystemErrorName(-errno);
    throw Object.assign(new Error(`${code}: flock failed`), {
        code,
        errno,
        syscall: 'flock',
    });
}
''';

// ---- rg 工具（@vscode/ripgrep 的平台包在 Android 上不存在）----

/// `@vscode/ripgrep`：glob/grep 工具固定 spawn 这个模块导出的 `rgPath`。
/// 上游按 `@vscode/ripgrep-${platform}-${arch}` 找打包二进制，Android 上
/// 必然解析失败（"ripgrep launch failed"）。改成「解析不到就沿 PATH 找
/// 可执行的 rg」——rg 由 Node 运行时一并装好并暂存到 `<stage>/bin`。
const String _rgShim = r'''
import { createRequire } from 'node:module';
import { accessSync, constants } from 'node:fs';

const require = createRequire(import.meta.url);

const arch = process.env.npm_config_arch || process.arch;
const binaryName = process.platform === 'win32' ? 'rg.exe' : 'rg';
const platformPkg = `@vscode/ripgrep-${process.platform}-${arch}`;

// local2api-android-shim: /storage/emulated is mounted noexec, so a packaged
// binary living beside this module can never be spawned on Android. Fall back
// to an `rg` that is executable and reachable through PATH.
function rgFromPath() {
    const sep = process.platform === 'win32' ? ';' : ':';
    for (const dir of (process.env.PATH || '').split(sep)) {
        if (!dir) continue;
        const candidate = `${dir}/${binaryName}`;
        try {
            accessSync(candidate, constants.X_OK);
            return candidate;
        } catch {
            // not here, keep looking
        }
    }
    return undefined;
}

let resolved;
try {
    resolved = require.resolve(`${platformPkg}/bin/${binaryName}`);
} catch {
    resolved = rgFromPath();
    if (!resolved) {
        throw new Error(
            `Could not find ${platformPkg}. ` +
            `Ensure optionalDependencies are installed for this platform (${process.platform}-${arch}).`
        );
    }
}

export const rgPath = resolved;
''';

// ---- 「用别的应用打开文件」（dsh-host-apiproxy 的原生打开器）----
//
// 上游 `canOpenNativePath()` 只认 darwin / win32 / linux(+WSL)，其它平台直接
// `return false`；真去开的时候 `openNativePathWithIntent()` 又只列了那三条分支，
// 落到最后一行 `throw new Error("native path opener is unsupported on android")`。
// 前者让 `host.describe` 回 `canOpenPath: false`，于是 Web 界面的产出文件行
// （"在文件夹中显示"）只能给出一句「没有可用的文件打开工具」。
//
// Android 上没有 xdg-open，但 node 进程是 Shizuku 给的 shell 身份，`am start`
// 可用 —— 这是唯一的通路。还有个附注：别的应用读不到我们工作区里的文件
// （`/data/local/tmp`、`/sdcard/Android/data/<pkg>`），所以先把它落到共享存储。
//
// 只能整段替换：这两处是 JS 侧的平台分支，不是插件层的开关，配置改不到。
const String _openCanFrom = 'function canOpenNativePath(internals = {}) {\n'
    '\tconst platform = internals.platform ?? process.platform;\n'
    '\tif (platform === "darwin" || platform === "win32") return true;\n'
    '\tif (platform !== "linux") return false;';
const String _openCanTo = 'function canOpenNativePath(internals = {}) {\n'
    '\tconst platform = internals.platform ?? process.platform;\n'
    '\tif (platform === "darwin" || platform === "win32") return true;\n'
    '\t// local2api-android-shim: `am start` is reachable from the Shizuku shell.\n'
    '\tif (platform === "android") return true;\n'
    '\tif (platform !== "linux") return false;';

const String _openDispatcherFrom =
    '\tif (platform === "linux") {\n'
    '\t\tif (wsl) {\n'
    '\t\t\tawait openWslPath(path, signal, run);\n'
    '\t\t\treturn;\n'
    '\t\t}\n'
    '\t\tawait run("xdg-open", [path], signal);\n'
    '\t\treturn;\n'
    '\t}\n'
    '\tthrow new Error(`native path opener is unsupported on \${platform}`);';
const String _openDispatcherTo =
    '\tif (platform === "linux") {\n'
    '\t\tif (wsl) {\n'
    '\t\t\tawait openWslPath(path, signal, run);\n'
    '\t\t\treturn;\n'
    '\t\t}\n'
    '\t\tawait run("xdg-open", [path], signal);\n'
    '\t\treturn;\n'
    '\t}\n'
    '\t// local2api-android-shim: hand the path to whatever app handles its type.\n'
    '\tif (platform === "android") {\n'
    '\t\tawait openAndroidPath(path, signal, intent, run);\n'
    '\t\treturn;\n'
    '\t}\n'
    '\tthrow new Error(`native path opener is unsupported on \${platform}`);';

/// 在 `openNativePathWithIntent` 前面插入 Android 打开器（锚点是它的文档注释）。
const String _openHelpersFrom =
    '/** Dispatch one shell-free platform command for the requested open intent. */\n'
    'async function openNativePathWithIntent(path, signal, intent, internals = {}) {';
const String _openHelpersTo = r'''
/* local2api-android-shim: v1
 * Android has no xdg-open, but the node process runs with the Shizuku shell
 * identity, so `am start -a android.intent.action.VIEW` is the one hand-off
 * that reaches a user-visible viewer.
 *
 * Second wrinkle: every other app reads neither `/data/local/tmp` nor
 * `<app>/Android/data`, so a workspace file has to land in shared storage
 * before anyone else can open it. We do not move the original.
 */
const ANDROID_SHARE_DIR = "/sdcard/Download/local2api";
const ANDROID_MIME_TYPES = {
	".txt": "text/plain", ".md": "text/markdown", ".csv": "text/csv",
	".json": "application/json", ".yaml": "text/yaml", ".yml": "text/yaml",
	".html": "text/html", ".htm": "text/html", ".pdf": "application/pdf",
	".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
	".gif": "image/gif", ".webp": "image/webp", ".svg": "image/svg+xml",
	".mp4": "video/mp4", ".mp3": "audio/mpeg", ".wav": "audio/wav",
	".zip": "application/zip", ".apk": "application/vnd.android.package-archive"
};
function androidFileName(path) {
	const segments = path.split("/");
	return segments[segments.length - 1] || "file";
}
/** file:// URI with every path segment percent-encoded (`#`, spaces, CJK…). */
function androidFileUri(path) {
	return "file://" + path.split("/").map((segment) => encodeURIComponent(segment)).join("/");
}
function androidMimeType(path, intent) {
	if (intent === "text-editor") return "text/plain";
	return ANDROID_MIME_TYPES[extname(path).toLowerCase()] ?? "*/*";
}
/** Publish a workspace path into shared storage so other apps can read it. */
async function androidShareablePath(path, signal, run) {
	if (path.startsWith("/sdcard/") || path.startsWith("/storage/emulated/")) return path;
	const target = `${ANDROID_SHARE_DIR}/${androidFileName(path)}`;
	await run("mkdir", ["-p", ANDROID_SHARE_DIR], signal).catch(() => {});
	await run("cp", [path, target], signal);
	await run("chmod", ["644", target], signal).catch(() => {});
	return target;
}
async function openAndroidPath(path, signal, intent, run) {
	const target = await androidShareablePath(path, signal, run);
	signal.throwIfAborted();
	const args = [
		"start",
		"-a", "android.intent.action.VIEW",
		"-d", androidFileUri(target),
		"-t", androidMimeType(target, intent),
		"--grant-read-uri-permission"
	];
	try {
		await run("am", args, signal);
	} catch (error) {
		await run("/system/bin/am", args, signal);
	}
}
/** Dispatch one shell-free platform command for the requested open intent. */
async function openNativePathWithIntent(path, signal, intent, internals = {}) {''';

// ---- node-pty（终端后端的 PTY 换成管道）----
//
// `dsh-terminal-bash` → `ctx.subprocess.spawnTerminal` → `dsh-subprocess-local`
// → `import * as nodePty from "node-pty"`，而它在模块顶层就
// `loadNativeModule('pty')`：`prebuilds/` 只有 darwin/linux/win32 六种，Android
// 既没有产物也没有 node-gyp/工具链，整个 `subprocess-local` 行加载失败。
//
// dsh 实际用到的 PTY 面很窄：`spawn()` 出来的句柄只要 `pid`、`onData()`、
// `onExit()`、`write()`、`kill()`（见 `LocalTerminalHandle`）。用
// `child_process` 的管道顶上：失去的是作业控制、窗口尺寸（resize 退化成记
// 数字）和 TTY 检测，命令执行、输出流与我方 kill 都照旧。
const String _nodePtyShim = r'''
"use strict";
/* local2api-android-shim: v1
 * node-pty loads a platform-arch-abi native binding and ships prebuilds for
 * darwin/linux/win32 only. Android has no artefact and no toolchain, so the
 * whole `dsh-subprocess-local` row — and with it every terminal consumer —
 * never activates ("终端不可用").
 *
 * What dsh actually touches on a pty handle is narrow (see LocalTerminalHandle
 * and spawnTerminal): `pid`, `onData`, `onExit`, `write`, `kill`. Everything
 * else here exists to keep the module shape recognisable. Lost relative to a
 * real pty: job control, window-size propagation, isatty detection. Command
 * execution, output streaming, and signalling still work.
 */
const { spawn: spawnProcess } = require("node:child_process");

var PipeTerminal = class {
	_child = null;
	pid = 0;
	cols = 80;
	rows = 24;
	process = "";
	_exited = false;
	_dataListeners = new Set();
	_exitListeners = new Set();
	constructor(file, args, options) {
		const opt = options || {};
		if (Number.isFinite(opt.cols)) this.cols = opt.cols;
		if (Number.isFinite(opt.rows)) this.rows = opt.rows;
		this.process = String(file || "");
		const child = spawnProcess(file, args || [], {
			cwd: opt.cwd || undefined,
			env: opt.env || process.env,
			// Detached puts the shell in its own process group so signalling
			// reaches the whole session, which is what the callers expect.
			detached: true,
			stdio: ["pipe", "pipe", "pipe"],
			windowsHide: true
		});
		this._child = child;
		this.pid = child.pid || 0;
		this._pump(child.stdout);
		this._pump(child.stderr);
		child.on("error", (error) => {
			this._emitData(`\r\n${(error && error.message) || String(error)}\r\n`);
			this._settle(1, undefined);
		});
		child.on("exit", (code, signal) => this._settle(code, signal));
		child.on("close", (code, signal) => this._settle(code, signal));
	}
	_pump(stream) {
		if (!stream) return;
		stream.setEncoding("utf8");
		stream.on("data", (chunk) => this._emitData(chunk));
	}
	_emitData(chunk) {
		for (const listener of this._dataListeners) {
			try {
				listener(chunk);
			} catch (_listenerThrew) {}
		}
	}
	_settle(code, signal) {
		if (this._exited) return;
		this._exited = true;
		// dsh reads `{ exitCode, signal }` and nulls exitCode when `signal` is a
		// non-zero *number*; a node signal name would be misread, so drop it.
		const outcome = { exitCode: code === null || code === undefined ? 1 : code, signal: undefined };
		for (const listener of this._exitListeners) {
			try {
				listener(outcome);
			} catch (_listenerThrew) {}
		}
	}
	onData(listener) {
		this._dataListeners.add(listener);
		return { dispose: () => this._dataListeners.delete(listener) };
	}
	onExit(listener) {
		this._exitListeners.add(listener);
		return { dispose: () => this._exitListeners.delete(listener) };
	}
	write(data) {
		const stdin = this._child && this._child.stdin;
		if (!stdin || stdin.destroyed || stdin.writableEnded) return;
		const text = typeof data === "string" ? data : Buffer.from(data).toString("utf8");
		try {
			stdin.write(text);
		} catch (_stdinGone) {}
	}
	/** No tty to reconfigure: record the size and move on. */
	resize(cols, rows) {
		if (Number.isFinite(cols) && cols > 0) this.cols = cols;
		if (Number.isFinite(rows) && rows > 0) this.rows = rows;
	}
	kill(signal) {
		if (!this._child || this._exited) return;
		const sent = signal || "SIGTERM";
		if (this.pid > 0) {
			try {
				process.kill(-this.pid, sent);
				return;
			} catch (_groupGone) {}
		}
		try {
			this._child.kill(sent);
		} catch (_alreadyGone) {}
	}
	pause() {
		const stdout = this._child && this._child.stdout;
		if (stdout) stdout.pause();
	}
	resume() {
		const stdout = this._child && this._child.stdout;
		if (stdout) stdout.resume();
	}
};

function spawn(file, args, options) {
	return new PipeTerminal(file, args, options);
}
/** @deprecated */
function fork(file, args, options) {
	return new PipeTerminal(file, args, options);
}
/** @deprecated */
function createTerminal(file, args, options) {
	return new PipeTerminal(file, args, options);
}
function open(options) {
	return new PipeTerminal(process.env.SHELL || "/system/bin/sh", [], options);
}
exports.native = null;
exports.spawn = spawn;
exports.fork = fork;
exports.createTerminal = createTerminal;
exports.open = open;
''';

// ---- 会话持久化 link→rename 回退（定点替换，锚点必须与上游逐字符一致）----

const String _spImportFrom = 'import { link, lstat, mkdir, mkdtemp, open, '
    'readFile, readdir, realpath, rm, stat, truncate } from "node:fs/promises";';
const String _spImportTo = 'import { link, lstat, mkdir, mkdtemp, open, '
    'readFile, readdir, realpath, rename, rm, stat, truncate } '
    'from "node:fs/promises";';

const String _spDefaultFsFrom = 'lstat: (path) => lstat(path),\n'
    '\tlink,\n'
    '\trm: (path) => rm(path, { force: true })';
const String _spDefaultFsTo = 'lstat: (path) => lstat(path),\n'
    '\tlink,\n'
    '\trename,\n'
    '\trm: (path) => rm(path, { force: true })';

const String _spPublishFrom = '\ttry {\n'
    '\t\tawait internals.fs.link(staged, currentPath);\n'
    '\t} catch (error) {\n'
    '\t\t/* v8 ignore else -- a non-collision filesystem error propagates unchanged. */\n'
    '\t\tif (isEEXIST(error)) return false;\n'
    '\t\t/* v8 ignore next -- the filesystem error is already complete. */\n'
    '\t\tthrow error;\n'
    '\t}';
const String _spPublishTo = '\ttry {\n'
    '\t\tawait internals.fs.link(staged, currentPath);\n'
    '\t} catch (error) {\n'
    '\t\t/* v8 ignore else -- a non-collision filesystem error propagates unchanged. */\n'
    '\t\tif (isEEXIST(error)) return false;\n'
    '\t\t// local2api-android-shim: FUSE (/storage/emulated) rejects hard\n'
    '\t\t// links outright (EACCES/EPERM/ENOSYS). Fall back to rename, but\n'
    '\t\t// keep exclusive-publish semantics: if the target already exists,\n'
    '\t\t// another writer committed first.\n'
    '\t\ttry {\n'
    '\t\t\tawait internals.fs.lstat(currentPath);\n'
    '\t\t\treturn false;\n'
    '\t\t}\n'
    '\t\tcatch { /* target absent */ }\n'
    '\t\tawait internals.fs.rename(staged, currentPath);\n'
    '\t}';

const String _spMaterializeFrom = '\t\tlet linked = false;\n'
    '\t\ttry {\n'
    '\t\t\tawait link(tmp, finalPath);\n'
    '\t\t\tlinked = true;\n'
    '\t\t} finally {';
const String _spMaterializeTo = '\t\tlet linked = false;\n'
    '\t\ttry {\n'
    '\t\t\ttry {\n'
    '\t\t\t\tawait link(tmp, finalPath);\n'
    '\t\t\t\tlinked = true;\n'
    '\t\t\t}\n'
    '\t\t\tcatch {\n'
    '\t\t\t\t// local2api-android-shim: FUSE (/storage/emulated) rejects\n'
    '\t\t\t\t// hard links; rename is the same atomic publish for a path\n'
    '\t\t\t\t// that must not pre-exist (rejectExistingLog guards above).\n'
    '\t\t\t\tawait rename(tmp, finalPath);\n'
    '\t\t\t\tlinked = true;\n'
    '\t\t\t}\n'
    '\t\t} finally {';

// ---- 附件存储的收权 chmod 降级（定点替换）----
//
// `dsh-attachment-local` 在初始化附件根（`$DSH_HOME/attachments/v1`）和
// `$DSH_HOME` 本身时都做 `mkdir(0700)` + `chmod(0700)`，把「目录只有我自己
// 能进」当成不变量。这条在 Linux 上成立，在 Android 的 FUSE 上不一定：
// 目录属主可能是应用（u0_a455）而不是 dsh 进程（shell），于是 chmod 直接
// EPERM，整个附件服务起不来 —— 表现就是「图片发不进去 / read_image 报错」，
// sharp 的错误只是先撞上的那一层。
//
// 而且这一刀必须**整个跳过**，不能只把错误吞掉：`.dsh` 要同时被应用（写
// cordis.patch.yml / profiles）和 dsh（shell 身份）读写，靠的是我们给的 777；
// 一旦让 chmod(0700) 成功执行，应用的配置写入立刻 EACCES。
// 私密性在 Android 上另有保证：/storage/emulated/0/Android/data/<pkg> 本身
// 就只有该应用和 shell 能进。`mkdir(..., mode: 448)` 建新目录时依然是 0700，
// 所以新附件目录的权限不变。
const String _attChmodFrom = '\tawait chmod(target, 448);';
const String _attChmodTo = '\t// local2api-android-shim: skip owner-only chmod.\n'
    '\t// - FUSE refuses chmod on app-owned dirs (EPERM), which kills the\n'
    '\t//   whole attachment service before sharp is ever reached.\n'
    '\t// - Succeeding would lock the app out of \$DSH_HOME, where it writes\n'
    '\t//   the profile and model config.\n'
    '\t// Android already isolates .../Android/data/<pkg> to the app + shell.\n'
    '\tvoid chmod;';

// 附件对象落盘用硬链接做内容寻址（同一个 sha256 只存一份）。FUSE
// （/storage/emulated）上 link 一律 EACCES，于是任何一张图都写不进去。
// 回退成 copyFile：source 不动，target 拿一份副本，语义与「加别名」一致；
// staged 那条也一样（后面紧跟的 unlink 会正常把临时文件删掉）。
const String _attImportFrom = 'import { chmod, link, mkdir, open, readFile, '
    'rename, rm, unlink, writeFile } from "node:fs/promises";';
const String _attImportTo = 'import { chmod, copyFile, link, mkdir, open, readFile, '
    'rename, rm, unlink, writeFile } from "node:fs/promises";';

const String _attAliasLinkFrom = '\t\t\tawait link(source, target);';
const String _attAliasLinkTo = '\t\t\ttry {\n'
    '\t\t\t\tawait link(source, target);\n'
    '\t\t\t} catch (linkError) {\n'
    '\t\t\t\tconst linkCode = linkError?.code;\n'
    '\t\t\t\tif (linkCode !== "EACCES" && linkCode !== "EPERM" && '
    'linkCode !== "ENOSYS" && linkCode !== "ENOTSUP" && linkCode !== "EXDEV") '
    'throw linkError;\n'
    '\t\t\t\t// local2api-android-shim: FUSE rejects hard links; copy instead.\n'
    '\t\t\t\tawait copyFile(source, target);\n'
    '\t\t\t}';

const String _attStagedLinkFrom = '\t\t\tawait link(staged.path, target);';
const String _attStagedLinkTo = '\t\t\ttry {\n'
    '\t\t\t\tawait link(staged.path, target);\n'
    '\t\t\t} catch (linkError) {\n'
    '\t\t\t\tconst linkCode = linkError?.code;\n'
    '\t\t\t\tif (linkCode !== "EACCES" && linkCode !== "EPERM" && '
    'linkCode !== "ENOSYS" && linkCode !== "ENOTSUP" && linkCode !== "EXDEV") '
    'throw linkError;\n'
    '\t\t\t\t// local2api-android-shim: FUSE rejects hard links; copy instead.\n'
    '\t\t\t\tawait copyFile(staged.path, target);\n'
    '\t\t\t}';

// 落盘后再把对象收成 0400（只读不可改）。FUSE 上这一步同样可能 EPERM，
// 而它失败会把已经写好的附件判成整体失败 —— 直接降级忽略。
const String _attChmodStagedFrom =
    '\t\tawait unlink(staged.path);\n\t\tawait chmod(target, 256);';
const String _attChmodStagedTo =
    '\t\tawait unlink(staged.path);\n\t\tawait chmod(target, 256).catch(() => {});';

const String _attChmodAliasFrom =
    '\t\tawait chmod(target, 256);\n\t\tconst stop = resolve(root);';
const String _attChmodAliasTo =
    '\t\tawait chmod(target, 256).catch(() => {});\n\t\tconst stop = resolve(root);';

// ---- 写完文件后的原子发布：硬链接 → rename 回退 ----
//
// `writeFileAtomic` 在「目标应该不存在」（create 语义）时用 `link` 做
// no-replace 发布，异常只认 EEXIST。FUSE（/storage/emulated）上 link 一律
// EACCES → 模型写任何新文件都失败：
//   cannot write ".../parse.mjs": EACCES: permission denied, link '...tmp' -> '...'
//
// 回退方案：先用 lstat 探一次目标（保住「不许覆盖」的语义 —— 已被别的
// 写入抢先时仍走 throwGuardedCreateFailure 报 FS_NOT_OBSERVED），确认没有
// 才 rename 落盘。并发窗口比 link 大一点，但这是 FUSE 上唯一能写成的做法。
const String _fslLinkFrom = '\t\t\tawait linkFile(tempPath, absolutePath);';
const String _fslLinkTo = '\t\t\tawait linkFile(tempPath, absolutePath).catch(async (linkError) => {\n'
    '\t\t\t\tconst linkCode = linkError?.code;\n'
    '\t\t\t\tif (linkCode !== "EACCES" && linkCode !== "EPERM" && '
    'linkCode !== "ENOSYS" && linkCode !== "ENOTSUP" && linkCode !== "EXDEV") '
    'throw linkError;\n'
    '\t\t\t\t// local2api-android-shim: FUSE rejects hard links. Probe for an\n'
    '\t\t\t\t// existing target to keep the no-replace contract, then rename.\n'
    '\t\t\t\tlet taken = false;\n'
    '\t\t\t\ttry {\n'
    '\t\t\t\t\tawait inspectPublicationTarget(absolutePath);\n'
    '\t\t\t\t\ttaken = true;\n'
    '\t\t\t\t} catch (_) { /* absent: safe to publish */ }\n'
    '\t\t\t\tif (taken) return throwGuardedCreateFailure(linkError, absolutePath, '
    'createIfAbsent.displayPath, inspectPublicationTarget);\n'
    '\t\t\t\tawait rename(tempPath, absolutePath);\n'
    '\t\t\t});';
