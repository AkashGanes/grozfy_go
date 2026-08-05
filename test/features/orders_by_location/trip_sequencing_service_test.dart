import 'package:flutter_test/flutter_test.dart';
import 'package:grozfy_go/features/orders_by_location/services/trip_sequencing_service.dart';

void main() {
  group('TripSequencingService.suggestOrder', () {
    test('orders pending keys nearest-first from the reference point', () {
      final Map<String, (double, double)> coords = {
        'a': (0.0, 0.0),
        'b': (0.0, 1.0),
        'c': (0.0, 0.2),
      };
      final List<String> result = TripSequencingService.suggestOrder(
        fromLat: 0.0,
        fromLng: -0.05,
        pendingKeys: ['a', 'b', 'c'],
        coordsOf: (key) => coords[key],
      );
      expect(result, ['a', 'c', 'b']);
    });

    test('falls back to server order when no reference point is available',
        () {
      final List<String> result = TripSequencingService.suggestOrder(
        fromLat: null,
        fromLng: null,
        pendingKeys: ['x', 'y', 'z'],
        coordsOf: (key) => (0.0, 0.0),
      );
      expect(result, ['x', 'y', 'z']);
    });

    test('appends stops with no resolvable coordinates at the end', () {
      final Map<String, (double, double)> coords = {'a': (0.0, 0.0)};
      final List<String> result = TripSequencingService.suggestOrder(
        fromLat: 0.0,
        fromLng: 0.0,
        pendingKeys: ['unresolved', 'a'],
        coordsOf: (key) => coords[key],
      );
      expect(result, ['a', 'unresolved']);
    });

    test('handles an empty pending list', () {
      final List<String> result = TripSequencingService.suggestOrder(
        fromLat: 0.0,
        fromLng: 0.0,
        pendingKeys: [],
        coordsOf: (key) => null,
      );
      expect(result, isEmpty);
    });
  });

  group('TripSequencingService.mergeManualOrder', () {
    test('fully replaces display order with suggested order when manual mode is off',
        () {
      final List<String> result = TripSequencingService.mergeManualOrder(
        currentDisplayOrder: ['old1', 'old2'],
        pendingKeys: ['a', 'b'],
        manualOrderActive: false,
        suggestedOrder: ['b', 'a'],
      );
      expect(result, ['b', 'a']);
    });

    test(
        'preserves manual arrangement, drops completed stops, appends new ones',
        () {
      final List<String> result = TripSequencingService.mergeManualOrder(
        currentDisplayOrder: ['b', 'a', 'completed'],
        pendingKeys: ['a', 'b', 'new'],
        manualOrderActive: true,
        suggestedOrder: ['a', 'b', 'new'],
      );
      // 'completed' dropped (no longer pending), manual b-before-a order
      // kept, 'new' appended at the end in server order.
      expect(result, ['b', 'a', 'new']);
    });

    test('manual mode with no changes returns the same relative order', () {
      final List<String> result = TripSequencingService.mergeManualOrder(
        currentDisplayOrder: ['a', 'b', 'c'],
        pendingKeys: ['a', 'b', 'c'],
        manualOrderActive: true,
        suggestedOrder: ['c', 'b', 'a'],
      );
      expect(result, ['a', 'b', 'c']);
    });
  });
}
