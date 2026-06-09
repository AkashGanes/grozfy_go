import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_routes.dart';
import '../../../core/state/app_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_shell.dart';
import '../models/driver_stats.dart';
import '../providers/stats_providers.dart';

class DailySummaryCard extends ConsumerStatefulWidget {
  const DailySummaryCard({super.key});

  @override
  ConsumerState<DailySummaryCard> createState() => _DailySummaryCardState();
}

class _DailySummaryCardState extends ConsumerState<DailySummaryCard> {
  Timer? _ticker;
  bool _wasOnline = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    final isOnline = app.isOnline;

    if (isOnline && _ticker == null) {
      _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!isOnline && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }

    // Re-fetch completed sessions when driver just went offline.
    if (_wasOnline && !isOnline) {
      ref.invalidate(dailySummaryProvider);
    }
    _wasOnline = isOnline;
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

    return GestureDetector(
      onTap: () => Navigator.of(context).pushNamed(AppRoutes.earnings),
      child: FrostCard(
        child: async.when(
          loading: _buildLoading,
          error: (_, _) => _buildEmpty(app),
          data: (summary) => _buildData(summary, app),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 260.ms)
        .slideY(begin: 0.04, end: 0);
  }

  Widget _buildLoading() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: 14),
        const Center(
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.oceanBlue,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(dynamic app) => _buildData(DailySummary.empty, app);

  Widget _buildData(DailySummary summary, dynamic app) {
    final onlineSince = app.onlineSince as DateTime?;
    final Duration dutyHours;
    if (onlineSince != null) {
      final live = DateTime.now().difference(onlineSince);
      dutyHours = summary.dutyHours + (live.isNegative ? Duration.zero : live);
    } else {
      dutyHours = summary.dutyHours;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: 14),
        Row(
          children: [
            _statCell(
              Icons.access_time_rounded,
              'Duty Hours',
              _formatDuration(dutyHours),
              live: onlineSince != null,
            ),
            _divider(),
            _statCell(
              Icons.local_shipping_outlined,
              'Trips',
              '${summary.tripsCompleted}',
            ),
            _divider(),
            _statCell(
              Icons.timer_outlined,
              'Avg Duration',
              summary.avgTripDuration == Duration.zero
                  ? '—'
                  : _formatDuration(summary.avgTripDuration),
            ),
          ],
        ),
      ],
    );
  }

  Widget _header() {
    return Row(
      children: [
        const Icon(Icons.today_rounded, size: 15, color: AppTheme.oceanBlue),
        const SizedBox(width: 6),
        const Expanded(
          child: Text(
            'Today',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppTheme.nightBlue,
              fontSize: 13,
            ),
          ),
        ),
        const Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: Colors.black38,
        ),
      ],
    );
  }

  Widget _statCell(
    IconData icon,
    String label,
    String value, {
    bool live = false,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: AppTheme.oceanBlue),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.nightBlue,
                  fontSize: 15,
                ),
              ),
              if (live) ...[
                const SizedBox(width: 4),
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1AB36A),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Colors.black45, fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(width: 1, height: 36, color: Colors.black12);
  }

  static String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      final mins = d.inMinutes.remainder(60);
      return '${d.inHours}h ${mins}m';
    }
    if (d.inMinutes > 0) return '${d.inMinutes} min';
    return '< 1 min';
  }
}
