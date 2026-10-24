import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 列表右侧的 A-Z 索引条（对外模型页「首字母正序」时出现）。
///
/// 触摸 / 拖动时在条左侧浮出一个当前字母气泡，松手即隐；[onSelected] 在
/// 手指划过每个字母时连续回调，页面那边据此把目标分组滚到顶部。
///
/// 两套风格共用这一个实现，配色由调用方注入（Material 走 colorScheme、
/// miuix 走 MiuixColors），所以这里不 import 任何主题包。
class AzIndexBar extends StatefulWidget {
  const AzIndexBar({
    super.key,
    required this.letters,
    required this.onSelected,
    required this.color,
    required this.activeColor,
    this.active,
    this.bubbleColor,
    this.bubbleTextColor,
  });

  /// 数据里实际出现的字母，按顺序排（末尾的 `#` 表示非字母分组）。
  final List<String> letters;

  /// 手指划过命中的字母。
  final ValueChanged<String> onSelected;

  /// 未激活字母的颜色。
  final Color color;

  /// 当前高亮字母的颜色。
  final Color activeColor;

  /// 当前停在哪个字母上（页面根据滚动位置算出来的），null = 不高亮。
  final String? active;

  /// 气泡底色 / 字色；不传则用 [activeColor] + 白色。
  final Color? bubbleColor;
  final Color? bubbleTextColor;

  /// 单个字母槽位的最大高度（字母太多时按可用高度自动压缩）。
  static const double itemHeight = 17.0;

  /// 字母条本身的宽度。
  static const double barWidth = 22.0;

  @override
  State<AzIndexBar> createState() => _AzIndexBarState();
}

class _AzIndexBarState extends State<AzIndexBar> {
  /// 手指是否按在条上（按下时浮气泡）。
  bool _touching = false;

  /// 手指当前命中的字母（气泡里显示的那个）。
  String? _touchLetter;

  /// 本次布局算出的槽位高度，供指针事件换算下标用。
  double _itemH = AzIndexBar.itemHeight;

  /// 总宽度：左侧留给气泡，右侧是字母条。
  static const double _totalWidth = 60;

  void _hit(Offset local, double height) {
    if (height <= 0 || widget.letters.isEmpty) return;
    final total = widget.letters.length * _itemH;
    // 字母条在整块里垂直居中：换算成相对条顶的 y
    final top = (height - total) / 2;
    final i = ((local.dy - top) / _itemH)
        .floor()
        .clamp(0, widget.letters.length - 1);
    final letter = widget.letters[i];
    if (letter == _touchLetter) return;
    setState(() => _touchLetter = letter);
    widget.onSelected(letter);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.letters.isEmpty) return const SizedBox.shrink();
    final active = _touching ? _touchLetter : widget.active;
    final bubbleColor = widget.bubbleColor ?? widget.activeColor;
    final bubbleText = widget.bubbleTextColor ?? Colors.white;

    return SizedBox(
      width: _totalWidth,
      child: LayoutBuilder(
        builder: (context, c) {
          // 字母多、可用高度不够时压缩槽位，绝不溢出。
          final itemH = math.min(
            AzIndexBar.itemHeight,
            c.maxHeight / widget.letters.length,
          );
          _itemH = itemH;
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              setState(() => _touching = true);
              _hit(e.localPosition, c.maxHeight);
            },
            onPointerMove: (e) => _hit(e.localPosition, c.maxHeight),
            onPointerUp: (_) => setState(() {
              _touching = false;
              _touchLetter = null;
            }),
            onPointerCancel: (_) => setState(() {
              _touching = false;
              _touchLetter = null;
            }),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: AzIndexBar.barWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final letter in widget.letters)
                          SizedBox(
                            height: itemH,
                            child: Center(
                              child: Text(
                                letter,
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1,
                                  fontWeight: letter == active
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: letter == active
                                      ? widget.activeColor
                                      : widget.color,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_touching && _touchLetter != null)
                  Positioned(
                    right: AzIndexBar.barWidth + 6,
                    top: (c.maxHeight - 44) / 2,
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: bubbleColor,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _touchLetter!,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: bubbleText,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
