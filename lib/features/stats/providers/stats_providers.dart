import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/services/secure_token_storage.dart';
import '../../orders_by_location/model/timing_event.dart';
import '../models/driver_stats.dart';

// ── Selected month state for the Stats screen ────────────────────────────────

final selectedMonthProvider = StateProvider<({int month, int year})>((ref) {
  final now = DateTime.now();
  return (month: now.month, year: now.year);
});

// ── Helpers ───────────────────────────────────────────────────────────────────

List<TimingEvent> _rowsToEvents(List<PartnerTimingLog> rows) {
  return rows
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
      .toList();
}

/// Merges ERPNext events with locally-unsynced events, deduplicating by
/// eventUuid. ERPNext events are listed first so they take precedence; local
/// unsynced events fill in anything not yet on the server.
List<TimingEvent> _merge(
  List<TimingEvent> erp,
  List<TimingEvent> localUnsynced,
) {
  final seen = <String>{};
  final result = <TimingEvent>[];
  for (final e in [...erp, ...localUnsynced]) {
    if (seen.add(e.eventUuid)) result.add(e);
  }
  result.sort((a, b) => a.eventTime.compareTo(b.eventTime));
  return result;
}

/// Fetches events from ERPNext. Throws on network/server error so callers
/// can catch and fall back to local data.
Future<List<TimingEvent>> _fetchFromErpNext(
  Map<String, String> params,
) async {
  final prefs = await SharedPreferences.getInstance();
  final driver = prefs.getString('driver_name')?.trim() ?? '';
  if (driver.isEmpty) return [];

  final token = await SecureTokenStorage.read(SecureTokenStorage.accessToken);
  final tokenType =
      (await SecureTokenStorage.read(SecureTokenStorage.tokenType) ?? 'token')
          .trim();

  final headers = <String, String>{'Accept': 'application/json'};
  if (token != null && token.isNotEmpty) {
    headers['Authorization'] = '$tokenType $token';
  }

  final uri = Uri.parse(ApiConstants.getTimingEvents).replace(
    queryParameters: {'driver': driver, ...params},
  );

  final response = await http
      .get(uri, headers: headers)
      .timeout(const Duration(seconds: 15));

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('Server returned ${response.statusCode}');
  }

  final body = jsonDecode(response.body) as Map<String, dynamic>;
  final msg = body['message'];
  if (msg is! Map) return [];
  final logs = (msg as Map<String, dynamic>)['logs'];
  if (logs == null || logs is! List) return [];

  return (logs as List)
      .whereType<Map<String, dynamic>>()
      .map(TimingEvent.fromJson)
      .toList()
    ..sort((a, b) => a.eventTime.compareTo(b.eventTime));
}

// ── Metric computation helpers ────────────────────────────────────────────────

DailySummary _computeDaily(List<TimingEvent> events) {
  final logins = events.where((e) => e.eventType == 'login').toList();
  final logouts = events.where((e) => e.eventType == 'logout').toList();

  Duration dutyHours = Duration.zero;
  if (logins.isNotEmpty) {
    final loginTime = logins.first.eventTime;
    final logoutTime =
        logouts.isNotEmpty ? logouts.last.eventTime : DateTime.now();
    final diff = logoutTime.difference(loginTime);
    if (!diff.isNegative) dutyHours = diff;
  }

  return DailySummary(
    dutyHours: dutyHours,
    tripsCompleted: events.where((e) => e.eventType == 'trip_completed').length,
    avgTripDuration: _avgTripDuration(events),
  );
}

MonthlySummary _computeMonthly(
  List<TimingEvent> events,
  int month,
  int year,
) {
  return MonthlySummary(
    month: month,
    year: year,
    tripsCompleted: events.where((e) => e.eventType == 'trip_completed').length,
    totalRoadTime: _totalTripTime(events),
    avgTripDuration: _avgTripDuration(events),
  );
}

LifetimeStats _computeLifetime(List<TimingEvent> events) {
  return LifetimeStats(
    totalTrips: events.where((e) => e.eventType == 'trip_completed').length,
    totalHours: _totalTripTime(events),
    bestMonth: _bestMonth(events),
    longestStreak: _longestStreak(events),
  );
}

Duration _avgTripDuration(List<TimingEvent> events) {
  final accepted = <String, DateTime>{};
  final durations = <Duration>[];

  for (final e in events) {
    if (e.eventType == 'trip_accepted' && e.tripRef != null) {
      accepted[e.tripRef!] = e.eventTime;
    } else if (e.eventType == 'trip_completed' && e.tripRef != null) {
      final start = accepted[e.tripRef!];
      if (start != null) {
        final diff = e.eventTime.difference(start);
        if (!diff.isNegative) durations.add(diff);
      }
    }
  }

  if (durations.isEmpty) return Duration.zero;
  final totalMs = durations.fold<int>(0, (sum, d) => sum + d.inMilliseconds);
  return Duration(milliseconds: totalMs ~/ durations.length);
}

Duration _totalTripTime(List<TimingEvent> events) {
  final accepted = <String, DateTime>{};
  var total = Duration.zero;

  for (final e in events) {
    if (e.eventType == 'trip_accepted' && e.tripRef != null) {
      accepted[e.tripRef!] = e.eventTime;
    } else if (e.eventType == 'trip_completed' && e.tripRef != null) {
      final start = accepted[e.tripRef!];
      if (start != null) {
        final diff = e.eventTime.difference(start);
        if (!diff.isNegative) total += diff;
      }
    }
  }
  return total;
}

String? _bestMonth(List<TimingEvent> events) {
  final counts = <String, int>{};
  for (final e in events.where((e) => e.eventType == 'trip_completed')) {
    final key =
        '${e.eventTime.year}-${e.eventTime.month.toString().padLeft(2, '0')}';
    counts[key] = (counts[key] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  final best = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
  final parts = best.key.split('-');
  final year = parts[0];
  final month = int.tryParse(parts[1]) ?? 1;
  const monthNames = [
    '',
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return '${monthNames[month]} $year';
}

int _longestStreak(List<TimingEvent> events) {
  final days = events
      .where((e) => e.eventType == 'trip_completed')
      .map((e) => DateTime(e.eventTime.year, e.eventTime.month, e.eventTime.day))
      .toSet()
      .toList()
    ..sort();

  if (days.isEmpty) return 0;

  var longest = 1;
  var current = 1;
  for (int i = 1; i < days.length; i++) {
    if (days[i].difference(days[i - 1]).inDays == 1) {
      current++;
      if (current > longest) longest = current;
    } else {
      current = 1;
    }
  }
  return longest;
}

// ── Providers ─────────────────────────────────────────────────────────────────

/// Daily: local DB only — today's events are always on-device.
final dailySummaryProvider =
    FutureProvider.autoDispose<DailySummary>((ref) async {
  final dao = ref.read(partnerTimingLogDaoProvider);
  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day);
  final endOfDay = startOfDay.add(const Duration(days: 1));
  final rows = await dao.getEventsInRange(startOfDay, endOfDay);
  return _computeDaily(_rowsToEvents(rows));
});

/// Monthly: ERPNext (complete history) merged with any local unsynced events.
/// Falls back to local DB only when offline or after a reinstall with no data.
final monthlySummaryProvider = FutureProvider.autoDispose
    .family<MonthlySummary, ({int month, int year})>((ref, period) async {
  final dao = ref.read(partnerTimingLogDaoProvider);
  final start = DateTime(period.year, period.month, 1);
  final end = period.month < 12
      ? DateTime(period.year, period.month + 1, 1)
      : DateTime(period.year + 1, 1, 1);

  final allLocal = await dao.getEventsInRange(start, end);
  final localUnsynced =
      _rowsToEvents(allLocal.where((r) => !r.isSynced).toList());

  try {
    final erpEvents = await _fetchFromErpNext({
      'type': 'monthly',
      'month': period.month.toString().padLeft(2, '0'),
      'year': period.year.toString(),
    });
    return _computeMonthly(
      _merge(erpEvents, localUnsynced),
      period.month,
      period.year,
    );
  } catch (_) {
    // Offline or server error — fall back to all local events for this period.
    return _computeMonthly(_rowsToEvents(allLocal), period.month, period.year);
  }
});

/// Lifetime: ERPNext (complete history across reinstalls/devices) merged with
/// any local unsynced events. Falls back to local DB only when offline.
final lifetimeStatsProvider =
    FutureProvider.autoDispose<LifetimeStats>((ref) async {
  final dao = ref.read(partnerTimingLogDaoProvider);
  final allLocal = await dao.getAllEvents();
  final localUnsynced =
      _rowsToEvents(allLocal.where((r) => !r.isSynced).toList());

  try {
    final erpEvents = await _fetchFromErpNext({'type': 'lifetime'});
    return _computeLifetime(_merge(erpEvents, localUnsynced));
  } catch (_) {
    // Offline or server error — fall back to all local events.
    return _computeLifetime(_rowsToEvents(allLocal));
  }
});
