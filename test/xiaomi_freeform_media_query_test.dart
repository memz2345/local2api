import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/widgets/xiaomi_freeform_media_query.dart';

/// 小米 HyperOS2 + Android 15 小窗下 `MediaQuery.padding` 会返回离谱值
/// （flutter#161086）。这组用例钉住兜底逻辑的边界，别顺手改坏。
void main() {
  MediaQueryData mq({
    Size size = const Size(400, 800),
    EdgeInsets padding = EdgeInsets.zero,
    EdgeInsets viewPadding = EdgeInsets.zero,
    EdgeInsets viewInsets = EdgeInsets.zero,
  }) => MediaQueryData(
    size: size,
    padding: padding,
    viewPadding: viewPadding,
    viewInsets: viewInsets,
  );

  group('小米小窗 padding 兜底', () {
    test('正常 inset 原样返回（零开销，不做无谓复制）', () {
      final data = mq(
        padding: const EdgeInsets.only(top: 24, bottom: 48),
        viewPadding: const EdgeInsets.only(top: 24, bottom: 48),
      );
      expect(identical(sanitizeXiaomiFreeformPadding(data), data), isTrue);
    });

    test('小窗下的top离谱值归零，viewPadding 同步修', () {
      // 窗口高 400，却报了个 640 的 top —— 正是 issue 里的现场
      final data = mq(
        size: const Size(600, 400),
        padding: const EdgeInsets.only(top: 640),
        viewPadding: const EdgeInsets.only(top: 737),
      );
      final fixed = sanitizeXiaomiFreeformPadding(data);
      expect(fixed.padding.top, 0);
      expect(fixed.viewPadding.top, 0);
      // 其它轴不动
      expect(fixed.padding.bottom, 0);
      expect(fixed.size, data.size);
    });

    test('bottom 离谱值同样归零', () {
      final data = mq(
        size: const Size(600, 400),
        padding: const EdgeInsets.only(bottom: 500),
        viewPadding: const EdgeInsets.only(bottom: 500),
      );
      final fixed = sanitizeXiaomiFreeformPadding(data);
      expect(fixed.padding.bottom, 0);
      expect(fixed.viewPadding.bottom, 0);
    });

    test('只修异常的那一侧，正常侧保留', () {
      final data = mq(
        size: const Size(600, 400),
        padding: const EdgeInsets.only(top: 640, bottom: 30),
        viewPadding: const EdgeInsets.only(top: 640, bottom: 30),
      );
      final fixed = sanitizeXiaomiFreeformPadding(data);
      expect(fixed.padding.top, 0);
      expect(fixed.padding.bottom, 30);
      expect(fixed.viewPadding.bottom, 30);
    });

    test('恰好等于窗口一半不算异常（判据是「大于」）', () {
      final data = mq(
        size: const Size(600, 400),
        padding: const EdgeInsets.only(top: 200),
      );
      expect(identical(sanitizeXiaomiFreeformPadding(data), data), isTrue);
    });

    test('键盘 viewInsets 不动（那是另一回事，不该被清）', () {
      final data = mq(
        size: const Size(600, 400),
        padding: const EdgeInsets.only(top: 640),
        viewInsets: const EdgeInsets.only(bottom: 300),
      );
      final fixed = sanitizeXiaomiFreeformPadding(data);
      expect(fixed.viewInsets.bottom, 300);
    });

    test('窗口尺寸还没量出来（height <= 0）直接放行', () {
      final data = mq(size: Size.zero, padding: const EdgeInsets.only(top: 640));
      expect(identical(sanitizeXiaomiFreeformPadding(data), data), isTrue);
    });
  });

  testWidgets('包装器把修正后的 MediaQuery 传下去', (tester) async {
    late EdgeInsets seen;
    await tester.pumpWidget(
      MediaQuery(
        data: mq(
          size: const Size(600, 400),
          padding: const EdgeInsets.only(top: 640),
        ),
        child: XiaomiFreeformMediaQuery(
          child: Builder(
            builder: (context) {
              seen = MediaQuery.paddingOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(seen.top, 0);
  });
}
