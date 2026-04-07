import 'package:delivery_partner_app/core/state/app_controller.dart';
import 'package:delivery_partner_app/core/state/providers.dart';
import 'package:delivery_partner_app/features/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('renders login auth options', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = AppController()..setLanguage('en');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    expect(find.text('Mobile Number'), findsOneWidget);
    expect(find.text('Enter your mobile number to continue'), findsOneWidget);
    expect(find.text('Send OTP'), findsOneWidget);
  });
}
