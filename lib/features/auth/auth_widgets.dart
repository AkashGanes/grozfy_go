import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class AuthBackground extends StatelessWidget {
  const AuthBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark
        ? Theme.of(context).scaffoldBackgroundColor
        : const Color(0xFFEEF2F8);

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          Positioned(
            left: -60,
            top: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                color: AppTheme.oceanBlue.withValues(alpha: isDark ? 0.18 : 0.13),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: -50,
            top: 60,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                color: AppTheme.mint.withValues(alpha: isDark ? 0.14 : 0.10),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  color: AppTheme.mango.withValues(alpha: isDark ? 0.10 : 0.08),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class AuthStepPill extends StatelessWidget {
  const AuthStepPill({super.key, required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color dotActive = AppTheme.oceanBlue;
    final Color dotInactive =
        isDark ? Colors.white24 : const Color(0xFFD0D9E6);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: AppTheme.oceanBlue.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(color: dotActive),
          const SizedBox(width: 5),
          _Dot(color: step >= 2 ? dotActive : dotInactive),
          const SizedBox(width: 10),
          Text(
            'Step $step of 2',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : const Color(0xFF4A6080),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
