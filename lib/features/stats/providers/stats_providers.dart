import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/services/secure_token_storage.dart';
import '../../orders_by_location/model/timing_event.dart';
import '../../orders_by_location/repository/external_delivery_repository.dart';
import '../models/driver_stats.dart';

final selectedMonthProvider = StateProvider<({int month, int year})>((ref) {
  final now = DateTime.now();
  return (month: now.month, year: now.year);
});

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

List<TimingEvent> _merge(
  List<TimingEvent> erp,
  List<TimingEvent> local,
) {
  final seen = <String>{};
  final result = <TimingEvent>[];
  for (final e in [...erp, ...local]) {
    if (seen.add(e.eventUuid)) result.add(e);
  }
  result.sort((a, b) => a.eventTime.compareTo(b.eventTime));
  return result;
}

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
  if (msg is! Map) {
    throw Exception('Unexpected response format: message=${msg.runtimeType}');
  }
  final logs = (msg as Map<String, dynamic>)['logs'];
  if (logs == null || logs is! List) {
    throw Exception('Missing logs array in response');
  }

  return (logs as List)
      .whereType<Map<String, dynamic>>()
      .map(TimingEvent.fromJson)
      .toList()
    ..sort((a, b) => a.eventTime.compareTo(b.eventTime));
}

DailySummary _computeDaily(List<TimingEvent> events) {
  final hasLogin = events.any((e) => e.eventType == 'driver_login');

  Duration dutyHours = Duration.zero;
  if (hasLogin) {
    // Walk events in chronological order as a state machine.
    // Each login starts a duty window; the next logout closes it.
    // Multiple sessions per day are summed, not just the first pair.
    DateTime? activeLogin;
    for (final e in events) {
      if (e.eventType == 'driver_login' && activeLogin == null) {
        activeLogin = e.eventTime;
      } else if (e.eventType == 'driver_logout' && activeLogin != null) {
        final diff = e.eventTime.difference(activeLogin);
        if (!diff.isNegative) dutyHours += diff;
        activeLogin = null;
      }
    }
    // Still on duty — accumulate up to now.
    if (activeLogin != null) {
      final diff = DateTime.now().difference(activeLogin);
      if (!diff.isNegative) dutyHours += diff;
    }
  }

  return DailySummary(
    dutyHours: dutyHours,
    tripsCompleted: _countCompletedTrips(events),
    avgTripDuration: _avgTripDuration(events),
  );
}

MonthlySummary _computeMonthly(
  List<TimingEvent> events,
  int month,
  int year,
) {
  final delivered = events.where((e) => e.eventType == 'stop_delivered').length;
  final failed = events.where((e) => e.eventType == 'stop_failed').length;
  final totalStops = delivered + failed;
  final onTimePercent =
      totalStops > 0 ? (delivered / totalStops) * 100 : null;

  return MonthlySummary(
    month: month,
    year: year,
    tripsCompleted: _countCompletedTrips(events),
    totalRoadTime: _totalTripTime(events),
    avgTripDuration: _avgTripDuration(events),
    onTimePercent: onTimePercent,
  );
}

LifetimeStats _computeLifetime(List<TimingEvent> events) {
  return LifetimeStats(
    totalTrips: _countCompletedTrips(events),
    totalHours: _totalTripTime(events),
    bestMonth: _bestMonth(events),
    longestStreak: _longestStreak(events),
  );
}

/// Counts distinct trips that were worked on.
/// A trip counts as completed when either:
///   - a `trip_completed` event exists for it, OR
///   - at least one `stop_delivered` or `stop_failed` event exists for it.
/// This handles drivers who skip "Returned to Store".
int _countCompletedTrips(List<TimingEvent> events) {
  final completedByTripCompleted = events
      .where((e) => e.eventType == 'trip_completed' && e.tripRef != null)
      .map((e) => e.tripRef!)
      .toSet();

  final completedByStopEvent = events
      .where((e) =>
          (e.eventType == 'stop_delivered' || e.eventType == 'stop_failed') &&
          e.tripRef != null)
      .map((e) => e.tripRef!)
      .toSet();

  return {...completedByTripCompleted, ...completedByStopEvent}.length;
}

Duration _avgTripDuration(List<TimingEvent> events) {
  final accepted = <String, DateTime>{};
  final durations = <Duration>[];

  // Collect trip_accepted timestamps keyed by tripRef.
  for (final e in events) {
    if (e.eventType == 'trip_accepted' && e.tripRef != null) {
      accepted[e.tripRef!] = e.eventTime;
    }
  }

  // For each trip, use trip_completed if available, else the last stop event.
  final tripEndTimes = <String, DateTime>{};
  for (final e in events) {
    if (e.tripRef == null) continue;
    if (e.eventType == 'trip_completed') {
      tripEndTimes[e.tripRef!] = e.eventTime;
    } else if (e.eventType == 'stop_delivered' || e.eventType == 'stop_failed') {
      // Only use stop event as fallback if no trip_completed recorded yet.
      final existing = tripEndTimes[e.tripRef!];
      if (existing == null || e.eventTime.isAfter(existing)) {
        // Will be overwritten if trip_completed comes later in the loop.
        tripEndTimes[e.tripRef!] ??= e.eventTime;
      }
    }
  }

  for (final entry in accepted.entries) {
    final end = tripEndTimes[entry.key];
    if (end != null) {
      final diff = end.difference(entry.value);
      if (!diff.isNegative) durations.add(diff);
    }
  }

  if (durations.isEmpty) return Duration.zero;
  final totalMs = durations.fold<int>(0, (sum, d) => sum + d.inMilliseconds);
  return Duration(milliseconds: totalMs ~/ durations.length);
}

Duration _totalTripTime(List<TimingEvent> events) {
  // Reuse _avgTripDuration logic: sum of all individual trip durations.
  final accepted = <String, DateTime>{};
  var total = Duration.zero;

  for (final e in events) {
    if (e.eventType == 'trip_accepted' && e.tripRef != null) {
      accepted[e.tripRef!] = e.eventTime;
    }
  }

  final tripEndTimes = <String, DateTime>{};
  for (final e in events) {
    if (e.tripRef == null) continue;
    if (e.eventType == 'trip_completed') {
      tripEndTimes[e.tripRef!] = e.eventTime;
    } else if (e.eventType == 'stop_delivered' || e.eventType == 'stop_failed') {
      tripEndTimes[e.tripRef!] ??= e.eventTime;
    }
  }

  for (final entry in accepted.entries) {
    final end = tripEndTimes[entry.key];
    if (end != null) {
      final diff = end.difference(entry.value);
      if (!diff.isNegative) total += diff;
    }
  }
  return total;
}

String? _bestMonth(List<TimingEvent> events) {
  final counts = <String, int>{};
  // Count trips per month using trip_completed or stop_delivered as completion signal.
  final tripDays = <String, Set<String>>{};
  for (final e in events) {
    if ((e.eventType == 'trip_completed' || e.eventType == 'stop_delivered') &&
        e.tripRef != null) {
      final monthKey =
          '${e.eventTime.year}-${e.eventTime.month.toString().padLeft(2, '0')}';
      tripDays.putIfAbsent(monthKey, () => <String>{}).add(e.tripRef!);
    }
  }
  for (final entry in tripDays.entries) {
    counts[entry.key] = entry.value.length;
  }
  if (counts.isEmpty) return null;
  final best = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
  final parts = best.key.split('-');
  final year = parts[0];
  final month = int.tryParse(parts[1]) ?? 1;
  return AppDateFormat.monthYearFromParts(month, int.parse(year));
}

int _longestStreak(List<TimingEvent> events) {
  // Use either trip_completed or stop_delivered as a "worked today" signal.
  final days = events
      .where((e) =>
          e.eventType == 'trip_completed' || e.eventType == 'stop_delivered')
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

final dailySummaryProvider =
    FutureProvider.autoDispose<DailySummary>((ref) async {
  final dao = ref.read(partnerTimingLogDaoProvider);
  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day);
  final endOfDay = startOfDay.add(const Duration(days: 1));

  final allLocal = await dao.getEventsInRange(startOfDay, endOfDay);
  final localEvents = _rowsToEvents(allLocal);

  try {
    final erpEvents = await _fetchFromErpNext({'type': 'daily'});
    return _computeDaily(_merge(erpEvents, localEvents));
  } catch (_) {
    return _computeDaily(localEvents);
  }
});

final monthlySummaryProvider = FutureProvider.autoDispose
    .family<MonthlySummary, ({int month, int year})>((ref, period) async {
  final dao = ref.read(partnerTimingLogDaoProvider);
  final start = DateTime(period.year, period.month, 1);
  final end = period.month < 12
      ? DateTime(period.year, period.month + 1, 1)
      : DateTime(period.year + 1, 1, 1);

  final allLocal = await dao.getEventsInRange(start, end);
  final localEvents = _rowsToEvents(allLocal);

  try {
    final erpEvents = await _fetchFromErpNext({
      'type': 'monthly',
      'month': period.month.toString().padLeft(2, '0'),
      'year': period.year.toString(),
    });
    return _computeMonthly(_merge(erpEvents, localEvents), period.month, period.year);
  } catch (_) {
    return _computeMonthly(localEvents, period.month, period.year);
  }
});

final lifetimeStatsProvider =
    FutureProvider.autoDispose<LifetimeStats>((ref) async {
  final dao = ref.read(partnerTimingLogDaoProvider);
  final allLocal = await dao.getAllEvents();
  final localEvents = _rowsToEvents(allLocal);

  try {
    final erpEvents = await _fetchFromErpNext({'type': 'lifetime'});
    return _computeLifetime(_merge(erpEvents, localEvents));
  } catch (_) {
    return _computeLifetime(localEvents);
  }
});

/// Total delivered orders for the logged-in driver.
/// Yields the SharedPreferences cache immediately (no loading flash),
/// then silently refreshes from ERPNext and updates the cache.
final deliveredOrderCountProvider =
    StreamProvider.autoDispose<int>((ref) async* {
  final prefs = await SharedPreferences.getInstance();
  final cached = prefs.getInt('delivered_order_count');
  if (cached != null) yield cached;

  final repo = ExternalDeliveryRepository();
  try {
    final count = await repo.fetchDeliveredCountForDriver();
    await prefs.setInt('delivered_order_count', count);
    yield count;
  } catch (_) {
    if (cached == null) rethrow;
  }
});
