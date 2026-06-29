class CodHandover {
  const CodHandover({
    required this.name,
    required this.deliveryTrip,
    required this.codCashExpected,
    required this.codCashActual,
    required this.status,
    this.notes = '',
  });

  final String name;
  final String deliveryTrip;
  final double codCashExpected;
  final double codCashActual;
  final String status; // Pending | Submitted | Discrepancy
  final String notes;

  bool get needsCollection =>
      codCashExpected > 0 && status.toLowerCase() == 'pending';

  factory CodHandover.fromJson(Map<String, dynamic> m) {
    double toDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    return CodHandover(
      name: (m['name'] ?? '').toString(),
      deliveryTrip: (m['delivery_trip'] ?? '').toString(),
      codCashExpected: toDouble(m['cod_cash_expected']),
      codCashActual: toDouble(m['cod_cash_actual']),
      status: (m['status'] ?? 'Pending').toString(),
      notes: (m['notes'] ?? '').toString(),
    );
  }
}
