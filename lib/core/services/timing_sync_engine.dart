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
    await dao.migrateEventTypes();

    final connectivity = ConnectivityService();
    _connectivitySubscription = connectivity.connectivityStream.listen((
      isConnected,
    ) {
      if (isConnected) {
        unawaited(_flushToErpNext());
      }
    });

    final online = await connectivity.checkConnectivity();
    if (online) {
      unawaited(_flushToErpNext());
    }
  }

  Future<void> _flushToErpNext() async {
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
        // null = key absent (old server → mark all as fallback)
        // non-null = key present; empty set means 0 successes → mark none
        Set<String>? syncedUuids;
        try {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final msg = body['message'];
          if (msg is Map) {
            final msgMap = msg as Map<String, dynamic>;
            if (msgMap.containsKey('synced_uuids')) {
              final uuidList = msgMap['synced_uuids'];
              if (uuidList is List) {
                syncedUuids = uuidList.map((e) => e.toString()).toSet();
              }
            }
          }
        } catch (_) {}

        // If server returned synced_uuids, only mark confirmed UUIDs.
        // If key absent (old server), fall back to marking all so the queue doesn't stall.
        final toMark = syncedUuids != null
            ? events.where((e) => syncedUuids!.contains(e.eventUuid)).toList()
            : events;

        for (final event in toMark) {
          try {
            await dao.markAsSynced(event.eventUuid);
          } catch (_) {}
        }
      }
    } catch (_) {
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

  void triggerFlush() {
    unawaited(_flushToErpNext());
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }
}
