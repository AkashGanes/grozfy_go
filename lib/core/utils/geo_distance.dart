import 'dart:math' as math;

/// Straight-line distance between two coordinates, in meters.
double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const double earthRadiusMeters = 6371000;
  final double dLat = _degToRad(lat2 - lat1);
  final double dLng = _degToRad(lng2 - lng1);
  final double a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_degToRad(lat1)) *
          math.cos(_degToRad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusMeters * c;
}

double _degToRad(double deg) => deg * (math.pi / 180);

/// True when ([lat], [lng]) fall within valid Earth coordinate ranges
/// (latitude ±90, longitude ±180) and aren't the common "unset" sentinel
/// (0, 0) — guards against corrupt/placeholder backend data (e.g. a stray
/// amount or count field mistakenly stored in a latitude/longitude column)
/// being treated as a real location for sequencing or navigation.
bool isValidLatLng(double lat, double lng) {
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return false;
  if (lat == 0 && lng == 0) return false;
  return true;
}

/// Greedy nearest-neighbor chain: starting from `(fromLat, fromLng)`, repeatedly
/// picks the closest remaining item (by [coordsOf]), then continues from that
/// item's own coordinates. Items with no resolvable coordinates are excluded
/// from the chain and appended at the end, preserving their relative input order.
List<T> nearestNeighborOrder<T>(
  double fromLat,
  double fromLng,
  List<T> items, {
  required (double, double)? Function(T item) coordsOf,
}) {
  final List<T> located = <T>[];
  final List<T> unlocated = <T>[];
  for (final T item in items) {
    if (coordsOf(item) != null) {
      located.add(item);
    } else {
      unlocated.add(item);
    }
  }

  final List<T> remaining = List<T>.from(located);
  final List<T> ordered = <T>[];
  double refLat = fromLat;
  double refLng = fromLng;

  while (remaining.isNotEmpty) {
    int nearestIndex = 0;
    double nearestDistance = double.infinity;
    for (int i = 0; i < remaining.length; i++) {
      final (double, double) coords = coordsOf(remaining[i])!;
      final double distance = haversineMeters(
        refLat,
        refLng,
        coords.$1,
        coords.$2,
      );
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = i;
      }
    }
    final T nearest = remaining.removeAt(nearestIndex);
    final (double, double) nearestCoords = coordsOf(nearest)!;
    refLat = nearestCoords.$1;
    refLng = nearestCoords.$2;
    ordered.add(nearest);
  }

  return <T>[...ordered, ...unlocated];
}
