// 本地 TTS（Qwen3-TTS）模型文件的按需下载 / 删除管理。
//
// 自 NaviFlash lib/services/tts_model_service.dart 移植，去掉那边特有的
// 存储槽位（StoragePaths/StorageSlot）与 Android 原生前台下载
// （ModelDownloadService），落盘位置固定为
// getApplicationSupportDirectory()/tts/<variantId>/。
//
// 断点续传逻辑原样保留：`.part` 就是断点，中断/失败一律保留，
// 下次 install 从断点接着下。
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 镜像站选择。
enum TtsMirror {
  /// HuggingFace 官方（海外网络）
  official,

  /// hf-mirror.com（国内可直连，目录结构一致）
  hfMirror,

  /// 用户自定义地址
  custom,
}

extension TtsMirrorX on TtsMirror {
  String get id => switch (this) {
    TtsMirror.official => 'official',
    TtsMirror.hfMirror => 'hfMirror',
    TtsMirror.custom => 'custom',
  };
}

/// 清单里的单个文件。
class TtsModelFile {
  /// 相对变体根目录的路径，同时用作下载时的 URL 后缀。
  final String rel;

  /// 预期字节数；仅用于进度计算与完整性粗校验（允许小幅偏差）。
  final int bytes;

  const TtsModelFile(this.rel, this.bytes);

  String get name => rel.split('/').last;
}

/// 一个可下载的 TTS 模型变体。
class TtsModelVariant {
  /// 本地目录名，也是设置里持久化的标识。
  final String id;

  /// HuggingFace 仓库 id。
  final String repo;

  /// 展示名。
  final String label;

  final List<TtsModelFile> files;

  const TtsModelVariant({
    required this.id,
    required this.repo,
    required this.label,
    required this.files,
  });

  int get totalBytes => files.fold<int>(0, (sum, f) => sum + f.bytes);
}

/// Qwen3-TTS 1.7B Base（llama.cpp 官方转换版）。
///
/// 用 ggml-org 的官方 GGUF：llamadart 的 `TextToSpeechEngine` 只认
/// llama.cpp 官方那套「主模型 + mmproj」结构，talker 自回归、codec 解码、
/// 声音克隆整套编排它都做好了。
///
/// 来源：https://huggingface.co/ggml-org/Qwen3-TTS-12Hz-1.7B-Base-GGUF
///   主模型 Q4_K_M  988 MB
///   mmproj Q8_0   425.7 MB（音频生成投影器，TTS 必须加载）
const TtsModelVariant kQwen3Tts17BBase = TtsModelVariant(
  id: 'qwen3-1.7b-base',
  repo: 'ggml-org/Qwen3-TTS-12Hz-1.7B-Base-GGUF',
  label: 'Qwen3-TTS 1.7B',
  files: [
    TtsModelFile('Qwen3-TTS-12Hz-1.7B-Base-Q4_K_M.gguf', 1035993088),
    TtsModelFile('mmproj-Qwen3-TTS-12Hz-1.7B-Base-Q8_0.gguf', 446376857),
  ],
);

/// 当前内置的模型变体。
const List<TtsModelVariant> kTtsModelVariants = [kQwen3Tts17BBase];

/// 安装状态。
enum TtsModelState {
  /// 未下载（目录不存在或空）
  notInstalled,

  /// 下载不完整（部分文件缺失/截断，继续下载可补全）
  partial,

  /// 齐全
  installed,
}

class TtsModelService {
  TtsModelService._();

  static final http.Client _client = http.Client();

  /// 当前使用的变体。
  static TtsModelVariant variant = kQwen3Tts17BBase;

  /// 镜像选择；由 TtsSettings 在 load / setter 里同步写入。
  static TtsMirror mirror = TtsMirror.hfMirror;

  /// 自定义镜像的根地址（仅 [TtsMirror.custom] 时生效）。
  static String? customBaseUrl;

  static const String _officialPrefix = 'https://huggingface.co/';
  static const String _hfMirrorPrefix = 'https://hf-mirror.com/';

  /// 下载源根目录（末尾带 '/'）。
  static String get baseUrl {
    final prefix = switch (mirror) {
      TtsMirror.official => _officialPrefix,
      TtsMirror.hfMirror => _hfMirrorPrefix,
      TtsMirror.custom => (customBaseUrl ?? '').trim(),
    };
    final base = prefix.isEmpty ? _hfMirrorPrefix : prefix;
    final withSlash = base.endsWith('/') ? base : '$base/';
    return '$withSlash${variant.repo}/resolve/main/';
  }

  static void applyMirror(TtsMirror m, String customUrl) {
    mirror = m;
    customBaseUrl = customUrl.trim().isEmpty ? null : customUrl.trim();
  }

  /// tts 根目录：getApplicationSupportDirectory()/tts/。
  ///
  /// 不用缓存目录：避免被系统「清理缓存」连带删掉，删除只能用户显式操作。
  static Future<Directory> get ttsRoot async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'tts'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 当前变体的模型目录。
  static Future<Directory> modelDir([TtsModelVariant? v]) async {
    final root = await ttsRoot;
    final dir = Directory(p.join(root.path, (v ?? variant).id));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<File> _file(TtsModelFile f) async =>
      File(p.join((await modelDir()).path, f.rel));

  /// 单个文件是否已完整（允许 2% 偏差：进度计算的大小是估值）。
  static bool _isComplete(int actual, int expected) {
    if (actual <= 0) return false;
    if (expected <= 8 * 1024) return true; // 小文件（json 之类）只看存在
    return actual >= (expected * 0.98).floor();
  }

  /// 已安装字节数。
  static Future<int> installedBytes() async {
    var total = 0;
    final dir = await modelDir();
    for (final f in variant.files) {
      final file = File(p.join(dir.path, f.rel));
      if (await file.exists()) {
        total += await file.length().catchError((_) => 0);
      }
    }
    return total;
  }

  static Future<TtsModelState> state() async {
    final dir = await modelDir();
    return _stateAt(dir);
  }

  /// 模型齐全时返回目录路径，否则 null。
  static Future<String?> readyModelDir() async {
    final dir = await modelDir();
    if (await _stateAt(dir) == TtsModelState.installed) return dir.path;
    return null;
  }

  static Future<TtsModelState> _stateAt(Directory dir) async {
    var missing = 0;
    var present = 0;
    for (final f in variant.files) {
      final file = File(p.join(dir.path, f.rel));
      if (!await file.exists()) {
        missing++;
        continue;
      }
      final len = await file.length().catchError((_) => 0);
      if (_isComplete(len, f.bytes)) {
        present++;
      } else {
        missing++;
      }
    }
    if (missing == 0) return TtsModelState.installed;
    if (present > 0) return TtsModelState.partial;
    return TtsModelState.notInstalled;
  }

  /// 下载缺失的文件（**支持断点续传**）。
  ///
  /// 续传规则：`.part` 存在就用它接着下；上一版留下的「半截正式文件」会被
  /// 挪成 `.part` 继续用。中断/失败时**保留** `.part`，下次调用从这里继续。
  ///
  /// [onProgress] 回调 (已收总字节, 总字节, 当前文件名)。
  /// [shouldCancel] 返回 true → 抛 [TtsModelCancelled]（已完成的分片与 `.part` 都留着）。
  static Future<void> install({
    void Function(int received, int total, String currentName)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    // 开下之前先扫掉没用的零碎文件（真断点会留着），顺手回收空间
    final freed = await cleanupOrphans();
    if (freed > 0) {
      debugPrint('[TtsModel] 清理无用断点文件 ${(freed / 1024 / 1024).round()}MB');
    }

    // ── ① 规划：哪些要下、各从第几字节开始 ──
    var doneBytes = 0;
    final todo = <(TtsModelFile, int)>[];
    for (final f in variant.files) {
      final file = await _file(f);
      final tmp = File('${file.path}.part');
      final len = await _lengthOf(file);

      // 已完整：跳过，并把它遗留的 .part 清掉
      if (len > 0 && _isComplete(len, f.bytes)) {
        doneBytes += len;
        await _deleteQuietly(tmp);
        continue;
      }

      // 续传起点：.part 优先，其次把半截的正式文件挪成 .part
      var start = await _lengthOf(tmp);
      if (start == 0 && len > 0) {
        if (await _renameQuietly(file, tmp)) start = len;
      }
      // 比预期还大（源文件换过了）→ 从零来
      if (start > f.bytes) {
        await _deleteQuietly(tmp);
        start = 0;
      }
      todo.add((f, start));
    }

    final total = variant.totalBytes;
    final base = baseUrl;
    for (final (f, start) in todo) {
      if (shouldCancel?.call() ?? false) throw const TtsModelCancelled();
      final target = await _file(f);
      await target.parent.create(recursive: true);
      final url = Uri.parse('$base${f.rel}');
      await _download(
        url,
        target,
        start: start,
        onProgress: (received, _) {
          onProgress?.call(doneBytes + received, total, f.name);
        },
        shouldCancel: shouldCancel,
      );
      doneBytes += f.bytes;
    }

    // 收尾校验
    if (await state() != TtsModelState.installed) {
      throw TtsModelException('部分文件校验失败，请重新下载');
    }
  }

  /// 删除模型文件。
  static Future<void> uninstall() async {
    final dir = await modelDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true).catchError((_) => dir);
    }
  }

  /// 下载单个文件，**支持断点续传**。
  ///
  /// [start] > 0 时带 `Range: bytes=start-`：
  ///   · 206 Partial Content → 追加写 `.part`（并保留断点）；
  ///   · 200 → 服务器不认 Range / 源文件变了 → 丢掉已有字节从头下。
  /// 任何中断都**不删** `.part` —— 那就是断点。
  static Future<void> _download(
    Uri url,
    File target, {
    int start = 0,
    void Function(int received, int total)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final tmp = File('${target.path}.part');
    var offset = start;

    late final http.StreamedResponse resp;
    try {
      final req = http.Request('GET', url)..followRedirects = true;
      if (offset > 0) req.headers['Range'] = 'bytes=$offset-';
      // 1GB 级的仓库，握手给足时间
      resp = await _client.send(req).timeout(const Duration(seconds: 60));
    } catch (e) {
      throw TtsModelException('连接下载源失败：$e（已保留断点，可继续）');
    }

    // 本次要下的总长度：206 时从 Content-Range 里取完整大小
    var totalFull = 0;
    if (resp.statusCode == 206) {
      final cr = resp.headers['content-range'] ?? '';
      final m = RegExp(r'/(\d+)\s*$').firstMatch(cr);
      totalFull =
          int.tryParse(m?.group(1) ?? '') ??
          (offset + (resp.contentLength ?? 0));
    } else if (resp.statusCode == 200) {
      if (offset > 0) {
        // 不认 Range：已有字节作废，从头来（.part 截断）
        debugPrint('[TtsModel] 下载源不支持断点，重新下载 ${p.basename(target.path)}');
        offset = 0;
      }
      totalFull = resp.contentLength ?? 0;
    } else {
      throw TtsModelException(
        '下载失败：HTTP ${resp.statusCode}（${p.basename(target.path)}）',
      );
    }

    IOSink? sink;
    var received = 0;
    try {
      sink = tmp.openWrite(
        mode: offset > 0 ? FileMode.append : FileMode.write,
      );
      // 单文件 1GB，40 分钟兜底
      await resp.stream.timeout(const Duration(minutes: 40)).forEach((chunk) {
        if (shouldCancel?.call() ?? false) throw const TtsModelCancelled();
        sink!.add(chunk);
        received += chunk.length;
        onProgress?.call(offset + received, totalFull);
      });
      await sink.flush();
      await sink.close();
      sink = null;

      final onDisk = await _lengthOf(tmp);
      if (totalFull > 0 && onDisk < totalFull) {
        throw TtsModelException(
          '下载中断（$onDisk/$totalFull 字节），已保留断点，可继续',
        );
      }
      // 先在 .part 落盘再 rename，避免中断留下半截文件被当成已下载
      if (await target.exists()) {
        await target.delete();
      }
      await tmp.rename(target.path);
    } on TtsModelCancelled {
      rethrow;
    } on TtsModelException {
      rethrow;
    } catch (e) {
      throw TtsModelException('下载失败：$e（已保留断点，可继续）');
    } finally {
      if (sink != null) {
        await sink.close().catchError((_) {});
      }
      // ⚠️ 这里**不再删 .part**：断点续传就靠它，下次 install 会从这里接着下
    }
    debugPrint('[TtsModel] 已下载 ${p.basename(target.path)}');
  }

  /// 一个 `.part` 是不是「没用的零碎文件」（可以删）：
  ///   · 对应文件不在清单里（历史遗留 / 换过变体）→ 没用；
  ///   · 正式文件已经完整 → 没用；
  ///   · 断点比预期还大（源文件变小了）→ 没用。
  /// 其它情况都当**真断点**留着。
  static bool partIsUseless({
    required int partLen,
    required int targetLen,
    required int? expected,
  }) {
    if (expected == null) return true;
    if (_isComplete(targetLen, expected)) return true;
    return partLen > expected;
  }

  /// 文件长度（不存在 / 读失败按 0）。
  static Future<int> _lengthOf(File f) async {
    if (!await f.exists()) return 0;
    return f.length().catchError((_) => 0);
  }

  static Future<void> _deleteQuietly(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// [from] → [to] 改名；成功返回 true。
  static Future<bool> _renameQuietly(File from, File to) async {
    try {
      await from.rename(to.path);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 扫掉「没用」的 `.part`（对应文件已完整 / 超出预期大小 / 不在清单里）
  /// 与清单外的孤儿文件，返回清掉的字节数。
  ///
  /// 中断留下的断点**不会被清**（那是要接着下的），只清真正没用的。
  static Future<int> cleanupOrphans() async {
    var freed = 0;
    final dir = await modelDir();
    if (!await dir.exists()) return 0;

    final known = <String, int>{};
    for (final f in variant.files) {
      known[p.basename(f.rel)] = f.bytes;
    }

    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.endsWith('.part')) continue;
      final target = name.substring(0, name.length - '.part'.length);
      final expected = known[target];
      final len = await _lengthOf(entity);
      // 对应文件不在清单 / 已经完整 / 断点超出预期 → 没用了
      final targetFile = File(entity.path.substring(0, entity.path.length - 5));
      final targetLen = await _lengthOf(targetFile);
      if (!partIsUseless(
        partLen: len,
        targetLen: targetLen,
        expected: expected,
      )) {
        continue;
      }
      await _deleteQuietly(entity);
      freed += len;
    }
    return freed;
  }
}

/// 用户主动取消（不是失败）——已下好的分片与 `.part` 都保留，下次接着下。
class TtsModelCancelled implements Exception {
  const TtsModelCancelled();

  @override
  String toString() => '已取消（断点已保留）';
}

class TtsModelException implements Exception {
  final String message;
  TtsModelException(this.message);

  @override
  String toString() => message;
}
