import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/context_colors.dart';
import '../dashboard/widgets/dashboard_colors.dart';
import '../dashboard/widgets/section_card.dart';

/// ---------------------------------------------------------------------------
/// Design tokens for the Privacy & Legal module.
///
/// The module deliberately owns no visual language of its own — it reuses the
/// app's [SectionCard], [DashColors] and the grouped-list idiom from the
/// Profile screen. Colour appears only where it carries meaning (destructive
/// actions, required-permission badges); everything else is neutral.
/// ---------------------------------------------------------------------------
class LegalTokens {
  LegalTokens._();

  // Geometry — matches the grouped sections on the Profile screen.
  static const double cardRadius = 18;
  static const double innerRadius = 12;
  static const EdgeInsets cardPadding = EdgeInsets.all(16);

  /// Vertical rhythm. Tight on purpose: these are reference pages, and every
  /// extra gap is another swipe through a long document.
  static const double gapTight = 8;
  static const double gapGroup = 18;

  static const Duration fade = Duration(milliseconds: 260);
  static const Duration stagger = Duration(milliseconds: 40);
}

/// Staggered fade + rise, applied to each group so a page settles as one.
extension LegalEntrance on Widget {
  Widget legalEntrance(int index) => animate()
      .fadeIn(duration: LegalTokens.fade, delay: LegalTokens.stagger * index)
      .slideY(begin: 0.03, end: 0, duration: LegalTokens.fade);
}

/// ---------------------------------------------------------------------------
/// Surfaces
/// ---------------------------------------------------------------------------

/// Standalone card. Thin wrapper over the app's [SectionCard] so the module
/// picks up any future change to the shared surface.
class LegalCard extends StatelessWidget {
  const LegalCard({
    super.key,
    required this.child,
    this.padding = LegalTokens.cardPadding,
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: padding,
      borderRadius: LegalTokens.cardRadius,
      child: child,
    );
  }
}

/// A run of rows in one card, separated by inset dividers — the same grouped
/// list the Profile screen uses. Replaces one-card-per-item, which is what made
/// these pages so long.
class LegalGroup extends StatelessWidget {
  const LegalGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(
          Divider(
            height: 1,
            indent: 56,
            endIndent: 16,
            color: DashColors.cardBorder(context).withValues(alpha: 0.7),
          ),
        );
      }
    }

    return SectionCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      borderRadius: LegalTokens.cardRadius,
      child: Column(children: rows),
    );
  }
}

/// Uppercase group label, matching the Profile screen's section headers.
class LegalSectionLabel extends StatelessWidget {
  const LegalSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: DashColors.textSecondary(context),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Flat, neutral leading glyph. One treatment for every row — no per-section
/// colour, no gradient.
class LegalGlyph extends StatelessWidget {
  const LegalGlyph({super.key, required this.icon, this.tint});

  final IconData icon;

  /// Only supplied for genuinely semantic rows (destructive actions).
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final Color color = tint ?? context.textSecondary;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: tint == null
            ? context.fillSubtle
            : tint!.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 17),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Page intro — replaces the previous hero illustration
/// ---------------------------------------------------------------------------

/// Short lead paragraph under the app bar. No artwork: it added a screenful of
/// scrolling to every page and read as decoration rather than information.
class LegalIntro extends StatelessWidget {
  const LegalIntro(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 18),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          height: 1.55,
          fontWeight: FontWeight.w500,
          color: context.textSecondary,
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Content primitives
/// ---------------------------------------------------------------------------

class LegalParagraph extends StatelessWidget {
  const LegalParagraph(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          height: 1.6,
          color: context.textSecondary,
        ),
      ),
    );
  }
}

class LegalBullet extends StatelessWidget {
  const LegalBullet(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6.5, right: 10),
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: context.textSecondary.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.55,
                color: context.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Neutral pill used to list collected data fields.
class LegalDataChip extends StatelessWidget {
  const LegalDataChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: context.fillSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.borderSubtle),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: context.textPrimary,
        ),
      ),
    );
  }
}

/// Quiet callout for a limitation or reassurance.
class LegalNote extends StatelessWidget {
  const LegalNote(this.text, {super.key, this.icon = Icons.info_outline_rounded});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: context.fillSubtle,
        borderRadius: BorderRadius.circular(LegalTokens.innerRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: context.textSecondary),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: context.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Rows
/// ---------------------------------------------------------------------------

/// Expandable document section, sized and spaced to sit inside a [LegalGroup]
/// alongside plain rows.
class LegalExpansionRow extends StatefulWidget {
  const LegalExpansionRow({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.initiallyExpanded = false,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  State<LegalExpansionRow> createState() => _LegalExpansionRowState();
}

class _LegalExpansionRowState extends State<LegalExpansionRow>
    with SingleTickerProviderStateMixin {
  late bool _expanded = widget.initiallyExpanded;
  late final AnimationController _chevron = AnimationController(
    duration: const Duration(milliseconds: 200),
    vsync: this,
    value: widget.initiallyExpanded ? 1 : 0,
  );

  @override
  void dispose() {
    _chevron.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _chevron.forward() : _chevron.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                LegalGlyph(icon: widget.icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: DashColors.textPrimary(context),
                    ),
                  ),
                ),
                RotationTransition(
                  turns: Tween<double>(begin: 0, end: 0.5).animate(_chevron),
                  child: Icon(
                    Icons.expand_more_rounded,
                    size: 20,
                    color: context.textSecondary.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: widget.children,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Plain navigation row inside a [LegalGroup].
class LegalNavRow extends StatelessWidget {
  const LegalNavRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.meta,
    this.tint,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Small trailing count, e.g. "13".
  final String? meta;

  /// Semantic colour — only for destructive rows.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            LegalGlyph(icon: icon, tint: tint),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: tint ?? DashColors.textPrimary(context),
                ),
              ),
            ),
            if (meta != null) ...[
              Text(
                meta!,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: context.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: context.textSecondary.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Footer
/// ---------------------------------------------------------------------------

class LegalDocumentFooter extends StatelessWidget {
  const LegalDocumentFooter({
    super.key,
    required this.version,
    required this.lastUpdated,
  });

  final String version;
  final String lastUpdated;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Document $version  ·  Updated $lastUpdated',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          color: context.textSecondary.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}

class LegalPrimaryButton extends StatelessWidget {
  const LegalPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final Color base = color ?? AppTheme.nightBlue;
    final bool enabled = onPressed != null && !busy;

    return ElevatedButton(
      onPressed: enabled ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: base,
        foregroundColor: Colors.white,
        disabledBackgroundColor: context.surfaceContainer,
        disabledForegroundColor: context.textDisabled,
        minimumSize: const Size.fromHeight(52),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          fontFamily: 'Poppins',
        ),
      ),
      child: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            )
          : Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
