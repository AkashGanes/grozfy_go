import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grozfy_go/core/constants/legal_constants.dart';
import 'package:grozfy_go/core/models/app_models.dart';
import 'package:grozfy_go/core/theme/app_theme.dart';
import 'package:grozfy_go/features/legal/legal_content.dart';
import 'package:grozfy_go/features/legal/legal_design.dart';
import 'package:grozfy_go/features/legal/legal_screens.dart';

/// The five points the consent screen must state. Duplicated here rather than
/// imported from the screen, deliberately: this is the disclosure a driver
/// agrees to, so the test should fail when someone edits the wording, not
/// silently follow it.
const List<String> kHighlightTitles = <String>[
  'We use your location',
  'We verify your documents',
  'We pay you directly',
  'We never sell your data',
  'You stay in control',
];

/// Renders every screen in the Privacy & Legal module in both themes and at a
/// small viewport. These screens are almost entirely layout, so "it lays out
/// without overflowing or throwing" is the assertion that actually matters.
void main() {
  Widget host(Widget child, {Brightness brightness = Brightness.light}) {
    return MaterialApp(
      theme: brightness == Brightness.light
          ? AppTheme.getLightTheme()
          : AppTheme.getDarkTheme(),
      home: child,
    );
  }

  final Map<String, Widget> screens = <String, Widget>{
    'Terms & Privacy (reference)': const TermsPrivacyScreen(),
    'Terms & Privacy (consent gate)':
        const TermsPrivacyScreen(requireConsent: true),
    'Privacy Policy': const PrivacyPolicyScreen(),
    'Information We Collect': const DataCollectionScreen(),
    'Terms & Conditions': const TermsConditionsScreen(),
    'Data & Permissions': const DataPermissionsScreen(),
    'Contact & Support': const ContactSupportScreen(),
    'Delete Account': const DeleteAccountScreen(),
  };

  group('renders in light theme', () {
    screens.forEach((name, screen) {
      testWidgets(name, (tester) async {
        await tester.pumpWidget(host(screen));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('renders in dark theme', () {
    screens.forEach((name, screen) {
      testWidgets(name, (tester) async {
        await tester.pumpWidget(host(screen, brightness: Brightness.dark));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('renders on a small viewport without overflow', () {
    screens.forEach((name, screen) {
      testWidgets(name, (tester) async {
        tester.view.physicalSize = const Size(720, 1280);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(host(screen));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    });
  });

  testWidgets('consent gate states the terms instead of listing documents',
      (tester) async {
    await tester.pumpWidget(host(const TermsPrivacyScreen(requireConsent: true)));
    await tester.pumpAndSettle();

    // The summary is the screen — every point must be on it, or the driver is
    // consenting to less than they were shown. Spelled out as literal strings
    // because the wording *is* the disclosure: reworded or dropped silently,
    // and the consent record no longer describes what was agreed to.
    for (final title in kHighlightTitles) {
      expect(
        find.text(title),
        findsOneWidget,
        reason: '"$title" is missing from the gate',
      );
    }

    // No grouped cards, no navigation rows — the document-list layout is what
    // this redesign replaced.
    expect(find.byType(LegalNavRow), findsNothing);
    expect(find.byType(LegalGroup), findsNothing);

    // But the full text stays reachable before acceptance.
    expect(find.text('Read the full Privacy Policy'), findsOneWidget);
    expect(find.text('Read the full Terms & Conditions'), findsOneWidget);
  });

  testWidgets('the reference hub keeps the paths that lead only from it',
      (tester) async {
    await tester.pumpWidget(host(const TermsPrivacyScreen()));
    await tester.pumpAndSettle();

    // Data & Permissions and Contact & Support are not duplicated in the More
    // menu, so losing them here would orphan both screens.
    expect(find.text('Data & Permissions'), findsOneWidget);
    expect(find.text('Contact & Support'), findsOneWidget);
    expect(find.text('Read the full Privacy Policy'), findsOneWidget);
    expect(find.text('Read the full Terms & Conditions'), findsOneWidget);
    expect(find.byType(LegalNavRow), findsNothing);
  });

  testWidgets('continue is disabled until the checkbox is ticked',
      (tester) async {
    await tester.pumpWidget(host(const TermsPrivacyScreen(requireConsent: true)));
    await tester.pumpAndSettle();

    final Finder accept = find.widgetWithText(ElevatedButton, 'Continue');
    expect(accept, findsOneWidget);
    expect(tester.widget<ElevatedButton>(accept).onPressed, isNull);

    // Ticking the box is the whole gate now — no document has to be opened
    // first.
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(accept).onPressed, isNotNull);

    // And un-ticking must close it again.
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(accept).onPressed, isNull);
  });

  testWidgets('accepting returns the version and documents the backend records',
      (tester) async {
    LegalConsentResult? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.getLightTheme(),
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push<LegalConsentResult>(
                MaterialPageRoute<LegalConsentResult>(
                  builder: (_) => const TermsPrivacyScreen(requireConsent: true),
                ),
              );
            },
            child: const Text('open gate'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open gate'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.version, LegalConstants.documentVersion);
    expect(result!.documents, 'privacy_policy,terms');
    expect(result!.source, 'Registration');
  });

  testWidgets('dismissing the gate returns null so registration cannot proceed',
      (tester) async {
    LegalConsentResult? result;
    bool popped = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.getLightTheme(),
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push<LegalConsentResult>(
                MaterialPageRoute<LegalConsentResult>(
                  builder: (_) => const TermsPrivacyScreen(requireConsent: true),
                ),
              );
              popped = true;
            },
            child: const Text('open gate'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open gate'));
    await tester.pumpAndSettle();

    // Backing out without ticking must yield null, or the caller would treat a
    // dismissal as consent.
    Navigator.of(tester.element(find.byType(Checkbox))).pop();
    await tester.pumpAndSettle();

    expect(popped, isTrue);
    expect(result, isNull);
  });

  testWidgets('the policy offers deletion from inside the section about it',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host(const PrivacyPolicyScreen()));
    await tester.pumpAndSettle();

    // Nothing at the top of the document — the way to delete belongs with the
    // text that explains it, not above the policy the partner is still reading.
    expect(find.text('Delete my account'), findsNothing);

    final Finder section = find.text('Deleting Your Account');
    await tester.ensureVisible(section);
    await tester.pumpAndSettle();
    await tester.tap(section);
    await tester.pumpAndSettle();

    expect(find.text('Delete my account'), findsOneWidget);
  });

  testWidgets('deletion needs an explicit acknowledgement first',
      (tester) async {
    await tester.pumpWidget(host(const DeleteAccountScreen()));
    await tester.pumpAndSettle();

    final Finder submit =
        find.widgetWithText(ElevatedButton, 'Request account deletion');
    expect(submit, findsOneWidget);
    expect(tester.widget<ElevatedButton>(submit).onPressed, isNull);

    // The box sits below the fold on a default test viewport.
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(submit).onPressed, isNotNull);

    // The screen must state what survives deletion, not only what goes — a
    // partner told "everything is deleted" would be told something untrue.
    // LegalSectionLabel renders uppercase.
    expect(find.text('WHAT WE DELETE'), findsOneWidget);
    expect(find.text('WHAT WE HAVE TO KEEP'), findsOneWidget);
  });

  testWidgets('a blocked request shows what to clear, not a failure',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host(
      DeleteAccountScreen(
        onLoadStatus: () async => (data: AccountDeletionStatus.none, error: null),
        onSubmit: ({String? reasonCode, String? reason}) async => (
          data: const AccountDeletionStatus(
            status: 'blocked',
            requestName: 'ADR-2026-00015',
            requestStatus: 'Blocked',
            blockers: <AccountDeletionBlocker>[
              AccountDeletionBlocker(
                code: 'COD_OUTSTANDING',
                message: 'You are holding ₹1,240 in cash collections.',
                amount: 1240,
              ),
            ],
          ),
          error: null,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Request account deletion'));
    await tester.pumpAndSettle();

    // The server's wording, verbatim — the app must not paraphrase a blocker.
    expect(find.text('You are holding ₹1,240 in cash collections.'), findsOneWidget);
    // And the form is gone, so a second request cannot be fired at it.
    expect(find.byType(Checkbox), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Check again'), findsOneWidget);

    // Let the confirmation toast expire — it owns a timer.
    await tester.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets('an existing request is shown instead of a fresh form',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    bool cancelled = false;

    await tester.pumpWidget(host(
      DeleteAccountScreen(
        onLoadStatus: () async => (
          data: AccountDeletionStatus(
            status: 'already_requested',
            requestName: 'ADR-2026-00014',
            requestStatus: 'Approved',
            requestedOn: DateTime(2026, 8, 3),
            scheduledDeletionOn: DateTime(2026, 8, 10),
            cancellableUntil: DateTime(2026, 8, 10),
          ),
          error: null,
        ),
        onSubmit: ({String? reasonCode, String? reason}) async =>
            (data: null, error: 'should not be called'),
        onCancelRequest: (name) async {
          cancelled = name == 'ADR-2026-00014';
          return (
            data: const AccountDeletionStatus(
              status: 'cancelled',
              requestStatus: 'Cancelled',
            ),
            error: null,
          );
        },
      ),
    ));
    await tester.pumpAndSettle();

    // Never the form — raising a second request against a scheduled account is
    // the thing this state exists to prevent.
    expect(find.byType(Checkbox), findsNothing);
    expect(find.textContaining('10 Aug 2026'), findsWidgets);

    final Finder cancel =
        find.widgetWithText(ElevatedButton, 'Cancel deletion request');
    await tester.ensureVisible(cancel);
    await tester.pumpAndSettle();
    await tester.tap(cancel);
    await tester.pumpAndSettle();

    expect(cancelled, isTrue);
    // Cancelling is terminal, so the partner is back to a fresh decision.
    expect(find.byType(Checkbox), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets('a failed request is reported, never worked around',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host(
      DeleteAccountScreen(
        onSubmit: ({String? reasonCode, String? reason}) async =>
            (data: null, error: 'Request failed (404)'),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(
        find.widgetWithText(ElevatedButton, 'Request account deletion'));
    await tester.pumpAndSettle();

    // The server's own message, shown as-is. While `Driver.user_id` is being
    // backfilled this is how the 404 reaches whoever is testing, so it must not
    // be swallowed or paraphrased.
    expect(find.text('Request failed (404)'), findsOneWidget);
    // The API is the only deletion path — no alternative route may appear here.
    expect(find.text('Email the request instead'), findsNothing);
    // And the form stays, to retry from once the patch lands.
    expect(find.widgetWithText(ElevatedButton, 'Request account deletion'),
        findsOneWidget);
  });

  test('content model is populated as the screens advertise', () {
    expect(kPrivacySections, hasLength(14));
    expect(
      kPrivacySections.any((s) => s.title == 'Deleting Your Account'),
      isTrue,
      reason: 'the policy must describe deletion, not just offer the button',
    );
    expect(kTermsSections, hasLength(10));
    expect(kDataGroups, hasLength(6));
    expect(kPermissions, hasLength(5));
    expect(kContactChannels, hasLength(4));

    // Every section must render something, or it would collapse to an empty
    // card.
    for (final section in [...kPrivacySections, ...kTermsSections]) {
      expect(
        section.paragraphs.isNotEmpty || section.bullets.isNotEmpty,
        isTrue,
        reason: '"${section.title}" has no body content',
      );
    }
  });
}

