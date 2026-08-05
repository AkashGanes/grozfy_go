import 'package:flutter/material.dart';

/// Fixed design tokens for the "My Stats" visual handoff spec — one literal
/// value set per theme (dark/light), taken directly from the two approved
/// mockups. Spacing/sizing is identical between the two specs; only colors
/// (and, in one spot, badge-label font weight and card shadow) differ, so
/// [StatsSpacing] stays theme-agnostic while [StatsTokens] carries the rest.
///
/// Resolved via `context.statsTokens`, keyed off `Theme.of(context).brightness`
/// — the same mechanism the rest of the app already uses (see
/// `context_colors.dart`), so this screen follows the app's global theme
/// rather than breaking from it.
///
/// Deliberately isolated to `features/stats/` — nothing here touches
/// `context_colors.dart`/`app_theme.dart`, so no other screen is affected.
@immutable
class StatsTokens {
  const StatsTokens({
    required this.bgCard,
    required this.cardShadow,
    required this.borderCard,
    required this.borderDivider,
    required this.borderDividerVertical,
    required this.textTitle,
    required this.textValue,
    required this.textSecondary,
    required this.textDisabled,
    required this.blue,
    required this.blueTint,
    required this.green,
    required this.greenTint,
    required this.greenPillText,
    required this.amber,
    required this.amberTint,
    required this.gold,
    required this.goldChipTint,
    required this.goldCardTint,
    required this.goldCardBorder,
    required this.goldLabelText,
    required this.orange,
    required this.orangeChipTint,
    required this.orangeCardTint,
    required this.orangeCardBorder,
    required this.orangeLabelText,
    required this.ringGood,
    required this.ringWarn,
    required this.ringBad,
    required this.ringTrack,
    required this.ringMutedTrack,
    required this.streakDotUnfilled,
    required this.navButtonEnabledBg,
    required this.navButtonDisabledBg,
    required this.navButtonEnabledIcon,
    required this.badgeLabelWeight,
    required this.shimmerHighlight,
  });

  final Color bgCard;
  final List<BoxShadow> cardShadow;
  final Color borderCard;
  final Color borderDivider;
  final Color borderDividerVertical;

  final Color textTitle;
  final Color textValue;
  final Color textSecondary;
  final Color textDisabled;

  final Color blue;
  final Color blueTint;

  final Color green;
  final Color greenTint;
  final Color greenPillText;

  final Color amber;
  final Color amberTint;

  final Color gold;
  final Color goldChipTint;
  final Color goldCardTint;
  final Color goldCardBorder;
  final Color goldLabelText;

  final Color orange;
  final Color orangeChipTint;
  final Color orangeCardTint;
  final Color orangeCardBorder;
  final Color orangeLabelText;

  final Color ringGood;
  final Color ringWarn;
  final Color ringBad;
  final Color ringTrack; // background arc behind an active percentage
  final Color ringMutedTrack; // dashed outline ring when value is null

  final Color streakDotUnfilled;

  final Color navButtonEnabledBg;
  final Color navButtonDisabledBg;
  final Color navButtonEnabledIcon;

  /// Badge labels need extra weight on light backgrounds to stay legible
  /// where the dark theme can rely on lightness alone.
  final FontWeight badgeLabelWeight;

  final Color shimmerHighlight;

  Color ringColorForPercent(double? percent) {
    if (percent == null) return ringMutedTrack;
    if (percent >= 90) return ringGood;
    if (percent >= 70) return ringWarn;
    return ringBad;
  }

  static const StatsTokens dark = StatsTokens(
    bgCard: Color(0xFF14171D),
    cardShadow: [], // dark cards separate from the bg via fill+border alone
    borderCard: Color.fromRGBO(255, 255, 255, 0.06),
    borderDivider: Color.fromRGBO(255, 255, 255, 0.07),
    borderDividerVertical: Color.fromRGBO(255, 255, 255, 0.08),
    textTitle: Color(0xFFF2F3F5),
    textValue: Color(0xFFE7EDFF),
    textSecondary: Color(0xFF9299A6),
    textDisabled: Color(0xFF4A4E57),
    blue: Color(0xFF7FA8FF),
    blueTint: Color.fromRGBO(127, 168, 255, 0.12),
    green: Color(0xFF4ADE80),
    greenTint: Color.fromRGBO(74, 222, 128, 0.12),
    greenPillText: Color(0xFF7FD99A),
    amber: Color(0xFFFBBF24),
    amberTint: Color.fromRGBO(251, 191, 36, 0.12),
    gold: Color(0xFFF5C451),
    goldChipTint: Color.fromRGBO(245, 196, 81, 0.18),
    goldCardTint: Color.fromRGBO(245, 196, 81, 0.08),
    goldCardBorder: Color.fromRGBO(245, 196, 81, 0.22),
    goldLabelText: Color(0xFFC9A668),
    orange: Color(0xFFFB923C),
    orangeChipTint: Color.fromRGBO(251, 146, 60, 0.18),
    orangeCardTint: Color.fromRGBO(251, 146, 60, 0.08),
    orangeCardBorder: Color.fromRGBO(251, 146, 60, 0.22),
    orangeLabelText: Color(0xFFD69A6B),
    ringGood: Color(0xFF4ADE80),
    ringWarn: Color(0xFFFBBF24),
    ringBad: Color(0xFFE24B4A),
    ringTrack: Color.fromRGBO(255, 255, 255, 0.05),
    ringMutedTrack: Color.fromRGBO(255, 255, 255, 0.08),
    streakDotUnfilled: Color.fromRGBO(255, 255, 255, 0.12),
    navButtonEnabledBg: Color.fromRGBO(255, 255, 255, 0.05),
    navButtonDisabledBg: Color.fromRGBO(255, 255, 255, 0.02),
    navButtonEnabledIcon: Color(0xFF9299A6),
    badgeLabelWeight: FontWeight.w400,
    shimmerHighlight: Color.fromRGBO(255, 255, 255, 0.08),
  );

  static const StatsTokens light = StatsTokens(
    bgCard: Color(0xFFFFFFFF),
    cardShadow: [
      BoxShadow(
        color: Color.fromRGBO(15, 23, 42, 0.07),
        blurRadius: 8,
        offset: Offset(0, 2),
      ),
    ],
    borderCard: Color.fromRGBO(15, 23, 42, 0.12),
    borderDivider: Color.fromRGBO(15, 23, 42, 0.1),
    borderDividerVertical: Color.fromRGBO(15, 23, 42, 0.14),
    textTitle: Color(0xFF05070A),
    textValue: Color(0xFF05070A),
    textSecondary: Color(0xFF565E6D),
    textDisabled: Color(0xFFB0B4BC),
    blue: Color(0xFF2454C7),
    blueTint: Color.fromRGBO(36, 84, 199, 0.14),
    green: Color(0xFF0F9D4E),
    greenTint: Color.fromRGBO(15, 157, 78, 0.14),
    greenPillText: Color(0xFF0C7A3E),
    amber: Color(0xFFB96E00),
    amberTint: Color.fromRGBO(185, 110, 0, 0.14),
    gold: Color(0xFFA97B03),
    goldChipTint: Color.fromRGBO(169, 123, 3, 0.2),
    goldCardTint: Color.fromRGBO(169, 123, 3, 0.09),
    goldCardBorder: Color.fromRGBO(169, 123, 3, 0.3),
    goldLabelText: Color(0xFF7A5A02),
    orange: Color(0xFFD2540A),
    orangeChipTint: Color.fromRGBO(210, 84, 10, 0.2),
    orangeCardTint: Color.fromRGBO(210, 84, 10, 0.09),
    orangeCardBorder: Color.fromRGBO(210, 84, 10, 0.3),
    orangeLabelText: Color(0xFF8F4108),
    ringGood: Color(0xFF0F9D4E),
    ringWarn: Color(0xFFB96E00),
    ringBad: Color(0xFFC0342E),
    ringTrack: Color.fromRGBO(15, 23, 42, 0.1),
    ringMutedTrack: Color.fromRGBO(15, 23, 42, 0.1),
    streakDotUnfilled: Color.fromRGBO(15, 23, 42, 0.15),
    navButtonEnabledBg: Color.fromRGBO(15, 23, 42, 0.07),
    navButtonDisabledBg: Color.fromRGBO(15, 23, 42, 0.04),
    navButtonEnabledIcon: Color(0xFF374151),
    badgeLabelWeight: FontWeight.w500,
    shimmerHighlight: Color.fromRGBO(15, 23, 42, 0.08),
  );
}

extension StatsThemeContext on BuildContext {
  StatsTokens get statsTokens =>
      Theme.of(this).brightness == Brightness.dark ? StatsTokens.dark : StatsTokens.light;
}

class StatsSpacing {
  StatsSpacing._();

  static const double cardRadius = 20;
  static const double cardPadding = 18;
  static const double cardGap = 12;

  static const double statChipRadiusSmall = 10; // 34px chips (Today)
  static const double statChipRadiusLarge = 11; // 40px chips (All Time)
  static const double badgeChipRadius = 8; // 28px badge icon chip
  static const double badgeCardRadius = 16;
  static const double badgeCardPadding = 14;

  static const double pillRadius = 999;
  static const double monthNavSize = 26;
  static const double monthNavRadius = 8;
}

/// Theme-independent text metrics (size/weight/letter-spacing) — color comes
/// from [StatsTokens] and is applied by the caller via `.copyWith(color: …)`.
class StatsText {
  StatsText._();

  static const TextStyle todayEyebrow = TextStyle(fontSize: 13, fontWeight: FontWeight.w400);
  static const TextStyle sectionHeader = TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
  static const TextStyle heroNumber =
      TextStyle(fontSize: 44, fontWeight: FontWeight.w500, letterSpacing: -0.5, height: 1.0);
  static const TextStyle heroCaption = TextStyle(fontSize: 13, fontWeight: FontWeight.w400);
  static const TextStyle monthHeadlineNumber = TextStyle(fontSize: 30, fontWeight: FontWeight.w500);
  static const TextStyle monthCaption = TextStyle(fontSize: 12, fontWeight: FontWeight.w400);
  static const TextStyle ringPercent = TextStyle(fontSize: 15, fontWeight: FontWeight.w500);
  static const TextStyle ringSubLabel = TextStyle(fontSize: 9, fontWeight: FontWeight.w400);
  static const TextStyle statPairValueSmall = TextStyle(fontSize: 16, fontWeight: FontWeight.w500);
  static const TextStyle statPairValueLarge = TextStyle(fontSize: 22, fontWeight: FontWeight.w500);
  static const TextStyle statPairLabel = TextStyle(fontSize: 11, fontWeight: FontWeight.w400);
  static const TextStyle badgeValue = TextStyle(fontSize: 17, fontWeight: FontWeight.w500);
  static const TextStyle badgeLabel = TextStyle(fontSize: 11);
  static const TextStyle caption = TextStyle(fontSize: 13, fontWeight: FontWeight.w400);
  static const TextStyle listRowValue = TextStyle(fontSize: 13, fontWeight: FontWeight.w500);
  static const TextStyle onDutyPillText = TextStyle(fontSize: 11, fontWeight: FontWeight.w500);
}

/// 1px horizontal rule used between a hero/headline block and a stat row.
class StatsDivider extends StatelessWidget {
  const StatsDivider({super.key, this.marginTop = 16, this.marginBottom = 16});

  final double marginTop;
  final double marginBottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: marginTop, bottom: marginBottom),
      child: ColoredBox(
        color: context.statsTokens.borderDivider,
        child: const SizedBox(height: 1, width: double.infinity),
      ),
    );
  }
}

/// Hairline vertical rule between two stat-pair columns.
class StatsVerticalDivider extends StatelessWidget {
  const StatsVerticalDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ColoredBox(
        color: context.statsTokens.borderDividerVertical,
        child: const SizedBox(width: 0.5, height: 40),
      ),
    );
  }
}
