import 'package:flutter/material.dart';

import 'stats_theme.dart';

enum BadgeVariant { gold, orange }

/// Reward-styled chip for lifetime "callout" stats (Best Month, Longest
/// Streak). Top row is always icon-chip + label; [bottom] is the flexible
/// slot — a plain value `Text` for Best Month, or a value+dot-strip row for
/// Longest Streak. Colors are resolved from [BadgeVariant] at build time
/// (not baked in at construction) so the badge follows the active theme.
class BadgeChip extends StatelessWidget {
  const BadgeChip.gold({
    super.key,
    required this.icon,
    required this.label,
    required this.bottom,
  }) : variant = BadgeVariant.gold;

  const BadgeChip.orange({
    super.key,
    required this.icon,
    required this.label,
    required this.bottom,
  }) : variant = BadgeVariant.orange;

  final IconData icon;
  final String label;
  final BadgeVariant variant;
  final Widget bottom;

  @override
  Widget build(BuildContext context) {
    final tokens = context.statsTokens;
    final bool gold = variant == BadgeVariant.gold;
    final Color iconColor = gold ? tokens.gold : tokens.orange;
    final Color iconChipTint = gold ? tokens.goldChipTint : tokens.orangeChipTint;
    final Color cardTint = gold ? tokens.goldCardTint : tokens.orangeCardTint;
    final Color cardBorder = gold ? tokens.goldCardBorder : tokens.orangeCardBorder;
    final Color labelColor = gold ? tokens.goldLabelText : tokens.orangeLabelText;

    return Container(
      padding: const EdgeInsets.all(StatsSpacing.badgeCardPadding),
      decoration: BoxDecoration(
        color: cardTint,
        borderRadius: BorderRadius.circular(StatsSpacing.badgeCardRadius),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: iconChipTint,
                  borderRadius: BorderRadius.circular(StatsSpacing.badgeChipRadius),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 15, color: iconColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: StatsText.badgeLabel.copyWith(
                    color: labelColor,
                    fontWeight: tokens.badgeLabelWeight,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          bottom,
        ],
      ),
    );
  }
}

/// Visual rendering of a "longest streak" integer as a row of filled/unfilled
/// dots instead of plain text — makes a small number like "2" read as a
/// pattern worth continuing rather than an abstract count. Capped at
/// [maxDots] (default 5, per the handoff spec's suggested default) since a
/// streak is unbounded but the badge card isn't.
class StreakDotStrip extends StatelessWidget {
  const StreakDotStrip({super.key, required this.streak, this.maxDots = 5});

  final int streak;
  final int maxDots;

  @override
  Widget build(BuildContext context) {
    final tokens = context.statsTokens;
    final filled = streak.clamp(0, maxDots);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(maxDots, (i) {
        final isFilled = i < filled;
        return Padding(
          padding: EdgeInsets.only(right: i == maxDots - 1 ? 0 : 4),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isFilled ? tokens.orange : tokens.streakDotUnfilled,
            ),
          ),
        );
      }),
    );
  }
}
