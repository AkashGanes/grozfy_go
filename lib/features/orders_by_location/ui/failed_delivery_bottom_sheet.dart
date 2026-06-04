import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_bottom_sheet.dart';

class FailedDeliveryResult {
  const FailedDeliveryResult({
    required this.reason,
    this.notes = '',
    this.photoPath,
  });
  final String reason;
  final String notes;
  final String? photoPath;
}

/// Shows a bottom sheet asking the delivery partner why the delivery failed.
/// Returns [FailedDeliveryResult] on confirm, or null if dismissed.
Future<FailedDeliveryResult?> showFailedDeliverySheet(
  BuildContext context,
) {
  return showAppBottomSheet<FailedDeliveryResult>(
    context: context,
    builder: (_) => const _FailedDeliverySheet(),
  );
}

class _FailedDeliverySheet extends StatefulWidget {
  const _FailedDeliverySheet();

  @override
  State<_FailedDeliverySheet> createState() => _FailedDeliverySheetState();
}

class _FailedDeliverySheetState extends State<_FailedDeliverySheet> {
  static const List<String> _reasons = [
    'Customer Not Available / Not Answering',
    'Wrong Address',
    'Customer Refused Delivery',
    'Other',
  ];

  String _selectedReason = _reasons.first;
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _otherReasonController = TextEditingController();
  XFile? _pickedFile;

  bool get _isOther => _selectedReason == 'Other';

  bool get _canConfirm =>
      !_isOther || _otherReasonController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _notesController.dispose();
    _otherReasonController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 80);
    if (file != null && mounted) {
      setState(() => _pickedFile = file);
    }
  }

  void _showPhotoSourceSheet() {
    showAppBottomSheet<void>(
      context: context,
      builder: (ctx) => AppBottomSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: AppTheme.oceanBlue),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppTheme.oceanBlue),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickPhoto(ImageSource.gallery);
              },
            ),
            if (_pickedFile != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Remove Photo', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  setState(() => _pickedFile = null);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return AppBottomSheet(
      scrollable: true,
      title: 'Delivery Failed',
      leadingIcon: Icons.cancel_outlined,
      leadingIconColor: Colors.red,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),

          // Reason label
            Text(
              'Why couldn\'t you deliver?',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withValues(alpha: 0.85),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),

            // Reason radio list
            ..._reasons.map(
              (reason) => InkWell(
                onTap: () => setState(() => _selectedReason = reason),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _selectedReason == reason
                        ? AppTheme.oceanBlue.withValues(alpha: 0.08)
                        : scheme.onSurface.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _selectedReason == reason
                          ? AppTheme.oceanBlue.withValues(alpha: 0.4)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _selectedReason == reason
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 18,
                        color: _selectedReason == reason
                            ? AppTheme.oceanBlue
                            : scheme.onSurface.withValues(alpha: 0.4),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          reason,
                          style: TextStyle(
                            color: _selectedReason == reason
                                ? scheme.onSurface
                                : scheme.onSurface.withValues(alpha: 0.6),
                            fontWeight: _selectedReason == reason
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Custom reason field — shown only when "Other" is selected
            if (_isOther) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _otherReasonController,
                autofocus: true,
                maxLines: 2,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Please specify the reason...',
                  hintStyle: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.4),
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: scheme.onSurface.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: Colors.red.withValues(alpha: 0.4),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.red, width: 1.4),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 14),

            // Notes field
            Text(
              'Notes (optional)',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withValues(alpha: 0.85),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 2,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: 'Add any additional details...',
                hintStyle: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.4),
                  fontSize: 13,
                ),
                filled: true,
                fillColor: scheme.onSurface.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: AppTheme.oceanBlue.withValues(alpha: 0.2),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: scheme.onSurface.withValues(alpha: 0.1),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppTheme.oceanBlue,
                    width: 1.4,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Photo proof section
            Text(
              'Photo Proof (optional)',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withValues(alpha: 0.85),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _showPhotoSourceSheet,
              child: _pickedFile == null
                  ? Container(
                      width: double.infinity,
                      height: 80,
                      decoration: BoxDecoration(
                        color: scheme.onSurface.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: scheme.onSurface.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.camera_alt_outlined,
                            color: scheme.onSurface.withValues(alpha: 0.4),
                            size: 26,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tap to add photo',
                            style: TextStyle(
                              color: scheme.onSurface.withValues(alpha: 0.4),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            File(_pickedFile!.path),
                            width: double.infinity,
                            height: 120,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: GestureDetector(
                            onTap: _showPhotoSourceSheet,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Change',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),

          const SizedBox(height: 20),

          // Confirm button
          AppSheetPrimaryButton(
            label: 'Confirm Failed Delivery',
            icon: Icons.cancel_outlined,
            color: _canConfirm ? Colors.red : Colors.red.withValues(alpha: 0.4),
            onPressed: _canConfirm
                ? () {
                    final reason = _isOther
                        ? _otherReasonController.text.trim()
                        : _selectedReason;
                    Navigator.of(context).pop(
                      FailedDeliveryResult(
                        reason: reason,
                        notes: _notesController.text.trim(),
                        photoPath: _pickedFile?.path,
                      ),
                    );
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
