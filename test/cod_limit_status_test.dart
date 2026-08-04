import 'package:flutter_test/flutter_test.dart';
import 'package:grozfy_go/features/cod_settlement/model/cod_limit_status.dart';

/// A fully-populated backend payload, matching
/// docs/backend-specs/cod_cash_limit.md.
Map<String, dynamic> _payload({
  Object? enabled = true,
  num settled = 3000,
  num inFlight = 1200,
  num cashInHand = 4200,
  num maxLimit = 5000,
  num? available = 800,
  String state = 'warning',
}) {
  return <String, dynamic>{
    'enabled': enabled,
    'settled_balance': settled,
    'in_flight_cod': inFlight,
    'cash_in_hand': cashInHand,
    'max_limit': maxLimit,
    'available_limit': ?available,
    'warning_threshold_percent': 80,
    'state': state,
    'in_flight_orders': 2,
    'currency': 'INR',
  };
}

void main() {
  group('CodLimitStatus.fromJson', () {
    test('parses every field from the documented payload', () {
      final s = CodLimitStatus.fromJson(_payload());

      expect(s.enabled, isTrue);
      expect(s.settledBalance, 3000);
      expect(s.inFlightCod, 1200);
      expect(s.cashInHand, 4200);
      expect(s.maxLimit, 5000);
      expect(s.availableLimit, 800);
      expect(s.warningThresholdPercent, 80);
      expect(s.state, CodLimitStatus.stateWarning);
      expect(s.inFlightOrders, 2);
      expect(s.isWarning, isTrue);
      expect(s.isBlocked, isFalse);
      expect(s.hasValidLimit, isTrue);
    });

    test('accepts the truthy encodings Frappe uses for checkboxes', () {
      for (final raw in <Object>[true, 1, '1', 'true', 'yes']) {
        expect(
          CodLimitStatus.fromJson(_payload(enabled: raw)).enabled,
          isTrue,
          reason: 'expected $raw to parse as enabled',
        );
      }
      for (final raw in <Object>[false, 0, '0', 'no']) {
        expect(
          CodLimitStatus.fromJson(_payload(enabled: raw)).enabled,
          isFalse,
          reason: 'expected $raw to parse as disabled',
        );
      }
    });

    test('defaults every amount to zero when keys are missing', () {
      final s = CodLimitStatus.fromJson(<String, dynamic>{});

      expect(s.enabled, isFalse);
      expect(s.settledBalance, 0);
      expect(s.inFlightCod, 0);
      expect(s.cashInHand, 0);
      expect(s.maxLimit, 0);
      expect(s.availableLimit, 0);
      expect(s.warningThresholdPercent, 80);
      expect(s.state, CodLimitStatus.stateOk);
      expect(s.hasValidLimit, isFalse);
    });

    test('recomputes available_limit when the backend omits it', () {
      final s = CodLimitStatus.fromJson(
        _payload(cashInHand: 1500, maxLimit: 5000, available: null),
      );
      expect(s.availableLimit, 3500);
    });

    test('never reports negative headroom when already over the limit', () {
      final s = CodLimitStatus.fromJson(
        _payload(cashInHand: 6000, maxLimit: 5000, available: null),
      );
      expect(s.availableLimit, 0);
    });

    test('normalises state casing', () {
      expect(
        CodLimitStatus.fromJson(_payload(state: 'BLOCKED')).isBlocked,
        isTrue,
      );
    });
  });

  group('CodLimitStatus.usedFraction', () {
    test('is the consumed share of the limit', () {
      final s = CodLimitStatus.fromJson(
        _payload(cashInHand: 2500, maxLimit: 5000),
      );
      expect(s.usedFraction, 0.5);
    });

    test('clamps to 1 when over the limit', () {
      final s = CodLimitStatus.fromJson(
        _payload(cashInHand: 9000, maxLimit: 5000),
      );
      expect(s.usedFraction, 1.0);
    });

    test('is zero (not NaN/Infinity) when no limit is configured', () {
      final s = CodLimitStatus.fromJson(
        _payload(cashInHand: 400, maxLimit: 0),
      );
      expect(s.usedFraction, 0);
    });
  });

  group('CodLimitStatus.formatAmount', () {
    test('drops a whole-number decimal tail', () {
      expect(CodLimitStatus.formatAmount(5000), '5,000');
    });

    test('keeps paise when present', () {
      expect(CodLimitStatus.formatAmount(1234.50), '1,234.50');
    });
  });
}
