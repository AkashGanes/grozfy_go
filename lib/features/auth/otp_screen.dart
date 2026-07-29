import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/context_colors.dart';
import '../../core/widgets/app_shell.dart';
import 'auth_widgets.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final TextEditingController _otpCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _busy = false;
  int _resendSeconds = 30;
  Timer? _resendTimer;
  String _mobile = '';
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String) _mobile = args;
      _startResendTimer();
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _otpCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_resendSeconds > 0) {
          _resendSeconds--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  Future<void> _resendOtp() async {
    final app = ref.read(appControllerProvider);
    setState(() => _busy = true);
    final String message = await app.sendOtp(_mobile);
    if (!mounted) return;
    setState(() => _busy = false);
    showInfoSnack(context, message);
    if (message.contains('successfully')) {
      _otpCtrl.clear();
      _startResendTimer();
    }
  }

  Future<void> _login() async {
    final app = ref.read(appControllerProvider);
    setState(() => _busy = true);

    final String? error = await app.loginWithOtp(
      mobile: _mobile,
      otp: _otpCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _busy = false);

    if (error == 'ACCOUNT_NOT_FOUND') {
      Navigator.of(context)
          .pushNamedAndRemoveUntil(AppRoutes.register, (route) => false);
      return;
    }

    if (error != null) {
      final lowerErr = error.toLowerCase();
      if (lowerErr.contains('expired') || lowerErr.contains('too many')) {
        showInfoSnack(context, error);
        if (context.mounted) Navigator.of(context).pop();
        return;
      }
      showInfoSnack(context, error);
      return;
    }

    if (!app.profileCompleted) {
      Navigator.of(context)
          .pushNamedAndRemoveUntil(AppRoutes.register, (route) => false);
    } else if (!app.isKycComplete) {
      Navigator.of(context)
          .pushNamedAndRemoveUntil(AppRoutes.kycDocuments, (route) => false);
    } else if (!app.hasSelectedLocation) {
      Navigator.of(context)
          .pushNamedAndRemoveUntil(AppRoutes.currentLocation, (route) => false);
    } else {
      Navigator.of(context)
          .pushNamedAndRemoveUntil(AppRoutes.dashboard, (route) => false);
    }
  }

  String _formatMobile(String m) {
    if (m.length != 10) return m;
    return '${m.substring(0, 5)} ${m.substring(5)}';
  }

  String _formatTimer() {
    final int m = _resendSeconds ~/ 60;
    final int s = _resendSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildOtpBox(int index, String otp) {
    final bool filled = index < otp.length;
    final bool isActive = index == otp.length && _focusNode.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 46,
      height: 56,
      decoration: BoxDecoration(
        color: filled ? context.cardColor : context.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? context.textPrimary
              : filled
                  ? AppTheme.oceanBlue
                  : context.borderStrong,
          width: isActive || filled ? 2 : 1.5,
        ),
      ),
      child: Center(
        child: Text(
          filled ? otp[index] : '',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: context.textPrimary,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider);
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color textColor = context.textPrimary;
    final Color mutedColor = context.textSecondary;
    final String otp = _otpCtrl.text;
    final bool canSubmit = otp.length == 6 && !_busy;

    return AuthBackground(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              // Back button
              GestureDetector(
                onTap: _busy ? null : () => Navigator.of(context).pop(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: context.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: isDark
                        ? null
                        : [
                            BoxShadow(
                              color: AppTheme.oceanBlue.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: Icon(
                    Icons.arrow_back_rounded,
                    color: textColor,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const AuthStepPill(step: 2),
              const SizedBox(height: 28),
              Text(
                'Verify OTP',
                style: theme.textTheme.headlineMedium
                    ?.copyWith(color: textColor),
              ),
              const SizedBox(height: 10),
              Text(
                "We've sent a 6-digit code to your number",
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: mutedColor, height: 1.5),
              ),
              const SizedBox(height: 16),
              // Phone chip
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: context.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.phone_android_rounded,
                      size: 15,
                      color: mutedColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '+91 ${_formatMobile(_mobile)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(
                        'Change',
                        style: TextStyle(
                          color: AppTheme.oceanBlue,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              // OTP boxes with hidden input field
              GestureDetector(
                onTap: () => _focusNode.requestFocus(),
                behavior: HitTestBehavior.opaque,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(
                        6,
                        (i) => _buildOtpBox(i, otp),
                      ),
                    ),
                    // Hidden TextField — captures keyboard input
                    IgnorePointer(
                      child: Opacity(
                        opacity: 0,
                        child: SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: TextField(
                            controller: _otpCtrl,
                            focusNode: _focusNode,
                            autofocus: true,
                            maxLength: 6,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) {
                              if (canSubmit) _login();
                            },
                            decoration:
                                const InputDecoration(counterText: ''),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Resend row
              Row(
                children: [
                  if (_resendSeconds > 0) ...[
                    Icon(
                      Icons.timer_outlined,
                      size: 14,
                      color: mutedColor,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Resend in ${_formatTimer()}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: mutedColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const Spacer(),
                  GestureDetector(
                    onTap:
                        _resendSeconds == 0 && !_busy ? _resendOtp : null,
                    child: Text(
                      app.t('resend_otp'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _resendSeconds == 0 && !_busy
                            ? AppTheme.oceanBlue
                            : mutedColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: canSubmit ? _login : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canSubmit
                      ? AppTheme.nightBlue
                      : context.surfaceContainer,
                  foregroundColor:
                      canSubmit ? Colors.white : context.textDisabled,
                  disabledBackgroundColor: context.surfaceContainer,
                  disabledForegroundColor: context.textDisabled,
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Poppins',
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(app.t('verify_login')),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
