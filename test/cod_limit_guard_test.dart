import 'package:flutter_test/flutter_test.dart';
import 'package:grozfy_go/features/cod_settlement/model/cod_limit_status.dart';

/// Builds a status with the given exposure, mirroring what the backend returns.
CodLimitStatus _status({
  bool enabled = true,
  double cashInHand = 4000,
  double maxLimit = 5000,
  String state = 'ok',
}) {
  return CodLimitStatus.fromJson(<String, dynamic>{
    'enabled': enabled,
    'settled_balance': cashInHand,
    'in_flight_cod': 0,
    'cash_in_hand': cashInHand,
    'max_limit': maxLimit,
    'warning_threshold_percent': 80,
    'state': state,
    'in_flight_orders': 0,
  });
}

void main() {
  group('blockReasonFor — COD orders', () {
    test('blocks when the order would push the driver past the limit', () {
      // 4000 held + 1500 order = 5500 > 5000 limit.
      final reason = _status().blockReasonFor(isCod: true, amount: 1500);

      expect(reason, isNotNull);
      // The message must name both figures — it is shown verbatim to the driver.
      expect(reason, contains('4,000'));
      expect(reason, contains('5,000'));
    });

    test('allows an order that fits inside the remaining headroom', () {
      // 4000 held + 500 order = 4500 <= 5000 limit.
      expect(_status().blockReasonFor(isCod: true, amount: 500), isNull);
    });

    test('allows landing exactly on the limit (boundary is inclusive)', () {
      // 4000 held + 1000 order = 5000, exactly the limit.
      expect(_status().blockReasonFor(isCod: true, amount: 1000), isNull);
    });

    test('blocks a zero-value order once already at the limit', () {
      // Guards the case where cod_amount_to_collect is missing: at 5000/5000 a
      // further COD order is still allowed only because it adds nothing.
      expect(
        _status(cashInHand: 5000).blockReasonFor(isCod: true, amount: 0),
        isNull,
      );
      expect(
        _status(cashInHand: 5001).blockReasonFor(isCod: true, amount: 0),
        isNotNull,
      );
    });
  });

  group('blockReasonFor — prepaid orders stay eligible', () {
    test('never blocks a prepaid order, even far over the limit', () {
      final overLimit = _status(cashInHand: 9000, state: 'blocked');

      expect(overLimit.isBlocked, isTrue);
      expect(overLimit.blockReasonFor(isCod: false, amount: 2000), isNull);
      // ...while the same amount as COD would be refused.
      expect(overLimit.blockReasonFor(isCod: true, amount: 2000), isNotNull);
    });
  });

  group('blockReasonFor — fails open', () {
    test('never blocks when the feature is disabled', () {
      final disabled = _status(enabled: false, cashInHand: 9000);
      expect(disabled.blockReasonFor(isCod: true, amount: 5000), isNull);
    });

    test('never blocks when no limit is configured', () {
      final unconfigured = _status(cashInHand: 9000, maxLimit: 0);
      expect(unconfigured.hasValidLimit, isFalse);
      expect(unconfigured.blockReasonFor(isCod: true, amount: 5000), isNull);
    });

    test('never blocks on a malformed (negative) limit', () {
      final malformed = _status(cashInHand: 100, maxLimit: -1);
      expect(malformed.blockReasonFor(isCod: true, amount: 50), isNull);
    });
  });
}
