import 'package:flutter_test/flutter_test.dart';
import 'package:grozfy_go/features/delivery_radius/model/delivery_radius_settings.dart';

void main() {
  group('DeliveryRadiusSettings.fromJson', () {
    test('parses all fields and keeps the selected value', () {
      final s = DeliveryRadiusSettings.fromJson({
        'delivery_radius_enabled': 1,
        'minimum_radius_km': 2,
        'default_radius_km': 5,
        'maximum_radius_km': 10,
        'selected_radius_km': 7,
      });

      expect(s.enabled, isTrue);
      expect(s.minimumRadiusKm, 2);
      expect(s.defaultRadiusKm, 5);
      expect(s.maximumRadiusKm, 10);
      expect(s.selectedRadiusKm, 7);
      expect(s.effectiveRadiusKm, 7);
      expect(s.hasValidBounds, isTrue);
    });

    test('falls back to default when selected_radius_km is null', () {
      final s = DeliveryRadiusSettings.fromJson({
        'delivery_radius_enabled': true,
        'minimum_radius_km': 1,
        'default_radius_km': 5,
        'maximum_radius_km': 25,
        'selected_radius_km': null,
      });

      expect(s.selectedRadiusKm, isNull);
      expect(s.effectiveRadiusKm, 5);
    });

    test('reads enabled from various truthy/falsey encodings', () {
      expect(
        DeliveryRadiusSettings.fromJson({'delivery_radius_enabled': 0}).enabled,
        isFalse,
      );
      expect(
        DeliveryRadiusSettings.fromJson({
          'delivery_radius_enabled': '1',
        }).enabled,
        isTrue,
      );
      expect(
        DeliveryRadiusSettings.fromJson({
          'delivery_radius_enabled': false,
        }).enabled,
        isFalse,
      );
    });

    test('parses string numbers from the backend', () {
      final s = DeliveryRadiusSettings.fromJson({
        'delivery_radius_enabled': 1,
        'minimum_radius_km': '2',
        'default_radius_km': '5',
        'maximum_radius_km': '10.0',
        'selected_radius_km': '8.5',
      });

      expect(s.minimumRadiusKm, 2);
      expect(s.maximumRadiusKm, 10);
      expect(s.selectedRadiusKm, 8.5);
    });

    test('hasValidBounds is false when max does not exceed min', () {
      final s = DeliveryRadiusSettings.fromJson({
        'delivery_radius_enabled': 1,
        'minimum_radius_km': 10,
        'default_radius_km': 10,
        'maximum_radius_km': 10,
      });

      expect(s.hasValidBounds, isFalse);
    });

    test('parses the deployed backend shape (short keys, selected 0 = unset)', () {
      final s = DeliveryRadiusSettings.fromJson({
        'driver': 'HR-DRI-2026-00009',
        'enabled': true,
        'minimum_km': 2.0,
        'maximum_km': 10.0,
        'default_km': 5.0,
        'selected_km': 0.0,
      });

      expect(s.enabled, isTrue);
      expect(s.minimumRadiusKm, 2);
      expect(s.maximumRadiusKm, 10);
      expect(s.defaultRadiusKm, 5);
      // selected_km == 0 means "not chosen yet" → fall back to default.
      expect(s.selectedRadiusKm, isNull);
      expect(s.effectiveRadiusKm, 5);
      expect(s.hasValidBounds, isTrue);
    });

    test('keeps a real selected_km from the backend', () {
      final s = DeliveryRadiusSettings.fromJson({
        'enabled': true,
        'minimum_km': 2.0,
        'maximum_km': 10.0,
        'default_km': 5.0,
        'selected_km': 7.0,
      });

      expect(s.selectedRadiusKm, 7);
      expect(s.effectiveRadiusKm, 7);
    });

    test('withSelected can reset the selection back to null', () {
      final s = DeliveryRadiusSettings.fromJson({
        'delivery_radius_enabled': 1,
        'minimum_radius_km': 1,
        'default_radius_km': 5,
        'maximum_radius_km': 20,
        'selected_radius_km': 9,
      });

      expect(s.withSelected(null).selectedRadiusKm, isNull);
      expect(s.withSelected(12).selectedRadiusKm, 12);
    });
  });
}
