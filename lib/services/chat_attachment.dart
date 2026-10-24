// lib/services/chat_attachment.dart
// 对话模拟的附件选取：图片走 image_picker（相册 / 拍照，选取时就地压成
// ≤1024px 的 JPEG，兼顾展示与发给上游时的体积），文件走 file_picker
// （只取名字和大小，内容不读）。
//
// 图片选完就是「能发出去」的那份字节：气泡里渲染它，发请求时把它编成
// data URL 塞进多模态 content（见 ChatMsg.toWire）。
//
// 失败一定要报出来：以前 catch 完直接返回 null，用户点了半天没反应，
// 看起来就像「不支持图片输入」。所以这里把「取消」和「失败」分开返回，
// 失败带上原因给页面 toast。
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:image_picker/image_picker.dart';

import 'chat_simulation.dart';

/// 一次选取的结果。
enum AttachmentPick {
  /// 拿到了附件。
  ok,

  /// 用户中途取消（不算错误，别 toast）。
  cancelled,

  /// 选图器 / 读文件出错，[ChatAttachmentPicker.lastError] 有原因。
  failed,
}

class ChatAttachmentPicker {
  static final ImagePicker _imagePicker = ImagePicker();

  /// 最近一次失败原因（插件抛出来的原文，界面上直接显示，方便对着查）。
  static String? lastError;

  /// 从系统相册（[fromCamera] 时是相机）选一张图，压成缩略图返回。
  /// [image] 为 null 时按 [pick] 判断是取消还是失败。
  ///
  /// image_picker 只有移动端实现：桌面端（Windows/Linux）第一次调用抛
  /// MissingPluginException —— 这就是「点了选图直接报不支持」的根源。
  /// 桌面端没有相机，也没有「相册」概念，退到 file_picker 的图片选择
  /// （带字节读回，走同一条压缩/编码管线）。
  static Future<({AttachmentPick pick, ChatAttachment? image})> pickImage({
    bool fromCamera = false,
  }) async {
    lastError = null;
    try {
      final x = await _imagePicker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        // 1024px + JPEG 85：视觉模型看得清，base64 后一般 100～300KB，
        // 不会被纯文本车道的请求体上限卡住。
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (x == null) return (pick: AttachmentPick.cancelled, image: null);
      final bytes = await x.readAsBytes();
      return _imageFromBytes(bytes, x.name);
    } on MissingPluginException {
      // 桌面端：file_picker 选图（相机请求也一样退到选图）。
      final r = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      final f = r?.files.singleOrNull;
      if (f == null) return (pick: AttachmentPick.cancelled, image: null);
      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) {
        lastError = '${f.name} 读不出内容';
        return (pick: AttachmentPick.failed, image: null);
      }
      return _imageFromBytes(bytes, f.name);
    } on Object catch (e) {
      // PlatformException（权限被拒 / ROM 的相册 Activity 起不来）等。
      lastError = _brief(e);
      return (pick: AttachmentPick.failed, image: null);
    }
  }

  /// 字节头嗅探 MIME + 组装附件；空文件按失败报。
  static ({AttachmentPick pick, ChatAttachment? image}) _imageFromBytes(
    Uint8List bytes,
    String name,
  ) {
    if (bytes.isEmpty) {
      lastError = '$name 是空文件';
      return (pick: AttachmentPick.failed, image: null);
    }
    return (
      pick: AttachmentPick.ok,
      image: ChatAttachment(
        name: name,
        isImage: true,
        // 压缩后的大小：展示用，够准了（原始大小选图器不带回）。
        sizeBytes: bytes.length,
        thumbnail: bytes,
      ),
    );
  }

  /// 从文件管理器选一个文件，只取元信息（名字 / 大小），内容不读。
  static Future<({AttachmentPick pick, ChatAttachment? file})> pickFile() async {
    lastError = null;
    try {
      final result = await FilePicker.platform.pickFiles(withData: false);
      final f = result?.files.singleOrNull;
      if (f == null) return (pick: AttachmentPick.cancelled, file: null);
      return (
        pick: AttachmentPick.ok,
        file: ChatAttachment(name: f.name, isImage: false, sizeBytes: f.size),
      );
    } on Object catch (e) {
      lastError = _brief(e);
      return (pick: AttachmentPick.failed, file: null);
    }
  }

  static String _brief(Object e) {
    var s = '$e';
    s = s.replaceAll('\n', ' ').trim();
    if (s.startsWith('PlatformException')) s = s.substring(16);
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }
}
