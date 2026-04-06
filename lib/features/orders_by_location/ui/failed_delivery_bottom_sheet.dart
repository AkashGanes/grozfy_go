import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';

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
  return showModalBottomSheet<FailedDeliveryResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
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
  XFile? _pickedFile;

  @override
  void dispose() {
    _notesController.dispose();
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
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
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
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Title
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.cancel_outlined,
                    color: Colors.red,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Delivery Failed',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.nightBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Reason label
            const Text(
              'Why couldn\'t you deliver?',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
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
                        : Colors.grey.withValues(alpha: 0.06),
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
                            : Colors.black38,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          reason,
                          style: TextStyle(
                            color: _selectedReason == reason
                                ? AppTheme.nightBlue
                                : Colors.black54,
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

            const SizedBox(height: 14),

            // Notes field
            const Text(
              'Notes (optional)',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
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
                hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
                filled: true,
                fillColor: Colors.grey.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: AppTheme.oceanBlue.withValues(alpha: 0.2),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: Colors.black.withValues(alpha: 0.1),
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
            const Text(
              'Photo Proof (optional)',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
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
                        color: Colors.grey.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.1),
                        ),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_alt_outlined, color: Colors.black38, size: 26),
                          SizedBox(height: 4),
                          Text(
                            'Tap to add photo',
                            style: TextStyle(color: Colors.black38, fontSize: 12),
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
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text(
                  'Confirm Failed Delivery',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                onPressed: () {
                  Navigator.of(context).pop(
                    FailedDeliveryResult(
                      reason: _selectedReason,
                      notes: _notesController.text.trim(),
                      photoPath: _pickedFile?.path,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
