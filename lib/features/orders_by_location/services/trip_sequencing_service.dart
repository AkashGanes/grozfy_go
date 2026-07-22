import '../../../core/utils/geo_distance.dart';

/// Pure, Flutter-independent nearest-first sequencing logic for multi-stop
/// trips. Extracted from `_resolveStopSequencing` so it can be unit-tested in
/// isolation and swapped for a smarter optimizer (e.g. a backend route
/// service) later without touching any widget code.
class TripSequencingService {
  const TripSequencingService._();

  /// Nearest-neighbor order of [pendingKeys] starting from ([fromLat],
  /// [fromLng]), using [coordsOf] to resolve each key's coordinates. Falls
  /// back to [pendingKeys] verbatim (server order) when no reference point is
  /// available.
  static List<String> suggestOrder({
    required double? fromLat,
    required double? fromLng,
    required List<String> pendingKeys,
    required (double, double)? Function(String key) coordsOf,
  }) {
    if (fromLat == null || fromLng == null) {
      return List<String>.from(pendingKeys);
    }
    return nearestNeighborOrder<String>(
      fromLat,
      fromLng,
      pendingKeys,
      coordsOf: coordsOf,
    );
  }

  /// Merges [suggestedOrder] into [currentDisplayOrder]. When
  /// [manualOrderActive] is false, the suggested order fully replaces the
  /// display order. When true, the driver's current arrangement is preserved
  /// (dropping any keys no longer in [pendingKeys] — i.e. completed/vanished
  /// stops — and appending brand-new pending keys in server order), exactly
  /// matching the "manual order sticks" behavior of the original
  /// `_resolveStopSequencing`.
  static List<String> mergeManualOrder({
    required List<String> currentDisplayOrder,
    required List<String> pendingKeys,
    required bool manualOrderActive,
    required List<String> suggestedOrder,
  }) {
    if (!manualOrderActive) {
      return List<String>.from(suggestedOrder);
    }
    final Set<String> pendingSet = pendingKeys.toSet();
    final List<String> kept = currentDisplayOrder
        .where((String k) => pendingSet.contains(k))
        .toList();
    final List<String> newOnes = pendingKeys
        .where((String k) => !kept.contains(k))
        .toList();
    return <String>[...kept, ...newOnes];
  }
}
