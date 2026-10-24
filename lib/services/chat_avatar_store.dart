import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_attachment.dart';
import 'chat_simulation.dart' show ChatRole;

/// 「对话模拟」页的用户 / 助手自定义头像（全机一份，Material 与 miuix 共用）。
///
/// 只有用户与助手两个角色支持换图；系统提示词那条继续用齿轮图标。
/// 选图后统一压到 ≤[maxDimension] 的 JPEG 再落盘 —— 桌面端的 file_picker
/// 回落不做压缩，原图几 MB 直接进 SharedPreferences 会把存档撑肥。
class ChatAvatarStore extends ChangeNotifier {
  static const String _key = 'local2api.chatsim.avatars.v1';

  /// 头像压缩目标边长（显示最大也就 56px，512 足够清晰还省体积）。
  static const int maxDimension = 512;

  /// 单张头像落盘上限（压缩后正常只有几十 KB，防呆用）。
  static const int maxAvatarBytes = 1024 * 1024;

  final Map<ChatRole, Uint8List> _avatars = {};
  bool _loaded = false;
  Timer? _saveTimer;

  /// 最近一次选图 / 压缩失败的原因（界面直接 toast 原文）。
  static String? lastPickError;

  bool get loaded => _loaded;

  /// 这个角色的自定义头像字节；null = 没配（用默认图标）。
  Uint8List? avatarOf(ChatRole role) => _avatars[role];

  bool hasAvatarOf(ChatRole role) => _avatars[role]?.isNotEmpty ?? false;

  /// 从相册（[fromCamera] 时是相机）选一张图并设为该角色的头像。
  /// 结果语义与附件选取一致：ok / cancelled（不 toast）/ failed（报原因）。
  Future<AttachmentPick> pickAvatar(
    ChatRole role, {
    bool fromCamera = false,
  }) async {
    if (role == ChatRole.system) return AttachmentPick.cancelled;
    lastPickError = null;
    final r = await ChatAttachmentPicker.pickImage(fromCamera: fromCamera);
    final raw = r.image?.thumbnail;
    if (raw == null) {
      // 取消不报；失败带上选图器的原因。
      lastPickError = ChatAttachmentPicker.lastError;
      return r.pick;
    }
    final squeezed = await _squeeze(raw);
    if (squeezed == null) {
      lastPickError = '图片无法解码';
      return AttachmentPick.failed;
    }
    if (squeezed.length > maxAvatarBytes) {
      lastPickError = '压缩后仍超过 1MB';
      return AttachmentPick.failed;
    }
    await setAvatar(role, squeezed);
    return AttachmentPick.ok;
  }

  /// 设置 / 清除（null = 恢复默认）某个角色的头像。system 不接受设置。
  /// 与现状相同时直接短路（不通知也不落盘）。
  Future<void> setAvatar(ChatRole role, Uint8List? bytes) async {
    if (role == ChatRole.system) return;
    final next = (bytes == null || bytes.isEmpty)
        ? null
        : Uint8List.fromList(bytes);
    final current = _avatars[role];
    if (next == null && current == null) return;
    if (next != null && current != null && listEquals(next, current)) return;
    if (next == null) {
      _avatars.remove(role);
    } else {
      _avatars[role] = next;
    }
    notifyListeners();
    _scheduleSave();
  }

  /// 在 isolate 里缩放 + 编码 JPEG（大图解码别卡住 UI，同 `analyzeImageColor`）。
  static Future<Uint8List?> _squeeze(Uint8List bytes) =>
      compute(_squeezeInIsolate, bytes, debugLabel: 'chatAvatarSqueeze');

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          for (final role in const [ChatRole.user, ChatRole.assistant]) {
            final b64 = decoded[role.wire];
            if (b64 is String && b64.isNotEmpty) {
              try {
                _avatars[role] = base64Decode(b64);
              } catch (_) {
                // 单张坏了丢这张，别牵连另一张。
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('ChatAvatarStore load failed: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_save());
    });
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          for (final e in _avatars.entries)
            if (e.value.isNotEmpty) e.key.wire: base64Encode(e.value),
        }),
      );
    } catch (e) {
      debugPrint('ChatAvatarStore save failed: $e');
    }
  }

  /// 立即落盘（退出前调用，别指望防抖定时器）。
  Future<void> flush() async {
    _saveTimer?.cancel();
    await _save();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}

/// isolate 入口：解码 → 缩放到 ≤512 → JPEG 88。解不开返回 null。
Uint8List? _squeezeInIsolate(Uint8List bytes) {
  img.Image? image;
  try {
    image = img.decodeImage(bytes);
  } catch (_) {
    // image 包对部分垃圾数据会在格式探测阶段抛异常（如 PSD 探测越界）
    return null;
  }
  if (image == null) return null;
  const maxDim = ChatAvatarStore.maxDimension;
  if (image.width > maxDim || image.height > maxDim) {
    image = img.copyResize(
      image,
      width: maxDim,
      height: maxDim,
      maintainAspect: true,
    );
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 88));
}

final ChatAvatarStore chatAvatarStore = ChatAvatarStore();
