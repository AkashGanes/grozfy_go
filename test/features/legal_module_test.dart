import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grozfy_go/core/constants/legal_constants.dart';
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

  test('content model is populated as the screens advertise', () {
    expect(kPrivacySections, hasLength(13));
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

