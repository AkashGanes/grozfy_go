import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

const int _kFgNotificationId = 88;
const String _kChannelId = 'grozfy_location';

// Limits that mirror the backend contract
const int _kAccuracyLimitM = 80; // server rejects pings with accuracy > 80 m
const int _kStaleLimitSec = 88;  // server limit is 90 s; use 88 for safety
const int _kMaxRetries = 3;      // retry a failed ping up to this many times
const int _kDefaultPingSec = 10; // initial send interval

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

  /// Start the background service for [tripId] / [deliveryId].
  /// [authHeader] is the full Authorization value
  /// (e.g. `"token key:secret"` or `"Bearer <token>"`).
  static Future<void> start({
    required String tripId,
    required String deliveryId,
    required String authHeader,
    required String baseUrl,
  }) async {
    final bool running = await _service.isRunning();
    if (!running) {
      await _service.startService();
      // Give the background isolate time to boot before the first message.
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

  /// Stream of ping events from the background isolate.
  /// Each event contains: `lat`, `lng`, `ok`, `message` (if error),
  /// `next_ping_sec`.
  static Stream<Map<String, dynamic>?> get locationUpdates =>
      _service.on('locationUpdate');
}

// ─── Background isolate entry points ─────────────────────────────────────────

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async => true;

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) {
  // Register all Flutter platform-channel plugins in this background isolate.
  DartPluginRegistrant.ensureInitialized();

  // ── Trip context (populated via 'startPing') ────────────────────────────
  String? tripId;
  String? deliveryId;
  String? authHeader;
  String? baseUrl;

  // ── GPS state ───────────────────────────────────────────────────────────
  Position? latestPos;
  StreamSubscription<Position>? posSub;

  // ── Ping timing ─────────────────────────────────────────────────────────
  Timer? fallbackTimer;
  bool isPinging = false;
  int nextPingSec = _kDefaultPingSec;
  DateTime? lastPingedAt;

  // ── Retry / offline cache ───────────────────────────────────────────────
  Map<String, dynamic>? retryBody;      // payload queued for retry
  DateTime? retryBodyCapturedAt;        // when the cached payload was built
  int failureCount = 0;

  // ── Indirect reference to sendPing (breaks the restartTimer ↔ sendPing
  //    forward-reference cycle; set after sendPing is declared below). ─────
  Future<void> Function() doSendPing = () async {};

  // ── Helper: restart the fallback timer at a new interval ────────────────
  void restartTimer(int newSec) {
    if (newSec == nextPingSec) return;
    nextPingSec = newSec;
    fallbackTimer?.cancel();
    fallbackTimer = Timer.periodic(
      Duration(seconds: nextPingSec),
      (_) => doSendPing(),
    );
  }

  // ── Helper: handle HTTP / network failure with retry + exponential backoff
  void onNetworkFailure(Map<String, dynamic> payload) {
    failureCount++;
    final bool exceeded = failureCount > _kMaxRetries;
    if (!exceeded) {
      retryBody = payload; // keep payload; retry on next tick
    } else {
      retryBody = null;
      retryBodyCapturedAt = null;
      failureCount = 0;
    }
    // Exponential backoff: interval × failures, capped at 60 s.
    final int backoff = exceeded
        ? nextPingSec
        : (nextPingSec * failureCount).clamp(nextPingSec, 60);
    restartTimer(backoff);
    debugPrint('[LocationPing] failure #$failureCount — retry in ${backoff}s');
  }

  // ── Helper: build a fresh payload or reuse the retry cache ──────────────
  //
  // Returns null when the ping cycle must be skipped:
  //   • No GPS fix available yet
  //   • Accuracy worse than 80 m (server will reject it)
  //   • GPS fix older than 88 s (server limit is 90 s)
  //   • Retry cache has itself expired
  Map<String, dynamic>? resolveBody(DateTime now) {
    // Prefer a cached payload from a previous failed attempt.
    if (retryBody != null) {
      final int cacheAge = now.difference(retryBodyCapturedAt!).inSeconds;
      if (cacheAge <= _kStaleLimitSec) {
        return retryBody!;
      }
      // Cache has expired — discard and fall through to build fresh.
      retryBody = null;
      retryBodyCapturedAt = null;
      failureCount = 0;
    }

    if (latestPos == null) {
      return null;
    }
    // Pre-flight accuracy guard — mirrors the server's 80 m rejection rule.
    if (latestPos!.accuracy > _kAccuracyLimitM) {
      return null;
    }
    // Pre-flight freshness guard — reject fixes the server would mark stale.
    final int fixAge = now.difference(latestPos!.timestamp.toUtc()).inSeconds;
    if (fixAge > _kStaleLimitSec) {
      return null;
    }

    retryBodyCapturedAt = now;
    return {
      'trip_id': tripId!,
      'external_delivery': deliveryId!,
      'lat': latestPos!.latitude,
      'lng': latestPos!.longitude,
      'captured_at': _frappeUtc(now),
      if (latestPos!.accuracy > 0) 'accuracy_m': latestPos!.accuracy,
      if (latestPos!.speed >= 0) 'speed_mps': latestPos!.speed,
      if (latestPos!.heading >= 0) 'heading_deg': latestPos!.heading,
    };
  }

  // ── Core ping ────────────────────────────────────────────────────────────

  Future<void> sendPing() async {
    if (tripId == null ||
        deliveryId == null ||
        authHeader == null ||
        baseUrl == null ||
        isPinging) {
      return;
    }

    final DateTime now = DateTime.now().toUtc();

    // Throttle: never ping faster than nextPingSec.
    if (lastPingedAt != null &&
        now.difference(lastPingedAt!).inSeconds < nextPingSec - 1) {
      return;
    }

    final Map<String, dynamic>? body = resolveBody(now);
    if (body == null) return; // pre-flight check failed; skip this cycle

    isPinging = true;
    lastPingedAt = now;

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

        // Any 200 response clears the retry cache.
        retryBody = null;
        retryBodyCapturedAt = null;
        failureCount = 0;

        final dynamic nextRaw = json['next_ping_sec'];
        final int suggested =
            (nextRaw is num && nextRaw > 0) ? nextRaw.toInt() : nextPingSec;

        // Snapshot position before potential mutation below.
        final Position? pos = latestPos;

        if (json['ok'] == true) {
          // ── Happy path: update interval, notify UI ───────────────────────
          restartTimer(suggested);
          service.invoke('locationUpdate', {
            'lat': pos?.latitude,
            'lng': pos?.longitude,
            'ok': true,
            'next_ping_sec': nextPingSec,
          });
        } else {
          // ── Error responses — handle per backend contract ────────────────
          final String msg = (json['message'] as String?) ?? '';
          switch (msg) {
            case 'low_gps_accuracy':
              // Server confirmed accuracy is too poor; respect its delay.
              restartTimer(suggested);
            case 'impossible_speed':
              // GPS glitch / teleport — discard fix, wait for next stream event.
              latestPos = null;
            case 'stale location update':
              // Fix was too old when it arrived — discard and wait for fresh one.
              latestPos = null;
          }
          service.invoke('locationUpdate', {
            'lat': pos?.latitude,
            'lng': pos?.longitude,
            'ok': false,
            'message': msg,
            'next_ping_sec': suggested,
          });
        }
      } else {
        // Non-200 HTTP — treat as transient and schedule a retry.
        onNetworkFailure(body);
      }
    } catch (_) {
      // Timeout, no network, DNS failure, etc. — cache payload and retry.
      onNetworkFailure(body);
    } finally {
      isPinging = false;
    }
  }

  // Wire the indirect reference now that sendPing is declared.
  doSendPing = sendPing;

  // ── GPS stream setup ─────────────────────────────────────────────────────

  void stopAll() {
    posSub?.cancel();
    fallbackTimer?.cancel();
    service.stopSelf();
  }

  void startStreams() {
    posSub?.cancel();
    fallbackTimer?.cancel();

    // Single shared stream — store latest fix in memory; never call GPS again
    // inside sendPing().  distanceFilter = 10 m is the device-side gate.
    posSub = Geolocator.getPositionStream(
      locationSettings: Platform.isAndroid
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
              intervalDuration: const Duration(seconds: 4),
            )
          : AppleSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
              activityType: ActivityType.automotiveNavigation,
              pauseLocationUpdatesAutomatically: false,
            ),
    ).listen((Position pos) {
      latestPos = pos;
      sendPing();
    });

    // Fallback: keep pinging at the current interval even when stationary.
    fallbackTimer = Timer.periodic(
      Duration(seconds: nextPingSec),
      (_) => sendPing(),
    );
  }

  // ── Service message handlers ─────────────────────────────────────────────

  service.on('startPing').listen((Map<String, dynamic>? data) {
    if (data == null) return;
    tripId = data['trip_id'] as String?;
    deliveryId = data['delivery_id'] as String?;
    authHeader = data['auth_header'] as String?;
    baseUrl = data['base_url'] as String?;
    nextPingSec = (data['interval_sec'] as int?) ?? _kDefaultPingSec;
    lastPingedAt = null;
    isPinging = false;
    retryBody = null;
    retryBodyCapturedAt = null;
    failureCount = 0;
    startStreams();
  });

  service.on('stopPing').listen((_) => stopAll());
}

// ─── Pure helpers ─────────────────────────────────────────────────────────────

/// Formats [utcNow] as `"YYYY-MM-DD HH:MM:SS"` — the Frappe datetime format.
String _frappeUtc(DateTime utcNow) =>
    '${utcNow.year.toString().padLeft(4, '0')}-'
    '${utcNow.month.toString().padLeft(2, '0')}-'
    '${utcNow.day.toString().padLeft(2, '0')} '
    '${utcNow.hour.toString().padLeft(2, '0')}:'
    '${utcNow.minute.toString().padLeft(2, '0')}:'
    '${utcNow.second.toString().padLeft(2, '0')}';
