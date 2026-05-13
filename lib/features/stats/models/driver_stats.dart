class DailySummary {
  const DailySummary({
    required this.dutyHours,
    required this.tripsCompleted,
    required this.avgTripDuration,
  });

  final Duration dutyHours;
  final int tripsCompleted;
  final Duration avgTripDuration;

  static const DailySummary empty = DailySummary(
    dutyHours: Duration.zero,
    tripsCompleted: 0,
    avgTripDuration: Duration.zero,
  );
}

class MonthlySummary {
  const MonthlySummary({
    required this.month,
    required this.year,
    required this.tripsCompleted,
    required this.totalRoadTime,
    required this.avgTripDuration,
  });

  final int month;
  final int year;
  final int tripsCompleted;
  final Duration totalRoadTime;
  final Duration avgTripDuration;
}

class LifetimeStats {
  const LifetimeStats({
    required this.totalTrips,
    required this.totalHours,
    required this.longestStreak,
    this.bestMonth,
  });

  final int totalTrips;
  final Duration totalHours;
  final int longestStreak;
  final String? bestMonth; // e.g. "March 2026"
}
