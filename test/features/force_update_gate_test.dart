import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:grozfy_go/core/services/app_version_service.dart';
import 'package:grozfy_go/core/state/app_controller.dart';
import 'package:grozfy_go/core/state/providers.dart';
import 'package:grozfy_go/features/settings/force_update_screen.dart';

Future<PackageInfo> _packageInfo() async => PackageInfo(
  appName: 'Grozfy Go',
  packageName: 'com.grozfy.go',
  version: '1.0.1',
  buildNumber: '2',
);

AppController _controller(Map<String, dynamic> message) => AppController(
  appVersionService: AppVersionService(
    client: MockClient(
      (_) async =>
          http.Response(jsonEncode(<String, dynamic>{'message': message}), 200),
    ),
    packageInfoLoader: _packageInfo,
    platformName: 'android',
  ),
);

/// Mirrors how `main.dart` mounts the gate: a plain [MaterialApp] with routes
/// and a `builder`, **not** MaterialApp.router. The distinction matters — the
/// first version of the gate used `BackButtonListener`, which asserts on a
/// missing `Router` and crashed on device while every unit test passed.
Widget _app(AppController controller, {VoidCallback? onContentTap}) {
  return UncontrolledProviderScope(
    container: ProviderContainer(
      overrides: <Override>[
        appControllerProvider.overrideWith((_) => controller),
      ],
    ),
    child: MaterialApp(
      initialRoute: '/',
      builder: (BuildContext context, Widget? child) =>
          ForceUpdateGate(child: child ?? const SizedBox.shrink()),
      onGenerateRoute: (RouteSettings settings) => MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: onContentTap ?? () {},
              child: const Text('app content'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('mounts without error and shows the app when up to date', (
    WidgetTester tester,
  ) async {
    final AppController controller = _controller(<String, dynamic>{});
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('app content'), findsOneWidget);
  });

  testWidgets('a mandatory verdict shows the sheet over the live app', (
    WidgetTester tester,
  ) async {
    final AppController controller = _controller(<String, dynamic>{
      'update_required': true,
      'latest_version': '1.2.0',
    });
    await tester.pumpWidget(_app(controller));
    await controller.checkAppVersion();
    await tester.pumpAndSettle();

    // The crash this test exists for: BackButtonListener asserting on a
    // missing Router while the block mounts.
    expect(tester.takeException(), isNull);
    expect(find.byType(MandatoryUpdateSheet), findsOneWidget);
    // The app stays mounted behind the sheet — that is the point of the sheet
    // over the old full-screen page.
    expect(find.text('app content'), findsOneWidget);
    expect(find.text('1.2.0'), findsOneWidget);
  });

  testWidgets('the mandatory scrim does not dismiss — only "Later" does', (
    WidgetTester tester,
  ) async {
    final AppController controller = _controller(<String, dynamic>{
      'update_required': true,
    });
    await tester.pumpWidget(_app(controller));
    await controller.checkAppVersion();
    await tester.pumpAndSettle();

    // Scoped: routes carry their own ModalBarrier, so an unscoped finder
    // matches more than one.
    final ModalBarrier barrier = tester.widget<ModalBarrier>(
      find.descendant(
        of: find.byType(MandatoryUpdateSheet),
        matching: find.byType(ModalBarrier),
      ),
    );
    expect(barrier.dismissible, isFalse);

    await tester.tapAt(const Offset(200, 60)); // well above the sheet
    await tester.pumpAndSettle();
    expect(
      find.byType(MandatoryUpdateSheet),
      findsOneWidget,
      reason: 'a stray tap on the scrim must not count as "Later"',
    );
  });

  testWidgets('"Later" on the mandatory sheet returns the app to the driver', (
    WidgetTester tester,
  ) async {
    final AppController controller = _controller(<String, dynamic>{
      'update_required': true,
    });
    await tester.pumpWidget(_app(controller));
    await controller.checkAppVersion();
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(MandatoryUpdateSheet),
        matching: find.text('Later'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MandatoryUpdateSheet), findsNothing);
    expect(controller.isUpdateBlocking, isFalse);
  });

  testWidgets('the app behind a mandatory block cannot be tapped', (
    WidgetTester tester,
  ) async {
    int taps = 0;
    final AppController controller = _controller(<String, dynamic>{
      'update_required': true,
    });
    await tester.pumpWidget(_app(controller, onContentTap: () => taps++));
    await tester.pumpAndSettle();

    // Sanity: the button does work before the block lands.
    await tester.tap(find.text('app content'));
    expect(taps, 1);

    await controller.checkAppVersion();
    await tester.pumpAndSettle();

    await tester.tap(find.text('app content'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(
      taps,
      1,
      reason: 'the barrier must absorb taps aimed at the app behind',
    );
  });

  testWidgets('an optional verdict overlays the app, leaving it mounted', (
    WidgetTester tester,
  ) async {
    final AppController controller = _controller(<String, dynamic>{
      'update_available': true,
    });
    await tester.pumpWidget(_app(controller));
    await controller.checkAppVersion();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(OptionalUpdateSheet), findsOneWidget);
    expect(find.text('app content'), findsOneWidget);
  });

  testWidgets('dismissing the optional prompt returns to the app', (
    WidgetTester tester,
  ) async {
    final AppController controller = _controller(<String, dynamic>{
      'update_available': true,
    });
    await tester.pumpWidget(_app(controller));
    await controller.checkAppVersion();
    await tester.pumpAndSettle();

    await controller.dismissOptionalUpdate();
    await tester.pumpAndSettle();

    expect(find.byType(OptionalUpdateSheet), findsNothing);
    expect(find.text('app content'), findsOneWidget);
  });

  testWidgets('back acts as "Later" and never closes the app', (
    WidgetTester tester,
  ) async {
    final AppController controller = _controller(<String, dynamic>{
      'update_required': true,
    });
    await tester.pumpWidget(_app(controller));
    await controller.checkAppVersion();
    await tester.pumpAndSettle();

    // Same path the platform back press takes.
    final bool handled = await WidgetsBinding.instance.handlePopRoute();
    await tester.pumpAndSettle();

    expect(handled, isTrue, reason: 'unhandled would close the app');
    expect(find.byType(MandatoryUpdateSheet), findsNothing);
    expect(find.text('app content'), findsOneWidget);
  });
}
