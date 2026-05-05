import 'package:flutter/material.dart';

extension AppColors on BuildContext {
  ColorScheme get scheme => Theme.of(this).colorScheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get textPrimary => scheme.onSurface;
  Color get textSecondary => scheme.onSurface.withValues(alpha: 0.6);
  Color get textTertiary => scheme.onSurface.withValues(alpha: 0.5);
  Color get textDisabled => scheme.onSurface.withValues(alpha: 0.4);

  Color get iconMuted => scheme.onSurface.withValues(alpha: 0.4);
  Color get iconSubtle => scheme.onSurface.withValues(alpha: 0.5);

  Color get surface => scheme.surface;
  Color get surfaceMuted => scheme.surface.withValues(alpha: 0.86);
  Color get surfaceContainer => scheme.surfaceContainerHighest;
  Color get fillSubtle => scheme.onSurface.withValues(alpha: 0.05);
  Color get fillMuted => scheme.onSurface.withValues(alpha: 0.08);

  Color get borderSubtle => scheme.onSurface.withValues(alpha: 0.12);
  Color get borderMuted => scheme.onSurface.withValues(alpha: 0.1);
  Color get borderStrong => scheme.onSurface.withValues(alpha: 0.2);

  Color get shadowColor =>
      Colors.black.withValues(alpha: isDark ? 0.25 : 0.06);
}
