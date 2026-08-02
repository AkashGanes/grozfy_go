import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/context_colors.dart';
import 'app_bottom_nav.dart';
import 'app_toast.dart';
import 'offline_status_indicator.dart';

/// The app-wide page background: the scaffold colour with a soft diagonal
/// blend of the secondary and tertiary accents. Exposed so screens that build
/// their own [Scaffold] still sit on the same background as every AppShell
/// page instead of a flat colour.
LinearGradient appBackgroundGradient(BuildContext context) {
  final theme = Theme.of(context);
  final bgColor = theme.scaffoldBackgroundColor;
  return LinearGradient(
    colors: [
      bgColor,
      Color.alphaBlend(
        theme.colorScheme.secondary.withValues(alpha: 0.08),
        bgColor,
      ),
      Color.alphaBlend(
        theme.colorScheme.tertiary.withValues(alpha: 0.06),
        bgColor,
      ),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.actions,
    this.header,
    this.scrollable = true,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 20),
    this.loading = false,
    this.loadingMessage = 'Please wait...',
    this.onRefresh,
    this.footer,
    this.showBottomNav = false,
    this.bottomNavIndex = 0,
    this.onBottomNavTap,
    this.noBottomPadding = true,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget>? actions;
  final Widget? header;
  final bool scrollable;
  final EdgeInsets padding;
  final bool loading;
  final String loadingMessage;
  final Future<void> Function()? onRefresh;
  final Widget? footer;
  final bool showBottomNav;
  final int bottomNavIndex;
  final ValueChanged<int>? onBottomNavTap;
  final bool noBottomPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectivePadding = noBottomPadding
        ? EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, 0)
        : padding;
    final Widget body = Padding(padding: effectivePadding, child: child);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: appBackgroundGradient(context)),
        child: Stack(
          children: [
            const AppBackdropShapes(),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const OfflineStatusIndicator(),
                  const SyncStatusBanner(),
                  if (header != null)
                    header!
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                      child: Row(
                        children: [
                          if (Navigator.canPop(context))
                            IconButton(
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: theme.textTheme.titleLarge,
                                ),
                                if (subtitle != null)
                                  Text(
                                    subtitle!,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          ...?actions,
                        ],
                      ),
                    ),
                  if (footer == null) const SizedBox(height: 12),
                  Expanded(
                    child: scrollable
                        ? onRefresh != null
                              ? RefreshIndicator(
                                  onRefresh: onRefresh!,
                                  child: SingleChildScrollView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(
                                          parent: BouncingScrollPhysics(),
                                        ),
                                    child: body,
                                  ),
                                )
                              : SingleChildScrollView(
                                  physics: const BouncingScrollPhysics(),
                                  child: body,
                                )
                        : body,
                  ),
                  if (footer != null) ...[
                    padding == const EdgeInsets.fromLTRB(20, 12, 20, 20)
                        ? Padding(
                            padding: EdgeInsets.fromLTRB(
                              20,
                              0,
                              20,
                              noBottomPadding ? 0 : 20,
                            ),
                            child: footer,
                          )
                        : footer!,
                  ],
                  if (showBottomNav) ...[
                    AppBottomNav(
                      currentIndex: bottomNavIndex,
                      onTap: onBottomNavTap ?? (_) {},
                    ),
                  ],
                ],
              ),
            ),
            if (loading)
              Positioned.fill(
                child: AbsorbPointer(
                  child: ColoredBox(
                    color: Colors.black26,
                    child: Center(
                      child: FrostCard(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _ShellLoadingIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              loadingMessage,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class FrostCard extends StatelessWidget {
  const FrostCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = context.isDark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: context.surfaceMuted,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? theme.colorScheme.outline.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.7),
        ),
        boxShadow: [
          BoxShadow(
            color: context.shadowColor,
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? Theme.of(context).colorScheme.primary;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: effectiveColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: effectiveColor.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: effectiveColor,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The three soft accent shapes behind every page. Public so screens with a
/// custom [Scaffold] can paint the same backdrop.
class AppBackdropShapes extends StatelessWidget {
  const AppBackdropShapes({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: -60,
            top: -70,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: -35,
            top: 110,
            child: Transform.rotate(
              angle: 0.8,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: colorScheme.tertiary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
          ),
          Positioned(
            left: 40,
            bottom: -60,
            child: Container(
              width: 210,
              height: 210,
              decoration: BoxDecoration(
                color: colorScheme.secondary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SafeMap extends StatefulWidget {
  const SafeMap({super.key, required this.child});

  final Widget child;

  @override
  State<SafeMap> createState() => _SafeMapState();
}

class _SafeMapState extends State<SafeMap> {
  bool _hasError = false;

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        decoration: BoxDecoration(
          color: context.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.map_outlined, size: 48, color: context.iconMuted),
              const SizedBox(height: 8),
              Text(
                'Map unavailable',
                style: TextStyle(
                  color: context.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Check your internet connection',
                style: TextStyle(color: context.textTertiary, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => setState(() => _hasError = false),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return _MapErrorBoundary(
      onError: () {
        if (mounted) setState(() => _hasError = true);
      },
      child: widget.child,
    );
  }
}

class _MapErrorBoundary extends StatelessWidget {
  const _MapErrorBoundary({required this.child, required this.onError});

  final Widget child;
  final VoidCallback onError;

  @override
  Widget build(BuildContext context) {
    ErrorWidget.builder = (FlutterErrorDetails details) {
      onError();
      return Container(
        color: Colors.grey[100],
        child: const Center(
          child: Icon(Icons.map_outlined, size: 48, color: Colors.grey),
        ),
      );
    };
    return child;
  }
}

void showInfoSnack(BuildContext context, String message) {
  AppToast.show(context, message);
}

class _ShellLoadingIndicator extends StatefulWidget {
  const _ShellLoadingIndicator();

  @override
  State<_ShellLoadingIndicator> createState() => _ShellLoadingIndicatorState();
}

class _ShellLoadingIndicatorState extends State<_ShellLoadingIndicator>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (index) => AnimationController(
        duration: const Duration(milliseconds: 600),
        vsync: this,
      ),
    );

    _animations = _controllers.map((controller) {
      return Tween<double>(
        begin: 0,
        end: -12,
      ).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut));
    }).toList();

    _startAnimation();
  }

  void _startAnimation() async {
    while (mounted) {
      for (int i = 0; i < 3; i++) {
        if (!mounted) return;
        _controllers[i].forward().then((_) {
          if (mounted) _controllers[i].reverse();
        });
        await Future.delayed(const Duration(milliseconds: 150));
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (index) {
          return AnimatedBuilder(
            animation: _animations[index],
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, _animations[index].value),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppTheme.oceanBlue.withValues(
                      alpha: 0.3 + (index * 0.2),
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
