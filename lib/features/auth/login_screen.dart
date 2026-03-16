import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_models.dart';
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
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _otpCtrl = TextEditingController();

  AuthMode _authMode = AuthMode.otp;
  bool _busy = false;

  @override
  void dispose() {
    _mobileCtrl.dispose();
    _passwordCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final app = ref.read(appControllerProvider);
    setState(() => _busy = true);
    final String message = await app.sendOtp(_mobileCtrl.text.trim());
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    showInfoSnack(context, message);
  }

  Future<void> _login() async {
    final app = ref.read(appControllerProvider);
    setState(() => _busy = true);

    String? error;
    if (_authMode == AuthMode.password) {
      error = await app.loginWithPassword(
        mobile: _mobileCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
    } else {
      error = await app.loginWithOtp(
        mobile: _mobileCtrl.text.trim(),
        otp: _otpCtrl.text.trim(),
      );
    }

    if (!mounted) {
      return;
    }

    setState(() => _busy = false);

    if (error != null) {
      showInfoSnack(context, error);
      return;
    }

    if (!app.profileCompleted) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.register, (route) => false);
    } else if (!app.isKycComplete) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.kycDocuments, (route) => false);
    } else if (!app.hasSelectedLocation) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.currentLocation, (route) => false);
    } else {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.dashboard, (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider);

    return AppShell(
      title: app.t('login'),
      subtitle: 'Mobile + OTP or Password authentication',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FrostCard(
            child: Column(
              children: [
                _AuthModeSwitcher(
                  mode: _authMode,
                  onChanged: (AuthMode mode) => setState(() {
                    _authMode = mode;
                  }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _mobileCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Mobile Number',
                    prefixIcon: Icon(Icons.phone_android_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                if (_authMode == AuthMode.password)
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline_rounded),
                    ),
                  ),
                if (_authMode == AuthMode.otp)
                  Column(
                    children: [
                      TextField(
                        controller: _otpCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'OTP',
                          prefixIcon: Icon(Icons.shield_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _busy ? null : _sendOtp,
                          child: const Text('Send OTP'),
                        ),
                      ),
                    ],
                  ),
                Row(
                  children: [
                    Checkbox(
                      value: app.rememberMe,
                      onChanged: (bool? value) {
                        app.setRememberMe(value ?? false);
                      },
                    ),
                    const Expanded(child: Text('Remember me')),
                    TextButton(
                      onPressed: _busy ? null : _sendOtp,
                      child: const Text('Forgot password?'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ElevatedButton(
                  onPressed: _busy ? null : _login,
                  child: Text(_busy ? 'Please wait...' : 'Login'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => Navigator.of(context).pushNamed(AppRoutes.register),
            child: const Text('Create New Account'),
          ),
        ],
      ),
    );
  }
}

class _AuthModeSwitcher extends StatelessWidget {
  const _AuthModeSwitcher({required this.mode, required this.onChanged});

  final AuthMode mode;
  final ValueChanged<AuthMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _toggleButton(
              context,
              selected: mode == AuthMode.otp,
              label: 'Mobile + OTP',
              onTap: () => onChanged(AuthMode.otp),
            ),
          ),
          Expanded(
            child: _toggleButton(
              context,
              selected: mode == AuthMode.password,
              label: 'Mobile + Password',
              onTap: () => onChanged(AuthMode.password),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleButton(
    BuildContext context, {
    required bool selected,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: selected ? Theme.of(context).colorScheme.primary : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : Colors.black54,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
