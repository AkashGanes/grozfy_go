import 'dart:async';

import '../../features/orders_by_location/repository/external_delivery_repository.dart';
import '../logging/app_logger.dart';
import 'connectivity_service.dart';
import 'offline_storage_service.dart';

class ConflictResolutionResult {
  final Map<String, dynamic> resolvedData;
  final List<String> conflicts;
  // Did the resolver pick the server-side value as the winner for the
  // mutation field? When true, the client-side intent was overridden.
  final bool serverWon;

  ConflictResolutionResult({
    required this.resolvedData,
    required this.conflicts,
    required this.serverWon,
  });
}

class SyncManager {
  static final SyncManager _instance = SyncManager._internal();
  factory SyncManager() => _instance;
  SyncManager._internal();

  final OfflineStorageService _storage = OfflineStorageService();
  final ExternalDeliveryRepository _repository = ExternalDeliveryRepository();
  StreamSubscription<bool>? _connectivitySubscription;
  Timer? _syncTimer;
  bool _isSyncing = false;

  static const int _maxRetries = 5;
  static const Duration _initialRetryDelay = Duration(seconds: 5);
  static const Duration _syncInterval = Duration(minutes: 5);

  // Terminal status fields where server always wins. Two drivers can't
  // both mark an order delivered; whichever the server already accepted is
  // authoritative.
  static const Set<String> _serverAuthoritativeStatuses = {
    'Delivered',
    'Failed',
    'Returned',
    'Cancelled',
  };

  final _syncStatusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  Future<void> initialize() async {
    await _storage.initialize();
    final connectivity = ConnectivityService();
    _connectivitySubscription = connectivity.connectivityStream.listen((
      isConnected,
    ) {
      if (isConnected) {
        _onConnectivityRestored();
      }
    });
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(_syncInterval, (_) => syncAllPendingData());

    // If we boot up online, the connectivity stream's initial event was
    // already fired before this subscription existed (broadcast streams
    // don't replay), so kick off an immediate drain. Otherwise queued
    // items from a previous session would wait up to one _syncInterval.
    if (await connectivity.checkConnectivity()) {
      unawaited(syncAllPendingData());
    }
  }

  void _onConnectivityRestored() {
    AppLogger.sync.info('Connectivity restored, draining queues');
    _syncStatusController.add(SyncStatus.syncing);
    syncAllPendingData();
  }

  Future<void> syncAllPendingData() async {
    // Claim the lock synchronously, before any await — otherwise two
    // concurrent triggers (e.g. boot-time call + connectivity-stream
    // listener firing at the same moment) both pass the guard, both await
    // checkConnectivity, then both flip the flag and run the whole flush
    // in parallel — pushing each pending update twice.
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final connectivity = ConnectivityService();
      if (!await connectivity.checkConnectivity()) return;

      _syncStatusController.add(SyncStatus.syncing);
      // Recover updates whose previous sync attempt was interrupted (app
      // kill, network drop) — they're stuck in `syncing` and would be
      // skipped forever by the per-queue loops without this reset.
      await _resetStuckSyncingState();
      await _processLocationPingQueue();
      await _processStatusUpdateQueue();
      await _processStopStatusQueue();
      _syncStatusController.add(SyncStatus.idle);
    } catch (e) {
      AppLogger.sync.error('Sync error', error: e);
      _syncStatusController.add(SyncStatus.error);
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _resetStuckSyncingState() async {
    int reset = 0;
    for (final u in _storage.getPendingStatusUpdates()) {
      if (u.status == SyncStatus.syncing) {
        await _storage.updateStatusUpdate(u.copyWith(status: SyncStatus.pending));
        reset++;
      }
    }
    for (final u in _storage.getPendingStopStatusUpdates()) {
      if (u.status == SyncStatus.syncing) {
        await _storage.updateStopStatusUpdate(
          u.copyWith(status: SyncStatus.pending),
        );
        reset++;
      }
    }
    if (reset > 0) {
      AppLogger.sync.warning('Reset $reset stuck syncing updates to pending');
    }
  }

  // ============ LOCATION PING QUEUE ============

  Future<void> queueLocationPing(double lat, double lng) async {
    final ping = LocationPing(
      id: 'ping_${DateTime.now().microsecondsSinceEpoch}',
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
    );
    await _storage.addLocationPing(ping);

    final connectivity = ConnectivityService();
    if (await connectivity.checkConnectivity()) {
      // Best-effort immediate flush; failures stay queued.
      unawaited(_processLocationPingQueue());
    }
  }

  Future<void> _processLocationPingQueue() async {
    final pending = _storage.getPendingLocationPings();
    if (pending.isEmpty) return;
    AppLogger.sync.debug('Flushing ${pending.length} pings');

    for (final ping in pending) {
      if (ping.retryCount >= _maxRetries) {
        // Cap retries but never drop silently — keep the ping in storage
        // marked failed so it stays visible in pendingPingCount instead of
        // vanishing. UI/metrics can surface stuck pings for manual action.
        if (ping.status != SyncStatus.failed) {
          await _storage.addLocationPing(
            ping.copyWith(status: SyncStatus.failed),
          );
        }
        continue;
      }
      try {
        await _repository.sendLocationPing(
          latitude: ping.latitude,
          longitude: ping.longitude,
          recordedAt: ping.timestamp,
        );
        await _storage.removeLocationPing(ping.id);
      } catch (e) {
        await _storage.addLocationPing(
          ping.copyWith(
            retryCount: ping.retryCount + 1,
            status: SyncStatus.failed,
          ),
        );
        // Backoff before next ping in the same flush — keeps a flaky network
        // from burning all retries in a tight loop.
        await Future.delayed(_backoffFor(ping.retryCount));
      }
    }
  }

  // ============ STATUS UPDATE QUEUE ============

  Future<void> queueStatusUpdate({
    required String orderName,
    required String newStatus,
    String? baseModified,
  }) async {
    final update = PendingStatusUpdate(
      id: 'status_${DateTime.now().microsecondsSinceEpoch}',
      orderName: orderName,
      newStatus: newStatus,
      timestamp: DateTime.now(),
      baseModified: baseModified,
    );
    await _storage.addStatusUpdate(update);

    final connectivity = ConnectivityService();
    if (await connectivity.checkConnectivity()) {
      unawaited(_processStatusUpdateQueue());
    }
  }

  Future<void> _processStatusUpdateQueue() async {
    final pending = _storage.getPendingStatusUpdates();
    if (pending.isEmpty) return;
    AppLogger.sync.debug('Flushing ${pending.length} status updates');

    for (final update in pending) {
      if (update.status == SyncStatus.syncing) continue;
      if (update.retryCount >= _maxRetries) {
        await _storage.updateStatusUpdate(
          update.copyWith(status: SyncStatus.failed),
        );
        continue;
      }

      await _storage.updateStatusUpdate(
        update.copyWith(status: SyncStatus.syncing),
      );

      try {
        // Check for conflicts before pushing: if server's `modified` differs
        // from what we saw when queueing, run the resolver.
        final shouldPush = await _checkAndResolveConflict(update);
        if (!shouldPush) {
          // Conflict resolver decided server wins — drop the local intent.
          await _storage.removeStatusUpdate(update.id);
          continue;
        }

        // Use set_value rather than PUT /api/resource: External Delivery is
        // a submittable doctype, and PUT on a submitted (docstatus=1) doc
        // is rejected by Frappe regardless of the field. set_value works
        // for any field marked "Allow on Submit" — and silently no-ops
        // for non-submittable docs too, so it's the safer flush path.
        await _repository.updateStatusViaSetValue(
          update.orderName,
          update.newStatus,
        );
        await _storage.removeStatusUpdate(update.id);
      } catch (e) {
        AppLogger.sync.error(
          'Status update flush failed for ${update.orderName} '
          '(retry ${update.retryCount + 1}/$_maxRetries)',
          error: e,
        );
        await _storage.updateStatusUpdate(
          update.copyWith(
            retryCount: update.retryCount + 1,
            errorMessage: e.toString(),
            status: SyncStatus.failed,
          ),
        );
        await Future.delayed(_backoffFor(update.retryCount));
      }
    }
  }

  /// Returns true if the local update should still be pushed; false if the
  /// resolver decided the server's state wins and the local intent is dropped.
  Future<bool> _checkAndResolveConflict(PendingStatusUpdate update) async {
    if (update.baseModified == null) return true;

    final Map<String, dynamic>? serverDoc =
        await _fetchOrderRaw(update.orderName);
    if (serverDoc == null) return true;

    final serverModified = serverDoc['modified']?.toString();
    if (serverModified == null || serverModified == update.baseModified) {
      return true;
    }

    final result = resolveConflict(
      localStatus: update.newStatus,
      serverData: serverDoc,
    );
    AppLogger.sync.warning(
      'Conflict on ${update.orderName}',
      data: {
        'local': update.newStatus,
        'server': serverDoc['status'],
        'serverWon': result.serverWon,
      },
    );
    // Refresh cached order with the resolved doc so the UI matches what we
    // just decided.
    await _storage.cacheOrder(result.resolvedData);
    return !result.serverWon;
  }

  Future<Map<String, dynamic>?> _fetchOrderRaw(String orderName) async {
    try {
      final detail = await _repository.fetchDetail(orderName);
      return <String, dynamic>{
        'name': detail.name,
        'status': detail.status,
        'modified': detail.modified,
      };
    } catch (_) {
      return null;
    }
  }

  /// Field-scoped resolver. Server wins for terminal statuses (delivered,
  /// failed, returned, cancelled) — those are non-reversible business
  /// outcomes, and a stale offline mutation should never undo them. For
  /// non-terminal status the most recently captured local intent wins.
  ConflictResolutionResult resolveConflict({
    required String localStatus,
    required Map<String, dynamic> serverData,
  }) {
    final serverStatus = serverData['status']?.toString() ?? '';
    final conflicts = <String>[];
    final resolved = Map<String, dynamic>.from(serverData);
    bool serverWon = false;

    if (_serverAuthoritativeStatuses.contains(serverStatus) &&
        serverStatus != localStatus) {
      conflicts.add('status (server=$serverStatus, local=$localStatus)');
      serverWon = true;
    } else if (serverStatus != localStatus) {
      resolved['status'] = localStatus;
      conflicts.add('status (chose local=$localStatus over $serverStatus)');
    }

    return ConflictResolutionResult(
      resolvedData: resolved,
      conflicts: conflicts,
      serverWon: serverWon,
    );
  }

  // ============ STOP STATUS QUEUE ============

  Future<void> queueStopStatusUpdate({
    required String stopDocType,
    required String stopName,
    required String parentTripName,
    required String orderName,
    required String newStatus,
  }) async {
    final update = PendingStopStatusUpdate(
      id: 'stop_${DateTime.now().microsecondsSinceEpoch}',
      stopDocType: stopDocType,
      stopName: stopName,
      parentTripName: parentTripName,
      orderName: orderName,
      newStatus: newStatus,
      timestamp: DateTime.now(),
    );
    await _storage.addStopStatusUpdate(update);

    final connectivity = ConnectivityService();
    if (await connectivity.checkConnectivity()) {
      unawaited(_processStopStatusQueue());
    }
  }

  Future<void> _processStopStatusQueue() async {
    final pending = _storage.getPendingStopStatusUpdates();
    if (pending.isEmpty) return;
    AppLogger.sync.debug('Flushing ${pending.length} stop updates');

    for (final update in pending) {
      if (update.status == SyncStatus.syncing) continue;
      if (update.retryCount >= _maxRetries) {
        await _storage.updateStopStatusUpdate(
          update.copyWith(status: SyncStatus.failed),
        );
        continue;
      }

      await _storage.updateStopStatusUpdate(
        update.copyWith(status: SyncStatus.syncing),
      );

      try {
        // Conflict check: if the server already moved this stop into a
        // terminal state (delivered/failed/etc), drop the local intent
        // instead of overwriting an authoritative business outcome.
        final shouldPush = await _checkAndResolveStopConflict(update);
        if (!shouldPush) {
          await _storage.removeStopStatusUpdate(update.id);
          continue;
        }

        await _repository.setStopStatusRaw(
          stopDocType: update.stopDocType,
          stopName: update.stopName,
          parentTripName: update.parentTripName,
          newStatus: update.newStatus,
        );
        await _storage.removeStopStatusUpdate(update.id);
      } catch (e) {
        AppLogger.sync.error(
          'Stop status flush failed for ${update.stopName} '
          '(retry ${update.retryCount + 1}/$_maxRetries)',
          error: e,
        );
        await _storage.updateStopStatusUpdate(
          update.copyWith(
            retryCount: update.retryCount + 1,
            errorMessage: e.toString(),
            status: SyncStatus.failed,
          ),
        );
        await Future.delayed(_backoffFor(update.retryCount));
      }
    }
  }

  /// Returns true if the queued stop update should still be pushed; false
  /// if the server's stop has already reached a terminal status that
  /// differs from local intent. Mirrors the order-level resolver but
  /// keyed on the stop's current status rather than a `modified` snapshot
  /// (the stop child row's modified isn't reliably exposed).
  Future<bool> _checkAndResolveStopConflict(
    PendingStopStatusUpdate update,
  ) async {
    if (update.parentTripName.isEmpty) return true;

    final trip = await _fetchTripRaw(update.parentTripName);
    if (trip == null) return true;

    final stops = trip['stops'];
    if (stops is! List) return true;

    String? serverStatus;
    for (final s in stops) {
      if (s is Map && s['name']?.toString() == update.stopName) {
        serverStatus = s['status']?.toString();
        break;
      }
    }
    if (serverStatus == null) return true;

    if (_serverAuthoritativeStatuses.contains(serverStatus) &&
        serverStatus != update.newStatus) {
      AppLogger.sync.warning(
        'Stop conflict on ${update.stopName}',
        data: {
          'local': update.newStatus,
          'server': serverStatus,
          'serverWon': true,
        },
      );
      // Refresh cached trip so the UI reflects the resolved server state.
      await _storage.cacheTripWithDetails(trip);
      return false;
    }
    return true;
  }

  Future<Map<String, dynamic>?> _fetchTripRaw(String tripName) async {
    try {
      final trip = await _repository.fetchTripDetails(tripName);
      return <String, dynamic>{
        ...trip.rawFields,
        'name': trip.name,
      };
    } catch (_) {
      return null;
    }
  }

  // ============ HELPERS ============

  // Capped exponential backoff: 5s, 10s, 20s, 40s, 80s, then ceiling.
  Duration _backoffFor(int retryCount) {
    final shift = retryCount.clamp(0, 4);
    return _initialRetryDelay * (1 << shift);
  }

  int get pendingStatusCount => _storage.getPendingStatusUpdates().length;
  int get pendingStopStatusCount =>
      _storage.getPendingStopStatusUpdates().length;
  int get pendingPingCount => _storage.getPendingLocationPings().length;

  List<PendingStatusUpdate> getPendingStatusUpdates() =>
      _storage.getPendingStatusUpdates();
  List<PendingStopStatusUpdate> getPendingStopStatusUpdates() =>
      _storage.getPendingStopStatusUpdates();
  List<LocationPing> getPendingLocationPings() =>
      _storage.getPendingLocationPings();

  void dispose() {
    _connectivitySubscription?.cancel();
    _syncTimer?.cancel();
    _syncStatusController.close();
  }
}
