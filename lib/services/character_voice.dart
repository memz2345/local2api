// 角色卡音色样本的选取与落盘：从文件管理器挑一段 wav/mp3，拷进
// 应用目录（SharedPreferences 里只存路径，样本本体跟着应用走）。
//
// 体积上限 7MB：MiMo voiceclone 要求 base64 后 ≤10MB（base64 膨胀 4/3，
// 7MB 原文 ≈ 9.3MB 编码，留了余量）。
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class CharacterVoiceException implements Exception {
  final String message;
  const CharacterVoiceException(this.message);

  @override
  String toString() => message;
}

class CharacterVoice {
  CharacterVoice._();

  static const int maxBytes = 7 * 1024 * 1024;

  /// 选取音频并拷进应用目录，返回新路径；用户取消返回 null。
  ///
  /// [existingPath] 是卡上现有的样本：换新成功后顺手删旧文件（只删
  /// 我们自己 voices 目录里的，别去动用户外面的文件）。
  static Future<String?> pickAndStore({String? existingPath}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['wav', 'mp3'],
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return null;

    final lower = path.toLowerCase();
    if (!lower.endsWith('.wav') && !lower.endsWith('.mp3')) {
      throw const CharacterVoiceException('仅支持 wav / mp3 音频');
    }
    final source = File(path);
    if (await source.length() > maxBytes) {
      throw const CharacterVoiceException('音频样本太大，请压缩到 7MB 以内');
    }

    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'tts', 'voices'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final target =
        p.join(dir.path, 'voice_${DateTime.now().millisecondsSinceEpoch}'
            '${p.extension(path)}');
    await source.copy(target);
    await deleteStored(existingPath);
    return target;
  }

  /// 删除存在我们 voices 目录里的样本；路径在目录外（或为空）不动。
  static Future<void> deleteStored(String? path) async {
    final clean = (path ?? '').trim();
    if (clean.isEmpty) return;
    try {
      final support = await getApplicationSupportDirectory();
      final voicesDir = p.normalize(p.join(support.path, 'tts', 'voices'));
      final normalized = p.normalize(clean);
      if (!normalized.startsWith(voicesDir)) return;
      final f = File(normalized);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// 展示用文件名（路径太长，列表/卡片里只认名字）。
  static String displayName(String? path) {
    final clean = (path ?? '').trim();
    return clean.isEmpty ? '' : p.basename(clean);
  }
}
