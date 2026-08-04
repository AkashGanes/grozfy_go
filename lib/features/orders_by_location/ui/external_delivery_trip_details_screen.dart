import 'dart:async';
import 'dart:convert';
import 'package:html/parser.dart' show parse;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/navigation/app_routes.dart';
import '../../../core/database/partner_timing_log_dao.dart';
import '../../../core/state/providers.dart';
import 'trip_stage_timeline_widget.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/offline_trip_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/context_colors.dart';
import '../../../core/widgets/app_shell.dart';
import '../../cod_settlement/providers/settlement_provider.dart';
import '../../../core/widgets/status_confirm_sheet.dart';
import '../model/external_delivery.dart';
import '../model/external_delivery_detail.dart';
import '../repository/external_delivery_repository.dart';
import '../../orders/delivery_tracking_screen.dart';
import '../../pickup_jobs/model/pickup_job.dart';
import '../../pickup_jobs/repository/pickup_job_repository.dart';
import 'cod_collection_sheet.dart';
import 'cod_handover_sheet.dart';
import 'delivery_otp_sheet.dart';
import 'delivery_proof_sheet.dart';
import 'failed_delivery_bottom_sheet.dart';
import '../../pickup_jobs/ui/failed_pickup_bottom_sheet.dart';

import '../../../core/utils/geo_distance.dart';
import '../../../core/utils/maps_launcher.dart';
import '../model/stop_progress_status.dart' as stop_progress;
import '../providers/trip_controller.dart';
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
  bool _tripAcceptedFired = false;
  static const List<String> _stopStatusOptions = <String>[
    'Pending',
    'Out for Delivery',
    'Delivered',
    'Failed',
    'Cancelled',
  ];
  static const String _skipForNowValue = '__skip_for_now__';

  // ── Pickup flow State ──────────────────────────────────────────────────────
  final Map<String, PickupJob> _pickupJobDetails = {};
  bool _fetchingPickupDetails = false;
  // ───────────────────────────────────────────────────────────────────────────

  // Nearest-stop sequencing state (coords, suggested/display order, manual
  // override, in-flight action guards, ETA cache, auto-navigate/trip-complete
  // triggers) all live in TripController now — it's the single source of
  // truth, shared/testable independent of this widget. `_controller` is a
  // read-only accessor (safe from any method, including callbacks);
  // `build()` establishes the rebuild subscription via a single `ref.watch`.
  TripController get _controller =>
      ref.read(tripControllerProvider(widget.tripName).notifier);

  @override
  void initState() {
    super.initState();
    _future = _loadTrip();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_tripAcceptedFired) {
        _tripAcceptedFired = true;
        _writeTimingEvent(
          eventType: TimingEventType.tripAccepted,
          tripRef: widget.tripName,
        );
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// Loads the trip, then resolves pending-stop coordinates and (re)computes
  /// the nearest-first sequence from the driver's current live GPS location.
  Future<ExternalDeliveryTrip> _loadTrip() async {
    final ExternalDeliveryTrip trip = await _fetchTrip();
    await _controller.resolveSequencing(trip);
    return trip;
  }

  /// Cache-aware trip fetch. Online → fetch + cache; Offline → cache only;
  /// Network error mid-call → flip connectivity flag and serve cache. Only
  /// throws when both network and cache fail.
  Future<ExternalDeliveryTrip> _fetchTrip() async {
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

  // Terminal-status check, coordinate lookup, and stop-key derivation now
  // live on TripController (single source of truth) — these stay as thin
  // delegators so the ~30 existing call sites throughout this file need no
  // further changes.
  bool _isTerminalStop(dynamic stop) => stop_progress.isTerminalStop(stop);

  (double, double)? _coordsFor(dynamic stop) => _controller.coordsFor(stop);

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

    // Subscribes this widget to TripController's state (sequencing, guards,
    // ETA cache, etc.) so it rebuilds whenever the controller's state
    // changes — the actual reads throughout this file go through `_controller`
    // (a `ref.read`-backed accessor), relying on this single watch call for
    // the rebuild subscription.
    ref.watch(tripControllerProvider(widget.tripName));

    // Reactive trigger for the one side effect that needs a BuildContext
    // (showing the trip-completed dialog) and so can't live inside
    // TripController itself. Google Maps navigation is no longer
    // auto-launched — the driver taps the "Navigate" button explicitly (see
    // _navigateButton/_navigateAllPendingStops) so they see the stop list
    // first instead of being sent straight to Maps on screen entry.
    ref.listen<TripControllerState>(
      tripControllerProvider(widget.tripName),
      (previous, next) {
        final ExternalDeliveryTrip? justCompleted = next.justCompletedTrip;
        if (justCompleted != null &&
            justCompleted != previous?.justCompletedTrip) {
          unawaited(_showTripCompletedDialog(justCompleted));
        }
      },
    );

    return AppShell(
      title: 'External Delivery Trip',
      subtitle: widget.tripName,
      scrollable: false,
      actions: [_navigateButton()],
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
                      color: context.scheme.primary.withValues(alpha: 0.12),
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FrostCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trip Statistics',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
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
                          context.scheme.primary,
                        ),
                        const SizedBox(width: 8),
                        _statBox(
                          'Done',
                          '${trip.completedStops}',
                          Icons.check_circle_outline,
                          context.success,
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
                        backgroundColor: context.fillMuted,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          trip.completedStops >= trip.totalStops &&
                                  trip.totalStops > 0
                              ? context.success
                              : context.scheme.primary,
                        ),
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Progress',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.textTertiary,
                          ),
                        ),
                        Text(
                          '${trip.completedStops}/${trip.totalStops} stops',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    if (trip.totalDistanceKm > 0) ...[
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Icon(
                            Icons.route_outlined,
                            size: 16,
                            color: context.scheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Total Distance',
                              style: TextStyle(
                                color: context.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Text(
                            '${trip.totalDistanceKm.toStringAsFixed(1)} km',
                            style: TextStyle(
                              color: context.textPrimary,
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
                          Icon(
                            Icons.play_circle_outline,
                            size: 16,
                            color: context.scheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Started',
                              style: TextStyle(
                                color: context.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Text(
                            trip.startedAt,
                            style: TextStyle(
                              color: context.textPrimary,
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
                          Icon(
                            Icons.stop_circle_outlined,
                            size: 16,
                            color: context.success,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Completed',
                              style: TextStyle(
                                color: context.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Text(
                            trip.completedAt,
                            style: TextStyle(
                              color: context.textPrimary,
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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
                      Text(
                        'Stops Progress',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
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
                            context.scheme.primary,
                          ),
                          const SizedBox(width: 8),
                          _statBox(
                            'Done',
                            '${trip.completedStops}',
                            Icons.check_circle_outline,
                            context.success,
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
                          backgroundColor: context.fillMuted,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            trip.completedStops >= trip.totalStops
                                ? context.success
                                : context.scheme.primary,
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
            color: context.scheme.primary.withValues(alpha: 0.14),
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
              color: context.scheme.primary.withValues(alpha: 0.18),
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
              color: context.scheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.local_shipping_outlined,
              size: 18,
              color: context.scheme.primary,
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
              color: context.scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: context.scheme.primary),
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
            ? context.success.withValues(alpha: 0.08)
            : AppTheme.mango.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: alreadyCompleted
              ? context.success.withValues(alpha: 0.3)
              : AppTheme.mango.withValues(alpha: 0.4),
        ),
      ),
      child: alreadyCompleted
          ? Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: context.success,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Package returned to store successfully.',
                    style: TextStyle(
                      color: context.success,
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
                      ? Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: context.scheme.primary,
                            ),
                          ),
                        )
                      : ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.scheme.primary,
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
            Icon(Icons.store_outlined, color: context.scheme.primary),
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
              backgroundColor: context.scheme.primary,
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
    if (ref.read(appControllerProvider).profileCompleteness.percentage < 1.0) {
      showInfoSnack(context, 'Complete your profile to process orders.');
      return;
    }
    if (!ref.read(appControllerProvider).isOnline) {
      showInfoSnack(context, 'You are offline — go online to process orders.');
      return;
    }

    // Block if any delivery stop is still in a non-terminal state.
    const activeStatuses = {'pending', 'out for delivery', 'out_for_delivery'};
    final unresolvedStops = trip.stops
        .where(
          (s) => activeStatuses.contains(
            s.status.trim().toLowerCase().replaceAll('_', ' '),
          ),
        )
        .length;
    if (unresolvedStops > 0) {
      showInfoSnack(
        context,
        'Please mark all $unresolvedStops remaining '
        'stop${unresolvedStops == 1 ? '' : 's'} as Delivered or Failed first.',
      );
      return;
    }

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

    // COD handover reconciliation before completing the trip
    final codHandover = await ExternalDeliveryRepository().fetchCodHandover(trip.name);
    if (!mounted) return;
    if (codHandover != null && codHandover.needsCollection) {
      final handoverResult = await showCodHandoverSheet(
        context,
        codHandover: codHandover,
      );
      if (!mounted) return;
      if (handoverResult == null) return;
      try {
        await ExternalDeliveryRepository().submitCodHandover(
          name: codHandover.name,
          actualAmount: handoverResult.actualAmount,
          notes: handoverResult.notes,
        );
        // Handing cash over frees cash-in-hand headroom — refetch the limit so
        // the dashboard and the accept guard see the new available amount.
        ref.invalidate(codLimitStatusProvider);
      } catch (_) {
        if (mounted) showInfoSnack(context, 'COD handover save failed — continuing');
      }
      if (!mounted) return;
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

  /// Nearest-first (or manually reordered) pending stops. Delegates to
  /// TripController, the single source of truth for display order.
  List<dynamic> _pendingOrderedStops(ExternalDeliveryTrip trip) =>
      _controller.pendingOrderedStops(trip);

  Widget _stopsTab(ExternalDeliveryTrip trip) {
    final List<dynamic> allStops = [...trip.stops, ...trip.pickupStops];

    // Pending stops render in nearest-first (or manually reordered) sequence;
    // completed/failed/etc. stops move to a collapsed section below.
    final List<dynamic> pendingOrdered = _pendingOrderedStops(trip);
    final List<dynamic> completed = allStops.where(_isTerminalStop).toList()
      ..sort((a, b) {
        final int stopA = (a is ExternalDeliveryTripStop)
            ? a.stop
            : (a as PickupTripStop).stop;
        final int stopB = (b is ExternalDeliveryTripStop)
            ? b.stop
            : (b as PickupTripStop).stop;
        return stopA.compareTo(stopB);
      });

    final ColorScheme scheme = Theme.of(context).colorScheme;

    double? nextStopDistanceMeters;
    String? nextStopEtaLabel;
    if (pendingOrdered.isNotEmpty) {
      final app = ref.watch(appControllerProvider);
      final (double, double)? coords = _coordsFor(pendingOrdered.first);
      final double? driverLat = app.currentLatitude;
      final double? driverLng = app.currentLongitude;
      if (coords != null && driverLat != null && driverLng != null) {
        nextStopDistanceMeters =
            haversineMeters(driverLat, driverLng, coords.$1, coords.$2);
        nextStopEtaLabel = _etaLabelFor(
          _stopKey(pendingOrdered.first),
          driverLat,
          driverLng,
          coords.$1,
          coords.$2,
        );
      }
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        children: [
          if (trip.isReturnTrip) ...[
            _returnTripBanner(trip),
            const SizedBox(height: 10),
          ],
          if (_controller.value.manualOrderActive && pendingOrdered.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: context.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Manual stop order active',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textTertiary,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _controller.resetToSuggested(),
                    child: Text(
                      'Reset to suggested',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.scheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (allStops.isEmpty)
            FrostCard(
              child: Text(
                'No stops found',
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            )
          else ...[
            if (pendingOrdered.isNotEmpty)
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: pendingOrdered.length,
                onReorderItem: (int oldIndex, int newIndex) {
                  _controller.reorder(oldIndex, newIndex);
                },
                itemBuilder: (context, index) {
                  final dynamic stop = pendingOrdered[index];
                  final String key = _stopKey(stop);
                  final bool hasMultipleStops = pendingOrdered.length > 1;
                  final bool isNext = index == 0;
                  final bool highlightAsNext = isNext && hasMultipleStops;
                  final List<String> suggestedOrder = _controller.value.suggestedOrder;
                  final bool isSuggestedNext = hasMultipleStops &&
                      suggestedOrder.isNotEmpty &&
                      suggestedOrder.first == key;

                  final Widget innerCard = stop is ExternalDeliveryTripStop
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: FrostCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (isNext) ...[
                                  _stopHeader(stop),
                                  const SizedBox(height: 12),
                                ],
                                _stopInfoCard(stop),
                                if (_isStopEditable(
                                  tripStatus: trip.status,
                                  stopStatus: stop.status,
                                )) ...[
                                  const SizedBox(height: 12),
                                  const Divider(height: 1),
                                  const SizedBox(height: 10),
                                  _stopActionButtons(trip, stop),
                                ],
                              ],
                            ),
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _pickupStopCard(trip, stop as PickupTripStop),
                        );

                  final Widget card = (!isNext && hasMultipleStops)
                      ? _collapsibleStopCard(stop, innerCard)
                      : innerCard;

                  final Widget row = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 18, right: 4),
                          child: Icon(
                            Icons.drag_indicator_rounded,
                            size: 18,
                            color: context.iconMuted,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (highlightAsNext)
                              _nearestStopBanner(
                                distanceMeters: nextStopDistanceMeters,
                                stopIndex: 1,
                                totalPending: pendingOrdered.length,
                                etaLabel: nextStopEtaLabel,
                              )
                            else if (isSuggestedNext)
                              _suggestedPill(),
                            card,
                          ],
                        ),
                      ),
                    ],
                  );

                  if (!highlightAsNext) {
                    return KeyedSubtree(key: ValueKey(key), child: row);
                  }

                  return Container(
                    key: ValueKey(key),
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.only(left: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: context.scheme.primary,
                          width: 3,
                        ),
                      ),
                    ),
                    child: row,
                  );
                },
              ),
            if (completed.isNotEmpty) _completedStopsSection(trip, completed),
          ],
        ],
      ),
    );
  }

  /// Header action that launches ONE Google Maps session covering every
  /// currently-pending stop as a multi-stop driving route (destination =
  /// last pending stop, waypoints = the rest, in nearest-first/manual
  /// order). Explicit tap only — the app no longer auto-launches Google
  /// Maps on screen entry/resume, so the driver sees the stop list first.
  Widget _navigateButton() {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: 'Navigate',
        child: GestureDetector(
          onTap: _navigateAllPendingStops,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Radar-style "live" ping — repeatedly expands + fades out
                // from behind the icon to read as an active/always-on action,
                // not just a static button.
                Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: context.scheme.primary,
                          width: 1.5,
                        ),
                      ),
                    )
                    .animate(onPlay: (controller) => controller.repeat())
                    .scale(
                      begin: const Offset(0.55, 0.55),
                      end: const Offset(1.35, 1.35),
                      duration: 1400.ms,
                      curve: Curves.easeOut,
                    )
                    .fadeOut(duration: 1400.ms, curve: Curves.easeOut),
                Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: context.scheme.primary.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.navigation_rounded,
                        color: context.scheme.primary,
                        size: 22,
                      ),
                    )
                    .animate(
                      onPlay: (controller) => controller.repeat(reverse: true),
                    )
                    .scale(
                      begin: const Offset(1, 1),
                      end: const Offset(1.08, 1.08),
                      duration: 900.ms,
                      curve: Curves.easeInOut,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _navigateAllPendingStops() async {
    final ExternalDeliveryTrip trip;
    try {
      trip = await _future;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final List<dynamic> pendingOrdered = _pendingOrderedStops(trip);
    final List<(double, double)> routeCoords = [
      for (final dynamic stop in pendingOrdered)
        if (_coordsFor(stop) != null) _coordsFor(stop)!,
    ];
    if (routeCoords.isEmpty) {
      showInfoSnack(context, 'No stop locations available to navigate.');
      return;
    }
    launchGoogleMapsMultiStopNavigation(context, stops: routeCoords);
  }

  String _formatDistance(double meters) => TripController.formatDistance(meters);

  /// Best-effort ETA label for the stop at [stopKey]/[destLat]/[destLng] from
  /// the driver's current position. Delegates to TripController, which owns
  /// the cache/in-flight-dedupe state.
  String? _etaLabelFor(
    String stopKey,
    double driverLat,
    double driverLng,
    double destLat,
    double destLng,
  ) =>
      _controller.etaLabelFor(stopKey, driverLat, driverLng, destLat, destLng);

  /// Checks whether the driver is within the configured delivery radius of
  /// [stop], for gating "Mark Delivered". Delegates to TripController, which
  /// reuses `AppController`'s existing radius check as-is (read-only).
  (bool ok, String? blockMessage) _checkDeliveryRadiusFor(dynamic stop) =>
      _controller.checkDeliveryRadius(stop);

  Widget _nearestStopBanner({
    required double? distanceMeters,
    int? stopIndex,
    int? totalPending,
    String? etaLabel,
  }) {
    final Color accent = context.success;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
          SizedBox(
            width: 14,
            height: 14,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    )
                    .animate(onPlay: (controller) => controller.repeat())
                    .scale(
                      begin: const Offset(0.4, 0.4),
                      end: const Offset(2.4, 2.4),
                      duration: 1400.ms,
                      curve: Curves.easeOut,
                    )
                    .fadeOut(begin: 0.55, duration: 1400.ms),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Nearest stop',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: accent,
              letterSpacing: 0.2,
            ),
          ),
          if (distanceMeters != null) ...[
            const SizedBox(width: 6),
            Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                color: context.textTertiary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _formatDistance(distanceMeters),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: context.textSecondary,
              ),
            ),
          ],
            ],
          ),
          if ((stopIndex != null && totalPending != null) || etaLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 22),
              child: Row(
                children: [
                  if (stopIndex != null && totalPending != null)
                    Text(
                      'Stop $stopIndex of $totalPending',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: context.textTertiary,
                      ),
                    ),
                  if (stopIndex != null &&
                      totalPending != null &&
                      etaLabel != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 3,
                      height: 3,
                      decoration: BoxDecoration(
                        color: context.textTertiary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (etaLabel != null)
                    Text(
                      'ETA $etaLabel',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: context.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _suggestedPill() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 12, color: context.textTertiary),
          const SizedBox(width: 4),
          Text(
            'Suggested next',
            style: TextStyle(
              fontSize: 11,
              color: context.textTertiary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _collapsibleStopCard(dynamic stop, Widget child) {
    final int stopNumber;
    final String status;
    final String address;
    final IconData icon;
    if (stop is ExternalDeliveryTripStop) {
      stopNumber = stop.stop;
      status = stop.status;
      address = _parseHtml(stop.address);
      icon = Icons.location_on_outlined;
    } else {
      final ps = stop as PickupTripStop;
      stopNumber = ps.stop;
      status = ps.status;
      address = _parseHtml(ps.pickupAddress);
      icon = Icons.inventory_2_outlined;
    }

    final String statusNorm = status.trim().toLowerCase();
    final Color statusColor;
    if (statusNorm == 'delivered' ||
        statusNorm == 'returned' ||
        statusNorm == 'received at store') {
      statusColor = context.success;
    } else if (statusNorm == 'failed') {
      statusColor = context.danger;
    } else if (statusNorm == 'out for delivery' || statusNorm == 'picked up') {
      statusColor = context.scheme.primary;
    } else if (statusNorm == 'cancelled') {
      statusColor = context.textDisabled;
    } else {
      statusColor = context.textTertiary;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          leading: Icon(icon, size: 18, color: context.scheme.primary),
          title: Text(
            'Stop $stopNumber',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: context.textPrimary,
            ),
          ),
          subtitle: Row(
            children: [
              if (address.isNotEmpty)
                Expanded(
                  child: Text(
                    address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: context.textSecondary),
                  ),
                ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  status.isEmpty ? 'Pending' : status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          children: [child],
        ),
      ),
    );
  }

  Widget _completedStopsSection(
    ExternalDeliveryTrip trip,
    List<dynamic> completed,
  ) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: context.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          leading: Icon(
            Icons.check_circle_outline,
            size: 18,
            color: context.success,
          ),
          title: Text(
            'Completed (${completed.length})',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: context.textSecondary,
            ),
          ),
          children: [
            for (final dynamic stop in completed)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: stop is ExternalDeliveryTripStop
                    ? FrostCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _stopHeader(stop),
                            const SizedBox(height: 12),
                            _stopInfoCard(stop),
                          ],
                        ),
                      )
                    : _pickupStopCard(trip, stop as PickupTripStop),
              ),
          ],
        ),
      ),
    );
  }

  void _skipForNow(dynamic stop) {
    _controller.skipForNow(stop);
    showInfoSnack(context, 'Moved to the back of the queue');
  }

  Widget _pickupStopCard(ExternalDeliveryTrip trip, PickupTripStop ps) {
    final statusNorm = ps.status.trim().toLowerCase();
    final Color statusColor;
    switch (statusNorm) {
      case 'received at store':
        statusColor = context.success;
      case 'picked up':
      case 'en route':
        statusColor = context.scheme.primary;
      case 'failed':
        statusColor = context.danger;
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
              Icon(
                Icons.inventory_2_outlined,
                size: 16,
                color: context.scheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Pickup stop ${ps.stop}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
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
              _stopNavigationButtons(
                address: cleanPickupAddress,
                stopNumber: ps.stop,
                coords: _coordsFor(ps),
                onOpenInApp: () => _openInAppNavigationFor(ps),
              ),
              const SizedBox(height: 8),
            ],
          ],

          // Customer mobile
          if (ps.customerMobile.isNotEmpty) ...[
            Row(
              children: [
                Icon(
                  Icons.phone_outlined,
                  size: 15,
                  color: context.iconMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ps.customerMobile,
                    style: TextStyle(
                      color: context.textPrimary,
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
                        color: context.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: context.success.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.call_rounded,
                            size: 13,
                            color: context.success,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Call',
                            style: TextStyle(
                              color: context.success,
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
                color: context.fillSubtle,
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
                      color: context.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...jobDetail.items.map(
                    (it) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '• ${it.qty.toStringAsFixed(0)}x ${it.itemName}',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ] else if (_fetchingPickupDetails && jobDetail == null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.scheme.primary,
                  ),
                ),
              ),
            ),
          ],

          // Action Buttons
          if (!isTerminal && trip.status.toLowerCase() != 'completed') ...[
            const Divider(height: 1),
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
              color: context.danger,
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
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 14,
                    color: context.iconMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      ps.pickupJob,
                      style: TextStyle(
                        color: context.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Text(
                    'View Detail →',
                    style: TextStyle(
                      color: context.scheme.primary.withValues(alpha: 0.7),
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
    final isUpdating = _controller.isUpdating(stopKey);

    if (isUpdating) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.scheme.primary,
            ),
          ),
        ),
      );
    }

    // Same staged status flow as the single pickup-job screen
    // (PickupJobDetailScreen._actionArea): Pending → En Route → Picked Up →
    // Received at Store, each confirmed via the shared StatusConfirmSheet,
    // with "Mark Failed" offered alongside the primary action at every
    // non-terminal stage (mirroring `_primaryActionButton`+`_failedActionButton`
    // pairing there).
    Widget primaryButton({
      required String label,
      required IconData icon,
      required VoidCallback onTap,
    }) {
      return SizedBox(
        height: 48,
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: context.scheme.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      );
    }

    Widget failedButton() {
      return SizedBox(
        height: 48,
        child: OutlinedButton.icon(
          onPressed: () => _handlePickupFailed(ps),
          icon: Icon(Icons.cancel_outlined, size: 18, color: context.danger),
          label: Text(
            'Mark Failed',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: context.danger,
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: context.danger,
            side: BorderSide(color: context.danger),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      );
    }

    if (statusNorm == 'picked up') {
      return Row(
        children: [
          Expanded(
            child: primaryButton(
              label: 'Received at Store',
              icon: Icons.store_outlined,
              onTap: () => _handlePickupReceivedAtStore(ps),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: failedButton()),
        ],
      );
    }

    if (statusNorm == 'en route') {
      return Row(
        children: [
          Expanded(
            child: primaryButton(
              label: 'Mark Picked Up',
              icon: Icons.inventory_2_outlined,
              onTap: () => _handlePickupPickedUp(ps),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: failedButton()),
        ],
      );
    }

    // Default: Pending / Draft / blank -> Mark En Route or Failed
    return Row(
      children: [
        Expanded(
          child: primaryButton(
            label: 'Mark En Route',
            icon: Icons.directions_car_rounded,
            onTap: () => _handlePickupEnRoute(ps),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: failedButton()),
      ],
    );
  }

  String _pickupCustomerLabel(PickupTripStop ps) =>
      ps.customerName.trim().isNotEmpty ? ps.customerName.trim() : 'the customer';

  Future<void> _handlePickupEnRoute(PickupTripStop ps) async {
    final confirmed = await showStatusConfirmSheet(
      context,
      title: 'Mark En Route?',
      body:
          "Confirm you're heading to pick up from ${_pickupCustomerLabel(ps)}.",
      actionLabel: 'Confirm En Route',
      icon: Icons.directions_car_rounded,
      color: context.scheme.primary,
    );
    if (confirmed != true || !mounted) return;
    await _runPickupCommit(
      ps,
      'En Route',
      () => _controller.startPickupEnRouteCommit(ps),
    );
  }

  Future<void> _handlePickupPickedUp(PickupTripStop ps) async {
    final photoPath = await showDeliveryProofSheet(context);
    if (!mounted) return;
    final confirmed = await showStatusConfirmSheet(
      context,
      title: 'Items Picked Up?',
      body:
          "Confirm you've collected the items from ${_pickupCustomerLabel(ps)}.",
      actionLabel: 'Confirm Picked Up',
      icon: Icons.inventory_2_rounded,
      color: const Color(0xFF6A1B9A),
    );
    if (confirmed != true || !mounted) return;
    await _runPickupCommit(
      ps,
      'Picked Up',
      () => _controller.markPickupPickedUpCommit(ps, proofPhotoPath: photoPath),
    );
  }

  Future<void> _handlePickupReceivedAtStore(PickupTripStop ps) async {
    final confirmed = await showStatusConfirmSheet(
      context,
      title: 'Drop at Store?',
      body:
          'Confirm you have dropped the items for ${_pickupCustomerLabel(ps)} at the store dock.',
      actionLabel: 'Confirm Drop',
      icon: Icons.store_rounded,
      color: context.success,
    );
    if (confirmed != true || !mounted) return;
    await _runPickupCommit(
      ps,
      'Received at Store',
      () => _controller.markPickupReceivedAtStoreCommit(ps),
    );
  }

  Future<void> _handlePickupFailed(PickupTripStop ps) async {
    final result = await showFailedPickupSheet(context);
    if (result == null || !mounted) return;
    await _runPickupCommit(
      ps,
      'Failed',
      () => _controller.markPickupFailedCommit(
        ps,
        reasonCode: result.reasonCode,
        notes: result.notes,
        photoPath: result.photoPath,
      ),
    );
  }

  Future<void> _runPickupCommit(
    PickupTripStop ps,
    String targetStatusLabel,
    Future<void> Function() commit,
  ) async {
    if (ref.read(appControllerProvider).profileCompleteness.percentage < 1.0) {
      showInfoSnack(context, 'Complete your profile to process orders.');
      return;
    }
    if (!ref.read(appControllerProvider).isOnline) {
      showInfoSnack(context, 'You are offline — go online to process orders.');
      return;
    }
    final stopKey = '${ps.pickupJob}-${ps.stop}';
    _controller.beginAction(stopKey);
    try {
      await commit();
      if (!mounted) return;
      final Future<ExternalDeliveryTrip> newFuture = _loadTrip();
      setState(() {
        _future = newFuture;
      });
      _notifyStopCompleted(
        'Pickup status updated to $targetStatusLabel',
        newFuture,
      );
    } catch (e) {
      if (!mounted) return;
      showInfoSnack(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) _controller.endAction(stopKey);
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
    if (ref.read(appControllerProvider).profileCompleteness.percentage < 1.0) {
      showInfoSnack(context, 'Complete your profile to process orders.');
      return;
    }
    if (!ref.read(appControllerProvider).isOnline) {
      showInfoSnack(context, 'You are offline — go online to process orders.');
      return;
    }

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
    _controller.beginAction(stopKey);
    try {
      // Always go through the offline-aware path: it queues + flushes
      // when online, and queues + updates the local cache when offline.
      // The user gets immediate visual feedback either way.
      final String message =
          await _controller.updateGenericStopStatusCommit(stop, newStatus);
      if (!mounted) return;
      showInfoSnack(context, message);
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      setState(() {
        _future = _loadTrip();
      });
    } catch (e) {
      if (!mounted) return;
      showInfoSnack(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) _controller.endAction(stopKey);
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

  /// Guarded end-to-end from the very first line — the in-flight guard is
  /// taken before the radius check or any sheet opens (not just around the
  /// final network call), closing a narrow double-tap race window that
  /// existed pre-refactor (see TripController.beginAction docs).
  Future<void> _handleDeliveredStop(ExternalDeliveryTripStop stop) async {
    final stopKey = _stopKey(stop);
    _controller.beginAction(stopKey);
    try {
      final (bool withinRadius, String? blockMessage) =
          _checkDeliveryRadiusFor(stop);
      if (!withinRadius) {
        if (mounted) showInfoSnack(context, blockMessage!);
        return;
      }

      final orderName = stop.externalDelivery.trim();

      // Fetch order detail first to determine payment mode
      ExternalDeliveryDetail? detail;
      try {
        detail = await ExternalDeliveryRepository().fetchDetail(
          orderName,
          resolveAddress: false,
        );
      } catch (_) {}
      if (!mounted) return;

      final double codAmount = detail?.codAmountToCollect ?? 0;
      final bool isCod = detail != null && detail.isCod && codAmount > 0;

      // Capture proof photo for both online and COD
      final photoPath = await showDeliveryProofSheet(context);
      if (!mounted) return;
      if (photoPath != null && orderName.isNotEmpty) {
        await ExternalDeliveryRepository().uploadProofPhoto(
          orderName: orderName,
          filePath: photoPath,
        );
      }
      if (!mounted) return;

      // Customer-facing OTP gate — transitions the External Delivery order
      // to Delivered server-side on success. Everything below just records
      // COD payment (if any) and flips the trip-stop row's own status.
      final bool? otpVerified = await showDeliveryOtpSheet(
        context,
        repository: ExternalDeliveryRepository(),
        externalDelivery: orderName,
      );
      if (!mounted || otpVerified != true) return;

      if (isCod) {
        // COD order: collect payment after proof
        final codResult = await showCodCollectionSheet(
          context,
          amountToCollect: codAmount,
        );
        if (!mounted) return;
        if (codResult == null) return;
        if (codResult.mode == 'Not Collected') {
          // Cash wasn't collected — ask whether to deliver anyway or fail the stop.
          final shouldFail = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Cash not collected'),
              content: const Text(
                'The customer did not pay. What would you like to do with this stop?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Deliver anyway'),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: context.danger),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Mark Failed'),
                ),
              ],
            ),
          );
          if (!mounted) return;
          if (shouldFail == null) return;
          if (shouldFail) {
            await _handleFailedDelivery(stop);
            return;
          }
          // Deliver anyway — fall through without calling markDeliveredWithCod.
        } else {
          try {
            await ExternalDeliveryRepository().markDeliveredWithCod(
              orderName,
              codCollectionMode: codResult.mode,
              codUpiReference: codResult.upiRef,
            );
          } catch (e) {
            if (mounted) showInfoSnack(context, 'COD save failed — continuing');
          }
          if (!mounted) return;
        }
      }

      try {
        await _controller.markDeliveredCommit(stop, isCod: isCod);
        if (!mounted) return;
        if (isCod) {
          // Delivering a COD stop moves its amount from in-flight exposure to
          // cash actually held; either way the limit needs a refetch.
          ref.invalidate(codLimitStatusProvider);
        }
        final isConnected = ConnectivityService().isConnected;
        final String completionMessage = isConnected
            ? 'Stop status updated to Delivered'
            : 'Saved offline. Will sync when reconnected.';
        await Future.delayed(const Duration(milliseconds: 800));
        if (!mounted) return;
        final Future<ExternalDeliveryTrip> newFuture = _loadTrip();
        setState(() {
          _future = newFuture;
        });
        _notifyStopCompleted(completionMessage, newFuture);
      } catch (e) {
        if (!mounted) return;
        showInfoSnack(context, e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) _controller.endAction(stopKey);
    }
  }

  /// Guarded end-to-end from the very first line — see
  /// TripController.beginAction docs for why (mirrors _handleDeliveredStop).
  Future<void> _handleFailedDelivery(ExternalDeliveryTripStop stop) async {
    final stopKey = _stopKey(stop);
    _controller.beginAction(stopKey);
    try {
      bool isCodStop = false;
      try {
        final d = await ExternalDeliveryRepository().fetchDetail(
          stop.externalDelivery.trim(),
          resolveAddress: false,
        );
        isCodStop = d.isCod;
      } catch (_) {}
      if (!mounted) return;

      final result = await showFailedDeliverySheet(context, isCod: isCodStop);
      if (result == null || !mounted) return;

      final orderName = stop.externalDelivery.trim();
      final fullReason = result.notes.isEmpty
          ? result.reason
          : '${result.reason} — ${result.notes}';

      // The full failed-delivery flow uploads a photo, mutates the order,
      // and (optionally) creates a server-side return trip. None of that
      // can run offline. If we're offline, fall back to a queued stop
      // status update so the driver can still mark Failed locally; the
      // photo + return-trip steps will need to be redone online.
      if (!ConnectivityService().isConnected) {
        try {
          await _controller.markFailedOfflineCommit(stop);
          if (!mounted) return;
          final Future<ExternalDeliveryTrip> newFuture = _loadTrip();
          setState(() {
            _future = newFuture;
          });
          _notifyStopCompleted(
            'Marked Failed offline. Photo upload and return trip will need '
            'to be done when back online.',
            newFuture,
          );
        } catch (e) {
          if (!mounted) return;
          showInfoSnack(context, e.toString().replaceFirst('Exception: ', ''));
        }
        return;
      }

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            content: Row(
              children: [
                const CircularProgressIndicator(strokeWidth: 2),
                const SizedBox(width: 20),
                Text(
                  'Marking delivery as failed...',
                  style: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurface,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      try {
        final processResult = await _controller.markFailedOnlineCommit(
          stop,
          orderName: orderName,
          fullReason: fullReason,
          reasonCode: result.reasonCode,
          photoPath: result.photoPath,
        );
        if (!mounted) return;
        Navigator.of(context).pop(); // dismiss loading dialog
        // Defer setState past the Navigator.pop rebuild to avoid calling it
        // during the build phase triggered by the dialog dismissal.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final Future<ExternalDeliveryTrip> newFuture = _loadTrip();
            setState(() { _future = newFuture; });
            _notifyStopCompleted(processResult.message, newFuture);
          }
        });
      } catch (e) {
        if (!mounted) return;
        Navigator.of(context).pop(); // dismiss loading dialog
        showInfoSnack(context, e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) _controller.endAction(stopKey);
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
              style: TextStyle(
                fontSize: 10,
                color: context.textSecondary,
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
      statusColor = context.success;
    } else if (statusNorm == 'failed') {
      statusColor = context.danger;
    } else if (statusNorm == 'out for delivery') {
      statusColor = context.scheme.primary;
    } else if (statusNorm == 'cancelled') {
      statusColor = context.textDisabled;
    } else {
      statusColor = context.textTertiary;
    }

    return Row(
      children: [
        Icon(Icons.location_on_outlined, size: 18, color: context.scheme.primary),
        const SizedBox(width: 6),
        Text(
          'Stop ${stop.stop}',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
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
              Icon(Icons.phone_outlined, size: 15, color: context.iconMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  stop.mobile,
                  style: TextStyle(
                    color: context.textPrimary,
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
                      color: context.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: context.success.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.call_rounded,
                          size: 13,
                          color: context.success,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Call',
                          style: TextStyle(
                            color: context.success,
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
          _stopNavigationButtons(
            address: cleanAddress,
            stopNumber: stop.stop,
            coords: _coordsFor(stop),
            onOpenInApp: () => _openInAppNavigationFor(stop),
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
            color: context.success,
          ),
        ],
        if (statusNorm == 'failed' && stop.failureReasonCode.isNotEmpty) ...[
          const SizedBox(height: 4),
          _stopInfoRow(
            Icons.cancel_outlined,
            stop.failureReasonLabel,
            color: context.danger,
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
    final textColor =
        color ?? (subtle ? context.textTertiary : context.textPrimary);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: color ?? context.iconMuted),
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
    final isUpdating = _controller.isUpdating(stopKey);

    if (isUpdating) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.scheme.primary,
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
            color: context.success,
            onTap: () => _updateStopStatus(stop, 'Delivered'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _actionButton(
            label: 'Failed',
            icon: Icons.close_rounded,
            color: context.danger,
            onTap: () => _updateStopStatus(stop, 'Failed'),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          onSelected: (status) {
            if (status == _skipForNowValue) {
              _skipForNow(stop);
            } else {
              _updateStopStatus(stop, status);
            }
          },
          itemBuilder: (context) {
            return [
              ...menuOptions.map(
                (s) => PopupMenuItem<String>(value: s, child: Text(s)),
              ),
              const PopupMenuItem<String>(
                value: _skipForNowValue,
                child: Text('Skip for now'),
              ),
            ];
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: context.fillSubtle,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.borderMuted),
            ),
            child: Icon(
              Icons.more_horiz,
              size: 18,
              color: context.textSecondary,
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

  /// Pushes the in-app navigation screen for [stop] — the live-tracking
  /// `DeliveryTrackingScreen` for delivery stops, or the simpler
  /// `TripStopMapScreen` for pickup stops (which has no delivery-specific
  /// Mark Failed/Confirm Delivery actions to wire up).
  void _openInAppNavigationFor(dynamic stop) {
    final (double, double)? coords = _coordsFor(stop);
    if (stop is ExternalDeliveryTripStop) {
      final String cleanAddress = _parseHtml(stop.address);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DeliveryTrackingScreen(
            deliveryName: stop.externalDelivery,
            customerName: stop.customer,
            contactNumber: stop.mobile,
            dropAddress: cleanAddress,
            dropLat: coords?.$1,
            dropLng: coords?.$2,
          ),
        ),
      );
    } else {
      final PickupTripStop ps = stop as PickupTripStop;
      final String cleanPickupAddress = _parseHtml(ps.pickupAddress);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TripStopMapScreen(
            address: cleanPickupAddress,
            stopNumber: ps.stop,
            knownLocation: coords == null ? null : LatLng(coords.$1, coords.$2),
          ),
        ),
      );
    }
  }

  /// Reacts to TripController.state.justCompletedTrip, set by
  /// TripController.maybeAutoCompleteTrip on success. Reloads the trip and
  /// shows the same "Trip completed" dialog as the original
  /// `_maybeAutoCompleteTrip` did inline.
  Future<void> _showTripCompletedDialog(ExternalDeliveryTrip trip) async {
    if (!mounted) return;
    setState(() {
      _future = _loadTrip();
    });
    if (!mounted) return;
    final int totalStops = trip.stops.length + trip.pickupStops.length;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trip completed'),
        content: Text('All $totalStops stops completed. Nice work!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    _controller.acknowledgeTripCompleted();
  }

  /// Shows a single completion notification, folding in a one-tap "Navigate"
  /// action to whatever pending stop is now nearest — so the driver never
  /// has to hunt through the list for it after finishing the current one.
  Future<void> _notifyStopCompleted(
    String completionMessage,
    Future<ExternalDeliveryTrip> tripFuture,
  ) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();

    dynamic next;
    ExternalDeliveryTrip? loadedTrip;
    try {
      final ExternalDeliveryTrip trip = await tripFuture;
      loadedTrip = trip;
      final List<dynamic> pendingOrdered = _pendingOrderedStops(trip);
      next = pendingOrdered.isEmpty ? null : pendingOrdered.first;
    } catch (_) {
      next = null;
    }
    if (!mounted) return;

    if (next == null) {
      showInfoSnack(context, completionMessage);
      if (loadedTrip != null) {
        unawaited(_controller.maybeAutoCompleteTrip(loadedTrip));
      }
      return;
    }

    final int stopNumber = next is ExternalDeliveryTripStop
        ? next.stop
        : (next as PickupTripStop).stop;
    final (double, double)? coords = _coordsFor(next);
    double? distanceMeters;
    final app = ref.read(appControllerProvider);
    final double? driverLat = app.currentLatitude;
    final double? driverLng = app.currentLongitude;
    if (coords != null && driverLat != null && driverLng != null) {
      distanceMeters = haversineMeters(driverLat, driverLng, coords.$1, coords.$2);
    }
    final String distanceLabel =
        distanceMeters != null ? ' · ${_formatDistance(distanceMeters)}' : '';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$completionMessage  →  Next: Stop $stopNumber$distanceLabel'),
        action: SnackBarAction(
          label: 'Navigate',
          onPressed: _navigateAllPendingStops,
        ),
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _stopNavigationButtons({
    required String address,
    required int? stopNumber,
    required (double, double)? coords,
    required VoidCallback onOpenInApp,
  }) {
    return Row(
      children: [
        Expanded(
          child: _actionButton(
            label: 'In-App',
            icon: Icons.navigation_rounded,
            color: context.scheme.primary,
            onTap: onOpenInApp,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _actionButton(
            label: 'Google Maps',
            icon: Icons.map_outlined,
            color: context.textSecondary,
            onTap: () => launchGoogleMapsNavigation(
              context,
              lat: coords?.$1,
              lng: coords?.$2,
              address: coords == null ? address : null,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _launchCall(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
}
