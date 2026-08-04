/// The driver's current cash-in-hand exposure against their configured COD
/// limit, as returned by `cod_settlement.get_cod_limit_status`.
///
/// The backend owns every value here — the app never persists its own copy, so
/// a fresh fetch is always the source of truth. [state] in particular is
/// computed server-side so the app and server can never disagree about where
/// the warning/block thresholds sit.
class CodLimitStatus {
  const CodLimitStatus({
    required this.enabled,
    required this.settledBalance,
    required this.inFlightCod,
    required this.cashInHand,
    required this.maxLimit,
    required this.availableLimit,
    required this.warningThresholdPercent,
    required this.state,
    required this.inFlightOrders,
  });

  /// Whether the limit is offered to this driver. When false the UI hides the
  /// cash-in-hand surfaces entirely and acceptance is never blocked.
  final bool enabled;

  /// Unsettled cash already collected from delivered COD orders — the same
  /// quantity `get_driver_settlement_today` reports as `remaining_balance`.
  final double settledBalance;

  /// COD exposure of orders the driver has accepted but not yet delivered.
  final double inFlightCod;

  /// [settledBalance] + [inFlightCod].
  final double cashInHand;

  /// The ceiling. Non-positive means the business has not configured one.
  final double maxLimit;

  /// Remaining headroom, floored at zero by the backend.
  final double availableLimit;

  /// Percentage of [maxLimit] at which the driver is warned (default 80).
  final double warningThresholdPercent;

  /// `ok` | `warning` | `blocked` — computed server-side.
  final String state;

  /// Count of accepted-but-undelivered COD orders, for the card subtitle.
  final int inFlightOrders;

  static const String stateOk = 'ok';
  static const String stateWarning = 'warning';
  static const String stateBlocked = 'blocked';

  bool get isBlocked => state == stateBlocked;
  bool get isWarning => state == stateWarning;

  /// True when the limit is usable for display/enforcement. Guards against a
  /// malformed or half-configured backend response.
  bool get hasValidLimit => enabled && maxLimit > 0;

  /// Fraction of the limit consumed, clamped to 0..1 for progress indicators.
  double get usedFraction =>
      maxLimit <= 0 ? 0 : (cashInHand / maxLimit).clamp(0.0, 1.0);

  /// The single decision point for whether a driver may take on an order.
  ///
  /// Returns null when the order is allowed, or a driver-facing reason when it
  /// is not. Kept pure (no I/O, no framework types) so the business rule is
  /// unit-testable without standing up [AppController].
  ///
  /// Prepaid/online orders are always allowed — carrying cash must not stop the
  /// driver earning on work that collects none. This mirrors the server rule in
  /// `docs/backend-specs/cod_cash_limit.md`; the server remains authoritative.
  String? blockReasonFor({required bool isCod, required double amount}) {
    if (!isCod) return null;
    if (!hasValidLimit) return null;

    // Boundary is inclusive: landing exactly on the limit is allowed.
    if (cashInHand + amount <= maxLimit) return null;

    return 'Cash limit reached. You are holding ${_money(cashInHand)} of your '
        '${_money(maxLimit)} limit. Settle cash to accept more COD orders.';
  }

  factory CodLimitStatus.fromJson(Map<String, dynamic> json) {
    final double maxLimit = _asDouble(json['max_limit']) ?? 0;
    final double cashInHand = _asDouble(json['cash_in_hand']) ?? 0;
    return CodLimitStatus(
      enabled: _asBool(json['enabled'] ?? json['cod_limit_enabled']),
      settledBalance: _asDouble(json['settled_balance']) ?? 0,
      inFlightCod: _asDouble(json['in_flight_cod']) ?? 0,
      cashInHand: cashInHand,
      maxLimit: maxLimit,
      // Recompute when absent so the UI never shows a blank headroom; floored
      // at zero to match the backend contract (never negative).
      availableLimit: _asDouble(json['available_limit']) ??
          (maxLimit - cashInHand).clamp(0.0, double.infinity),
      warningThresholdPercent:
          _asDouble(json['warning_threshold_percent']) ?? 80,
      state: json['state']?.toString().trim().toLowerCase() ?? stateOk,
      inFlightOrders: _asDouble(json['in_flight_orders'])?.round() ?? 0,
    );
  }

  /// Formats an amount the way the settlement screen does: `₹1,234` / `₹1,234.50`.
  static String _money(double amount) => '₹${formatAmount(amount)}';

  /// Rupee amount formatting, shared with the settlement screens (which delegate
  /// here) so the app never shows the same figure two different ways. Drops a
  /// whole-number decimal tail and groups digits Indian-style.
  static String formatAmount(double amount) {
    if (amount == amount.truncateToDouble()) {
      return _addCommas(amount.toStringAsFixed(0));
    }
    return _addCommas(amount.toStringAsFixed(2));
  }

  static String _addCommas(String s) {
    final parts = s.split('.');
    final intPart = parts[0];
    final buffer = StringBuffer();
    int count = 0;
    for (int i = intPart.length - 1; i >= 0; i--) {
      if (count > 0 && count == 3) {
        buffer.write(',');
        count = 0;
      } else if (count > 0 && (count - 3) % 2 == 0 && count > 3) {
        buffer.write(',');
      }
      buffer.write(intPart[i]);
      count++;
    }
    final result = buffer.toString().split('').reversed.join();
    return parts.length > 1 ? '$result.${parts[1]}' : result;
  }

  static bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase();
    return text == '1' || text == 'true' || text == 'yes';
  }

  static double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
