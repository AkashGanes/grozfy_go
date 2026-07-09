import 'package:flutter/material.dart';

/// Theme-driven semantic color tokens. Every widget should read colors from
/// here (or from Theme.of directly) instead of hardcoding black/white/grey.
extension AppColors on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get scheme => Theme.of(this).colorScheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  // Text
  Color get textPrimary => scheme.onSurface;
  Color get textSecondary => scheme.onSurfaceVariant;
  Color get textTertiary => scheme.onSurface.withValues(alpha: 0.5);
  Color get textDisabled => scheme.onSurface.withValues(alpha: 0.4);

  // Icons (muted tints get a lift in dark mode so they don't disappear).
  Color get iconPrimary => scheme.onSurface;
  Color get iconMuted =>
      scheme.onSurface.withValues(alpha: isDark ? 0.55 : 0.4);
  Color get iconSubtle =>
      scheme.onSurface.withValues(alpha: isDark ? 0.65 : 0.5);

  // Surfaces & fills
  Color get surface => scheme.surface;
  Color get surfaceMuted => scheme.surface.withValues(alpha: 0.86);
  Color get surfaceContainer => scheme.surfaceContainerHighest;
  Color get cardColor => theme.cardColor;
  Color get fillSubtle => scheme.onSurface.withValues(alpha: 0.05);
  Color get fillMuted => scheme.onSurface.withValues(alpha: 0.08);

  // Borders & dividers
  Color get borderSubtle => scheme.outlineVariant;
  Color get borderMuted => scheme.onSurface.withValues(alpha: 0.1);
  Color get borderStrong => scheme.outline;
  Color get divider => theme.dividerColor;

  Color get shadowColor =>
      Colors.black.withValues(alpha: isDark ? 0.25 : 0.06);

  // Semantic status colors (foreground + tinted container background).
  Color get success =>
      isDark ? const Color(0xFF43DB8E) : const Color(0xFF118A52);
  Color get successContainer =>
      isDark ? const Color(0xFF14352A) : const Color(0xFFE7F7EE);

  Color get warning =>
      isDark ? const Color(0xFFFFC44D) : const Color(0xFFB45309);
  Color get warningContainer =>
      isDark ? const Color(0xFF3A2E14) : const Color(0xFFFFF4E0);

  Color get danger =>
      isDark ? const Color(0xFFFF8080) : const Color(0xFFB42318);
  Color get dangerContainer =>
      isDark ? const Color(0xFF3A1B1E) : const Color(0xFFFBEAEA);

  Color get info => isDark ? const Color(0xFF82B4FF) : const Color(0xFF2D6CDF);
  Color get infoContainer =>
      isDark ? const Color(0xFF1A2C4F) : const Color(0xFFE5EEFB);
}
