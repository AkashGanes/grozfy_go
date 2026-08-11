import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_strings.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/context_colors.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/app_toast.dart';
import '../dashboard/widgets/section_card.dart';
import '../delivery_radius/ui/delivery_radius_card.dart';
import '../sos/ui/sos_sheet.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appControllerProvider);

    return AppShell(
      title: controller.t('settings'),
      padding: EdgeInsets.zero,
      scrollable: false,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('Appearance', [
            _buildThemeCustomizationSection(context, controller),
            _divider(context),
            _buildLanguageCustomizationSection(context, controller),
          ]),
          const SizedBox(height: 22),
          // Draws its own label: the card hides itself when the feature is off
          // for this driver, and a lone "DELIVERY" heading over nothing is
          // worse than no heading at all.
          DeliveryRadiusCard(sectionLabel: _sectionLabel(context, 'Delivery')),
          const SizedBox(height: 22),
          _section('Safety', [const _SosHapticsTile()]),
          const SizedBox(height: 22),
          _section('Account', [_buildDeleteAccountTile(context)]),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// Groups related rows under one heading, matching the More tab
  /// (`my_orders_screen.dart:_buildSection`) so Settings stops being the one
  /// screen with its own layout language.
  Widget _section(String title, List<Widget> children) {
    return Builder(
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(context, title),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            borderRadius: 18,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  static Widget _sectionLabel(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.6),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _divider(BuildContext context) => Divider(
    height: 1,
    thickness: 1,
    indent: 16,
    endIndent: 16,
    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
  );

  Widget _buildLanguageCustomizationSection(
    BuildContext context,
    dynamic controller,
  ) {
    final theme = Theme.of(context);
    final currentLang = controller.languageCode.isEmpty
        ? 'en'
        : controller.languageCode;

    // Transparent wrapper: this tile now sits inside its section's own
    // SectionCard, and a second Card here would double the border and shadow.
    return Material(
      type: MaterialType.transparency,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          shape: const RoundedRectangleBorder(),
          collapsedShape: const RoundedRectangleBorder(),
          title: Row(
            children: [
              Icon(Icons.language, color: theme.colorScheme.primary, size: 22),
              const SizedBox(width: 12),
              Text(
                controller.t('language'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _getLanguageName(controller, currentLang),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  ...[
                    ('en', 'sample_english_ready'),
                    ('hi', 'sample_hindi_ready'),
                    ('ta', 'sample_tamil_ready'),
                    ('te', 'sample_telugu_ready'),
                    ('kn', 'sample_kannada_ready'),
                    ('ml', 'sample_malayalam_ready'),
                    ('bn', 'sample_bengali_ready'),
                  ].expand((entry) {
                    final code = entry.$1;
                    final sampleKey = entry.$2;
                    return [
                      if (code != 'en') const SizedBox(height: 8),
                      _buildLanguageTile(
                        context: context,
                        code: code,
                        label: AppStrings.nativeLanguageNames[code] ?? code,
                        sample: controller.t(sampleKey),
                        selected: currentLang == code,
                        onTap: () => controller.setLanguage(code),
                      ),
                    ];
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageTile({
    required BuildContext context,
    required String code,
    required String label,
    required String sample,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.2),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: theme.colorScheme.primary.withValues(
                alpha: 0.12,
              ),
              child: Text(
                code.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      fontSize: 15,
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sample,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(
                Icons.check_circle,
                color: theme.colorScheme.primary,
                size: 22,
              ),
          ],
        ),
      ),
    );
  }

  String _getLanguageName(dynamic controller, String code) {
    return AppStrings.nativeLanguageNames[code] ?? code.toUpperCase();
  }

  Widget _buildThemeCustomizationSection(
    BuildContext context,
    dynamic controller,
  ) {
    final theme = Theme.of(context);

    // Transparent wrapper: this tile now sits inside its section's own
    // SectionCard, and a second Card here would double the border and shadow.
    return Material(
      type: MaterialType.transparency,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          shape: const RoundedRectangleBorder(),
          collapsedShape: const RoundedRectangleBorder(),
          title: Row(
            children: [
              Icon(
                Icons.palette_outlined,
                color: theme.colorScheme.primary,
                size: 22,
              ),
              const SizedBox(width: 12),
              Text(
                controller.t('theme_customization'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildThemeModeRow(context, controller, theme),
                  const Divider(height: 28),
                  _buildColorPickerRow(
                    context: context,
                    controller: controller,
                    label: controller.t('background_color'),
                    currentColor: controller.backgroundColor,
                    colorOptions: AppTheme.backgroundColorOptions,
                    onColorSelected: controller.setBackgroundColor,
                  ),
                  const Divider(height: 28),
                  _buildColorPickerRow(
                    context: context,
                    controller: controller,
                    label: controller.t('accent_color'),
                    currentColor: controller.accentColor,
                    colorOptions: AppTheme.accentColorOptions,
                    onColorSelected: controller.setAccentColor,
                  ),
                  const Divider(height: 28),
                  _buildResetButton(context, controller),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeModeRow(
    BuildContext context,
    dynamic controller,
    ThemeData theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          controller.t('theme_mode'),
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildThemeModeOption(
                context: context,
                controller: controller,
                mode: ThemeMode.system,
                icon: Icons.brightness_auto,
                label: controller.t('system'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildThemeModeOption(
                context: context,
                controller: controller,
                mode: ThemeMode.light,
                icon: Icons.light_mode,
                label: controller.t('light'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildThemeModeOption(
                context: context,
                controller: controller,
                mode: ThemeMode.dark,
                icon: Icons.dark_mode,
                label: controller.t('dark'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildColorPickerRow({
    required BuildContext context,
    required dynamic controller,
    required String label,
    required Color currentColor,
    required List<Color> colorOptions,
    required Function(Color) onColorSelected,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: currentColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: colorOptions.map((color) {
            final bool isSelected = currentColor.toARGB32() == color.toARGB32();
            return GestureDetector(
              onTap: () => onColorSelected(color),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline.withValues(alpha: 0.3),
                    width: isSelected ? 3 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.4),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: isSelected
                    ? Icon(
                        Icons.check,
                        size: 18,
                        color: _getContrastColor(color),
                      )
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildThemeModeOption({
    required BuildContext context,
    required dynamic controller,
    required ThemeMode mode,
    required IconData icon,
    required String label,
  }) {
    final bool isSelected = controller.themeMode == mode;
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => controller.setThemeMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Account deletion, moved here from the More tab.
  ///
  /// Kept last and visually separated from the preference cards above: it is
  /// the only destructive, irreversible action on this screen. Play requires
  /// an in-app deletion path, so this entry must stay reachable — More →
  /// Settings → Delete Account.
  Widget _buildDeleteAccountTile(BuildContext context) {
    // context.danger, not colorScheme.error — this is the same treatment as
    // Log out on the More tab, and the two must not drift apart.
    final Color danger = context.danger;

    return ListTile(
      leading: Icon(Icons.person_remove_outlined, color: danger, size: 22),
      title: Text(
        'Delete Account',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: danger,
        ),
      ),
      subtitle: const Text('Request permanent removal of your account.'),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: danger.withValues(alpha: 0.4),
        size: 20,
      ),
      onTap: () =>
          Navigator.of(context).pushNamed(AppRoutes.legalDeleteAccount),
    );
  }

  /// Lives inside the Theme Customization panel — it resets the theme, so it
  /// belongs with the controls it undoes rather than in a section of its own.
  Widget _buildResetButton(BuildContext context, dynamic controller) {
    final theme = Theme.of(context);

    return OutlinedButton.icon(
      icon: const Icon(Icons.refresh, size: 18),
      label: Text(controller.t('reset_defaults')),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.5),
        ),
      ),
      onPressed: () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(controller.t('reset_theme_title')),
            content: Text(controller.t('reset_theme_message')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(controller.t('cancel')),
              ),
              FilledButton(
                onPressed: () {
                  controller.resetThemeToDefaults();
                  Navigator.of(context).pop();
                  AppToast.show(context, controller.t('reset_success'));
                },
                child: Text(controller.t('reset')),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getContrastColor(Color color) {
    final double luminance = color.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }
}

/// Toggles the haptic feedback on the emergency (SOS) button.
///
/// Scoped to SOS deliberately rather than being an app-wide haptics switch:
/// this exists so a driver can trigger an alert discreetly when being watched,
/// not as a general preference.
class _SosHapticsTile extends StatefulWidget {
  const _SosHapticsTile();

  @override
  State<_SosHapticsTile> createState() => _SosHapticsTileState();
}

class _SosHapticsTileState extends State<_SosHapticsTile> {
  bool _enabled = SosHaptics.enabled;

  @override
  void initState() {
    super.initState();
    SosHaptics.load().then((value) {
      if (mounted) setState(() => _enabled = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SwitchListTile(
      value: _enabled,
      secondary: Icon(
        Icons.vibration,
        color: theme.colorScheme.primary,
        size: 22,
      ),
      title: Text(
        'Emergency button vibration',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: const Text(
        'Vibrate while holding the SOS button. Turn off to raise an alert '
        'silently.',
      ),
      onChanged: (value) {
        setState(() => _enabled = value);
        SosHaptics.setEnabled(value);
      },
    );
  }
}
