import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/providers.dart';
import '../../core/widgets/app_shell.dart';
import '../legal/legal_screens.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();

  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  bool get _isFormValid => _nameCtrl.text.trim().isNotEmpty;

  Future<void> _register() async {
    final app = ref.read(appControllerProvider);

    // Consent is taken before the account is created, so we are not processing
    // the partner's data ahead of their agreement. The gate returns a result
    // only after they have opened a document and ticked the box; anything else
    // — back button, dismissal — returns null and leaves them on this screen
    // with nothing submitted.
    final LegalConsentResult? consent = await Navigator.of(context)
        .pushNamed<LegalConsentResult>(AppRoutes.legalConsent);
    if (consent == null || !mounted) return;

    setState(() => _busy = true);

    // The consent travels with the registration request rather than in a
    // follow-up call, so an account can never exist without its consent record.
    final String? error = await app.registerNewPartner(
      fullName: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      consent: consent,
    );

    if (!mounted) return;
    setState(() => _busy = false);

    if (error != null) {
      showInfoSnack(context, error);
      return;
    }

    await app.completeProfile();

    if (!mounted) return;

    Navigator.of(context)
        .pushNamedAndRemoveUntil(AppRoutes.kycDocuments, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider);
    final theme = Theme.of(context);
    final String mobile = app.pendingRegistrationMobile ?? '';

    return AppShell(
      title: app.t('complete_registration'),
      subtitle: app.t('register_subtitle'),
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
                  enabled: false,
                  decoration: InputDecoration(
                    hintText: mobile.isEmpty ? app.t('verified') : '+91  $mobile',
                    prefixIcon: const Icon(Icons.phone_android_rounded),
                    suffixIcon:
                        const Icon(Icons.check_circle, color: Colors.green),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  app.t('full_name'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: app.t('enter_full_name'),
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  app.t('email_optional'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: app.t('enter_email'),
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isFormValid && !_busy ? _register : null,
                    child: Text(
                        _busy ? app.t('creating_account') : app.t('create_account')),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pushNamedAndRemoveUntil(
                              AppRoutes.login,
                              (route) => false,
                            ),
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: Text(app.t('back_to_login')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
