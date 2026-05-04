import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/providers.dart';
import '../../core/widgets/app_shell.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _mobileCtrl = TextEditingController();
  final TextEditingController _otpCtrl = TextEditingController();

  bool _busy = false;
  bool _otpSent = false;

  @override
  void initState() {
    super.initState();
    _mobileCtrl.addListener(_onMobileChanged);
  }

  @override
  void dispose() {
    _mobileCtrl.removeListener(_onMobileChanged);
    _mobileCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  void _onMobileChanged() => setState(() {});

  bool get _isMobileValid =>
      RegExp(r'^[6-9]\d{9}$').hasMatch(_mobileCtrl.text.trim());

  Future<void> _sendOtp() async {
    final app = ref.read(appControllerProvider);
    setState(() => _busy = true);
    final String message = await app.sendOtp(_mobileCtrl.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (message.contains('successfully')) {
        _otpSent = true;
      }
    });
    showInfoSnack(context, message);
  }

  Future<void> _login() async {
    final app = ref.read(appControllerProvider);
    setState(() => _busy = true);

    final String? error = await app.loginWithOtp(
      mobile: _mobileCtrl.text.trim(),
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
      // Reset to mobile input if OTP expired or too many attempts
      final lowerErr = error.toLowerCase();
      if (lowerErr.contains('expired') || lowerErr.contains('too many')) {
        setState(() {
          _otpSent = false;
          _otpCtrl.clear();
        });
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

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider);
    final theme = Theme.of(context);

    return AppShell(
      title: app.t('login'),
      subtitle: app.t('login_subtitle'),
      loading: _busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FrostCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.t('mobile_number'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _mobileCtrl,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  enabled: !_otpSent || !_busy,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    hintText: app.t('enter_mobile'),
                    prefixIcon: const Icon(Icons.phone_android_rounded),
                    prefixText: '+91  ',
                    counterText: '',
                    suffixIcon: _isMobileValid
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                if (!_otpSent)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isMobileValid && !_busy ? _sendOtp : null,
                      child: Text(_busy ? app.t('sending_otp') : app.t('send_otp')),
                    ),
                  ),
                if (_otpSent) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        app.t('otp'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _otpSent = false;
                                  _otpCtrl.clear();
                                }),
                        icon: const Icon(Icons.edit, size: 16),
                        label: Text(app.t('change_number')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _otpCtrl,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      hintText: app.t('enter_otp'),
                      prefixIcon: const Icon(Icons.shield_rounded),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _busy ? null : _sendOtp,
                      child: Text(app.t('resend_otp')),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _login,
                      child: Text(_busy ? app.t('verifying') : app.t('verify_login')),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
