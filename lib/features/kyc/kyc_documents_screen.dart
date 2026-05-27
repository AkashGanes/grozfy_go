import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/app_controller.dart';
import '../../core/state/providers.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/app_shell.dart';
import 'widgets/kyc_form_widgets.dart';

class KycDocumentsScreen extends ConsumerStatefulWidget {
  const KycDocumentsScreen({super.key, this.licenseReuploadMode = false});

  final bool licenseReuploadMode;

  @override
  ConsumerState<KycDocumentsScreen> createState() => _KycDocumentsScreenState();
}

class _KycDocumentsScreenState extends ConsumerState<KycDocumentsScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _licenseNumberCtrl = TextEditingController();
  final TextEditingController _aadharNoCtrl = TextEditingController();
  final TextEditingController _panNoCtrl = TextEditingController();

  final ImagePicker _picker = ImagePicker();

  DateTime? _issuingDate;
  DateTime? _expiryDate;

  // Local file paths from picker (not yet uploaded)
  String? _licenseFilePath;
  String? _licenseFileName;
  String? _aadharFilePath;
  String? _aadharFileName;
  String? _panFilePath;
  String? _panFileName;

  // Existing server-side URLs from a previous submission
  String? _existingLicenseUrl;
  String? _existingAadharUrl;
  String? _existingPanUrl;

  bool _busy = false;

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
        setState(() {
          _applyExistingValues(ref.read(appControllerProvider));
        });
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

  bool get _isFormValid => widget.licenseReuploadMode
      ? _licenseNumberCtrl.text.trim().isNotEmpty && _licenseFilePath != null
      : _aadharNoCtrl.text.trim().isNotEmpty &&
            (_aadharFilePath != null || _existingAadharUrl != null);

  Future<void> _pickDate({required bool isIssuing}) async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isIssuing ? now : now.add(const Duration(days: 365)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2040),
    );
    if (picked != null) {
      setState(() {
        if (isIssuing) {
          _issuingDate = picked;
        } else {
          _expiryDate = picked;
        }
      });
    }
  }

  static const int _maxFileSizeBytes = 5 * 1024 * 1024;
  static const List<String> _allowedExtensions = ['jpg', 'jpeg', 'png'];

  static const Map<String, String> _fieldLabel = {
    'license': 'Driving License',
    'aadhar': 'Aadhaar Card',
    'pan': 'PAN Card',
  };

  Future<void> _pickFile(String field) async {
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Upload ${_fieldLabel[field]}',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ListTile(
                leading:
                    const CircleAvatar(child: Icon(Icons.camera_alt_rounded)),
                title: const Text('Take Photo'),
                subtitle: const Text('Use camera to capture document'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading:
                    const CircleAvatar(child: Icon(Icons.photo_library_rounded)),
                title: const Text('Choose from Gallery'),
                subtitle: const Text('Pick an existing image'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null || !mounted) return;

    final XFile? file = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1500,
      maxHeight: 1500,
    );
    if (file == null || !mounted) return;

    final String ext = file.name.split('.').last.toLowerCase();
    if (!_allowedExtensions.contains(ext)) {
      showInfoSnack(context, 'Only JPG and PNG images are accepted');
      return;
    }

    final int sizeBytes = await File(file.path).length();
    if (!mounted) return;
    if (sizeBytes > _maxFileSizeBytes) {
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


  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final app = ref.read(appControllerProvider);

    setState(() => _busy = true);

    if (widget.licenseReuploadMode) {
      final String? licenseUrl = await app.uploadFile(
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

      final String? error = await app.resubmitLicense(
        licenseNumber: _licenseNumberCtrl.text.trim(),
        licenseAttachmentUrl: licenseUrl,
        issuingDate: _issuingDate != null ? AppDateFormat.apiDate(_issuingDate!) : null,
        expiryDate: _expiryDate != null ? AppDateFormat.apiDate(_expiryDate!) : null,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      if (error != null) {
        showInfoSnack(context, error);
        return;
      }
      showInfoSnack(context, 'License uploaded successfully');
      Navigator.of(context)
          .pushNamedAndRemoveUntil(AppRoutes.dashboard, (route) => false);
      return;
    }

    String? licenseUrl;
    String? aadharUrl;
    String? panUrl;

    if (_licenseFilePath != null) {
      licenseUrl = await app.uploadFile(
        filePath: _licenseFilePath!,
        fileName: _licenseFileName ?? 'license.jpg',
        doctype: 'Driver',
        docname: app.driverName,
        fieldname: 'custom_license_attachment',
      );
      if (licenseUrl == null && mounted) {
        setState(() => _busy = false);
        showInfoSnack(context, 'Failed to upload license attachment');
        return;
      }
    }

    if (_aadharFilePath != null) {
      aadharUrl = await app.uploadFile(
        filePath: _aadharFilePath!,
        fileName: _aadharFileName ?? 'aadhar.jpg',
        doctype: 'Driver',
        docname: app.driverName,
        fieldname: 'custom_aadhar_attachment',
      );
      if (aadharUrl == null && mounted) {
        setState(() => _busy = false);
        showInfoSnack(context, 'Failed to upload Aadhar attachment');
        return;
      }
    }

    if (_panFilePath != null) {
      panUrl = await app.uploadFile(
        filePath: _panFilePath!,
        fileName: _panFileName ?? 'pan.jpg',
        doctype: 'Driver',
        docname: app.driverName,
        fieldname: 'custom_pan_attachment',
      );
      if (panUrl == null && mounted) {
        setState(() => _busy = false);
        showInfoSnack(context, 'Failed to upload PAN attachment');
        return;
      }
    }

    final String? error = await app.submitDriverKyc(
      aadharNo: _aadharNoCtrl.text.trim(),
      aadharAttachmentUrl: aadharUrl ?? _existingAadharUrl ?? '',
      licenseNumber: _licenseNumberCtrl.text.trim().isEmpty
          ? null
          : _licenseNumberCtrl.text.trim(),
      licenseAttachmentUrl: licenseUrl ?? _existingLicenseUrl,
      issuingDate: _issuingDate != null ? AppDateFormat.apiDate(_issuingDate!) : null,
      expiryDate: _expiryDate != null ? AppDateFormat.apiDate(_expiryDate!) : null,
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
        .pushNamedAndRemoveUntil(AppRoutes.dashboard, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final bool reupload = widget.licenseReuploadMode;
    ref.watch(appControllerProvider);

    final bool licenseUploaded = (_existingLicenseUrl ?? '').isNotEmpty;
    final bool aadharUploaded = (_existingAadharUrl ?? '').isNotEmpty;
    final bool panUploaded = (_existingPanUrl ?? '').isNotEmpty;
    final bool licenseEditable = reupload || !licenseUploaded;
    final bool aadharEditable = !aadharUploaded;
    final bool panEditable = !panUploaded;
    final bool anyEditable = licenseEditable || aadharEditable || panEditable;

    return Scaffold(
      backgroundColor: KycColors.pageBg(context),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KycHeader(
                  title: reupload ? 'Re-upload License' : 'KYC Verification',
                  subtitle: reupload
                      ? 'Update your driving license details'
                      : 'Upload identity & license details',
                  icon: Icons.verified_user_outlined,
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        if (reupload) ...[
                          _ReuploadWarningBanner(),
                          const SizedBox(height: 14),
                        ],
                        const KycSectionHeading('Driving License'),
                        KycFieldCard(
                          icon: Icons.badge_outlined,
                          label: 'License Number',
                          child: _baseTextField(
                            controller: _licenseNumberCtrl,
                            hint: 'Enter license number',
                            textCapitalization: TextCapitalization.characters,
                            validator: (v) =>
                                validateLicenseNumber(v, required: reupload),
                            enabled: licenseEditable,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        _AttachmentCard(
                          icon: Icons.image_outlined,
                          label: 'License Attachment',
                          fileName: _licenseFileName,
                          existingUrl:
                              reupload ? null : _existingLicenseUrl,
                          enabled: licenseEditable,
                          onTap: () => _pickFile('license'),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: KycFieldCard(
                                icon: Icons.event_available_outlined,
                                label: 'Issuing Date',
                                trailing: Icon(
                                  Icons.calendar_today_outlined,
                                  color: KycColors.textHint(context),
                                  size: 18,
                                ),
                                onTap: licenseEditable
                                    ? () => _pickDate(isIssuing: true)
                                    : null,
                                child: _staticText(
                                  _issuingDate != null
                                      ? AppDateFormat.date(_issuingDate)
                                      : null,
                                  'Select date',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: KycFieldCard(
                                icon: Icons.event_busy_outlined,
                                label: 'Expiry Date',
                                trailing: Icon(
                                  Icons.calendar_today_outlined,
                                  color: KycColors.textHint(context),
                                  size: 18,
                                ),
                                onTap: licenseEditable
                                    ? () => _pickDate(isIssuing: false)
                                    : null,
                                child: _staticText(
                                  _expiryDate != null
                                      ? AppDateFormat.date(_expiryDate)
                                      : null,
                                  'Select date',
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (!reupload) ...[
                          const SizedBox(height: 8),
                          const KycSectionHeading('Aadhar (Required)'),
                          KycFieldCard(
                            icon: Icons.credit_card_rounded,
                            label: 'Aadhar Number',
                            child: _baseTextField(
                              controller: _aadharNoCtrl,
                              hint: 'Enter 12-digit Aadhar',
                              keyboardType: TextInputType.number,
                              validator: validateAadhar,
                              enabled: aadharEditable,
                              onChanged: (_) => setState(() {}),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(12),
                              ],
                            ),
                          ),
                          _AttachmentCard(
                            icon: Icons.image_outlined,
                            label: 'Aadhar Attachment',
                            fileName: _aadharFileName,
                            existingUrl: _existingAadharUrl,
                            enabled: aadharEditable,
                            required: true,
                            onTap: () => _pickFile('aadhar'),
                          ),
                          const SizedBox(height: 8),
                          const KycSectionHeading('PAN (Optional)'),
                          KycFieldCard(
                            icon: Icons.account_balance_wallet_outlined,
                            label: 'PAN Number',
                            child: _baseTextField(
                              controller: _panNoCtrl,
                              hint: 'Enter PAN number',
                              textCapitalization:
                                  TextCapitalization.characters,
                              validator: validatePAN,
                              enabled: panEditable,
                              inputFormatters: [
                                LengthLimitingTextInputFormatter(10),
                              ],
                            ),
                          ),
                          _AttachmentCard(
                            icon: Icons.image_outlined,
                            label: 'PAN Attachment',
                            fileName: _panFileName,
                            existingUrl: _existingPanUrl,
                            enabled: panEditable,
                            onTap: () => _pickFile('pan'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (anyEditable)
                  KycPrimaryButton(
                    label: _busy
                        ? 'Submitting...'
                        : reupload
                            ? 'Submit License'
                            : 'Submit KYC & Continue',
                    onPressed: _isFormValid && !_busy ? _submit : null,
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

  Widget _baseTextField({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
    bool enabled = true,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      validator: validator,
      enabled: enabled,
      onChanged: onChanged,
      inputFormatters: inputFormatters,
      style: kycInputStyle(context).copyWith(
        color: enabled
            ? KycColors.textPrimary(context)
            : KycColors.textHint(context),
      ),
      decoration:
          kycHintDecoration(hint, hintColor: KycColors.textHint(context)),
    );
  }

  Widget _staticText(String? value, String hint) {
    final hasValue = value != null && value.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        hasValue ? value : hint,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: hasValue ? FontWeight.w500 : FontWeight.w400,
          color: hasValue
              ? KycColors.textPrimary(context)
              : KycColors.textHint(context),
        ),
      ),
    );
  }
}

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
              'Your driving license is missing or expired. Please upload to continue.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF7A4F08),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({
    required this.icon,
    required this.label,
    required this.fileName,
    required this.existingUrl,
    required this.enabled,
    required this.onTap,
    this.required = false,
  });

  final IconData icon;
  final String label;
  final String? fileName;
  final String? existingUrl;
  final bool enabled;
  final VoidCallback onTap;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final bool hasNewFile = fileName != null;
    final bool hasExisting = (existingUrl ?? '').isNotEmpty && !hasNewFile;
    final bool hasFile = hasNewFile || hasExisting;

    final IconData statusIcon = hasFile
        ? Icons.check_circle_rounded
        : Icons.upload_rounded;
    final Color statusColor =
        hasFile ? const Color(0xFF1AB36A) : KycColors.textHint(context);

    return KycFieldCard(
      icon: icon,
      label: label + (required ? ' *' : ''),
      trailing: Icon(statusIcon, size: 20, color: statusColor),
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          hasNewFile
              ? fileName!
              : hasExisting
                  ? 'Already uploaded'
                  : enabled
                      ? 'Tap to select image'
                      : 'Locked',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: hasFile ? FontWeight.w600 : FontWeight.w400,
            color: hasFile ? const Color(0xFF118A52) : KycColors.textHint(context),
          ),
        ),
      ),
    );
  }
}
