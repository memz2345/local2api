// 本地 TTS（Qwen3-TTS）推理后端的选择策略。
//
// 自 NaviFlash lib/services/tts_backend_policy.dart 移植，逻辑保持一致：
//
//   用户偏好（自动 / NPU / GPU / CPU）
//     × 当前设备 SoC（高通 Hexagon / 联发科 APU / 其他）
//     × 随包运行时实际编进了哪些后端
//   ────────────────────────────────────────────────►
//   实际下发给 llama.cpp 的后端（GpuBackend + gpuLayers）
//
// 本仓库 android-arm64 的原生 bundle 含 Hexagon NPU 后端
// （native/bundle/android-arm64，libggml-hexagon.so + libggml-htp-v*.so），
// high-pass（高通）平台 auto/NPU 走 HTP；HTP 不可用（非高通机、FastRPC
// 失败、skel 被拒）时原生侧加载期自动回退 CPU。
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:llamadart/llamadart.dart' as llama;

/// 用户在设置页选择的推理后端偏好。
enum TtsInferenceDevicePreference {
  /// 自动：高通平台优先 NPU（不可用回退 CPU），其他平台走 GPU/Vulkan。
  auto,

  /// 高通 Hexagon NPU（QNN/HTP）；不支持的设备 / 运行时回退 CPU。
  npu,

  /// GPU：Android/Windows/Linux 走 Vulkan，Apple 平台走 Metal。
  gpu,

  /// 纯 CPU，兼容性最好。
  cpu,
}

extension TtsInferenceDevicePreferenceX on TtsInferenceDevicePreference {
  /// 落盘用标识（TtsSettings 持久化）。
  String get id => switch (this) {
    TtsInferenceDevicePreference.auto => 'auto',
    TtsInferenceDevicePreference.npu => 'npu',
    TtsInferenceDevicePreference.gpu => 'gpu',
    TtsInferenceDevicePreference.cpu => 'cpu',
  };
}

/// 设备 SoC 厂商——目前只有高通具备 GGUF/llama.cpp 直上 NPU 的路径。
enum TtsSocVendor { qualcomm, mediatek, other }

/// 当前设备的硬件画像（一次探测，全局缓存）。
class TtsHardwareInfo {
  final TtsSocVendor vendor;

  /// android.os.Build.HARDWARE（ro.hardware）原值，调试用。
  final String hardware;

  /// android.os.Build.BOARD（ro.product.board）原值，调试用。
  final String board;

  const TtsHardwareInfo({
    required this.vendor,
    this.hardware = '',
    this.board = '',
  });

  /// 只有 Android + 高通骁龙才具备走 Hexagon NPU 的硬件前提。
  bool get isQualcommAndroid => vendor == TtsSocVendor.qualcomm;

  static const TtsHardwareInfo unknown =
      TtsHardwareInfo(vendor: TtsSocVendor.other);
}

/// NPU 回退的具体原因（用于 UI 提示 / 日志）。
enum TtsNpuFallbackReason {
  /// 不是高通平台（MTK / 其他 Android / 桌面端）。
  hardwareUnsupported,

  /// 设备是高通，但当前安装包没有内置 Hexagon NPU 运行时。
  runtimeNotBundled,

  /// Hexagon 设备枚举到了，但模型加载时 HTP session / 共享内存 / buffer
  /// 分配失败（多见于未签名 skel 被 CDSP 拒绝、FastRPC 权限、机型差异）。
  deviceLoadFailed,
}

/// 偏好解析后的最终结果。
class ResolvedTtsDevice {
  /// 用户选择的原始偏好。
  final TtsInferenceDevicePreference preference;

  /// 本次加载实际使用的后端（NPU 不可用时可能从 [preference] 回退）。
  final TtsInferenceDevicePreference effective;

  /// 下发给 llamadart / llama.cpp 的后端枚举。
  final llama.GpuBackend gpuBackend;

  /// 下发给 llama.cpp 的 n_gpu_layers。
  final int gpuLayers;

  /// 设备硬件画像。
  final TtsHardwareInfo hardware;

  /// 非空时覆盖 [fallbackReason] 的推断结果（NPU 已选但加载失败回退）。
  TtsNpuFallbackReason? overrideFallbackReason;

  ResolvedTtsDevice({
    required this.preference,
    required this.effective,
    required this.gpuBackend,
    required this.gpuLayers,
    required this.hardware,
    this.overrideFallbackReason,
  });

  /// NPU 设备可用但加载失败时，构造一份 CPU 结果并带上明确原因。
  ResolvedTtsDevice._fallback({
    required TtsInferenceDevicePreference preference,
    required TtsHardwareInfo hardware,
    required TtsNpuFallbackReason reason,
  }) : this(
         preference: preference,
         effective: TtsInferenceDevicePreference.cpu,
         gpuBackend: llama.GpuBackend.cpu,
         gpuLayers: 0,
         hardware: hardware,
         overrideFallbackReason: reason,
       );

  /// 用户的意图（含「自动」在高通上解析出的意图）是否是 NPU。
  bool get npuRequested =>
      preference == TtsInferenceDevicePreference.npu ||
      (preference == TtsInferenceDevicePreference.auto &&
          hardware.isQualcommAndroid);

  /// 是否最终没能用上 NPU（回退到了 CPU）。
  bool get fellBackFromNpu =>
      npuRequested && effective != TtsInferenceDevicePreference.npu;

  /// 回退原因；未发生回退时为 null。
  TtsNpuFallbackReason? get fallbackReason {
    if (!fellBackFromNpu) return null;
    final override = overrideFallbackReason;
    if (override != null) return override;
    return hardware.isQualcommAndroid
        ? TtsNpuFallbackReason.runtimeNotBundled
        : TtsNpuFallbackReason.hardwareUnsupported;
  }

  /// 复制一份实际后端改为 CPU 的结果（NPU 设备在但加载失败时用）。
  static ResolvedTtsDevice cpuFallbackFrom(
    ResolvedTtsDevice npu, {
    TtsNpuFallbackReason reason = TtsNpuFallbackReason.deviceLoadFailed,
  }) {
    return ResolvedTtsDevice._fallback(
      preference: npu.preference,
      hardware: npu.hardware,
      reason: reason,
    );
  }
}

/// 后端选择策略：硬件探测 + 偏好解析。
class TtsBackendPolicy {
  TtsBackendPolicy._();

  /// 当前安装包是否内置了可用的 Hexagon NPU 运行时。
  ///
  /// android-arm64 bundle 由高通 Snapdragon toolchain 自编译
  /// （GGML_HEXAGON=ON），含 libggml-hexagon.so + libggml-htp-v*.so；
  /// vendored llamadart 通过 ggml 注册表 "HTP" 选设备，枚举不到时加载期
  /// 自动回退 CPU。仅 android-arm64 的自编译产物具备；x64/桌面走其他分支。
  static const bool bundledNpuRuntime = true;

  static TtsHardwareInfo? _cachedHardware;
  static Future<TtsHardwareInfo>? _pendingProbe;

  /// 探测当前设备的 SoC 厂商（结果缓存，重复调用零开销）。
  static Future<TtsHardwareInfo> hardware() {
    final cached = _cachedHardware;
    if (cached != null) return Future.value(cached);
    final pending = _pendingProbe;
    if (pending != null) return pending;

    final future = _probeHardware();
    _pendingProbe = future;
    return future.then((info) {
      _cachedHardware = info;
      _pendingProbe = null;
      return info;
    });
  }

  static Future<TtsHardwareInfo> _probeHardware() async {
    if (!Platform.isAndroid) return TtsHardwareInfo.unknown;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final hw = info.hardware.toLowerCase();
      final board = info.board.toLowerCase();
      final vendor = _classifyVendor(hw, board);
      return TtsHardwareInfo(
        vendor: vendor,
        hardware: info.hardware,
        board: info.board,
      );
    } catch (_) {
      return TtsHardwareInfo.unknown;
    }
  }

  /// 依据 ro.hardware / ro.product.board 判断 SoC 厂商。
  ///
  /// 高通现代机型 ro.hardware 多为 "qcom"，board 为 sm/msm/sdm/qcs 开头；
  /// MTK 机型两者均为 "mt6xxx"/"mt8xxx"。识别失败归为 other——后果只是
  /// 「自动」不走 NPU（手动选 NPU 也照样安全回退 CPU），不会出故障。
  static TtsSocVendor _classifyVendor(String hardware, String board) {
    bool isMtk(String s) => RegExp(r'^mt\d').hasMatch(s);
    bool isQualcomm(String s) =>
        s.startsWith('qcom') ||
        s.startsWith('msm') ||
        s.startsWith('sdm') ||
        RegExp(r'^(sm|qcs|qcm)\d').hasMatch(s);

    if (isQualcomm(hardware) || isQualcomm(board)) {
      return TtsSocVendor.qualcomm;
    }
    if (isMtk(hardware) || isMtk(board)) {
      return TtsSocVendor.mediatek;
    }
    return TtsSocVendor.other;
  }

  /// 把用户偏好解析成本次加载实际使用的后端参数。
  static Future<ResolvedTtsDevice> resolve(
    TtsInferenceDevicePreference preference,
  ) async {
    final hw = await hardware();

    switch (preference) {
      case TtsInferenceDevicePreference.npu:
        if (hw.isQualcommAndroid && bundledNpuRuntime) {
          return _npu(preference, hw);
        }
        return _cpu(preference, hw);
      case TtsInferenceDevicePreference.auto:
        // 高通平台默认 NPU；NPU 运行时未就绪则由 _cpu 回退。
        if (hw.isQualcommAndroid) {
          return bundledNpuRuntime
              ? _npu(preference, hw)
              : _cpu(preference, hw);
        }
        // 其他平台保持 llamadart 原生 auto（Windows 上会选 Vulkan，
        // Android 上由原生库按设备情况在 Vulkan/CPU 间保守选择），
        // 不强制 Vulkan 以免在不支持的机型上加载失败。
        return _autoNative(preference, hw);
      case TtsInferenceDevicePreference.gpu:
        return _gpu(preference, hw);
      case TtsInferenceDevicePreference.cpu:
        return _cpu(preference, hw);
    }
  }

  static ResolvedTtsDevice _cpu(
    TtsInferenceDevicePreference preference,
    TtsHardwareInfo hw,
  ) {
    return ResolvedTtsDevice(
      preference: preference,
      effective: TtsInferenceDevicePreference.cpu,
      gpuBackend: llama.GpuBackend.cpu,
      gpuLayers: 0,
      hardware: hw,
    );
  }

  /// 交给 llamadart / llama.cpp 原生 auto 调度（非高通平台的「自动」）。
  static ResolvedTtsDevice _autoNative(
    TtsInferenceDevicePreference preference,
    TtsHardwareInfo hw,
  ) {
    return ResolvedTtsDevice(
      preference: preference,
      effective: TtsInferenceDevicePreference.auto,
      gpuBackend: llama.GpuBackend.auto,
      gpuLayers: llama.ModelParams.maxGpuLayers,
      hardware: hw,
    );
  }

  static ResolvedTtsDevice _gpu(
    TtsInferenceDevicePreference preference,
    TtsHardwareInfo hw,
  ) {
    // Apple 设备 llamadart 走 Metal；其余平台（Android/Windows/Linux）走
    // Vulkan——这些都是预编译包里确定包含的后端。
    final apple = Platform.isIOS || Platform.isMacOS;
    return ResolvedTtsDevice(
      preference: preference,
      effective: TtsInferenceDevicePreference.gpu,
      gpuBackend: apple ? llama.GpuBackend.metal : llama.GpuBackend.vulkan,
      gpuLayers: llama.ModelParams.maxGpuLayers,
      hardware: hw,
    );
  }

  static ResolvedTtsDevice _npu(
    TtsInferenceDevicePreference preference,
    TtsHardwareInfo hw,
  ) {
    // vendored llamadart 补丁新增的档位：按 ggml 后端注册表 "HTP" 枚举
    // 设备（HTP0…）；设备不存在时由原生侧加载期回退 CPU（见补丁说明）。
    // 全部层卸载到 NPU；不支持的算子（mmproj/conformer/codec 等）llama.cpp
    // 会自动留 CPU。
    return ResolvedTtsDevice(
      preference: preference,
      effective: TtsInferenceDevicePreference.npu,
      gpuBackend: llama.GpuBackend.hexagon,
      gpuLayers: llama.ModelParams.maxGpuLayers,
      hardware: hw,
    );
  }
}
