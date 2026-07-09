import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/context_colors.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_toast.dart';

/// Shows the proof-of-delivery capture bottom sheet.
/// Returns the local file path if the driver captured/selected a photo,
/// or null if they tapped "Skip".
Future<String?> showDeliveryProofSheet(BuildContext context) {
  return showAppBottomSheet<String?>(
    context: context,
    builder: (_) => const _DeliveryProofSheet(),
  );
}

/// Converts a relative ERPNext path like /files/proof_XYZ.jpg to a full URL.
String resolveProofPhotoUrl(String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  return '${ApiConstants.erpBaseUrl}$url';
}

/// Tappable proof-of-delivery photo that opens full-screen on tap.
Widget buildProofPhotoWidget(BuildContext context, String photoUrl) {
  final url = resolveProofPhotoUrl(photoUrl);
  return GestureDetector(
    onTap: () => _openFullScreen(context, url),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        width: double.infinity,
        height: 200,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            height: 200,
            child: Center(
              child: CircularProgressIndicator(
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded /
                        progress.expectedTotalBytes!
                    : null,
                color: AppTheme.oceanBlue,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stack) => Container(
          height: 200,
          decoration: BoxDecoration(
            color: context.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.broken_image_outlined,
                  color: context.textTertiary, size: 36),
              const SizedBox(height: 8),
              Text(
                'Could not load photo',
                style: TextStyle(color: context.textTertiary, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void _openFullScreen(BuildContext context, String url) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => _FullScreenPhotoViewer(url: url)),
  );
}

class _FullScreenPhotoViewer extends StatelessWidget {
  const _FullScreenPhotoViewer({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Proof of Delivery',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            },
            errorBuilder: (context, error, stack) => const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image_outlined,
                    color: Colors.white54, size: 48),
                SizedBox(height: 12),
                Text(
                  'Could not load photo',
                  style: TextStyle(color: Colors.white54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom sheet widget
// ---------------------------------------------------------------------------

class _DeliveryProofSheet extends StatefulWidget {
  const _DeliveryProofSheet();

  @override
  State<_DeliveryProofSheet> createState() => _DeliveryProofSheetState();
}

class _DeliveryProofSheetState extends State<_DeliveryProofSheet> {
  XFile? _pickedFile;

  static const int _maxFileSizeBytes = 5 * 1024 * 1024; // 5 MB

  Future<void> _pickPhoto(ImageSource source) async {
    final picker = ImagePicker();

    // Pick at full quality to get the original file for size validation
    final original = await picker.pickImage(source: source);
    if (original == null || !mounted) return;

    final fileSize = await File(original.path).length();
    if (fileSize > _maxFileSizeBytes) {
      if (mounted) {
        AppToast.show(
          context,
          'Selected image exceeds 5 MB limit. Please choose a smaller image.',
        );
      }
      return;
    }

    // Original is within limit — compress before preview/upload
    final compressed = await FlutterImageCompress.compressWithFile(
      original.path,
      quality: 80,
    );
    if (compressed == null || !mounted) return;

    final tempDir = await getTemporaryDirectory();
    final tempFile = File(
      '${tempDir.path}/proof_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await tempFile.writeAsBytes(compressed);

    if (mounted) {
      setState(() => _pickedFile = XFile(tempFile.path));
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
              leading: const Icon(Icons.camera_alt_outlined,
                  color: AppTheme.oceanBlue),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppTheme.oceanBlue),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickPhoto(ImageSource.gallery);
              },
            ),
            if (_pickedFile != null)
              ListTile(
                leading:
                    Icon(Icons.delete_outline, color: ctx.danger),
                title: Text('Remove Photo',
                    style: TextStyle(color: ctx.danger)),
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
    return AppBottomSheet(
      scrollable: true,
      title: 'Proof of Delivery',
      subtitle: 'Optionally capture a photo as proof of delivery.',
      leadingIcon: Icons.camera_alt_rounded,
      leadingIconColor: Colors.green,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),

          GestureDetector(
              onTap: _showPhotoSourceSheet,
              child: _pickedFile == null
                  ? Container(
                      width: double.infinity,
                      height: 160,
                      decoration: BoxDecoration(
                        color: context.fillSubtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: context.borderMuted,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo_outlined,
                              color: context.textTertiary, size: 36),
                          const SizedBox(height: 8),
                          Text(
                            'Tap to capture photo',
                            style: TextStyle(
                                color: context.textTertiary, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Camera or gallery',
                            style: TextStyle(
                                color: context.textDisabled, fontSize: 11),
                          ),
                        ],
                      ),
                    )
                  : Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(_pickedFile!.path),
                            width: double.infinity,
                            height: 200,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: _showPhotoSourceSheet,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Change',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
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

          Row(
            children: [
              Expanded(
                child: AppSheetSecondaryButton(
                  label: 'Skip',
                  onPressed: () => Navigator.of(context).pop(null),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: AppSheetPrimaryButton(
                  label: 'Confirm Delivered',
                  icon: Icons.done_all_rounded,
                  color: const Color(0xFF4CAF50),
                  onPressed: () =>
                      Navigator.of(context).pop(_pickedFile?.path),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
