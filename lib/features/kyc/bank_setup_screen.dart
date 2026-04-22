import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/skeleton_loader.dart';

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
  final TextEditingController _partyCtrl = TextEditingController();
  Map<String, String> _linkDoctypeByField = <String, String>{};

  String? _selectedBank;
  String? _selectedCompanyAccount;
  String? _selectedAccountType;
  String? _selectedAccountSubtype;
  String? _selectedCompany;
  String? _selectedPartyType;
  String? _selectedParty;

  bool _busy = false;
  bool _ready = false;
  bool _editMode = false;

  bool get _canSubmit =>
      _ready &&
      !_busy &&
      _accountNameCtrl.text.trim().isNotEmpty &&
      _branchCodeCtrl.text.trim().isNotEmpty &&
      (_selectedBank?.trim().isNotEmpty == true);

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
    _partyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    final app = AppScope.of(context);
    final Map<String, String> linkDoctypeByField = await app
        .fetchBankAccountLinkDoctypes();
    await app.hydrateBankFromBackend();
    if (!mounted) {
      return;
    }

    final Map<String, dynamic>? bankData = app.submittedBankRaw;
    setState(() {
      _linkDoctypeByField = linkDoctypeByField;
      if (bankData != null) {
        _accountNameCtrl.text = bankData['account_name']?.toString() ?? '';
        _selectedBank = bankData['bank']?.toString();
        _selectedCompanyAccount = bankData['account']?.toString();
        _selectedAccountType = bankData['account_type']?.toString();
        _selectedAccountSubtype = bankData['account_subtype']?.toString();
        _selectedCompany = bankData['company']?.toString();
        _selectedPartyType = bankData['party_type']?.toString();
        _selectedParty = bankData['party']?.toString();
        _partyCtrl.text = _selectedParty ?? '';
        _ibanCtrl.text = bankData['iban']?.toString() ?? '';
        _branchCodeCtrl.text = bankData['branch_code']?.toString() ?? '';
        _bankAccountNoCtrl.text = bankData['bank_account_no']?.toString() ?? '';
        _lastIntegrationDateCtrl.text =
            bankData['last_integration_date']?.toString() ?? '';
      }
      _ready = true;
    });
  }

  String? _doctypeForField(String fieldname) {
    final String? configured = _linkDoctypeByField[fieldname];
    if (fieldname == 'account') {
      return 'Account';
    }
    if (configured == null || configured.trim().isEmpty) {
      return null;
    }
    return configured.trim();
  }

  Future<String?> _openLinkPicker({
    required String title,
    required String doctype,
    String? initialQuery,
    Map<String, dynamic>? filters,
    int pageLength = 10,
  }) async {
    final app = AppScope.of(context);
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) => _LinkSearchBottomSheet(
        title: title,
        initialQuery: initialQuery,
        onSearch: (String query) {
          return app.fetchLinkOptions(
            doctype: doctype,
            query: query,
            pageLength: pageLength,
            filters: filters,
          );
        },
      ),
    );
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
      disabled: false,
      isDefault: false,
      isCompanyAccount: false,
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
    if (!_ready) {
      return AppShell(
        title: 'Bank Account Setup',
        subtitle: 'Loading bank details…',
        child: FrostCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(8, (_) => const SkeletonFormField()),
          ),
        ),
      );
    }

    final dynamic args = ModalRoute.of(context)?.settings.arguments;
    final bool forceEdit =
        args is Map<String, dynamic> && args['force_edit'] == true;
    final app = AppScope.of(context);
    final Map<String, dynamic>? bankData = app.submittedBankRaw;
    final bool showSubmittedDetails =
        !_editMode && !forceEdit && bankData != null && bankData.isNotEmpty;
    if (showSubmittedDetails) {
      final Map<String, String> displayData = _buildDisplayData(bankData);
      final String title =
          bankData['account_name']?.toString().trim().isNotEmpty == true
          ? bankData['account_name']!.toString().trim()
          : 'Bank Account Details';
      return AppShell(
        title: title,
        subtitle: 'Submitted bank account details',
        child: FrostCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in displayData.entries) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 150,
                      child: Text(
                        entry.key,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
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
              ElevatedButton.icon(
                onPressed: () {
                  setState(() => _editMode = true);
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit Bank Details'),
              ),
            ],
          ),
        ),
      );
    }

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
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Account Name *',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            _linkField(
              label: 'Bank *',
              icon: Icons.account_balance_outlined,
              value: _selectedBank,
              doctype: _doctypeForField('bank'),
              onChanged: (String value) {
                setState(() => _selectedBank = value);
              },
            ),
            const SizedBox(height: 12),
            _linkField(
              label: 'Company Account',
              icon: Icons.business_center_outlined,
              value: _selectedCompanyAccount,
              doctype: _doctypeForField('account'),
              filters: const <String, dynamic>{
                'account_type': 'Bank',
                'company': 'LyncSpace',
                'is_group': 0,
              },
              pageLength: 10,
              onChanged: (String value) {
                setState(() => _selectedCompanyAccount = value);
              },
            ),
            const SizedBox(height: 12),
            _linkField(
              label: 'Account Type',
              icon: Icons.category_outlined,
              value: _selectedAccountType,
              doctype: _doctypeForField('account_type'),
              onChanged: (String value) {
                setState(() => _selectedAccountType = value);
              },
            ),
            const SizedBox(height: 12),
            _linkField(
              label: 'Account Subtype',
              icon: Icons.tune_outlined,
              value: _selectedAccountSubtype,
              doctype: _doctypeForField('account_subtype'),
              onChanged: (String value) {
                setState(() => _selectedAccountSubtype = value);
              },
            ),
            const SizedBox(height: 12),
            _linkField(
              label: 'Company',
              icon: Icons.corporate_fare_outlined,
              value: _selectedCompany,
              doctype: _doctypeForField('company'),
              onChanged: (String value) {
                setState(() => _selectedCompany = value);
              },
            ),
            const SizedBox(height: 12),
            _linkField(
              label: 'Party Type',
              icon: Icons.apartment_outlined,
              value: _selectedPartyType,
              doctype: _doctypeForField('party_type'),
              onChanged: (String value) {
                setState(() {
                  _selectedPartyType = value;
                  _selectedParty = null;
                  _partyCtrl.clear();
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _partyCtrl,
              onChanged: (String value) {
                setState(
                  () => _selectedParty = value.trim().isEmpty ? null : value,
                );
              },
              decoration: const InputDecoration(
                labelText: 'Party',
                prefixIcon: Icon(Icons.people_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ibanCtrl,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 ]')),
                LengthLimitingTextInputFormatter(34),
              ],
              decoration: const InputDecoration(
                labelText: 'IBAN',
                prefixIcon: Icon(Icons.credit_card_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _branchCodeCtrl,
              onChanged: (_) => setState(() {}),
              textCapitalization: TextCapitalization.characters,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
                LengthLimitingTextInputFormatter(20),
              ],
              decoration: const InputDecoration(
                labelText: 'Branch Code *',
                prefixIcon: Icon(Icons.qr_code_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bankAccountNoCtrl,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
                LengthLimitingTextInputFormatter(34),
              ],
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
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _canSubmit ? _submit : null,
              child: const Text('Save Bank Details'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _linkField({
    required String label,
    required IconData icon,
    required String? value,
    required String? doctype,
    required ValueChanged<String> onChanged,
    bool enabled = true,
    Map<String, dynamic>? filters,
    int pageLength = 10,
  }) {
    final bool canOpen =
        enabled && doctype != null && doctype.trim().isNotEmpty;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: !canOpen
          ? null
          : () async {
              final String? selected = await _openLinkPicker(
                title: label,
                doctype: doctype.trim(),
                initialQuery: value,
                filters: filters,
                pageLength: pageLength,
              );
              if (selected == null || !mounted) {
                return;
              }
              onChanged(selected);
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
        ),
        child: Text(
          value?.trim().isNotEmpty == true
              ? value!
              : canOpen
              ? 'Tap to search and select'
              : 'Field unavailable',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: value?.trim().isNotEmpty == true
                ? null
                : Theme.of(context).hintColor,
          ),
        ),
      ),
    );
  }

  Map<String, String> _buildDisplayData(Map<String, dynamic> raw) {
    final Map<String, String> data = <String, String>{};

    void put(String label, String key) {
      final String value = (raw[key]?.toString() ?? '').trim();
      if (value.isNotEmpty) {
        data[label] = value;
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

    data['Disabled'] = raw['disabled']?.toString() == '1' ? 'Yes' : 'No';
    data['Is Default'] = raw['is_default']?.toString() == '1' ? 'Yes' : 'No';
    data['Is Company Account'] = raw['is_company_account']?.toString() == '1'
        ? 'Yes'
        : 'No';

    return data;
  }
}

class _LinkSearchBottomSheet extends StatefulWidget {
  const _LinkSearchBottomSheet({
    required this.title,
    required this.onSearch,
    this.initialQuery,
  });

  final String title;
  final String? initialQuery;
  final Future<List<String>> Function(String query) onSearch;

  @override
  State<_LinkSearchBottomSheet> createState() => _LinkSearchBottomSheetState();
}

class _LinkSearchBottomSheetState extends State<_LinkSearchBottomSheet> {
  late final TextEditingController _queryCtrl;
  Timer? _debounce;
  List<String> _results = <String>[];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _queryCtrl = TextEditingController(text: widget.initialQuery ?? '');
    _load(_queryCtrl.text.trim(), showLoading: false);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryCtrl.dispose();
    super.dispose();
  }

  Widget _buildResults(BuildContext context) {
    final String typed = _queryCtrl.text.trim();
    if (_results.isNotEmpty) {
      return ListView.builder(
        itemCount: _results.length,
        itemBuilder: (BuildContext context, int index) {
          final String item = _results[index];
          return ListTile(
            dense: true,
            title: Text(item, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => Navigator.of(context).pop(item),
          );
        },
      );
    }
    // No results from API (possibly 403 or genuinely empty).
    // Let the user confirm whatever they've typed as a free-text value.
    if (typed.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            dense: true,
            leading: const Icon(Icons.check_circle_outline),
            title: Text(
              'Use "$typed"',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => Navigator.of(context).pop(typed),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'No matching records found. You can use the typed value above.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        ],
      );
    }
    return const Center(child: Text('No results found'));
  }

  Future<void> _load(String query, {bool showLoading = true}) async {
    if (showLoading) {
      setState(() => _loading = true);
    }
    final List<String> values = await widget.onSearch(query);
    if (!mounted) {
      return;
    }
    setState(() {
      _results = values;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.82,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _queryCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Search',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (String value) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), () {
                    _load(value.trim());
                  });
                },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const _BankSearchLoading()
                    : _buildResults(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BankSearchLoading extends StatelessWidget {
  const _BankSearchLoading();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: SkeletonLoader(itemCount: 5, spacing: 4),
    );
  }
}
