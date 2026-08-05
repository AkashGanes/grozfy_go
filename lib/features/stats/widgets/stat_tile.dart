import 'package:flutter/material.dart';

import 'stats_theme.dart';

/// Small tinted icon chip — the icon itself is tinted, not the whole stat
/// block (unlike the previous tile-per-stat design). Used standalone inside
/// a [StatColumn] or a badge header.
class StatChip extends StatelessWidget {
  const StatChip({
    super.key,
    required this.icon,
    required this.color,
    required this.tint,
    this.size = 34,
    this.iconSize = 16,
    this.radius = StatsSpacing.statChipRadiusSmall,
  });

  final IconData icon;
  final Color color;
  final Color tint;
  final double size;
  final double iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: iconSize, color: color),
    );
  }
}

/// One column of a stat-pair row: icon chip, then value, then label —
/// laid out inside an `Expanded`/`Row` by the caller, with a
/// [StatsVerticalDivider] between two columns.
class StatColumn extends StatelessWidget {
  const StatColumn({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconTint,
    required this.value,
    required this.label,
    this.chipSize = 34,
    this.chipRadius = StatsSpacing.statChipRadiusSmall,
    this.chipIconSize = 16,
    this.valueStyle = StatsText.statPairValueSmall,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconTint;
  final String value;
  final String label;
  final double chipSize;
  final double chipRadius;
  final double chipIconSize;
  final TextStyle valueStyle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.statsTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        StatChip(
          icon: icon,
          color: iconColor,
          tint: iconTint,
          size: chipSize,
          iconSize: chipIconSize,
          radius: chipRadius,
        ),
        const SizedBox(height: 8),
        Text(value, style: valueStyle.copyWith(color: tokens.textValue)),
        const SizedBox(height: 2),
        Text(label, style: StatsText.statPairLabel.copyWith(color: tokens.textSecondary)),
      ],
    );
  }
}
