import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/services/connectivity_service.dart';
import '../../../core/services/offline_trip_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_shell.dart';
import '../model/external_delivery.dart';
import '../repository/external_delivery_repository.dart';
import 'failed_delivery_bottom_sheet.dart';

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

  String _labelFromKey(String key) {
    return key
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  List<MapEntry<String, dynamic>> _orderedTripFields(ExternalDeliveryTrip trip) {
    const priority = <String>[
      'name',
      'driver',
      'status',
      'docstatus',
      'trip_date',
      'total_stops',
      'completes_stops',
      'total_distancekm',
      'started_at',
      'completed_at',
    ];
    final remaining = Map<String, dynamic>.from(trip.rawFields)..remove('stops');
    final fields = <MapEntry<String, dynamic>>[];

    for (final key in priority) {
      if (remaining.containsKey(key)) {
        fields.add(MapEntry(key, remaining.remove(key)));
      }
    }
    fields.addAll(remaining.entries);
    return fields;
  }

  List<MapEntry<String, dynamic>> _orderedStopFields(ExternalDeliveryTripStop stop) {
    const priority = <String>[
      'stop',
      'external_delivery',
      'customer',
      'address',
      'mobile',
      'status',
      'delivered_at',
      'notes',
    ];
    final remaining = Map<String, dynamic>.from(stop.rawFields);
    final fields = <MapEntry<String, dynamic>>[];

    for (final key in priority) {
      if (remaining.containsKey(key)) {
        fields.add(MapEntry(key, remaining.remove(key)));
      }
    }
    fields.addAll(remaining.entries);
    return fields;
  }

  @override
  Widget build(BuildContext context) {
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
                      style: const TextStyle(color: Colors.black54),
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
                const TabBar(
                  indicatorColor: AppTheme.oceanBlue,
                  labelColor: AppTheme.nightBlue,
                  unselectedLabelColor: Colors.black54,
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  tabs: [
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
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: FrostCard(
        child: _fieldList(_orderedTripFields(trip)),
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

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: FrostCard(
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
    );
  }

  Widget _loadingView() {
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
            color: Colors.white.withValues(alpha: 0.72),
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
              style: const TextStyle(
                color: AppTheme.nightBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tripInfoRow(IconData icon, String label, String value) {
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
                  style: const TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppTheme.nightBlue,
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
                const Row(
                  children: [
                    Icon(Icons.undo_rounded, color: AppTheme.mango, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Return Trip',
                      style: TextStyle(
                        color: AppTheme.nightBlue,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Once you arrive at the store, confirm the package has been handed back.',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.store_outlined, color: AppTheme.oceanBlue),
            SizedBox(width: 8),
            Text(
              'Returned to Store?',
              style: TextStyle(
                color: AppTheme.nightBlue,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: const Text(
          'Confirm that you have handed the package back to the store.',
          style: TextStyle(color: Colors.black54),
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
            const FrostCard(
              child: Text(
                'No stops found',
                style: TextStyle(color: Colors.black54),
              ),
            )
                .animate()
                .fadeIn(delay: 100.ms, duration: 240.ms)
                .slideY(begin: 0.05, end: 0)
          else
            ...orderedStops.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FrostCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _stopTitleWithAction(trip, entry.value),
                      
                      const SizedBox(height: 8),
                      _fieldList(_orderedStopFields(entry.value)),
                    ],
                  ),
                ),
              )
                  .animate()
                  .fadeIn(
                    delay: (100 + (entry.key * 70)).ms,
                    duration: 250.ms,
                  )
                  .slideY(begin: 0.06, end: 0)
                  .scale(
                    begin: const Offset(0.985, 0.985),
                    end: const Offset(1, 1),
                    duration: 240.ms,
                    curve: Curves.easeOutCubic,
                  ),
            ),
        ],
      ),
    );
  }

  Widget _stopTitleWithAction(
    ExternalDeliveryTrip trip,
    ExternalDeliveryTripStop stop,
  ) {
    final stopKey = _stopKey(stop);
    final isUpdating = _updatingStops.contains(stopKey);
    final isEditable = _isStopEditable(
      tripStatus: trip.status,
      stopStatus: stop.status,
    );
    return Row(
      children: [
        _stopTitle('Stop ${stop.stop}'),
        const Spacer(),
        if (isUpdating)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.oceanBlue,
            ),
          )
        else if (isEditable)
          PopupMenuButton<String>(
            onSelected: (status) => _updateStopStatus(stop, status),
            itemBuilder: (context) {
              final options = <String>{
                ..._stopStatusOptions,
                if (stop.status.trim().isNotEmpty) stop.status.trim(),
              }.toList();
              return options
                  .map((status) => PopupMenuItem<String>(
                        value: status,
                        child: Text(status),
                      ))
                  .toList();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.oceanBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.oceanBlue.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(
                    Icons.edit_rounded,
                    size: 14,
                    color: AppTheme.oceanBlue,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Update Status',
                    style: TextStyle(
                      color: AppTheme.oceanBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
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

  Future<void> _handleFailedDelivery(ExternalDeliveryTripStop stop) async {
    final result = await showFailedDeliverySheet(context);
    if (result == null || !mounted) return;

    final orderName = stop.externalDelivery.trim();
    final stopKey = _stopKey(stop);
    final fullReason = result.notes.isEmpty
        ? result.reason
        : '${result.reason} — ${result.notes}';

    final createReturn = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.undo_rounded, color: AppTheme.oceanBlue),
            SizedBox(width: 8),
            Text(
              'Return to Store?',
              style: TextStyle(
                color: AppTheme.nightBlue,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Text(
          'Create a return trip to bring "$orderName" back to the store?',
          style: const TextStyle(color: Colors.black54),
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

  Widget _fieldList(List<MapEntry<String, dynamic>> entries) {
    return Column(
      children: entries
          .asMap()
          .entries
          .map(
            (entry) => _kv(
              _labelFromKey(entry.value.key),
              _displayValue(entry.value.value),
            )
                .animate()
                .fadeIn(
                  delay: (30 + (entry.key * 24)).ms,
                  duration: 180.ms,
                )
                .slideX(begin: 0.02, end: 0),
          )
          .toList(),
    );
  }

  Widget _kv(String key, String value) {
    const icon = Icon(
      Icons.label_outline_rounded,
      size: 14,
      color: Colors.black45,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: icon,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    key,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(color: AppTheme.nightBlue, height: 1.25),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stopTitle(String stopText) {
    return Row(
      children: [
        const Icon(
          Icons.location_on_outlined,
          size: 18,
          color: AppTheme.oceanBlue,
        ),
        const SizedBox(width: 6),
        Text(
          stopText,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppTheme.nightBlue,
          ),
        ),
      ],
    );
  }
}
