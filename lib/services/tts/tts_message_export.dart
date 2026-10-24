// lib/services/tts/tts_message_export.dart
//
// 对话模拟「下载」这一条路：把一条消息的文本合成出来，转成 MP3 / SILK v3
// （.silk/.slk）字节，再交给系统「另存为」。
//
// 与「朗读」共用同一套路线决策（[ChatTts.decideRoute]）和同一条合成路径
// （[TtsSpeechService.synthesizeLocal] / [synthesizeCloud]）—— 下出来的音频
// 就是朗读会播的那一段，只是不播放、不碰 activeTag，所以导出期间气泡上的
// 喇叭按钮不会莫名其妙变成「停止」。
//
// 编码只在 Android 上有（原生 libttsexport.so，见 tts_export_native.dart）；
// 其余平台 [isSupported] 为 false，UI 据此把「下载」这一项藏掉。
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../models/proxy_config.dart';
import '../chat_simulation.dart';
import 'tts_chat_speak.dart';
import 'tts_export_native.dart';
import 'tts_export_service.dart';
import 'tts_settings.dart';
import 'tts_speech_service.dart';

/// 一条消息的「合成 + 转码 + 存盘」。全是静态方法，无状态。
class TtsMessageExport {
  TtsMessageExport._();

  /// 当前平台能不能转 MP3/SILK（只有 Android 编了原生编码器）。
  static bool get isSupported => TtsExportService.isSupported;

  /// SILK 的 `-tencent`（微信/QQ 兼容：文件头多一个 0x02、结尾不写 0xFFFF
  /// 哨兵包）。默认开 —— 下 silk/slk 基本就是为了发微信/QQ。
  static const bool defaultTencent = true;

  /// 合成 [text] 并转成 [format]，返回编码后的字节。
  ///
  /// [voiceSamplePath] 是角色卡的音色样本，参与 [ChatTts.decideRoute] 的
  /// 三路线判定（克隆 / 设计 / 预置）。
  ///
  /// 抛 [TtsNotConfiguredException]（没配 TTS / 模型失效 / 克隆缺样本）、
  /// [TtsExportUnsupportedException]（非 Android）、[TtsExportException]
  /// （WAV 形状不对 / 采样率不支持）或引擎侧的 TtsModelException。
  static Future<Uint8List> render({
    required String text,
    required ProxyConfig config,
    String? voiceSamplePath,
    required TtsExportFormat format,
    bool tencent = defaultTencent,
  }) async {
    if (!isSupported) throw TtsExportUnsupportedException();
    if (text.trim().isEmpty) throw TtsExportException('这条消息没有可合成的文本');

    await TtsSettings.instance.load();
    final settings = TtsSettings.instance;
    if (settings.provider == TtsSettings.providerOff) {
      throw const TtsNotConfiguredException('未选择 TTS 服务商');
    }
    if (!ChatTts.providerAvailable(config, settings.provider)) {
      throw const TtsNotConfiguredException('所选 TTS 模型已不可用，请重新选择');
    }
    final decision = ChatTts.decideRoute(config, voiceSamplePath, settings);
    if (decision == null) {
      throw const TtsNotConfiguredException(
        '克隆模型需要音色样本：先给角色卡配一段音频，或改选其它 TTS 模型',
      );
    }

    final speech = TtsSpeechService.instance;
    final wav = decision.local
        ? await speech.synthesizeLocal(text, voicePath: decision.voicePath)
        : await speech.synthesizeCloud(
            text,
            model: decision.model,
            host: _loopbackOf(config),
            port: config.listenPort,
            apiKey: ChatSimulator.apiKeyOf(config),
            voiceSamplePath: decision.voicePath,
            instructions: decision.instructions,
          );

    return TtsExportService.encodeWavBytes(
      wav,
      format: format,
      tencent: tencent,
    );
  }

  /// 交给系统「另存为」。返回落盘路径；用户取消返回 null。
  ///
  /// 与 `profile_export.exportTextFile` 同一套：移动端走 SAF（bytes 交给
  /// 系统写），桌面端先问路径再自己写。
  ///
  /// 调用方应在 [render] 之后、调这个之前就把「合成中」的转圈关掉 ——
  /// 系统另存为是个要用户操作的界面，上面不该再压一层模态。
  static Future<String?> save({
    required Uint8List bytes,
    required String fileName,
    required TtsExportFormat format,
  }) async {
    if (Platform.isAndroid || Platform.isIOS) {
      return FilePicker.platform.saveFile(
        fileName: fileName,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: [format.ext],
      );
    }
    final path = await FilePicker.platform.saveFile(
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: [format.ext],
    );
    if (path == null) return null;
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  /// 与 [ChatTts.speakMessage] 同一条口径：监听在 0.0.0.0 时回环地址要写
  /// 127.0.0.1，不然连不上自己。
  static String _loopbackOf(ProxyConfig config) =>
      config.listenHost == '0.0.0.0' ? '127.0.0.1' : config.listenHost;
}
