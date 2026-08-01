/// Static configuration for the Privacy & Legal module.
///
/// The full legal documents are rendered natively inside the app (see
/// `lib/features/legal/`). These URLs are the canonical web copies, which Play
/// Console requires for the store listing and which must stay in step with the
/// in-app text.
class LegalConstants {
  LegalConstants._();

  // ---------------------------------------------------------------------------
  // PLACEHOLDER DOMAIN — replace before any store submission. HTTPS only; Play
  // rejects http:// policy links.
  // ---------------------------------------------------------------------------
  static const String _host = 'https://grozfy.com';

  /// Web copies of the in-app documents.
  static const String privacyPolicyUrl = '$_host/partner/privacy-policy';
  static const String termsUrl = '$_host/partner/terms';

  /// Flip to true once the web copies are live. Until then the "view on web"
  /// affordances stay hidden rather than opening a dead link — the in-app
  /// documents are unaffected and always readable.
  static const bool webCopiesPublished = false;

  // ---------------------------------------------------------------------------
  // Document version. Recorded against the driver's acceptance so there is a
  // record of which wording they agreed to. Bump on every material change.
  // ---------------------------------------------------------------------------
  static const String documentVersion = 'v1.0';
  static const String lastUpdated = '30 July 2026';

  // ---------------------------------------------------------------------------
  // Contact channels — replace with the real published details.
  // ---------------------------------------------------------------------------
  static const String privacyEmail = 'privacy@grozfy.com';
  static const String supportEmail = 'partners@grozfy.com';
  static const String supportPhone = '+91 80 4718 2200';
  static const String supportHours = 'Mon–Sun, 7:00 AM – 11:00 PM IST';
  static const String grievanceOfficer = 'Grievance Officer, Grozfy';
  static const String officeAddress =
      'Grozfy Technologies Pvt. Ltd.\n'
      '4th Floor, Lyncspace Tower, Outer Ring Road\n'
      'Bengaluru, Karnataka 560103, India';
}
