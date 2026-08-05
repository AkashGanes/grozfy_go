import 'package:flutter_test/flutter_test.dart';
import 'package:grozfy_go/features/orders_by_location/model/external_delivery.dart';
import 'package:grozfy_go/features/orders_by_location/model/external_delivery_detail.dart';

void main() {
  group('ExternalDelivery.fromJson distance_km', () {
    test('parses server-provided distance_km from list_available_deliveries', () {
      final d = ExternalDelivery.fromJson({
        'name': 'EXT-DEL-2026-03076',
        'store_name': 'Sunrise Mart',
        'store_url': 'https://example.com',
        'customer_name': 'A. Kumar',
        'status': 'Pending',
        'creation': '2026-07-23 10:12:00',
        'modified': '2026-07-23 10:40:00',
        'latitude': 8.135,
        'longitude': 77.350,
        'distance_km': 1.8,
      });

      expect(d.distanceKm, 1.8);
      expect(d.status, 'Pending');
      expect(d.latitude, 8.135);
    });

    test('coerces an integer distance_km to double', () {
      final d = ExternalDelivery.fromJson({'name': 'X', 'distance_km': 3});
      expect(d.distanceKm, 3.0);
    });

    test('distanceKm is null for generic list rows without the field', () {
      final d = ExternalDelivery.fromJson({
        'name': 'EXT-DEL-1',
        'store_name': 'Store',
        'status': 'Pending',
      });
      expect(d.distanceKm, isNull);
    });
  });

  group('ExternalDeliveryDetail.fromJson distance_km', () {
    test('parses server distance_km', () {
      final d = ExternalDeliveryDetail.fromJson({
        'name': 'EXT-DEL-1',
        'store_name': 'Store',
        'store_url': '',
        'customer_name': 'C',
        'status': 'Pending',
        'distance_km': 2.4,
      });
      expect(d.distanceKm, 2.4);
    });

    test('distanceKm is null when absent', () {
      final d = ExternalDeliveryDetail.fromJson({
        'name': 'EXT-DEL-1',
        'store_name': 'Store',
        'store_url': '',
        'customer_name': 'C',
        'status': 'Pending',
      });
      expect(d.distanceKm, isNull);
    });
  });
}
