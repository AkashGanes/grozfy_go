import 'package:hive_flutter/hive_flutter.dart';

class OfflineStorageService {
  static const String _ordersBoxName = 'cached_orders';
  static const String _tripsBoxName = 'cached_trips';
  static const String _statusQueueBoxName = 'status_queue';
  static const String _stopStatusQueueBoxName = 'stop_status_queue';
  static const String _locationPingsBoxName = 'location_pings';
  static const String _metadataBoxName = 'metadata';

  static final OfflineStorageService _instance =
      OfflineStorageService._internal();
  factory OfflineStorageService() => _instance;
  OfflineStorageService._internal();

  bool _initialized = false;
  bool get initialized => _initialized;

  Box<Map>? _ordersBox;
  Box<Map>? _tripsBox;
  Box<Map>? _statusQueueBox;
  Box<Map>? _stopStatusQueueBox;
  Box<Map>? _locationPingsBox;
  Box<dynamic>? _metadataBox;

  Future<void> initialize() async {
    if (_initialized) return;
    await Hive.initFlutter();
    _ordersBox = await Hive.openBox<Map>(_ordersBoxName);
    _tripsBox = await Hive.openBox<Map>(_tripsBoxName);
    _statusQueueBox = await Hive.openBox<Map>(_statusQueueBoxName);
    _stopStatusQueueBox = await Hive.openBox<Map>(_stopStatusQueueBoxName);
    _locationPingsBox = await Hive.openBox<Map>(_locationPingsBoxName);
    _metadataBox = await Hive.openBox(_metadataBoxName);
    _initialized = true;
  }

  // ============ ORDERS ============

  Future<void> cacheOrder(Map<String, dynamic> order) async {
    final box = _ordersBox;
    if (box == null) return;
    final name = order['name']?.toString();
    if (name == null || name.isEmpty) return;
    await box.put(name, order);
  }

  Future<void> cacheOrders(List<Map<String, dynamic>> orders) async {
    final box = _ordersBox;
    if (box == null) return;
    for (final order in orders) {
      final name = order['name']?.toString();
      if (name != null && name.isNotEmpty) {
        await box.put(name, order);
      }
    }
    await _metadataBox?.put(
      'orders_last_sync',
      DateTime.now().toIso8601String(),
    );
  }

  List<Map<String, dynamic>> getCachedOrders() {
    final box = _ordersBox;
    if (box == null) return const [];
    return box.values.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Map<String, dynamic>? getCachedOrder(String name) {
    final box = _ordersBox;
    if (box == null) return null;
    final data = box.get(name);
    return data != null ? Map<String, dynamic>.from(data) : null;
  }

  // ============ TRIPS ============

  Future<void> cacheTrips(List<Map<String, dynamic>> trips) async {
    final box = _tripsBox;
    if (box == null) return;
    for (final trip in trips) {
      final name = trip['name']?.toString();
      if (name != null && name.isNotEmpty) {
        await box.put(name, trip);
      }
    }
    await _metadataBox?.put(
      'trips_last_sync',
      DateTime.now().toIso8601String(),
    );
  }

  Future<void> cacheTripWithDetails(Map<String, dynamic> tripData) async {
    final box = _tripsBox;
    if (box == null) return;
    final name = tripData['name']?.toString();
    if (name != null && name.isNotEmpty) {
      await box.put(name, tripData);
    }
  }

  List<Map<String, dynamic>> getCachedTrips() {
    final box = _tripsBox;
    if (box == null) return const [];
    return box.values.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Map<String, dynamic>? getCachedTrip(String name) {
    final box = _tripsBox;
    if (box == null) return null;
    final data = box.get(name);
    return data != null ? Map<String, dynamic>.from(data) : null;
  }

  // ============ STATUS UPDATE QUEUE ============

  Future<void> addStatusUpdate(PendingStatusUpdate update) async {
    final box = _statusQueueBox;
    if (box == null) return;
    await box.put(update.id, update.toJson());
  }

  Future<void> updateStatusUpdate(PendingStatusUpdate update) async {
    final box = _statusQueueBox;
    if (box == null) return;
    await box.put(update.id, update.toJson());
  }

  List<PendingStatusUpdate> getPendingStatusUpdates() {
    final box = _statusQueueBox;
    if (box == null) return const [];
    return box.values
        .map((e) => PendingStatusUpdate.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> removeStatusUpdate(String id) async {
    final box = _statusQueueBox;
    if (box == null) return;
    await box.delete(id);
  }

  // ============ STOP STATUS QUEUE ============

  Future<void> addStopStatusUpdate(PendingStopStatusUpdate update) async {
    final box = _stopStatusQueueBox;
    if (box == null) return;
    await box.put(update.id, update.toJson());
  }

  Future<void> updateStopStatusUpdate(PendingStopStatusUpdate update) async {
    final box = _stopStatusQueueBox;
    if (box == null) return;
    await box.put(update.id, update.toJson());
  }

  List<PendingStopStatusUpdate> getPendingStopStatusUpdates() {
    final box = _stopStatusQueueBox;
    if (box == null) return const [];
    return box.values
        .map((e) =>
            PendingStopStatusUpdate.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> removeStopStatusUpdate(String id) async {
    final box = _stopStatusQueueBox;
    if (box == null) return;
    await box.delete(id);
  }

  // ============ LOCATION PING QUEUE ============

  Future<void> addLocationPing(LocationPing ping) async {
    final box = _locationPingsBox;
    if (box == null) return;
    await box.put(ping.id, ping.toJson());
  }

  List<LocationPing> getPendingLocationPings() {
    final box = _locationPingsBox;
    if (box == null) return const [];
    return box.values
        .map((e) => LocationPing.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> removeLocationPing(String id) async {
    final box = _locationPingsBox;
    if (box == null) return;
    await box.delete(id);
  }

  Future<void> clearLocationPings() async {
    await _locationPingsBox?.clear();
  }

  // ============ METADATA ============

  DateTime? getLastTripsSync() {
    final v = _metadataBox?.get('trips_last_sync') as String?;
    return v != null ? DateTime.tryParse(v) : null;
  }

  DateTime? getLastOrdersSync() {
    final v = _metadataBox?.get('orders_last_sync') as String?;
    return v != null ? DateTime.tryParse(v) : null;
  }

  bool needsRefresh(DateTime? lastSync, Duration maxAge) {
    if (lastSync == null) return true;
    return DateTime.now().difference(lastSync) > maxAge;
  }

  Future<void> clearAll() async {
    await _ordersBox?.clear();
    await _tripsBox?.clear();
    await _statusQueueBox?.clear();
    await _stopStatusQueueBox?.clear();
    await _locationPingsBox?.clear();
  }
}

enum SyncStatus { pending, syncing, synced, failed, idle, error }

class PendingStatusUpdate {
  final String id;
  final String orderName;
  final String newStatus;
  final DateTime timestamp;
  final int retryCount;
  final String? errorMessage;
  final SyncStatus status;
  // Snapshot of `modified` field at the moment we queued the update — used for
  // conflict detection on flush.
  final String? baseModified;

  PendingStatusUpdate({
    required this.id,
    required this.orderName,
    required this.newStatus,
    required this.timestamp,
    this.retryCount = 0,
    this.errorMessage,
    this.status = SyncStatus.pending,
    this.baseModified,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'orderName': orderName,
        'newStatus': newStatus,
        'timestamp': timestamp.toIso8601String(),
        'retryCount': retryCount,
        'errorMessage': errorMessage,
        'status': status.name,
        'baseModified': baseModified,
      };

  factory PendingStatusUpdate.fromJson(Map<String, dynamic> json) {
    return PendingStatusUpdate(
      id: json['id'] as String,
      orderName: json['orderName'] as String,
      newStatus: json['newStatus'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      retryCount: json['retryCount'] as int? ?? 0,
      errorMessage: json['errorMessage'] as String?,
      status: SyncStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => SyncStatus.pending,
      ),
      baseModified: json['baseModified'] as String?,
    );
  }

  PendingStatusUpdate copyWith({
    int? retryCount,
    String? errorMessage,
    SyncStatus? status,
  }) {
    return PendingStatusUpdate(
      id: id,
      orderName: orderName,
      newStatus: newStatus,
      timestamp: timestamp,
      retryCount: retryCount ?? this.retryCount,
      errorMessage: errorMessage ?? this.errorMessage,
      status: status ?? this.status,
      baseModified: baseModified,
    );
  }
}

/// A queued mutation that sets the `status` field on a trip-stop child row.
/// Stops live under a parent External Delivery Trip, so we need both the
/// stop's own doctype/name and the parent trip name (so we can refresh the
/// trip's cache after the flush).
class PendingStopStatusUpdate {
  final String id;
  final String stopDocType;
  final String stopName;
  final String parentTripName;
  final String orderName;
  final String newStatus;
  final DateTime timestamp;
  final int retryCount;
  final String? errorMessage;
  final SyncStatus status;

  PendingStopStatusUpdate({
    required this.id,
    required this.stopDocType,
    required this.stopName,
    required this.parentTripName,
    required this.orderName,
    required this.newStatus,
    required this.timestamp,
    this.retryCount = 0,
    this.errorMessage,
    this.status = SyncStatus.pending,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'stopDocType': stopDocType,
        'stopName': stopName,
        'parentTripName': parentTripName,
        'orderName': orderName,
        'newStatus': newStatus,
        'timestamp': timestamp.toIso8601String(),
        'retryCount': retryCount,
        'errorMessage': errorMessage,
        'status': status.name,
      };

  factory PendingStopStatusUpdate.fromJson(Map<String, dynamic> json) {
    return PendingStopStatusUpdate(
      id: json['id'] as String,
      stopDocType: json['stopDocType'] as String,
      stopName: json['stopName'] as String,
      parentTripName: json['parentTripName'] as String? ?? '',
      orderName: json['orderName'] as String? ?? '',
      newStatus: json['newStatus'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      retryCount: json['retryCount'] as int? ?? 0,
      errorMessage: json['errorMessage'] as String?,
      status: SyncStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => SyncStatus.pending,
      ),
    );
  }

  PendingStopStatusUpdate copyWith({
    int? retryCount,
    String? errorMessage,
    SyncStatus? status,
  }) {
    return PendingStopStatusUpdate(
      id: id,
      stopDocType: stopDocType,
      stopName: stopName,
      parentTripName: parentTripName,
      orderName: orderName,
      newStatus: newStatus,
      timestamp: timestamp,
      retryCount: retryCount ?? this.retryCount,
      errorMessage: errorMessage ?? this.errorMessage,
      status: status ?? this.status,
    );
  }
}

class LocationPing {
  final String id;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final int retryCount;
  final SyncStatus status;

  LocationPing({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.retryCount = 0,
    this.status = SyncStatus.pending,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp.toIso8601String(),
        'retryCount': retryCount,
        'status': status.name,
      };

  factory LocationPing.fromJson(Map<String, dynamic> json) {
    return LocationPing(
      id: json['id'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      retryCount: json['retryCount'] as int? ?? 0,
      status: SyncStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => SyncStatus.pending,
      ),
    );
  }

  LocationPing copyWith({int? retryCount, SyncStatus? status}) {
    return LocationPing(
      id: id,
      latitude: latitude,
      longitude: longitude,
      timestamp: timestamp,
      retryCount: retryCount ?? this.retryCount,
      status: status ?? this.status,
    );
  }
}
