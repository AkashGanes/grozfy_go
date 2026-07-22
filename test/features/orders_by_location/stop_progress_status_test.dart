import 'package:flutter_test/flutter_test.dart';
import 'package:grozfy_go/features/orders_by_location/model/external_delivery.dart';
import 'package:grozfy_go/features/orders_by_location/model/stop_progress_status.dart';

ExternalDeliveryTripStop _deliveryStop(String status) {
  return ExternalDeliveryTripStop(
    stop: 1,
    externalDelivery: 'ED-1',
    customer: 'Customer',
    address: 'Address',
    mobile: '0000000000',
    status: status,
    deliveredAt: '',
    notes: '',
    rawFields: const {},
  );
}

PickupTripStop _pickupStop(String status) {
  return PickupTripStop(
    stop: 1,
    pickupJob: 'PJ-1',
    customerName: 'Customer',
    customerMobile: '0000000000',
    pickupAddress: 'Address',
    status: status,
  );
}

void main() {
  group('isTerminalStop', () {
    test('recognizes all terminal statuses case/whitespace-insensitively', () {
      for (final status in [
        'Delivered',
        '  returned ',
        'FAILED',
        'Cancelled',
        'Received At Store',
      ]) {
        expect(isTerminalStop(_deliveryStop(status)), isTrue, reason: status);
      }
    });

    test('treats Pending/Out for Delivery as non-terminal', () {
      expect(isTerminalStop(_deliveryStop('Pending')), isFalse);
      expect(isTerminalStop(_deliveryStop('Out for Delivery')), isFalse);
      expect(isTerminalStop(_pickupStop('Picked Up')), isFalse);
    });
  });

  group('deriveStopProgress', () {
    test('maps terminal statuses regardless of isActive', () {
      expect(
        deriveStopProgress(_deliveryStop('Delivered'), isActive: true),
        StopProgressStatus.delivered,
      );
      expect(
        deriveStopProgress(_deliveryStop('Failed'), isActive: false),
        StopProgressStatus.failed,
      );
      expect(
        deriveStopProgress(_pickupStop('Received at Store'), isActive: true),
        StopProgressStatus.receivedAtStore,
      );
    });

    test('non-terminal stop is active only when isActive is true', () {
      expect(
        deriveStopProgress(_deliveryStop('Pending'), isActive: true),
        StopProgressStatus.active,
      );
      expect(
        deriveStopProgress(_deliveryStop('Pending'), isActive: false),
        StopProgressStatus.pending,
      );
    });

    test('only one stop can be active in a derived set — by construction',
        () {
      final stops = [
        _deliveryStop('Pending'),
        _deliveryStop('Pending'),
        _deliveryStop('Pending'),
      ];
      // Simulates the controller's real usage: isActive is true only for
      // the stop that is first in display order.
      final statuses = [
        for (int i = 0; i < stops.length; i++)
          deriveStopProgress(stops[i], isActive: i == 0),
      ];
      expect(
        statuses.where((s) => s == StopProgressStatus.active).length,
        1,
      );
    });
  });
}
