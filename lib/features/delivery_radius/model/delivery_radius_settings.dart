/// Business-defined delivery-radius policy plus the driver's own selection,
/// as returned by `get_delivery_radius_settings`.
///
/// The backend owns every value here — the app never persists its own copy, so
/// a fresh fetch is always the source of truth (no stale values after
/// logout/login).
class DeliveryRadiusSettings {
  const DeliveryRadiusSettings({
    required this.enabled,
    required this.minimumRadiusKm,
    required this.defaultRadiusKm,
    required this.maximumRadiusKm,
    this.selectedRadiusKm,
  });

  /// Whether the feature is offered to this driver. When false the UI hides the
  /// section entirely.
  final bool enabled;

  /// Smallest selectable radius (slider minimum).
  final double minimumRadiusKm;

  /// Business default, used as the slider value when the driver has not chosen
  /// one yet ([selectedRadiusKm] is null).
  final double defaultRadiusKm;

  /// Largest selectable radius (slider maximum).
  final double maximumRadiusKm;

  /// The driver's saved selection, or null when they have never set one.
  final double? selectedRadiusKm;

  /// The value the slider should show: the driver's selection when present,
  /// otherwise the business default.
  double get effectiveRadiusKm => selectedRadiusKm ?? defaultRadiusKm;

  factory DeliveryRadiusSettings.fromJson(Map<String, dynamic> json) {
    // The deployed backend returns short keys: enabled, minimum_km, maximum_km,
    // default_km, selected_km. The longer *_radius_km fallbacks keep parsing
    // resilient if the contract ever shifts back.
    final double? selectedRaw = _asDouble(
      json['selected_km'] ?? json['selected_radius_km'],
    );
    return DeliveryRadiusSettings(
      enabled: _asBool(json['enabled'] ?? json['delivery_radius_enabled']),
      minimumRadiusKm:
          _asDouble(json['minimum_km'] ?? json['minimum_radius_km']) ?? 0,
      defaultRadiusKm:
          _asDouble(json['default_km'] ?? json['default_radius_km']) ?? 0,
      maximumRadiusKm:
          _asDouble(json['maximum_km'] ?? json['maximum_radius_km']) ?? 0,
      // The backend uses 0 (not null) to mean "no selection yet"; treat any
      // non-positive value as unselected so the slider falls back to default.
      selectedRadiusKm: (selectedRaw != null && selectedRaw > 0)
          ? selectedRaw
          : null,
    );
  }

  /// Returns a copy with a different [selectedRadiusKm]. Accepts null so the UI
  /// can restore a previously-unset selection when a save fails.
  DeliveryRadiusSettings withSelected(double? value) {
    return DeliveryRadiusSettings(
      enabled: enabled,
      minimumRadiusKm: minimumRadiusKm,
      defaultRadiusKm: defaultRadiusKm,
      maximumRadiusKm: maximumRadiusKm,
      selectedRadiusKm: value,
    );
  }

  /// True when the bounds are usable for a slider (min < max). Guards against a
  /// malformed backend response.
  bool get hasValidBounds => maximumRadiusKm > minimumRadiusKm;

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
