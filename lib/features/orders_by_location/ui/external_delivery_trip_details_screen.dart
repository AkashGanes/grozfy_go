import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/connectivity_service.dart';
import '../../../core/services/offline_trip_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_shell.dart';
import '../model/external_delivery.dart';
import '../repository/external_delivery_repository.dart';
import 'delivery_proof_sheet.dart';
import 'failed_delivery_bottom_sheet.dart';
import 'trip_stop_map_screen.dart';

class ExternalDeliveryTripDetailsScreen extends StatefulWidget {
  const ExternalDeliveryTripDetailsScreen({super.key, required this.tripName});

  final String tripName;

  @override
  State<ExternalDeliveryTripDetailsScreen> createState() =>
      _ExternalDeliveryTripDetailsScreenState();
}

class _ExternalDeliveryTripDetailsScreenState
    extends State<ExternalDeliveryTripDetailsScreen> {
  late Future<ExternalDeliveryTrip> _future;
  static const List<String> _stopStatusOptions = <String>[
    'Pending',
    'Out for Delivery',
    'Delivered',
    'Failed',
    'Cancelled',
  ];
  final Set<String> _updatingStops = <String>{};

  @override
  void initState() {
    super.initState();
    _future = _loadTrip();
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
      child: FrostCard(
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
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          if (trip.isReturnTrip) ...[
            _returnTripBanner(trip),
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
            ...orderedStops.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FrostCard(
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
              ),
            ),
        ],
      ),
    );
  }

  bool _isStopEditable({
    required String tripStatus,
    required String stopStatus,
  }) {
    final normalizedTripStatus = tripStatus.trim().toLowerCase();
    final normalizedStopStatus = stopStatus.trim().toLowerCase();
    const lockedStopStatuses = <String>{
      'delivered',
      'returned',
      'failed',
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
      await ExternalDeliveryRepository().updateTripStopStatus(
        stop: stop,
        newStatus: 'Delivered',
      );
      if (!mounted) return;
      showInfoSnack(context, 'Stop status updated to Delivered');
      setState(() {
        _future = ExternalDeliveryRepository().fetchTripDetails(widget.tripName);
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
    final statusNorm = stop.status.trim().toLowerCase();
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
        const Icon(Icons.location_on_outlined, size: 18, color: AppTheme.oceanBlue),
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

  Widget _stopInfoCard(ExternalDeliveryTripStop stop) {
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
        if (stop.address.isNotEmpty) ...[
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TripStopMapScreen(
                  address: stop.address,
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
                  Icon(Icons.navigation_rounded, size: 15, color: AppTheme.oceanBlue),
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
            final options = <String>{
              ..._stopStatusOptions,
              if (stop.status.trim().isNotEmpty) stop.status.trim(),
            }.toList();
            return options
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

