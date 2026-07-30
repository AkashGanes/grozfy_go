import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/context_colors.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../repository/external_delivery_repository.dart';

/// Shows a bottom sheet asking the driver to enter the customer's 6-digit
/// delivery OTP, verifies it against
/// `grozfy_go.grozfy_go.api.driver.verify_delivery_otp`, and pops `true`
/// once verified (the order is Delivered server-side at that point — the
/// caller just needs to refresh). Pops `null` if the driver cancels.
///
/// Every failure the server can return ("Invalid OTP", "OTP already
/// verified", "Order is not Out for Delivery", "Delivery partner is not
/// assigned to this order") is shown inline, as-is, with the sheet staying
/// open so the driver can retry or cancel.
Future<bool?> showDeliveryOtpSheet(
  BuildContext context, {
  required ExternalDeliveryRepository repository,
  required String externalDelivery,
}) {
  return showAppBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _DeliveryOtpSheet(
      repository: repository,
      externalDelivery: externalDelivery,
    ),
  );
}

class _DeliveryOtpSheet extends StatefulWidget {
  const _DeliveryOtpSheet({
    required this.repository,
    required this.externalDelivery,
  });

  final ExternalDeliveryRepository repository;
  final String externalDelivery;

  @override
  State<_DeliveryOtpSheet> createState() => _DeliveryOtpSheetState();
}

class _DeliveryOtpSheetState extends State<_DeliveryOtpSheet> {
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
      await widget.repository.verifyDeliveryOtp(
        externalDelivery: widget.externalDelivery,
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
      title: 'Delivery OTP',
      subtitle: 'Ask the customer for their 6-digit delivery code',
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
            label: _verifying ? 'Verifying...' : 'Verify & Mark Delivered',
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
