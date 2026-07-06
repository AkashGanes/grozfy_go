class SettlementOrder {
  const SettlementOrder({
    required this.salesOrder,
    required this.deliveryNote,
    required this.amountCollected,
    required this.collectionMode,
    required this.upiReference,
    required this.deliveredAt,
  });

  final String salesOrder;
  final String deliveryNote;
  final double amountCollected;
  final String collectionMode;
  final String upiReference;
  final String deliveredAt;

  factory SettlementOrder.fromJson(Map<String, dynamic> json) {
    return SettlementOrder(
      salesOrder: json['sales_order']?.toString() ?? '',
      deliveryNote: json['delivery_note']?.toString() ?? '',
      amountCollected: (json['amount_collected'] as num?)?.toDouble() ?? 0.0,
      collectionMode: json['collection_mode']?.toString() ?? '',
      upiReference: json['upi_reference']?.toString() ?? '',
      deliveredAt: json['delivered_at']?.toString() ?? '',
    );
  }
}

class DailyDriverSettlement {
  const DailyDriverSettlement({
    required this.exists,
    this.settlementName,
    this.settlementDate,
    this.status,
    this.carriedForwardBalance = 0.0,
    this.totalCollectedToday = 0.0,
    this.totalOwed = 0.0,
    this.amountTransferred,
    this.bankTransferReference,
    this.remainingBalance = 0.0,
    this.carryForwardToTomorrow = 0.0,
    this.settlementOrders = const [],
  });

  final bool exists;
  final String? settlementName;
  final String? settlementDate;
  final String? status;
  final double carriedForwardBalance;
  final double totalCollectedToday;
  final double totalOwed;
  final double? amountTransferred;
  final String? bankTransferReference;
  final double remainingBalance;
  final double carryForwardToTomorrow;
  final List<SettlementOrder> settlementOrders;

  factory DailyDriverSettlement.fromJson(Map<String, dynamic> json) {
    final ordersRaw = json['settlement_orders'];
    final orders = ordersRaw is List
        ? ordersRaw
            .whereType<Map<String, dynamic>>()
            .map(SettlementOrder.fromJson)
            .toList()
        : <SettlementOrder>[];

    return DailyDriverSettlement(
      exists: json['exists'] == true,
      settlementName: json['settlement_name']?.toString(),
      settlementDate: json['settlement_date']?.toString(),
      status: json['status']?.toString(),
      carriedForwardBalance:
          (json['carried_forward_balance'] as num?)?.toDouble() ?? 0.0,
      totalCollectedToday:
          (json['total_collected_today'] as num?)?.toDouble() ?? 0.0,
      totalOwed: (json['total_owed'] as num?)?.toDouble() ?? 0.0,
      amountTransferred:
          json['amount_transferred'] != null
              ? (json['amount_transferred'] as num).toDouble()
              : null,
      bankTransferReference: json['bank_transfer_reference']?.toString(),
      remainingBalance:
          (json['remaining_balance'] as num?)?.toDouble() ?? 0.0,
      carryForwardToTomorrow:
          (json['carry_forward_to_tomorrow'] as num?)?.toDouble() ?? 0.0,
      settlementOrders: orders,
    );
  }
}
