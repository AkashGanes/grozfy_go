import 'package:flutter/material.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/widgets/app_shell.dart';

class BankSubmittedDetailsScreen extends StatelessWidget {
  const BankSubmittedDetailsScreen({super.key, required this.bankData});

  final Map<String, dynamic> bankData;

  String _maskedAccountNo(String raw) {
    final String digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 4) return digits;
    final String visible = digits.substring(digits.length - 4);
    return '${'●' * (digits.length - 4)} $visible';
  }

  List<_DetailRow> _rows() {
    final List<_DetailRow> rows = <_DetailRow>[];

    void add(String label, String key, {bool mask = false}) {
      final String raw = (bankData[key]?.toString() ?? '').trim();
      if (raw.isEmpty) return;
      rows.add(_DetailRow(label: label, value: mask ? _maskedAccountNo(raw) : raw));
    }

    add('Account Holder Name', 'account_name');
    add('Bank', 'bank');
    add('Account Type', 'account_type');
    add('Account Number', 'bank_account_no', mask: true);
    add('IFSC Code', 'branch_code');
    add('Branch Name', 'branch_name');
    add('IBAN', 'iban');

    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final String holderName =
        (bankData['account_name']?.toString() ?? '').trim();
    final String pageTitle =
        holderName.isNotEmpty ? holderName : 'Bank Details';
    final List<_DetailRow> rows = _rows();

    return AppShell(
      title: pageTitle,
      subtitle: 'Your saved bank details',
      child: FrostCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final _DetailRow row in rows) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(
                      row.label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      row.value,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
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
                    label: const Text('Edit Account'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pushNamed(AppRoutes.permission);
                    },
                    child: const Text('Continue'),
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

class _DetailRow {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;
}
