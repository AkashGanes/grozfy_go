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
      '$erpBaseUrl/api/resource/External Delivery';
  static const String externalDeliveryTripList =
      '$erpBaseUrl/api/resource/External Delivery Trip';
  static const String frappeSubmitMethod =
      '$erpBaseUrl/api/method/frappe.client.submit';
  static const String defaultExternalDeliveryDriver = 'HR-DRI-2026-00001';

  // ---------------------------------------------------------------------------
  // API credentials
  // ---------------------------------------------------------------------------

  static const String apiKey = 'fcce513c95f7a5c';
  static const String apiSecret = 'c46e6e790a765ee';
}
