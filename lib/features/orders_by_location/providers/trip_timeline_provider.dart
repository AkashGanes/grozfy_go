import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/services/secure_token_storage.dart';
import '../../../core/services/timing_sync_engine.dart';
import '../model/timing_event.dart';

sealed class TimelineResult {}

/// ERPNext returned an empty list — trip has no recorded events yet.
class TimelineEmpty extends TimelineResult {}

/// Events successfully fetched (either from local DB or ERPNext).
class TimelineData extends TimelineResult {
  TimelineData(this.events);
  final List<TimingEvent> events;
}

/// Fetches the trip stage timeline for [tripName].
///
/// Flow:
///   1. Check local Drift for all events belonging to this trip (synced or not).
///      If any exist, show them immediately and trigger a background sync for
///      any that haven't reached ERPNext yet.
///   2. If no local events (e.g. historical trip on a fresh install), fall back
///      to a GET from ERPNext.
final tripTimelineProvider = FutureProvider.autoDispose
    .family<TimelineResult, String>((ref, tripName) async {
  // ── 1. Local events (covers both synced and unsynced) ────────────────────
  final dao = ref.read(partnerTimingLogDaoProvider);
  final localRows = await dao.getEventsByTrip(tripName);

  if (localRows.isNotEmpty) {
    // If any rows are still unsynced, kick off a flush in the background so
    // they land on ERPNext without the user having to wait.
    final hasUnsynced = localRows.any((r) => !r.isSynced);
    if (hasUnsynced) TimingSyncEngine().triggerFlush();

    final events = localRows
        .map(
          (r) => TimingEvent(
            eventUuid: r.eventUuid,
            partner: r.partner,
            eventType: r.eventType,
            eventTime: DateTime.parse(r.eventTime),
            tripRef: r.tripName,
            stopRef: r.stopName,
          ),
        )
        .toList()
      ..sort((a, b) => a.eventTime.compareTo(b.eventTime));

    return TimelineData(events);
  }

  // ── 2. No local events — fetch from ERPNext (historical / other device) ──
  final prefs = await SharedPreferences.getInstance();
  final driver = prefs.getString('driver_name')?.trim() ?? '';
  if (driver.isEmpty) return TimelineEmpty();

  final token = await SecureTokenStorage.read(SecureTokenStorage.accessToken);
  final tokenType =
      (await SecureTokenStorage.read(SecureTokenStorage.tokenType) ?? 'token')
          .trim();

  final headers = <String, String>{'Accept': 'application/json'};
  if (token != null && token.isNotEmpty) {
    headers['Authorization'] = '$tokenType $token';
  }

  final uri = Uri.parse(ApiConstants.getTimingEvents).replace(
    queryParameters: {'driver': driver, 'trip_ref': tripName},
  );

  final response = await http
      .get(uri, headers: headers)
      .timeout(const Duration(seconds: 15));

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('Server returned ${response.statusCode}');
  }

  final body = jsonDecode(response.body) as Map<String, dynamic>;
  final msg = body['message'];
  if (msg is! Map) return TimelineEmpty();
  final logs = (msg as Map<String, dynamic>)['logs'];
  if (logs == null || logs is! List || (logs as List).isEmpty) {
    return TimelineEmpty();
  }

  final events = (logs as List)
      .whereType<Map<String, dynamic>>()
      .map(TimingEvent.fromJson)
      .toList()
    ..sort((a, b) => a.eventTime.compareTo(b.eventTime));

  return TimelineData(events);
});
