import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../model/sos_alert.dart';
import '../repository/sos_repository.dart';

const Color _kDanger = Color(0xFFE8384F);
const Duration _kHoldDuration = Duration(seconds: 3);
const int _kCountdownSeconds = 5;

/// Haptic feedback for the emergency button, and the driver's opt-out.
///
/// Defaults to **on** — a driver in a panic needs to feel the hold registering
/// rather than watch a progress ring. Turning it off is a safety option, not a
/// cosmetic preference: "unsafe situation" is one of the reasons on offer, and
/// a driver triggering SOS discreetly while someone is watching them does not
/// want the phone buzzing in their hand.
///
/// The value is cached in memory because haptics fire from synchronous
/// gesture and animation callbacks that cannot await a preference read.
class SosHaptics {
  const SosHaptics._();

  static const String prefKey = 'sos_haptics_enabled';

  static bool _enabled = true;

  static bool get enabled => _enabled;

  /// Loads the stored preference into the cache. Called when the sheet opens
  /// and when the settings toggle is built.
  static Future<bool> load() async {
    final prefs = await SharedPreferences.getInstance();
    return _enabled = prefs.getBool(prefKey) ?? true;
  }

  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKey, value);
  }

  static void light() {
    if (_enabled) HapticFeedback.lightImpact();
  }

  static void selection() {
    if (_enabled) HapticFeedback.selectionClick();
  }

  static void medium() {
    if (_enabled) HapticFeedback.mediumImpact();
  }

  static void heavy() {
    if (_enabled) HapticFeedback.heavyImpact();
  }
}

/// Opens the emergency flow: hold 3s → pick reasons → 5s countdown → send.
Future<void> showSosSheet(BuildContext context) {
  return showAppBottomSheet<void>(
    context: context,
    builder: (_) => const SosSheet(),
  );
}

enum _SosStep { hold, reasons, countdown, sending, success, failure }

/// Emergency assistance flow.
///
/// Two guards against an accidental trigger, both required by the feature
/// spec: a 3-second press-and-hold to arm, then a 5-second countdown the
/// driver can cancel.
///
/// **Nothing leaves the device — and nothing is stored — until the countdown
/// elapses.** Cancelling therefore leaves zero trace, so no queue or retry can
/// later deliver an alert the driver explicitly stopped. The GPS fix is warmed
/// during the countdown purely to save seconds on send; it is discarded on
/// cancel.
class SosSheet extends StatefulWidget {
  const SosSheet({super.key});

  @override
  State<SosSheet> createState() => _SosSheetState();
}

class _SosSheetState extends State<SosSheet>
    with SingleTickerProviderStateMixin {
  final SosRepository _repository = SosRepository();
  final TextEditingController _noteController = TextEditingController();
  final Set<SosReason> _reasons = <SosReason>{};

  late final AnimationController _holdController = AnimationController(
    vsync: this,
    duration: _kHoldDuration,
  )..addStatusListener(_onHoldStatusChanged);

  _SosStep _step = _SosStep.hold;
  int _secondsLeft = _kCountdownSeconds;
  Timer? _countdownTimer;

  /// Started when the countdown begins so the fix is usually ready by the time
  /// it elapses. Never awaited unless the alert is actually sent.
  Future<Position?>? _positionFuture;

  SosTriggerResult? _result;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    // Refresh the cached preference; the sheet is rarely the first thing built.
    SosHaptics.load();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _holdController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Flow
  // ---------------------------------------------------------------------------

  void _onHoldStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed || _step != _SosStep.hold) return;
    SosHaptics.heavy();
    setState(() => _step = _SosStep.reasons);
  }

  void _startCountdown() {
    SosHaptics.medium();
    _positionFuture = _acquirePosition();
    setState(() {
      _step = _SosStep.countdown;
      _secondsLeft = _kCountdownSeconds;
    });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      if (_secondsLeft <= 1) {
        timer.cancel();
        _send();
        return;
      }
      setState(() => _secondsLeft -= 1);
    });
  }

  /// Aborts before anything has been stored or sent.
  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _positionFuture = null;
    _holdController.reset();
    SosHaptics.selection();
    setState(() => _step = _SosStep.hold);
  }

  Future<void> _send() async {
    setState(() => _step = _SosStep.sending);
    try {
      final Future<Position?> pending = _positionFuture ?? _acquirePosition();
      _positionFuture = pending;
      final Position? position = await pending;
      if (position == null) {
        // Drop the resolved-null future so "Try again" re-acquires instead of
        // re-awaiting the same failed fix and failing instantly.
        _positionFuture = null;
        throw Exception(
          'Could not get your location. Turn on location access and try again, '
          'or call operations directly.',
        );
      }

      final result = await _repository.triggerSos(
        latitude: position.latitude,
        longitude: position.longitude,
        message: encodeSosMessage(
          reasons: _reasons,
          note: _noteController.text,
        ),
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _step = _SosStep.success;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
        _step = _SosStep.failure;
      });
    }
  }

  /// Best-effort fix. Falls back to the last known position rather than
  /// failing — a slightly stale coordinate reaches ops; no alert does not.
  Future<Position?> _acquirePosition() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> _callOperations() async {
    final phone = ApiConstants.sosFallbackOpsPhone.trim();
    if (phone.isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: phone));
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Don't let a swipe orphan an in-flight alert whose outcome the driver
      // then never sees.
      canPop: _step != _SosStep.sending,
      child: AppBottomSheet(
        title: 'Emergency assistance',
        subtitle: _subtitle(),
        leadingIcon: Icons.sos_rounded,
        leadingIconColor: _kDanger,
        scrollable: true,
        child: switch (_step) {
          _SosStep.hold => _buildHoldStep(),
          _SosStep.reasons => _buildReasonsStep(),
          _SosStep.countdown => _buildCountdownStep(),
          _SosStep.sending => _buildSendingStep(),
          _SosStep.success => _buildSuccessStep(),
          _SosStep.failure => _buildFailureStep(),
        },
      ),
    );
  }

  String _subtitle() => switch (_step) {
    _SosStep.hold => 'Hold the button to start an emergency alert.',
    _SosStep.reasons => 'What is happening? Select all that apply.',
    _SosStep.countdown => 'Alerting operations. Cancel if this was a mistake.',
    _SosStep.sending => 'Sending your alert…',
    _SosStep.success => 'Operations has been alerted.',
    _SosStep.failure => 'Your alert could not be confirmed.',
  };

  Widget _buildHoldStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        _HoldToActivateButton(controller: _holdController),
        const SizedBox(height: 16),
        Text(
          'Your location, driver ID and active trip are shared with operations.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildReasonsStep() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: SosReason.values.map((reason) {
            final selected = _reasons.contains(reason);
            return FilterChip(
              label: Text(reason.label),
              selected: selected,
              showCheckmark: false,
              selectedColor: _kDanger.withValues(alpha: 0.14),
              side: BorderSide(
                color: selected
                    ? _kDanger
                    : scheme.onSurface.withValues(alpha: 0.18),
              ),
              labelStyle: TextStyle(
                color: selected ? _kDanger : scheme.onSurface,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              onSelected: (value) => setState(() {
                value ? _reasons.add(reason) : _reasons.remove(reason);
              }),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _noteController,
          maxLines: 2,
          maxLength: kSosMessageMaxLength,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Add a note (optional)',
            border: OutlineInputBorder(),
            counterText: '',
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _reasons.isEmpty ? null : _startCountdown,
          style: FilledButton.styleFrom(
            backgroundColor: _kDanger,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
          ),
          child: const Text('Send emergency alert'),
        ),
        TextButton(
          onPressed: () {
            _holdController.reset();
            setState(() => _step = _SosStep.hold);
          },
          child: const Text('Back'),
        ),
      ],
    );
  }

  Widget _buildCountdownStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Text(
          '$_secondsLeft',
          style: const TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.w800,
            color: _kDanger,
          ),
        ),
        const SizedBox(height: 4),
        const Text('Sending emergency alert…'),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _cancelCountdown,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              side: const BorderSide(color: _kDanger, width: 2),
              foregroundColor: _kDanger,
            ),
            child: const Text(
              'CANCEL',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSendingStep() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Center(child: CircularProgressIndicator(color: _kDanger)),
    );
  }

  Widget _buildSuccessStep() {
    final result = _result!;
    final scheme = Theme.of(context).colorScheme;
    final trip = result.deliveryTrip ?? result.externalDelivery;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusBanner(
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF12A150),
          title: 'Alert sent',
          body: trip == null
              ? 'Reference ${result.alertName}. Your location was shared with operations.'
              : 'Reference ${result.alertName}. Your location and $trip were shared with operations.',
        ),
        // The backend files an alert even when it cannot link the session user
        // to a Driver record (68% have no `user_id`). Ops still receives it,
        // but may not know who it is from — say so rather than showing an
        // unqualified success.
        if (!result.driverResolution.isResolved) ...[
          const SizedBox(height: 10),
          _StatusBanner(
            icon: Icons.info_outline_rounded,
            color: const Color(0xFFB26A00),
            title: 'Your driver profile could not be linked',
            body:
                'Operations has your alert and location. If nobody contacts you shortly, call them directly.',
          ),
        ],
        const SizedBox(height: 16),
        if (ApiConstants.sosFallbackOpsPhone.trim().isNotEmpty)
          OutlinedButton.icon(
            onPressed: _callOperations,
            icon: const Icon(Icons.call_rounded),
            label: const Text('Call operations'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: scheme.onSurface),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildFailureStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusBanner(
          icon: Icons.error_outline_rounded,
          color: _kDanger,
          title: 'Alert not sent',
          body: _errorMessage,
        ),
        const SizedBox(height: 16),
        if (ApiConstants.sosFallbackOpsPhone.trim().isNotEmpty)
          FilledButton.icon(
            onPressed: _callOperations,
            icon: const Icon(Icons.call_rounded),
            label: const Text('Call operations'),
            style: FilledButton.styleFrom(
              backgroundColor: _kDanger,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _send,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          child: const Text('Try again'),
        ),
        const SizedBox(height: 6),
        // The endpoint has no idempotency key, so a retry that succeeds after a
        // request that silently landed will create a second alert. Say so
        // rather than letting ops discover the duplicate.
        Text(
          'Trying again may create a second alert.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Hold-to-activate button
// -----------------------------------------------------------------------------

class _HoldToActivateButton extends StatefulWidget {
  const _HoldToActivateButton({required this.controller});

  final AnimationController controller;

  @override
  State<_HoldToActivateButton> createState() => _HoldToActivateButtonState();
}

class _HoldToActivateButtonState extends State<_HoldToActivateButton> {
  static const Duration _pulseInterval = Duration(milliseconds: 400);

  Timer? _pulseTimer;

  @override
  void dispose() {
    _pulseTimer?.cancel();
    super.dispose();
  }

  /// Pulses while the button is held, hardening as the ring fills, so the
  /// driver can feel the hold registering without watching the screen. The
  /// completion `heavy()` is fired by the parent's status listener.
  void _startHold() {
    SosHaptics.selection();
    widget.controller.forward();
    _pulseTimer?.cancel();
    _pulseTimer = Timer.periodic(_pulseInterval, (timer) {
      if (widget.controller.value >= 1.0) return timer.cancel();
      widget.controller.value > 0.6 ? SosHaptics.medium() : SosHaptics.light();
    });
  }

  void _endHold() {
    _pulseTimer?.cancel();
    _pulseTimer = null;
    widget.controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return GestureDetector(
      onTapDown: (_) => _startHold(),
      onTapUp: (_) => _endHold(),
      onTapCancel: _endHold,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return SizedBox(
            width: 168,
            height: 168,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 168,
                  height: 168,
                  child: CircularProgressIndicator(
                    value: controller.value,
                    strokeWidth: 6,
                    backgroundColor: _kDanger.withValues(alpha: 0.15),
                    valueColor: const AlwaysStoppedAnimation(_kDanger),
                  ),
                ),
                Container(
                  width: 140,
                  height: 140,
                  decoration: const BoxDecoration(
                    color: _kDanger,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'SOS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                      Text(
                        controller.isAnimating || controller.value > 0
                            ? 'Keep holding'
                            : 'Hold 3s',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w800, color: color),
                ),
                const SizedBox(height: 4),
                Text(body, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
