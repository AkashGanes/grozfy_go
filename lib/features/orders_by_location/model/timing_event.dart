class TimingEvent {
  const TimingEvent({
    required this.eventUuid,
    required this.partner,
    required this.eventType,
    required this.eventTime,
    this.tripRef,
    this.stopRef,
  });

  final String eventUuid;
  final String partner;
  final String eventType;
  final DateTime eventTime;
  final String? tripRef;
  final String? stopRef;

  factory TimingEvent.fromJson(Map<String, dynamic> json) {
    return TimingEvent(
      eventUuid: json['event_uuid']?.toString() ?? '',
      partner: json['driver']?.toString() ?? '',
      eventType: json['event_type']?.toString() ?? '',
      eventTime:
          DateTime.tryParse(json['occurred_at']?.toString() ?? '') ??
          DateTime.now(),
      tripRef: _nullIfBlank(json['trip_ref']?.toString()),
      stopRef: _nullIfBlank(json['stop_ref']?.toString()),
    );
  }

  static String? _nullIfBlank(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();
}
