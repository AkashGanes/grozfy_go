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

  final events = (logs as List)
      .whereType<Map<String, dynamic>>()
      .map(TimingEvent.fromJson)
      .toList()
    ..sort((a, b) => a.eventTime.compareTo(b.eventTime));

  return events;
}

DailySummary _computeDaily(List<TimingEvent> events) {
  final logins = events.where((e) => e.eventType == 'driver_login').toList();
  final logouts = events.where((e) => e.eventType == 'driver_logout').toList();

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
  final delivered = events.where((e) => e.eventType == 'stop_delivered').length;
  final failed = events.where((e) => e.eventType == 'stop_failed').length;
  final totalStops = delivered + failed;
  final onTimePercent =
      totalStops > 0 ? (delivered / totalStops) * 100 : null;

  return MonthlySummary(
    month: month,
    year: year,
    tripsCompleted: events.where((e) => e.eventType == 'trip_completed').length,
    totalRoadTime: _totalTripTime(events),
    avgTripDuration: _avgTripDuration(events),
    onTimePercent: onTimePercent,
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
  return AppDateFormat.monthYearFromParts(month, int.parse(year));
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
    final merged = _merge(erpEvents, localEvents);
    return _computeDaily(merged);
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
    final merged = _merge(erpEvents, localEvents);
    return _computeMonthly(merged, period.month, period.year);
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
    final merged = _merge(erpEvents, localEvents);
    return _computeLifetime(merged);
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
