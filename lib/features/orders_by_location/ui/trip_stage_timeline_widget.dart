import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/context_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_shell.dart';
import '../model/timing_event.dart';
import '../providers/trip_timeline_provider.dart';

class TripStageTimelineWidget extends ConsumerWidget {
  const TripStageTimelineWidget({super.key, required this.tripName});

  final String tripName;

  static const Map<String, String> _labels = {
    'driver_login': 'Driver Login',
    'driver_logout': 'Driver Logout',
    'trip_accepted': 'Trip Accepted',
    'pickup_reached': 'Pickup Reached',
    'picked_up': 'Picked Up',
    'stop_delivered': 'Stop Delivered',
    'stop_failed': 'Stop Failed',
    'trip_completed': 'Trip Completed',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tripTimelineProvider(tripName));
    return FrostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.timeline_rounded,
                size: 16,
                color: AppTheme.oceanBlue,
              ),
              const SizedBox(width: 8),
              Text(
                'Trip Stage Timeline',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          async.when(
            loading: _buildLoading,
            error: (e, _) => _buildError(context, e),
            data: (result) => _buildContent(context, result),
          ),
        ],
      ),
    );
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

  Widget _buildError(BuildContext context, Object error) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: AppTheme.mango),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error.toString().replaceFirst('Exception: ', ''),
              style: TextStyle(color: context.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, TimelineResult result) {
    return switch (result) {
      TimelineEmpty() => _buildEmpty(context),
      TimelinePending() => _buildPending(context),
      TimelineData(:final events) => _buildTimeline(context, events),
    };
  }

  Widget _buildPending(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.oceanBlue),
          ),
          const SizedBox(width: 8),
          Text(
            'Syncing trip data...',
            style: TextStyle(color: context.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        'No timeline data for this trip yet.',
        style: TextStyle(color: context.textSecondary, fontSize: 12),
      ),
    );
  }

  Widget _buildTimeline(BuildContext context, List<TimingEvent> events) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(events.length, (i) {
        final event = events[i];
        final isLast = i == events.length - 1;
        final duration = isLast
            ? null
            : events[i + 1].eventTime.difference(event.eventTime);
        return _TimelineRow(
          event: event,
          label: _labels[event.eventType] ?? _titleCase(event.eventType),
          duration: duration,
          isLast: isLast,
          dotColor: _dotColor(context, event.eventType),
        );
      }),
    );
  }

  Color _dotColor(BuildContext context, String eventType) {
    if (eventType == 'stop_failed') return context.danger;
    if (eventType == 'trip_completed' || eventType == 'stop_delivered') {
      return context.success;
    }
    return AppTheme.oceanBlue;
  }

  static String _titleCase(String s) {
    return s.replaceAll('_', ' ').split(' ').map((w) {
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1);
    }).join(' ');
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.event,
    required this.label,
    required this.dotColor,
    required this.isLast,
    this.duration,
  });

  final TimingEvent event;
  final String label;
  final Color dotColor;
  final bool isLast;
  final Duration? duration;

  static const double _dotSize = 12;
  static const double _lineWidth = 2;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Left rail: dot + connector line ──────────────────────────────
        SizedBox(
          width: 20,
          child: Column(
            children: [
              Container(
                width: _dotSize,
                height: _dotSize,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Container(
                  width: _lineWidth,
                  height: 44,
                  color: context.borderSubtle,
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        // ── Right content ─────────────────────────────────────────────────
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: context.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      AppDateFormat.time(event.eventTime),
                      style: TextStyle(
                        color: context.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                if (!isLast && duration != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '↓  ${AppDateFormat.duration(duration!)}',
                    style: TextStyle(
                      color: context.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

}
