import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/legal_constants.dart';
import '../../core/models/app_version_status.dart';
import '../../core/state/app_controller.dart';
import '../../core/state/providers.dart';
import '../../core/theme/context_colors.dart';
import '../../core/utils/call_utils.dart';

/// Sits between [MaterialApp.builder]'s child and the screen, so the update UI
/// covers every route — including one opened from an FCM deep link — rather
/// than only the splash.
///
/// Both states are bottom sheets over the live app, and neither is a pushed
/// route: the gate lives above the app's [Navigator], so it has nothing to push
/// to, and nothing underneath can dismiss it with a stray `pop()`. The
/// difference is enforcement — [MandatoryUpdateSheet] blocks input and offers no
/// way out but updating, [OptionalUpdateSheet] can be dismissed. See the
/// back-button note on [MandatoryUpdateSheet.didPopRoute]: sitting above the
/// Navigator rules out the usual ways of intercepting it.
class ForceUpdateGate extends ConsumerWidget {
  const ForceUpdateGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppController controller = ref.watch(appControllerProvider);
    final AppVersionStatus status = controller.versionStatus;

    if (controller.isUpdateBlocking) {
      // The app stays mounted and visible behind the sheet, but every pointer
      // event is absorbed by the barrier inside [MandatoryUpdateSheet], so it
      // is look-but-don't-touch. "Blocks further app use" is enforced by that
      // barrier, not by hiding the screen.
      return Stack(
        children: <Widget>[
          child,
          Positioned.fill(
            child: MandatoryUpdateSheet(
              status: status,
              onDismiss: () => ref
                  .read(appControllerProvider.notifier)
                  .dismissMandatoryUpdate(),
            ),
          ),
        ],
      );
    }

    if (controller.shouldPromptOptionalUpdate) {
      return Stack(
        children: <Widget>[
          child,
          Positioned.fill(
            child: OptionalUpdateSheet(
              status: status,
              onDismiss: () => ref
                  .read(appControllerProvider.notifier)
                  .dismissOptionalUpdate(),
            ),
          ),
        ],
      );
    }

    return child;
  }
}

/// The unsupported-build sheet, over the dimmed app.
///
/// Stronger than [OptionalUpdateSheet] but, by product decision, not a hard
/// lockout: it carries a "Later". While it is up the barrier swallows every
/// tap aimed at the app behind, and the scrim does not dismiss — leaving is a
/// deliberate act, not a stray tap. Dismissal lasts the session only; see
/// [AppController.dismissMandatoryUpdate].
class MandatoryUpdateSheet extends ConsumerStatefulWidget {
  const MandatoryUpdateSheet({
    super.key,
    required this.status,
    required this.onDismiss,
  });

  final AppVersionStatus status;
  final VoidCallback onDismiss;

  @override
  ConsumerState<MandatoryUpdateSheet> createState() =>
      _MandatoryUpdateSheetState();
}

class _MandatoryUpdateSheetState extends ConsumerState<MandatoryUpdateSheet>
    with WidgetsBindingObserver {
  String _installedVersion = '';
  bool _storeUnavailable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInstalledVersion();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back behaves as "Later" — the sheet has that button, so a back press that
  /// did nothing would just read as broken. It never closes the app.
  ///
  /// Partial by construction: observers are consulted in registration order and
  /// WidgetsApp registers first, so when the app's Navigator has a route to pop
  /// it pops one before we are asked, and the sheet stays. Closing that hole
  /// would mean unmounting the app entirely, which is the full-screen treatment
  /// this sheet replaced.
  ///
  /// The alternatives don't work above the app's Navigator: PopScope has no
  /// enclosing ModalRoute to register with, and BackButtonListener asserts on a
  /// missing Router (this is a MaterialApp with routes, not MaterialApp.router)
  /// — that assert crashed every launch before this observer replaced it.
  @override
  Future<bool> didPopRoute() async {
    widget.onDismiss();
    return true;
  }

  Future<void> _update() async {
    final bool opened = await _openStore(widget.status);
    if (!mounted) return;
    setState(() => _storeUnavailable = !opened);
  }

  Future<void> _loadInstalledVersion() async {
    final String label = await _readInstalledVersionLabel();
    if (!mounted) return;
    setState(() => _installedVersion = label);
  }

  @override
  Widget build(BuildContext context) {
    final AppController controller = ref.watch(appControllerProvider);
    final AppVersionStatus status = widget.status;

    final String title = status.title.isNotEmpty
        ? status.title
        : controller.t('update_required_title');
    final String message = status.message.isNotEmpty
        ? status.message
        : controller.t('update_required_message');

    return Stack(
      children: <Widget>[
        // A ModalBarrier, not a GestureDetector: it absorbs every pointer
        // event aimed at the app behind — drags and scrolls included, which a
        // tap handler would let through. `dismissible: false` is the point:
        // this scrim has no dismiss.
        const Positioned.fill(
          child: ModalBarrier(color: Color(0x8A000000), dismissible: false),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: context.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // No grab handle: it would advertise a drag-to-dismiss this
                    // sheet deliberately does not have.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _UpdateBadge(
                          icon: Icons.system_update_rounded,
                          background: context.warningContainer,
                          foreground: context.warning,
                          size: 44,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                title,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: context.textPrimary,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                message,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: context.textSecondary,
                                      height: 1.45,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _VersionSummary(
                      installedVersion: _installedVersion,
                      latestVersion: status.latestVersion,
                      controller: controller,
                    ),
                    if (status.releaseNotes.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 20),
                      _ReleaseNotes(
                        notes: status.releaseNotes,
                        heading: controller.t('update_whats_new'),
                      ),
                    ],
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: _update,
                      icon: const Icon(Icons.download_rounded, size: 20),
                      label: Text(controller.t('update_now')),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    // Doubles as the escape hatch a "Retry check" used to
                    // provide: if the block is wrong — a bad floor, a verdict
                    // cached just before the driver updated — this is what
                    // stops it from stranding them.
                    TextButton(
                      onPressed: widget.onDismiss,
                      style: TextButton.styleFrom(
                        foregroundColor: context.textSecondary,
                      ),
                      child: Text(controller.t('update_later')),
                    ),
                    // Support surfaces only once the store link has actually
                    // failed. A driver who can reach neither the store nor the
                    // app has no other way out; until that happens the extra
                    // link is noise on a sheet that should have one action.
                    if (_storeUnavailable) ...<Widget>[
                      _StoreUnavailableNotice(
                        message: controller.t('update_store_unavailable'),
                      ),
                      TextButton(
                        onPressed: () =>
                            makePhoneCall(context, LegalConstants.supportPhone),
                        style: TextButton.styleFrom(
                          foregroundColor: context.textTertiary,
                        ),
                        child: Text(controller.t('update_need_help')),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The dismissible prompt. Rendered in-tree with its own scrim so it behaves
/// the same whichever route is underneath.
class OptionalUpdateSheet extends ConsumerStatefulWidget {
  const OptionalUpdateSheet({
    super.key,
    required this.status,
    required this.onDismiss,
  });

  final AppVersionStatus status;
  final VoidCallback onDismiss;

  @override
  ConsumerState<OptionalUpdateSheet> createState() =>
      _OptionalUpdateSheetState();
}

class _OptionalUpdateSheetState extends ConsumerState<OptionalUpdateSheet>
    with WidgetsBindingObserver {
  bool _storeUnavailable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back dismisses the prompt — but only when the app's Navigator has nothing
  /// to pop, since WidgetsApp is consulted first and answers the press by
  /// popping a route. In practice that covers the common case (the prompt shows
  /// on the first screen after launch); deeper in the stack, back navigates
  /// underneath and the prompt stays until "Later" or "Update now". Making this
  /// airtight would mean unmounting the app the way the blocking branch does,
  /// which is the wrong trade for a dismissible prompt.
  @override
  Future<bool> didPopRoute() async {
    widget.onDismiss();
    return true;
  }

  Future<void> _update() async {
    final bool opened = await _openStore(widget.status);
    if (!mounted) return;
    setState(() => _storeUnavailable = !opened);
  }

  @override
  Widget build(BuildContext context) {
    final AppController controller = ref.watch(appControllerProvider);
    final AppVersionStatus status = widget.status;
    final VoidCallback onDismiss = widget.onDismiss;

    final String title = status.title.isNotEmpty
        ? status.title
        : controller.t('update_available_title');
    final String message = status.message.isNotEmpty
        ? status.message
        : controller.t('update_available_message');

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: context.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: context.borderSubtle,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _UpdateBadge(
                          icon: Icons.auto_awesome_rounded,
                          background: context.infoContainer,
                          foreground: context.info,
                          size: 44,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                title,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: context.textPrimary,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                message,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: context.textSecondary,
                                      height: 1.45,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (status.releaseNotes.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 16),
                      _ReleaseNotes(
                        notes: status.releaseNotes,
                        heading: controller.t('update_whats_new'),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: onDismiss,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              foregroundColor: context.textSecondary,
                              side: BorderSide(color: context.borderSubtle),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(controller.t('update_later')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: _update,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(controller.t('update_now')),
                          ),
                        ),
                      ],
                    ),
                    if (_storeUnavailable)
                      _StoreUnavailableNotice(
                        message: controller.t('update_store_unavailable'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared pieces
// ---------------------------------------------------------------------------

class _UpdateBadge extends StatelessWidget {
  const _UpdateBadge({
    required this.icon,
    required this.background,
    required this.foreground,
    this.size = 72,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Icon(icon, size: size * 0.45, color: foreground),
      ),
    );
  }
}

class _VersionSummary extends StatelessWidget {
  const _VersionSummary({
    required this.installedVersion,
    required this.latestVersion,
    required this.controller,
  });

  final String installedVersion;
  final String latestVersion;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    if (installedVersion.isEmpty && latestVersion.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.fillSubtle,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        children: <Widget>[
          if (installedVersion.isNotEmpty)
            _VersionRow(
              label: controller.t('update_installed_version'),
              value: installedVersion,
            ),
          if (installedVersion.isNotEmpty && latestVersion.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: context.borderSubtle),
            ),
          if (latestVersion.isNotEmpty)
            _VersionRow(
              label: controller.t('update_latest_version'),
              value: latestVersion,
              emphasise: true,
            ),
        ],
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  final String label;
  final String value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.textSecondary),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: emphasise ? context.success : context.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _ReleaseNotes extends StatelessWidget {
  const _ReleaseNotes({required this.notes, required this.heading});

  final List<String> notes;
  final String heading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          heading,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        for (final String note in notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 8),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: context.iconMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    note,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Store launch
// ---------------------------------------------------------------------------

/// Opens the store listing. Falls back to a listing built from this app's own
/// package name when the backend sent no link.
///
/// Returns false when nothing could be opened, so the caller can surface that
/// inline — a blocking screen with a dead button is worse than no blocking
/// screen at all. Reporting it inline rather than through a SnackBar keeps it
/// independent of whether a ScaffoldMessenger exists above the app's Navigator.
Future<bool> _openStore(AppVersionStatus status) async {
  final List<Uri> candidates = <Uri>[];

  if (status.storeUrl.isNotEmpty) {
    final Uri? parsed = Uri.tryParse(status.storeUrl);
    if (parsed != null) candidates.add(parsed);
  }

  final String packageName = await _readPackageName();
  if (packageName.isNotEmpty && _isAndroid) {
    candidates.add(Uri.parse('market://details?id=$packageName'));
    candidates.add(
      Uri.parse('https://play.google.com/store/apps/details?id=$packageName'),
    );
  }

  for (final Uri uri in candidates) {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (_) {
      // Try the next candidate.
    }
  }

  return false;
}

bool get _isAndroid {
  try {
    return Platform.isAndroid;
  } catch (_) {
    return true;
  }
}

Future<String> _readPackageName() async {
  try {
    final PackageInfo info = await PackageInfo.fromPlatform();
    return info.packageName.trim();
  } catch (_) {
    return '';
  }
}

/// `1.0.1 (2)` — the build number is what the supported-version floor is
/// actually expressed in, so it belongs on screen next to the marketing
/// version when a driver is reading this out to support.
Future<String> _readInstalledVersionLabel() async {
  try {
    final PackageInfo info = await PackageInfo.fromPlatform();
    final String version = info.version.trim();
    final String build = info.buildNumber.trim();
    if (version.isEmpty) return '';
    return build.isEmpty ? version : '$version ($build)';
  } catch (_) {
    return '';
  }
}

/// Shown under the update button when no store could be opened.
class _StoreUnavailableNotice extends StatelessWidget {
  const _StoreUnavailableNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline_rounded, size: 16, color: context.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.danger),
            ),
          ),
        ],
      ),
    );
  }
}
