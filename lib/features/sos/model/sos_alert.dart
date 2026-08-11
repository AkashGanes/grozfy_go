/// Models for the SOS / Emergency Assistance feature.
///
/// Mirrors the deployed `SOS Alert` contract
/// (`grozfy_go.grozfy_go.api.sos.trigger_sos`).
library;

/// Emergency reasons offered to the driver.
///
/// NOTE: the backend `SOS Alert` DocType has **no reason field** — `message`
/// (Small Text, max 500, server-trimmed) is the only free-form field. Reasons
/// are therefore encoded into `message` by [encodeSosMessage] so they stay
/// readable in the ops email and the Desk list view. If the backend later
/// gains a real `reasons` field, send it there instead and drop the prefix —
/// ops cannot filter or report on free text.
enum SosReason {
  accident('Accident'),
  unsafe('Unsafe situation'),
  breakdown('Vehicle breakdown'),
  medical('Medical emergency'),
  other('Other');

  const SosReason(this.label);

  final String label;
}

/// Server-enforced cap on `message` (Small Text). Trimmed server-side too, but
/// truncating here keeps the driver's own note from being silently cut.
const int kSosMessageMaxLength = 500;

/// Packs the selected [reasons] and the driver's optional [note] into the
/// single `message` field the backend accepts.
///
/// Produces e.g.:
/// ```
/// Reasons: Accident, Unsafe situation
/// Note: hit from behind at the junction
/// ```
/// The reasons line is never truncated — it is the part ops triage on; only
/// the note is trimmed to fit [kSosMessageMaxLength].
String encodeSosMessage({required Set<SosReason> reasons, String? note}) {
  final ordered = SosReason.values.where(reasons.contains).toList();
  final buffer = StringBuffer();
  if (ordered.isNotEmpty) {
    buffer.write('Reasons: ${ordered.map((r) => r.label).join(', ')}');
  }

  final trimmedNote = note?.trim() ?? '';
  if (trimmedNote.isNotEmpty) {
    if (buffer.isNotEmpty) buffer.write('\n');
    final remaining = kSosMessageMaxLength - buffer.length - 'Note: '.length;
    buffer.write(
      'Note: ${remaining > 0 && trimmedNote.length > remaining ? trimmedNote.substring(0, remaining) : trimmedNote}',
    );
  }

  final result = buffer.toString();
  return result.length > kSosMessageMaxLength
      ? result.substring(0, kSosMessageMaxLength)
      : result;
}

/// How the backend resolved the driver behind the session user.
///
/// 68% of Driver records have no `user_id`, so `trigger_sos` falls back to a
/// phone match and, failing that, files the alert against the session user
/// alone with `driver` left blank. [unresolved] therefore means "ops received
/// an alert they may not be able to tie to a driver record" — the UI surfaces
/// it rather than showing an unqualified success.
enum SosDriverResolution {
  userId,
  phoneFallback,
  unresolved;

  static SosDriverResolution fromJson(Object? value) {
    switch (value?.toString()) {
      case 'user_id':
        return SosDriverResolution.userId;
      case 'phone_fallback':
        return SosDriverResolution.phoneFallback;
      default:
        return SosDriverResolution.unresolved;
    }
  }

  bool get isResolved => this != SosDriverResolution.unresolved;
}

/// Confirmed outcome of a [trigger_sos] call.
///
/// Only constructed when the server returned `success: true` *and* a non-empty
/// `sos_alert` docname — see `SosRepository.triggerSos`.
class SosTriggerResult {
  const SosTriggerResult({
    required this.alertName,
    required this.driverResolution,
    this.deliveryTrip,
    this.externalDelivery,
  });

  final String alertName;
  final SosDriverResolution driverResolution;

  /// Trip/order context the backend auto-attached, if the driver had an active
  /// one. Null is normal (driver on duty but not on a trip), not an error.
  final String? deliveryTrip;
  final String? externalDelivery;
}
