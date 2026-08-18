import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/api_constants.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_controller.dart';
import '../../core/state/providers.dart';
import '../../core/theme/context_colors.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/app_shell.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum _DocFilter { all, uploaded, missing, expired }

enum _DocStatus { missing, uploaded, expired, reuploadRequired }

extension _DocStatusStyle on _DocStatus {
  // Badge/pill copy stays exactly what it was — only the color/icon that
  // pairs with it changes (see _Severity below).
  String get label => switch (this) {
    _DocStatus.missing => 'Missing',
    _DocStatus.uploaded => 'Uploaded',
    _DocStatus.expired => 'Expired',
    _DocStatus.reuploadRequired => 'Re-upload Required',
  };
}

/// Three-tier visual severity used for every color/icon decision in this
/// screen. This is a presentation-only concept — it never feeds back into
/// `_isFormValid` or any submit-gating logic, which continue to depend only
/// on `_DocStatus` + the existing per-field validity checks.
enum _Severity { success, warning, danger }

extension _SeverityStyle on _Severity {
  Color color(BuildContext context) => switch (this) {
    _Severity.success => context.success,
    _Severity.warning => context.warning,
    _Severity.danger => context.danger,
  };

  Color bgColor(BuildContext context) => switch (this) {
    _Severity.success => context.successContainer,
    _Severity.warning => context.warningContainer,
    _Severity.danger => context.dangerContainer,
  };

  IconData get icon => switch (this) {
    _Severity.success => Icons.check_circle_rounded,
    _Severity.warning => Icons.warning_rounded,
    _Severity.danger => Icons.error_rounded,
  };

  String get legendLabel => switch (this) {
    _Severity.success => 'Complete',
    _Severity.warning => 'Needs attention',
    _Severity.danger => 'Action required',
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

  /// New in this redesign: `missing` no longer maps to one neutral color —
  /// it splits by whether the field is actually required, so a missing
  /// Aadhaar (blocks Submit) reads as clearly more urgent than a missing,
  /// optional PAN. `expired` and `reuploadRequired` are unaffected by
  /// required-ness (they already imply "something needs fixing").
  _Severity get severity => switch (status) {
    _DocStatus.uploaded => _Severity.success,
    _DocStatus.expired => _Severity.danger,
    _DocStatus.reuploadRequired => _Severity.warning,
    _DocStatus.missing => isRequired ? _Severity.danger : _Severity.warning,
  };

  bool matchesFilter(_DocFilter f) => switch (f) {
    _DocFilter.all => true,
    _DocFilter.uploaded => status == _DocStatus.uploaded,
    _DocFilter.missing => status == _DocStatus.missing,
    _DocFilter.expired =>
      status == _DocStatus.expired || status == _DocStatus.reuploadRequired,
  };
}

// ─── Design tokens ("Kinetic Trust", scoped to this screen only) ──────────────
//
// Severity colors (success/warning/danger) deliberately keep using the shared,
// dark-mode-aware `context.success/warning/danger` tokens from
// core/theme/context_colors.dart — only the brand/primary blue, neutral
// layout, and Inter typography below are new, and they live only in this
// file so no other screen is affected.

const Color _kDocsPrimaryLight = Color(0xFF003D9B);
const Color _kDocsPrimaryDark = Color(0xFF9DB8FF);

extension _DocsTheme on BuildContext {
  Color get docsPrimary => isDark ? _kDocsPrimaryDark : _kDocsPrimaryLight;
  Color get docsPrimarySoft =>
      isDark ? const Color(0xFF13294D) : const Color(0xFFE8EEFC);
}

List<BoxShadow> _docsCardShadow(BuildContext context) => [
  BoxShadow(
    color: context.docsPrimary.withValues(alpha: context.isDark ? 0.28 : 0.08),
    blurRadius: 16,
    offset: const Offset(0, 4),
  ),
];

TextStyle _interHeadline(BuildContext context) => GoogleFonts.inter(
  fontSize: 20,
  fontWeight: FontWeight.w600,
  height: 28 / 20,
  color: context.textPrimary,
);

TextStyle _interBodyMd(
  BuildContext context, {
  Color? color,
  FontWeight? weight,
}) => GoogleFonts.inter(
  fontSize: 16,
  fontWeight: weight ?? FontWeight.w400,
  height: 24 / 16,
  color: color ?? context.textPrimary,
);

TextStyle _interLabelMd(BuildContext context, {Color? color}) =>
    GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.14,
      height: 20 / 14,
      color: color ?? context.textPrimary,
    );

TextStyle _interLabelSm(
  BuildContext context, {
  Color? color,
  FontWeight? weight,
}) => GoogleFonts.inter(
  fontSize: 12,
  fontWeight: weight ?? FontWeight.w500,
  height: 16 / 12,
  color: color ?? context.textSecondary,
);

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
  final _scrollController = ScrollController();

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
  bool _headerElevated = false;

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
    _scrollController.addListener(() {
      final elevated = _scrollController.hasClients &&
          _scrollController.offset > 4;
      if (elevated != _headerElevated) {
        setState(() => _headerElevated = elevated);
      }
    });
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
    _scrollController.dispose();
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
          icon: Icons.contact_page_outlined,
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
    final aadharEditable = (_existingAadharUrl ?? '').isEmpty ||
        _editableOverrides.contains('aadhar');
    final panEditable = (_existingPanUrl ?? '').isEmpty ||
        _editableOverrides.contains('pan');

    // Only validate format if the user actually changed the value from the
    // saved backend snapshot. Pre-populated data is trusted as-is.
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

  /// Mirrors `_isFormValid` exactly, but instead of a bool returns *which*
  /// field is failing (checked Aadhaar → License → PAN) so the Submit bar
  /// can tell the user something more useful than a disabled button.
  /// `_submitDisabledReason() == null` is equivalent to `_isFormValid`.
  String? _submitDisabledReason() {
    if (widget.licenseReuploadMode) {
      if (validateLicenseNumber(_licenseNumberCtrl.text, required: true) != null) {
        return 'Enter a valid license number to continue';
      }
      if (_licenseFilePath == null) {
        return 'Take or choose a photo of your license';
      }
      return null;
    }

    final aadharEditable = (_existingAadharUrl ?? '').isEmpty ||
        _editableOverrides.contains('aadhar');
    if (aadharEditable) {
      final v = validateAadhar(_aadharNoCtrl.text);
      final hasAadharFile =
          _aadharFilePath != null || (_existingAadharUrl ?? '').isNotEmpty;
      if (v != null || !hasAadharFile) {
        return 'Add a valid Aadhaar number to continue';
      }
    }

    if (_licenseNumberCtrl.text.trim().isNotEmpty &&
        validateLicenseNumber(_licenseNumberCtrl.text) != null) {
      return 'Check your license number format';
    }

    final panEditable = (_existingPanUrl ?? '').isEmpty ||
        _editableOverrides.contains('pan');
    final panChanged = _panNoCtrl.text != _savedPanNo;
    if (panEditable &&
        _panNoCtrl.text.trim().isNotEmpty &&
        panChanged &&
        validatePAN(_panNoCtrl.text) != null) {
      return 'Check your PAN format';
    }

    return null;
  }

  /// The license badge can read as alarming (expired/missing) without ever
  /// blocking Submit in full mode — this gates the reassurance note so it
  /// never contradicts an actual, currently-active validation error.
  bool get _licenseActivelyInvalid =>
      _licenseNumberCtrl.text.trim().isNotEmpty &&
      validateLicenseNumber(_licenseNumberCtrl.text) != null;

  Future<void> _pickFile(String field) async {
    final labels = {
      'license': 'Driving License',
      'aadhar': 'Aadhaar Card',
      'pan': 'PAN Card',
    };
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.kycApprovalStatus, (_) => false);
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
    final disabledReason = _submitDisabledReason();

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DocsAppHeader(
                  title: reupload ? 'Re-upload License' : 'My Documents',
                  subtitle: reupload
                      ? 'Update your driving license details'
                      : 'Manage your KYC identity documents',
                  onBack: () => Navigator.of(context).maybePop(),
                  showBottomBorder: _headerElevated,
                  showBadge: !reupload,
                ),
                Expanded(
                  child: Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
                      children: [
                        if (reupload) ...[
                          const SizedBox(height: 8),
                          const _ReuploadWarningBanner(),
                          const SizedBox(height: 16),
                        ] else ...[
                          const SizedBox(height: 8),
                          _ProgressCard(
                            doneCount: uploadedCount,
                            entries: all,
                            activeFilter: _activeFilter,
                            onFilterChanged: (f) =>
                                setState(() => _activeFilter = f),
                          ),
                          const SizedBox(height: 16),
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
                    disabledReason: disabledReason,
                    onSubmit: _submit,
                  ),
              ],
            ),
            if (_busy)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(
                    alpha: context.isDark ? 0.45 : 0.35,
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(_DocEntry entry) {
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

    // Only the license card ever gets the "doesn't block submission" note,
    // only in full mode, only while its badge looks concerning, and never
    // while the field is actively invalid (that gets a real error instead).
    final bool showLicenseNote = entry.field == 'license' &&
        !widget.licenseReuploadMode &&
        entry.severity != _Severity.success &&
        !_licenseActivelyInvalid;

    return _DocCard(
      key: ValueKey(entry.field),
      entry: entry,
      authHeaders: _authHeaders,
      fullExistingUrl: fullExistingUrl,
      showLicenseNote: showLicenseNote,
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
      dateFields: entry.field == 'license' ? _buildValidity(entry) : null,
    );
  }

  Widget _buildNumberField(_DocEntry entry) {
    switch (entry.field) {
      case 'license':
        return _NumberField(
          controller: _licenseNumberCtrl,
          editable: entry.editable,
          hint: 'Enter license number',
          lockedPlaceholder: 'Not entered',
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
          lockedPlaceholder: 'Not entered',
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
          lockedPlaceholder: 'Not entered',
          textCapitalization: TextCapitalization.characters,
          validator: validatePAN,
          onChanged: () => setState(() {}),
          inputFormatters: [LengthLimitingTextInputFormatter(10)],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildValidity(_DocEntry entry) {
    return Row(
      children: [
        Expanded(
          child: _ValidityCell(
            label: 'Issued',
            date: _issuingDate,
            enabled: entry.editable,
            onTap: entry.editable ? () => _pickDate(isIssuing: true) : null,
            formatter: _fmtDateDmy,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ValidityCell(
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

// ─── Header ───────────────────────────────────────────────────────────────────

class _DocsAppHeader extends StatelessWidget {
  const _DocsAppHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.showBottomBorder,
    this.showBadge = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final bool showBottomBorder;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: showBottomBorder ? context.borderSubtle : Colors.transparent,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _DocsBackButton(onTap: onBack),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: _interHeadline(context)),
                const SizedBox(height: 2),
                Text(subtitle, style: _interLabelSm(context)),
              ],
            ),
          ),
          if (showBadge) ...[
            const SizedBox(width: 8),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: context.successContainer,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.folder_special_rounded,
                color: context.success,
                size: 22,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DocsBackButton extends StatelessWidget {
  const _DocsBackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.cardColor,
      shape: CircleBorder(side: BorderSide(color: context.borderSubtle)),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            Icons.arrow_back_rounded,
            size: 20,
            color: context.textPrimary,
          ),
        ),
      ),
    );
  }
}

// ─── Progress card (progress + legend + filter, merged) ───────────────────────

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.doneCount,
    required this.entries,
    required this.activeFilter,
    required this.onFilterChanged,
  });

  final int doneCount;
  final List<_DocEntry> entries;
  final _DocFilter activeFilter;
  final ValueChanged<_DocFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final total = entries.length;
    // Legend groups by severity *tier*, not by raw _DocStatus — a missing
    // Aadhaar (danger) and a missing PAN (warning) are both "Missing" text,
    // but they must not collapse into a single legend row, since that would
    // hide exactly which one blocks Submit.
    final present = entries.map((e) => e.severity).toSet();
    final ordered = [_Severity.danger, _Severity.warning, _Severity.success]
        .where(present.contains)
        .toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderSubtle),
        boxShadow: _docsCardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  '$doneCount of $total documents complete',
                  style: _interHeadline(context),
                ),
              ),
              Text('$doneCount/$total', style: _interHeadline(context)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: entries.map((e) {
              return Expanded(
                child: Container(
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: e.severity.color(context),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (ordered.isNotEmpty)
                Expanded(
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: ordered.map((sv) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: sv.color(context),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(sv.legendLabel, style: _interLabelSm(context)),
                        ],
                      );
                    }).toList(),
                  ),
                )
              else
                const Spacer(),
              _FilterMenu(
                active: activeFilter,
                entries: entries,
                onChanged: onFilterChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterMenu extends StatelessWidget {
  const _FilterMenu({
    required this.active,
    required this.entries,
    required this.onChanged,
  });

  final _DocFilter active;
  final List<_DocEntry> entries;
  final ValueChanged<_DocFilter> onChanged;

  int _count(_DocFilter f) =>
      entries.where((e) => e.matchesFilter(f) && f != _DocFilter.all).length;

  String _label(_DocFilter f) => switch (f) {
    _DocFilter.all => 'All',
    _DocFilter.uploaded => 'Uploaded',
    _DocFilter.missing => 'Missing',
    _DocFilter.expired => 'Expired',
  };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_DocFilter>(
      initialValue: active,
      onSelected: onChanged,
      offset: const Offset(0, 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: context.cardColor,
      itemBuilder: (context) => _DocFilter.values.map((f) {
        final count = _count(f);
        return PopupMenuItem<_DocFilter>(
          value: f,
          height: 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _label(f),
                style: _interLabelMd(
                  context,
                  color: f == active ? context.docsPrimary : context.textPrimary,
                ),
              ),
              if (count > 0)
                Text('$count', style: _interLabelSm(context)),
            ],
          ),
        );
      }).toList(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Show: ${_label(active)}',
            style: _interLabelMd(context, color: context.docsPrimary),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: context.docsPrimary,
          ),
        ],
      ),
    );
  }
}

// ─── Document card ────────────────────────────────────────────────────────────

class _DocCard extends StatelessWidget {
  const _DocCard({
    super.key,
    required this.entry,
    required this.authHeaders,
    required this.fullExistingUrl,
    required this.showLicenseNote,
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
  final bool showLicenseNote;
  final Widget numberField;
  final Widget? dateFields;
  final VoidCallback? onUpload;
  final VoidCallback? onView;
  final VoidCallback? onViewLocal;
  final VoidCallback? onUnlock;

  @override
  Widget build(BuildContext context) {
    final severity = entry.severity;
    final hasPicked = entry.pickedPath != null;
    final hasExisting = (fullExistingUrl ?? '').isNotEmpty;
    final hasAnyFile = hasPicked || hasExisting;
    final accent = severity.color(context);

    return Semantics(
      label:
          '${entry.label}, ${entry.isRequired ? 'required' : 'optional'}, ${entry.status.label}',
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border(
            top: BorderSide(color: context.borderSubtle),
            right: BorderSide(color: context.borderSubtle),
            bottom: BorderSide(color: context.borderSubtle),
            left: BorderSide(
              color: severity == _Severity.success
                  ? context.borderSubtle
                  : accent,
              width: severity == _Severity.success ? 1 : 4,
            ),
          ),
          boxShadow: _docsCardShadow(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Card header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: hasAnyFile
                          ? context.successContainer
                          : context.borderSubtle.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      entry.icon,
                      size: 20,
                      color: hasAnyFile ? context.success : context.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.label,
                                style: _interLabelMd(context),
                              ),
                            ),
                            _RequirementPill(isRequired: entry.isRequired),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _StatusPill(status: entry.status, severity: severity),
                        if (showLicenseNote) ...[
                          const SizedBox(height: 6),
                          Text(
                            "Doesn't block submission — update it whenever you're ready.",
                            style: _interLabelSm(
                              context,
                              weight: FontWeight.w400,
                            ).copyWith(height: 1.35),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (onUnlock != null) ...[
                    const SizedBox(width: 8),
                    _EditButton(onTap: onUnlock!),
                  ],
                ],
              ),
            ),
            Divider(height: 1, color: context.borderSubtle),
            // ── Card body ──
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: hasPicked
                        ? onViewLocal
                        : hasExisting
                            ? onView
                            : onUpload,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 80,
                        height: 80,
                        child: _DocThumbnail(
                          pickedPath: entry.pickedPath,
                          serverUrl: fullExistingUrl,
                          authHeaders: authHeaders,
                          severity: severity,
                          onTap: onUpload,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _numberLabel(entry.field),
                          style: _interLabelSm(context),
                        ),
                        const SizedBox(height: 4),
                        numberField,
                        if (dateFields != null) ...[
                          const SizedBox(height: 12),
                          Text('Validity', style: _interLabelSm(context)),
                          const SizedBox(height: 6),
                          dateFields!,
                        ],
                        if (entry.field == 'pan' && !hasAnyFile) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Add your PAN card to speed up future payouts. Not required to submit.',
                            style: _interLabelSm(
                              context,
                              weight: FontWeight.w400,
                            ).copyWith(height: 1.35),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── Action buttons ──
            if (hasAnyFile || entry.editable) ...[
              Divider(height: 1, color: context.borderSubtle),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    if (hasAnyFile)
                      Expanded(
                        child: _OutlinedPillButton(
                          icon: Icons.visibility_outlined,
                          label: 'View Document',
                          onPressed: hasPicked ? onViewLocal : onView,
                        ),
                      ),
                    if (hasAnyFile && entry.editable) const SizedBox(width: 10),
                    if (entry.editable)
                      Expanded(
                        child: _FilledPillButton(
                          icon: hasAnyFile
                              ? Icons.refresh_rounded
                              : Icons.upload_rounded,
                          label: hasAnyFile ? 'Replace Photo' : 'Upload Photo',
                          onPressed: onUpload,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _numberLabel(String field) => switch (field) {
    'license' => 'License number',
    'aadhar' => 'Aadhaar number',
    'pan' => 'PAN number',
    _ => 'Number',
  };
}

class _RequirementPill extends StatelessWidget {
  const _RequirementPill({required this.isRequired});
  final bool isRequired;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isRequired
            ? context.docsPrimarySoft
            : context.borderSubtle.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        isRequired ? 'Required' : 'Optional',
        style: _interLabelSm(
          context,
          color: isRequired ? context.docsPrimary : context.textSecondary,
        ),
      ),
    );
  }
}

class _OutlinedPillButton extends StatelessWidget {
  const _OutlinedPillButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: context.docsPrimary,
        side: BorderSide(color: context.borderStrong.withValues(alpha: 0.4)),
        minimumSize: const Size(0, 48),
        textStyle: _interLabelMd(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _FilledPillButton extends StatelessWidget {
  const _FilledPillButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: context.docsPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(0, 48),
        textStyle: _interLabelMd(context, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _EditButton extends StatelessWidget {
  const _EditButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Edit',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.docsPrimarySoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_outlined, size: 14, color: context.docsPrimary),
              const SizedBox(width: 4),
              Text('Edit', style: _interLabelMd(context, color: context.docsPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Document thumbnail ───────────────────────────────────────────────────────

class _DocThumbnail extends StatelessWidget {
  const _DocThumbnail({
    required this.pickedPath,
    required this.serverUrl,
    required this.authHeaders,
    required this.severity,
    required this.onTap,
  });

  final String? pickedPath;
  final String? serverUrl;
  final Map<String, String> authHeaders;
  final _Severity severity;
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
            color: context.docsPrimarySoft,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.docsPrimary,
              ),
            ),
          );
        },
      );
    }

    // No file — dashed upload placeholder, tinted by this document's severity.
    return GestureDetector(
      onTap: onTap,
      child: _DashedRoundedBox(
        color: severity.color(context).withValues(alpha: 0.5),
        radius: 12,
        child: Container(
          decoration: BoxDecoration(
            color: severity.bgColor(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_photo_alternate_outlined,
                color: severity.color(context),
                size: 22,
              ),
              const SizedBox(height: 4),
              Text(
                'Upload',
                style: _interLabelSm(
                  context,
                  color: severity.color(context),
                  weight: FontWeight.w600,
                ).copyWith(fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallback(BuildContext context) => Container(
    color: context.docsPrimarySoft,
    child: Icon(
      Icons.broken_image_outlined,
      color: context.textTertiary,
      size: 24,
    ),
  );
}

/// Lightweight dashed-border box (no extra package dependency) used for the
/// "add a photo" upload placeholder, matching the redesign's dashed upload
/// zone treatment.
class _DashedRoundedBox extends StatelessWidget {
  const _DashedRoundedBox({
    required this.child,
    required this.color,
    required this.radius,
  });

  final Widget child;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(color: color, radius: radius),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const double _dashWidth = 4;
  static const double _dashGap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = (distance + _dashWidth).clamp(0, metric.length);
        canvas.drawPath(
          metric.extractPath(distance, next.toDouble()),
          paint,
        );
        distance = next + _dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

// ─── Status pill ──────────────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.severity});
  final _DocStatus status;
  final _Severity severity;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(severity.icon, size: 14, color: severity.color(context)),
        const SizedBox(width: 4),
        Text(
          status.label,
          style: _interLabelSm(
            context,
            color: severity.color(context),
            weight: FontWeight.w600,
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
    required this.lockedPlaceholder,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
    this.onChanged,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final bool editable;
  final String hint;
  final String lockedPlaceholder;
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
      cursorColor: context.docsPrimary,
      style: _interBodyMd(context, weight: FontWeight.w500),
      decoration: editable
          ? _activeDecoration(context)
          : _lockedDecoration(context),
    );
  }

  InputDecoration _activeDecoration(BuildContext context) => InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: context.docsPrimarySoft,
        hintText: hint,
        hintStyle: _interBodyMd(context, color: context.textTertiary),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: context.docsPrimary.withValues(alpha: 0.35),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.docsPrimary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.danger, width: 2),
        ),
        errorStyle: const TextStyle(fontSize: 12, height: 1.3),
        counterText: '',
      );

  InputDecoration _lockedDecoration(BuildContext context) => InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
        filled: false,
        hintText: controller.text.trim().isEmpty ? lockedPlaceholder : null,
        hintStyle: _interBodyMd(context, color: context.textTertiary),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        counterText: '',
      );
}

// ─── Validity cell (two-tier: on-time / expiring soon / past due) ─────────────

class _ValidityCell extends StatelessWidget {
  const _ValidityCell({
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

  /// Two-tier split for the expiry cell: already-past dates escalate to
  /// `danger`, dates within 30 days show `warning`. Underlying math unchanged
  /// from before this redesign — only how many colors it maps to.
  _Severity? get _tier {
    if (!isExpiry || date == null) return null;
    final now = DateTime.now();
    if (date!.isBefore(now)) return _Severity.danger;
    if (date!.difference(now).inDays < 30) return _Severity.warning;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final hasDate = date != null;
    final tier = _tier;
    final bgColor = tier != null
        ? tier.bgColor(context)
        : context.docsPrimarySoft;
    final iconColor = tier != null ? tier.color(context) : context.textTertiary;
    final textColor = tier != null ? tier.color(context) : context.textPrimary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, size: 13, color: iconColor),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: _interLabelSm(context).copyWith(fontSize: 10),
                  ),
                  Text(
                    hasDate ? formatter(date!) : 'Select',
                    style: _interLabelSm(
                      context,
                      color: hasDate ? textColor : context.textTertiary,
                      weight: hasDate ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
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
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Upload $label',
              style: _interLabelMd(context).copyWith(fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text('JPG or PNG · max 5 MB', style: _interLabelSm(context)),
            const SizedBox(height: 18),
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
          color: context.docsPrimarySoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.borderSubtle),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: context.docsPrimary, size: 26),
            const SizedBox(height: 8),
            Text(label, style: _interLabelMd(context)),
            const SizedBox(height: 2),
            Text(subtitle, style: _interLabelSm(context)),
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
    required this.disabledReason,
    required this.onSubmit,
  });

  final bool busy;
  final String uploadingLabel;
  final bool isReupload;
  final bool canSubmit;
  final String? disabledReason;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      decoration: BoxDecoration(
        color: context.cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.4 : 0.06),
            blurRadius: 16,
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
                    color: context.docsPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  uploadingLabel,
                  style: _interLabelSm(context, weight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                backgroundColor: context.borderSubtle,
                color: context.docsPrimary,
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 10),
          ] else if (!busy && !canSubmit && disabledReason != null) ...[
            Row(
              children: [
                Icon(Icons.error_rounded, size: 16, color: context.danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    disabledReason!,
                    style: _interLabelSm(
                      context,
                      color: context.danger,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ] else if (!busy && canSubmit) ...[
            Text(
              'Submit your documents for verification',
              textAlign: TextAlign.center,
              style: _interLabelSm(context),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            height: 56,
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
                backgroundColor: context.docsPrimary,
                disabledBackgroundColor:
                    context.docsPrimary.withValues(alpha: 0.4),
                foregroundColor: Colors.white,
                elevation: 0,
                textStyle: _interLabelMd(context, color: Colors.white),
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
            size: 44,
            color: context.textTertiary,
          ),
          const SizedBox(height: 12),
          Text(label, style: _interLabelMd(context, color: context.textTertiary)),
        ],
      ),
    );
  }
}

// ─── Reupload warning banner ──────────────────────────────────────────────────

/// Kept as a single, statically-worded banner — matching today's behavior
/// exactly. `_DocStatus` collapses missing/expired into one `reuploadRequired`
/// value in reupload mode, so a genuine missing-vs-expired distinction here
/// would require new logic reaching past the enum; out of scope for this pass.
class _ReuploadWarningBanner extends StatelessWidget {
  const _ReuploadWarningBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.warningContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: context.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your driving license is missing or expired. Please upload a valid copy to continue.',
              style: _interBodyMd(context, weight: FontWeight.w400)
                  .copyWith(height: 1.4),
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
