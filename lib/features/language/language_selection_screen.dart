import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_strings.dart';
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
  void initState() {
    super.initState();
    final String savedLanguage = ref.read(appControllerProvider).languageCode;
    if (savedLanguage.isNotEmpty) {
      _selectedCode = savedLanguage;
    }
  }

  static const _languages = [
    ('en', 'sample_english_ready'),
    ('hi', 'sample_hindi_ready'),
    ('ta', 'sample_tamil_ready'),
    ('te', 'sample_telugu_ready'),
    ('kn', 'sample_kannada_ready'),
    ('ml', 'sample_malayalam_ready'),
    ('bn', 'sample_bengali_ready'),
  ];

  List<Widget> _buildLanguageTiles(dynamic app) {
    final tiles = <Widget>[];
    for (final (code, sampleKey) in _languages) {
      if (tiles.isNotEmpty) tiles.add(const SizedBox(height: 12));
      tiles.add(
        _LanguageTile(
          code: code,
          label: AppStrings.nativeLanguageNames[code] ?? code,
          sample: app.t(sampleKey),
          selected: _selectedCode == code,
          onTap: () => setState(() => _selectedCode = code),
        ),
      );
    }
    return tiles;
  }

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
          ..._buildLanguageTiles(app),
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
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? scheme.surface : scheme.surface.withValues(alpha: 0.74),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? scheme.primary
                : scheme.onSurface.withValues(alpha: 0.12),
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
                  Text(
                    sample,
                    style: TextStyle(
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
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
