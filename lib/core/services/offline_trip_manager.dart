import 'package:flutter/foundation.dart';

import '../../features/orders_by_location/model/external_delivery.dart';
import '../../features/orders_by_location/model/external_delivery_detail.dart';
import '../../features/orders_by_location/repository/external_delivery_repository.dart';
import 'connectivity_service.dart';
import 'offline_storage_service.dart';
import 'sync_manager.dart';

/// Coordinates the "download all trip data at trip start" flow and serves
/// reads from the Hive cache when offline.
class OfflineTripManager {
  static final OfflineTripManager _instance = OfflineTripManager._internal();
  factory OfflineTripManager() => _instance;
  OfflineTripManager._internal();

  final OfflineStorageService _storage = OfflineStorageService();
  final ExternalDeliveryRepository _repository = ExternalDeliveryRepository();
  final SyncManager _syncManager = SyncManager();

  bool _initialized = false;

  // Default retention before we re-prefetch on next online session.
  static const Duration _cacheMaxAge = Duration(hours: 24);

  Future<void> initialize() async {
    if (_initialized) return;
    await _storage.initialize();
    _initialized = true;
  }

  /// Walks every trip the driver owns, then every stop's order, caching
  /// each. Called at the moment the driver starts their trip so the rest
  /// of the day can run fully offline.
  Future<int> downloadAllTripsAtTripStart() async {
    final connectivity = ConnectivityService();
    if (!await connectivity.checkConnectivity()) {
      debugPrint('[OfflineTripManager] No connectivity, skipping prefetch');
      return 0;
    }

    // Cap at 50 trips to prevent unbounded fetching for drivers with large history.
    const int maxTripsToPrefetch = 50;

    int tripsCached = 0;
    try {
      // Phase 1 — trip summary pages (1–2 list calls).
      final summaries = <ExternalDeliveryTripSummary>[];
      var page = await _repository.fetchTripPage(limitStart: 0);
      summaries.addAll(page);
      while (page.length >= ExternalDeliveryRepository.pageSize &&
          summaries.length < maxTripsToPrefetch) {
        page = await _repository.fetchTripPage(limitStart: summaries.length);
        if (page.isEmpty) break;
        summaries.addAll(page);
      }
      final cappedSummaries = summaries.take(maxTripsToPrefetch).toList();
      await _storage.cacheTrips(cappedSummaries.map(_summaryToJson).toList());

      // Phase 2 — trip detail fetches in batches of 3 (needed for the stops
      // child table, which the list API does not return).
      const batchSize = 3;
      final fetchedTrips = <ExternalDeliveryTrip>[];
      for (int i = 0; i < cappedSummaries.length; i += batchSize) {
        final end = (i + batchSize).clamp(0, cappedSummaries.length);
        final batch = cappedSummaries.sublist(i, end);
        final results = await Future.wait(
          batch.map((s) async {
            try {
              final trip = await _repository.fetchTripDetails(s.name);
              await _storage.cacheTripWithDetails(_tripToJson(trip));
              tripsCached++;
              return trip;
            } catch (e) {
              debugPrint(
                '[OfflineTripManager] Failed to cache trip ${s.name}: $e',
              );
              return null;
            }
          }),
        );
        fetchedTrips.addAll(results.whereType<ExternalDeliveryTrip>());
      }

      // Phase 3 — collect every order name from every trip stop, then fetch
      // ALL orders in a single Frappe list call (filters=[["name","in",[...]]]).
      // This replaces the previous pattern of one HTTP call per stop order.
      final allOrderNames = fetchedTrips
          .expand((t) => t.stops.map((s) => s.externalDelivery.trim()))
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList();

      if (allOrderNames.isNotEmpty) {
        try {
          final orders = await _repository.fetchOrdersBatch(allOrderNames);
          for (final order in orders) {
            await _storage.cacheOrder(_detailToJson(order));
          }
          debugPrint(
            '[OfflineTripManager] Batch-cached ${orders.length} orders '
            '(${allOrderNames.length} requested)',
          );
        } catch (e) {
          debugPrint('[OfflineTripManager] Order batch fetch failed: $e');
        }
      }

      debugPrint('[OfflineTripManager] Cached $tripsCached trips');
    } catch (e) {
      debugPrint('[OfflineTripManager] Prefetch error: $e');
    }
    return tripsCached;
  }

  /// Refreshes the cache only when older than [_cacheMaxAge] — used on
  /// app resume to avoid re-pulling everything on every foreground.
  Future<void> refreshIfStale() async {
    final last = _storage.getLastTripsSync();
    if (_storage.needsRefresh(last, _cacheMaxAge)) {
      await downloadAllTripsAtTripStart();
    }
  }

  // ============ READS — online with cache fallback ============

  /// Fetches trip summaries, falling back to cached data when offline or
  /// when the network request fails. The cache is also refreshed on
  /// successful fetches so subsequent offline reads get the latest state.
  Future<List<ExternalDeliveryTripSummary>> fetchTripSummaries() async {
    final connectivity = ConnectivityService();
    if (await connectivity.checkConnectivity()) {
      try {
        final summaries = <ExternalDeliveryTripSummary>[];
        var page = await _repository.fetchTripPage(limitStart: 0);
        summaries.addAll(page);
        while (page.length >= ExternalDeliveryRepository.pageSize) {
          page =
              await _repository.fetchTripPage(limitStart: summaries.length);
          if (page.isEmpty) break;
          summaries.addAll(page);
        }
        await _storage.cacheTrips(summaries.map(_summaryToJson).toList());
        return summaries;
      } catch (e) {
        debugPrint(
          '[OfflineTripManager] fetchTripSummaries network failed, '
          'falling back to cache: $e',
        );
      }
    }
    return getCachedTripSummaries();
  }

  Future<ExternalDeliveryTrip?> fetchTrip(String tripName) async {
    final connectivity = ConnectivityService();
    if (await connectivity.checkConnectivity()) {
      try {
        final trip = await _repository.fetchTripDetails(tripName);
        await _storage.cacheTripWithDetails(_tripToJson(trip));
        return trip;
      } catch (e) {
        debugPrint(
          '[OfflineTripManager] fetchTrip network failed for $tripName: $e',
        );
      }
    }
    return getCachedTrip(tripName);
  }

  Future<ExternalDeliveryDetail?> fetchOrder(String orderName) async {
    final connectivity = ConnectivityService();
    if (await connectivity.checkConnectivity()) {
      try {
        final detail = await _repository.fetchDetail(orderName);
        await _storage.cacheOrder(_detailToJson(detail));
        return detail;
      } catch (e) {
        debugPrint(
          '[OfflineTripManager] fetchOrder network failed for $orderName: $e',
        );
      }
    }
    return getCachedOrder(orderName);
  }

  // ============ WRITES — used by paginated screens ============

  /// Caches a freshly-fetched trip's full detail so subsequent offline
  /// opens succeed. Used by screens that already hold the trip in memory.
  Future<void> cacheTrip(ExternalDeliveryTrip trip) async {
    await _storage.cacheTripWithDetails(_tripToJson(trip));
  }

  /// Caches a freshly-fetched order detail. Used by screens that already
  /// hold the detail in memory and want to make it available offline.
  Future<void> cacheOrderDetail(ExternalDeliveryDetail detail) async {
    await _storage.cacheOrder(_detailToJson(detail));
  }

  /// Caches order list-summary rows alongside any existing full-detail
  /// cache. Like cacheTripSummariesPage, this merges to avoid wiping
  /// rich fields that were cached by the order detail screen.
  Future<void> cacheOrderSummaries(
    List<Map<String, dynamic>> summaries,
  ) async {
    if (summaries.isEmpty) return;
    final merged = <Map<String, dynamic>>[];
    for (final s in summaries) {
      final name = s['name']?.toString();
      if (name == null || name.isEmpty) continue;
      final existing = _storage.getCachedOrder(name) ?? <String, dynamic>{};
      merged.add(<String, dynamic>{
        ...existing,
        // Summary fields — these are authoritative when freshly fetched.
        'name': name,
        if (s['store_url'] != null) 'store_url': s['store_url'],
        if (s['store_name'] != null) 'store_name': s['store_name'],
        if (s['customer_name'] != null) 'customer_name': s['customer_name'],
        if (s['status'] != null) 'status': s['status'],
        if (s['creation'] != null) 'creation': s['creation'],
        if (s['modified'] != null) 'modified': s['modified'],
        // Delivery coordinates power the offline delivery-radius filter.
        if (s['latitude'] != null) 'latitude': s['latitude'],
        if (s['longitude'] != null) 'longitude': s['longitude'],
      });
    }
    // Single batched disk flush instead of one awaited write per row.
    await _storage.cacheOrdersBatch(merged);
  }

  /// Returns all cached orders as ExternalDelivery summaries. Suitable
  /// for list screens that don't need full ExternalDeliveryDetail.
  List<ExternalDelivery> getCachedOrderSummaries() {
    return _storage
        .getCachedOrders()
        .map((m) => ExternalDelivery.fromJson(m))
        .toList();
  }

  /// Adds these summaries to the cache without clobbering full trip details
  /// (stops, raw fields) that may have been cached earlier. Summary-only
  /// fields are merged on top of any existing entry — so a list refresh
  /// can't wipe stops cached by the details screen.
  Future<void> cacheTripSummariesPage(
    List<ExternalDeliveryTripSummary> summaries,
  ) async {
    if (summaries.isEmpty) return;
    for (final s in summaries) {
      final existing = _storage.getCachedTrip(s.name);
      final merged = <String, dynamic>{
        ...?existing,
        // Summary fields — overwrite with the fresh values from the list.
        'name': s.name,
        'driver': s.driver,
        'status': s.status,
        'docstatus': s.docstatus,
        'trip_date': s.tripDate,
        'total_stops': s.totalStops,
        'completes_stops': s.completedStops,
        'modified': s.modified,
      };
      await _storage.cacheTripWithDetails(merged);
    }
  }

  // ============ READS — cache only ============

  List<ExternalDeliveryTripSummary> getCachedTripSummaries() {
    return _storage
        .getCachedTrips()
        .map((m) => ExternalDeliveryTripSummary.fromJson(m))
        .toList();
  }

  ExternalDeliveryTrip? getCachedTrip(String tripName) {
    final cached = _storage.getCachedTrip(tripName);
    return cached != null ? ExternalDeliveryTrip.fromJson(cached) : null;
  }

  ExternalDeliveryDetail? getCachedOrder(String orderName) {
    final cached = _storage.getCachedOrder(orderName);
    return cached != null ? ExternalDeliveryDetail.fromJson(cached) : null;
  }

  // ============ OFFLINE STATUS UPDATE ============

  Future<void> updateOrderStatusOffline({
    required String orderName,
    required String newStatus,
  }) async {
    // Capture the server-state we last saw so the resolver can detect
    // conflicts when this update finally flushes.
    final cached = _storage.getCachedOrder(orderName);
    final baseModified = cached?['modified']?.toString();

    await _syncManager.queueStatusUpdate(
      orderName: orderName,
      newStatus: newStatus,
      baseModified: baseModified,
    );

    // Optimistic local update — UI reflects the new status immediately.
    if (cached != null) {
      cached['status'] = newStatus;
      cached['modified'] = DateTime.now().toIso8601String();
      await _storage.cacheOrder(Map<String, dynamic>.from(cached));
    }
  }

  /// Marks a trip stop's status (Delivered / Failed / etc.) — works
  /// online or offline. Online: queues + immediately drains. Offline:
  /// queues + optimistically updates the cached trip so the UI reflects
  /// the new status until the next online sync.
  Future<void> updateStopStatusOffline({
    required String stopDocType,
    required String stopName,
    required String parentTripName,
    required String orderName,
    required String newStatus,
  }) async {
    await _syncManager.queueStopStatusUpdate(
      stopDocType: stopDocType,
      stopName: stopName,
      parentTripName: parentTripName,
      orderName: orderName,
      newStatus: newStatus,
    );

    // Patch the cached trip so the user sees the change immediately. We
    // do a shallow rewrite of the matching stop's status in the raw
    // fields list — the trip cache uses the original API shape.
    if (parentTripName.isEmpty) return;
    final cachedTrip = _storage.getCachedTrip(parentTripName);
    if (cachedTrip == null) return;
    final stops = cachedTrip['stops'];
    if (stops is! List) return;
    bool changed = false;
    for (final s in stops) {
      if (s is Map) {
        final n = s['name']?.toString();
        if (n == stopName) {
          s['status'] = newStatus;
          changed = true;
          break;
        }
      }
    }
    if (changed) {
      await _storage.cacheTripWithDetails(
        Map<String, dynamic>.from(cachedTrip),
      );
    }
  }

  // ============ EXPOSED COUNTS ============

  int get pendingStatusUpdates =>
      _syncManager.pendingStatusCount + _syncManager.pendingStopStatusCount;
  int get pendingLocationPings => _syncManager.pendingPingCount;

  // ============ SERIALIZERS ============

  Map<String, dynamic> _summaryToJson(ExternalDeliveryTripSummary s) => {
        'name': s.name,
        'driver': s.driver,
        'status': s.status,
        'docstatus': s.docstatus,
        'trip_date': s.tripDate,
        'total_stops': s.totalStops,
        'completes_stops': s.completedStops,
        'modified': s.modified,
        // Optional enrichment fields — cached too, so an offline list renders
        // the same card as the online one.
        'customer_name': s.customerName,
        'delivery_location': s.location,
        'total_orders': s.orderCount,
        'driver_earnings': s.earnings,
      };

  Map<String, dynamic> _tripToJson(ExternalDeliveryTrip t) => {
        ...t.rawFields,
        'name': t.name,
      };

  Map<String, dynamic> _detailToJson(ExternalDeliveryDetail d) => {
        'name': d.name,
        'store_name': d.storeName,
        'store_url': d.storeUrl,
        'customer_name': d.customerName,
        'status': d.status,
        'contact_mobile': d.contactMobile,
        'delivery_address': d.deliveryAddress,
        'pickup_address': d.pickupAddress,
        'latitude': d.latitude,
        'longitude': d.longitude,
        'payment_mode': d.paymentMode,
        'grand_total': d.grandTotal,
        'creation': d.creation,
        'modified': d.modified,
      };
}
