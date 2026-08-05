import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/legal_constants.dart';
import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/theme/context_colors.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/app_toast.dart';
import '../dashboard/widgets/dashboard_colors.dart';
import 'legal_content.dart';
import 'legal_design.dart';

/// ---------------------------------------------------------------------------
/// Every screen in the Privacy & Legal module.
///
/// Kept in one file on purpose. Five of these were under 180 lines and three
/// under 35, and split across seven files the module read as far larger than it
/// is. The copy lives in `legal_content.dart` and the shared widgets in
/// `legal_design.dart`; what remains here is only layout.
///
///   1. [TermsPrivacyScreen]    — summary, and the consent gate
///   2. [PrivacyPolicyScreen]   — the full policy
///   3. [DataCollectionScreen]  — every field we hold
///   4. [TermsConditionsScreen] — the full terms
///   5. [DataPermissionsScreen] — why each permission is asked for
///   6. [ContactSupportScreen]  — channels and the Grievance Officer
///   7. [DeleteAccountScreen]   — exercising the right to erasure
/// ---------------------------------------------------------------------------

/// What the consent gate returns when a partner accepts.
///
/// The gate used to pop a bare `true`, which told the caller *that* consent was
/// given but not *what* was consented to. The backend records a Delivery
/// Partner Consent row per acceptance, so it needs the version and the set of
/// documents — and those must come from the screen the partner actually read,
/// not be re-derived later by whoever happens to submit the registration.
///
/// Deliberately carries no timestamp: the backend stamps `accepted_on` and the
/// request IP server-side. A client clock can be wrong or deliberately altered,
/// and a consent record that cannot be defended is not worth storing.
class LegalConsentResult {
  const LegalConsentResult({
    required this.version,
    required this.documents,
    this.source = 'Registration',
  });

  /// The document version shown to the partner — `LegalConstants.documentVersion`.
  final String version;

  /// Comma-separated document keys accepted together, e.g.
  /// `privacy_policy,terms`. The gate presents both as a single agreement, so
  /// they are always recorded together.
  final String documents;

  /// Where the acceptance was taken. `Registration` today; a re-consent gate
  /// for existing partners would pass its own value.
  final String source;
}

/// The five things a delivery partner is actually agreeing to.
///
/// This exists because pointing a driver at two documents and asking them to
/// tick a box is a disclosure that satisfies nobody — they do not read it, and
/// an unread policy is not informed consent whatever the checkbox says. Five
/// lines they will actually read do more real work than 23 sections they will
/// not.
///
/// Every point compresses something already stated in [kDataGroups] and
/// [kPermissions] — nothing is disclosed here that is not in the full policy,
/// and nothing there is contradicted here. **If those lists change, change
/// these lines too.** A summary that has drifted from the document it
/// summarises is worse than no summary.
const List<({IconData icon, String title, String detail})> _highlights = [
  (
    icon: Icons.my_location_rounded,
    title: 'We use your location',
    detail: 'From when you accept a delivery until you have none active — with '
        'a notification visible the whole time. Never when you are offline.',
  ),
  (
    icon: Icons.badge_outlined,
    title: 'We verify your documents',
    detail: 'Aadhaar, PAN and driving licence confirm you are eligible to '
        'deliver. Seen by verification staff only.',
  ),
  (
    icon: Icons.account_balance_wallet_outlined,
    title: 'We pay you directly',
    detail: 'Bank and UPI details are used to pay your earnings and settle cash '
        'collections. Nothing else.',
  ),
  (
    icon: Icons.shield_outlined,
    title: 'We never sell your data',
    detail: 'Not to advertisers, not for marketing. Customers see only your '
        'first name, photo and vehicle type.',
  ),
  (
    icon: Icons.tune_rounded,
    title: 'You stay in control',
    detail: 'Withdraw consent, revoke any permission in device settings, or ask '
        'us to delete your data at any time.',
  ),
];

/// Screen 1 — Terms & Privacy.
///
/// States what the partner is agreeing to in five plain lines rather than
/// listing documents to open. A driver standing between sign-up and their first
/// delivery does not read a 23-section policy, so a screen built around links
/// to one is a disclosure that only looks thorough. The full documents stay one
/// tap away for anyone who wants them.
///
/// Serves two jobs from one implementation, because the summary is identical
/// and only what follows it differs:
///
///  * [requireConsent] `true` — the onboarding gate. Adds the checkbox and
///    Continue button, and pops a [LegalConsentResult] once accepted. Any other
///    exit — back button, swipe, system back — pops null, and the caller must
///    not register.
///  * [requireConsent] `false` — the reference entry reached from More →
///    Terms & Privacy. No commitment, plus the related pages that lead only
///    from here.
class TermsPrivacyScreen extends StatefulWidget {
  const TermsPrivacyScreen({super.key, this.requireConsent = false});

  final bool requireConsent;

  @override
  State<TermsPrivacyScreen> createState() => _TermsPrivacyScreenState();
}

class _TermsPrivacyScreenState extends State<TermsPrivacyScreen> {
  bool _accepted = false;

  void _go(String route) => Navigator.of(context).pushNamed(route);

  @override
  Widget build(BuildContext context) {
    final bool gate = widget.requireConsent;

    return AppShell(
      title: 'Terms & Privacy',
      subtitle:
          gate ? "Here's what you're agreeing to" : 'How we handle your data',
      footer: gate ? _consentFooter() : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LegalIntro(
            gate
                ? 'The short version of how we handle your information as a '
                      'delivery partner. Every point comes from our full '
                      'Privacy Policy.'
                : 'The short version of how we collect, use and protect your '
                      'information, and what you agreed to as a delivery '
                      'partner.',
          ),
          for (int i = 0; i < _highlights.length; i++)
            _Highlight(_highlights[i]).legalEntrance(i),
          const SizedBox(height: 4),
          Divider(height: 1, color: context.borderSubtle),
          const SizedBox(height: 8),
          // The full text has to stay reachable before acceptance — a summary
          // is the honest way to present it, not a replacement for it.
          _Link('Read the full Privacy Policy',
              () => _go(AppRoutes.legalPrivacy)),
          _Link('Read the full Terms & Conditions',
              () => _go(AppRoutes.legalTerms)),
          // Reachable only from here — the More menu deliberately does not
          // duplicate them — so losing these links would orphan both screens.
          if (!gate) ...[
            _Link('Data & Permissions', () => _go(AppRoutes.legalPermissions)),
            _Link('Contact & Support', () => _go(AppRoutes.legalContact)),
          ],
          const SizedBox(height: 22),
          // The version is what the consent record names, so it belongs on the
          // screen where the agreement is given.
          const LegalDocumentFooter(
            version: LegalConstants.documentVersion,
            lastUpdated: LegalConstants.lastUpdated,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _consentFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: context.cardColor,
        border: Border(top: BorderSide(color: context.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => setState(() => _accepted = !_accepted),
              borderRadius: BorderRadius.circular(LegalTokens.innerRadius),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _accepted,
                    onChanged: (value) =>
                        setState(() => _accepted = value ?? false),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        'I have read and agree to the Terms & Conditions and '
                        'Privacy Policy.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                          color: context.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            LegalPrimaryButton(
              label: 'Continue',
              // Returns the version actually rendered on this screen, so the
              // consent record names the wording the partner was shown rather
              // than whatever the constant happens to be when the request is
              // built.
              onPressed: _accepted
                  ? () => Navigator.of(context).pop(
                        const LegalConsentResult(
                          version: LegalConstants.documentVersion,
                          documents: 'privacy_policy,terms',
                        ),
                      )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Screen 2 — Privacy Policy. Thirteen expandable sections over the shared
/// document shell, with a link through to the collected-data detail page.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _DocumentPage(
      title: 'Privacy Policy',
      intro:
          'Written for delivery partners. Every section below reflects what the '
          'app actually does — tap a heading to read it in full.',
      sections: kPrivacySections,
      leadingGroup: LegalGroup(
        children: [
          LegalNavRow(
            icon: Icons.inventory_2_outlined,
            label: 'View collected data',
            meta: '6 categories',
            onTap: () =>
                Navigator.of(context).pushNamed(AppRoutes.legalDataDetail),
          ),
        ],
      ),
      // The section that explains deletion is also where a partner decides to
      // go through with it, so the way there sits at the end of that section
      // rather than at the top of the document.
      sectionExtras: {
        'Deleting Your Account': _Link(
          'Delete my account',
          () => Navigator.of(context).pushNamed(AppRoutes.legalDeleteAccount),
          color: context.danger,
        ),
      },
    );
  }
}

/// Screen 4 — Terms & Conditions. Ten expandable sections over the same
/// document shell the privacy policy uses.
class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _DocumentPage(
      title: 'Terms & Conditions',
      intro: 'You deliver as an independent partner, not an employee. These '
          'sections set out what you can expect from us and what we expect '
          'from you.',
      sections: kTermsSections,
    );
  }
}

/// Screen 3 — Information We Collect.
///
/// The detail behind the policy's summary: every field we hold, grouped by
/// category. Fields render as neutral chips so a long category stays scannable
/// without turning into a wall of bullets.
class DataCollectionScreen extends StatelessWidget {
  const DataCollectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final int fieldCount =
        kDataGroups.fold<int>(0, (sum, group) => sum + group.items.length);

    return AppShell(
      title: 'Information We Collect',
      subtitle: '$fieldCount fields across ${kDataGroups.length} categories',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LegalIntro(
            'This is the complete list. If a field is not on this page, the '
            'app does not collect it.',
          ),
          const LegalSectionLabel('What we never do'),
          _pledges(context).legalEntrance(0),
          const SizedBox(height: LegalTokens.gapGroup),
          const LegalSectionLabel('Data categories'),
          for (int i = 0; i < kDataGroups.length; i++) ...[
            _groupCard(context, kDataGroups[i]).legalEntrance(i + 1),
            if (i != kDataGroups.length - 1)
              const SizedBox(height: LegalTokens.gapTight),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _pledges(BuildContext context) {
    const List<String> pledges = [
      'We never sell your personal data.',
      'We never share it with advertisers or data brokers.',
      'We never track your location when you have no active delivery.',
      'We never read your contacts, messages or other apps.',
    ];

    return LegalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < pledges.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == pledges.length - 1 ? 0 : 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1, right: 10),
                    child: Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: context.success,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      pledges[i],
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: context.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _groupCard(BuildContext context, DataGroup group) {
    return LegalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LegalGlyph(icon: group.icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: DashColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      group.purpose,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final item in group.items) LegalDataChip(label: item),
            ],
          ),
          if (group.note != null) ...[
            const SizedBox(height: 12),
            LegalNote(group.note!, icon: Icons.shield_outlined),
          ],
        ],
      ),
    );
  }
}

/// Screen 5 — Data & Permissions.
///
/// One card per runtime permission: what it is used for, when it applies, and
/// whether deliveries are possible without it. The "when it applies" line is
/// the scope limit, and it is what Play's prominent-disclosure rule for
/// background location expects to see.
class DataPermissionsScreen extends StatelessWidget {
  const DataPermissionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Data & Permissions',
      subtitle: 'Why the app asks, and when',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LegalIntro(
            'The app asks for five permissions. You can change any of them at '
            'any time in your device settings — we will tell you if a delivery '
            'cannot proceed without one.',
          ),
          const LegalSectionLabel('Permissions'),
          for (int i = 0; i < kPermissions.length; i++) ...[
            _card(context, kPermissions[i]).legalEntrance(i),
            if (i != kPermissions.length - 1)
              const SizedBox(height: LegalTokens.gapTight),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, PermissionInfo permission) {
    return LegalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LegalGlyph(icon: permission.icon),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  permission.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DashColors.textPrimary(context),
                  ),
                ),
              ),
              _badge(context, permission.required_),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            permission.why,
            style: TextStyle(
              fontSize: 13,
              height: 1.55,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 11),
          LegalNote(permission.scope, icon: Icons.schedule_rounded),
        ],
      ),
    );
  }

  /// The one place colour is earned on this screen — "required" changes what
  /// the driver should do about it.
  Widget _badge(BuildContext context, bool required) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: required ? context.warningContainer : context.fillSubtle,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        required ? 'Required' : 'Optional',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: required ? context.warning : context.textSecondary,
        ),
      ),
    );
  }
}

/// Screen 6 — Contact & Support.
///
/// Email and phone channels launch the relevant app; every card can be
/// long-pressed to copy its value, which matters when no mail client is set up.
class ContactSupportScreen extends StatelessWidget {
  const ContactSupportScreen({super.key});

  Future<void> _launch(BuildContext context, ContactChannel channel) async {
    if (channel.uri == null) {
      await _copy(context, channel);
      return;
    }

    final Uri uri = Uri.parse(channel.uri!);
    final bool opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    // No mail or dialler app available — fall back to the clipboard rather
    // than leaving the tap doing nothing.
    if (!opened && context.mounted) await _copy(context, channel);
  }

  Future<void> _copy(BuildContext context, ContactChannel channel) async {
    await Clipboard.setData(ClipboardData(text: channel.value));
    if (context.mounted) {
      AppToast.show(context, '${channel.title} copied to clipboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Contact & Support',
      subtitle: 'We usually reply within one working day',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LegalIntro(
            'Pick the channel that fits your question. Tap a card to open it, '
            'or press and hold to copy the details.',
          ),
          const LegalSectionLabel('Get in touch'),
          for (int i = 0; i < kContactChannels.length; i++) ...[
            _card(context, kContactChannels[i]).legalEntrance(i),
            if (i != kContactChannels.length - 1)
              const SizedBox(height: LegalTokens.gapTight),
          ],
          const SizedBox(height: LegalTokens.gapGroup),
          const LegalSectionLabel('Escalation'),
          _grievance(context).legalEntrance(kContactChannels.length),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, ContactChannel channel) {
    return GestureDetector(
      onLongPress: () => _copy(context, channel),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _launch(context, channel),
          borderRadius: BorderRadius.circular(LegalTokens.cardRadius),
          child: LegalCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LegalGlyph(icon: channel.icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: DashColors.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        channel.value,
                        style: TextStyle(
                          fontSize: 13,
                          height: channel.multiline ? 1.5 : 1.3,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        channel.subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  channel.uri == null
                      ? Icons.copy_rounded
                      : Icons.arrow_outward_rounded,
                  size: 15,
                  color: context.textSecondary.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Named separately because the DPDP Act requires the Grievance Officer to be
  /// identifiable, not just reachable through a generic inbox.
  Widget _grievance(BuildContext context) {
    return LegalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LegalGlyph(icon: Icons.gavel_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Grievance Officer',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DashColors.textPrimary(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${LegalConstants.grievanceOfficer}\n'
            '${LegalConstants.privacyEmail}',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'If we do not resolve your privacy grievance, you may escalate it '
            'to the Data Protection Board of India.',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Screen 7 — Delete Account.
///
/// Reached from the Privacy Policy, because that is where the right to erasure
/// is described. Deliberately provider-free: the partner's details arrive as
/// parameters so this stays a plain widget the route can build and a test can
/// render without standing up app state.
///
/// Talks to `grozfy_go.grozfy_go.api.account.*` (spec:
/// `docs/backend-specs/request_account_deletion.md`). The request is not
/// immediate — it is approved, then erased after a grace period, so this screen
/// has three faces: raise a request, show what is blocking one, and show a
/// scheduled one with a way to call it off.
///
/// The callbacks are injected rather than read from a provider. That keeps the
/// screen renderable on its own, and lets the blocked and scheduled states be
/// tested without a server.
///
/// A failed call is reported, not worked around. There is no email fallback:
/// the API is the deletion path, and a request that did not reach it must look
/// like a request that did not reach it.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({
    super.key,
    this.onLoadStatus,
    this.onSubmit,
    this.onCancelRequest,
  });

  final Future<({AccountDeletionStatus? data, String? error})> Function()?
      onLoadStatus;
  final Future<({AccountDeletionStatus? data, String? error})> Function()?
      onSubmit;
  final Future<({AccountDeletionStatus? data, String? error})> Function(
    String requestName,
  )? onCancelRequest;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  bool _understood = false;
  bool _sending = false;
  bool _loading = false;
  String? _error;
  AccountDeletionStatus? _request;

  @override
  void initState() {
    super.initState();
    if (widget.onLoadStatus != null) {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadStatus());
    }
  }

  /// A partner who already asked must see that, not a fresh form they could
  /// submit again.
  Future<void> _loadStatus() async {
    final result = await widget.onLoadStatus!();
    if (!mounted) return;
    setState(() {
      _loading = false;
      // A failed status read is not evidence there is no request, but it must
      // not block the screen either — fall through to the form, where a
      // duplicate submit returns `already_requested` anyway.
      if (result.data != null && result.data!.isPending) {
        _request = result.data;
      }
    });
  }

  static const List<String> _removed = [
    'Your profile, photo, phone number, email and address',
    'Aadhaar, PAN and driving licence copies',
    'Vehicle, bank and UPI details',
    'Location history and saved device tokens',
  ];

  static const List<String> _retained = [
    'Order, payout and tax records the law requires us to keep — unlinked from '
        'your profile',
    'Anything needed to close an open dispute or settle cash you are holding',
  ];

  Future<void> _submit() async {
    // Never return silently. A button that does nothing is indistinguishable
    // from a broken one, and this is the screen where "did that work?" matters
    // most.
    if (widget.onSubmit == null) {
      setState(
        () => _error = 'Account deletion is unavailable in this build.',
      );
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    final result = await widget.onSubmit!();
    if (!mounted) return;

    if (result.data != null) {
      setState(() {
        _sending = false;
        _request = result.data;
      });
      AppToast.show(context, _outcomeMessage(result.data!));
      return;
    }

    // Report the failure and stop. Routing around a broken endpoint would make
    // a request that never landed look to the partner like one that did.
    setState(() {
      _sending = false;
      _error = result.error ?? 'Could not reach the server. Please try again.';
    });
  }

  String _outcomeMessage(AccountDeletionStatus status) {
    if (status.isBlocked) {
      return 'Deletion is on hold until the items below are cleared';
    }
    if (status.status == 'already_requested') {
      return 'You already have a deletion request in progress';
    }
    return 'Deletion requested. You can still cancel it until '
        '${_formatDate(status.cancellableUntil)}.';
  }

  Future<void> _cancel() async {
    final String? name = _request?.requestName;
    if (name == null || widget.onCancelRequest == null) return;

    setState(() => _sending = true);
    final result = await widget.onCancelRequest!(name);
    if (!mounted) return;

    setState(() {
      _sending = false;
      // Cancelled and rejected are terminal, so the form comes back — a new
      // decision means a new request.
      if (result.data != null) _request = null;
      if (result.data != null) _understood = false;
    });
    AppToast.show(
      context,
      result.data != null
          ? 'Your account will not be deleted.'
          : result.error ?? 'Could not cancel the request',
    );
  }

  static String _formatDate(DateTime? value) {
    if (value == null) return 'the scheduled date';
    const List<String> months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${value.day} ${months[value.month - 1]} ${value.year}';
  }

  @override
  Widget build(BuildContext context) {
    final AccountDeletionStatus? request = _request;

    return AppShell(
      title: 'Delete Account',
      subtitle: request != null && request.isPending
          ? 'Your request is being processed'
          : 'This closes your partner account for good',
      loading: _loading,
      loadingMessage: 'Checking your account…',
      child: request != null && request.isPending
          ? _pendingBody(context, request)
          : _formBody(context),
    );
  }

  /// A request already exists — blocked on settlement, or scheduled. Either way
  /// the form must not be shown, or a partner would raise a second request
  /// against an account that already has one.
  Widget _pendingBody(BuildContext context, AccountDeletionStatus request) {
    final Color danger = context.danger;
    final bool blocked = request.isBlocked;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LegalIntro(
          blocked
              ? 'We cannot delete your account yet. Clear the items below, then '
                  'ask again — nothing has been deleted.'
              : 'Your account is scheduled for deletion on '
                  '${_formatDate(request.scheduledDeletionOn)}. Until then you '
                  'can keep working as normal, and you can still change your '
                  'mind.',
        ),
        if (blocked) ...[
          const LegalSectionLabel('Before you can delete'),
          LegalCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < request.blockers.length; i++) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 18,
                        color: danger,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        // Worded and localised by the server, shown verbatim —
                        // the app must not invent copy from the code.
                        child: Text(
                          request.blockers[i].message,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                            color: DashColors.textPrimary(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (i != request.blockers.length - 1)
                    const SizedBox(height: 14),
                ],
              ],
            ),
          ).legalEntrance(0),
          const SizedBox(height: LegalTokens.gapGroup),
          LegalPrimaryButton(
            label: 'Check again',
            color: danger,
            busy: _sending,
            onPressed: _submit,
          ),
        ] else ...[
          const LegalSectionLabel('What happens next'),
          LegalCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LegalBullet(
                  'On ${_formatDate(request.scheduledDeletionOn)} your personal '
                  'data is permanently erased.',
                ),
                const LegalBullet(
                  'Pending earnings are paid and any cash you hold is '
                  'reconciled first.',
                ),
                const LegalBullet(
                  'Order and tax records are kept, with your details removed.',
                ),
              ],
            ),
          ).legalEntrance(0),
          const SizedBox(height: LegalTokens.gapGroup),
          LegalNote(
            'Request ${request.requestName ?? ''} · raised '
            '${_formatDate(request.requestedOn)}',
            icon: Icons.receipt_long_outlined,
          ).legalEntrance(1),
          const SizedBox(height: LegalTokens.gapGroup),
          if (request.isCancellable && widget.onCancelRequest != null)
            LegalPrimaryButton(
              label: 'Cancel deletion request',
              busy: _sending,
              onPressed: _cancel,
            ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _formBody(BuildContext context) {
    final Color danger = context.danger;

    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LegalIntro(
            'Deleting your account removes your personal data from Grozfy. It '
            'cannot be undone — your delivery history, ratings and incentive '
            'progress are lost, and signing up again means starting '
            'verification from scratch.',
          ),
          const LegalSectionLabel('What we delete'),
          LegalCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final String item in _removed) LegalBullet(item),
              ],
            ),
          ).legalEntrance(0),
          const SizedBox(height: LegalTokens.gapGroup),
          const LegalSectionLabel('What we have to keep'),
          LegalCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final String item in _retained) LegalBullet(item),
              ],
            ),
          ).legalEntrance(1),
          const SizedBox(height: LegalTokens.gapGroup),
          const LegalNote(
            'Pending earnings are paid and any cash you hold is reconciled '
            'before the account closes. We acknowledge your request within 48 '
            'hours and finish within 30 days.',
            icon: Icons.schedule_rounded,
          ).legalEntrance(2),
          const SizedBox(height: LegalTokens.gapGroup),
          InkWell(
            onTap: () => setState(() => _understood = !_understood),
            borderRadius: BorderRadius.circular(LegalTokens.innerRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _understood,
                    activeColor: danger,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) => setState(() => _understood = v ?? false),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'I understand my account and data will be permanently '
                        'deleted and cannot be recovered.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                          color: DashColors.textPrimary(context),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_error != null) ...[
            LegalNote(_error!, icon: Icons.error_outline_rounded),
            const SizedBox(height: 12),
          ],
          LegalPrimaryButton(
            label: 'Request account deletion',
            color: danger,
            busy: _sending,
            onPressed: _understood ? _submit : null,
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: _sending ? null : () => Navigator.of(context).pop(),
              child: Text(
                'Keep my account',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
    );
  }
}

// ── Shared pieces ───────────────────────────────────────────────────────────

/// Shell for the two long-form documents.
///
/// Sections render as expandable rows inside a single grouped card — the same
/// idiom as the Profile screen — rather than one card each, which is what
/// previously made these pages so long.
class _DocumentPage extends StatefulWidget {
  const _DocumentPage({
    required this.title,
    required this.intro,
    required this.sections,
    this.leadingGroup,
    this.sectionExtras = const <String, Widget>{},
  });

  final String title;
  final String intro;
  final List<LegalSection> sections;

  /// Optional group inserted above the sections — used by the privacy policy to
  /// link through to the collected-data page.
  final Widget? leadingGroup;

  /// Widget appended inside a named section's body, keyed by section title.
  /// Lets a section that describes an action also offer it, without putting
  /// that action at the top of the document where it is not in context.
  final Map<String, Widget> sectionExtras;

  @override
  State<_DocumentPage> createState() => _DocumentPageState();
}

class _DocumentPageState extends State<_DocumentPage> {
  /// Bumped to rebuild the rows with a new initial expansion state, which is
  /// how expand-all / collapse-all is applied.
  int _generation = 0;
  bool _allExpanded = false;

  void _toggleAll() {
    setState(() {
      _allExpanded = !_allExpanded;
      _generation++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: widget.title,
      subtitle: 'Updated ${LegalConstants.lastUpdated}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LegalIntro(widget.intro),
          if (widget.leadingGroup != null) ...[
            widget.leadingGroup!.legalEntrance(0),
            const SizedBox(height: LegalTokens.gapGroup),
          ],
          LegalSectionLabel(
            '${widget.sections.length} sections',
            trailing: TextButton(
              onPressed: _toggleAll,
              style: TextButton.styleFrom(
                foregroundColor: context.scheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Poppins',
                ),
              ),
              child: Text(_allExpanded ? 'Collapse all' : 'Expand all'),
            ),
          ),
          LegalGroup(
            children: [
              for (final section in widget.sections)
                LegalExpansionRow(
                  key: ValueKey('${section.title}-$_generation'),
                  title: section.title,
                  icon: section.icon,
                  initiallyExpanded: _allExpanded,
                  children: [
                    for (final paragraph in section.paragraphs)
                      LegalParagraph(paragraph),
                    for (final bullet in section.bullets) LegalBullet(bullet),
                    if (section.closing != null) ...[
                      LegalNote(section.closing!),
                      const SizedBox(height: 10),
                    ],
                    ?widget.sectionExtras[section.title],
                  ],
                ),
            ],
          ).legalEntrance(1),
          const SizedBox(height: 20),
          const LegalDocumentFooter(
            version: LegalConstants.documentVersion,
            lastUpdated: LegalConstants.lastUpdated,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

/// One consent point: glyph, title, one or two lines of detail. No card and no
/// chevron — it is a statement, not somewhere to navigate to.
class _Highlight extends StatelessWidget {
  const _Highlight(this.data);

  final ({IconData icon, String title, String detail}) data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LegalGlyph(icon: data.icon),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  // Optical alignment with the 34dp glyph — the title's cap
                  // height sits high in its line box.
                  padding: const EdgeInsets.only(top: 5, bottom: 4),
                  child: Text(
                    data.title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      color: context.textPrimary,
                    ),
                  ),
                ),
                Text(
                  data.detail,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A plain underlined text link. The documents are references to dip into, not
/// steps to complete — rendering them as rows in a card was what made a
/// two-item list read as a checklist.
class _Link extends StatelessWidget {
  const _Link(this.label, this.onTap, {this.color});

  final String label;
  final VoidCallback onTap;

  /// Overrides the default link blue — used for the destructive one.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color accent = color ?? context.info;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(LegalTokens.innerRadius),
      child: Padding(
        // Vertical padding carries the 48dp tap target on its own, so the row
        // needs no background to be comfortably tappable.
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: accent,
                  decoration: TextDecoration.underline,
                  decorationColor: accent.withValues(alpha: 0.4),
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 19, color: accent),
          ],
        ),
      ),
    );
  }
}
