import 'dart:async';
import 'dart:convert';
import 'package:html/parser.dart' show parse;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/navigation/app_routes.dart';
import '../../../core/database/partner_timing_log_dao.dart';
import '../../../core/state/providers.dart';
import 'trip_stage_timeline_widget.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/offline_trip_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_shell.dart';
import '../model/external_delivery.dart';
import '../repository/external_delivery_repository.dart';
import '../../pickup_jobs/model/pickup_job.dart';
import '../../pickup_jobs/repository/pickup_job_repository.dart';
import 'delivery_proof_sheet.dart';
import 'failed_delivery_bottom_sheet.dart';

import 'trip_stop_map_screen.dart';

class ExternalDeliveryTripDetailsScreen extends ConsumerStatefulWidget {
  const ExternalDeliveryTripDetailsScreen({super.key, required this.tripName});

  final String tripName;

  @override
  ConsumerState<ExternalDeliveryTripDetailsScreen> createState() =>
      _ExternalDeliveryTripDetailsScreenState();
}

class _ExternalDeliveryTripDetailsScreenState
    extends ConsumerState<ExternalDeliveryTripDetailsScreen> {
  late Future<ExternalDeliveryTrip> _future;
  static const List<String> _stopStatusOptions = <String>[
    'Pending',
    'Out for Delivery',
    'Delivered',
    'Failed',
    'Cancelled',
  ];
  final Set<String> _updatingStops = <String>{};

  // ── Pickup flow State ──────────────────────────────────────────────────────
  final Map<String, PickupJob> _pickupJobDetails = {};
  bool _fetchingPickupDetails = false;
  // ───────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _future = _loadTrip();
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// Cache-aware trip fetch. Online → fetch + cache; Offline → cache only;
  /// Network error mid-call → flip connectivity flag and serve cache. Only
  /// throws when both network and cache fail.
  Future<ExternalDeliveryTrip> _loadTrip() async {
    if (!ConnectivityService().isConnected) {
      final cached = OfflineTripManager().getCachedTrip(widget.tripName);
      if (cached != null) return cached;
      throw Exception(
        'No internet and no cached copy of this trip. '
        'Open it once online to enable offline access.',
      );
    }
    try {
      final trip = await ExternalDeliveryRepository().fetchTripDetails(
        widget.tripName,
      );

      if (trip.pickupStops.isNotEmpty) {
        unawaited(_fetchPickupDetails(trip));
      }

      ConnectivityService().reportNetworkSuccess();
      // Cache the fresh trip so subsequent offline opens succeed.
      await OfflineTripManager().cacheTrip(trip);
      return trip;
    } catch (e) {
      if (_isNetworkError(e)) {
        ConnectivityService().reportNetworkFailure();
        final cached = OfflineTripManager().getCachedTrip(widget.tripName);
        if (cached != null) return cached;
      }
      rethrow;
    }
  }

  Future<void> _fetchPickupDetails(ExternalDeliveryTrip trip) async {
    if (_fetchingPickupDetails) return;
    setState(() => _fetchingPickupDetails = true);
    try {
      final repo = PickupJobRepository();
      final results = await Future.wait(
        trip.pickupStops.map(
          (ps) => ps.pickupJob.isEmpty
              ? Future.value(null)
              : repo.fetchJob(ps.pickupJob).catchError((_) => null),
        ),
      );
      if (mounted) {
        setState(() {
          for (final job in results.whereType<PickupJob>()) {
            _pickupJobDetails[job.name] = job;
          }
          _fetchingPickupDetails = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _fetchingPickupDetails = false);
    }
  }

  bool _isNetworkError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('socketexception') ||
        s.contains('network is unreachable') ||
        s.contains('failed host lookup') ||
        s.contains('connection failed') ||
        s.contains('connection refused') ||
        s.contains('connection closed') ||
        s.contains('timed out') ||
        s.contains('clientexception');
  }

  String _valueOrDash(String value) => value.trim().isEmpty ? '-' : value;

  String _displayValue(dynamic value) {
    if (value == null) return '-';
    if (value is String) return _valueOrDash(value);
    if (value is num || value is bool) return '$value';
    if (value is List || value is Map) {
      return const JsonEncoder.withIndent('  ').convert(value);
    }
    return '$value';
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return AppShell(
      title: 'External Delivery Trip',
      subtitle: widget.tripName,
      scrollable: false,
      child: FutureBuilder<ExternalDeliveryTrip>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _loadingView();
          }

          if (snapshot.hasError) {
            return Center(
              child: FrostCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 42,
                      color: AppTheme.mango,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      snapshot.error.toString().replaceFirst('Exception: ', ''),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _future = _loadTrip();
                        });
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final trip = snapshot.data!;
          return DefaultTabController(
            length: 3,
            child: Column(
              children: [
                _tripIdentityHeader(trip)
                    .animate()
                    .fadeIn(duration: 220.ms)
                    .slideY(begin: 0.04, end: 0),
                const SizedBox(height: 10),
                TabBar(
                      indicatorColor: scheme.primary,
                      labelColor: scheme.primary,
                      unselectedLabelColor: scheme.onSurface.withValues(
                        alpha: 0.6,
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(
                          icon: Icon(Icons.local_shipping_outlined, size: 18),
                          text: 'Trip',
                        ),
                        Tab(
                          icon: Icon(Icons.route_outlined, size: 18),
                          text: 'Stops',
                        ),
                        Tab(
                          icon: Icon(Icons.summarize_outlined, size: 18),
                          text: 'Summary',
                        ),
                      ],
                    )
                    .animate()
                    .fadeIn(delay: 60.ms, duration: 220.ms)
                    .slideY(begin: 0.04, end: 0)
                    .shimmer(
                      delay: 320.ms,
                      duration: 900.ms,
                      color: AppTheme.oceanBlue.withValues(alpha: 0.12),
                    ),
                const SizedBox(height: 12),
                Expanded(
                  child: TabBarView(
                    children: [
                      _tripTab(trip),
                      _stopsTab(trip),
                      _summaryTab(trip),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _summaryTab(ExternalDeliveryTrip trip) {
    final remaining = (trip.totalStops - trip.completedStops).clamp(
      0,
      trip.totalStops,
    );
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FrostCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Trip Statistics',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.nightBlue,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _statBox(
                          'Total',
                          '${trip.totalStops}',
                          Icons.route_outlined,
                          AppTheme.oceanBlue,
                        ),
                        const SizedBox(width: 8),
                        _statBox(
                          'Done',
                          '${trip.completedStops}',
                          Icons.check_circle_outline,
                          const Color(0xFF2E7D32),
                        ),
                        const SizedBox(width: 8),
                        _statBox(
                          'Left',
                          '$remaining',
                          Icons.pending_outlined,
                          AppTheme.mango,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: trip.totalStops > 0
                            ? trip.completedStops / trip.totalStops
                            : 0,
                        backgroundColor: Colors.black12,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          trip.completedStops >= trip.totalStops &&
                                  trip.totalStops > 0
                              ? const Color(0xFF2E7D32)
                              : AppTheme.oceanBlue,
                        ),
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Progress',
                          style: TextStyle(fontSize: 11, color: Colors.black45),
                        ),
                        Text(
                          '${trip.completedStops}/${trip.totalStops} stops',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    if (trip.totalDistanceKm > 0) ...[
                      const SizedBox(height: 14),
                      const Divider(height: 1, color: Colors.black12),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(
                            Icons.route_outlined,
                            size: 16,
                            color: AppTheme.oceanBlue,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Total Distance',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Text(
                            '${trip.totalDistanceKm.toStringAsFixed(1)} km',
                            style: const TextStyle(
                              color: AppTheme.nightBlue,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (trip.startedAt.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(
                            Icons.play_circle_outline,
                            size: 16,
                            color: AppTheme.oceanBlue,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Started',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Text(
                            trip.startedAt,
                            style: const TextStyle(
                              color: AppTheme.nightBlue,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (trip.completedAt.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(
                            Icons.stop_circle_outlined,
                            size: 16,
                            color: Color(0xFF2E7D32),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Completed',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Text(
                            trip.completedAt,
                            style: const TextStyle(
                              color: AppTheme.nightBlue,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              )
              .animate()
              .fadeIn(delay: 60.ms, duration: 260.ms)
              .slideY(begin: 0.05, end: 0)
              .scale(
                begin: const Offset(0.98, 0.98),
                end: const Offset(1, 1),
                duration: 280.ms,
                curve: Curves.easeOutCubic,
              ),
          const SizedBox(height: 12),
          TripStageTimelineWidget(tripName: trip.name)
              .animate()
              .fadeIn(delay: 120.ms, duration: 260.ms)
              .slideY(begin: 0.05, end: 0),
        ],
      ),
    );
  }

  Widget _tripTab(ExternalDeliveryTrip trip) {
    final driver = _displayValue(trip.rawFields['driver']);
    final tripDate = _displayValue(trip.rawFields['trip_date']);
    final status = _displayValue(trip.rawFields['status']);
    final remaining = (trip.totalStops - trip.completedStops).clamp(
      0,
      trip.totalStops,
    );

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          FrostCard(
                child: Column(
                  children: [
                    _tripInfoRow(Icons.person_outline, 'Driver', driver),
                    _tripInfoRow(
                      Icons.calendar_month_outlined,
                      'Trip Date',
                      tripDate,
                    ),
                    _tripInfoRow(Icons.flag_outlined, 'Status', status),
                  ],
                ),
              )
              .animate()
              .fadeIn(delay: 60.ms, duration: 260.ms)
              .slideY(begin: 0.05, end: 0)
              .scale(
                begin: const Offset(0.98, 0.98),
                end: const Offset(1, 1),
                duration: 280.ms,
                curve: Curves.easeOutCubic,
              ),
          if (trip.totalStops > 0) ...[
            const SizedBox(height: 10),
            FrostCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Stops Progress',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.nightBlue,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _statBox(
                            'Total',
                            '${trip.totalStops}',
                            Icons.route_outlined,
                            AppTheme.oceanBlue,
                          ),
                          const SizedBox(width: 8),
                          _statBox(
                            'Done',
                            '${trip.completedStops}',
                            Icons.check_circle_outline,
                            const Color(0xFF2E7D32),
                          ),
                          const SizedBox(width: 8),
                          _statBox(
                            'Left',
                            '$remaining',
                            Icons.pending_outlined,
                            AppTheme.mango,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: trip.totalStops > 0
                              ? trip.completedStops / trip.totalStops
                              : 0,
                          backgroundColor: Colors.black12,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            trip.completedStops >= trip.totalStops
                                ? const Color(0xFF2E7D32)
                                : AppTheme.oceanBlue,
                          ),
                          minHeight: 8,
                        ),
                      ),
                    ],
                  ),
                )
                .animate()
                .fadeIn(delay: 120.ms, duration: 260.ms)
                .slideY(begin: 0.05, end: 0),
          ],
        ],
      ),
    );
  }

  Widget _loadingView() {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    Widget line({double widthFactor = 1}) {
      return FractionallySizedBox(
        widthFactor: widthFactor,
        child: Container(
          height: 12,
          decoration: BoxDecoration(
            color: AppTheme.oceanBlue.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }

    return Column(
      children: [
        Container(
              height: 44,
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(12),
              ),
            )
            .animate(onPlay: (controller) => controller.repeat())
            .shimmer(
              duration: 1100.ms,
              color: AppTheme.oceanBlue.withValues(alpha: 0.18),
            ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              children: [
                FrostCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      line(widthFactor: 0.42),
                      const SizedBox(height: 14),
                      line(),
                      const SizedBox(height: 10),
                      line(widthFactor: 0.9),
                      const SizedBox(height: 10),
                      line(widthFactor: 0.75),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                FrostCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      line(widthFactor: 0.35),
                      const SizedBox(height: 14),
                      line(widthFactor: 0.95),
                      const SizedBox(height: 10),
                      line(widthFactor: 0.82),
                      const SizedBox(height: 10),
                      line(widthFactor: 0.68),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.03, end: 0);
  }

  Widget _tripIdentityHeader(ExternalDeliveryTrip trip) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return FrostCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.oceanBlue.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.local_shipping_outlined,
              size: 18,
              color: AppTheme.oceanBlue,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Trip ID: ${trip.name}',
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tripInfoRow(IconData icon, String label, String value) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppTheme.oceanBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: AppTheme.oceanBlue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _returningToStore = false;

  Widget _returnTripBanner(ExternalDeliveryTrip trip) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final alreadyCompleted =
        trip.status.trim().toLowerCase() == 'completed' ||
        trip.stops.every((s) => s.status.trim().toLowerCase() == 'delivered');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: alreadyCompleted
            ? const Color(0xFF2E7D32).withValues(alpha: 0.08)
            : AppTheme.mango.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: alreadyCompleted
              ? const Color(0xFF2E7D32).withValues(alpha: 0.3)
              : AppTheme.mango.withValues(alpha: 0.4),
        ),
      ),
      child: alreadyCompleted
          ? const Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: Color(0xFF2E7D32),
                  size: 20,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Package returned to store successfully.',
                    style: TextStyle(
                      color: Color(0xFF2E7D32),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.undo_rounded,
                      color: AppTheme.mango,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Return Trip',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Once you arrive at the store, confirm the package has been handed back.',
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: _returningToStore
                      ? const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppTheme.oceanBlue,
                            ),
                          ),
                        )
                      : ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.oceanBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.store_outlined, size: 18),
                          label: const Text(
                            'Returned to Store',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          onPressed: () => _handleReturnedToStore(trip),
                        ),
                ),
              ],
            ),
    );
  }

  Future<void> _handleReturnedToStore(ExternalDeliveryTrip trip) async {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.store_outlined, color: AppTheme.oceanBlue),
            const SizedBox(width: 8),
            Text(
              'Returned to Store?',
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Text(
          'Confirm that you have handed the package back to the store.',
          style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.oceanBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // markReturnedToStore is a multi-step flow that mutates several docs
    // (stop status, parent trip status, completes_stops counter, completed_at
    // stamp). It can't run offline cleanly — gate it.
    if (!ConnectivityService().isConnected) {
      showInfoSnack(
        context,
        'You are offline. Mark each stop Returned individually, '
        'or try again when back online.',
      );
      return;
    }

    setState(() => _returningToStore = true);
    try {
      await ExternalDeliveryRepository().markReturnedToStore(trip: trip);
      _writeTimingEvent(
        eventType: TimingEventType.tripCompleted,
        tripRef: trip.name.isEmpty ? null : trip.name,
      );
      if (!mounted) return;
      showInfoSnack(context, 'Order marked Returned. Trip completed.');
      setState(() {
        _future = _loadTrip();
      });
    } catch (e) {
      if (!mounted) return;
      showInfoSnack(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _returningToStore = false);
    }
  }

  Widget _stopsTab(ExternalDeliveryTrip trip) {
    // Combine all stops (delivery and pickup) into a single ordered list
    final List<dynamic> allStops = [...trip.stops, ...trip.pickupStops];

    // Sort by stop number
    allStops.sort((a, b) {
      final int stopA = (a is ExternalDeliveryTripStop)
          ? a.stop
          : (a as PickupTripStop).stop;
      final int stopB = (b is ExternalDeliveryTripStop)
          ? b.stop
          : (b as PickupTripStop).stop;
      return stopA.compareTo(stopB);
    });

    final ColorScheme scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          if (trip.isReturnTrip) ...[
            _returnTripBanner(trip),
            const SizedBox(height: 10),
          ],
          if (allStops.isEmpty)
            FrostCard(
              child: Text(
                'No stops found',
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            )
          else
            ...allStops.map((stop) {
              if (stop is ExternalDeliveryTripStop) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FrostCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _stopHeader(stop),
                        const SizedBox(height: 12),
                        _stopInfoCard(stop),
                        if (_isStopEditable(
                          tripStatus: trip.status,
                          stopStatus: stop.status,
                        )) ...[
                          const SizedBox(height: 12),
                          const Divider(height: 1, color: Colors.black12),
                          const SizedBox(height: 10),
                          _stopActionButtons(trip, stop),
                        ],
                      ],
                    ),
                  ),
                );
              } else if (stop is PickupTripStop) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _pickupStopCard(trip, stop),
                );
              }
              return const SizedBox.shrink();
            }),
        ],
      ),
    );
  }

  Widget _pickupStopCard(ExternalDeliveryTrip trip, PickupTripStop ps) {
    final statusNorm = ps.status.trim().toLowerCase();
    final Color statusColor;
    switch (statusNorm) {
      case 'received at store':
        statusColor = const Color(0xFF2E7D32);
      case 'picked up':
        statusColor = AppTheme.oceanBlue;
      case 'failed':
        statusColor = Colors.red;
      default:
        statusColor = AppTheme.mango;
    }

    final isTerminal =
        statusNorm == 'received at store' || statusNorm == 'failed';
    final jobDetail = _pickupJobDetails[ps.pickupJob];

    final cleanCustomer = _parseHtml(ps.customerName);
    final cleanPickupAddress = _parseHtml(ps.pickupAddress);

    return FrostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(
                Icons.inventory_2_outlined,
                size: 16,
                color: AppTheme.oceanBlue,
              ),
              const SizedBox(width: 6),
              Text(
                'Pickup stop ${ps.stop}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.nightBlue,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.30),
                  ),
                ),
                child: Text(
                  ps.status.isEmpty ? 'Pending' : ps.status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Details section
          if (cleanCustomer.isNotEmpty) ...[
            _stopInfoRow(Icons.person_outline, cleanCustomer),
            const SizedBox(height: 6),
          ],

          // Pickup address (+ navigate button)
          if (cleanPickupAddress.isNotEmpty) ...[
            _stopInfoRow(Icons.my_location_outlined, cleanPickupAddress),
            const SizedBox(height: 8),
            if (!isTerminal) ...[
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TripStopMapScreen(
                      address: cleanPickupAddress,
                      stopNumber: ps.stop,
                    ),
                  ),
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.oceanBlue.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.oceanBlue.withValues(alpha: 0.2),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.navigation_rounded,
                        size: 15,
                        color: AppTheme.oceanBlue,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Navigate to Pickup',
                        style: TextStyle(
                          color: AppTheme.oceanBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],

          // Customer mobile
          if (ps.customerMobile.isNotEmpty) ...[
            Row(
              children: [
                const Icon(
                  Icons.phone_outlined,
                  size: 15,
                  color: Colors.black45,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ps.customerMobile,
                    style: const TextStyle(
                      color: AppTheme.nightBlue,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (!isTerminal)
                  GestureDetector(
                    onTap: () => _launchCall(ps.customerMobile),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF2E7D32).withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.call_rounded,
                            size: 13,
                            color: Color(0xFF2E7D32),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Call',
                            style: TextStyle(
                              color: Color(0xFF2E7D32),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // Items (fetched from getdoc)
          if (jobDetail != null && jobDetail.items.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Items to Pickup:',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.nightBlue.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...jobDetail.items.map(
                    (it) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '• ${it.qty.toStringAsFixed(0)}x ${it.itemName}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.nightBlue,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ] else if (_fetchingPickupDetails && jobDetail == null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.oceanBlue,
                  ),
                ),
              ),
            ),
          ],

          // Action Buttons
          if (!isTerminal && trip.status.toLowerCase() != 'completed') ...[
            const Divider(height: 1, color: Colors.black12),
            const SizedBox(height: 10),
            _pickupStopActionButtons(trip, ps),
          ],

          // Failure reason
          if (statusNorm == 'failed' && ps.failureReasonCode.isNotEmpty) ...[
            const SizedBox(height: 6),
            _stopInfoRow(
              Icons.error_outline_rounded,
              ps.failureReasonCode,
              subtle: true,
              color: Colors.red,
            ),
          ],

          // Pickup Job reference
          if (ps.pickupJob.isNotEmpty) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => Navigator.of(
                context,
              ).pushNamed(AppRoutes.pickupJobDetail, arguments: ps.pickupJob),
              child: Row(
                children: [
                  const Icon(
                    Icons.receipt_long_outlined,
                    size: 14,
                    color: Colors.black45,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      ps.pickupJob,
                      style: const TextStyle(
                        color: Colors.black45,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Text(
                    'View Detail →',
                    style: TextStyle(
                      color: AppTheme.oceanBlue.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pickupStopActionButtons(
    ExternalDeliveryTrip trip,
    PickupTripStop ps,
  ) {
    final statusNorm = ps.status.trim().toLowerCase();
    final stopKey = '${ps.pickupJob}-${ps.stop}';
    final isUpdating = _updatingStops.contains(stopKey);

    if (isUpdating) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.oceanBlue,
            ),
          ),
        ),
      );
    }

    if (statusNorm == 'picked up') {
      return SizedBox(
        width: double.infinity,
        child: _actionButton(
          label: 'Mark Received at Store',
          icon: Icons.store_outlined,
          color: const Color(0xFF2E7D32),
          onTap: () => _handlePickupAction(ps, 'Received at Store'),
        ),
      );
    }

    // Default: Pending / Draft -> Picked Up or Failed
    return Row(
      children: [
        Expanded(
          child: _actionButton(
            label: 'Picked Up',
            icon: Icons.check_box_outlined,
            color: AppTheme.oceanBlue,
            onTap: () => _handlePickupAction(ps, 'Picked Up'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _actionButton(
            label: 'Failed',
            icon: Icons.close_rounded,
            color: Colors.red,
            onTap: () => _handlePickupAction(ps, 'Failed'),
          ),
        ),
      ],
    );
  }

  Future<void> _handlePickupAction(
    PickupTripStop ps,
    String targetStatus,
  ) async {
    final stopKey = '${ps.pickupJob}-${ps.stop}';
    setState(() => _updatingStops.add(stopKey));

    try {
      final repo = PickupJobRepository();
      if (targetStatus == 'Picked Up') {
        await repo.markPickedUp(ps.pickupJob);
      } else if (targetStatus == 'Received at Store') {
        await repo.updatePickupTripStopCompleted(
          tripName: widget.tripName,
          pickupJobName: ps.pickupJob,
        );
      } else if (targetStatus == 'Failed') {
        await ExternalDeliveryRepository().setStopStatusRaw(
          stopDocType: 'External Delivery Trip Pickup Stop',
          stopName: (ps.rawFields['name'] ?? '').toString(),
          parentTripName: widget.tripName,
          newStatus: 'Failed',
        );
      }

      if (!mounted) return;
      showInfoSnack(context, 'Pickup status updated to $targetStatus');
      setState(() {
        _future = _loadTrip();
      });
    } catch (e) {
      if (!mounted) return;
      showInfoSnack(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _updatingStops.remove(stopKey));
    }
  }

  // ───────────────────────────────────────────────────────────────────────────

  bool _isStopEditable({
    required String tripStatus,
    required String stopStatus,
  }) {
    final normalizedTripStatus = tripStatus.trim().toLowerCase();
    // Normalise underscores
    final normalizedStopStatus = stopStatus.trim().toLowerCase().replaceAll(
      '_',
      ' ',
    );
    const lockedStopStatuses = <String>{
      'delivered',
      'returned',
      'failed',
      'received at store',
    };

    if (normalizedTripStatus == 'completed') {
      return false;
    }

    if (lockedStopStatuses.contains(normalizedStopStatus)) {
      return false;
    }

    return true;
  }

  String _stopKey(dynamic stop) {
    if (stop is ExternalDeliveryTripStop) {
      final rowName = (stop.rawFields['name'] ?? '').toString().trim();
      if (rowName.isNotEmpty) return rowName;
      return '${stop.externalDelivery}-${stop.stop}';
    } else if (stop is PickupTripStop) {
      final rowName = (stop.rawFields['name'] ?? '').toString().trim();
      if (rowName.isNotEmpty) return rowName;
      return '${stop.pickupJob}-${stop.stop}';
    }
    return '';
  }

  Future<void> _updateStopStatus(
    ExternalDeliveryTripStop stop,
    String newStatus,
  ) async {
    final current = stop.status.trim().toLowerCase();
    if (current == newStatus.trim().toLowerCase()) return;

    // Intercept "Delivered" — show proof-of-delivery capture sheet
    if (newStatus == 'Delivered') {
      await _handleDeliveredStop(stop);
      return;
    }

    // Intercept "Failed" — show reason sheet and handle return trip flow
    if (newStatus == 'Failed') {
      await _handleFailedDelivery(stop);
      return;
    }

    final stopKey = _stopKey(stop);
    setState(() => _updatingStops.add(stopKey));
    try {
      final stopDocType = (stop.rawFields['doctype'] ?? '').toString().trim();
      final stopName = (stop.rawFields['name'] ?? '').toString().trim();
      final parentTripName = (stop.rawFields['parent'] ?? '').toString().trim();
      // Always go through the offline-aware path: it queues + flushes
      // when online, and queues + updates the local cache when offline.
      // The user gets immediate visual feedback either way.
      await OfflineTripManager().updateStopStatusOffline(
        stopDocType: stopDocType,
        stopName: stopName,
        parentTripName: parentTripName,
        orderName: stop.externalDelivery.trim(),
        newStatus: newStatus,
      );
      if (!mounted) return;
      final isConnected = ConnectivityService().isConnected;
      showInfoSnack(
        context,
        isConnected
            ? 'Stop status updated to $newStatus'
            : 'Saved offline. Will sync when reconnected.',
      );
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      setState(() {
        _future = _loadTrip();
      });
    } catch (e) {
      if (!mounted) return;
      showInfoSnack(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _updatingStops.remove(stopKey));
      }
    }
  }

  void _writeTimingEvent({
    required String eventType,
    String? tripRef,
    String? stopRef,
  }) {
    ref
        .read(appControllerProvider)
        .recordTimingEvent(
          eventType: eventType,
          tripRef: tripRef,
          stopRef: stopRef,
        );
  }

  Future<void> _handleDeliveredStop(ExternalDeliveryTripStop stop) async {
    final photoPath = await showDeliveryProofSheet(context);
    if (!mounted) return;

    final orderName = stop.externalDelivery.trim();
    if (photoPath != null && orderName.isNotEmpty) {
      await ExternalDeliveryRepository().uploadProofPhoto(
        orderName: orderName,
        filePath: photoPath,
      );
    }

    final stopKey = _stopKey(stop);
    setState(() => _updatingStops.add(stopKey));
    try {
      final stopDocType = (stop.rawFields['doctype'] ?? '').toString().trim();
      final stopName = (stop.rawFields['name'] ?? '').toString().trim();
      final parentTripName = (stop.rawFields['parent'] ?? '').toString().trim();
      await OfflineTripManager().updateStopStatusOffline(
        stopDocType: stopDocType,
        stopName: stopName,
        parentTripName: parentTripName,
        orderName: stop.externalDelivery.trim(),
        newStatus: 'Delivered',
      );
      _writeTimingEvent(
        eventType: TimingEventType.stopDelivered,
        tripRef: parentTripName.isEmpty ? null : parentTripName,
        stopRef: stopName.isEmpty ? null : stopName,
      );
      if (!mounted) return;
      final isConnected = ConnectivityService().isConnected;
      showInfoSnack(
        context,
        isConnected
            ? 'Stop status updated to Delivered'
            : 'Saved offline. Will sync when reconnected.',
      );
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      setState(() {
        _future = _loadTrip();
      });
    } catch (e) {
      if (!mounted) return;
      showInfoSnack(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _updatingStops.remove(stopKey));
    }
  }

  Future<void> _handleFailedDelivery(ExternalDeliveryTripStop stop) async {
    final result = await showFailedDeliverySheet(context);
    if (result == null || !mounted) return;

    final orderName = stop.externalDelivery.trim();
    final stopKey = _stopKey(stop);
    final fullReason = result.notes.isEmpty
        ? result.reason
        : '${result.reason} — ${result.notes}';

    // The full failed-delivery flow uploads a photo, mutates the order,
    // and (optionally) creates a server-side return trip. None of that
    // can run offline. If we're offline, fall back to a queued stop
    // status update so the driver can still mark Failed locally; the
    // photo + return-trip steps will need to be redone online.
    if (!ConnectivityService().isConnected) {
      setState(() => _updatingStops.add(stopKey));
      try {
        final stopDocType = (stop.rawFields['doctype'] ?? '').toString().trim();
        final stopName = (stop.rawFields['name'] ?? '').toString().trim();
        final parentTripName = (stop.rawFields['parent'] ?? '')
            .toString()
            .trim();
        await OfflineTripManager().updateStopStatusOffline(
          stopDocType: stopDocType,
          stopName: stopName,
          parentTripName: parentTripName,
          orderName: orderName,
          newStatus: 'Failed',
        );
        _writeTimingEvent(
          eventType: TimingEventType.stopFailed,
          tripRef: parentTripName.isEmpty ? null : parentTripName,
          stopRef: stopName.isEmpty ? null : stopName,
        );
        if (!mounted) return;
        showInfoSnack(
          context,
          'Marked Failed offline. Photo upload and return trip will need '
          'to be done when back online.',
        );
        setState(() {
          _future = _loadTrip();
        });
      } catch (e) {
        if (!mounted) return;
        showInfoSnack(context, e.toString().replaceFirst('Exception: ', ''));
      } finally {
        if (mounted) setState(() => _updatingStops.remove(stopKey));
      }
      return;
    }

    setState(() => _updatingStops.add(stopKey));
    try {
      final processResult = await ExternalDeliveryRepository()
          .processFailedDeliveryReturn(
            stop: stop,
            orderName: orderName,
            reason: fullReason,
            reasonCode: result.reasonCode,
            photoPath: result.photoPath,
            shouldCreateReturnTrip: false,
          );
      if (!mounted) return;
      _writeTimingEvent(
        eventType: TimingEventType.stopFailed,
        tripRef: (stop.rawFields['parent'] ?? '').toString().trim().isEmpty
            ? null
            : (stop.rawFields['parent'] ?? '').toString().trim(),
        stopRef: (stop.rawFields['name'] ?? '').toString().trim().isEmpty
            ? null
            : (stop.rawFields['name'] ?? '').toString().trim(),
      );
      showInfoSnack(context, processResult.message);
      setState(() {
        _future = _loadTrip();
      });
    } catch (e) {
      if (!mounted) return;
      showInfoSnack(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _updatingStops.remove(stopKey));
      }
    }
  }

  Widget _statBox(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stopHeader(ExternalDeliveryTripStop stop) {
    final statusNorm = stop.status.trim().toLowerCase().replaceAll('_', ' ');
    final Color statusColor;
    if (statusNorm == 'delivered' || statusNorm == 'returned') {
      statusColor = const Color(0xFF2E7D32);
    } else if (statusNorm == 'failed') {
      statusColor = Colors.red;
    } else if (statusNorm == 'out for delivery') {
      statusColor = AppTheme.oceanBlue;
    } else if (statusNorm == 'cancelled') {
      statusColor = Colors.black38;
    } else {
      statusColor = Colors.black45;
    }

    return Row(
      children: [
        Icon(Icons.location_on_outlined, size: 18, color: AppTheme.oceanBlue),
        const SizedBox(width: 6),
        Text(
          'Stop ${stop.stop}',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppTheme.nightBlue,
            fontSize: 14,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: statusColor.withValues(alpha: 0.3)),
          ),
          child: Text(
            stop.status.isEmpty ? 'Pending' : stop.status,
            style: TextStyle(
              color: statusColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  String _parseHtml(String? htmlString) {
    if (htmlString == null || htmlString.isEmpty) return '';
    try {
      final document = parse(htmlString);
      final String parsedString =
          parse(document.body?.text ?? '').documentElement?.text ?? '';
      return parsedString.trim();
    } catch (_) {
      return htmlString.trim();
    }
  }

  Widget _stopInfoCard(ExternalDeliveryTripStop stop) {
    final statusNorm = stop.status.toLowerCase().trim();
    final isTerminal = {
      'delivered',
      'failed',
      'returned',
      'cancelled',
    }.contains(statusNorm);
    final String cleanAddress = _parseHtml(stop.address);
    final String cleanNotes = _parseHtml(stop.notes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stop.customer.isNotEmpty) ...[
          _stopInfoRow(Icons.person_outline, stop.customer),
          const SizedBox(height: 6),
        ],
        if (cleanAddress.isNotEmpty) ...[
          _stopInfoRow(Icons.location_on_outlined, cleanAddress),
          const SizedBox(height: 6),
        ],
        if (stop.mobile.isNotEmpty) ...[
          Row(
            children: [
              const Icon(Icons.phone_outlined, size: 15, color: Colors.black45),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  stop.mobile,
                  style: const TextStyle(
                    color: AppTheme.nightBlue,
                    fontSize: 13,
                  ),
                ),
              ),
              if (!isTerminal)
                GestureDetector(
                  onTap: () => _launchCall(stop.mobile),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF2E7D32).withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.call_rounded,
                          size: 13,
                          color: Color(0xFF2E7D32),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Call',
                          style: TextStyle(
                            color: Color(0xFF2E7D32),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        if (cleanAddress.isNotEmpty && !isTerminal) ...[
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TripStopMapScreen(
                  address: cleanAddress,
                  stopNumber: stop.stop,
                ),
              ),
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: AppTheme.oceanBlue.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppTheme.oceanBlue.withValues(alpha: 0.2),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.navigation_rounded,
                    size: 15,
                    color: AppTheme.oceanBlue,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Navigate',
                    style: TextStyle(
                      color: AppTheme.oceanBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
        if (stop.externalDelivery.isNotEmpty)
          _stopInfoRow(
            Icons.receipt_long_outlined,
            stop.externalDelivery,
            subtle: true,
          ),
        if (stop.deliveredAt.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          _stopInfoRow(
            Icons.check_circle_outline,
            'Delivered: ${stop.deliveredAt}',
            color: const Color(0xFF2E7D32),
          ),
        ],
        if (statusNorm == 'failed' && stop.failureReasonCode.isNotEmpty) ...[
          const SizedBox(height: 4),
          _stopInfoRow(
            Icons.cancel_outlined,
            stop.failureReasonLabel,
            color: Colors.red,
          ),
        ],
        if (cleanNotes.isNotEmpty) ...[
          const SizedBox(height: 4),
          _stopInfoRow(Icons.notes_rounded, cleanNotes, subtle: true),
        ],
      ],
    );
  }

  Widget _stopInfoRow(
    IconData icon,
    String text, {
    bool subtle = false,
    Color? color,
  }) {
    final textColor = color ?? (subtle ? Colors.black45 : AppTheme.nightBlue);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: color ?? Colors.black45),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: textColor, fontSize: subtle ? 12 : 13),
          ),
        ),
      ],
    );
  }

  Widget _stopActionButtons(
    ExternalDeliveryTrip trip,
    ExternalDeliveryTripStop stop,
  ) {
    final stopKey = _stopKey(stop);
    final isUpdating = _updatingStops.contains(stopKey);

    if (isUpdating) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.oceanBlue,
            ),
          ),
        ),
      );
    }

    // Scrub Delivered/Failed from the popup options list
    final menuOptions =
        _stopStatusOptions
            .where((s) => s != 'Delivered' && s != 'Failed')
            .toSet()
          ..addAll([
            if (stop.status.trim().isNotEmpty &&
                stop.status.trim() != 'Delivered' &&
                stop.status.trim() != 'Failed')
              stop.status.trim(),
          ]);

    return Row(
      children: [
        Expanded(
          child: _actionButton(
            label: 'Delivered',
            icon: Icons.check_rounded,
            color: const Color(0xFF2E7D32),
            onTap: () => _updateStopStatus(stop, 'Delivered'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _actionButton(
            label: 'Failed',
            icon: Icons.close_rounded,
            color: Colors.red,
            onTap: () => _updateStopStatus(stop, 'Failed'),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          onSelected: (status) => _updateStopStatus(stop, status),
          itemBuilder: (context) {
            return menuOptions
                .map((s) => PopupMenuItem<String>(value: s, child: Text(s)))
                .toList();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black12),
            ),
            child: const Icon(
              Icons.more_horiz,
              size: 18,
              color: Colors.black54,
            ),
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchCall(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
}
