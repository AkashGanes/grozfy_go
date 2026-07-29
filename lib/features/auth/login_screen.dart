import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/context_colors.dart';
import '../../core/widgets/app_shell.dart';
import 'auth_widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _mobileCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _mobileCtrl.dispose();
    super.dispose();
  }

  bool get _isMobileValid =>
      RegExp(r'^[6-9]\d{9}$').hasMatch(_mobileCtrl.text.trim());

  Future<void> _sendOtp() async {
    final app = ref.read(appControllerProvider);
    setState(() => _busy = true);
    final String message = await app.sendOtp(_mobileCtrl.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);

    if (message.contains('successfully')) {
      Navigator.of(context).pushNamed(
        AppRoutes.otp,
        arguments: _mobileCtrl.text.trim(),
      );
    } else {
      showInfoSnack(context, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider);
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color textColor = context.textPrimary;
    final Color mutedColor = context.textSecondary;
    final Color inputBg = context.cardColor;
    final Color borderColor = context.borderSubtle;

    return AuthBackground(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              const AuthStepPill(step: 1),
              const SizedBox(height: 28),
              Text(
                'Enter your mobile\nnumber',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: textColor,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "We'll send a one-time password\nto verify your identity",
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: mutedColor, height: 1.5),
              ),
              const SizedBox(height: 32),
              // Phone input container
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                decoration: BoxDecoration(
                  color: inputBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                  boxShadow: isDark
                      ? null
                      : [
                          BoxShadow(
                            color:
                                AppTheme.oceanBlue.withValues(alpha: 0.06),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: Row(
                  children: [
                    // Country badge
                    Container(
                      margin: const EdgeInsets.all(4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: context.surfaceContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '🇮🇳',
                            style: TextStyle(fontSize: 16),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '+91',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Vertical divider
                    Container(
                      width: 1,
                      height: 28,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: borderColor,
                    ),
                    // Text field
                    Expanded(
                      child: TextField(
                        controller: _mobileCtrl,
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        autofocus: true,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) {
                          if (_isMobileValid && !_busy) _sendOtp();
                        },
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintText: 'Enter mobile number',
                          hintStyle: TextStyle(
                            color: mutedColor,
                            fontWeight: FontWeight.w400,
                          ),
                          counterText: '',
                          filled: false,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                    if (_isMobileValid)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Icon(
                          Icons.check_circle_rounded,
                          color: context.success,
                          size: 20,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 12,
                    color: mutedColor.withValues(alpha: 0.65),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Standard SMS rates may apply',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: mutedColor.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _isMobileValid && !_busy ? _sendOtp : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isMobileValid
                      ? AppTheme.nightBlue
                      : context.surfaceContainer,
                  foregroundColor:
                      _isMobileValid ? Colors.white : context.textDisabled,
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
                    : Text(app.t('send_otp')),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
