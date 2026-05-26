import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/database/partner_timing_log_dao.dart';
import '../../../core/state/providers.dart';
import 'trip_stage_timeline_widget.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/offline_trip_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_shell.dart';
import '../model/external_delivery.dart';
import '../repository/external_delivery_repository.dart';
import 'delivery_proof_sheet.dart';
import 'failed_delivery_bottom_sheet.dart';
import 'recall_interstitial_sheet.dart';
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

  // ── Recall flow ────────────────────────────────────────────────────────────
  Timer? _pollTimer;
  ExternalDeliveryTrip? _cachedTrip;
  final Set<String> _seenRecallPending = {};
  final Set<String> _recallRetryStops = {};
  String get _recallRetryPrefsKey => 'pending_recall_retries_${widget.tripName}';

  static const Color _recallOrange = Color(0xFFE65100);
  static const Color _recallAmber = Color(0xFFFFF8E1);
  // ───────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _future = _loadTripAndInitRecall();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => _pollForRecallTransition(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
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
      final trip =
          await ExternalDeliveryRepository().fetchTripDetails(widget.tripName);
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

  // Seeds _cachedTrip and _seenRecallPending, then restores any persisted retries.
  Future<ExternalDeliveryTrip> _loadTripAndInitRecall() async {
    final trip = await _loadTrip();
    _cachedTrip = trip;
    for (final s in trip.stops) {
      if (_isRecallPendingStatus(s.status)) {
        _seenRecallPending.add(_stopKey(s));
      }
    }
    await _restorePersistedRecallRetries(trip);
    return trip;
  }

  // Diffs cached vs fresh trip; toasts + re-renders when a new Recall Pending found.
  Future<void> _pollForRecallTransition() async {
    if (!ConnectivityService().isConnected || !mounted) return;
    try {
      final fresh = await ExternalDeliveryRepository()
          .fetchTripDetails(widget.tripName);
      if (!mounted) return;
      bool hasNewRecall = false;
      final prev = _cachedTrip;
      for (final stop in fresh.stops) {
        final key = _stopKey(stop);
        final prevStop =
            prev?.stops.where((s) => _stopKey(s) == key).firstOrNull;
        if (_isRecallPendingStatus(stop.status) &&
            !_isRecallPendingStatus(prevStop?.status ?? '') &&
            !_seenRecallPending.contains(key)) {
          _seenRecallPending.add(key);
          hasNewRecall = true;
        }
      }
      _cachedTrip = fresh;
      if (hasNewRecall) {
        setState(() => _future = Future.value(fresh));
        await _showRecallInterstitial(fresh);
      }
    } catch (_) {}
  }

  /// Full-screen bottom sheet that fires the moment a Recall Pending is detected.
  /// Driver must tap "Got it" before interacting with anything else.
  Future<void> _showRecallInterstitial(ExternalDeliveryTrip trip) async {
    if (!mounted) return;
    final recallCount =
        trip.stops.where((s) => _isRecallPendingStatus(s.status)).length;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      builder: (_) => RecallInterstitialSheet(recallCount: recallCount),
    );
  }

  Future<void> _restorePersistedRecallRetries(ExternalDeliveryTrip trip) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final persisted = prefs.getStringList(_recallRetryPrefsKey) ?? [];
      if (persisted.isEmpty) return;
      final pending = persisted.toSet();
      for (final s in trip.stops) {
        if (pending.contains(s.externalDelivery)) {
          _recallRetryStops.add(_stopKey(s));
        }
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _persistRecallRetry(String externalDelivery) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_recallRetryPrefsKey) ?? [];
      if (!existing.contains(externalDelivery)) {
        await prefs.setStringList(
            _recallRetryPrefsKey, [...existing, externalDelivery]);
      }
    } catch (_) {}
  }

  Future<void> _clearPersistedRecallRetry(String externalDelivery) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_recallRetryPrefsKey) ?? [];
      await prefs.setStringList(
        _recallRetryPrefsKey,
        existing.where((e) => e != externalDelivery).toList(),
      );
    } catch (_) {}
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
                  unselectedLabelColor:
                      scheme.onSurface.withValues(alpha: 0.6),
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
    final remaining = (trip.totalStops - trip.completedStops).clamp(0, trip.totalStops);
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
                _statBox('Total', '${trip.totalStops}', Icons.route_outlined, AppTheme.oceanBlue),
                const SizedBox(width: 8),
                _statBox('Done', '${trip.completedStops}', Icons.check_circle_outline, const Color(0xFF2E7D32)),
                const SizedBox(width: 8),
                _statBox('Left', '$remaining', Icons.pending_outlined, AppTheme.mango),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: trip.totalStops > 0 ? trip.completedStops / trip.totalStops : 0,
                backgroundColor: Colors.black12,
                valueColor: AlwaysStoppedAnimation<Color>(
                  trip.completedStops >= trip.totalStops && trip.totalStops > 0
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
                const Text('Progress', style: TextStyle(fontSize: 11, color: Colors.black45)),
                Text(
                  '${trip.completedStops}/${trip.totalStops} stops',
                  style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            if (trip.totalDistanceKm > 0) ...[
              const SizedBox(height: 14),
              const Divider(height: 1, color: Colors.black12),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.route_outlined, size: 16, color: AppTheme.oceanBlue),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Total Distance', style: TextStyle(color: Colors.black54, fontSize: 13)),
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
                  const Icon(Icons.play_circle_outline, size: 16, color: AppTheme.oceanBlue),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Started', style: TextStyle(color: Colors.black54, fontSize: 13)),
                  ),
                  Text(trip.startedAt, style: const TextStyle(color: AppTheme.nightBlue, fontSize: 12)),
                ],
              ),
            ],
            if (trip.completedAt.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.stop_circle_outlined, size: 16, color: Color(0xFF2E7D32)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Completed', style: TextStyle(color: Colors.black54, fontSize: 13)),
                  ),
                  Text(trip.completedAt, style: const TextStyle(color: AppTheme.nightBlue, fontSize: 12)),
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
    final remaining = (trip.totalStops - trip.completedStops).clamp(0, trip.totalStops);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          FrostCard(
            child: Column(
              children: [
                _tripInfoRow(Icons.person_outline, 'Driver', driver),
                _tripInfoRow(Icons.calendar_month_outlined, 'Trip Date', tripDate),
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
                      _statBox('Total', '${trip.totalStops}', Icons.route_outlined, AppTheme.oceanBlue),
                      const SizedBox(width: 8),
                      _statBox('Done', '${trip.completedStops}', Icons.check_circle_outline, const Color(0xFF2E7D32)),
                      const SizedBox(width: 8),
                      _statBox('Left', '$remaining', Icons.pending_outlined, AppTheme.mango),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: trip.totalStops > 0 ? trip.completedStops / trip.totalStops : 0,
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
    )
        .animate()
        .fadeIn(duration: 220.ms)
        .slideY(begin: 0.03, end: 0);
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
        trip.stops.every(
          (s) => s.status.trim().toLowerCase() == 'delivered',
        );

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
                Icon(Icons.check_circle_outline, color: Color(0xFF2E7D32), size: 20),
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
                    const Icon(Icons.undo_rounded, color: AppTheme.mango, size: 20),
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
          style: TextStyle(
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
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
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final orderedStops = trip.stops.asMap().entries.toList();
    final recallPendingStops =
        trip.stops.where((s) => _isRecallPendingStatus(s.status)).toList();
    final hasRecall = recallPendingStops.isNotEmpty;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          if (trip.isReturnTrip) ...[
            _returnTripBanner(trip),
            const SizedBox(height: 10),
          ],
          if (hasRecall) ...[
            _recallTripBanner(recallPendingStops.length),
            const SizedBox(height: 10),
          ],
          if (trip.stops.isEmpty)
            FrostCard(
              child: Text(
                'No stops found',
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            )
          else
            ...orderedStops.map((entry) {
              final isRecall = _isRecallPendingStatus(entry.value.status);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: isRecall
                    ? _recallStopCard(trip, entry.value)
                    : FrostCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _stopHeader(entry.value),
                            const SizedBox(height: 12),
                            _stopInfoCard(entry.value),
                            if (_isStopEditable(
                              tripStatus: trip.status,
                              stopStatus: entry.value.status,
                            )) ...[
                              const SizedBox(height: 12),
                              const Divider(height: 1, color: Colors.black12),
                              const SizedBox(height: 10),
                              _stopActionButtons(trip, entry.value),
                            ],
                          ],
                        ),
                      ),
              );
            }),
        ],
      ),
    );
  }

  // ── Recall trip-level banner ──────────────────────────────────────────────

  Widget _recallTripBanner(int count) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: _recallOrange,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _recallOrange.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.u_turn_left_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count == 1
                      ? 'Order Recalled — Turn Around'
                      : '$count Orders Recalled — Turn Around',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Return items to store and confirm at the dock',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .shimmer(
          duration: 1800.ms,
          color: Colors.white.withValues(alpha: 0.15),
        );
  }

  // ── Recall stop card ──────────────────────────────────────────────────────

  Widget _recallStopCard(ExternalDeliveryTrip trip, ExternalDeliveryTripStop stop) {
    return Container(
      decoration: BoxDecoration(
        color: _recallAmber,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _recallOrange.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _recallOrange.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Solid orange header strip
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              color: _recallOrange,
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.white, size: 17),
                  const SizedBox(width: 8),
                  const Text(
                    'RECALL — RETURN TO STORE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Customer Cancelled',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _stopHeader(stop),
                  const SizedBox(height: 12),
                  _stopInfoCard(stop, isRecall: true),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Color(0xFFFFCC80)),
                  const SizedBox(height: 10),
                  _stopActionButtons(trip, stop),
                ],
              ),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.06, end: 0, duration: 300.ms, curve: Curves.easeOut);
  }

  Future<void> _handleConfirmRecall(ExternalDeliveryTripStop stop) async {
    // Fetch item count before showing the dialog; degrade gracefully on failure.
    int? itemCount;
    if (ConnectivityService().isConnected && stop.externalDelivery.isNotEmpty) {
      try {
        final detail = await ExternalDeliveryRepository()
            .fetchDetail(stop.externalDelivery, resolveAddress: false);
        itemCount = detail.items.length;
      } catch (_) {}
    }
    if (!mounted) return;

    final scheme = Theme.of(context).colorScheme;
    final customerLabel =
        stop.customer.isNotEmpty ? stop.customer : 'this customer';
    final bodyText = itemCount != null
        ? '$itemCount item${itemCount == 1 ? '' : 's'} for $customerLabel — confirm return to store?'
        : "You're returning items for $customerLabel — confirm?";

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.store_rounded, color: _recallOrange),
            const SizedBox(width: 8),
            Text(
              'Confirm Recall',
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Text(
          bodyText,
          style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _recallOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    if (!ConnectivityService().isConnected) {
      showInfoSnack(context, 'You are offline — connect and try again.');
      return;
    }

    final stopKey = _stopKey(stop);
    setState(() => _updatingStops.add(stopKey));
    try {
      final result = await ExternalDeliveryRepository()
          .confirmRecallReceivedAtStore(
        externalDelivery: stop.externalDelivery,
      );
      if (!mounted) return;
      final alreadyReturned = result['already_returned'] == true;
      showInfoSnack(
        context,
        alreadyReturned
            ? 'Already confirmed'
            : 'Recall confirmed — items returned to store.',
      );
      unawaited(_clearPersistedRecallRetry(stop.externalDelivery));
      setState(() {
        _recallRetryStops.remove(stopKey);
        _future = _loadTrip();
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      final isValidationError =
          msg.contains('no active recall') || msg.contains('validationerror');
      if (isValidationError) {
        showInfoSnack(
          context,
          'No active recall found for this order. It may have already been processed.',
        );
      } else {
        unawaited(_persistRecallRetry(stop.externalDelivery));
        setState(() => _recallRetryStops.add(stopKey));
        showInfoSnack(
          context,
          'Could not confirm recall. Tap "Try Again" to retry.',
        );
      }
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
    // Normalise underscores so 'recall_pending' == 'recall pending'
    final normalizedStopStatus =
        stopStatus.trim().toLowerCase().replaceAll('_', ' ');
    const lockedStopStatuses = <String>{
      'delivered',
      'returned',
      'failed',
      'recall pending',
    };

    if (normalizedTripStatus == 'completed') {
      return false;
    }

    if (lockedStopStatuses.contains(normalizedStopStatus)) {
      return false;
    }

    return true;
  }

  String _stopKey(ExternalDeliveryTripStop stop) {
    final rowName = (stop.rawFields['name'] ?? '').toString().trim();
    if (rowName.isNotEmpty) return rowName;
    return '${stop.externalDelivery}-${stop.stop}';
  }

  bool _isRecallPendingStatus(String status) {
    final s = status.trim().toLowerCase().replaceAll('_', ' ');
    return s == 'recall pending';
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
      final parentTripName =
          (stop.rawFields['parent'] ?? '').toString().trim();
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
    ref.read(appControllerProvider).recordTimingEvent(
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
      final stopDocType =
          (stop.rawFields['doctype'] ?? '').toString().trim();
      final stopName = (stop.rawFields['name'] ?? '').toString().trim();
      final parentTripName =
          (stop.rawFields['parent'] ?? '').toString().trim();
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

    final scheme = Theme.of(context).colorScheme;
    final createReturn = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.undo_rounded, color: AppTheme.oceanBlue),
            const SizedBox(width: 8),
            Text(
              'Return to Store?',
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Text(
          'Create a return trip to bring "$orderName" back to the store?',
          style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
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
            child: const Text('Yes, Return'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    // The full failed-delivery flow uploads a photo, mutates the order,
    // and (optionally) creates a server-side return trip. None of that
    // can run offline. If we're offline, fall back to a queued stop
    // status update so the driver can still mark Failed locally; the
    // photo + return-trip steps will need to be redone online.
    if (!ConnectivityService().isConnected) {
      setState(() => _updatingStops.add(stopKey));
      try {
        final stopDocType =
            (stop.rawFields['doctype'] ?? '').toString().trim();
        final stopName = (stop.rawFields['name'] ?? '').toString().trim();
        final parentTripName =
            (stop.rawFields['parent'] ?? '').toString().trim();
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
        photoPath: result.photoPath,
        shouldCreateReturnTrip: createReturn == true,
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
      if (processResult.tripName != null && createReturn == true) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ExternalDeliveryTripDetailsScreen(
              tripName: processResult.tripName!,
            ),
          ),
        );
      }
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
    final statusNorm =
        stop.status.trim().toLowerCase().replaceAll('_', ' ');
    final Color statusColor;
    if (statusNorm == 'delivered' || statusNorm == 'returned') {
      statusColor = const Color(0xFF2E7D32);
    } else if (statusNorm == 'failed') {
      statusColor = Colors.red;
    } else if (statusNorm == 'out for delivery') {
      statusColor = AppTheme.oceanBlue;
    } else if (statusNorm == 'recall pending') {
      statusColor = _recallOrange;
    } else if (statusNorm == 'cancelled') {
      statusColor = Colors.black38;
    } else {
      statusColor = Colors.black45;
    }

    return Row(
      children: [
        Icon(
          statusNorm == 'recall pending'
              ? Icons.warning_amber_rounded
              : Icons.location_on_outlined,
          size: 18,
          color: statusNorm == 'recall pending'
              ? _recallOrange
              : AppTheme.oceanBlue,
        ),
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

  Widget _stopInfoCard(ExternalDeliveryTripStop stop, {bool isRecall = false}) {
    final String storeAddress =
        (stop.rawFields['drop_address']?.toString().trim() ?? '');
    final String navAddress = isRecall ? storeAddress : stop.address;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stop.customer.isNotEmpty) ...[
          _stopInfoRow(Icons.person_outline, stop.customer),
          const SizedBox(height: 6),
        ],
        if (stop.address.isNotEmpty) ...[
          _stopInfoRow(Icons.location_on_outlined, stop.address),
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
                  style: const TextStyle(color: AppTheme.nightBlue, fontSize: 13),
                ),
              ),
              GestureDetector(
                onTap: () => _launchCall(stop.mobile),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                      Icon(Icons.call_rounded, size: 13, color: Color(0xFF2E7D32)),
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
        if (navAddress.isNotEmpty) ...[
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TripStopMapScreen(
                  address: navAddress,
                  stopNumber: stop.stop,
                ),
              ),
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: isRecall
                    ? _recallOrange.withValues(alpha: 0.07)
                    : AppTheme.oceanBlue.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isRecall
                      ? _recallOrange.withValues(alpha: 0.3)
                      : AppTheme.oceanBlue.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isRecall ? Icons.store_rounded : Icons.navigation_rounded,
                    size: 15,
                    color: isRecall ? _recallOrange : AppTheme.oceanBlue,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isRecall ? 'Navigate to Store' : 'Navigate',
                    style: TextStyle(
                      color: isRecall ? _recallOrange : AppTheme.oceanBlue,
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
          _stopInfoRow(Icons.receipt_long_outlined, stop.externalDelivery, subtle: true),
        if (stop.deliveredAt.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          _stopInfoRow(
            Icons.check_circle_outline,
            'Delivered: ${stop.deliveredAt}',
            color: const Color(0xFF2E7D32),
          ),
        ],
        if (stop.notes.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          _stopInfoRow(Icons.notes_rounded, stop.notes, subtle: true),
        ],
      ],
    );
  }

  Widget _stopInfoRow(IconData icon, String text, {bool subtle = false, Color? color}) {
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
            style: TextStyle(
              color: textColor,
              fontSize: subtle ? 12 : 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _stopActionButtons(ExternalDeliveryTrip trip, ExternalDeliveryTripStop stop) {
    final stopKey = _stopKey(stop);
    final isUpdating = _updatingStops.contains(stopKey);
    final isRecallPending = _isRecallPendingStatus(stop.status);
    // If ANY stop on the trip is Recall Pending, disable Delivered on ALL other stops.
    final tripHasRecall =
        trip.stops.any((s) => _isRecallPendingStatus(s.status));

    if (isUpdating) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.oceanBlue),
          ),
        ),
      );
    }

    if (isRecallPending) {
      final needsRetry = _recallRetryStops.contains(stopKey);
      return SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor:
                needsRetry ? Colors.orange.shade700 : _recallOrange,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          icon: Icon(
            needsRetry ? Icons.refresh_rounded : Icons.store_rounded,
            size: 18,
          ),
          label: Text(
            needsRetry ? 'Try Again' : 'Confirm Recall at Store',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          onPressed: () => _handleConfirmRecall(stop),
        ),
      );
    }

    // When the trip has an active recall, block "Delivered" on all other stops.
    // Driver must resolve the recall first.
    if (tripHasRecall) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _recallOrange.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _recallOrange.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_outline, size: 14, color: _recallOrange),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Resolve recalled order first before marking others delivered',
                style: TextStyle(
                  color: _recallOrange,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Scrub Delivered/Failed from the popup options list
    final menuOptions = _stopStatusOptions
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
            child: const Icon(Icons.more_horiz, size: 18, color: Colors.black54),
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


