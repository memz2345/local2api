import 'dart:io';

import 'package:local_auth/local_auth.dart';

/// 生物识别锁（Hail 同款应用锁）的薄封装。
///
/// 语义对齐 Hail 的 MainActivity：**只在应用冷启动（进程新起）时**弹一次
/// BiometricPrompt，通过前不渲染任何界面。切后台 / 回前台 / 切屏都不再验证
/// —— Hail 的 onStop 那句 `finishAndRemoveTask()` 是注释掉的，验一次就够。
///
/// `biometricOnly: false` 让生物识别不可用时回落到设备凭据（PIN / 图案 /
/// 密码）—— 对应 Hail 的 `BIOMETRIC_STRONG | DEVICE_CREDENTIAL`。
class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  /// 设备是否具备验证硬件。有没有**录入**凭据不看这里 —— 以「开启开关时的
  /// 那次试验证」为准（失败就开不了），避免状态 API 在各 OEM 上口径不一。
  Future<bool> isSupported() async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// 弹一次系统验证。通过返回 true；取消 / 失败 / 异常返回 false。
  ///
  /// [reason] 会显示在系统对话框上。`stickyAuth` 让验证流程跨过切后台
  /// （弹窗期间来电话之类的场景）不断链。
  Future<bool> authenticate(String reason) async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
