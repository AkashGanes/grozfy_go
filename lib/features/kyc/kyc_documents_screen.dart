import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/api_constants.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_controller.dart';
import '../../core/state/providers.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/app_shell.dart';
import 'widgets/kyc_form_widgets.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum _DocFilter { all, uploaded, missing, expired }

enum _DocStatus { missing, uploaded, expired, reuploadRequired }

extension _DocStatusStyle on _DocStatus {
  String get label => switch (this) {
    _DocStatus.missing => 'Missing',
    _DocStatus.uploaded => 'Uploaded',
    _DocStatus.expired => 'Expired',
    _DocStatus.reuploadRequired => 'Re-upload Required',
  };

  Color get color => switch (this) {
    _DocStatus.missing => const Color(0xFF98A2B3),
    _DocStatus.uploaded => const Color(0xFF1AB36A),
    _DocStatus.expired => const Color(0xFFE53935),
    _DocStatus.reuploadRequired => const Color(0xFFE57700),
  };

  Color get bgColor => switch (this) {
    _DocStatus.missing => const Color(0xFFF2F4F7),
    _DocStatus.uploaded => const Color(0xFFE6F9F1),
    _DocStatus.expired => const Color(0xFFFEECEB),
    _DocStatus.reuploadRequired => const Color(0xFFFFF3E0),
  };

  IconData get icon => switch (this) {
    _DocStatus.missing => Icons.upload_rounded,
    _DocStatus.uploaded => Icons.check_circle_rounded,
    _DocStatus.expired => Icons.error_rounded,
    _DocStatus.reuploadRequired => Icons.warning_rounded,
  };
}

// ─── Data class ───────────────────────────────────────────────────────────────

class _DocEntry {
  const _DocEntry({
    required this.field,
    required this.label,
    required this.icon,
    required this.editable,
    required this.isRequired,
    this.number,
    this.pickedPath,
    this.existingUrl,
    this.issuingDate,
    this.expiryDate,
    this.isReuploadRequired = false,
  });

  final String field;
  final String label;
  final IconData icon;
  final bool editable;
  final bool isRequired;
  final String? number;
  final String? pickedPath;
  final String? existingUrl;
  final DateTime? issuingDate;
  final DateTime? expiryDate;
  final bool isReuploadRequired;

  bool get hasFile => pickedPath != null || (existingUrl ?? '').isNotEmpty;

  _DocStatus get status {
    if (isReuploadRequired) return _DocStatus.reuploadRequired;
    if (!hasFile) return _DocStatus.missing;
    if (expiryDate != null && expiryDate!.isBefore(DateTime.now())) {
      return _DocStatus.expired;
    }
    return _DocStatus.uploaded;
  }

  bool matchesFilter(_DocFilter f) => switch (f) {
    _DocFilter.all => true,
    _DocFilter.uploaded => status == _DocStatus.uploaded,
    _DocFilter.missing => status == _DocStatus.missing,
    _DocFilter.expired =>
      status == _DocStatus.expired || status == _DocStatus.reuploadRequired,
  };
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class KycDocumentsScreen extends ConsumerStatefulWidget {
  const KycDocumentsScreen({super.key, this.licenseReuploadMode = false});

  final bool licenseReuploadMode;

  @override
  ConsumerState<KycDocumentsScreen> createState() => _KycDocumentsScreenState();
}

class _KycDocumentsScreenState extends ConsumerState<KycDocumentsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _licenseNumberCtrl = TextEditingController();
  final _aadharNoCtrl = TextEditingController();
  final _panNoCtrl = TextEditingController();
  final _picker = ImagePicker();

  // Snapshot of values loaded from backend — used to skip validation
  // for fields the user hasn't actually changed.
  String? _savedLicenseNo;
  String? _savedAadharNo;
  String? _savedPanNo;

  DateTime? _issuingDate;
  DateTime? _expiryDate;

  String? _licenseFilePath, _licenseFileName;
  String? _aadharFilePath, _aadharFileName;
  String? _panFilePath, _panFileName;

  String? _existingLicenseUrl;
  String? _existingAadharUrl;
  String? _existingPanUrl;

  // Fields manually unlocked for editing after initial submission
  final Set<String> _editableOverrides = {};

  bool _busy = false;
  String _uploadingLabel = '';
  _DocFilter _activeFilter = _DocFilter.all;

  static const int _maxFileSizeBytes = 5 * 1024 * 1024;
  static const List<String> _allowedExtensions = ['jpg', 'jpeg', 'png'];

  @override
  void initState() {
    super.initState();
    _applyExistingValues(ref.read(appControllerProvider));
    final app = ref.read(appControllerProvider);
    if (app.kycCompleted && app.existingAadharNo == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await ref
            .read(appControllerProvider)
            .fetchLoggedInEmployeeDriverProfile(forceRefresh: true);
        if (!mounted) return;
        setState(() => _applyExistingValues(ref.read(appControllerProvider)));
      });
    }
  }

  void _applyExistingValues(AppController app) {
    if (_licenseNumberCtrl.text.isEmpty && app.existingLicenseNo != null) {
      _licenseNumberCtrl.text = app.existingLicenseNo!;
    }
    if (_aadharNoCtrl.text.isEmpty && app.existingAadharNo != null) {
      _aadharNoCtrl.text = app.existingAadharNo!;
    }
    if (_panNoCtrl.text.isEmpty && app.existingPanNo != null) {
      _panNoCtrl.text = app.existingPanNo!;
    }
    // Save a snapshot so _isFormValid can detect user edits
    _savedLicenseNo ??= _licenseNumberCtrl.text;
    _savedAadharNo ??= _aadharNoCtrl.text;
    _savedPanNo ??= _panNoCtrl.text;
    _existingLicenseUrl ??= app.existingLicenseUrl;
    _existingAadharUrl ??= app.existingAadharUrl;
    _existingPanUrl ??= app.existingPanUrl;
    _issuingDate ??= _parseDate(app.existingIssuingDate);
    _expiryDate ??= _parseDate(app.existingExpiryDate);
  }

  static DateTime? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _licenseNumberCtrl.dispose();
    _aadharNoCtrl.dispose();
    _panNoCtrl.dispose();
    super.dispose();
  }

  List<_DocEntry> get _allEntries {
    final bool reupload = widget.licenseReuploadMode;
    final bool licenseUploaded = (_existingLicenseUrl ?? '').isNotEmpty;
    final bool aadharUploaded = (_existingAadharUrl ?? '').isNotEmpty;
    final bool panUploaded = (_existingPanUrl ?? '').isNotEmpty;

    return [
      _DocEntry(
        field: 'license',
        label: 'Driving License',
        icon: Icons.badge_outlined,
        editable: reupload || !licenseUploaded || _editableOverrides.contains('license'),
        isRequired: reupload,
        number: _licenseNumberCtrl.text,
        pickedPath: _licenseFilePath,
        existingUrl: reupload ? null : _existingLicenseUrl,
        issuingDate: _issuingDate,
        expiryDate: _expiryDate,
        isReuploadRequired: reupload,
      ),
      if (!reupload) ...[
        _DocEntry(
          field: 'aadhar',
          label: 'Aadhaar Card',
          icon: Icons.credit_card_rounded,
          editable: !aadharUploaded || _editableOverrides.contains('aadhar'),
          isRequired: true,
          number: _aadharNoCtrl.text,
          pickedPath: _aadharFilePath,
          existingUrl: _existingAadharUrl,
        ),
        _DocEntry(
          field: 'pan',
          label: 'PAN Card',
          icon: Icons.account_balance_wallet_outlined,
          editable: !panUploaded || _editableOverrides.contains('pan'),
          isRequired: false,
          number: _panNoCtrl.text,
          pickedPath: _panFilePath,
          existingUrl: _existingPanUrl,
        ),
      ],
    ];
  }

  List<_DocEntry> get _filteredEntries =>
      _allEntries.where((e) => e.matchesFilter(_activeFilter)).toList();

  bool get _isFormValid {
    if (widget.licenseReuploadMode) {
      final ln = validateLicenseNumber(_licenseNumberCtrl.text, required: true) == null;
      final fp = _licenseFilePath != null;
      return ln && fp;
    }
    final licenseEditable = (_existingLicenseUrl ?? '').isEmpty ||
        _editableOverrides.contains('license');
    final aadharEditable = (_existingAadharUrl ?? '').isEmpty ||
        _editableOverrides.contains('aadhar');
    final panEditable = (_existingPanUrl ?? '').isEmpty ||
        _editableOverrides.contains('pan');

    // Only validate format if the user actually changed the value from the
    // saved backend snapshot. Pre-populated data is trusted as-is.
    final licenseChanged = _licenseNumberCtrl.text != _savedLicenseNo;
    final panChanged = _panNoCtrl.text != _savedPanNo;

    bool aadharValid = true;
    if (aadharEditable) {
      final v = validateAadhar(_aadharNoCtrl.text);
      final f = _aadharFilePath != null || (_existingAadharUrl ?? '').isNotEmpty;
      aadharValid = v == null && f;
    }
    bool licenseValid = true;
    if (_licenseNumberCtrl.text.trim().isNotEmpty) {
      final v = validateLicenseNumber(_licenseNumberCtrl.text);
      licenseValid = v == null;
    }
    bool panValid = true;
    if (panEditable && _panNoCtrl.text.trim().isNotEmpty && panChanged) {
      final v = validatePAN(_panNoCtrl.text);
      panValid = v == null;
    }
    final result = aadharValid && licenseValid && panValid;
    return result;
  }

  bool get _anyEditable {
    final bool reupload = widget.licenseReuploadMode;
    final bool licenseUploaded = (_existingLicenseUrl ?? '').isNotEmpty;
    final bool aadharUploaded = (_existingAadharUrl ?? '').isNotEmpty;
    final bool panUploaded = (_existingPanUrl ?? '').isNotEmpty;
    if (reupload) return true;
    if (_editableOverrides.isNotEmpty) return true;
    return !licenseUploaded || !aadharUploaded || !panUploaded;
  }

  Future<void> _pickFile(String field) async {
    final labels = {
      'license': 'Driving License',
      'aadhar': 'Aadhaar Card',
      'pan': 'PAN Card',
    };
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      showDragHandle: true,
      builder: (_) => _UploadSourceSheet(label: labels[field]!),
    );
    if (source == null || !mounted) return;

    final file = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1500,
      maxHeight: 1500,
    );
    if (file == null || !mounted) return;

    final ext = file.name.split('.').last.toLowerCase();
    if (!_allowedExtensions.contains(ext)) {
      showInfoSnack(context, 'Only JPG and PNG images are accepted');
      return;
    }
    final size = await File(file.path).length();
    if (!mounted) return;
    if (size > _maxFileSizeBytes) {
      showInfoSnack(context, 'Image must be smaller than 5 MB');
      return;
    }
    setState(() {
      switch (field) {
        case 'license':
          _licenseFilePath = file.path;
          _licenseFileName = file.name;
        case 'aadhar':
          _aadharFilePath = file.path;
          _aadharFileName = file.name;
        case 'pan':
          _panFilePath = file.path;
          _panFileName = file.name;
      }
    });
  }

  Future<void> _pickDate({required bool isIssuing}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isIssuing ? now : now.add(const Duration(days: 365)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2040),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isIssuing) {
          _issuingDate = picked;
        } else {
          _expiryDate = picked;
        }
      });
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtDateDmy(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final app = ref.read(appControllerProvider);
    setState(() {
      _busy = true;
      _uploadingLabel = '';
    });

    if (widget.licenseReuploadMode) {
      setState(() => _uploadingLabel = 'Uploading driving license...');
      final licenseUrl = await app.uploadFile(
        filePath: _licenseFilePath!,
        fileName: _licenseFileName ?? 'license.jpg',
        doctype: 'Driver',
        docname: app.driverName,
        fieldname: 'custom_license_attachment',
      );
      if (!mounted) return;
      if (licenseUrl == null) {
        setState(() => _busy = false);
        showInfoSnack(context, 'Failed to upload license attachment');
        return;
      }
      setState(() => _uploadingLabel = 'Saving changes...');
      final error = await app.resubmitLicense(
        licenseNumber: _licenseNumberCtrl.text.trim(),
        licenseAttachmentUrl: licenseUrl,
        issuingDate: _issuingDate != null ? _fmtDate(_issuingDate!) : null,
        expiryDate: _expiryDate != null ? _fmtDate(_expiryDate!) : null,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      if (error != null) {
        showInfoSnack(context, error);
        return;
      }
      showInfoSnack(context, 'License updated successfully');
      Navigator.of(context)
          .pushNamedAndRemoveUntil(AppRoutes.dashboard, (_) => false);
      return;
    }

    String? licenseUrl;
    String? aadharUrl;
    String? panUrl;

    if (_licenseFilePath != null) {
      setState(() => _uploadingLabel = 'Uploading driving license...');
      licenseUrl = await app.uploadFile(
        filePath: _licenseFilePath!,
        fileName: _licenseFileName ?? 'license.jpg',
        doctype: 'Driver',
        docname: app.driverName,
        fieldname: 'custom_license_attachment',
      );
      if (!mounted) return;
      if (licenseUrl == null) {
        setState(() => _busy = false);
        showInfoSnack(context, 'Failed to upload driving license');
        return;
      }
    }

    if (_aadharFilePath != null) {
      setState(() => _uploadingLabel = 'Uploading Aadhaar card...');
      aadharUrl = await app.uploadFile(
        filePath: _aadharFilePath!,
        fileName: _aadharFileName ?? 'aadhar.jpg',
        doctype: 'Driver',
        docname: app.driverName,
        fieldname: 'custom_aadhar_attachment',
      );
      if (!mounted) return;
      if (aadharUrl == null) {
        setState(() => _busy = false);
        showInfoSnack(context, 'Failed to upload Aadhaar card');
        return;
      }
    }

    if (_panFilePath != null) {
      setState(() => _uploadingLabel = 'Uploading PAN card...');
      panUrl = await app.uploadFile(
        filePath: _panFilePath!,
        fileName: _panFileName ?? 'pan.jpg',
        doctype: 'Driver',
        docname: app.driverName,
        fieldname: 'custom_pan_attachment',
      );
      if (!mounted) return;
      if (panUrl == null) {
        setState(() => _busy = false);
        showInfoSnack(context, 'Failed to upload PAN card');
        return;
      }
    }

    setState(() => _uploadingLabel = 'Submitting KYC...');
    final error = await app.submitDriverKyc(
      aadharNo: _aadharNoCtrl.text.trim(),
      aadharAttachmentUrl: aadharUrl ?? _existingAadharUrl ?? '',
      licenseNumber: _licenseNumberCtrl.text.trim().isEmpty
          ? null
          : _licenseNumberCtrl.text.trim(),
      licenseAttachmentUrl: licenseUrl ?? _existingLicenseUrl,
      issuingDate: _issuingDate != null ? _fmtDate(_issuingDate!) : null,
      expiryDate: _expiryDate != null ? _fmtDate(_expiryDate!) : null,
      panNo: _panNoCtrl.text.trim().isEmpty ? null : _panNoCtrl.text.trim(),
      panAttachmentUrl: panUrl ?? _existingPanUrl,
    );

    if (!mounted) return;
    setState(() => _busy = false);

    if (error != null) {
      showInfoSnack(context, error);
      return;
    }
    showInfoSnack(context, 'KYC submitted successfully');
    Navigator.of(context)
        .pushNamedAndRemoveUntil(AppRoutes.dashboard, (_) => false);
  }

  Map<String, String> get _authHeaders =>
      ref.read(appControllerProvider).buildAuthHeaders();

  String _fullUrl(String url) =>
      url.startsWith('http') ? url : '${ApiConstants.erpBaseUrl}$url';

  void _viewServerDoc(String url, String label) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _DocPreviewScreen(
        url: _fullUrl(url),
        label: label,
        authHeaders: _authHeaders,
      ),
    ));
  }

  void _viewLocalFile(String path, String label) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _LocalDocPreviewScreen(path: path, label: label),
    ));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appControllerProvider);
    final all = _allEntries;
    final filtered = _filteredEntries;
    final uploadedCount =
        all.where((e) => e.status == _DocStatus.uploaded).length;
    final reupload = widget.licenseReuploadMode;
    final anyEditable = _anyEditable;
    final isFormValid = _isFormValid;

    return Scaffold(
      backgroundColor: KycColors.pageBg(context),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KycHeader(
                  title: reupload ? 'Re-upload License' : 'My Documents',
                  subtitle: reupload
                      ? 'Update your driving license details'
                      : 'Upload and manage your documents',
                  icon: Icons.folder_special_outlined,
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      children: [
                        if (reupload) ...[
                          const SizedBox(height: 8),
                          _ReuploadWarningBanner(),
                          const SizedBox(height: 14),
                        ] else ...[
                          const SizedBox(height: 8),
                          _KycStatusCard(
                            uploaded: uploadedCount,
                            total: all.length,
                            entries: all,
                          ),
                          const SizedBox(height: 12),
                          _FilterRow(
                            active: _activeFilter,
                            entries: all,
                            onChanged: (f) =>
                                setState(() => _activeFilter = f),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (filtered.isEmpty)
                          _EmptyFilterPlaceholder(filter: _activeFilter)
                        else
                          ...filtered.map(_buildCard),
                      ],
                    ),
                  ),
                ),
                if (anyEditable)
                  _SubmitBar(
                    busy: _busy,
                    uploadingLabel: _uploadingLabel,
                    isReupload: reupload,
                    canSubmit: isFormValid && !_busy,
                    onSubmit: _submit,
                  ),
              ],
            ),
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(color: Colors.black26),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(_DocEntry entry) {
    if (entry.field == 'pan' && entry.status == _DocStatus.missing) {
      return _PanMissingCard(onAdd: () => _pickFile('pan'));
    }

    final existingUrl = switch (entry.field) {
      'license' => _existingLicenseUrl,
      'aadhar' => _existingAadharUrl,
      'pan' => _existingPanUrl,
      _ => null,
    };
    final String? fullExistingUrl =
        (existingUrl ?? '').isEmpty ? null : _fullUrl(existingUrl!);

    // Show unlock button when the card is locked after initial submission
    // and is not already in forced-reupload mode.
    final bool canUnlock = !entry.editable &&
        !entry.isReuploadRequired &&
        entry.hasFile;

    return _DocumentCard(
      key: ValueKey(entry.field),
      entry: entry,
      authHeaders: _authHeaders,
      fullExistingUrl: fullExistingUrl,
      onUpload: entry.editable ? () => _pickFile(entry.field) : null,
      onView: fullExistingUrl != null
          ? () => _viewServerDoc(existingUrl!, entry.label)
          : null,
      onViewLocal: entry.pickedPath != null
          ? () => _viewLocalFile(entry.pickedPath!, entry.label)
          : null,
      onUnlock: canUnlock
          ? () => setState(() => _editableOverrides.add(entry.field))
          : null,
      numberField: _buildNumberField(entry),
      dateFields: entry.field == 'license' ? _buildDateRow(entry) : null,
    );
  }

  Widget _buildNumberField(_DocEntry entry) {
    switch (entry.field) {
      case 'license':
        return _NumberField(
          controller: _licenseNumberCtrl,
          editable: entry.editable,
          hint: 'Enter license number',
          textCapitalization: TextCapitalization.characters,
          validator: (v) =>
              validateLicenseNumber(v, required: widget.licenseReuploadMode),
          onChanged: () => setState(() {}),
        );
      case 'aadhar':
        return _NumberField(
          controller: _aadharNoCtrl,
          editable: entry.editable,
          hint: 'Enter 12-digit Aadhaar',
          keyboardType: TextInputType.number,
          validator: validateAadhar,
          onChanged: () => setState(() {}),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(12),
          ],
        );
      case 'pan':
        return _NumberField(
          controller: _panNoCtrl,
          editable: entry.editable,
          hint: 'Enter PAN number (optional)',
          textCapitalization: TextCapitalization.characters,
          validator: validatePAN,
          inputFormatters: [LengthLimitingTextInputFormatter(10)],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDateRow(_DocEntry entry) {
    return Row(
      children: [
        Expanded(
          child: _DatePickerCell(
            label: 'Issued',
            date: _issuingDate,
            enabled: entry.editable,
            onTap: entry.editable ? () => _pickDate(isIssuing: true) : null,
            formatter: _fmtDateDmy,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _DatePickerCell(
            label: 'Expires',
            date: _expiryDate,
            enabled: entry.editable,
            onTap: entry.editable ? () => _pickDate(isIssuing: false) : null,
            formatter: _fmtDateDmy,
            isExpiry: true,
          ),
        ),
      ],
    );
  }
}

// ─── Number field ─────────────────────────────────────────────────────────────

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.editable,
    required this.hint,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
    this.onChanged,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final bool editable;
  final String hint;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;
  final VoidCallback? onChanged;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: editable,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      // Suppress validation entirely when locked so stale errors never show
      validator: editable ? validator : null,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onChanged: (editable && onChanged != null) ? (_) => onChanged!() : null,
      inputFormatters: inputFormatters,
      cursorColor: KycColors.accent,
      style: TextStyle(
        fontSize: 14,
        fontWeight: editable ? FontWeight.w600 : FontWeight.w600,
        color: KycColors.textPrimary(context),
      ),
      decoration: editable ? _activeDecoration(context) : _lockedDecoration(context),
    );
  }

  InputDecoration _activeDecoration(BuildContext context) => InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        filled: true,
        fillColor: KycColors.accentSoft(context),
        hintText: hint,
        hintStyle: TextStyle(
          color: KycColors.textHint(context),
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: KycColors.accent.withValues(alpha: 0.45),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kKycAccent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE53935)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE53935), width: 1.5),
        ),
        errorStyle: const TextStyle(fontSize: 11, height: 1.2),
        counterText: '',
      );

  InputDecoration _lockedDecoration(BuildContext context) => InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
        filled: false,
        hintText: hint,
        hintStyle: TextStyle(
          color: KycColors.textHint(context),
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        counterText: '',
      );
}

// ─── Status summary card ──────────────────────────────────────────────────────

class _KycStatusCard extends StatelessWidget {
  const _KycStatusCard({
    required this.uploaded,
    required this.total,
    required this.entries,
  });

  final int uploaded;
  final int total;
  final List<_DocEntry> entries;

  Color _accentColor() {
    if (entries.any((e) => e.status == _DocStatus.reuploadRequired)) {
      return const Color(0xFFE57700);
    }
    if (entries.any((e) => e.status == _DocStatus.expired)) {
      return const Color(0xFFE57700);
    }
    if (uploaded == total) return const Color(0xFF1AB36A);
    if (uploaded == 0) return const Color(0xFF98A2B3);
    return const Color(0xFF2DBA9F);
  }

  static String _shortDocName(String field) => switch (field) {
    'license' => 'License',
    'aadhar' => 'Aadhar',
    'pan' => 'PAN',
    _ => field,
  };

  String _summaryText() {
    if (entries.any((e) => e.status == _DocStatus.reuploadRequired)) {
      return 'Action required — re-upload needed';
    }
    if (entries.any((e) => e.status == _DocStatus.expired)) {
      return 'One or more documents expired';
    }
    if (uploaded == total) return 'All documents uploaded';
    if (uploaded == 0) return 'No documents uploaded yet';
    return '$uploaded of $total documents uploaded';
  }

  @override
  Widget build(BuildContext context) {
    final color = _accentColor();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KycColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KycColors.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.verified_user_outlined,
                  size: 20,
                  color: color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'KYC Status',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: KycColors.textSecondary(context),
                      ),
                    ),
                    Text(
                      _summaryText(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$uploaded/$total',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: entries.map((e) {
              return Expanded(
                child: Container(
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: e.status.color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Row(
            children: entries.map((e) {
              return Expanded(
                child: Text(
                  _shortDocName(e.field),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: e.status.color,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─── Filter chips ─────────────────────────────────────────────────────────────

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.active,
    required this.entries,
    required this.onChanged,
  });

  final _DocFilter active;
  final List<_DocEntry> entries;
  final ValueChanged<_DocFilter> onChanged;

  int _count(_DocFilter f) =>
      entries.where((e) => e.matchesFilter(f) && f != _DocFilter.all).length;

  @override
  Widget build(BuildContext context) {
    const filters = [
      (_DocFilter.all, 'All'),
      (_DocFilter.uploaded, 'Uploaded'),
      (_DocFilter.missing, 'Missing'),
      (_DocFilter.expired, 'Expired'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((tuple) {
          final (filter, label) = tuple;
          final count = _count(filter);
          final isActive = active == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onChanged(filter),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color:
                      isActive ? KycColors.accent : KycColors.cardBg(context),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isActive
                        ? KycColors.accent
                        : KycColors.cardBorder(context),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isActive
                            ? Colors.white
                            : KycColors.textSecondary(context),
                      ),
                    ),
                    if (count > 0 && !(filter == _DocFilter.expired)) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 0,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? Colors.white.withValues(alpha: 0.25)
                              : KycColors.accentSoft(context),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color:
                                isActive ? Colors.white : KycColors.accent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Document card ────────────────────────────────────────────────────────────

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    super.key,
    required this.entry,
    required this.authHeaders,
    required this.fullExistingUrl,
    required this.numberField,
    this.dateFields,
    this.onUpload,
    this.onView,
    this.onViewLocal,
    this.onUnlock,
  });

  final _DocEntry entry;
  final Map<String, String> authHeaders;
  final String? fullExistingUrl;
  final Widget numberField;
  final Widget? dateFields;
  final VoidCallback? onUpload;
  final VoidCallback? onView;
  final VoidCallback? onViewLocal;
  final VoidCallback? onUnlock;

  @override
  Widget build(BuildContext context) {
    final status = entry.status;
    final hasPicked = entry.pickedPath != null;
    final hasExisting = (fullExistingUrl ?? '').isNotEmpty;
    final hasAnyFile = hasPicked || hasExisting;

    final bool alertBorder =
        status == _DocStatus.reuploadRequired || status == _DocStatus.expired;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: KycColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: alertBorder
              ? status.color.withValues(alpha: 0.4)
              : KycColors.cardBorder(context),
          width: alertBorder ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Card header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: KycColors.accentSoft(context),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(entry.icon, size: 20, color: KycColors.accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: KycColors.textPrimary(context),
                        ),
                      ),
                      Text(
                        entry.isRequired
                            ? 'Required'
                            : entry.field == 'pan'
                                ? 'Optional'
                                : '',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: entry.isRequired
                              ? KycColors.accent
                              : KycColors.textHint(context),
                        ),
                      ),
                    ],
                  ),
                ),
                _DocStatusBadge(status: status),
              ],
            ),
          ),
          Divider(height: 1, color: KycColors.cardBorder(context)),
          // ── Card body ──
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail
                GestureDetector(
                  onTap: hasPicked
                      ? onViewLocal
                      : hasExisting
                          ? onView
                          : onUpload,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 90,
                      height: 90,
                      child: _DocThumbnail(
                        pickedPath: entry.pickedPath,
                        serverUrl: fullExistingUrl,
                        authHeaders: authHeaders,
                        onTap: onUpload,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Fields
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _numberLabel(entry.field),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: KycColors.textHint(context),
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      numberField,
                      if (dateFields != null) ...[
                        const SizedBox(height: 10),
                        dateFields!,
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ── Action buttons ──
          if (hasAnyFile || entry.editable) ...[
            Divider(height: 1, color: KycColors.cardBorder(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Row(
                children: [
                  if (hasAnyFile)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: hasPicked ? onViewLocal : onView,
                        icon:
                            const Icon(Icons.visibility_outlined, size: 15),
                        label: const Text('View'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: KycColors.accent,
                          side: BorderSide(
                            color: KycColors.accent.withValues(alpha: 0.5),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  if (hasAnyFile && !entry.editable && onUnlock != null)
                    const SizedBox(width: 10),
                  if (hasAnyFile && !entry.editable && onUnlock != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onUnlock,
                        icon: const Icon(Icons.edit_outlined, size: 15),
                        label: const Text('Edit'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: KycColors.accent,
                          side: BorderSide(
                            color: KycColors.accent.withValues(alpha: 0.5),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  if (hasAnyFile && entry.editable)
                    const SizedBox(width: 10),
                  if (entry.editable)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onUpload,
                        icon: Icon(
                          hasAnyFile
                              ? Icons.refresh_rounded
                              : Icons.upload_rounded,
                          size: 15,
                        ),
                        label: Text(hasAnyFile ? 'Replace' : 'Upload'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: KycColors.accent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _numberLabel(String field) => switch (field) {
    'license' => 'LICENSE NUMBER',
    'aadhar' => 'AADHAAR NUMBER',
    'pan' => 'PAN NUMBER',
    _ => 'NUMBER',
  };
}

// ─── Document thumbnail ───────────────────────────────────────────────────────

class _DocThumbnail extends StatelessWidget {
  const _DocThumbnail({
    required this.pickedPath,
    required this.serverUrl,
    required this.authHeaders,
    required this.onTap,
  });

  final String? pickedPath;
  final String? serverUrl;
  final Map<String, String> authHeaders;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (pickedPath != null) {
      return Image.file(
        File(pickedPath!),
        fit: BoxFit.cover,
        errorBuilder: (context, e, s) => _fallback(context),
      );
    }

    if ((serverUrl ?? '').isNotEmpty) {
      return Image.network(
        serverUrl!,
        fit: BoxFit.cover,
        headers: authHeaders,
        errorBuilder: (context, e, s) => _fallback(context),
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return Container(
            color: KycColors.accentSoft(context),
            child: const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: kKycAccent,
              ),
            ),
          );
        },
      );
    }

    // No file — upload placeholder
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: KycColors.accentSoft(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: KycColors.accent.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              color: KycColors.accent,
              size: 26,
            ),
            const SizedBox(height: 4),
            Text(
              'Add photo',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: KycColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallback(BuildContext context) => Container(
    color: KycColors.accentSoft(context),
    child: Icon(
      Icons.broken_image_outlined,
      color: KycColors.textHint(context),
      size: 26,
    ),
  );
}

// ─── Status badge ─────────────────────────────────────────────────────────────

class _DocStatusBadge extends StatelessWidget {
  const _DocStatusBadge({required this.status});
  final _DocStatus status;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? status.color.withValues(alpha: 0.18)
            : status.bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 12, color: status.color),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: status.color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Date picker cell ─────────────────────────────────────────────────────────

class _DatePickerCell extends StatelessWidget {
  const _DatePickerCell({
    required this.label,
    required this.date,
    required this.enabled,
    required this.onTap,
    required this.formatter,
    this.isExpiry = false,
  });

  final String label;
  final DateTime? date;
  final bool enabled;
  final VoidCallback? onTap;
  final String Function(DateTime) formatter;
  final bool isExpiry;

  bool get _warn {
    if (!isExpiry || date == null) return false;
    final now = DateTime.now();
    return date!.isBefore(now) || date!.difference(now).inDays < 30;
  }

  @override
  Widget build(BuildContext context) {
    final hasDate = date != null;
    final warnColor = const Color(0xFFE57700);
    final expColor = const Color(0xFFE53935);
    final chipColor = _warn
        ? (isExpiry && date != null && date!.isBefore(DateTime.now())
            ? expColor
            : warnColor)
        : KycColors.accent;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: _warn
              ? chipColor.withValues(alpha: 0.12)
              : KycColors.accentSoft(context),
          borderRadius: BorderRadius.circular(8),
          border: _warn
              ? Border.all(color: chipColor.withValues(alpha: 0.35))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 10,
              color: chipColor,
            ),
            const SizedBox(width: 3),
            Text(
              hasDate ? formatter(date!) : label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: hasDate ? chipColor : KycColors.textHint(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Upload source sheet ──────────────────────────────────────────────────────

class _UploadSourceSheet extends StatelessWidget {
  const _UploadSourceSheet({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Upload $label',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'JPG or PNG · max 5 MB',
              style: TextStyle(
                fontSize: 12,
                color: KycColors.textHint(context),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _SourceOption(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camera',
                    subtitle: 'Take a photo',
                    onTap: () => Navigator.pop(context, ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SourceOption(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    subtitle: 'Choose image',
                    onTap: () => Navigator.pop(context, ImageSource.gallery),
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

class _SourceOption extends StatelessWidget {
  const _SourceOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: KycColors.accentSoft(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: KycColors.cardBorder(context)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: KycColors.accent, size: 30),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: KycColors.textPrimary(context),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: KycColors.textHint(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Submit bar ───────────────────────────────────────────────────────────────

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({
    required this.busy,
    required this.uploadingLabel,
    required this.isReupload,
    required this.canSubmit,
    required this.onSubmit,
  });

  final bool busy;
  final String uploadingLabel;
  final bool isReupload;
  final bool canSubmit;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: KycColors.cardBg(context),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
            blurRadius: 14,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy && uploadingLabel.isNotEmpty) ...[
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: KycColors.accent,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  uploadingLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: KycColors.textSecondary(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                backgroundColor: KycColors.cardBorder(context),
                color: KycColors.accent,
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            height: 50,
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: canSubmit ? onSubmit : null,
              icon: Icon(
                busy ? Icons.hourglass_top_rounded : Icons.check_rounded,
                size: 18,
              ),
              label: Text(
                busy
                    ? 'Please wait...'
                    : isReupload
                        ? 'Submit License'
                        : 'Submit Documents',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: KycColors.accent,
                disabledBackgroundColor:
                    KycColors.accent.withValues(alpha: 0.4),
                foregroundColor: Colors.white,
                elevation: 0,
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty filter state ───────────────────────────────────────────────────────

class _EmptyFilterPlaceholder extends StatelessWidget {
  const _EmptyFilterPlaceholder({required this.filter});
  final _DocFilter filter;

  @override
  Widget build(BuildContext context) {
    final label = switch (filter) {
      _DocFilter.uploaded => 'No uploaded documents',
      _DocFilter.missing => 'No missing documents',
      _DocFilter.expired => 'No expired documents',
      _ => 'No documents',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_open_rounded,
            size: 48,
            color: KycColors.textHint(context),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: KycColors.textHint(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Reupload warning banner ──────────────────────────────────────────────────

class _ReuploadWarningBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF6E7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF6D697)),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFB87707)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your driving license is missing or expired. Please upload a valid copy to continue.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF7A4F08),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── PAN missing state card ───────────────────────────────────────────────────

class _PanMissingCard extends StatelessWidget {
  const _PanMissingCard({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF6E7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF6D697)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFE57700).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.account_balance_wallet_outlined,
              size: 20,
              color: Color(0xFFB87707),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PAN Card (Optional)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: KycColors.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Add your PAN card for faster verification',
                  style: TextStyle(
                    fontSize: 11,
                    color: KycColors.textHint(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Add'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE57700),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Document preview screens ─────────────────────────────────────────────────

class _DocPreviewScreen extends StatelessWidget {
  const _DocPreviewScreen({
    required this.url,
    required this.label,
    required this.authHeaders,
  });

  final String url;
  final String label;
  final Map<String, String> authHeaders;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(label),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: Image.network(
            url,
            headers: authHeaders,
            fit: BoxFit.contain,
            errorBuilder: (context, e, s) => const _PreviewErrorState(),
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LocalDocPreviewScreen extends StatelessWidget {
  const _LocalDocPreviewScreen({required this.path, required this.label});
  final String path;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(label),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: Image.file(
            File(path),
            fit: BoxFit.contain,
            errorBuilder: (context, e, s) => const _PreviewErrorState(),
          ),
        ),
      ),
    );
  }
}

class _PreviewErrorState extends StatelessWidget {
  const _PreviewErrorState();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
        SizedBox(height: 12),
        Text(
          'Unable to load image',
          style: TextStyle(color: Colors.white54, fontSize: 14),
        ),
      ],
    );
  }
}
