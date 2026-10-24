// lib/widgets/navi_oval_tab_row.dart
//
// 全站共用的 oval 选项卡行（从 NaviFlash `widgets/navi_oval_tab_row.dart` 移植）：
//   - 椭圆点击区 + 文字 + 底部小胶囊指示条（选中主色加粗）；
//   - 空间够时整组居中，不够时横向可滚（对齐主页顶栏 tab 的行为）；
//   - 可选长按液态玻璃菜单（按住左右滑动切换）。
//
// 为什么需要它：Material 侧「页面级的互斥筛选」（请求日志的全部/通过/失败、
// 用量统计的时间范围）按 NaviFlash 的做法应该进**顶栏自带的 tab 行**
// （`FrostedPageBar.bottom`），而不是像原来那样在内容区浮一排 FilterChip。
// NaviFlash 那边这个 tab 行是搜索页 / 动态页 / 分区页共用的同一个组件，
// 这里同样只留一份实现，别让两个页面各写一套视觉。
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'liquid_glass.dart' show naviGlassAdvanced;
import 'long_press_glass_tab_switcher.dart';

/// 顶栏 tab 行的默认高度（与 NaviFlash `NaviOvalTabRow.height` /
/// `FrostedPageBar.bottomHeight` 的默认值一致）。
const double kNaviOvalTabRowHeight = 44;

/// 由标签列表生成长按玻璃切换器需要的 [GlassTab] 配置（NaviFlash 搜索页同款：
/// 只有文字、无图标）。放在这里是为了让页面不必 import liquid_glass_widgets。
List<GlassTab> naviGlassTabsFromLabels(List<String> labels) => [
  for (final label in labels) GlassTab(label: label),
];

class NaviOvalTabRow extends StatelessWidget {
  /// 选项卡文字（可带计数后缀，如「视频 12.3万」）。
  final List<String> labels;

  final int selectedIndex;

  /// 点击某一项：包含「点击当前项」的情况，由调用方决定是回顶刷新还是切换。
  final ValueChanged<int> onTap;

  /// 长按液态玻璃菜单的配置；为空（或渲染路径不支持着色器）时保持普通选项卡。
  final List<GlassTab>? glassTabs;

  /// 行高（含指示条）。
  final double height;

  const NaviOvalTabRow({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onTap,
    this.glassTabs,
    this.height = kNaviOvalTabRowHeight,
  });

  @override
  Widget build(BuildContext context) {
    // 空间够时整组居中；不够时横向滚动（Center + 横向 ScrollView 组合）
    final row = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < labels.length; i++)
            _NaviOvalTab(
              label: labels[i],
              selected: i == selectedIndex,
              onTap: () => onTap(i),
            ),
        ],
      ),
    );
    // 玻璃切换器要在「着色器真的跑得动」时才挂：软渲染（模拟器）上
    // LiquidGlass 会崩，与底栏/顶栏同一道门槛（见 liquid_glass.dart）。
    final tabs = glassTabs;
    if (tabs == null || tabs.isEmpty || !naviGlassAdvanced) {
      return SizedBox(height: height, child: Center(child: row));
    }
    return LongPressGlassTabSwitcher(
      tabs: tabs,
      selectedIndex: selectedIndex,
      onIndexChanged: onTap,
      barHeight: height - 4,
      child: Center(child: row),
    );
  }
}

/// 单个 oval tab：椭圆 ripple + 文字 + 底部胶囊指示条。
class _NaviOvalTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NaviOvalTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      customBorder: const StadiumBorder(),
      splashColor: cs.primary.withValues(alpha: 0.12),
      highlightColor: cs.primary.withValues(alpha: 0.08),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 文字区固定 19 + 指示器 3 = 22：与主页顶栏的 oval tab 同规格，
          // 这样各处 tab 的垂直位置完全对齐，也与两侧 22px 图标同高。
          SizedBox(
            height: 19,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.0,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected ? cs.primary : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            height: 3,
            width: selected ? 24 : 0,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}
