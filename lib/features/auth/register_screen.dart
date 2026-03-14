import 'package:flutter/material.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/widgets/app_shell.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _mobileCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _referralCtrl = TextEditingController();
  final TextEditingController _otpCtrl = TextEditingController();

  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _referralCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final app = AppScope.of(context);
    setState(() => _busy = true);
    final String message = await app.sendOtp(_mobileCtrl.text.trim());
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    showInfoSnack(context, message);
  }

  Future<void> _register() async {
    final app = AppScope.of(context);
    setState(() => _busy = true);

    final String? error = await app.registerPartner(
      fullName: _nameCtrl.text,
      mobile: _mobileCtrl.text.trim(),
      password: _passwordCtrl.text,
      otp: _otpCtrl.text.trim(),
      email: _emailCtrl.text,
      referralCode: _referralCtrl.text,
    );

    if (!mounted) {
      return;
    }

    setState(() => _busy = false);

    if (error != null) {
      showInfoSnack(context, error);
      return;
    }

    await app.completeProfile();

    if (!mounted) {
      return;
    }

    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.currentLocation, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Partner Registration',
      subtitle: 'Create account and verify mobile using OTP',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FrostCard(
            child: Column(
              children: [
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _mobileCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Mobile Number',
                    prefixIcon: Icon(Icons.phone_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email (Optional)',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _referralCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Referral Code (Optional)',
                    prefixIcon: Icon(Icons.card_giftcard_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _otpCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'OTP',
                    prefixIcon: Icon(Icons.shield_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy ? null : _sendOtp,
                    child: const Text('Send OTP'),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _busy ? null : _register,
                  child: Text(_busy ? 'Creating account...' : 'Create Account'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
