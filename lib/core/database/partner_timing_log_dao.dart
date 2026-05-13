import 'package:drift/drift.dart';

import 'app_database.dart';

part 'partner_timing_log_dao.g.dart';

@DriftAccessor(tables: [PartnerTimingLogs])
class PartnerTimingLogDao extends DatabaseAccessor<FlowFleetDatabase>
    with _$PartnerTimingLogDaoMixin {
  PartnerTimingLogDao(super.db);

  Future<void> insertEvent(PartnerTimingLogsCompanion event) {
    return into(partnerTimingLogs).insertOnConflictUpdate(event);
  }

  Future<List<PartnerTimingLog>> getUnsyncedEvents() {
    return (select(partnerTimingLogs)
          ..where((t) => t.isSynced.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.eventTime)]))
        .get();
  }

  Future<void> markAsSynced(String eventUuid) {
    return (update(partnerTimingLogs)
          ..where((t) => t.eventUuid.equals(eventUuid)))
        .write(const PartnerTimingLogsCompanion(isSynced: Value(true)));
  }

  Future<List<PartnerTimingLog>> getEventsByTrip(String tripName) {
    return (select(partnerTimingLogs)
          ..where((t) => t.tripName.equals(tripName))
          ..orderBy([(t) => OrderingTerm.asc(t.eventTime)]))
        .get();
  }

  /// Returns all events whose [eventTime] falls within [start, end).
  /// ISO-8601 strings compare lexicographically in the same order as
  /// chronologically, so plain string comparison is correct here.
  Future<List<PartnerTimingLog>> getEventsInRange(
    DateTime start,
    DateTime end,
  ) {
    final startStr = start.toIso8601String();
    final endStr = end.toIso8601String();
    return (select(partnerTimingLogs)
          ..where(
            (t) =>
                t.eventTime.isBiggerOrEqualValue(startStr) &
                t.eventTime.isSmallerThanValue(endStr),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.eventTime)]))
        .get();
  }

  Future<List<PartnerTimingLog>> getAllEvents() {
    return (select(partnerTimingLogs)
          ..orderBy([(t) => OrderingTerm.asc(t.eventTime)]))
        .get();
  }
}

/// Event type constants that mirror the ERPNext Partner Timing Log values.
class TimingEventType {
  TimingEventType._();

  static const String login = 'login';
  static const String logout = 'logout';
  static const String tripAccepted = 'trip_accepted';
  static const String pickupReached = 'pickup_reached';
  static const String pickedUp = 'picked_up';
  static const String stopDelivered = 'stop_delivered';
  static const String stopFailed = 'stop_failed';
  static const String tripStarted = 'trip_started';
  static const String tripCompleted = 'trip_completed';
}
