import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

const int _kFgNotificationId = 88;
const String _kChannelId = 'grozfy_location';

/// Manages the background foreground-service that POSTs driver location pings
/// to the server while a trip is active.
class LocationPingService {
  LocationPingService._();

  static final FlutterBackgroundService _service = FlutterBackgroundService();

  /// Call once at app startup (before [start]).
  static Future<void> initialize() async {
    final FlutterLocalNotificationsPlugin notifications =
        FlutterLocalNotificationsPlugin();
    await notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _kChannelId,
            'Location Tracking',
            description: 'Active while your location is being shared',
            importance: Importance.low,
          ),
        );

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: _kChannelId,
        initialNotificationTitle: 'Grozfy Go',
        initialNotificationContent: 'Sharing your live location…',
        foregroundServiceNotificationId: _kFgNotificationId,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  /// Start the background service and begin sending location pings for [tripId]
  /// / [deliveryId]. [authHeader] must be the full value of the Authorization
  /// header (e.g. `"token key:secret"` or `"Bearer <token>"`).
  static Future<void> start({
    required String tripId,
    required String deliveryId,
    required String authHeader,
    required String baseUrl,
  }) async {
    final bool running = await _service.isRunning();
    if (!running) {
      await _service.startService();
      // Allow the background isolate to boot before sending the first message.
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    _service.invoke('startPing', {
      'trip_id': tripId,
      'delivery_id': deliveryId,
      'auth_header': authHeader,
      'base_url': baseUrl,
    });
  }

  /// Stop location pings and kill the background service.
  static void stop() => _service.invoke('stopPing');

  /// Stream of successful ping acknowledgements from the background isolate.
  /// Each event contains `lat`, `lng`, `ok`, `next_ping_sec`.
  static Stream<Map<String, dynamic>?> get locationUpdates =>
      _service.on('locationUpdate');
}

// ─── Background isolate entry points ─────────────────────────────────────────

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async => true;

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) {
  // Ensure all Flutter platform-channel plugins (Geolocator, http, etc.)
  // are registered in this background isolate.
  DartPluginRegistrant.ensureInitialized();

  // Trip context — populated via 'startPing' message.
  String? tripId;
  String? deliveryId;
  String? authHeader;
  String? baseUrl;

  // GPS state
  Position? latestPos;
  StreamSubscription<Position>? posSub;

  // Ping timing
  Timer? fallbackTimer;
  bool isPinging = false;
  int nextPingSec = 10;
  DateTime? lastPingedAt;

  Future<void> sendPing() async {
    if (tripId == null ||
        deliveryId == null ||
        authHeader == null ||
        baseUrl == null ||
        latestPos == null ||
        isPinging) {
      return;
    }

    final DateTime now = DateTime.now(); // local device time — matches Frappe server timezone
    if (lastPingedAt != null &&
        now.difference(lastPingedAt!).inSeconds < nextPingSec - 1) {
      return;
    }

    isPinging = true;
    lastPingedAt = now;

    // Format: "YYYY-MM-DD HH:MM:SS" — what Frappe datetime fields expect
    final String capturedAt =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';

    final Map<String, dynamic> body = {
      'trip_id': tripId,
      'external_delivery': deliveryId,
      'lat': latestPos!.latitude,
      'lng': latestPos!.longitude,
      'captured_at': capturedAt,
      if (latestPos!.accuracy > 0) 'accuracy_m': latestPos!.accuracy,
      if (latestPos!.speed >= 0) 'speed_mps': latestPos!.speed,
      if (latestPos!.heading >= 0) 'heading_deg': latestPos!.heading,
    };

    try {
      final http.Response resp = await http
          .post(
            Uri.parse(
              '$baseUrl/api/method/grozfy_go.grozfy_go.api.driver_uplink.location_ping',
            ),
            headers: {
              'Authorization': authHeader!,
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final Map<String, dynamic> json =
            jsonDecode(resp.body) as Map<String, dynamic>;
        final dynamic next = json['next_ping_sec'];
        if (next is num && next > 0) nextPingSec = next.toInt();
        service.invoke('locationUpdate', {
          'lat': latestPos!.latitude,
          'lng': latestPos!.longitude,
          'ok': json['ok'] == true,
          'next_ping_sec': nextPingSec,
        });
      }
    } catch (e) {
      debugPrint('[LocationPing] $e');
    } finally {
      isPinging = false;
    }
  }

  void stopAll() {
    posSub?.cancel();
    fallbackTimer?.cancel();
    service.stopSelf();
  }

  void startStreams() {
    posSub?.cancel();
    fallbackTimer?.cancel();

    // Movement-triggered pings (5 m distance filter).
    posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position pos) {
      latestPos = pos;
      sendPing();
    });

    // Fallback: ping every 10 s even when stationary.
    fallbackTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => sendPing(),
    );
  }

  service.on('startPing').listen((Map<String, dynamic>? data) {
    if (data == null) return;
    tripId = data['trip_id'] as String?;
    deliveryId = data['delivery_id'] as String?;
    authHeader = data['auth_header'] as String?;
    baseUrl = data['base_url'] as String?;
    nextPingSec = (data['interval_sec'] as int?) ?? 10;
    lastPingedAt = null;
    isPinging = false;
    startStreams();
  });

  service.on('stopPing').listen((_) => stopAll());
}
