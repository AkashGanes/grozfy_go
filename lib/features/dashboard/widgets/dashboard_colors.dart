import 'package:flutter/material.dart';
import '../../../core/theme/context_colors.dart';

/// Theme-adaptive color tokens shared across dashboard widgets.
/// Delegates to the central theme so dashboard stays in sync with the rest
/// of the app.
class DashColors {
  static Color textPrimary(BuildContext c) => c.textPrimary;

  static Color textSecondary(BuildContext c) => c.textSecondary;

  static Color textTertiary(BuildContext c) => c.textTertiary;

  static Color cardBg(BuildContext c) => c.cardColor;

  static Color cardBorder(BuildContext c) => c.borderSubtle;

  static Color subtleFill(BuildContext c) => c.surfaceContainer;
}
