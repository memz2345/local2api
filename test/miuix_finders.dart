import 'package:flutter_test/flutter_test.dart';
import 'package:local2api/widgets/miuix/miuix_app_icon.dart';

export 'package:local2api/widgets/miuix/miuix_app_icon.dart' show AppIconNames;

/// 找 miuix 语义图标。
///
/// `MiuixAppIcon` 渲染的是矢量图标（CustomPaint），不是 `Icon` + IconData，
/// 所以不能用 `find.byIcon`；这里按语义名匹配（`AppIconNames` 里的常量）。
Finder miuixIcon(String name) => find.byWidgetPredicate(
      (w) => w is MiuixAppIcon && w.name == name,
    );
