import 'package:flutter/material.dart';

/// Theme-adaptive color tokens shared across dashboard widgets.
class DashColors {
  static bool _isDark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;

  static Color textPrimary(BuildContext c) =>
      _isDark(c) ? const Color(0xFFF2F4F7) : const Color(0xFF101828);

  static Color textSecondary(BuildContext c) =>
      _isDark(c) ? const Color(0xFFA4ABB8) : const Color(0xFF667085);

  static Color textTertiary(BuildContext c) =>
      _isDark(c) ? const Color(0xFFB6BDC9) : const Color(0xFF475467);

  static Color cardBg(BuildContext c) =>
      _isDark(c) ? const Color(0xFF1B1E2A) : Colors.white;

  static Color cardBorder(BuildContext c) =>
      _isDark(c) ? const Color(0xFF2A2F3D) : const Color(0xFFE4E7EC);

  static Color subtleFill(BuildContext c) =>
      _isDark(c) ? const Color(0xFF252A38) : const Color(0xFFEEF2F7);
}
