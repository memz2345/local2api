import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/widgets/ios_push_transition.dart';

/// 把移植的曲线钉在 miuix-nav 的参考值上：参数一旦被顺手改掉（或者公式
/// 写错一个符号），这些用例会立刻红。
void main() {
  group('miuix-nav 停靠曲线（KernelSU 页面切换同款）', () {
    final curve = MiuixNavSettleCurve();

    test('起点是 0，末帧吸附到 1', () {
      expect(curve.transform(0), 0);
      // 上游 tween 的 transform(1) ≈ 0.99933，末帧把残差拍平成 1
      expect(curve.transform(1), 1);
    });

    test('中段节奏和上游参考点一致：t = 0.2 时约 48%', () {
      // NavSettleEasing 文档里的原话：「a brisk middle (≈48% at a fifth
      // of the duration)」。实测精确值是 0.479383。
      expect(curve.transform(0.2), closeTo(0.4794, 0.001));
      // 几处采样一起钉住整条形状（response 0.8 / damping 0.95 的实算值）
      expect(curve.transform(0.1), closeTo(0.1897, 0.001));
      expect(curve.transform(0.5), closeTo(0.9232, 0.001));
      expect(curve.transform(0.9), closeTo(0.9978, 0.001));
    });

    test('0..1 上单调不回头，不会过冲', () {
      var last = -1.0;
      for (var i = 0; i <= 100; i++) {
        final v = curve.transform(i / 100);
        expect(v, greaterThanOrEqualTo(last), reason: 't = ${i / 100} 处回头了');
        expect(v, inInclusiveRange(0, 1));
        last = v;
      }
    });

    test('转场时长跟上游一致：500ms（PROGRAMMATIC_DURATION_MILLIS）', () {
      expect(
        const IosPushPageTransitionsBuilder().transitionDuration,
        const Duration(milliseconds: 500),
      );
      expect(
        const IosPushPageTransitionsBuilder().reverseTransitionDuration,
        const Duration(milliseconds: 500),
      );
    });

    test('曲线解析导数与数值差分一致（打断交接靠它）', () {
      final h = 1e-5;
      // t = 1 不参与差分：末帧是**故意吸附**到 1 的（见 transformInternal），
      // 那里本来就有一个小跳变，数值差分会炸。
      for (final t in [0.0, 0.1, 0.2, 0.35, 0.5, 0.8, 0.95]) {
        final lo = curve.transform(math.max(0.0, t - h));
        final hi = curve.transform(math.min(1.0, t + h));
        final span = math.min(1.0, t + h) - math.max(0.0, t - h);
        final numeric = (hi - lo) / span;
        expect(
          curve.derivative(t),
          closeTo(numeric, 0.01),
          reason: 't = $t 处导数对不上',
        );
      }
      // 两端都是静止（阶跃响应从静止起、到静止收）
      expect(curve.derivative(0), closeTo(0, 1e-9));
      expect(curve.derivative(1), 0);
    });
  });

  group('miuix-nav 停靠驱动（打断 / 手势交接）', () {
    // raw 恒速：stepSeconds = 0.5 ⇒ raw 以 2/秒 走完 0→1（Flutter
    // AnimationController 的行为，见 MiuixNavSettleDriver 的注释）。
    const stepSeconds = 0.5;
    const rawSpeed = 1 / stepSeconds;
    const dt = 0.02; // 每帧 20ms ⇒ Δraw = 0.04

    /// 从 [from] 恒速走到 [to]，返回沿途采样到的 (raw, value, velocity)。
    List<List<double>> run(
      MiuixNavSettleDriver driver, {
      required double from,
      required double to,
      double t0 = 0,
    }) {
      final out = <List<double>>[];
      final steps = ((to - from).abs() / (rawSpeed * dt)).round();
      for (var i = 1; i <= steps; i++) {
        final raw = from + (to - from) * i / steps;
        final t = t0 + dt * i;
        final v = driver.sample(raw, nowSeconds: t);
        out.add([raw, v, driver.velocity]);
      }
      return out;
    }

    test('静止起步的整步走烘焙曲线（usesProgrammaticCurve 的第一支）', () {
      final driver = MiuixNavSettleDriver(stepSeconds: stepSeconds);
      final curve = MiuixNavSettleCurve();
      // 播种到 raw = 0 的静止状态
      driver.sample(0, nowSeconds: 0);
      final frames = run(driver, from: 0, to: 1);
      for (final f in frames) {
        final raw = f[0];
        expect(
          f[1],
          closeTo(curve.transform(raw), 0.01),
          reason: 'raw = $raw 处没走烘焙曲线',
        );
      }
      expect(frames.last[1], closeTo(1, 1e-9));
      expect(frames.last[2], closeTo(0, 1e-6));
    });

    /// 用一帧「几乎不动」的位移把新 leg 起起来，Δt 配成同样的 raw 速度
    /// （= 1/stepSeconds），于是读到的就是**交接瞬时**的位置/速度 ——
    /// 而不是一帧之后已经变过的值（重阻尼下弹簧一帧内就会掉头，
    /// 参考实现也一样，拿一帧后的值比是比不出连续性的）。
    List<double> handoff(
      MiuixNavSettleDriver driver, {
      required double raw,
      required double dir,
      required double t,
    }) {
      const eps = 1e-4;
      driver.sample(
        raw + eps * dir,
        nowSeconds: t + eps * stepSeconds,
      );
      return [driver.value, driver.velocity];
    }

    test('打断：位置与速度都连续（首导数连续，不顿）', () {
      final driver = MiuixNavSettleDriver(stepSeconds: stepSeconds);
      driver.sample(0, nowSeconds: 0);
      // push 走到 raw = 0.40 就被 pop 打断 —— 前进段只跑到那里，
      // 不能先把整段跑完再回头（那就不是打断了）。
      final forward = run(driver, from: 0, to: 0.40, t0: 0);
      final flipAt = forward.last;
      final t1 = dt * forward.length;

      final h = handoff(
        driver,
        raw: flipAt[0],
        dir: -1,
        t: t1,
      );
      // 位置连续：交接点上不该跳
      expect(h[0], closeTo(flipAt[1], 1e-3), reason: '打断处位置跳了');
      // 速度连续：交接点上速度不跳（这才是「打断不顿」的核心）。
      // 顺带验证惯性：打断前还在往 1 走，交接后瞬时速度仍是正的。
      expect(
        h[1],
        closeTo(flipAt[2], 0.05),
        reason: '打断瞬间速度跳了：${flipAt[2]} → ${h[1]}',
      );
      expect(h[1], greaterThan(0), reason: '惯性没带上');

      // 再正常跑完收尾
      final backward = run(driver, from: flipAt[0], to: 0, t0: t1);
      expect(backward.last[1], closeTo(0, 1e-9));
    });

    test('打断后精确落点，且全程不越过目标', () {
      final driver = MiuixNavSettleDriver(stepSeconds: stepSeconds);
      driver.sample(0, nowSeconds: 0);
      final forward = run(driver, from: 0, to: 0.40, t0: 0);
      final t1 = dt * forward.length;
      final backward = run(driver, from: forward.last[0], to: 0, t0: t1);

      for (final f in backward) {
        expect(f[1], greaterThanOrEqualTo(-1e-9), reason: '越过目标 0 了');
        expect(f[1], lessThanOrEqualTo(1 + 1e-9), reason: '飞出屏幕了');
      }
      // raw 到 0 的那一帧视觉也必须正好到 0 —— Flutter 那边路由就是这一刻
      // 出栈的，晚一点点就会被拆掉硬切。
      expect(backward.last[1], closeTo(0, 1e-9));
      expect(backward.last[2], closeTo(0, 1e-6));
    });

    test('手指拖动 1:1 跟手，松手带速度交接', () {
      final driver = MiuixNavSettleDriver(stepSeconds: stepSeconds);
      driver.sample(1, nowSeconds: 0);
      // 手指从 1 往回拖到 0.6（grab-anchor：首帧落回采样点）
      final drag = <List<double>>[];
      for (var i = 1; i <= 20; i++) {
        final raw = 1 - 0.4 * i / 20;
        final v = driver.sample(raw, fingerDriven: true, nowSeconds: dt * i);
        drag.add([raw, v, driver.velocity]);
      }
      // 1:1：视觉进度跟着 raw 走，每帧步长一致
      for (var i = 1; i < drag.length; i++) {
        expect(
          drag[i][1] - drag[i - 1][1],
          closeTo(drag[i][0] - drag[i - 1][0], 1e-9),
          reason: '跟手不是 1:1',
        );
      }

      // 松手 → 收尾动画往 0 走
      final t1 = dt * 20;
      final h = handoff(driver, raw: drag.last[0], dir: -1, t: t1);
      // 交接处位置/速度都连续（手指的速度被原样带进收尾动画）
      expect(h[0], closeTo(drag.last[1], 1e-3), reason: '松手处位置跳了');
      expect(
        h[1],
        closeTo(drag.last[2], 0.05),
        reason: '松手瞬间速度跳了：${drag.last[2]} → ${h[1]}',
      );

      final settle = run(driver, from: drag.last[0], to: 0, t0: t1);
      // 精确落点
      expect(settle.last[1], closeTo(0, 1e-9));
      // 不越过目标
      for (final f in settle) {
        expect(f[1], greaterThanOrEqualTo(-1e-9));
      }
    });
  });
}