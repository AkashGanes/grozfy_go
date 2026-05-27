import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_shell.dart';
import 'models/driver_stats.dart';
import 'providers/stats_providers.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppShell(
      title: 'My Stats',
      child: Column(
        children: [
          _DailySection(),
          const SizedBox(height: 14),
          _MonthlySection(),
          const SizedBox(height: 14),
          _LifetimeSection(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Daily section ─────────────────────────────────────────────────────────────

class _DailySection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dailySummaryProvider);

    return FrostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.today_rounded, size: 15, color: AppTheme.oceanBlue),
              SizedBox(width: 6),
              Text(
                'Today',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.nightBlue,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          async.when(
            loading: _buildLoading,
            error: (e, _) => _buildError(e),
            data: _buildData,
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 260.ms)
        .slideY(begin: 0.04, end: 0);
  }

  Widget _buildLoading() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppTheme.oceanBlue,
        ),
      ),
    );
  }

  Widget _buildError(Object e) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        e.toString().replaceFirst('Exception: ', ''),
        style: const TextStyle(color: Colors.black54, fontSize: 12),
      ),
    );
  }

  Widget _buildData(DailySummary s) {
    if (s.tripsCompleted == 0 && s.dutyHours == Duration.zero) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'No activity today.',
          style: TextStyle(color: Colors.black45, fontSize: 13),
        ),
      );
    }
    return Row(
      children: [
        _statTile(
          'Duty Hours',
          AppDateFormat.duration(s.dutyHours),
          Icons.access_time_rounded,
          AppTheme.oceanBlue,
        ),
        const SizedBox(width: 10),
        _statTile(
          'Trips Today',
          '${s.tripsCompleted}',
          Icons.check_circle_outline,
          const Color(0xFF2E7D32),
        ),
        const SizedBox(width: 10),
        _statTile(
          'Avg Trip',
          AppDateFormat.duration(s.avgTripDuration),
          Icons.timer_outlined,
          AppTheme.mango,
        ),
      ],
    );
  }

  Widget _statTile(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.nightBlue,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: Colors.black45, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

}

// ── Monthly section ──────────────────────────────────────────────────────────

class _MonthlySection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(selectedMonthProvider);
    final async = ref.watch(monthlySummaryProvider(period));

    return FrostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MonthSelector(period: period),
          const SizedBox(height: 14),
          async.when(
            loading: _buildLoading,
            error: (e, _) => _buildError(e),
            data: _buildData,
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 260.ms)
        .slideY(begin: 0.04, end: 0);
  }

  Widget _buildLoading() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppTheme.oceanBlue,
        ),
      ),
    );
  }

  Widget _buildError(Object e) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        e.toString().replaceFirst('Exception: ', ''),
        style: const TextStyle(color: Colors.black54, fontSize: 12),
      ),
    );
  }

  Widget _buildData(MonthlySummary s) {
    if (s.tripsCompleted == 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'No trips in this month.',
          style: TextStyle(color: Colors.black45, fontSize: 13),
        ),
      );
    }
    return Column(
      children: [
        Row(
          children: [
            _statTile(
              'Trips Completed',
              '${s.tripsCompleted}',
              Icons.check_circle_outline,
              const Color(0xFF2E7D32),
            ),
            const SizedBox(width: 10),
            _statTile(
              'Total Road Time',
              AppDateFormat.duration(s.totalRoadTime),
              Icons.route_outlined,
              AppTheme.oceanBlue,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _statTile(
              'Avg Trip Duration',
              AppDateFormat.duration(s.avgTripDuration),
              Icons.timer_outlined,
              AppTheme.mango,
            ),
            const SizedBox(width: 10),
            _statTile(
              'On-Time Stops',
              s.onTimePercent != null
                  ? '${s.onTimePercent!.toStringAsFixed(0)}%'
                  : '—',
              Icons.verified_outlined,
              AppTheme.oceanBlue,
            ),
          ],
        ),
      ],
    );
  }

  Widget _statTile(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.nightBlue,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: Colors.black45, fontSize: 11),
            ),
          ],
        ),
      ),
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

    return Row(
      children: [
        const Icon(
          Icons.calendar_month_rounded,
          size: 15,
          color: AppTheme.oceanBlue,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            AppDateFormat.monthYearFromParts(period.month, period.year),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppTheme.nightBlue,
              fontSize: 13,
            ),
          ),
        ),
        IconButton(
          onPressed: () => ref
              .read(selectedMonthProvider.notifier)
              .state = _prevMonth(period),
          icon: const Icon(Icons.chevron_left_rounded),
          iconSize: 20,
          color: AppTheme.oceanBlue,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: isCurrentMonth
              ? null
              : () => ref
                  .read(selectedMonthProvider.notifier)
                  .state = _nextMonth(period),
          icon: const Icon(Icons.chevron_right_rounded),
          iconSize: 20,
          color: isCurrentMonth ? Colors.black26 : AppTheme.oceanBlue,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
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

    return FrostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(
                Icons.all_inclusive_rounded,
                size: 15,
                color: AppTheme.oceanBlue,
              ),
              SizedBox(width: 6),
              Text(
                'All Time',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.nightBlue,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          async.when(
            loading: _buildLoading,
            error: (e, _) => _buildError(e),
            data: _buildData,
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(delay: 80.ms, duration: 260.ms)
        .slideY(begin: 0.04, end: 0);
  }

  Widget _buildLoading() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppTheme.oceanBlue,
        ),
      ),
    );
  }

  Widget _buildError(Object e) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        e.toString().replaceFirst('Exception: ', ''),
        style: const TextStyle(color: Colors.black54, fontSize: 12),
      ),
    );
  }

  Widget _buildData(LifetimeStats s) {
    if (s.totalTrips == 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'No trips yet.',
          style: TextStyle(color: Colors.black45, fontSize: 13),
        ),
      );
    }
    return Column(
      children: [
        _row(Icons.local_shipping_outlined, 'Total Trips', '${s.totalTrips}'),
        const SizedBox(height: 10),
        _row(
          Icons.access_time_rounded,
          'Total Hours',
          _fmtHours(s.totalHours),
        ),
        if (s.bestMonth != null) ...[
          const SizedBox(height: 10),
          _row(
            Icons.emoji_events_outlined,
            'Best Month',
            s.bestMonth!,
          ),
        ],
        if (s.longestStreak > 0) ...[
          const SizedBox(height: 10),
          _row(
            Icons.local_fire_department_outlined,
            'Longest Streak',
            '${s.longestStreak} days',
          ),
        ],
      ],
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.oceanBlue),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppTheme.nightBlue,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  static String _fmtHours(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h';
    if (d.inMinutes > 0) return '${d.inMinutes} min';
    return '0h';
  }
}
