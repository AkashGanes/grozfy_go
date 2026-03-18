import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.actions,
    this.scrollable = true,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 20),
    this.loading = false,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget>? actions;
  final bool scrollable;
  final EdgeInsets padding;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final Widget body = Padding(padding: padding, child: child);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF1F7FF), Color(0xFFE8F5F0), Color(0xFFFFF5E6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            const _BackdropShapes(),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              if (subtitle != null)
                                Text(
                                  subtitle!,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: Colors.black54),
                                ),
                            ],
                          ),
                        ),
                        ...?actions,
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: scrollable
                        ? SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: body,
                          )
                        : body,
                  ),
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
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              'Please wait...',
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
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140A1D3A),
            blurRadius: 18,
            offset: Offset(0, 10),
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
          color: AppTheme.nightBlue,
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
    this.color = AppTheme.oceanBlue,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: color,
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

class _BackdropShapes extends StatelessWidget {
  const _BackdropShapes();

  @override
  Widget build(BuildContext context) {
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
                color: AppTheme.oceanBlue.withValues(alpha: 0.16),
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
                  color: AppTheme.mango.withValues(alpha: 0.18),
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
                color: AppTheme.mint.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void showInfoSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
