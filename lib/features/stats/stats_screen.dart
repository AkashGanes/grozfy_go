import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/app_scope.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_shell.dart';
import 'models/driver_stats.dart';
import 'providers/stats_providers.dart';
import 'widgets/badge_chip.dart';
import 'widgets/ring_indicator.dart';
import 'widgets/stat_tile.dart';
import 'widgets/stats_skeleton.dart';
import 'widgets/stats_theme.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppShell(
      title: 'My Stats',
      onRefresh: () async {
        final period = ref.read(selectedMonthProvider);
        try {
          await Future.wait([
            ref.refresh(dailySummaryProvider.future),
            ref.refresh(monthlySummaryProvider(period).future),
            ref.refresh(lifetimeStatsProvider.future),
          ]);
        } catch (_) {
          // Failures already surface via each section's own error branch.
        }
      },
      child: Column(
        children: [
          _DailySection(),
          const SizedBox(height: StatsSpacing.cardGap),
          _MonthlySection(),
          const SizedBox(height: StatsSpacing.cardGap),
          _LifetimeSection(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Shared helpers ───────────────────────────────────────────────────────────

/// Base card surface for all three sections — literal `bg.card`/`border.card`
/// (+ light-mode `card.shadow`) tokens from the handoff spec, not `FrostCard`.
/// This is a purpose-built local widget, not a modification of the shared
/// `FrostCard` (used in ~20 other files) — this screen simply doesn't call
/// `FrostCard` anymore, so nothing elsewhere in the app is affected.
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.statsTokens;
    return Container(
      padding: const EdgeInsets.all(StatsSpacing.cardPadding),
      decoration: BoxDecoration(
        color: tokens.bgCard,
        borderRadius: BorderRadius.circular(StatsSpacing.cardRadius),
        border: Border.all(color: tokens.borderCard),
        boxShadow: tokens.cardShadow,
      ),
      child: child,
    );
  }
}

/// Compact single-row empty state — replaces the old tall, mostly-blank card
/// body that wasted the top of the fold when a section had nothing to show.
Widget _compactEmptyState(
  BuildContext context, {
  required IconData icon,
  required String title,
  String? subtitle,
}) {
  final tokens = context.statsTokens;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: tokens.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: StatsText.caption.copyWith(color: tokens.textSecondary)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: tokens.textDisabled, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _sectionHeader({
  required IconData icon,
  required String label,
  required Color iconColor,
  required TextStyle labelStyle,
  Widget? trailing,
}) {
  return Row(
    children: [
      Icon(icon, size: 16, color: iconColor),
      const SizedBox(width: 6),
      Expanded(child: Text(label, style: labelStyle)),
      ?trailing,
    ],
  );
}

Widget _statusPill(BuildContext context, bool isOnline) {
  final tokens = context.statsTokens;
  final Color bg = isOnline ? tokens.greenTint : tokens.navButtonEnabledBg;
  final Color dot = isOnline ? tokens.green : tokens.textDisabled;
  final Color text = isOnline ? tokens.greenPillText : tokens.textSecondary;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(StatsSpacing.pillRadius),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          isOnline ? 'On duty' : 'Offline',
          style: StatsText.onDutyPillText.copyWith(color: text),
        ),
      ],
    ),
  );
}

Widget _errorText(BuildContext context, Object e) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      e.toString().replaceFirst('Exception: ', ''),
      style: StatsText.caption.copyWith(color: context.statsTokens.textSecondary),
    ),
  );
}

// ── Daily section (hero) ─────────────────────────────────────────────────────

class _DailySection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_DailySection> createState() => _DailySectionState();
}

class _DailySectionState extends ConsumerState<_DailySection> {
  Timer? _ticker;

  // Mirrors DailySummaryCard's pattern: the hero number would otherwise only
  // repaint when some unrelated AppController.notifyListeners() fires, which
  // reads as broken once Duty Hours is the largest number on the page.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isOnline = AppScope.of(context).isOnline;
    if (isOnline && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!isOnline && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final async = ref.watch(dailySummaryProvider);
    final tokens = context.statsTokens;

    final DateTime? onlineSince = app.onlineSince;
    final Duration completed = app.completedDutyToday;
    final Duration live = onlineSince != null
        ? DateTime.now().difference(onlineSince)
        : Duration.zero;
    final Duration dutyHours =
        completed + (live.isNegative ? Duration.zero : live);
    final int tripsToday = app.completedTripsToday;
    final Duration avgTripDuration = app.avgTripDurationToday;

    return _StatsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.today_rounded,
            label: 'Today',
            iconColor: tokens.blue,
            labelStyle: StatsText.todayEyebrow.copyWith(color: tokens.textSecondary),
            trailing: _statusPill(context, app.isOnline),
          ),
          const SizedBox(height: 14),
          async.when(
            loading: () => const HeroStatsSkeleton(),
            error: (e, _) => _errorText(context, e),
            data: (_) => _buildData(
              context,
              dutyHours,
              tripsToday,
              avgTripDuration,
              isLive: onlineSince != null,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 260.ms).slideY(begin: 0.04, end: 0);
  }

  Widget _buildData(
    BuildContext context,
    Duration dutyHours,
    int tripsToday,
    Duration avgTripDuration, {
    required bool isLive,
  }) {
    if (tripsToday == 0 && dutyHours == Duration.zero) {
      return _compactEmptyState(
        context,
        icon: Icons.directions_car_outlined,
        title: 'No activity yet today',
        subtitle: 'Go online to start tracking',
      );
    }
    final tokens = context.statsTokens;
    return Column(
      children: [
        Center(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppDateFormat.duration(dutyHours),
                    style: StatsText.heroNumber.copyWith(color: tokens.textValue),
                  ),
                  if (isLive) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: tokens.green, shape: BoxShape.circle),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Duty hours today',
                style: StatsText.heroCaption.copyWith(color: tokens.textSecondary),
              ),
            ],
          ),
        ),
        const StatsDivider(marginTop: 16, marginBottom: 14),
        Row(
          children: [
            Expanded(
              child: StatColumn(
                icon: Icons.check_circle_outline,
                iconColor: tokens.green,
                iconTint: tokens.greenTint,
                value: '$tripsToday',
                label: 'Trips today',
              ),
            ),
            const StatsVerticalDivider(),
            Expanded(
              child: StatColumn(
                icon: Icons.timer_outlined,
                iconColor: tokens.amber,
                iconTint: tokens.amberTint,
                value: avgTripDuration == Duration.zero
                    ? '—'
                    : AppDateFormat.duration(avgTripDuration),
                label: 'Avg trip',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Monthly section ──────────────────────────────────────────────────────────

class _MonthlySection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_MonthlySection> createState() => _MonthlySectionState();
}

class _MonthlySectionState extends ConsumerState<_MonthlySection> {
  // Last successfully rendered month, kept so switching months cross-fades
  // instead of hard-flashing to a spinner — `.family` providers start a new
  // provider (and a fresh `loading` state) per key, they don't carry data
  // over from whichever month was showing before.
  MonthlySummary? _lastData;

  @override
  Widget build(BuildContext context) {
    final period = ref.watch(selectedMonthProvider);
    final async = ref.watch(monthlySummaryProvider(period));

    ref.listen<AsyncValue<MonthlySummary>>(
      monthlySummaryProvider(period),
      (previous, next) {
        next.whenData((data) {
          if (mounted) setState(() => _lastData = data);
        });
      },
    );

    return _StatsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MonthSelector(period: period),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: 180.ms,
            child: _buildBody(context, async),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 260.ms).slideY(begin: 0.04, end: 0);
  }

  Widget _buildBody(BuildContext context, AsyncValue<MonthlySummary> async) {
    return async.when(
      loading: () {
        if (_lastData != null) {
          return KeyedSubtree(
            key: const ValueKey('monthly-stale'),
            child: Opacity(opacity: 0.45, child: _buildData(context, _lastData!)),
          );
        }
        return const KeyedSubtree(
          key: ValueKey('monthly-skeleton'),
          child: MonthStatsSkeleton(),
        );
      },
      error: (e, _) =>
          KeyedSubtree(key: const ValueKey('monthly-error'), child: _errorText(context, e)),
      data: (s) => KeyedSubtree(
        key: ValueKey('monthly-data-${s.year}-${s.month}'),
        child: _buildData(context, s),
      ),
    );
  }

  Widget _buildData(BuildContext context, MonthlySummary s) {
    if (s.tripsCompleted == 0) {
      return _compactEmptyState(
        context,
        icon: Icons.calendar_today_outlined,
        title: 'No trips in ${AppDateFormat.monthYearFromParts(s.month, s.year)}.',
      );
    }
    final tokens = context.statsTokens;
    final percent = s.onTimePercent;
    final ringColor = tokens.ringColorForPercent(percent);
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${s.tripsCompleted}',
                    style: StatsText.monthHeadlineNumber.copyWith(color: tokens.textValue),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Trips completed',
                    style: StatsText.monthCaption.copyWith(color: tokens.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '${AppDateFormat.duration(s.totalRoadTime)} road time',
                    style: StatsText.monthCaption.copyWith(color: tokens.textSecondary),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                RingIndicator(value: percent, color: ringColor, subLabel: 'on-time'),
                if (percent == null) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 90,
                    child: Text(
                      'No stops recorded yet',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: tokens.textDisabled, fontSize: 9),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        const StatsDivider(),
        Row(
          children: [
            Icon(Icons.timer_outlined, size: 15, color: tokens.amber),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Avg trip duration',
                style: StatsText.caption.copyWith(color: tokens.textSecondary),
              ),
            ),
            Text(
              AppDateFormat.duration(s.avgTripDuration),
              style: StatsText.listRowValue.copyWith(color: tokens.textValue),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Month selector row ────────────────────────────────────────────────────────

class _MonthSelector extends ConsumerWidget {
  const _MonthSelector({required this.period});

  final ({int month, int year}) period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final isCurrentMonth =
        period.month == now.month && period.year == now.year;
    final tokens = context.statsTokens;

    return Row(
      children: [
        Icon(Icons.calendar_month_rounded, size: 16, color: tokens.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            AppDateFormat.monthYearFromParts(period.month, period.year),
            style: StatsText.sectionHeader.copyWith(color: tokens.textTitle),
          ),
        ),
        _monthNavButton(
          context,
          icon: Icons.chevron_left_rounded,
          enabled: true,
          onPressed: () =>
              ref.read(selectedMonthProvider.notifier).state = _prevMonth(period),
        ),
        const SizedBox(width: 8),
        _monthNavButton(
          context,
          icon: Icons.chevron_right_rounded,
          enabled: !isCurrentMonth,
          onPressed: () =>
              ref.read(selectedMonthProvider.notifier).state = _nextMonth(period),
        ),
      ],
    );
  }

  Widget _monthNavButton(
    BuildContext context, {
    required IconData icon,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    final tokens = context.statsTokens;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(StatsSpacing.monthNavRadius),
        child: Container(
          width: StatsSpacing.monthNavSize,
          height: StatsSpacing.monthNavSize,
          decoration: BoxDecoration(
            color: enabled ? tokens.navButtonEnabledBg : tokens.navButtonDisabledBg,
            borderRadius: BorderRadius.circular(StatsSpacing.monthNavRadius),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 14,
            color: enabled ? tokens.navButtonEnabledIcon : tokens.textDisabled,
          ),
        ),
      ),
    );
  }

  static ({int month, int year}) _prevMonth(({int month, int year}) p) {
    if (p.month == 1) return (month: 12, year: p.year - 1);
    return (month: p.month - 1, year: p.year);
  }

  static ({int month, int year}) _nextMonth(({int month, int year}) p) {
    if (p.month == 12) return (month: 1, year: p.year + 1);
    return (month: p.month + 1, year: p.year);
  }
}

// ── Lifetime section ──────────────────────────────────────────────────────────

class _LifetimeSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(lifetimeStatsProvider);
    final tokens = context.statsTokens;

    return _StatsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.all_inclusive_rounded,
            label: 'All time',
            iconColor: tokens.textSecondary,
            labelStyle: StatsText.sectionHeader.copyWith(color: tokens.textTitle),
          ),
          const SizedBox(height: 14),
          async.when(
            loading: () => const LifetimeSkeleton(),
            error: (e, _) => _errorText(context, e),
            data: (s) => _buildData(context, s),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 80.ms, duration: 260.ms).slideY(begin: 0.04, end: 0);
  }

  Widget _buildData(BuildContext context, LifetimeStats s) {
    final tokens = context.statsTokens;
    final bool isEmpty = s.totalTrips == 0;
    final bool hasBestMonth = s.bestMonth != null;
    final bool hasStreak = s.longestStreak > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isEmpty) ...[
          _compactEmptyState(
            context,
            icon: Icons.local_shipping_outlined,
            title: 'No trips yet.',
          ),
          const SizedBox(height: 14),
        ],
        Row(
          children: [
            Expanded(
              child: StatColumn(
                icon: Icons.local_shipping_outlined,
                iconColor: tokens.blue,
                iconTint: tokens.blueTint,
                value: '${s.totalTrips}',
                label: 'Total trips',
                chipSize: 40,
                chipRadius: StatsSpacing.statChipRadiusLarge,
                chipIconSize: 18,
                valueStyle: StatsText.statPairValueLarge,
              ),
            ),
            const StatsVerticalDivider(),
            Expanded(
              child: StatColumn(
                icon: Icons.access_time_rounded,
                iconColor: tokens.blue,
                iconTint: tokens.blueTint,
                value: _fmtHours(s.totalHours),
                label: 'Total hours',
                chipSize: 40,
                chipRadius: StatsSpacing.statChipRadiusLarge,
                chipIconSize: 18,
                valueStyle: StatsText.statPairValueLarge,
              ),
            ),
          ],
        ),
        if (hasBestMonth || hasStreak) ...[
          const StatsDivider(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasBestMonth)
                Expanded(
                  child: BadgeChip.gold(
                    icon: Icons.emoji_events_outlined,
                    label: 'Best month',
                    bottom: Text(
                      s.bestMonth!,
                      style: StatsText.badgeValue.copyWith(color: tokens.textValue),
                    ),
                  ),
                ),
              if (hasBestMonth && hasStreak) const SizedBox(width: 10),
              if (hasStreak)
                Expanded(
                  child: BadgeChip.orange(
                    icon: Icons.local_fire_department_outlined,
                    label: 'Longest streak',
                    bottom: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '${s.longestStreak} day${s.longestStreak == 1 ? '' : 's'}',
                          style: StatsText.badgeValue.copyWith(color: tokens.textValue),
                        ),
                        StreakDotStrip(streak: s.longestStreak),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  static String _fmtHours(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h';
    if (d.inMinutes > 0) return '${d.inMinutes} min';
    return '0h';
  }
}
