import 'package:flutter/material.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/widgets/app_shell.dart';

class KycDocumentsScreen extends StatefulWidget {
  const KycDocumentsScreen({super.key});

  @override
  State<KycDocumentsScreen> createState() => _KycDocumentsScreenState();
}

class _KycDocumentsScreenState extends State<KycDocumentsScreen> {
  bool _uploading = false;

  Future<void> _uploadDoc(String key) async {
    final app = AppScope.of(context);
    setState(() => _uploading = true);
    await app.uploadKycDocument(key);
    if (!mounted) {
      return;
    }
    setState(() => _uploading = false);
    showInfoSnack(context, 'Document uploaded, waiting for admin verification');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    return AppShell(
      title: 'KYC Verification',
      subtitle: 'Upload identity documents and check approval status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FrostCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Required documents',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 6),
                Text('1) Aadhaar or ID proof\n2) Driving license\n3) Selfie'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _DocTile(
            title: 'Aadhaar / ID Proof',
            keyName: 'idProof',
            status: app.kycStatus['idProof'] ?? VerificationStatus.notSubmitted,
            progress: app.kycProgress['idProof'] ?? 0,
            onUpload: () => _uploadDoc('idProof'),
            loading: _uploading,
          ),
          const SizedBox(height: 10),
          _DocTile(
            title: 'Driving License',
            keyName: 'drivingLicense',
            status:
                app.kycStatus['drivingLicense'] ??
                VerificationStatus.notSubmitted,
            progress: app.kycProgress['drivingLicense'] ?? 0,
            onUpload: () => _uploadDoc('drivingLicense'),
            loading: _uploading,
          ),
          const SizedBox(height: 10),
          _DocTile(
            title: 'Selfie Photo',
            keyName: 'selfie',
            status: app.kycStatus['selfie'] ?? VerificationStatus.notSubmitted,
            progress: app.kycProgress['selfie'] ?? 0,
            onUpload: () => _uploadDoc('selfie'),
            loading: _uploading,
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: () {
              app.simulateKycApproval();
              showInfoSnack(context, 'Admin approval simulated for demo');
            },
            child: const Text('Simulate Admin Approval'),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.vehicleDetails),
            child: const Text('Continue to Vehicle Setup'),
          ),
        ],
      ),
    );
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({
    required this.title,
    required this.keyName,
    required this.status,
    required this.progress,
    required this.onUpload,
    required this.loading,
  });

  final String title;
  final String keyName;
  final VerificationStatus status;
  final double progress;
  final VoidCallback onUpload;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final Color statusColor = switch (status) {
      VerificationStatus.approved => Colors.green,
      VerificationStatus.pending => Colors.orange,
      VerificationStatus.rejected => Colors.red,
      VerificationStatus.notSubmitted => Colors.grey,
    };

    return FrostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Chip(
                label: Text(status.label),
                backgroundColor: statusColor.withValues(alpha: 0.14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: progress,
              backgroundColor: Colors.black.withValues(alpha: 0.06),
              color: statusColor,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: loading ? null : onUpload,
              icon: Icon(
                keyName == 'selfie'
                    ? Icons.camera_alt_outlined
                    : Icons.upload_file_rounded,
              ),
              label: const Text('Upload'),
            ),
          ),
        ],
      ),
    );
  }
}
