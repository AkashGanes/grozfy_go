class ApiConstants {
  ApiConstants._();

  // ---------------------------------------------------------------------------
  // Base URLs
  // ---------------------------------------------------------------------------

  static const String erpBaseUrl = 'http://209.182.232.35:8004';

  // ---------------------------------------------------------------------------
  // Auth endpoints
  // ---------------------------------------------------------------------------

  static const String sendOtp =
      '$erpBaseUrl/api/method/frappe.core.api.billing_auth_v4.send_whatsapp_otp';

  static const String verifyOtp =
      '$erpBaseUrl/api/method/frappe.core.api.billing_auth_v4.verify_whatsapp_otp';

  // ---------------------------------------------------------------------------
  // External Delivery endpoints
  // ---------------------------------------------------------------------------

  static const String externalDeliveryList =
      '$erpBaseUrl/api/resource/External%20Delivery';
  static const String externalDeliveryTripList =
      '$erpBaseUrl/api/resource/External%20Delivery%20Trip';
  static const String defaultExternalDeliveryDriver = 'HR-DRI-2026-00001';

  // Driver location ping endpoint. Backend exposes a method that accepts
  // {driver, latitude, longitude, recorded_at} and persists a Driver Location
  // Ping record. Server is responsible for de-duplicating by recorded_at so
  // retries from the offline queue are idempotent.
  static const String driverLocationPing =
      '$erpBaseUrl/api/method/grozfy.api.driver.record_location_ping';

  // Partner Timing Log Server Script endpoint (single URL, GET + POST).
  // POST: {events: [{event_uuid, driver, event_type, occurred_at, trip_ref, stop_ref}]}
  // GET:  ?driver=...&type=daily|monthly|lifetime&month=...&year=...  → {status, type, logs: [...]}
  static const String partnerTimingLog =
      '$erpBaseUrl/api/method/partner_timing_log';

  // Keep aliases so existing callers compile without change.
  static const String recordTimingEvents = partnerTimingLog;
  static const String getTimingEvents = partnerTimingLog;

  static const String issueList = '$erpBaseUrl/api/resource/Issue';
}
