import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/providers.dart';
import '../../core/widgets/app_shell.dart';

class LanguageSelectionScreen extends ConsumerStatefulWidget {
  const LanguageSelectionScreen({super.key});

  @override
  ConsumerState<LanguageSelectionScreen> createState() =>
      _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState
    extends ConsumerState<LanguageSelectionScreen> {
  String _selectedCode = 'en';

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider);

    return AppShell(
      title: app.t('choose_language'),
      subtitle: app.t('choose_language_subtitle'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FrostCard(
            child: Text(app.t('language_info')),
          ),
          const SizedBox(height: 16),
          _LanguageTile(
            code: 'en',
            label: 'English',
            sample: 'Ready for delivery shifts',
            selected: _selectedCode == 'en',
            onTap: () => setState(() => _selectedCode = 'en'),
          ),
          const SizedBox(height: 12),
          _LanguageTile(
            code: 'ta',
            label: 'Tamil',
            sample: 'டெலிவரி ஷிப்ட் தயார்',
            selected: _selectedCode == 'ta',
            onTap: () => setState(() => _selectedCode = 'ta'),
          ),
          const SizedBox(height: 12),
          _LanguageTile(
            code: 'hi',
            label: 'Hindi',
            sample: 'डिलीवरी शिफ्ट के लिए तैयार',
            selected: _selectedCode == 'hi',
            onTap: () => setState(() => _selectedCode = 'hi'),
          ),
          const SizedBox(height: 12),
          _LanguageTile(
            code: 'bn',
            label: 'Bengali',
            sample: 'ডেলিভারি শিফটের জন্য প্রস্তুত',
            selected: _selectedCode == 'bn',
            onTap: () => setState(() => _selectedCode = 'bn'),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              app.setLanguage(_selectedCode);
              Navigator.of(context).pushReplacementNamed(
                app.isLoggedIn
                    ? (app.hasSelectedLocation
                          ? AppRoutes.dashboard
                          : AppRoutes.currentLocation)
                    : AppRoutes.login,
              );
            },
            child: Text(app.t('continue')),
          ),
        ],
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.code,
    required this.label,
    required this.sample,
    required this.selected,
    required this.onTap,
  });

  final String code;
  final String label;
  final String sample;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.74),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.black12,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.12),
              child: Text(
                code.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(sample, style: const TextStyle(color: Colors.black54)),
                ],
              ),
            ),
            if (selected)
              Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}
