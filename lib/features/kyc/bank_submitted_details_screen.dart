import 'package:flutter/material.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/widgets/app_shell.dart';

class BankSubmittedDetailsScreen extends StatelessWidget {
  const BankSubmittedDetailsScreen({super.key, required this.bankData});

  final Map<String, dynamic> bankData;

  Map<String, String> _rows() {
    final Map<String, String> rows = <String, String>{};

    void put(String label, String key) {
      final String value = (bankData[key]?.toString() ?? '').trim();
      if (value.isNotEmpty) {
        rows[label] = value;
      }
    }

    put('Account Name', 'account_name');
    put('Bank', 'bank');
    put('Company Account', 'account');
    put('Account Type', 'account_type');
    put('Account Subtype', 'account_subtype');
    put('Company', 'company');
    put('Party Type', 'party_type');
    put('Party', 'party');
    put('IBAN', 'iban');
    put('Branch Code', 'branch_code');
    put('Bank Account No', 'bank_account_no');
    put('Last Integration Date', 'last_integration_date');

    rows['Disabled'] = bankData['disabled']?.toString() == '1' ? 'Yes' : 'No';
    rows['Is Default'] = bankData['is_default']?.toString() == '1'
        ? 'Yes'
        : 'No';
    rows['Is Company Account'] = bankData['is_company_account']?.toString() == '1'
        ? 'Yes'
        : 'No';

    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final String title =
        bankData['account_name']?.toString().trim().isNotEmpty == true
        ? bankData['account_name']!.toString().trim()
        : 'Bank Account Details';
    final Map<String, String> rows = _rows();

    return AppShell(
      title: title,
      subtitle: 'Submitted bank account details',
      child: FrostCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in rows.entries) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(
                      entry.key,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushReplacementNamed(
                        AppRoutes.bankSetup,
                        arguments: <String, dynamic>{'force_edit': true},
                      );
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit Bank Details'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pushNamed(AppRoutes.permission);
                    },
                    child: const Text('Permission Setup'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
