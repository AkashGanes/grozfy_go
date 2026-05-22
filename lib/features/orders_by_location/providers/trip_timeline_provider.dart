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

class TimelineEmpty extends TimelineResult {}

class TimelinePending extends TimelineResult {}

class TimelineData extends TimelineResult {
  TimelineData(this.events);
  final List<TimingEvent> events;
}

final tripTimelineProvider = FutureProvider.autoDispose
    .family<TimelineResult, String>((ref, tripName) async {
  final dao = ref.read(partnerTimingLogDaoProvider);

  final prefs = await SharedPreferences.getInstance();
  final driver = prefs.getString('driver_name')?.trim() ?? '';

  if (driver.isNotEmpty) {
    try {
      final token = await SecureTokenStorage.read(SecureTokenStorage.accessToken);
      final tokenType =
          (await SecureTokenStorage.read(SecureTokenStorage.tokenType) ?? 'token')
              .trim();

      final headers = <String, String>{'Accept': 'application/json'};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = '$tokenType $token';
      }

      final uri = Uri.parse(ApiConstants.getTimingEvents).replace(
        queryParameters: {'driver': driver, 'type': 'daily'},
      );

      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final msg = body['message'];
        if (msg is Map) {
          final logs = (msg as Map<String, dynamic>)['logs'];
          if (logs is List) {
            final allErpEvents = logs
                .whereType<Map<String, dynamic>>()
                .map(TimingEvent.fromJson)
                .toList();

            final tripEvents = allErpEvents
                .where((e) => e.tripRef == tripName)
                .toList()
              ..sort((a, b) => a.eventTime.compareTo(b.eventTime));

            if (tripEvents.isNotEmpty) {
              return TimelineData(tripEvents);
            }
          }
        }
      }
    } catch (_) {}
  }

  // Local DB fallback
  final localRows = await dao.getEventsByTrip(tripName);

  if (localRows.isNotEmpty) {
    final unsyncedRows = localRows.where((r) => !r.isSynced).toList();

    if (unsyncedRows.isNotEmpty) {
      TimingSyncEngine().triggerFlush();
      return TimelinePending();
    }

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

  return TimelineEmpty();
});
