import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import '../database/partner_timing_log_dao.dart';
import '../services/connectivity_service.dart';
import '../services/secure_token_storage.dart';

class TimingSyncEngine {
  static final TimingSyncEngine _instance = TimingSyncEngine._internal();
  factory TimingSyncEngine() => _instance;
  TimingSyncEngine._internal();

  static const Duration _networkTimeout = Duration(seconds: 15);

  PartnerTimingLogDao? _dao;
  StreamSubscription<bool>? _connectivitySubscription;
  bool _isSyncing = false;

  Future<void> initialize(PartnerTimingLogDao dao) async {
    _dao = dao;
    final connectivity = ConnectivityService();
    _connectivitySubscription = connectivity.connectivityStream.listen((
      isConnected,
    ) {
      if (isConnected) {
        unawaited(_flushToErpNext());
      }
    });
    // Broadcast streams don't replay past events, so if the device is
    // already online when we subscribe the listener never fires. Kick off
    // an immediate drain so events from a previous offline session are not
    // stuck until the next connectivity change.
    if (await connectivity.checkConnectivity()) {
      unawaited(_flushToErpNext());
    }
  }

  Future<void> _flushToErpNext() async {
    // Claim the lock synchronously before any await so two concurrent
    // triggers (boot-time call + connectivity stream) don't both slip
    // through the guard and double-send the same batch.
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final dao = _dao;
      if (dao == null) return;

      final events = await dao.getUnsyncedEvents();
      if (events.isEmpty) return;

      final payload = events
          .map(
            (e) => {
              'event_uuid': e.eventUuid,
              'driver': e.partner,
              'event_type': e.eventType,
              'occurred_at': e.eventTime,
              'trip_ref': e.tripName,
              'stop_ref': e.stopName,
            },
          )
          .toList();

      final headers = await _authHeaders();
      final response = await http
          .post(
            Uri.parse(ApiConstants.recordTimingEvents),
            headers: {...headers, 'Content-Type': 'application/json'},
            body: jsonEncode({'events': payload}),
          )
          .timeout(_networkTimeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        for (final event in events) {
          try {
            await dao.markAsSynced(event.eventUuid);
          } catch (e) {
            debugPrint('[TimingSyncEngine] markAsSynced failed: $e');
          }
        }
        debugPrint('[TimingSyncEngine] Synced ${events.length} timing events');
      } else {
        debugPrint(
          '[TimingSyncEngine] Server returned ${response.statusCode} — will retry',
        );
      }
    } catch (e) {
      debugPrint('[TimingSyncEngine] Flush failed: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<Map<String, String>> _authHeaders() async {
    final String? token = await SecureTokenStorage.read(
      SecureTokenStorage.accessToken,
    );
    final String tokenType =
        (await SecureTokenStorage.read(SecureTokenStorage.tokenType) ?? 'token')
            .trim();
    if (token != null && token.isNotEmpty) {
      return {
        'Accept': 'application/json',
        'Authorization': '$tokenType $token',
      };
    }
    return {'Accept': 'application/json'};
  }

  /// Call this immediately after writing a timing event to local DB so events
  /// are pushed to ERPNext without waiting for the next connectivity change.
  void triggerFlush() {
    unawaited(_flushToErpNext());
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }
}
