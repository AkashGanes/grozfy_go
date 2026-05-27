import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/connectivity_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/app_toast.dart';
import '../model/pickup_job.dart';
import '../repository/pickup_job_repository.dart';

class PickupJobDetailScreen extends ConsumerStatefulWidget {
  const PickupJobDetailScreen({super.key, required this.pickupJobName});

  final String pickupJobName;

  @override
  ConsumerState<PickupJobDetailScreen> createState() =>
      _PickupJobDetailScreenState();
}

class _PickupJobDetailScreenState
    extends ConsumerState<PickupJobDetailScreen> {
  late Future<PickupJob> _future;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _future = _loadJob();
  }

  Future<PickupJob> _loadJob() =>
      PickupJobRepository().fetchJob(widget.pickupJobName);

  // ── Mark Picked Up (B.3) ──────────────────────────────────────────────────

  Future<void> _handleMarkPickedUp(PickupJob job) async {
    // Optional photo capture
    final photoPath = await _showPickupProofSheet();
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.inventory_2_outlined, color: AppTheme.oceanBlue),
            const SizedBox(width: 8),
            const Text(
              'Confirm Pickup',
              style: TextStyle(
                  color: AppTheme.nightBlue,
                  fontWeight: FontWeight.w700,
                  fontSize: 16),
            ),
          ],
        ),
        content: Text(
          'Confirm you have collected the items from ${job.customerName.isNotEmpty ? job.customerName : "the customer"}?',
          style:
              const TextStyle(color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.oceanBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm Picked Up'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    if (!ConnectivityService().isConnected) {
      showInfoSnack(context, 'You are offline — connect and try again.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await PickupJobRepository()
          .markPickedUp(job.name, proofPhotoPath: photoPath);
      if (!mounted) return;
      showInfoSnack(context, 'Picked up — head to the store.');
      setState(() { _future = _loadJob(); });
    } catch (e) {
      if (!mounted) return;
      showInfoSnack(
          context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Drop at Store (B.4) ───────────────────────────────────────────────────

  Future<void> _handleDropAtStore(PickupJob job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.store_rounded, color: AppTheme.oceanBlue),
            const SizedBox(width: 8),
            const Text(
              'Drop at Store',
              style: TextStyle(
                  color: AppTheme.nightBlue,
                  fontWeight: FontWeight.w700,
                  fontSize: 16),
            ),
          ],
        ),
        content: Text(
          'Confirm you have dropped the items for ${job.customerName.isNotEmpty ? job.customerName : "this customer"} at the store dock?',
          style: const TextStyle(color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.oceanBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm Drop'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    if (!ConnectivityService().isConnected) {
      showInfoSnack(context, 'You are offline — connect and try again.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await PickupJobRepository().confirmCompleted(job.name);
      // Update the trip stop status in ERPNext.
      if (job.deliveryTrip != null && job.deliveryTrip!.isNotEmpty) {
        try {
          await PickupJobRepository().updatePickupTripStopCompleted(
            tripName: job.deliveryTrip!,
            pickupJobName: job.name,
          );
        } catch (e) {
          debugPrint('[PickupJob] trip stop update failed: $e');
          if (mounted) {
            showInfoSnack(context,
                'Stop update: ${e.toString().replaceFirst('Exception: ', '')}');
          }
        }
      } else {
        debugPrint('[PickupJob] deliveryTrip is empty — skipping stop update');
      }
      if (!mounted) return;
      _showCompletionDialog();
      setState(() { _future = _loadJob(); });
    } catch (e) {
      if (!mounted) return;
      showInfoSnack(
          context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showCompletionDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32)),
            SizedBox(width: 8),
            Text(
              'Pickup Complete',
              style: TextStyle(
                  color: AppTheme.nightBlue,
                  fontWeight: FontWeight.w700,
                  fontSize: 16),
            ),
          ],
        ),
        content: const Text(
          'Items received at the store.\n\nThe customer\'s refund will be issued within 5–7 business days.',
          style: TextStyle(color: Colors.black54),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  // ── Photo capture ─────────────────────────────────────────────────────────

  Future<String?> _showPickupProofSheet() {
    return showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PickupProofSheet(),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Pickup Job',
      subtitle: widget.pickupJobName,
      scrollable: false,
      child: FutureBuilder<PickupJob>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child:
                  CircularProgressIndicator(color: AppTheme.oceanBlue),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: FrostCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          size: 40, color: AppTheme.mango),
                      const SizedBox(height: 10),
                      Text(
                        snapshot.error
                            .toString()
                            .replaceFirst('Exception: ', ''),
                        textAlign: TextAlign.center,
                        style:
                            const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton(
                        onPressed: () =>
                            setState(() => _future = _loadJob()),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final job = snapshot.data!;
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _progressCard(job).animate().fadeIn(duration: 220.ms),
                const SizedBox(height: 12),
                _detailCard(job)
                    .animate()
                    .fadeIn(delay: 60.ms, duration: 220.ms),
                const SizedBox(height: 12),
                _actionArea(job)
                    .animate()
                    .fadeIn(delay: 100.ms, duration: 220.ms),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _progressCard(PickupJob job) {
    final statusNorm = job.status.trim().toLowerCase();
    final pickedUp =
        statusNorm == 'picked up' || statusNorm == 'received at store';
    final completed = statusNorm == 'received at store';

    final steps = <_ProgressStep>[
      const _ProgressStep(
        label: 'Job Claimed',
        sublabel: 'Added to your trip',
        done: true,
      ),
      _ProgressStep(
        label: 'Items Collected',
        sublabel: 'Picked up from customer',
        done: pickedUp,
      ),
      _ProgressStep(
        label: 'Dropped at Store',
        sublabel: 'Received at store',
        done: completed,
      ),
    ];

    return FrostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pickup Progress',
            style: TextStyle(
              color: AppTheme.nightBlue,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 14),
          for (int i = 0; i < steps.length; i++)
            _buildStep(steps[i], isLast: i == steps.length - 1),
        ],
      ),
    );
  }

  Widget _buildStep(_ProgressStep step, {required bool isLast}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: step.done ? AppTheme.oceanBlue : Colors.transparent,
                border: step.done
                    ? null
                    : Border.all(color: Colors.black26, width: 1.5),
              ),
              child: step.done
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 28,
                color: step.done
                    ? AppTheme.oceanBlue.withValues(alpha: 0.3)
                    : Colors.black12,
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.label,
                  style: TextStyle(
                    color:
                        step.done ? AppTheme.nightBlue : Colors.black38,
                    fontWeight:
                        step.done ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 13,
                  ),
                ),
                if (step.sublabel.isNotEmpty)
                  Text(
                    step.sublabel,
                    style: const TextStyle(
                        color: Colors.black38, fontSize: 11),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _detailCard(PickupJob job) {
    return FrostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow(Icons.person_outline, job.customerName),
          if (job.customerMobile.isNotEmpty) ...[
            const SizedBox(height: 8),
            _callRow(job.customerMobile),
          ],
          const SizedBox(height: 8),
          _infoRow(Icons.my_location_outlined, job.pickupAddress,
              label: 'Pickup from'),
          const SizedBox(height: 8),
          _infoRow(Icons.store_outlined, job.dropAddress,
              label: 'Drop at store'),
          if (job.scheduledWindow != null &&
              job.scheduledWindow!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _infoRow(Icons.schedule_outlined, job.scheduledWindow!),
          ],
        ],
      ),
    );
  }

  Widget _actionArea(PickupJob job) {
    final statusNorm = job.status.trim().toLowerCase();

    if (_isSubmitting) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: CircularProgressIndicator(color: AppTheme.oceanBlue),
        ),
      );
    }

    // Added to Trip → Mark Picked Up
    if (statusNorm == 'added to trip') {
      return _primaryActionButton(
        label: 'Mark Picked Up',
        icon: Icons.inventory_2_outlined,
        onTap: () => _handleMarkPickedUp(job),
      );
    }

    // Picked Up → Drop at Store
    if (statusNorm == 'picked up') {
      return _primaryActionButton(
        label: 'Drop at Store',
        icon: Icons.store_rounded,
        onTap: () => _handleDropAtStore(job),
      );
    }

    // Received at Store — terminal success
    if (statusNorm == 'received at store') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: const Color(0xFF2E7D32).withValues(alpha: 0.25)),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_rounded,
                size: 18, color: Color(0xFF2E7D32)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Pickup complete. Refund issued within 5–7 business days.',
                style: TextStyle(
                    color: Color(0xFF2E7D32),
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _primaryActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.oceanBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 15)),
        onPressed: onTap,
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, {String? label}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: Colors.black38),
        ),
        const SizedBox(width: 8),
        if (label != null)
          Text('$label: ',
              style: const TextStyle(
                  color: Colors.black38,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  color: AppTheme.nightBlue, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _callRow(String phone) {
    return Row(
      children: [
        const Icon(Icons.phone_outlined, size: 15, color: Colors.black38),
        const SizedBox(width: 8),
        Expanded(
          child: Text(phone,
              style: const TextStyle(
                  color: AppTheme.nightBlue, fontSize: 13)),
        ),
        GestureDetector(
          onTap: () async {
            final uri = Uri(scheme: 'tel', path: phone);
            if (await canLaunchUrl(uri)) await launchUrl(uri);
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.call_rounded,
                    size: 13, color: Color(0xFF2E7D32)),
                SizedBox(width: 4),
                Text('Call',
                    style: TextStyle(
                        color: Color(0xFF2E7D32),
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ],
    );
  }

}

class _ProgressStep {
  const _ProgressStep({
    required this.label,
    required this.sublabel,
    required this.done,
  });
  final String label;
  final String sublabel;
  final bool done;
}

// ── Pickup proof sheet ────────────────────────────────────────────────────────

class _PickupProofSheet extends StatefulWidget {
  const _PickupProofSheet();

  @override
  State<_PickupProofSheet> createState() => _PickupProofSheetState();
}

class _PickupProofSheetState extends State<_PickupProofSheet> {
  XFile? _pickedFile;
  static const int _maxFileSizeBytes = 5 * 1024 * 1024;

  Future<void> _pickPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final original = await picker.pickImage(source: source);
    if (original == null || !mounted) return;
    final size = await File(original.path).length();
    if (size > _maxFileSizeBytes) {
      if (mounted) {
        AppToast.show(context,
            'Selected image exceeds 5 MB limit. Choose a smaller image.');
      }
      return;
    }
    final compressed =
        await FlutterImageCompress.compressWithFile(original.path, quality: 80);
    if (compressed == null || !mounted) return;
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/pickup_proof_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await file.writeAsBytes(compressed);
    if (mounted) setState(() => _pickedFile = XFile(file.path));
  }

  void _showSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
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
                    const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Remove Photo',
                    style: TextStyle(color: Colors.red)),
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
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + inset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.oceanBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      color: AppTheme.oceanBlue, size: 20),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Proof of Pickup',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.nightBlue),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Optionally capture a photo of the items before collecting.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: _showSourceSheet,
              child: _pickedFile == null
                  ? Container(
                      width: double.infinity,
                      height: 160,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.black.withValues(alpha: 0.10)),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo_outlined,
                              color: Colors.black38, size: 36),
                          SizedBox(height: 8),
                          Text('Tap to capture photo',
                              style: TextStyle(
                                  color: Colors.black38, fontSize: 13)),
                          SizedBox(height: 4),
                          Text('Camera or gallery',
                              style: TextStyle(
                                  color: Colors.black26, fontSize: 11)),
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
                            onTap: _showSourceSheet,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('Change',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
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
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(
                          color: Colors.black.withValues(alpha: 0.20)),
                    ),
                    child: const Text('Skip',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.black54)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.oceanBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.done_all_rounded, size: 18),
                    label: const Text('Confirm Picked Up',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    onPressed: () =>
                        Navigator.of(context).pop(_pickedFile?.path),
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
