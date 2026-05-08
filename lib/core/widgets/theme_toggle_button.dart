import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';

class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeController = ref.watch(themeControllerProvider);

    final (IconData icon, String tooltip) = switch (themeController.themeMode) {
      ThemeMode.system => (Icons.brightness_auto, 'System'),
      ThemeMode.light => (Icons.light_mode, 'Light'),
      ThemeMode.dark => (Icons.dark_mode, 'Dark'),
    };

    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: () {
        final ThemeMode next = switch (themeController.themeMode) {
          ThemeMode.system => ThemeMode.light,
          ThemeMode.light => ThemeMode.dark,
          ThemeMode.dark => ThemeMode.system,
        };
        ref.read(themeControllerProvider).setThemeMode(next);
      },
    );
  }
}
