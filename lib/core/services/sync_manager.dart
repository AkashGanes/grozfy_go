import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../features/orders_by_location/repository/external_delivery_repository.dart';
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
  }

  void _onConnectivityRestored() {
    debugPrint('[SyncManager] Connectivity restored, draining queues');
    _syncStatusController.add(SyncStatus.syncing);
    syncAllPendingData();
  }

  Future<void> syncAllPendingData() async {
    if (_isSyncing) return;
    final connectivity = ConnectivityService();
    if (!await connectivity.checkConnectivity()) return;

    _isSyncing = true;
    _syncStatusController.add(SyncStatus.syncing);
    try {
      await _processLocationPingQueue();
      await _processStatusUpdateQueue();
      await _processStopStatusQueue();
      _syncStatusController.add(SyncStatus.idle);
    } catch (e) {
      debugPrint('[SyncManager] Sync error: $e');
      _syncStatusController.add(SyncStatus.error);
    } finally {
      _isSyncing = false;
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
    debugPrint('[SyncManager] Flushing ${pending.length} pings');

    for (final ping in pending) {
      if (ping.retryCount >= _maxRetries) {
        // Drop after maxRetries — don't let stale pings pile up forever.
        await _storage.removeLocationPing(ping.id);
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
    debugPrint('[SyncManager] Flushing ${pending.length} status updates');

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

        await _repository.updateStatus(update.orderName, update.newStatus);
        await _storage.removeStatusUpdate(update.id);
      } catch (e) {
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
    debugPrint(
      '[SyncManager] Conflict on ${update.orderName}: '
      'local=${update.newStatus} server=${serverDoc['status']} '
      'serverWon=${result.serverWon}',
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
    debugPrint('[SyncManager] Flushing ${pending.length} stop updates');

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
        await _repository.setStopStatusRaw(
          stopDocType: update.stopDocType,
          stopName: update.stopName,
          parentTripName: update.parentTripName,
          newStatus: update.newStatus,
        );
        await _storage.removeStopStatusUpdate(update.id);
      } catch (e) {
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
