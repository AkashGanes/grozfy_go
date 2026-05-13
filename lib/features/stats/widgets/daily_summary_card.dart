import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_shell.dart';
import '../models/driver_stats.dart';
import '../providers/stats_providers.dart';

class DailySummaryCard extends ConsumerWidget {
  const DailySummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dailySummaryProvider);
    return GestureDetector(
      onTap: () => Navigator.of(context).pushNamed(AppRoutes.earnings),
      child: FrostCard(
        child: async.when(
          loading: _buildLoading,
          error: (_, _) => _buildEmpty(),
          data: _buildData,
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

  Widget _buildEmpty() => _buildData(DailySummary.empty);

  Widget _buildData(DailySummary summary) {
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
              _formatDuration(summary.dutyHours),
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

  Widget _statCell(IconData icon, String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: AppTheme.oceanBlue),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppTheme.nightBlue,
              fontSize: 15,
            ),
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
    return '${d.inSeconds}s';
  }
}
