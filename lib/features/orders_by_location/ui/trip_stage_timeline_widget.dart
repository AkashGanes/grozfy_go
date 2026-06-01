import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
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

  static const Color _green = Color(0xFF2E7D32);
  static const Color _red = Color(0xFFB71C1C);

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
              const Text(
                'Trip Stage Timeline',
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
            data: _buildContent,
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

  Widget _buildError(Object error) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: AppTheme.mango),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error.toString().replaceFirst('Exception: ', ''),
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(TimelineResult result) {
    return switch (result) {
      TimelineEmpty() => _buildEmpty(),
      TimelinePending() => _buildPending(),
      TimelineData(:final events) => _buildTimeline(events),
    };
  }

  Widget _buildPending() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.oceanBlue),
          ),
          SizedBox(width: 8),
          Text(
            'Syncing trip data...',
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Text(
        'No timeline data for this trip yet.',
        style: TextStyle(color: Colors.black45, fontSize: 12),
      ),
    );
  }

  Widget _buildTimeline(List<TimingEvent> events) {
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
          dotColor: _dotColor(event.eventType),
        );
      }),
    );
  }

  Color _dotColor(String eventType) {
    if (eventType == 'stop_failed') return _red;
    if (eventType == 'trip_completed' || eventType == 'stop_delivered') {
      return _green;
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
                  color: Colors.black12,
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
                        style: const TextStyle(
                          color: AppTheme.nightBlue,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      AppDateFormat.time(event.eventTime),
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                if (!isLast && duration != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '↓  ${AppDateFormat.duration(duration!)}',
                    style: const TextStyle(
                      color: Colors.black38,
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
