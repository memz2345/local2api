import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local2api/l10n/app_localizations.dart';
import 'package:local2api/services/native_camera_scanner.dart';
import 'package:local2api/widgets/qr_zoom_control.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

/// 扫码核心（Material / miuix 两个扫码页共用）：相机预览 + 相机权限流程 +
/// 全屏扫描线 + 变焦控制。顶栏上的动作按钮由各页面自己摆，经
/// [QrScannerCoreState.switchCamera] / [QrScannerCoreState.pickFromGallery]
/// 全局键调进来；识别到内容通过 [onDetected] 交回页面（页面 pop 带值出去）。
///
/// 识别**不限取景框**：MLKit 分析整幅画面，屏幕任意位置出现二维码都立刻
/// 回调跳转；底部提示文案也按「任意位置」措辞。
///
/// 变焦：进页探测后置镜头（[MobileScannerController.getSupportedLenses]），
/// 有超广角则轮盘 0.6x 起步（0.6–1x 映射到超广角镜头，1–10x 走主摄数字
/// 变焦，跨界自动切镜头），没有则 1x 起步；双指捏合、预览单指滑动
/// （竖屏横滑 / 宽屏竖滑，滑动时调出轮盘）都可控焦。
/// [accentColor] 传当前风格的主题色，给轮盘指针/当前倍率上色。
///
/// 宽屏（width > height，平板横持 / 手机横屏）：预览竖排贴左，右侧留黑；
/// 变焦轮盘从**左边缘**展开（坐标系转 90°），预览滑动改纵向。
///
/// 权限处理分三态：未请求/被拒 → 页面内说明 +「重试」；永久拒绝 → 额外给
/// 「去设置」（permission_handler 的 openAppSettings）；非移动平台没有相机
/// 实现 → 只显示「当前平台不支持」。
class QrScannerCore extends StatefulWidget {
  const QrScannerCore({
    super.key,
    required this.onDetected,
    required this.accentColor,
  });

  final ValueChanged<String> onDetected;

  /// 轮盘指针与当前倍率文字的强调色（Material 主色 / miuix 主色）。
  final Color accentColor;

  @override
  State<QrScannerCore> createState() => QrScannerCoreState();
}

class QrScannerCoreState extends State<QrScannerCore>
    with SingleTickerProviderStateMixin {
  static const double _maxZoom = 10;

  /// 超广角镜头的「原生倍率」（相对主摄约 0.6x，MIUI 同款标法）。
  static const double _ultraWideZoom = 0.6;

  final MobileScannerController _controller = MobileScannerController(
    // 权限批下来再 start，别让插件自己抢跑。
    autoStart: false,
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  /// 变焦控制的实例键：预览滑动要直接带动轮盘（applySwipe）。
  final GlobalKey<QrZoomControlState> _zoomKey = GlobalKey();

  /// 相机权限当前状态；null = 还没问过。批了才渲染镜头。
  PermissionStatus? _permission;

  /// start 阶段的失败信息（相机被占用等）；非空时用说明区兜住，
  /// 不让 unawaited 的异步异常炸穿 zone，也不糊插件默认错误页。
  String? _startError;

  /// 相册识别按钮防抖（选图 + 解码期间再点会叠起两个 picker）。
  bool _pickingGallery = false;

  /// 一次只交一个结果：识别成功后扫码页立即 pop，但退场动画那几百毫秒里
  /// 镜头还开着，可能再吐一枚码。
  bool _handled = false;

  /// 全屏扫描线动画。仅在支持相机的平台上创建 —— `late final` 惰性初始化
  /// 在桌面平台上会「从没 build 过就 dispose」，被迫在 dispose 里创建
  /// ticker 再查 TickerMode，直接炸（deactivated ancestor）。
  AnimationController? _line;

  // ---- 镜头 / 变焦状态 ---------------------------------------------------

  /// 后置镜头类别（normal / wide / zoom，按 35mm 等效焦距分类）。
  /// `wide` 在列 → 设备有超广角，轮盘 0.6x 起步。
  Set<CameraLensType> _rearLenses = const {};

  // ---- Camera2 直连（隐藏广角兜底）--------------------------------------
  //
  // mobile_scanner 走 CameraX，而厂商（vivo 等）把辅助后置镜头从
  // cameraIdList / CameraX 里摘掉了 —— 那边永远看不到广角。Camera2 按 id
  // 直开却是通的（特性读得到、openCamera 成功），所以广角镜头走原生通道，
  // 主摄仍留在 mobile_scanner 上（不动原行为，风险最小）。

  /// 「广角档」候选（有序：优先 0.6x 逻辑多摄头，其次物理超广角）。
  /// 轮盘压到 1x 以下时按顺序试开，一颗失败换下一颗，全失败就回退 1x。
  List<NativeCameraLens> _nativeWideCandidates = const [];

  /// 候选全部开不起来（厂商不放行 / 被占用）→ 轮盘不再显示 0.6x 区间。
  bool _nativeWideDead = false;

  /// 当前跑的是哪套引擎：null = mobile_scanner；非空 = Camera2 直连。
  NativeCameraLens? _nativeLens;

  /// Camera2 会话的取景信息（textureId / 尺寸 / 转正角度）。
  NativeCameraView? _nativeView;

  /// 原生通道的解码广播订阅。
  StreamSubscription<String>? _nativeBarcodes;

  /// 取景画面是否由 Camera2 提供。
  bool get _usingNative => _nativeLens != null && _nativeView != null;

  /// 当前激活的镜头；切超广角要重启相机（插件只给 stop + start 一条路）。
  CameraLensType _activeLens = CameraLensType.normal;

  /// 镜头重启中：丢弃这段时间里的额外切换请求，结束后补一次变焦。
  bool _lensBusy = false;

  /// 当前倍率（轮盘 / 捏合 / 滑动共用）。
  double _zoom = 1;

  /// 当前朝向；前摄没有超广角，变焦控制整体隐藏。
  CameraFacing _facing = CameraFacing.back;

  /// 捏合起点倍率（null = 当前手势不是双指）。
  double? _pinchBase;

  /// 轮盘是否展开（受控：胶囊 / 预览滑动打开，点暗幕 / 超时收起）。
  bool _dialOpen = false;

  /// 预览单指滑动的轴锁定：先判断动的是不是「调焦轴」，锁错轴就忽略。
  _SwipeState _swipeState = _SwipeState.undecided;
  Offset? _swipeLast;

  bool get _supported => Platform.isAndroid || Platform.isIOS;

  bool get _granted =>
      _permission == PermissionStatus.granted ||
      _permission == PermissionStatus.limited;

  bool get _hasUltraWide => _rearLenses.contains(CameraLensType.wide);

  /// 设备上有没有可用的广角（CameraX 报的 + 原生探到的隐藏头）。
  bool get _hasWide =>
      _hasUltraWide ||
      (_nativeWideCandidates.isNotEmpty && !_nativeWideDead);

  /// 当前镜头的变焦下限：轮盘最低 0.6x = 广角档。
  /// 原生镜头按它自己报的 zoomMin（0.6x 逻辑头 / 1x 物理头）压。
  double get _minZoom {
    final lens = _nativeLens;
    if (lens != null) return lens.zoomMin <= 0 ? 1 : lens.zoomMin;
    return (_hasWide && _facing == CameraFacing.back) ? _ultraWideZoom : 1;
  }

  /// 当前镜头的变焦上限：原生镜头按 zoomMax（封到 10x，轮盘标定范围）。
  double get _maxZoomNative {
    final lens = _nativeLens;
    if (lens == null) return _maxZoom;
    return lens.zoomMax <= 1 ? _maxZoom : lens.zoomMax.clamp(1, _maxZoom);
  }

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid || Platform.isIOS) {
      _line = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2200),
      )..repeat(reverse: true);
      _controller.addListener(_onControllerChanged);
      _ensurePermission();
    }
  }

  @override
  void dispose() {
    _line?.dispose();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    // 原生 Camera2 会话：页面走了必须收摊，否则相机一直占着。
    _nativeBarcodes?.cancel();
    _nativeBarcodes = null;
    if (_nativeLens != null) NativeCameraScanner.stop();
    super.dispose();
  }

  /// 前后摄切换会走 controller 的 stop/start，靠状态流同步朝向；
  /// 换朝向后倍率与镜头记忆都作废，回到 1x，轮盘一并收起。
  void _onControllerChanged() {
    final facing = _controller.value.cameraDirection;
    if (facing == CameraFacing.unknown || facing == _facing) return;
    _facing = facing;
    _activeLens = CameraLensType.normal;
    if (mounted) setState(() { _zoom = 1; _dialOpen = false; });
  }

  bool _isBack() => _facing == CameraFacing.back;

  /// 请求相机权限 → 批了就开镜头。被拒时由 [_PermissionGate] 出说明 UI。
  Future<void> _ensurePermission() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    setState(() => _permission = status);
    if (_granted) unawaited(_startCamera());
  }

  /// 开镜头 + 探测后置镜头。start 失败不炸 zone：记下来走说明区；
  /// 镜头探测失败只降级（没有超广角信息 → 轮盘 1x 起步），不遮掉能用的取景。
  Future<void> _startCamera() async {
    try {
      await _controller.start();
    } catch (e) {
      if (!mounted) return;
      setState(() => _startError = '$e');
      return;
    }
    try {
      // 等效焦距分类：wide = 超广角（"0.6x"），zoom = 长焦，normal = 主摄。
      final lenses = await _controller.getSupportedLenses(
        facing: CameraFacing.back,
      );
      if (!mounted) return;
      setState(() => _rearLenses = lenses);
    } catch (_) {
      // 探测不到就当没有超广角。
    }
    // CameraX 看不见的镜头（厂商藏起来的广角）单独探一遍：有就并进
    // 「广角档」候选，轮盘压到 1x 以下时自动按原生 Camera2 直开。
    if (!Platform.isAndroid) return;
    final native = await NativeCameraScanner.lenses();
    if (!mounted || native.isEmpty) return;
    final back = [
      for (final l in native)
        if (!l.isFront) l,
    ];
    // 候选排序：0.6x 逻辑多摄头（zoomMin<1）优先 —— 它能连续变焦；
    // 物理超广角（15mm 这种固定头）排后面兜底。
    final wideCandidates = [
      for (final l in back)
        if (!l.listed && (l.zoomMin < 1 || l.isWide)) l,
    ]..sort((a, b) {
      final aw = a.zoomMin < 1 ? 0 : 1;
      final bw = b.zoomMin < 1 ? 0 : 1;
      return aw != bw ? aw - bw : (a.eq35mm - b.eq35mm);
    });
    setState(() {
      _nativeWideCandidates = wideCandidates;
    });
  }

  /// 切换前后摄像头（mobile_scanner 自己在前后之间翻转）。
  Future<void> switchCamera() async {
    if (!_supported) return _unsupportedAction();
    if (_usingNative) {
      // 原生通道只跑后置（广角），切前后 = 交回 mobile_scanner。
      await _stopNative();
      await _controller.start(cameraDirection: CameraFacing.front);
      return;
    }
    await _controller.switchCamera();
  }

  /// 开某颗原生镜头（Camera2 直连）；返回是否成功。
  /// 成功时按当前 [_zoom] 补一次真实变焦。
  Future<bool> _startNative(NativeCameraLens lens) async {
    final view = await NativeCameraScanner.start(lens.id);
    if (!mounted) return false;
    if (view == null) return false;
    _nativeBarcodes ??= NativeCameraScanner.barcodes.listen((value) {
      if (!_handled) _emit(value);
    });
    setState(() {
      _nativeLens = lens;
      _nativeView = view;
      // 轮盘倍率原样带过去（压在镜头自己的 zoomMin..10x 内）。
      _zoom = _zoom.clamp(_minZoom, _maxZoomNative);
    });
    await NativeCameraScanner.setZoom(_zoom);
    return true;
  }

  Future<void> _stopNative() async {
    await _nativeBarcodes?.cancel();
    _nativeBarcodes = null;
    if (!mounted) return;
    setState(() {
      _nativeLens = null;
      _nativeView = null;
    });
    await NativeCameraScanner.stop();
  }

  /// 把倍率落到相机：超广角区间切超广角镜头，其余主摄数字变焦。
  ///
  /// 倍率 → linear zoom 的换算：主摄按 1–10x 线性（插件不暴露最大数码
  /// 变焦，10x 封顶是轮盘标定）；超广角原生 0.6x，倍率 m 需要 m/0.6 的
  /// 数码变焦，linear ≈ (m/0.6 - 1)（按超广角最大数码 2x 估算）。
  Future<void> _applyZoom(double m) async {
    if (!_supported || !_granted) return;
    final clamped = m.clamp(_minZoom, _nativeLens != null ? _maxZoomNative : _maxZoom);
    setState(() => _zoom = clamped);
    // 原生通道直接下真实变焦倍率（0.6–20x 这种），不用换算成 linear；
    // 但跨过 1x 仍要按滞回规则切镜头（≥1x 回主摄）。
    if (_usingNative) {
      if (_lensFor(clamped) == CameraLensType.normal) {
        final switched = await _ensureLens(CameraLensType.normal);
        if (switched) return; // 切回主摄时已按 _zoom 补过变焦。
      }
      await NativeCameraScanner.setZoom(clamped);
      return;
    }
    if (!_isBack()) {
      // 前摄：没有镜头切换，纯数码变焦。
      await _pushLinearZoom(((clamped - 1) / (_maxZoom - 1)).clamp(0.0, 1.0));
      return;
    }
    final switched = await _ensureLens(_lensFor(clamped));
    if (switched) return; // 重启完成时已按最新 _zoom 补过变焦。
    await _pushLinearZoom(_linearFor(clamped));
  }

  /// 带滞回的镜头选择：跨界抖动不至于反复重启 —— 从超广角回主摄要
  /// 越过 1.0，从主摄进超广角要压过 0.98。
  CameraLensType _lensFor(double m) {
    if (_activeLens == CameraLensType.wide) {
      return m >= 1 ? CameraLensType.normal : CameraLensType.wide;
    }
    return m < 0.98 ? CameraLensType.wide : CameraLensType.normal;
  }

  /// 需要时切镜头；返回是否发生了切换。忙碌期间直接放弃，
  /// 由正在跑的那次切换在完成后按最新 [_zoom] 补变焦。
  ///
  /// - 广角档：优先走原生 Camera2 直开（CameraX 看不见的隐藏头）。
  ///   候选按序试（0.6x 逻辑头 → 物理超广角），**一颗失败换下一颗**；
  ///   全失败就把轮盘收回到 1x 起步（[_nativeWideDead]），不再重试。
  /// - 主摄档：原生 → 交回 mobile_scanner，行为与老版本一致。
  Future<bool> _ensureLens(CameraLensType target) async {
    if (target == _activeLens || _lensBusy) return false;
    _lensBusy = true;
    try {
      if (target == CameraLensType.wide &&
          _nativeWideCandidates.isNotEmpty &&
          !_nativeWideDead) {
        // 先把 mobile_scanner 停掉再开原生：0.6x 逻辑头（physicalIds 含
        // 主摄）和它抢 camera0，两边同时开会把主摄挤掉/开成半死状态
        // —— 之后切回主摄就是黑屏。
        try {
          await _controller.stop();
        } catch (_) {}
        for (final lens in _nativeWideCandidates) {
          if (await _startNative(lens)) {
            _activeLens = CameraLensType.wide;
            return true;
          }
        }
        // 全失败：回退 —— 主摄拉回来、轮盘收回 1x，别留黑屏。
        try {
          await _controller.start(
            cameraDirection: CameraFacing.back,
            cameraLensType: CameraLensType.normal,
          );
          _activeLens = CameraLensType.normal;
        } catch (_) {}
        if (mounted) {
          setState(() {
            _nativeWideDead = true;
            _zoom = _zoom < 1 ? 1 : _zoom;
          });
        }
        return false;
      }

      if (target == CameraLensType.normal && _nativeLens != null) {
        // 从原生广角回主摄：停原生、回 mobile_scanner。
        await _stopNative();
        await _controller.start(
          cameraDirection: CameraFacing.back,
          cameraLensType: CameraLensType.normal,
        );
        _activeLens = CameraLensType.normal;
        await _pushLinearZoom(_linearFor(_zoom));
        return true;
      }

      await _controller.stop();
      await _controller.start(
        cameraDirection: CameraFacing.back,
        cameraLensType: target,
      );
      _activeLens = target;
      await _pushLinearZoom(_linearFor(_zoom));
      return true;
    } catch (_) {
      // 切失败（如镜头被占）就尽力回到主摄，别把取景留在黑屏；
      // 回不来也只能交给 errorBuilder，倍率回调照常走数码变焦。
      try {
        await _stopNative();
        await _controller.start(
          cameraDirection: CameraFacing.back,
          cameraLensType: CameraLensType.normal,
        );
        _activeLens = CameraLensType.normal;
      } catch (_) {}
      return false;
    } finally {
      _lensBusy = false;
    }
  }

  /// 原生取景：Camera2 出来的帧是传感器方向，按原生报的转正角度旋转回来。
  Widget _nativeCamera() {
    final view = _nativeView;
    if (view == null) return const ColoredBox(color: Colors.black);
    return ColoredBox(
      color: Colors.black,
      child: RotatedBox(
        quarterTurns: view.quarterTurns,
        child: Texture(textureId: view.textureId),
      ),
    );
  }

  Future<void> _pushLinearZoom(double t) async {
    try {
      await _controller.setZoomScale(t);
    } catch (_) {
      // 相机恰好被停掉（切镜头/退出页面）时忽略。
    }
  }

  double _linearFor(double m) {
    if (_isBack() && _activeLens == CameraLensType.wide) {
      return ((m / _ultraWideZoom) - 1).clamp(0.0, 1.0);
    }
    return ((m - 1) / (_maxZoom - 1)).clamp(0.0, 1.0);
  }

  /// 相册识别：选一张图交给 MLKit 解码，出码走与实时扫描同一个出口。
  Future<void> pickFromGallery() async {
    if (!_supported) return _unsupportedAction();
    if (_pickingGallery) return;
    _pickingGallery = true;
    final l10n = AppLocalizations.of(context);
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      final capture = await _controller.analyzeImage(picked.path);
      final value = _firstValue(capture);
      if (!mounted) return;
      if (value == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.qrScannerGalleryEmpty)));
        return;
      }
      _emit(value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      _pickingGallery = false;
    }
  }

  void _unsupportedAction() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).qrScannerUnsupported),
      ),
    );
  }

  String? _firstValue(BarcodeCapture? capture) {
    for (final barcode in capture?.barcodes ?? const <Barcode>[]) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  void _onDetect(BarcodeCapture capture) {
    final value = _firstValue(capture);
    if (value != null) _emit(value);
  }

  void _emit(String value) {
    if (_handled) return;
    _handled = true;
    widget.onDetected(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mq = MediaQuery.of(context);
    // 宽屏（平板横持 / 手机横屏）：预览竖排贴左，右侧留黑。
    final isWide = mq.size.width > mq.size.height;
    Rect previewRect = Offset.zero & mq.size;
    if (isWide) {
      final horizontalInset = mq.padding.left + mq.padding.right;
      final width = math.max(
        280.0,
        math.min(mq.size.height * 0.75, mq.size.width - horizontalInset),
      );
      previewRect = Rect.fromLTWH(mq.padding.left, 0, width, mq.size.height);
    }

    final camera = GestureDetector(
      // 双指捏合变焦；单指沿调焦轴滑动也变焦并调出轮盘（轴锁定防误触）。
      onScaleStart: (d) {
        if (d.pointerCount >= 2) {
          _pinchBase = _zoom;
          _swipeState = _SwipeState.undecided;
        } else {
          _pinchBase = null;
          _swipeState = _SwipeState.undecided;
          _swipeLast = d.localFocalPoint;
        }
      },
      onScaleUpdate: (d) {
        if (d.pointerCount >= 2) {
          final base = _pinchBase;
          if (base == null) return;
          unawaited(_applyZoom(base * d.scale));
          return;
        }
        if (_swipeState == _SwipeState.ignore) return;
        final last = _swipeLast;
        if (last == null) return;
        final delta = d.localFocalPoint - last;
        _swipeLast = d.localFocalPoint;
        if (_swipeState == _SwipeState.undecided) {
          if (delta.distance < 8) return;
          final horizontal = delta.dx.abs() >= delta.dy.abs();
          final zoomAxisIsHorizontal = !isWide;
          if (horizontal != zoomAxisIsHorizontal) {
            _swipeState = _SwipeState.ignore;
            return;
          }
          _swipeState = _SwipeState.zoom;
        }
        if (!_isBack() || !_supported || !_granted) return;
        _zoomKey.currentState?.applySwipe(
          isWide ? delta.dy : delta.dx,
          mq.size.shortestSide,
        );
      },
      child: _usingNative ? _nativeCamera() : MobileScanner(
        controller: _controller,
        onDetect: _onDetect,
        // 镜头运行期错误（相机被占用等）也用同一块说明区兜住，
        // 别把插件的默认错误页（黑底红字）怼到脸上。
        errorBuilder: (context, error) => _CenterHint(
          icon: Icons.error_outline,
          title: l10n.qrScannerTitle,
          text: '${error.errorCode}',
        ),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        if (!_supported)
          _CenterHint(
            icon: Icons.qr_code_scanner,
            text: l10n.qrScannerUnsupported,
          )
        else if (!_granted)
          _PermissionGate(status: _permission, onRetry: _ensurePermission)
        else if (_startError != null)
          _CenterHint(
            icon: Icons.error_outline,
            title: l10n.qrScannerTitle,
            text: _startError!,
          )
        else ...[
          // 宽屏时预览右侧的留黑。
          const Positioned.fill(child: ColoredBox(color: Colors.black)),
          Positioned.fromRect(
            rect: previewRect,
            child: ClipRect(child: camera),
          ),
        ],
        // 扫描线与变焦画在镜头之上；权限没批 / 平台不支持时没有镜头，都不出现。
        if (_supported && _granted && _startError == null)
          Positioned.fromRect(
            rect: previewRect,
            child: _ScanOverlay(
              line: _line!,
              accent: widget.accentColor,
              zoom: _zoom,
              hasUltraWide: _hasWide && _isBack(),
              showZoom: _isBack(),
              edge: isWide ? QrDialEdge.left : QrDialEdge.bottom,
              dialOpen: _dialOpen,
              onDialOpenChanged: (v) => setState(() => _dialOpen = v),
              onZoomChanged: (m) => unawaited(_applyZoom(m)),
              zoomKey: _zoomKey,
            ),
          ),
      ],
    );
  }
}

/// 预览单指滑动的轴锁定状态。
enum _SwipeState { undecided, zoom, ignore }

/// 权限说明 / 拒绝后的引导页。
class _PermissionGate extends StatelessWidget {
  const _PermissionGate({required this.status, required this.onRetry});

  final PermissionStatus? status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final permanentlyDenied =
        status == PermissionStatus.permanentlyDenied ||
        status == PermissionStatus.restricted;
    return _CenterHint(
      icon: Icons.no_photography_outlined,
      text: l10n.qrScannerPermissionDesc,
      title: l10n.qrScannerPermissionTitle,
      actions: [
        if (permanentlyDenied)
          _GateButton(
            label: l10n.qrScannerOpenSettings,
            filled: true,
            onPressed: openAppSettings,
          ),
        _GateButton(label: l10n.qrScannerRetry, onPressed: onRetry),
      ],
    );
  }
}

/// 居中的说明块（权限 / 平台不支持共用）。
class _CenterHint extends StatelessWidget {
  const _CenterHint({
    required this.icon,
    required this.text,
    this.title,
    this.actions = const [],
  });

  final IconData icon;
  final String text;
  final String? title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(icon, size: 56, color: Colors.white70),
            const SizedBox(height: 16),
            Text(
              title ?? l10n.qrScannerTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white70,
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 20),
              for (final action in actions)
                Padding(padding: const EdgeInsets.only(top: 8), child: action),
            ],
          ],
        ),
      ),
    );
  }
}

class _GateButton extends StatelessWidget {
  const _GateButton({
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final button = filled
        ? FilledButton(onPressed: onPressed, child: Text(label))
        : OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
            child: Text(label),
          );
    return Center(child: button);
  }
}

/// 取景覆盖层：全屏往复扫描线 + 变焦控制。
///
/// 不再画取景框、不再压暗四周 —— 识别本来就是全画面的，框只会误导用户
/// 把码怼进框里；一条贯穿全屏的扫描线表达「哪里都能扫」。
///
/// [edge] 决定轮盘展开方位：bottom（手机竖屏，胶囊/轮盘在底部中间）或
/// left（宽屏，轮盘从左边缘展开、胶囊留在预览底部）。轮盘展开时铺一层
/// 点击收起的暗幕（对应 MIUI 的 preview_cover_zoom_circle_ruler）。
class _ScanOverlay extends StatelessWidget {
  const _ScanOverlay({
    required this.line,
    required this.accent,
    required this.zoom,
    required this.hasUltraWide,
    required this.showZoom,
    required this.edge,
    required this.dialOpen,
    required this.onDialOpenChanged,
    required this.onZoomChanged,
    required this.zoomKey,
  });

  final Animation<double> line;
  final Color accent;
  final double zoom;
  final bool hasUltraWide;
  final bool showZoom;
  final QrDialEdge edge;
  final bool dialOpen;
  final ValueChanged<bool> onDialOpenChanged;
  final ValueChanged<double> onZoomChanged;
  final GlobalKey<QrZoomControlState> zoomKey;

  @override
  Widget build(BuildContext context) {
    final control = QrZoomControl(
      key: zoomKey,
      value: zoom,
      hasUltraWide: hasUltraWide,
      accent: accent,
      onChanged: onZoomChanged,
      visible: dialOpen,
      onVisibleChanged: onDialOpenChanged,
      edge: edge,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: line,
            builder: (context, _) =>
                CustomPaint(painter: _ScanLinePainter(progress: line.value)),
          ),
        ),
        // 轮盘暗幕：点击任意处收起（淡入淡出）。
        Positioned.fill(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: dialOpen ? 1 : 0,
            child: IgnorePointer(
              ignoring: !dialOpen,
              child: GestureDetector(
                onTap: () => onDialOpenChanged(false),
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
        ),
        if (showZoom && edge == QrDialEdge.bottom)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              minimum: const EdgeInsets.only(bottom: 16),
              child: control,
            ),
          ),
        // 左边缘轮盘：贴预览左边展开，胶囊由 control 自己的 Stack 带着收起。
        if (showZoom && edge == QrDialEdge.left)
          Positioned.fill(
            child: SafeArea(child: control),
          ),
      ],
    );
  }
}

/// 全屏扫描线：一条横向渐隐的亮线从上到下往复扫过整个取景画面。
class _ScanLinePainter extends CustomPainter {
  const _ScanLinePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * (0.10 + 0.80 * progress);
    final rect = Rect.fromLTWH(0, y - 1.5, size.width, 3);
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.75),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ScanLinePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

