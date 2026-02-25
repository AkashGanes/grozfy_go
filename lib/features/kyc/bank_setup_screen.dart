import 'package:flutter/material.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/widgets/app_shell.dart';

class BankSetupScreen extends StatefulWidget {
  const BankSetupScreen({super.key});

  @override
  State<BankSetupScreen> createState() => _BankSetupScreenState();
}

class _BankSetupScreenState extends State<BankSetupScreen> {
  final TextEditingController _accountNumberCtrl = TextEditingController();
  final TextEditingController _ifscCtrl = TextEditingController();
  final TextEditingController _holderCtrl = TextEditingController();
  final TextEditingController _upiCtrl = TextEditingController();

  @override
  void dispose() {
    _accountNumberCtrl.dispose();
    _ifscCtrl.dispose();
    _holderCtrl.dispose();
    _upiCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final app = AppScope.of(context);
    final String? error = app.submitBankDetails(
      accountNumber: _accountNumberCtrl.text,
      ifsc: _ifscCtrl.text,
      accountHolder: _holderCtrl.text,
      upiId: _upiCtrl.text,
    );

    if (error != null) {
      showInfoSnack(context, error);
      return;
    }

    showInfoSnack(context, 'Bank account verified and payout enabled');
    Navigator.of(context).pushNamed(AppRoutes.permission);
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Bank Account Setup',
      subtitle: 'Secure payout account for weekly settlements',
      child: FrostCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _accountNumberCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Account Number',
                prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ifscCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'IFSC Code',
                prefixIcon: Icon(Icons.qr_code_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _holderCtrl,
              decoration: const InputDecoration(
                labelText: 'Account Holder Name',
                prefixIcon: Icon(Icons.person_2_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _upiCtrl,
              decoration: const InputDecoration(
                labelText: 'UPI ID (Optional)',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _submit,
              child: const Text('Save Bank Details'),
            ),
          ],
        ),
      ),
    );
  }
}
