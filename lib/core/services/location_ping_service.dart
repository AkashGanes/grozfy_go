import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../logging/app_logger.dart';

// Limits that mirror the backend contract
const int _kAccuracyLimitM = 80; // server rejects pings with accuracy > 80 m
const int _kStaleLimitSec = 88;  // server limit is 90 s; use 88 for safety
const int _kMaxRetries = 3;      // retry a failed ping up to this many times
const int _kDefaultPingSec = 10; // initial send interval

/// POSTs driver location pings to the server while a trip is active.
///
/// Runs on the **main isolate** via a Timer + a Geolocator stream. This
/// previously used `flutter_background_service` to host the loop in a second
/// Flutter engine, but on Vivo (and other compositor-strict OEMs) running
/// two Flutter engines in the same process exhausts BLAST surface buffers
/// and the OS recycles the foreground service / kills the app.
///
/// The trade-off: pings stop when the OS suspends the main isolate
/// (screen-off, app fully backgrounded for long periods). On Vivo with
/// aggressive battery management the foreground-service approach was
/// already unreliable, so this is acceptable.
class LocationPingService {
  LocationPingService._();

  // ── Trip context (populated by [start]) ───────────────────────────────────
  static String? _tripId;
  static String? _deliveryId;
  static String? _authHeader;
  static String? _baseUrl;

  // ── GPS state ─────────────────────────────────────────────────────────────
  static Position? _latestPos;
  static StreamSubscription<Position>? _posSub;
  static StreamSubscription<ServiceStatus>? _svcStatusSub;
  static bool _gpsDisabled = false;

  // ── Ping timing ───────────────────────────────────────────────────────────
  static Timer? _fallbackTimer;
  static bool _isPinging = false;
  static bool _isRefreshingFix = false;
  static int _nextPingSec = _kDefaultPingSec;
  static DateTime? _lastPingedAt;

  // ── Retry / offline cache ─────────────────────────────────────────────────
  static Map<String, dynamic>? _retryBody;
  static DateTime? _retryBodyCapturedAt;
  static int _failureCount = 0;

  // ── External event stream ─────────────────────────────────────────────────
  static final StreamController<Map<String, dynamic>?> _eventsController =
      StreamController<Map<String, dynamic>?>.broadcast();

  static void _log(String message) {
    AppLogger.location.debug(message);
  }

  /// Kept for API compatibility with callers; nothing to set up upfront now
  /// that we run on the main isolate.
  static Future<void> initialize() async {}

  /// Start sending pings for [tripId] / [deliveryId].
  /// [authHeader] is the full Authorization value
  /// (e.g. `"token key:secret"` or `"Bearer <token>"`).
  static Future<void> start({
    required String tripId,
    required String deliveryId,
    required String authHeader,
    required String baseUrl,
  }) async {
    _tripId = tripId;
    _deliveryId = deliveryId;
    _authHeader = authHeader;
    _baseUrl = baseUrl;
    _nextPingSec = _kDefaultPingSec;
    _lastPingedAt = null;
    _isPinging = false;
    _isRefreshingFix = false;
    _retryBody = null;
    _retryBodyCapturedAt = null;
    _failureCount = 0;
    _log('start trip_id=$tripId external_delivery=$deliveryId interval=${_nextPingSec}s');
    await _startStreams();
  }

  /// Stop pings and tear down all listeners/timers.
  static void stop() {
    _log('stop');
    _stopAll();
  }

  /// Stream of ping events. Each event contains `lat`, `lng`, `ok`,
  /// `message` (if error), `next_ping_sec`.
  static Stream<Map<String, dynamic>?> get locationUpdates =>
      _eventsController.stream;

  // ── Internal: stream + timer lifecycle ────────────────────────────────────

  static void _stopAll() {
    _posSub?.cancel();
    _posSub = null;
    _svcStatusSub?.cancel();
    _svcStatusSub = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    _gpsDisabled = false;
    _latestPos = null;
    _retryBody = null;
    _retryBodyCapturedAt = null;
  }

  static void _armFallbackTimer() {
    _fallbackTimer?.cancel();
    if (_gpsDisabled) return;
    _fallbackTimer = Timer.periodic(
      Duration(seconds: _nextPingSec),
      (_) => _sendPing(),
    );
  }

  static void _restartTimer(int newSec) {
    if (newSec == _nextPingSec) return;
    _nextPingSec = newSec;
    _armFallbackTimer();
  }

  static void _startPositionStream() {
    if (_posSub != null) return;
    _posSub = Geolocator.getPositionStream(
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
      _latestPos = pos;
      _log(
        'gps lat=${pos.latitude}, lng=${pos.longitude}, '
        'accuracy=${pos.accuracy}, speed=${pos.speed}, heading=${pos.heading}, '
        'captured_at=${_frappeDateTime(pos.timestamp.toLocal())}',
      );
      _sendPing();
    });
  }

  static void _stopPositionStream() {
    _posSub?.cancel();
    _posSub = null;
  }

  static void _onGpsEnabled() {
    if (!_gpsDisabled) return;
    _gpsDisabled = false;
    _log('GPS service enabled — resuming pings');
    _startPositionStream();
    _armFallbackTimer();
  }

  static void _onGpsDisabled() {
    if (_gpsDisabled) return;
    _gpsDisabled = true;
    _log('GPS service disabled — pausing pings until re-enabled');
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    _stopPositionStream();
    _latestPos = null;
  }

  static Future<void> _startStreams() async {
    _stopPositionStream();
    _svcStatusSub?.cancel();
    _fallbackTimer?.cancel();

    bool enabled = false;
    try {
      enabled = await Geolocator.isLocationServiceEnabled();
    } catch (e) {
      _log('initial isLocationServiceEnabled check failed: $e');
    }
    if (!enabled) _onGpsDisabled();

    _svcStatusSub = Geolocator.getServiceStatusStream().listen((status) {
      if (status == ServiceStatus.enabled) {
        _onGpsEnabled();
      } else {
        _onGpsDisabled();
      }
    });

    if (!_gpsDisabled) {
      _startPositionStream();
      _armFallbackTimer();
    }
  }

  // ── Internal: ping logic ──────────────────────────────────────────────────

  static Future<void> _refreshLatestPosition(String reason) async {
    if (_isRefreshingFix) {
      _log('skip: GPS refresh already in flight');
      return;
    }
    _isRefreshingFix = true;
    try {
      _log('refreshing GPS fix: $reason');
      final Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      _latestPos = pos;
      _log(
        'refreshed gps lat=${pos.latitude}, lng=${pos.longitude}, '
        'accuracy=${pos.accuracy}, speed=${pos.speed}, heading=${pos.heading}, '
        'captured_at=${_frappeDateTime(pos.timestamp.toLocal())}',
      );
    } catch (e) {
      _log('refresh GPS failed: $e');
    } finally {
      _isRefreshingFix = false;
    }
  }

  static Map<String, dynamic>? _resolveBody(DateTime now) {
    if (_retryBody != null && _retryBodyCapturedAt != null) {
      final int cacheAge = now.difference(_retryBodyCapturedAt!).inSeconds;
      if (cacheAge <= _kStaleLimitSec) {
        _log('retrying cached payload age=${cacheAge}s');
        return _retryBody!;
      }
      _retryBody = null;
      _retryBodyCapturedAt = null;
      _failureCount = 0;
    } else if (_retryBody != null) {
      _log('retry cache had no timestamp — dropping');
      _retryBody = null;
      _failureCount = 0;
    }

    if (_latestPos == null) {
      _log('skip: no GPS fix yet');
      return null;
    }
    if (_latestPos!.accuracy > _kAccuracyLimitM) {
      _log('skip: accuracy too low (${_latestPos!.accuracy}m)');
      return null;
    }
    final int fixAge = now.difference(_latestPos!.timestamp.toUtc()).inSeconds;
    if (fixAge > _kStaleLimitSec) {
      _log('skip: stale GPS fix age=${fixAge}s');
      return null;
    }

    final DateTime capturedAtLocal = _latestPos!.timestamp.toLocal();
    _retryBodyCapturedAt = _latestPos!.timestamp.toUtc();
    return {
      'trip_id': _tripId!,
      'external_delivery': _deliveryId!,
      'lat': _latestPos!.latitude,
      'lng': _latestPos!.longitude,
      'captured_at': _frappeDateTime(capturedAtLocal),
      if (_latestPos!.accuracy > 0) 'accuracy_m': _latestPos!.accuracy,
      if (_latestPos!.speed >= 0) 'speed_mps': _latestPos!.speed,
      if (_latestPos!.heading >= 0) 'heading_deg': _latestPos!.heading,
    };
  }

  static void _onNetworkFailure(Map<String, dynamic> payload) {
    _failureCount++;
    final bool exceeded = _failureCount > _kMaxRetries;
    if (!exceeded) {
      _retryBody = payload;
    } else {
      _retryBody = null;
      _retryBodyCapturedAt = null;
      _failureCount = 0;
    }
    final int backoff = exceeded
        ? _nextPingSec
        : (_nextPingSec * _failureCount).clamp(_nextPingSec, 60);
    _restartTimer(backoff);
    _log(
      'network failure #$_failureCount, retry in ${backoff}s, payload=${jsonEncode(payload)}',
    );
  }

  static void _onClientError(http.Response resp) {
    _retryBody = null;
    _retryBodyCapturedAt = null;
    _failureCount = 0;
    _log('client error status=${resp.statusCode}, not retrying automatically');
    _eventsController.add({
      'lat': _latestPos?.latitude,
      'lng': _latestPos?.longitude,
      'ok': false,
      'message': 'client_error_${resp.statusCode}',
      'next_ping_sec': _nextPingSec,
    });
  }

  static Future<void> _sendPing() async {
    if (_tripId == null ||
        _deliveryId == null ||
        _authHeader == null ||
        _baseUrl == null ||
        _isPinging ||
        _isRefreshingFix) {
      if (_isPinging) _log('skip: previous request still in flight');
      if (_isRefreshingFix) _log('skip: waiting for GPS refresh');
      return;
    }

    final DateTime now = DateTime.now().toUtc();

    if (_lastPingedAt != null &&
        now.difference(_lastPingedAt!).inSeconds < _nextPingSec - 1) {
      _log(
        'skip: throttled, next allowed in '
        '${_nextPingSec - now.difference(_lastPingedAt!).inSeconds}s',
      );
      return;
    }

    if (_latestPos == null) {
      await _refreshLatestPosition('no cached fix');
    } else {
      final int fixAge =
          now.difference(_latestPos!.timestamp.toUtc()).inSeconds;
      if (fixAge > _kStaleLimitSec) {
        await _refreshLatestPosition('stale cached fix age=${fixAge}s');
      }
    }

    final Map<String, dynamic>? body = _resolveBody(now);
    if (body == null) return;

    _isPinging = true;
    _lastPingedAt = now;

    try {
      _log(
        'POST $_baseUrl/api/method/grozfy_go.grozfy_go.api.driver_uplink.location_ping '
        'body=${jsonEncode(body)}',
      );
      final http.Response resp = await http
          .post(
            Uri.parse(
              '$_baseUrl/api/method/grozfy_go.grozfy_go.api.driver_uplink.location_ping',
            ),
            headers: {
              'Authorization': _authHeader!,
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));

      _log('response status=${resp.statusCode} body=${resp.body}');

      if (resp.statusCode == 200) {
        final Map<String, dynamic> raw =
            jsonDecode(resp.body) as Map<String, dynamic>;
        final Map<String, dynamic> json =
            (raw['message'] is Map<String, dynamic>)
                ? raw['message'] as Map<String, dynamic>
                : raw;

        _retryBody = null;
        _retryBodyCapturedAt = null;
        _failureCount = 0;

        final dynamic nextRaw = json['next_ping_sec'];
        final int suggested =
            (nextRaw is num && nextRaw > 0) ? nextRaw.toInt() : _nextPingSec;

        final Position? pos = _latestPos;

        final dynamic msgField = json['message'];
        final String msg = msgField is String ? msgField : '';
        final bool isOk = json['ok'] == true || msg == 'ok';

        if (isOk) {
          _restartTimer(suggested);
          _eventsController.add({
            'lat': pos?.latitude,
            'lng': pos?.longitude,
            'ok': true,
            'next_ping_sec': _nextPingSec,
          });
        } else {
          switch (msg) {
            case 'low_gps_accuracy':
              _restartTimer(suggested);
            case 'impossible_speed':
              _latestPos = null;
            case 'stale location update':
              _latestPos = null;
          }
          _eventsController.add({
            'lat': pos?.latitude,
            'lng': pos?.longitude,
            'ok': false,
            'message': msg,
            'next_ping_sec': suggested,
          });
        }
      } else if (resp.statusCode >= 400 &&
          resp.statusCode < 500 &&
          resp.statusCode != 408 &&
          resp.statusCode != 429) {
        _onClientError(resp);
      } else {
        _onNetworkFailure(body);
      }
    } catch (e) {
      _log('request error: $e');
      _onNetworkFailure(body);
    } finally {
      _isPinging = false;
    }
  }
}

/// Formats [dateTime] as `"YYYY-MM-DD HH:MM:SS"` for Frappe.
String _frappeDateTime(DateTime dateTime) =>
    '${dateTime.year.toString().padLeft(4, '0')}-'
    '${dateTime.month.toString().padLeft(2, '0')}-'
    '${dateTime.day.toString().padLeft(2, '0')} '
    '${dateTime.hour.toString().padLeft(2, '0')}:'
    '${dateTime.minute.toString().padLeft(2, '0')}:'
    '${dateTime.second.toString().padLeft(2, '0')}';
