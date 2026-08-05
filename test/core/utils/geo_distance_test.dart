import 'package:flutter_test/flutter_test.dart';
import 'package:grozfy_go/core/utils/geo_distance.dart';

void main() {
  group('isValidLatLng', () {
    test('accepts real-world coordinates', () {
      expect(isValidLatLng(8.120029142, 77.371123119), isTrue);
      expect(isValidLatLng(-33.8688, 151.2093), isTrue);
    });

    test('rejects out-of-range latitude/longitude', () {
      expect(isValidLatLng(2454.0, 245.0), isFalse);
      expect(isValidLatLng(91.0, 0.5), isFalse);
      expect(isValidLatLng(-91.0, 0.5), isFalse);
      expect(isValidLatLng(0.5, 181.0), isFalse);
      expect(isValidLatLng(0.5, -181.0), isFalse);
    });

    test('rejects the (0, 0) unset sentinel', () {
      expect(isValidLatLng(0, 0), isFalse);
    });

    test('accepts boundary values', () {
      expect(isValidLatLng(90.0, 180.0), isTrue);
      expect(isValidLatLng(-90.0, -180.0), isTrue);
    });
  });
}
