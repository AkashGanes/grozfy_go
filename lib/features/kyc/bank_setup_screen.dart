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
  final TextEditingController _accountNameCtrl = TextEditingController();
  final TextEditingController _ibanCtrl = TextEditingController();
  final TextEditingController _branchCodeCtrl = TextEditingController();
  final TextEditingController _bankAccountNoCtrl = TextEditingController();
  final TextEditingController _lastIntegrationDateCtrl =
      TextEditingController();

  List<String> _bankOptions = <String>[];
  List<String> _companyAccountOptions = <String>[];
  List<String> _accountTypeOptions = <String>[];
  List<String> _accountSubtypeOptions = <String>[];
  List<String> _companyOptions = <String>[];
  List<String> _partyTypeOptions = <String>[];
  List<String> _partyOptions = <String>[];

  String? _selectedBank;
  String? _selectedCompanyAccount;
  String? _selectedAccountType;
  String? _selectedAccountSubtype;
  String? _selectedCompany;
  String? _selectedPartyType;
  String? _selectedParty;

  bool _disabled = false;
  bool _isDefault = false;
  bool _isCompanyAccount = false;
  bool _busy = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadOptions();
    });
  }

  @override
  void dispose() {
    _accountNameCtrl.dispose();
    _ibanCtrl.dispose();
    _branchCodeCtrl.dispose();
    _bankAccountNoCtrl.dispose();
    _lastIntegrationDateCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    final app = AppScope.of(context);

    final List<String> banks = await app.fetchLinkOptions(doctype: 'Bank');
    final List<String> accounts = await app.fetchLinkOptions(
      doctype: 'Account',
    );
    final List<String> accountTypes = await app.fetchLinkOptions(
      doctype: 'Bank Account Type',
    );
    final List<String> accountSubtypes = await app.fetchLinkOptions(
      doctype: 'Bank Account Subtype',
    );
    final List<String> companies = await app.fetchLinkOptions(
      doctype: 'Company',
    );
    final List<String> partyTypes = await app.fetchLinkOptions(
      doctype: 'DocType',
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _bankOptions = banks;
      _companyAccountOptions = accounts;
      _accountTypeOptions = accountTypes;
      _accountSubtypeOptions = accountSubtypes;
      _companyOptions = companies;
      _partyTypeOptions = partyTypes;
      _selectedBank = banks.isNotEmpty ? banks.first : null;
      _ready = true;
    });
  }

  Future<void> _loadPartyOptions(String? partyType) async {
    if (partyType == null || partyType.trim().isEmpty) {
      setState(() {
        _partyOptions = <String>[];
        _selectedParty = null;
      });
      return;
    }

    final app = AppScope.of(context);
    final List<String> values = await app.fetchLinkOptions(
      doctype: partyType,
      referenceDoctype: 'Bank Account',
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _partyOptions = values;
      _selectedParty = values.isNotEmpty ? values.first : null;
    });
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) {
      return;
    }
    final String month = picked.month.toString().padLeft(2, '0');
    final String day = picked.day.toString().padLeft(2, '0');
    setState(() {
      _lastIntegrationDateCtrl.text = '${picked.year}-$month-$day';
    });
  }

  Future<void> _submit() async {
    final app = AppScope.of(context);
    setState(() => _busy = true);
    final String? error = await app.submitBankDetails(
      accountName: _accountNameCtrl.text,
      bank: _selectedBank ?? '',
      account: _selectedCompanyAccount,
      accountType: _selectedAccountType,
      accountSubtype: _selectedAccountSubtype,
      disabled: _disabled,
      isDefault: _isDefault,
      isCompanyAccount: _isCompanyAccount,
      company: _selectedCompany,
      partyType: _selectedPartyType,
      party: _selectedParty,
      iban: _ibanCtrl.text,
      branchCode: _branchCodeCtrl.text,
      bankAccountNo: _bankAccountNoCtrl.text,
      lastIntegrationDate: _lastIntegrationDateCtrl.text,
    );

    if (!mounted) {
      return;
    }
    setState(() => _busy = false);

    if (error != null) {
      showInfoSnack(context, error);
      return;
    }

    showInfoSnack(context, 'Bank account submitted successfully');
    Navigator.of(context).pushNamed(AppRoutes.permission);
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Bank Account Setup',
      subtitle: 'Bank Account DocType fields from ERP',
      loading: _busy,
      child: FrostCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _accountNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Account Name *',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            _dropdown(
              label: 'Bank *',
              icon: Icons.account_balance_outlined,
              value: _selectedBank,
              options: _bankOptions,
              onChanged: (value) {
                setState(() => _selectedBank = value);
              },
            ),
            const SizedBox(height: 12),
            _dropdown(
              label: 'Company Account',
              icon: Icons.business_center_outlined,
              value: _selectedCompanyAccount,
              options: _companyAccountOptions,
              onChanged: (value) {
                setState(() => _selectedCompanyAccount = value);
              },
            ),
            const SizedBox(height: 12),
            _dropdown(
              label: 'Account Type',
              icon: Icons.category_outlined,
              value: _selectedAccountType,
              options: _accountTypeOptions,
              onChanged: (value) {
                setState(() => _selectedAccountType = value);
              },
            ),
            const SizedBox(height: 12),
            _dropdown(
              label: 'Account Subtype',
              icon: Icons.tune_outlined,
              value: _selectedAccountSubtype,
              options: _accountSubtypeOptions,
              onChanged: (value) {
                setState(() => _selectedAccountSubtype = value);
              },
            ),
            const SizedBox(height: 12),
            _dropdown(
              label: 'Company',
              icon: Icons.corporate_fare_outlined,
              value: _selectedCompany,
              options: _companyOptions,
              onChanged: (value) {
                setState(() => _selectedCompany = value);
              },
            ),
            const SizedBox(height: 12),
            _dropdown(
              label: 'Party Type',
              icon: Icons.apartment_outlined,
              value: _selectedPartyType,
              options: _partyTypeOptions,
              onChanged: (value) {
                setState(() => _selectedPartyType = value);
                _loadPartyOptions(value);
              },
            ),
            const SizedBox(height: 12),
            _dropdown(
              label: 'Party',
              icon: Icons.people_outline,
              value: _selectedParty,
              options: _partyOptions,
              onChanged: (value) {
                setState(() => _selectedParty = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ibanCtrl,
              decoration: const InputDecoration(
                labelText: 'IBAN',
                prefixIcon: Icon(Icons.credit_card_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _branchCodeCtrl,
              decoration: const InputDecoration(
                labelText: 'Branch Code',
                prefixIcon: Icon(Icons.qr_code_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bankAccountNoCtrl,
              decoration: const InputDecoration(
                labelText: 'Bank Account No',
                prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lastIntegrationDateCtrl,
              readOnly: true,
              onTap: _pickDate,
              decoration: const InputDecoration(
                labelText: 'Last Integration Date',
                prefixIcon: Icon(Icons.calendar_month_outlined),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Disabled'),
              value: _disabled,
              onChanged: (value) => setState(() => _disabled = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Is Default'),
              value: _isDefault,
              onChanged: (value) => setState(() => _isDefault = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Is Company Account'),
              value: _isCompanyAccount,
              onChanged: (value) => setState(() => _isCompanyAccount = value),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: (_busy || !_ready) ? null : _submit,
              child: const Text('Save Bank Details'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required IconData icon,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: options.contains(value) ? value : null,
      items: options
          .map(
            (item) => DropdownMenuItem<String>(value: item, child: Text(item)),
          )
          .toList(),
      onChanged: options.isEmpty ? null : onChanged,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    );
  }
}
