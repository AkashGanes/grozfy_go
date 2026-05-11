import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/skeleton_loader.dart';
import 'bank_submitted_details_screen.dart';
import 'widgets/kyc_form_widgets.dart';

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

  final _formKey = GlobalKey<FormState>();

  bool _disabled = false;
  bool _isDefault = false;
  bool _isCompanyAccount = false;
  bool _busy = false;
  bool _ready = false;

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
      backgroundColor: KycColors.cardBg(context),
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
    if (!_formKey.currentState!.validate()) return;
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
    final dynamic args = ModalRoute.of(context)?.settings.arguments;
    final bool forceEdit =
        args is Map<String, dynamic> && args['force_edit'] == true;
    final app = AppScope.of(context);
    final Map<String, dynamic>? bankData = app.submittedBankRaw;

    // Bank already submitted — show read-only details screen immediately.
    if (_ready && !forceEdit && bankData != null && bankData.isNotEmpty) {
      return BankSubmittedDetailsScreen(bankData: bankData);
    }

    return Scaffold(
      backgroundColor: KycColors.pageBg(context),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KycHeader(
                  title: 'Bank Account Setup',
                  subtitle: 'Bank Account DocType fields from ERP',
                  icon: Icons.account_balance_outlined,
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: !_ready
                      ? _buildSkeleton()
                      : Form(
                          key: _formKey,
                          autovalidateMode:
                              AutovalidateMode.onUserInteraction,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            children: [
                              const KycSectionHeading('Account Details'),
                              KycFieldCard(
                                icon: Icons.person_outline_rounded,
                                label: 'Account Name *',
                                child: _baseTextField(
                                  controller: _accountNameCtrl,
                                  hint: 'Enter account name',
                                  onChanged: (_) => setState(() {}),
                                  validator: requiredField,
                                ),
                              ),
                              _linkFieldCard(
                                label: 'Bank *',
                                icon: Icons.account_balance_outlined,
                                value: _selectedBank,
                                doctype: _doctypeForField('bank'),
                                onChanged: (v) =>
                                    setState(() => _selectedBank = v),
                              ),
                              _linkFieldCard(
                                label: 'Company Account',
                                icon: Icons.business_center_outlined,
                                value: _selectedCompanyAccount,
                                doctype: _doctypeForField('account'),
                                filters: const <String, dynamic>{
                                  'account_type': 'Bank',
                                  'company': 'LyncSpace',
                                  'is_group': 0,
                                },
                                onChanged: (v) => setState(
                                    () => _selectedCompanyAccount = v),
                              ),
                              _linkFieldCard(
                                label: 'Account Type',
                                icon: Icons.category_outlined,
                                value: _selectedAccountType,
                                doctype: _doctypeForField('account_type'),
                                onChanged: (v) =>
                                    setState(() => _selectedAccountType = v),
                              ),
                              _linkFieldCard(
                                label: 'Account Subtype',
                                icon: Icons.tune_outlined,
                                value: _selectedAccountSubtype,
                                doctype: _doctypeForField('account_subtype'),
                                onChanged: (v) => setState(
                                    () => _selectedAccountSubtype = v),
                              ),
                              const SizedBox(height: 8),
                              const KycSectionHeading('Company & Party'),
                              _linkFieldCard(
                                label: 'Company',
                                icon: Icons.corporate_fare_outlined,
                                value: _selectedCompany,
                                doctype: _doctypeForField('company'),
                                onChanged: (v) =>
                                    setState(() => _selectedCompany = v),
                              ),
                              _linkFieldCard(
                                label: 'Party Type',
                                icon: Icons.apartment_outlined,
                                value: _selectedPartyType,
                                doctype: _doctypeForField('party_type'),
                                onChanged: (v) {
                                  setState(() {
                                    _selectedPartyType = v;
                                    _selectedParty = null;
                                    _partyCtrl.clear();
                                  });
                                },
                              ),
                              KycFieldCard(
                                icon: Icons.people_outline,
                                label: 'Party',
                                child: _baseTextField(
                                  controller: _partyCtrl,
                                  hint: 'Enter party',
                                  onChanged: (value) {
                                    setState(() => _selectedParty =
                                        value.trim().isEmpty ? null : value);
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                              const KycSectionHeading('Bank Details'),
                              KycFieldCard(
                                icon: Icons.credit_card_outlined,
                                label: 'IBAN',
                                child: _baseTextField(
                                  controller: _ibanCtrl,
                                  hint: 'Enter IBAN',
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  validator: validateIBAN,
                                  inputFormatters: <TextInputFormatter>[
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'[A-Za-z0-9 ]')),
                                    LengthLimitingTextInputFormatter(34),
                                  ],
                                ),
                              ),
                              KycFieldCard(
                                icon: Icons.qr_code_rounded,
                                label: 'Branch Code (IFSC) *',
                                child: _baseTextField(
                                  controller: _branchCodeCtrl,
                                  hint: 'Enter IFSC code',
                                  onChanged: (_) => setState(() {}),
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  validator: validateBranchCode,
                                  inputFormatters: <TextInputFormatter>[
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'[A-Za-z0-9]')),
                                    LengthLimitingTextInputFormatter(11),
                                  ],
                                ),
                              ),
                              KycFieldCard(
                                icon: Icons.account_balance_wallet_outlined,
                                label: 'Bank Account No',
                                child: _baseTextField(
                                  controller: _bankAccountNoCtrl,
                                  hint: 'Enter bank account number',
                                  keyboardType: TextInputType.number,
                                  validator: validateBankAccountNo,
                                  inputFormatters: <TextInputFormatter>[
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(18),
                                  ],
                                ),
                              ),
                              KycFieldCard(
                                icon: Icons.calendar_month_outlined,
                                label: 'Last Integration Date',
                                trailing: Icon(
                                  Icons.calendar_today_outlined,
                                  color: KycColors.textHint(context),
                                  size: 20,
                                ),
                                onTap: _pickDate,
                                child: _readonlyText(
                                  _lastIntegrationDateCtrl,
                                  'Select date',
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                KycPrimaryButton(
                  label: 'Save Bank Details',
                  onPressed: _canSubmit ? _submit : null,
                ),
              ],
            ),
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black26,
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(kKycAccent),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: List.generate(8, (_) => const SkeletonFormField()),
    );
  }

  Widget _linkFieldCard({
    required String label,
    required IconData icon,
    required String? value,
    required String? doctype,
    required ValueChanged<String> onChanged,
    Map<String, dynamic>? filters,
    int pageLength = 10,
  }) {
    final bool canOpen = doctype != null && doctype.trim().isNotEmpty;
    final bool hasValue = value?.trim().isNotEmpty == true;
    return KycFieldCard(
      icon: icon,
      label: label,
      trailing: Icon(
        Icons.keyboard_arrow_down_rounded,
        color: KycColors.textHint(context),
      ),
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
              if (selected == null || !mounted) return;
              onChanged(selected);
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          hasValue
              ? value!
              : canOpen
                  ? 'Tap to search and select'
                  : 'Field unavailable',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: hasValue ? FontWeight.w500 : FontWeight.w400,
            color: hasValue ? KycColors.textPrimary(context) : KycColors.textHint(context),
          ),
        ),
      ),
    );
  }

  Widget _baseTextField({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      validator: validator,
      onChanged: onChanged,
      inputFormatters: inputFormatters,
      style: kycInputStyle(context),
      decoration: kycHintDecoration(hint),
    );
  }

  Widget _readonlyText(TextEditingController controller, String hint) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      enableInteractiveSelection: false,
      style: kycInputStyle(context),
      decoration: kycHintDecoration(hint),
    );
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
            child: Text(
              '${_results.length} ${_results.length == 1 ? 'result' : 'results'}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: KycColors.textSecondary(context),
                letterSpacing: 0.4,
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              itemCount: _results.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (BuildContext context, int index) {
                final String item = _results[index];
                final selected = item == widget.initialQuery;
                return KycResultTile(
                  label: item,
                  selected: selected,
                  onTap: () => Navigator.of(context).pop(item),
                );
              },
            ),
          ),
        ],
      );
    }
    if (typed.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: KycColors.accentSoft(context),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.search_off_rounded,
                color: kKycAccent,
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'No matching records',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: KycColors.textPrimary(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'You can still use what you typed.',
              style: TextStyle(
                fontSize: 13,
                color: KycColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(typed),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(
                  'Use "$typed"',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kKycAccent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: KycColors.accentSoft(context),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.search_rounded,
              color: kKycAccent,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Start typing to search',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: KycColors.textPrimary(context),
            ),
          ),
        ],
      ),
    );
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
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.82,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: KycColors.sheetGrabber(context),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: KycColors.textPrimary(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: KycSearchInput(
                  controller: _queryCtrl,
                  autofocus: true,
                  hint: 'Search '
                      '${widget.title.replaceAll('*', '').trim().toLowerCase()}',
                  onChanged: (String value) {
                    _debounce?.cancel();
                    _debounce = Timer(
                      const Duration(milliseconds: 300),
                      () => _load(value.trim()),
                    );
                  },
                ),
              ),
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

