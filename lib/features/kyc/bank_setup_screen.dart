import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/context_colors.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/app_bottom_sheet.dart';
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
  final TextEditingController _bankAccountNoCtrl = TextEditingController();
  final TextEditingController _confirmAccountNoCtrl = TextEditingController();
  final TextEditingController _branchCodeCtrl = TextEditingController();
  final TextEditingController _branchNameCtrl = TextEditingController();
  final TextEditingController _ibanCtrl = TextEditingController();

  String? _selectedBank;
  String? _selectedAccountType;

  final _formKey = GlobalKey<FormState>();

  bool _obscureAccountNo = true;
  bool _busy = false;
  bool _ready = false;
  bool _fetchingBranch = false;
  bool _branchAutoFilled = false;
  String? _ifscLookupError;

  bool get _canSubmit =>
      _ready &&
      !_busy &&
      _accountNameCtrl.text.trim().isNotEmpty &&
      _selectedBank?.trim().isNotEmpty == true &&
      _bankAccountNoCtrl.text.trim().isNotEmpty &&
      _confirmAccountNoCtrl.text.trim() == _bankAccountNoCtrl.text.trim() &&
      _branchCodeCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _accountNameCtrl.dispose();
    _bankAccountNoCtrl.dispose();
    _confirmAccountNoCtrl.dispose();
    _branchCodeCtrl.dispose();
    _branchNameCtrl.dispose();
    _ibanCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final app = AppScope.of(context);
    await Future.wait([
      app.hydrateBankFromBackend(),
      app.fetchBankFormOptions(),
    ]);
    if (!mounted) return;

    final Map<String, dynamic>? bankData = app.submittedBankRaw;
    setState(() {
      if (bankData != null) {
        _accountNameCtrl.text = bankData['account_name']?.toString() ?? '';
        _selectedBank = bankData['bank']?.toString();
        _selectedAccountType = bankData['account_type']?.toString();
        _ibanCtrl.text = bankData['iban']?.toString() ?? '';
        _branchCodeCtrl.text = bankData['branch_code']?.toString() ?? '';
        _branchNameCtrl.text = bankData['branch_name']?.toString() ?? '';
        final String accountNo =
            bankData['bank_account_no']?.toString() ?? '';
        _bankAccountNoCtrl.text = accountNo;
        // Pre-fill confirm so the form doesn't immediately show an error.
        _confirmAccountNoCtrl.text = accountNo;
      }
      _ready = true;
    });
  }

  Future<String?> _pickBank() async {
    final app = AppScope.of(context);
    return showAppBottomSheet<String>(
      context: context,
      builder: (BuildContext sheetCtx) => _LinkSearchBottomSheet(
        title: 'Bank',
        initialQuery: _selectedBank,
        onSearch: (String q) =>
            app.fetchLinkOptions(doctype: 'Bank', query: q, pageLength: 10),
      ),
    );
  }

  Future<String?> _pickAccountType() async {
    final app = AppScope.of(context);
    final List<String> options = app.bankAccountTypeOptions;
    if (options.isEmpty) return null;
    return showAppBottomSheet<String>(
      context: context,
      builder: (BuildContext sheetCtx) => _LinkSearchBottomSheet(
        title: 'Account Type',
        initialQuery: _selectedAccountType,
        onSearch: (String q) async {
          final String query = q.trim().toLowerCase();
          if (query.isEmpty) return options;
          return options
              .where((String o) => o.toLowerCase().contains(query))
              .toList();
        },
      ),
    );
  }

  Future<void> _lookupIfsc(String raw) async {
    final String code = raw.trim().toUpperCase();

    // Reset auto-fill when the user edits the IFSC back to an incomplete value.
    if (code.length < 11) {
      if (_branchAutoFilled || _ifscLookupError != null) {
        setState(() {
          _branchAutoFilled = false;
          _ifscLookupError = null;
          _branchNameCtrl.clear();
        });
      }
      return;
    }

    setState(() {
      _fetchingBranch = true;
      _ifscLookupError = null;
    });

    try {
      final Uri uri = Uri.parse('https://ifsc.razorpay.com/$code');
      final http.Response response =
          await http.get(uri).timeout(const Duration(seconds: 8));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;
        final String branch =
            (data['BRANCH'] as String? ?? '').trim().toLowerCase().split(' ').map(
              (w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}',
            ).join(' ');
        setState(() {
          _fetchingBranch = false;
          _branchAutoFilled = branch.isNotEmpty;
          _branchNameCtrl.text = branch;
          _ifscLookupError = null;
        });
      } else {
        setState(() {
          _fetchingBranch = false;
          _branchAutoFilled = false;
          _branchNameCtrl.clear();
          _ifscLookupError = 'IFSC not found — please check and try again';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _fetchingBranch = false;
        _ifscLookupError = 'Could not verify IFSC — check your connection';
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final app = AppScope.of(context);
    setState(() => _busy = true);

    final String? error = await app.submitBankDetails(
      accountName: _accountNameCtrl.text,
      bank: _selectedBank ?? '',
      accountType: _selectedAccountType,
      iban: _ibanCtrl.text,
      branchCode: _branchCodeCtrl.text,
      branchName: _branchNameCtrl.text,
      bankAccountNo: _bankAccountNoCtrl.text,
      confirmAccountNo: _confirmAccountNoCtrl.text,
      // Internal fields — always auto-managed, never exposed to the UI.
      isDefault: true,
      isCompanyAccount: false,
      disabled: false,
    );

    if (!mounted) return;
    setState(() => _busy = false);

    if (error != null) {
      showInfoSnack(context, error);
      return;
    }

    showInfoSnack(context, 'Bank details saved successfully');
    Navigator.of(context).pushNamed(AppRoutes.permission);
  }

  @override
  Widget build(BuildContext context) {
    final dynamic args = ModalRoute.of(context)?.settings.arguments;
    final bool forceEdit =
        args is Map<String, dynamic> && args['force_edit'] == true;
    final app = AppScope.of(context);
    final Map<String, dynamic>? bankData = app.submittedBankRaw;

    if (_ready && !forceEdit && bankData != null && bankData.isNotEmpty) {
      return BankSubmittedDetailsScreen(bankData: bankData);
    }

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KycHeader(
                  title: 'Bank Details',
                  subtitle: 'Enter your bank account information',
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
                            padding:
                                const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            children: [
                              const KycSectionHeading('Account Details'),
                              // ── Account Holder Name ─────────────────
                              KycFieldCard(
                                icon: Icons.person_outline_rounded,
                                label: 'Account Holder Name *',
                                child: _textField(
                                  controller: _accountNameCtrl,
                                  hint: 'As printed on your passbook',
                                  textCapitalization:
                                      TextCapitalization.words,
                                  onChanged: (_) => setState(() {}),
                                  validator: validateAccountHolderName,
                                ),
                              ),
                              // ── Bank ────────────────────────────────
                              _bankPickerCard(),
                              // ── Account Type ────────────────────────
                              _accountTypeCard(),
                              const SizedBox(height: 8),
                              const KycSectionHeading('Bank Details'),
                              // ── Account Number ──────────────────────
                              KycFieldCard(
                                icon: Icons.account_balance_wallet_outlined,
                                label: 'Account Number *',
                                trailing: _visibilityToggle(),
                                child: _textField(
                                  controller: _bankAccountNoCtrl,
                                  hint: 'Enter account number',
                                  keyboardType: TextInputType.number,
                                  obscureText: _obscureAccountNo,
                                  onChanged: (_) => setState(() {}),
                                  validator: validateRequiredBankAccountNo,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(18),
                                  ],
                                ),
                              ),
                              // ── Confirm Account Number ───────────────
                              KycFieldCard(
                                icon: Icons.verified_outlined,
                                label: 'Confirm Account Number *',
                                trailing: _visibilityToggle(),
                                child: _textField(
                                  controller: _confirmAccountNoCtrl,
                                  hint: 'Re-enter account number',
                                  keyboardType: TextInputType.number,
                                  obscureText: _obscureAccountNo,
                                  onChanged: (_) => setState(() {}),
                                  validator: _validateConfirm,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(18),
                                  ],
                                ),
                              ),
                              // ── IFSC Code ───────────────────────────
                              KycFieldCard(
                                icon: Icons.qr_code_rounded,
                                label: 'IFSC Code *',
                                trailing: _ifscTrailing(),
                                child: _textField(
                                  controller: _branchCodeCtrl,
                                  hint: 'e.g. SBIN0001234',
                                  onChanged: (v) {
                                    setState(() {});
                                    _lookupIfsc(v);
                                  },
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  validator: validateBranchCode,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'[A-Za-z0-9]')),
                                    LengthLimitingTextInputFormatter(11),
                                  ],
                                ),
                              ),
                              if (_ifscLookupError != null)
                                Padding(
                                  padding: const EdgeInsets.only(
                                      left: 6, bottom: 6, top: 0),
                                  child: Text(
                                    _ifscLookupError!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: context.danger,
                                    ),
                                  ),
                                ),
                              // ── Branch Name (auto-filled from IFSC) ─
                              KycFieldCard(
                                icon: Icons.location_city_outlined,
                                label: 'Branch Name',
                                trailing: _branchAutoFilled
                                    ? GestureDetector(
                                        onTap: () => setState(() {
                                          _branchAutoFilled = false;
                                          _branchNameCtrl.clear();
                                        }),
                                        child: Icon(
                                          Icons.close_rounded,
                                          size: 18,
                                          color: context.textTertiary,
                                        ),
                                      )
                                    : null,
                                child: _textField(
                                  controller: _branchNameCtrl,
                                  hint: 'Auto-filled from IFSC code',
                                  textCapitalization:
                                      TextCapitalization.words,
                                  readOnly: _branchAutoFilled,
                                ),
                              ),
                              // ── IBAN (optional) ─────────────────────
                              KycFieldCard(
                                icon: Icons.credit_card_outlined,
                                label: 'IBAN',
                                child: _textField(
                                  controller: _ibanCtrl,
                                  hint: 'Optional — for international transfers',
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  validator: validateIBAN,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'[A-Za-z0-9 ]')),
                                    LengthLimitingTextInputFormatter(34),
                                  ],
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

  // ── Private helpers ──────────────────────────────────────────────────────

  String? _validateConfirm(String? v) {
    if (v == null || v.trim().isEmpty) {
      return 'Please confirm your account number';
    }
    if (v.trim() != _bankAccountNoCtrl.text.trim()) {
      return 'Account numbers do not match';
    }
    return null;
  }

  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: List.generate(6, (_) => const SkeletonFormField()),
    );
  }

  Widget _bankPickerCard() {
    final bool hasValue = _selectedBank?.trim().isNotEmpty == true;
    return KycFieldCard(
      icon: Icons.account_balance_outlined,
      label: 'Bank *',
      trailing: Icon(
        Icons.keyboard_arrow_down_rounded,
        color: context.textTertiary,
      ),
      onTap: () async {
        final String? selected = await _pickBank();
        if (selected == null || !mounted) return;
        setState(() => _selectedBank = selected);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          hasValue ? _selectedBank! : 'Tap to search and select your bank',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: hasValue ? FontWeight.w500 : FontWeight.w400,
            color: hasValue
                ? context.textPrimary
                : context.textTertiary,
          ),
        ),
      ),
    );
  }

  Widget _accountTypeCard() {
    final bool hasValue = _selectedAccountType?.trim().isNotEmpty == true;
    final bool canOpen = AppScope.of(context).bankAccountTypeOptions.isNotEmpty;
    return KycFieldCard(
      icon: Icons.account_balance_rounded,
      label: 'Account Type',
      trailing: Icon(
        Icons.keyboard_arrow_down_rounded,
        color: context.textTertiary,
      ),
      onTap: !canOpen
          ? null
          : () async {
              final String? selected = await _pickAccountType();
              if (selected == null || !mounted) return;
              setState(() => _selectedAccountType = selected);
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          hasValue
              ? _selectedAccountType!
              : canOpen
                  ? 'Tap to search and select'
                  : 'Tap to select',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: hasValue ? FontWeight.w500 : FontWeight.w400,
            color: hasValue
                ? context.textPrimary
                : context.textTertiary,
          ),
        ),
      ),
    );
  }

  Widget? _ifscTrailing() {
    if (_fetchingBranch) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: kKycAccent,
        ),
      );
    }
    if (_branchAutoFilled) {
      return const Icon(
        Icons.check_circle_rounded,
        color: kKycAccent,
        size: 20,
      );
    }
    if (_ifscLookupError != null) {
      return Icon(
        Icons.error_outline_rounded,
        color: context.danger,
        size: 20,
      );
    }
    return null;
  }

  Widget _visibilityToggle() {
    return GestureDetector(
      onTap: () => setState(() => _obscureAccountNo = !_obscureAccountNo),
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Icon(
          _obscureAccountNo
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          size: 20,
          color: context.textTertiary,
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool obscureText = false,
    bool readOnly = false,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      obscureText: obscureText,
      readOnly: readOnly,
      validator: validator,
      onChanged: onChanged,
      inputFormatters: inputFormatters,
      style: kycInputStyle(context).copyWith(
        color: readOnly
            ? context.textSecondary
            : context.textPrimary,
      ),
      decoration: kycHintDecoration(context, hint),
    );
  }
}

// ── Bank search bottom sheet ────────────────────────────────────────────────

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

  Future<void> _load(String query, {bool showLoading = true}) async {
    if (showLoading) setState(() => _loading = true);
    final List<String> values = await widget.onSearch(query);
    if (!mounted) return;
    setState(() {
      _results = values;
      _loading = false;
    });
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
                color: context.textSecondary,
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
                return KycResultTile(
                  label: item,
                  selected: item == widget.initialQuery,
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
            _emptyIcon(Icons.search_off_rounded),
            const SizedBox(height: 14),
            Text(
              'No matching records',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'You can still use what you typed.',
              style: TextStyle(
                fontSize: 13,
                color: context.textSecondary,
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
          _emptyIcon(Icons.search_rounded),
          const SizedBox(height: 14),
          Text(
            'Start typing to search',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyIcon(IconData icon) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: KycColors.accentSoft(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: kKycAccent, size: 28),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final double resultsMaxHeight =
        (mq.size.height - mq.viewInsets.bottom - mq.padding.top) * 0.40;

    return AppBottomSheet(
      padding: EdgeInsets.zero,
      title: widget.title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: KycSearchInput(
              controller: _queryCtrl,
              autofocus: true,
              hint:
                  'Search ${widget.title.replaceAll('*', '').trim().toLowerCase()}',
              onChanged: (String value) {
                _debounce?.cancel();
                _debounce = Timer(
                  const Duration(milliseconds: 300),
                  () => _load(value.trim()),
                );
              },
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: resultsMaxHeight),
            child: _loading
                ? const _BankSearchLoading()
                : _buildResults(context),
          ),
        ],
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
