import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/context_colors.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../repository/pickup_job_repository.dart';

/// Shows a bottom sheet asking the driver to enter the customer's 6-digit
/// return OTP, verifies it against
/// `grozfy_go.grozfy_go.api.driver.verify_return_otp`, and pops `true`
/// once verified (the pickup job is Picked Up server-side at that point —
/// the caller just needs to refresh). Pops `null` if the driver cancels.
///
/// Every failure the server can return ("Invalid OTP", "OTP already
/// verified", "Pickup is not Scheduled", "Delivery partner is not assigned
/// to this return") is shown inline, as-is, with the sheet staying open so
/// the driver can retry or cancel.
Future<bool?> showReturnOtpSheet(
  BuildContext context, {
  required PickupJobRepository repository,
  required String pickupJob,
}) {
  return showAppBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _ReturnOtpSheet(
      repository: repository,
      pickupJob: pickupJob,
    ),
  );
}

class _ReturnOtpSheet extends StatefulWidget {
  const _ReturnOtpSheet({
    required this.repository,
    required this.pickupJob,
  });

  final PickupJobRepository repository;
  final String pickupJob;

  @override
  State<_ReturnOtpSheet> createState() => _ReturnOtpSheetState();
}

class _ReturnOtpSheetState extends State<_ReturnOtpSheet> {
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _verifying = false;
  String? _error;

  @override
  void dispose() {
    _otpController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() => _error = 'Enter the 6-digit OTP');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await widget.repository.verifyReturnOtp(
        pickupJob: widget.pickupJob,
        otp: otp,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
      _otpController.clear();
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppBottomSheet(
      scrollable: true,
      title: 'Return OTP',
      subtitle: 'Ask the customer for their 6-digit return code',
      leadingIcon: Icons.lock_outline_rounded,
      leadingIconColor: context.scheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          TextField(
            controller: _otpController,
            focusNode: _focusNode,
            autofocus: true,
            enabled: !_verifying,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: 8,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••••',
              filled: true,
              fillColor: scheme.onSurface.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: scheme.onSurface.withValues(alpha: 0.12),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.scheme.primary, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: scheme.error),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: scheme.error, width: 1.5),
              ),
              errorText: _error,
              errorMaxLines: 3,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: 20),
          AppSheetPrimaryButton(
            label: _verifying ? 'Verifying...' : 'Verify & Mark Picked Up',
            icon: Icons.check_circle_rounded,
            color: const Color(0xFF2E7D32),
            onPressed: _verifying ? null : _verify,
          ),
          const SizedBox(height: 8),
          AppSheetSecondaryButton(
            label: 'Cancel',
            onPressed: _verifying ? null : () => Navigator.of(context).pop(null),
          ),
        ],
      ),
    );
  }
}
