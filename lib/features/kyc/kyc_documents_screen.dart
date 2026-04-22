import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/app_controller.dart';
import '../../core/state/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_shell.dart';

class KycDocumentsScreen extends ConsumerStatefulWidget {
  const KycDocumentsScreen({super.key});

  @override
  ConsumerState<KycDocumentsScreen> createState() => _KycDocumentsScreenState();
}

class _KycDocumentsScreenState extends ConsumerState<KycDocumentsScreen> {
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

    // If KYC is done but values aren't in memory yet (e.g. submitted before
    // this version was deployed), fetch the driver doc from the server.
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
  }

  @override
  void dispose() {
    _licenseNumberCtrl.dispose();
    _aadharNoCtrl.dispose();
    _panNoCtrl.dispose();
    super.dispose();
  }

  bool get _isFormValid =>
      _aadharNoCtrl.text.trim().isNotEmpty &&
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

  Future<void> _pickFile(String field) async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (file == null) return;
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

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    final app = ref.read(appControllerProvider);

    setState(() => _busy = true);

    // Upload files first (driver_name may be null for new users — that's OK)
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

    // Submit KYC — creates Driver if it doesn't exist
    final String? error = await app.submitDriverKyc(
      aadharNo: _aadharNoCtrl.text.trim(),
      aadharAttachmentUrl: aadharUrl ?? _existingAadharUrl ?? '',
      licenseNumber: _licenseNumberCtrl.text.trim().isEmpty
          ? null
          : _licenseNumberCtrl.text.trim(),
      licenseAttachmentUrl: licenseUrl ?? _existingLicenseUrl,
      issuingDate: _issuingDate != null ? _formatDate(_issuingDate!) : null,
      expiryDate: _expiryDate != null ? _formatDate(_expiryDate!) : null,
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
    final app = ref.watch(appControllerProvider);
    final bool kycDone = app.kycCompleted;

    return AppShell(
      title: 'KYC Verification',
      subtitle: 'Upload identity & license details',
      loading: _busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- License Section ----
          const SectionLabel('Driving License'),
          FrostCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _licenseNumberCtrl,
                  textCapitalization: TextCapitalization.characters,
                  enabled: !kycDone,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'License Number',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                _AttachTile(
                  label: 'License Attachment',
                  fileName: _licenseFileName,
                  onPick: () => _pickFile('license'),
                  existingUrl: _existingLicenseUrl,
                  enabled: !kycDone,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _DateTile(
                        label: 'Issuing Date',
                        value: _issuingDate,
                        onTap: kycDone ? () {} : () => _pickDate(isIssuing: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DateTile(
                        label: 'Expiry Date',
                        value: _expiryDate,
                        onTap: kycDone ? () {} : () => _pickDate(isIssuing: false),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ---- Aadhar Section ----
          const SectionLabel('Aadhar (Required)'),
          FrostCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _aadharNoCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 12,
                  enabled: !kycDone,
                  onChanged: (_) => setState(() {}),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Aadhar Number',
                    prefixIcon: Icon(Icons.credit_card_rounded),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                _AttachTile(
                  label: 'Aadhar Attachment',
                  fileName: _aadharFileName,
                  onPick: () => _pickFile('aadhar'),
                  required: true,
                  existingUrl: _existingAadharUrl,
                  enabled: !kycDone,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ---- PAN Section (Optional) ----
          const SectionLabel('PAN (Optional)'),
          FrostCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _panNoCtrl,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 10,
                  enabled: !kycDone,
                  decoration: const InputDecoration(
                    labelText: 'PAN Number',
                    prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                _AttachTile(
                  label: 'PAN Attachment',
                  fileName: _panFileName,
                  onPick: () => _pickFile('pan'),
                  existingUrl: _existingPanUrl,
                  enabled: !kycDone,
                ),
              ],
            ),
          ),
          if (!kycDone) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isFormValid && !_busy ? _submit : null,
                child: Text(_busy ? 'Submitting...' : 'Submit KYC & Continue'),
              ),
            ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ---- Date picker tile ----
class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String display = value != null
        ? '${value!.day.toString().padLeft(2, '0')}/${value!.month.toString().padLeft(2, '0')}/${value!.year}'
        : 'Select';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.calendar_today_rounded, size: 16),
                const SizedBox(width: 6),
                Text(
                  display,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---- File attachment tile ----
class _AttachTile extends StatelessWidget {
  const _AttachTile({
    required this.label,
    required this.fileName,
    required this.onPick,
    this.required = false,
    this.existingUrl,
    this.enabled = true,
  });

  final String label;
  final String? fileName;
  final VoidCallback onPick;
  final bool required;
  final String? existingUrl;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final bool hasNewFile = fileName != null;
    final bool hasExisting = existingUrl != null && !hasNewFile;
    final bool hasFile = hasNewFile || hasExisting;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: enabled ? onPick : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          color: hasFile
              ? AppTheme.mint.withValues(alpha: 0.08)
              : Colors.grey.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasFile
                ? AppTheme.mint.withValues(alpha: 0.3)
                : Colors.black12,
          ),
        ),
        child: Row(
          children: [
            Icon(
              hasFile ? Icons.check_circle : Icons.upload_file_rounded,
              color: hasFile ? Colors.green : Colors.grey,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label + (required ? ' *' : ''),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  if (hasNewFile)
                    Text(
                      fileName!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                      overflow: TextOverflow.ellipsis,
                    )
                  else if (hasExisting)
                    const Row(
                      children: [
                        Icon(Icons.cloud_done_outlined, size: 13, color: Colors.green),
                        SizedBox(width: 4),
                        Text(
                          'Already uploaded',
                          style: TextStyle(fontSize: 11, color: Colors.green),
                        ),
                      ],
                    )
                  else
                    const Text(
                      'Tap to select image',
                      style: TextStyle(fontSize: 11, color: Colors.black38),
                    ),
                ],
              ),
            ),
            if (hasFile && enabled)
              const Icon(Icons.edit, size: 16, color: Colors.black38),
          ],
        ),
      ),
    );
  }
}
