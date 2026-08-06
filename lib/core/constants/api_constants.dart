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

  // POST: {external_delivery, otp} → verifies the customer-provided delivery
  // OTP and, on success, transitions the order to Delivered server-side.
  // Response: {success: true, external_delivery: "..."} or
  // {success: true, already_delivered: true, ...}. On failure the server
  // returns one of: "Invalid OTP", "OTP already verified",
  // "Order is not Out for Delivery", "Delivery partner is not assigned to
  // this order" — surfaced as-is via _extractErrorMessage.
  static const String verifyDeliveryOtp =
      '$erpBaseUrl/api/method/grozfy_go.grozfy_go.api.driver.verify_delivery_otp';

  // POST: {pickup_job, otp} → verifies the customer-provided return OTP and,
  // on success, transitions the Pickup Job to Picked Up server-side.
  // Response: {success: true, pickup_job: "..."} or
  // {success: true, already_picked_up: true, ...}. On failure the server
  // returns one of: "Invalid OTP", "OTP already verified",
  // "Pickup is not Scheduled", "Delivery partner is not assigned to this
  // return" — surfaced as-is via _extractErrorMessage.
  static const String verifyReturnOtp =
      '$erpBaseUrl/api/method/grozfy_go.grozfy_go.api.driver.verify_return_otp';

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

  // ---------------------------------------------------------------------------
  // COD Settlement endpoints
  // ---------------------------------------------------------------------------

  static const String driverSettlementToday =
      '$erpBaseUrl/api/method/grozfy_go.grozfy_go.api.cod_settlement.get_driver_settlement_today';

  static const String submitBankTransfer =
      '$erpBaseUrl/api/method/grozfy_go.grozfy_go.api.cod_settlement.submit_bank_transfer';

  // ---------------------------------------------------------------------------
  // Delivery Radius endpoints
  // ---------------------------------------------------------------------------

  // GET: returns {delivery_radius_enabled, minimum_radius_km, default_radius_km,
  // maximum_radius_km, selected_radius_km} for the logged-in driver.
  static const String getDeliveryRadiusSettings =
      '$erpBaseUrl/api/method/grozfy_go.grozfy_go.api.delivery_radius.get_delivery_radius';

  // POST: {selected_radius_km} → persists the driver's chosen radius.
  static const String updateDeliveryRadius =
      '$erpBaseUrl/api/method/grozfy_go.grozfy_go.api.delivery_radius.update_delivery_radius';

  // Radius-aware "Available Orders" feed. Server filters Pending deliveries by
  // the driver's selected delivery radius and returns the full set in one call,
  // each row carrying a server-computed `distance_km`. Replaces the generic
  // `/api/resource/External Delivery` list (which is radius-blind) for that
  // screen only.
  static const String listAvailableDeliveries =
      '$erpBaseUrl/api/method/grozfy_go.grozfy_go.api.delivery_radius.list_available_deliveries';

  // ---------------------------------------------------------------------------
  // Vehicle endpoints
  // ---------------------------------------------------------------------------

  // GET → {message: {fuel_type_options: [...], required_fields: [...]}}.
  // Driver-accessible source for the KYC vehicle form config; replaces the
  // Desk-only `/api/resource/DocType/Vehicle` meta read that returned
  // AuthenticationError for non-desk partner drivers.
  static const String vehicleFormOptions =
      '$erpBaseUrl/api/method/grozfy_go.grozfy_go.api.vehicle.vehicle_form_options';

  // POST: {driver, license_plate, make, model, ...} → upserts the driver's
  // Vehicle with elevated permissions and returns the full saved doc under
  // `message`. Driver-callable replacement for the `/api/resource/Vehicle`
  // POST/PUT that returned AuthenticationError for non-desk partner drivers.
  static const String saveVehicle =
      '$erpBaseUrl/api/method/grozfy_go.grozfy_go.api.vehicle.save_vehicle';

  // ---------------------------------------------------------------------------
  // Bank Account endpoints
  // ---------------------------------------------------------------------------

  // GET → {message: {account_type_options: [...], required_fields: [...]}}.
  // Driver-accessible source for the KYC bank form; replaces the Desk-only
  // `/api/resource/DocType/Bank Account` meta read used to populate the
  // Account Type picker.
  static const String bankFormOptions =
      '$erpBaseUrl/api/method/grozfy_go.grozfy_go.api.bank.bank_form_options';

  // POST: {driver, account_name, bank, ...} → upserts the driver's Bank Account
  // with elevated permissions (stamps party_type='Driver'/party server-side) and
  // returns the full saved doc under `message`. Driver-callable replacement for
  // the `/api/resource/Bank Account` POST/PUT that returned AuthenticationError.
  static const String saveBankAccount =
      '$erpBaseUrl/api/method/grozfy_go.grozfy_go.api.bank.save_bank_account';

  // ---------------------------------------------------------------------------
  // Account deletion endpoints
  //
  // Spec: docs/backend-specs/request_account_deletion.md. All three are
  // session-authenticated and resolve the Driver from the session user — a
  // `driver` that isn't the caller's is a 403, so none of these may be called
  // on behalf of anyone else.
  // ---------------------------------------------------------------------------

  // POST: {confirmed: 1, app_version?, reason?} → creates the request and
  // returns {status: success|blocked|already_requested, request_name,
  // request_status, scheduled_deletion_on, cancellable_until, blockers[]}.
  // `blocked` is a 200, not an error: it means settlement is outstanding and
  // carries display-ready messages saying what to clear.
  static const String requestAccountDeletion =
      '$erpBaseUrl/api/method/grozfy_go.grozfy_go.api.account.request_account_deletion';

  // GET → {status: "none"} or the same object as above for a live request.
  static const String accountDeletionStatus =
      '$erpBaseUrl/api/method/grozfy_go.grozfy_go.api.account.get_account_deletion_status';

  // POST: {request_name} → {status: "cancelled"}. 409 once the grace period
  // has passed or the request is already terminal.
  static const String cancelAccountDeletion =
      '$erpBaseUrl/api/method/grozfy_go.grozfy_go.api.account.cancel_account_deletion';

  // ---------------------------------------------------------------------------
  // SOS / Emergency Assistance endpoints
  //
  // Both are session-authenticated and resolve the driver from the session user
  // — neither takes a `driver` argument, so neither can be called on behalf of
  // anyone else. The backend auto-attaches active trip/order context.
  // ---------------------------------------------------------------------------

  // POST: {lat, lng, message?} → {success, sos_alert, driver_resolved_via,
  // delivery_trip, external_delivery}. Only a missing/invalid lat or lng can
  // fail this call — driver-identity and trip-lookup problems never do.
  //
  // NOTE: there is no `alert_uuid` and no server-side dedupe, so *every* call
  // creates a row. Never retry automatically (see SosRepository).
  static const String triggerSos =
      '$erpBaseUrl/api/method/grozfy_go.grozfy_go.api.sos.trigger_sos';

  // Operations number dialled by the "Call operations" fallback when an alert
  // could not be confirmed by the server. While this is empty the UI *hides*
  // the call action rather than dialling nothing.
  //
  // TODO: set a real, monitored operations number before release. Push
  // notifications to ops are a dead channel today (no Delivery Manager has an
  // FCM token registered), which makes this the most reliable path to a human.
  static const String sosFallbackOpsPhone = '';
}
