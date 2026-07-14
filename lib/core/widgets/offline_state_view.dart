import 'package:flutter/material.dart';

import 'app_toast.dart';

/// Full-screen empty state shown when the driver is Offline and a screen's
/// work content (available orders / pickups) is intentionally hidden.
///
/// Styled to match the app's dashboard language — the rounded [SectionCard]
/// surface, the Offline "danger" status tone, and the Online "green" action
/// tone — so it reads as a native availability surface. Offers a one-tap
/// **Go Online** action that flips availability in place.
class OfflineStateView extends StatefulWidget {
  const OfflineStateView({
    super.key,
    required this.message,
    this.onGoOnline,
  });

  /// One-line explanation of what's hidden, e.g.
  /// "Go Online to see available orders."
  final String message;

  /// Toggles availability to Online. Returns an error string on failure, or
  /// null on success. When null, the "Go Online" button is hidden.
  final Future<String?> Function()? onGoOnline;

  @override
  State<OfflineStateView> createState() => _OfflineStateViewState();
}

class _OfflineStateViewState extends State<OfflineStateView> {
  // Status tokens mirrored from the dashboard (StatusPill / availability):
  // Offline = danger red, Online action = success green.
  static const Color _danger = Color(0xFFB7283A);
  static const Color _dangerBg = Color(0x1FE8384F); // ~12% of #E8384F
  static const Color _online = Color(0xFF1AB36A);

  bool _busy = false;

  Future<void> _goOnline() async {
    final callback = widget.onGoOnline;
    if (callback == null || _busy) return;
    setState(() => _busy = true);
    final String? error = await callback();
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null && error.isNotEmpty) {
      AppToast.show(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textPrimary =
        isDark ? const Color(0xFFF2F4F7) : const Color(0xFF101828);
    final Color textSecondary =
        isDark ? const Color(0xFFA4ABB8) : const Color(0xFF667085);
    final Color cardBg = isDark ? const Color(0xFF1B1E2A) : Colors.white;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          // App card surface (matches SectionCard: r22, soft shadow).
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.18)
                      : const Color(0x10000000),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Material(
              color: cardBg,
              borderRadius: BorderRadius.circular(22),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon badge — offline danger tone
                    Container(
                      width: 78,
                      height: 78,
                      decoration: const BoxDecoration(
                        color: _dangerBg,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.cloud_off_rounded,
                        size: 37,
                        color: _danger,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "You're Offline",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      widget.message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: textSecondary,
                      ),
                    ),
                    if (widget.onGoOnline != null) ...[
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _busy ? null : _goOnline,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.bolt_rounded, size: 20),
                          label: Text(_busy ? 'Going Online…' : 'Go Online'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _online,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor:
                                _online.withValues(alpha: 0.6),
                            disabledForegroundColor: Colors.white,
                            elevation: 0,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
