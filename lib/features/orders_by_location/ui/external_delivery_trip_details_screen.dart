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
import '../../../core/services/trip_route_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/context_colors.dart';
import '../../../core/widgets/app_shell.dart';
import '../model/external_delivery.dart';
import '../model/external_delivery_detail.dart';
import '../repository/external_delivery_repository.dart';
import '../../pickup_jobs/model/pickup_job.dart';
import '../../pickup_jobs/repository/pickup_job_repository.dart';
import 'cod_collection_sheet.dart';
import 'cod_handover_sheet.dart';
import 'delivery_proof_sheet.dart';
import 'failed_delivery_bottom_sheet.dart';

import '../../../core/utils/geo_distance.dart';
import 'trip_overview_map.dart';
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
  final Set<String> _updatingStops = <String>{};

  // ── Pickup flow State ──────────────────────────────────────────────────────
  final Map<String, PickupJob> _pickupJobDetails = {};
  bool _fetchingPickupDetails = false;
  // ───────────────────────────────────────────────────────────────────────────

  // ── Nearest-stop sequencing state ───────────────────────────────────────────
  // Resolved coordinates for pending stops, keyed by 'ed:<externalDelivery>' or
  // 'pj:<pickupJob>'. Best-effort — a stop with no entry here is excluded from
  // nearest-neighbor sorting and stays appended at the end in server order.
  final Map<String, (double, double)> _stopCoords = {};
  // Pure algorithm output — recalculated on load and after every
  // delivered/failed/skip event, never on a live GPS tick.
  List<String> _suggestedOrder = <String>[];
  // What's actually rendered/drag-reorderable. Mirrors _suggestedOrder until the
  // driver manually reorders, after which it only drops completed/vanished
  // stops and appends new ones, per the "manual order sticks" rule.
  List<String> _displayOrder = <String>[];
  bool _manualOrderActive = false;
  // ───────────────────────────────────────────────────────────────────────────

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
  /// the nearest-first sequence. [sequenceFrom], when provided, is used as the
  /// recalculation reference point instead of the driver's live GPS — used
  /// right after a stop is marked delivered/failed/skipped, per the "reference
  /// the just-completed stop's own location, not a live GPS ping" rule.
  Future<ExternalDeliveryTrip> _loadTrip({(double, double)? sequenceFrom}) async {
    final ExternalDeliveryTrip trip = await _fetchTrip();
    await _resolveStopSequencing(trip, referenceOverride: sequenceFrom);
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

  static const Set<String> _terminalStopStatuses = <String>{
    'delivered',
    'returned',
    'failed',
    'cancelled',
    'received at store',
  };

  bool _isTerminalStop(dynamic stop) {
    final String status = stop is ExternalDeliveryTripStop
        ? stop.status
        : (stop as PickupTripStop).status;
    return _terminalStopStatuses.contains(status.trim().toLowerCase());
  }

  (double, double)? _coordsFor(dynamic stop) {
    if (stop is ExternalDeliveryTripStop) {
      return _stopCoords['ed:${stop.externalDelivery}'];
    } else if (stop is PickupTripStop) {
      return _stopCoords['pj:${stop.pickupJob}'];
    }
    return null;
  }

  /// Resolves coordinates for pending stops (joining delivery stops to their
  /// [ExternalDelivery] record and pickup stops to their [PickupJob] record)
  /// and recomputes [_suggestedOrder]/[_displayOrder]. Best-effort: a network
  /// failure here never breaks the trip screen — unresolved stops simply stay
  /// in their original server order at the end of the list.
  Future<void> _resolveStopSequencing(
    ExternalDeliveryTrip trip, {
    (double, double)? referenceOverride,
  }) async {
    final List<ExternalDeliveryTripStop> pendingDeliveryStops = trip.stops
        .where((s) => !_isTerminalStop(s))
        .toList();
    final List<PickupTripStop> pendingPickupStops = trip.pickupStops
        .where((s) => !_isTerminalStop(s))
        .toList();

    final List<String> missingDeliveryNames = pendingDeliveryStops
        .map((s) => s.externalDelivery)
        .where((n) => n.isNotEmpty)
        .toSet()
        .where((n) => !_stopCoords.containsKey('ed:$n'))
        .toList();
    if (missingDeliveryNames.isNotEmpty) {
      try {
        final Map<String, ExternalDelivery> resolved =
            await ExternalDeliveryRepository().fetchDeliveriesByNames(
          missingDeliveryNames,
        );
        for (final MapEntry<String, ExternalDelivery> entry
            in resolved.entries) {
          final double? lat = entry.value.latitude;
          final double? lng = entry.value.longitude;
          if (lat != null && lng != null) {
            _stopCoords['ed:${entry.key}'] = (lat, lng);
          }
        }
      } catch (_) {
        // Best-effort — those stops just stay unsorted at the end.
      }
    }

    final List<String> missingPickupNames = pendingPickupStops
        .map((s) => s.pickupJob)
        .where((n) => n.isNotEmpty)
        .toSet()
        .where((n) => !_stopCoords.containsKey('pj:$n'))
        .toList();
    if (missingPickupNames.isNotEmpty) {
      final PickupJobRepository repo = PickupJobRepository();
      final List<PickupJob?> results = await Future.wait(
        missingPickupNames.map((String n) async {
          try {
            return await repo.fetchJob(n);
          } catch (_) {
            return null;
          }
        }),
      );
      for (final PickupJob job in results.whereType<PickupJob>()) {
        final double? lat = job.pickupLatitude;
        final double? lng = job.pickupLongitude;
        if (lat != null && lng != null) {
          _stopCoords['pj:${job.name}'] = (lat, lng);
        }
      }
    }

    final List<String> pendingKeys = <String>[
      for (final ExternalDeliveryTripStop s in pendingDeliveryStops) _stopKey(s),
      for (final PickupTripStop s in pendingPickupStops) _stopKey(s),
    ];
    final Map<String, String> coordKeyOf = <String, String>{
      for (final ExternalDeliveryTripStop s in pendingDeliveryStops)
        _stopKey(s): 'ed:${s.externalDelivery}',
      for (final PickupTripStop s in pendingPickupStops)
        _stopKey(s): 'pj:${s.pickupJob}',
    };

    final double? fromLat =
        referenceOverride?.$1 ?? ref.read(appControllerProvider).currentLatitude;
    final double? fromLng =
        referenceOverride?.$2 ?? ref.read(appControllerProvider).currentLongitude;

    if (fromLat != null && fromLng != null) {
      _suggestedOrder = nearestNeighborOrder<String>(
        fromLat,
        fromLng,
        pendingKeys,
        coordsOf: (String key) => _stopCoords[coordKeyOf[key]],
      );
    } else {
      _suggestedOrder = pendingKeys;
    }

    if (!_manualOrderActive) {
      _displayOrder = List<String>.from(_suggestedOrder);
    } else {
      final Set<String> pendingSet = pendingKeys.toSet();
      final List<String> kept = _displayOrder
          .where((String k) => pendingSet.contains(k))
          .toList();
      final List<String> newOnes = pendingKeys
          .where((String k) => !kept.contains(k))
          .toList();
      _displayOrder = <String>[...kept, ...newOnes];
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

  Widget _stopsTab(ExternalDeliveryTrip trip) {
    final List<dynamic> allStops = [...trip.stops, ...trip.pickupStops];
    final Map<String, dynamic> stopByKey = {
      for (final dynamic s in allStops) _stopKey(s): s,
    };

    // Pending stops render in nearest-first (or manually reordered) sequence;
    // completed/failed/etc. stops move to a collapsed section below.
    final List<dynamic> pendingOrdered = [
      for (final String key in _displayOrder)
        if (stopByKey.containsKey(key)) stopByKey[key]!,
    ];
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

    final List<OverviewMapStop> mapStops = [];
    for (int i = 0; i < pendingOrdered.length; i++) {
      final (double, double)? coords = _coordsFor(pendingOrdered[i]);
      if (coords != null) {
        mapStops.add(
          OverviewMapStop(
            id: _stopKey(pendingOrdered[i]),
            sequenceNumber: i + 1,
            lat: coords.$1,
            lng: coords.$2,
            status: i == 0 ? StopMapStatus.active : StopMapStatus.pending,
          ),
        );
      }
    }
    for (final dynamic stop in completed) {
      final (double, double)? coords = _coordsFor(stop);
      if (coords != null) {
        mapStops.add(
          OverviewMapStop(
            id: _stopKey(stop),
            sequenceNumber: 0,
            lat: coords.$1,
            lng: coords.$2,
            status: StopMapStatus.completed,
          ),
        );
      }
    }

    double? nextStopDistanceMeters;
    if (pendingOrdered.isNotEmpty) {
      final app = ref.watch(appControllerProvider);
      final (double, double)? coords = _coordsFor(pendingOrdered.first);
      final double? driverLat = app.currentLatitude;
      final double? driverLng = app.currentLongitude;
      if (coords != null && driverLat != null && driverLng != null) {
        nextStopDistanceMeters =
            haversineMeters(driverLat, driverLng, coords.$1, coords.$2);
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
          if (mapStops.isNotEmpty) ...[
            _overviewMapButton(mapStops),
            const SizedBox(height: 10),
          ],
          if (_manualOrderActive && pendingOrdered.isNotEmpty)
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
                    onTap: () => setState(() {
                      _manualOrderActive = false;
                      _displayOrder = List<String>.from(_suggestedOrder);
                    }),
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
                  setState(() {
                    final String moved = _displayOrder.removeAt(oldIndex);
                    _displayOrder.insert(newIndex, moved);
                    _manualOrderActive = true;
                  });
                },
                itemBuilder: (context, index) {
                  final dynamic stop = pendingOrdered[index];
                  final String key = _stopKey(stop);
                  final bool isNext = index == 0;
                  final bool isSuggestedNext = _suggestedOrder.isNotEmpty &&
                      _suggestedOrder.first == key;

                  final Widget card = stop is ExternalDeliveryTripStop
                      ? Padding(
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
                            if (isNext)
                              _nearestStopBanner(
                                distanceMeters: nextStopDistanceMeters,
                              )
                            else if (isSuggestedNext)
                              _suggestedPill(),
                            card,
                          ],
                        ),
                      ),
                    ],
                  );

                  if (!isNext) return KeyedSubtree(key: ValueKey(key), child: row);

                  return Container(
                    key: ValueKey(key),
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: context.success.withValues(alpha: 0.05),
                      border: Border.all(
                        color: context.success.withValues(alpha: 0.28),
                        width: 1.4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: context.success.withValues(alpha: 0.10),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
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

  Widget _overviewMapButton(List<OverviewMapStop> mapStops) {
    final int completedCount = mapStops
        .where((OverviewMapStop s) => s.status == StopMapStatus.completed)
        .length;
    return GestureDetector(
      onTap: () => _openOverviewMap(mapStops),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: context.scheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: context.scheme.primary.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.scheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.map_rounded,
                size: 18,
                color: context.scheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'View trip map',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$completedCount of ${mapStops.length} stops completed',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: context.scheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  void _openOverviewMap(List<OverviewMapStop> mapStops) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TripRouteMapScreen(mapStops: mapStops),
      ),
    );
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m away';
    return '${(meters / 1000).toStringAsFixed(1)} km away';
  }

  Widget _nearestStopBanner({required double? distanceMeters}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: context.success,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: context.success.withValues(alpha: 0.35),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(
              Icons.navigation_rounded,
              size: 13,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Nearest stop',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.success,
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
    final String key = _stopKey(stop);
    setState(() {
      _displayOrder.remove(key);
      _displayOrder.add(key);
      _manualOrderActive = true;
    });
    showInfoSnack(context, 'Moved to the back of the queue');
  }

  Widget _pickupStopCard(ExternalDeliveryTrip trip, PickupTripStop ps) {
    final statusNorm = ps.status.trim().toLowerCase();
    final Color statusColor;
    switch (statusNorm) {
      case 'received at store':
        statusColor = context.success;
      case 'picked up':
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
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) {
                      final (double, double)? coords = _coordsFor(ps);
                      return TripStopMapScreen(
                        address: cleanPickupAddress,
                        stopNumber: ps.stop,
                        knownLocation: coords == null
                            ? null
                            : LatLng(coords.$1, coords.$2),
                      );
                    },
                  ),
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: context.scheme.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: context.scheme.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.navigation_rounded,
                        size: 15,
                        color: context.scheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Navigate to Pickup',
                        style: TextStyle(
                          color: context.scheme.primary,
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
    final isUpdating = _updatingStops.contains(stopKey);

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

    if (statusNorm == 'picked up') {
      return SizedBox(
        width: double.infinity,
        child: _actionButton(
          label: 'Mark Received at Store',
          icon: Icons.store_outlined,
          color: context.success,
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
            color: context.scheme.primary,
            onTap: () => _handlePickupAction(ps, 'Picked Up'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _actionButton(
            label: 'Failed',
            icon: Icons.close_rounded,
            color: context.danger,
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
      final (double, double)? sequenceFrom = _coordsFor(ps);
      setState(() {
        _future = _loadTrip(sequenceFrom: sequenceFrom);
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
      final (double, double)? sequenceFrom = _coordsFor(stop);
      setState(() {
        _future = _loadTrip(sequenceFrom: sequenceFrom);
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

    final stopKey = _stopKey(stop);
    setState(() => _updatingStops.add(stopKey));
    try {
      final stopDocType = (stop.rawFields['doctype'] ?? '').toString().trim();
      final stopName = (stop.rawFields['name'] ?? '').toString().trim();
      final parentTripName = (stop.rawFields['parent'] ?? '').toString().trim();

      // COD + online: the async-queue flush (conflict check + PUT) can exceed
      // the 800ms reload window, causing the stop to reappear as editable.
      // Use the direct awaited path instead when we know we have connectivity.
      if (isCod && ConnectivityService().isConnected) {
        await ExternalDeliveryRepository().updateTripStopStatus(
          stop: stop,
          newStatus: 'Delivered',
        );
      } else {
        await OfflineTripManager().updateStopStatusOffline(
          stopDocType: stopDocType,
          stopName: stopName,
          parentTripName: parentTripName,
          orderName: stop.externalDelivery.trim(),
          newStatus: 'Delivered',
        );
      }
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
      final (double, double)? sequenceFrom = _coordsFor(stop);
      setState(() {
        _future = _loadTrip(sequenceFrom: sequenceFrom);
      });
    } catch (e) {
      if (!mounted) return;
      showInfoSnack(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _updatingStops.remove(stopKey));
    }
  }

  Future<void> _handleFailedDelivery(ExternalDeliveryTripStop stop) async {
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
        final (double, double)? sequenceFrom = _coordsFor(stop);
        setState(() {
          _future = _loadTrip(sequenceFrom: sequenceFrom);
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
      Navigator.of(context).pop(); // dismiss loading dialog
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
      // Defer setState past the Navigator.pop rebuild to avoid calling it
      // during the build phase triggered by the dialog dismissal.
      final (double, double)? sequenceFrom = _coordsFor(stop);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() { _future = _loadTrip(sequenceFrom: sequenceFrom); });
        }
      });
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loading dialog
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
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) {
                  final (double, double)? coords = _coordsFor(stop);
                  return TripStopMapScreen(
                    address: cleanAddress,
                    stopNumber: stop.stop,
                    knownLocation: coords == null
                        ? null
                        : LatLng(coords.$1, coords.$2),
                  );
                },
              ),
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: context.scheme.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: context.scheme.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.navigation_rounded,
                    size: 15,
                    color: context.scheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Navigate',
                    style: TextStyle(
                      color: context.scheme.primary,
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
    final isUpdating = _updatingStops.contains(stopKey);

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

  Future<void> _launchCall(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
}

/// Full-screen route coordination map. Opens immediately with a straight-line
/// fallback route (so the button never feels laggy), then upgrades to a real
/// road-following polyline once the best-effort OSRM fetch resolves.
class _TripRouteMapScreen extends ConsumerStatefulWidget {
  const _TripRouteMapScreen({required this.mapStops});

  final List<OverviewMapStop> mapStops;

  @override
  ConsumerState<_TripRouteMapScreen> createState() =>
      _TripRouteMapScreenState();
}

class _TripRouteMapScreenState extends ConsumerState<_TripRouteMapScreen> {
  List<LatLng>? _routePoints;
  bool _routeRequested = false;

  Future<void> _fetchRoute(double driverLat, double driverLng) async {
    final List<LatLng> pendingPoints = [
      for (final OverviewMapStop s in widget.mapStops)
        if (s.status != StopMapStatus.completed) LatLng(s.lat, s.lng),
    ];
    if (pendingPoints.isEmpty) return;
    final List<LatLng> result = await TripRouteService.fetchRoute(
          [LatLng(driverLat, driverLng), ...pendingPoints],
        ) ??
        <LatLng>[];
    if (mounted && result.isNotEmpty) {
      setState(() => _routePoints = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider);
    final double? driverLat = app.currentLatitude;
    final double? driverLng = app.currentLongitude;

    if (!_routeRequested && driverLat != null && driverLng != null) {
      _routeRequested = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _fetchRoute(driverLat, driverLng),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: TripOverviewMap(
              stops: widget.mapStops,
              driverLat: driverLat,
              driverLng: driverLng,
              routePoints: _routePoints,
              height: null,
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: context.cardColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: context.textPrimary,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
