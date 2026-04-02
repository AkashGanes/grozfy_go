class PartnerWidgetData {
  final bool isOnline;
  final double todayEarnings;
  final String? activeOrderId;
  final String? activeOrderStatus;
  final DateTime lastUpdated;

  const PartnerWidgetData({
    required this.isOnline,
    required this.todayEarnings,
    this.activeOrderId,
    this.activeOrderStatus,
    required this.lastUpdated,
  });

  Map<String, dynamic> toMap() {
    return {
      'isOnline': isOnline,
      'todayEarnings': todayEarnings,
      'activeOrderId': activeOrderId ?? '',
      'activeOrderStatus': activeOrderStatus ?? '',
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  factory PartnerWidgetData.fromMap(Map<String, dynamic> map) {
    return PartnerWidgetData(
      isOnline: map['isOnline'] ?? false,
      todayEarnings: (map['todayEarnings'] ?? 0).toDouble(),
      activeOrderId: (map['activeOrderId'] as String?)?.isEmpty == true
          ? null
          : map['activeOrderId'],
      activeOrderStatus: (map['activeOrderStatus'] as String?)?.isEmpty == true
          ? null
          : map['activeOrderStatus'],
      lastUpdated: map['lastUpdated'] != null
          ? DateTime.parse(map['lastUpdated'])
          : DateTime.now(),
    );
  }

  factory PartnerWidgetData.empty() {
    return PartnerWidgetData(
      isOnline: false,
      todayEarnings: 0,
      activeOrderId: null,
      activeOrderStatus: null,
      lastUpdated: DateTime.now(),
    );
  }

  PartnerWidgetData copyWith({
    bool? isOnline,
    double? todayEarnings,
    String? activeOrderId,
    String? activeOrderStatus,
    DateTime? lastUpdated,
  }) {
    return PartnerWidgetData(
      isOnline: isOnline ?? this.isOnline,
      todayEarnings: todayEarnings ?? this.todayEarnings,
      activeOrderId: activeOrderId ?? this.activeOrderId,
      activeOrderStatus: activeOrderStatus ?? this.activeOrderStatus,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}
