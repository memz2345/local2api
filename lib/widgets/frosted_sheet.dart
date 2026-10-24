import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:local2api/services/settings_service.dart';
import 'package:local2api/widgets/liquid_glass.dart';

class FrostedSheet extends StatelessWidget {
  final Widget child;

  final BorderRadius borderRadius;

  final double blurSigma;

  final double opacity;

  final Color? color;

  final double stretch;

  const FrostedSheet({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.vertical(top: Radius.circular(24)),
    this.blurSigma = 12.0,
    this.opacity = 0.75,
    this.color,
    this.stretch = 0.3,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final legacyColor = (color ?? cs.surfaceContainerLow).withValues(
      alpha: opacity,
    );
    if (!SettingsService.fragmentRenderingEnabled) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(color: legacyColor, child: child),
        ),
      );
    }
    final radius = borderRadius.topLeft.x;
    return GlassShellStretch(
      stretch: stretch,
      shell: ClipRRect(
        borderRadius: borderRadius,
        child: NaviGlass(
          radius: radius,
          blur: blurSigma,
          child: const SizedBox.expand(),
        ),
      ),
      content: child,
    );
  }
}
