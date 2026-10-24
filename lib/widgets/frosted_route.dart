// lib/widgets/frosted_route.dart
//
// iOS 风格转场路由：
//   - 转场期间「背景雾化压暗」：底层旧页面与滑入中的新页面各盖一层
//     纯色雾化层，透明度共用同一渐变曲线（快起 → 保持 → 平滑归零），
//     只有 Navigator 最上层的 Hero 飞行元素保持清晰；
//   - 雾化程度随转场进度渐变，转场结束后雾化层被移除，页面恢复清晰、
//     无残留渲染开销；
//   - 入场页面从右侧滑入，与 Hero 飞行共用同一 animation，时序天然对齐。
//
// 性能说明：原先旧页用 BackdropFilter、新页用 ImageFiltered 做真模糊，
// 二者在转场期间逐帧 saveLayer + 重光栅化整页，是全 app 最重的单帧开销
// （长列表页转场掉帧明显，ios_push_transition 移除同类实现时已验证）。
// 现改为纯半透明色块雾化：零 saveLayer、零重光栅化，观感从「真模糊」
// 变为「雾化压暗」，与全局 MaterialPageRoute 转场的旧页压暗一致。
import 'package:flutter/material.dart';
import 'package:local2api/services/settings_service.dart';
import 'package:local2api/widgets/hero_gesture_curve.dart';
import 'package:local2api/widgets/predictive_back_detector.dart';

/// 统一 Hero 转场路由工厂：
/// - 设置开启「Hero 转场背景模糊」→ [FrostedHeroRoute]（iOS 风格）
/// - 设置关闭 → 与引入该特性之前完全一致的 [MaterialPageRoute]
///   （平台默认转场 + 经典封面 Hero，无任何模糊/滑动）
///
/// ⚠️ 模糊只在**有 Hero 卡片可放大**（[heroZoom]）时才给：那种转场的主体是
/// 卡片飞成整页，模糊只是配角。没有卡片时（从历史 / 跳转列表 / 消息 / 浏览器
/// 等入口直达视频页或详情页）整屏只剩「蒙一层雾」，页面自己明明在滑入淡入，
/// 观众却只记住那层雾 —— 观感很怪，所以这类入口 [blurSigma] 直接给 0。
Route<T> heroTransitionRoute<T>({
  required Widget page,
  bool heroZoom = false,
  RouteSettings? settings,
}) {
  if (!SettingsService.heroTransitionBlurEnabled) {
    return MaterialPageRoute<T>(settings: settings, builder: (_) => page);
  }
  return FrostedHeroRoute<T>(
    page: page,
    heroZoom: heroZoom,
    blurSigma: heroZoom ? 12.0 : 0.0,
    settings: settings,
  );
}

/// 标记接口：整页路由打开的是「整页内容页」时由页面类实现。
///
/// 当前实现者：**视频页 / 番剧页 / 专栏页**（都是点开就进入全屏沉浸阅读 /
/// 观看的内容页）。
///
/// [IosBackdropScale] 的 iOS 景深缩放（被覆盖页向中心后撤 + 渐隐）只在这类
/// 页面压上来时才生效 —— 打开视频 / 番剧 / 专栏 = iOS 开 App 式的背景后撤，
/// 那是想要的效果；而「设置 → 关于 → 存储」这种普通跳转也把整页缩一下就很怪。
///
/// ⚠️ 名字里的「Immersive」是历史遗留（最初只有视频 / 番剧）。判据是
/// **「这是个整页内容页」**，不是「它是不是播放器」—— 新增同类内容页
/// （长文 / 图集 / 直播回放…）时一起加上；纯工具页（设置 / 关于 / 存储）
/// 坚决不要加。
///
/// 由页面实现标记 + 路由工厂自动识别，而不是在十几个 push 处逐个传参：
/// 打开视频 / 番剧 / 专栏的入口遍布推荐流 / 搜索 / 空间 / 缓存 / 动态 / 评论 /
/// 聊天 / URI 路由，逐个传参既啰嗦又容易漏。
abstract interface class ImmersivePageMarker {}

/// 路由栈上「沉浸播放页」的数量（驱动被覆盖页重算缩放）。
///
/// ⚠️ 由 [FrostedHeroRoute] 的 `didPush` / `dispose` 维护，**不要**改到页面
/// 的 `initState` 上去：那会儿框架正在 build，改 notifier 会让被覆盖页的
/// AnimatedBuilder「setState() called during build」直接抛异常。
/// 路由生命周期这两个时机都不在 build 阶段（与既有 `_releaseProgress()` 同款）。
class ImmersiveRouteDepth {
  ImmersiveRouteDepth._();

  static final ValueNotifier<int> active = ValueNotifier<int>(0);

  static void add() => active.value++;

  static void remove() {
    if (active.value > 0) active.value--;
  }

  /// 测试用：清空计数（避免用例间互相污染）。
  @visibleForTesting
  static void reset() => active.value = 0;
}

/// 「本路由打开的页面是不是沉浸播放页」的计数逻辑，[FrostedHeroRoute] 与
/// [ImmersiveMaterialPageRoute] 共用一份，避免两处 add / remove 各自漂移。
///
/// 计数时机只能是路由生命周期（`didPush` / `dispose`），**不能**挪到页面的
/// `initState`：那会儿框架正在 build，改 [ImmersiveRouteDepth.active] 会让
/// 被覆盖页的 AnimatedBuilder 抛 "setState() called during build"。
mixin _ImmersiveDepthCounted<T> on PageRoute<T> {
  /// 本路由要展示的页面（用来识别 [ImmersivePageMarker]）。
  Widget get immersivePage;

  /// 是否已计入 [ImmersiveRouteDepth]（`didPush` 与 `dispose` 严格配对）。
  bool _depthCounted = false;

  void _claimImmersiveDepth() {
    if (immersivePage is ImmersivePageMarker && !_depthCounted) {
      _depthCounted = true;
      ImmersiveRouteDepth.add();
    }
  }

  /// 不撤销则计数泄漏 → 被覆盖页永久停在缩放态。
  void _releaseImmersiveDepth() {
    if (_depthCounted) {
      _depthCounted = false;
      ImmersiveRouteDepth.remove();
    }
  }
}

/// 少数入口（短视频页 / 历史 / 我的评论）历史上直接构造 [MaterialPageRoute]
/// 打开视频页。用这个同款路由替换，让「沉浸播放页上台」的计数与
/// [heroTransitionRoute] 的入口完全一致 —— 否则从这些入口打开视频页时
/// 背景不会后撤，与从推荐 / 搜索打开观感不一致。
///
/// 转场动画仍是 [MaterialPageRoute] 的平台默认动画，不做任何修改。
class ImmersiveMaterialPageRoute<T> extends MaterialPageRoute<T>
    with _ImmersiveDepthCounted<T> {
  ImmersiveMaterialPageRoute({required Widget page, super.settings})
    : _page = page,
      super(builder: (_) => page);

  final Widget _page;

  @override
  Widget get immersivePage => _page;

  @override
  TickerFuture didPush() {
    _claimImmersiveDepth();
    return super.didPush();
  }

  @override
  void dispose() {
    _releaseImmersiveDepth();
    super.dispose();
  }
}

class FrostedHeroRoute<T> extends PageRouteBuilder<T>
    with _ImmersiveDepthCounted<T> {
  /// 被覆盖页面（底层路由）的 iOS 景深缩放进度（0 = 原状，1 = 完全收缩）。
  ///
  /// PageRouteBuilder 类型的路由不会驱动下方路由的 `secondaryAnimation`
  /// （实测始终停留在 0），因此由本路由在转场期间主动驱动此值，
  /// 供被覆盖页（如搜索页）监听实现「页面向中心缩小」的 iOS 效果。
  static final ValueNotifier<double> backdropProgress = ValueNotifier(0);

  // ── 静态进度驱动：同一时刻只有最上层 FrostedHeroRoute 在转场，
  //    由它独占驱动 backdropProgress。路由生命周期负责抢占，
  //    transitionsBuilder 只作为动画尚未安装时的兜底。 ──
  static Animation<double>? _activeAnimation;
  static AnimationStatusListener? _activeStatusListener;

  // 只有从已完成的入场转场返回时，Hero 才需要一帧完整背景来测量
  // 卡片终点。入场尚未完成就被打断时，背景必须保持当前比例连续恢复。
  static bool _capturePopTargetFrame = false;

  /// 返回转场开始时是否需要保持背景完整一帧。
  static bool get capturePopTargetFrame => _capturePopTargetFrame;

  /// 当前驱动 backdropProgress 的路由动画。
  ///
  /// 供被覆盖页判断「本页是否就是驱动该进度的整页路由」：
  /// - 整页路由（FrostedHeroRoute）自身入场飞行 / 自身弹栈期间
  ///   不叠加背景缩放（避免双重形变）；
  /// - 而被覆盖页在「上方整页路由弹栈」期间 isCurrent 已被框架提前
  ///   置 true（didPopNext 在 pop 起始即派发），需要此信号配合
  ///   backdropProgress > 0 才能识别「正在被返回的整页路由覆盖」，
  ///   从而让背景在返回转场中持续缩放。
  static Animation<double>? get activeAnimation => _activeAnimation;

  /// 动画 tick（transientCallbacks 阶段）回调：更新共享进度。
  ///
  /// 必须在动画阶段更新 notifier——此时把下游监听方（被覆盖页的
  /// AnimatedBuilder）标记为脏是合法的；若在 transitionsBuilder 的
  /// build 阶段直接改 notifier，会触发「setState during build」异常。
  static void _onProgressTick() {
    final animation = _activeAnimation;
    if (animation == null) return;
    final progress = animation.value.clamp(0.0, 1.0);
    if (progress > 0.001) {
      if (backdropProgress.value != progress) {
        backdropProgress.value = progress;
      }
    } else if (backdropProgress.value != 0) {
      backdropProgress.value = 0;
    }
  }

  /// 转场结束（完成 / 路由被移除）时归零：
  /// - completed 归零：避免最上层路由的 animation 停在 1.0 产生残留值，
  ///   污染下一段转场（被覆盖页会瞬间跳到收缩态再展开）；被覆盖页保持
  ///   收缩仅需发生在转场进行中，完成后即可恢复。
  /// - dismissed 归零：兜底，避免残留缩放状态。
  static void _onProgressStatus(AnimationStatus status) {
    if ((status == AnimationStatus.dismissed ||
            status == AnimationStatus.completed) &&
        backdropProgress.value != 0) {
      backdropProgress.value = 0;
    }
    if (status == AnimationStatus.dismissed ||
        status == AnimationStatus.completed) {
      _capturePopTargetFrame = false;
    }
  }

  static void _claimProgress(Animation<double> animation) {
    if (identical(_activeAnimation, animation)) return;

    final oldAnimation = _activeAnimation;
    final oldStatusListener = _activeStatusListener;
    oldAnimation?.removeListener(_onProgressTick);
    if (oldAnimation != null && oldStatusListener != null) {
      oldAnimation.removeStatusListener(oldStatusListener);
    }

    _activeAnimation = animation;
    animation.addListener(_onProgressTick);

    // 旧路由的动画结束时不能清掉新路由的进度。
    late final AnimationStatusListener statusListener;
    statusListener = (status) {
      if (identical(_activeAnimation, animation)) {
        _onProgressStatus(status);
      }
    };
    _activeStatusListener = statusListener;
    animation.addStatusListener(statusListener);
  }

  /// 释放共享进度持有权并把进度归零。
  ///
  /// 路由销毁（dispose）时必须调用：转场进行中路由被直接移除
  /// （removeRoute / replaceRoute / 中断返回）时，其动画不会再触发
  /// completed/dismissed，若不在这里收尾，[backdropProgress] 会永久卡在
  /// 中间值 —— 所有 [IosBackdropScale] 页面（侧边栏内嵌的消息中心等）
  /// 将永久处于「被覆盖」的缩放 + 40% 透明度状态，视觉上整页灰化。
  static void _releaseProgress() {
    final oldAnimation = _activeAnimation;
    final oldStatusListener = _activeStatusListener;
    oldAnimation?.removeListener(_onProgressTick);
    if (oldAnimation != null && oldStatusListener != null) {
      oldAnimation.removeStatusListener(oldStatusListener);
    }
    _activeAnimation = null;
    _activeStatusListener = null;
    if (backdropProgress.value != 0) {
      backdropProgress.value = 0;
    }
  }

  static void _attachProgress(Animation<double> animation) {
    if (identical(_activeAnimation, animation)) return;
    // 被覆盖的旧路由会因 secondaryAnimation 重建并重新走
    // transitionsBuilder。只要当前动画仍在进行，就保持最上层路由的
    // 独占权；新路由会在 didPush/didPop 中先主动抢占。
    final active = _activeAnimation;
    if (active != null &&
        (active.status == AnimationStatus.forward ||
            active.status == AnimationStatus.reverse)) {
      return;
    }
    _claimProgress(animation);
  }

  /// 景深模糊强度（0 = 完全不模糊）。
  ///
  /// 构造参数原本只被 transitionsBuilder 的闭包捕获，这里额外存一份：调用方
  /// （如 `heroTransitionRoute` 工厂、测试）需要确认「这条转场到底模不模糊」。
  final double _blurSigma;
  double get blurSigma => _blurSigma;

  /// 本路由要展示的页面（用来识别 [ImmersivePageMarker]）。
  final Widget _page;

  @override
  Widget get immersivePage => _page;

  FrostedHeroRoute({
    required Widget page,
    double blurSigma = 12.0,

    /// 转场时长（正向/反向一致）。Hero 飞行共用本路由动画，
    /// 因此调慢这里 = 整页放大/缩回卡片的飞行同时变慢。
    super.transitionDuration = const Duration(milliseconds: 500),

    /// iOS 开 App 风格：整个 Hero（如整张卡片）自行放大到全屏，
    /// 入场页面不雾化、不滑动，只对底层旧页面做雾化压暗。
    bool heroZoom = false,

    /// 无 Hero 的「整页放大」入场：页面自身从 0.92 放大到 1.0 并淡入，
    /// 底层同样做景深缩放 + 渐变模糊（与 [heroZoom] 共用背景那一套）。
    /// 用于没有卡片 Hero 的整页路由（如首页搜索栏 → 搜索页）。
    bool childZoom = false,

    /// 「从小矩形飞入放大」的起点（全局坐标，如首页搜索框的屏幕矩形）。
    /// 传入时入场 = 该矩形 → 全屏的几何插值（内容按比例缩放、圆角收敛），
    /// 返回时反向压回该矩形 —— 观感与卡片 Hero 放大到全屏一致，
    /// 但走的是本路由自己的动画，不依赖 Hero 配对（不会被搬 element）。
    Rect? beginRect,

    /// [beginRect] 起点的圆角（默认 12，与卡片圆角一致；搜索框可传更圆的值）。
    double beginRadius = 12.0,
    super.settings,
  }) : _blurSigma = blurSigma,
       _page = page,
       super(
         reverseTransitionDuration: transitionDuration,
         pageBuilder: (context, animation, secondaryAnimation) => page,
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           // 只挂一次监听：动画 tick 阶段驱动 backdropProgress，
           // 避免在 build 阶段修改 notifier（会打脏被覆盖页的
           // AnimatedBuilder，触发 setState during build）。
           _attachProgress(animation);

           // 预测式返回跟手状态。用可变局部变量 + 闭包共享：探测器在手势
           // 开始/结束时 setState 重进本闭包刷新它，内层 AnimatedBuilder
           // 每帧重建时现读，所以曲线切换逐帧生效。
           //
           // 为什么必须线性化：控制器已被手势逐帧 seek，再套 easeOutCubic
           // 会让起手一大段几乎不动。而 commit/cancel 的收尾阶段不能立刻切回
           // 曲线（会从 curve(a) 跳变）—— 框架保证 popGestureInProgress 直到
           // 收尾动画跑完才翻 false，跟着它走天然不会跳。
           var gesturing = false;

           Widget buildContent() {
             // 模糊强度渐变曲线：0 → 峰值(保持) → 0。
             // 反向（返回）时随 animation 自动镜像，同样平滑。
             final sigmaTween = TweenSequence<double>([
               TweenSequenceItem(
                 tween: Tween(
                   begin: 0.0,
                   end: 1.0,
                 ).chain(CurveTween(curve: Curves.easeOut)),
                 weight: 25,
               ),
               TweenSequenceItem(tween: ConstantTween(1.0), weight: 35),
               TweenSequenceItem(
                 tween: Tween(
                   begin: 1.0,
                   end: 0.0,
                 ).chain(CurveTween(curve: Curves.easeIn)),
                 weight: 40,
               ),
             ]);
             // 跟手期间直通（线性），其余时候套缓动曲线
             Animation<double> eased(Curve curve, {Curve? reverseCurve}) {
               if (gesturing) return animation;
               return CurvedAnimation(
                 parent: animation,
                 curve: curve,
                 reverseCurve: reverseCurve,
               );
             }

             return AnimatedBuilder(
               animation: animation,
               builder: (context, _) {
                 // 雾化渐变系数复用原 sigma 曲线（0 → 峰值保持 → 0，
                 // 反向返回时自动镜像）。blurSigma = 0 的入口全程为 0。
                 final fog = blurSigma <= 0
                     ? 0.0
                     : sigmaTween.evaluate(animation);
                 // 旧页面雾化：与 ios_push_transition 的旧页压暗同款
                 // 黑色遮罩、同款峰值（0.40），层级感一致。
                 final oldPageDim = 0.40 * fog;
                 // 入场页面自身的雾化（仅 childZoom / 常规滑入模式）。
                 final childFog = 0.30 * fog;
                 return Stack(
                   fit: StackFit.expand,
                   children: [
                     // 旧页面雾化层：纯色块，不 saveLayer、不重光栅化背景
                     if (oldPageDim > 0.003)
                       IgnorePointer(
                         child: ColoredBox(
                           color: Color.fromRGBO(0, 0, 0, oldPageDim),
                         ),
                       ),
                     if (heroZoom)
                       // iOS 开 App 风格：页面的所有几何变化都交给 Hero。
                       // 不在路由层叠加反向平移，否则打断返回时会让 Hero
                       // 的起点和目标卡片在同一帧发生两次位移。
                       child
                     else if (beginRect != null)
                       // 矩形飞行：整页内容先按全屏尺寸布局，再整体缩放进
                       // 起点矩形里，随着转场放大铺满全屏（圆角同步收敛）。
                       Builder(
                         builder: (context) {
                           final size = MediaQuery.sizeOf(context);
                           final end = Offset.zero & size;
                           final raw = animation.value.clamp(0.0, 1.0);
                           final t = gesturing
                               ? raw
                               : Curves.easeOutCubic.transform(raw);
                           final rect = Rect.lerp(beginRect, end, t) ?? end;
                           return Positioned.fromRect(
                             rect: rect,
                             child: ClipRRect(
                               borderRadius: BorderRadius.circular(
                                 beginRadius * (1 - t),
                               ),
                               child: FittedBox(
                                 fit: BoxFit.fill,
                                 child: SizedBox(
                                   width: size.width,
                                   height: size.height,
                                   child: child,
                                 ),
                               ),
                             ),
                           );
                         },
                       )
                     else if (childZoom)
                       // 无 Hero 的整页放大：页面自己从 0.92 放大到 1.0
                       // 并淡入，返回时反向缩回（与背景景深同一根动画）
                       FadeTransition(
                         opacity: eased(Curves.easeOutCubic),
                         child: ScaleTransition(
                           scale: Tween<double>(begin: 0.92, end: 1.0).animate(
                             eased(
                               Curves.easeOutCubic,
                               reverseCurve: Curves.easeInCubic,
                             ),
                           ),
                           child: childFog > 0.003
                               ? DecoratedBox(
                                   // 入场雾化层：纯色块替代 ImageFiltered
                                   // 真模糊（零重光栅化）
                                   decoration: BoxDecoration(
                                     color: Color.fromRGBO(0, 0, 0, childFog),
                                   ),
                                   child: child,
                                 )
                               : child,
                         ),
                       )
                     else
                       // 常规模式：入场页面淡入 + 滑入；滑入期间自身同样
                       // 处于雾化中，到站后 fog 归零自动恢复清晰
                       FadeTransition(
                         opacity: eased(Curves.easeOutCubic),
                         child: SlideTransition(
                           position:
                               Tween<Offset>(
                                 begin: const Offset(1, 0),
                                 end: Offset.zero,
                               ).animate(
                                 eased(
                                   Curves.easeOutCubic,
                                   reverseCurve: Curves.easeInCubic,
                                 ),
                               ),
                           child: childFog > 0.003
                               ? DecoratedBox(
                                   // 入场雾化层：纯色块替代 ImageFiltered
                                   // 真模糊（零重光栅化）
                                   decoration: BoxDecoration(
                                     color: Color.fromRGBO(0, 0, 0, childFog),
                                   ),
                                   child: child,
                                 )
                               : child,
                         ),
                       ),
                   ],
                 );
               },
             );
           }

           // 预测式返回：Android 14+ 的侧滑手势交给探测器，它把进度转成
           // 本路由控制器进度。Hero 飞行由 HeroController 在
           // didStartUserGesture 时自行启动并跟手，这里不用管。
           final route = ModalRoute.of(context);
           if (route == null) return buildContent();
           return PredictiveBackGestureDetector(
             route: route,
             builder: (_, g) {
               gesturing = g;
               // 让页面里的 Hero 也能感知跟手状态：Hero 飞行动画在框架里
               // 会被套上 Hero.curve，跟手期间必须换成线性（详见
               // hero_gesture_curve.dart 的实测数据）。
               return HeroGestureCurve(linear: g, child: buildContent());
             },
           );
         },
       );

  @override
  TickerFuture didPush() {
    _capturePopTargetFrame = false;
    // 沉浸播放页（视频 / 番剧）上台：被覆盖页据此启用 iOS 景深缩放
    // （普通页面不标记 → 背景保持原样，见 ImmersivePageMarker）。
    _claimImmersiveDepth();
    final result = super.didPush();
    final routeAnimation = animation;
    if (routeAnimation != null) _claimProgress(routeAnimation);
    return result;
  }

  @override
  bool didPop(T? result) {
    // pop 可能发生在 push 尚未完成时，必须立刻把同一个动画的反向进度
    // 交给背景层，不能等到下一次 transitionsBuilder 重建才接管。
    final routeAnimation = animation;
    _capturePopTargetFrame =
        routeAnimation?.status == AnimationStatus.completed;
    if (routeAnimation != null) _claimProgress(routeAnimation);
    return super.didPop(result);
  }

  @override
  void dispose() {
    // 撤销沉浸播放页计数（与 didPush 的 add 配对；不撤销则计数泄漏 →
    // 被覆盖页永久停在缩放态）。
    _releaseImmersiveDepth();
    // 转场中途路由被移除时动画不会走到 completed/dismissed（上面的
    // _onProgressStatus 收不到），必须在这里释放共享进度并归零，
    // 否则 backdropProgress 永久卡在中间值 → 所有 IosBackdropScale
    // 页面永久灰化（详见 _releaseProgress 注释）。
    if (identical(_activeAnimation, animation)) {
      _capturePopTargetFrame = false;
      _releaseProgress();
    }
    super.dispose();
  }
}
