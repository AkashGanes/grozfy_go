import 'package:flutter/material.dart';

import '../../../core/theme/context_colors.dart';

const Color kKycAccent = Color(0xFF2DBA9F);

/// Brand accent tokens for the KYC / form-card design system.
/// Neutral colors (text, cards, borders, fills) come from the central
/// `AppColors` extension in core/theme/context_colors.dart.
class KycColors {
  static const Color accent = Color(0xFF2DBA9F);

  static Color accentSoft(BuildContext c) =>
      c.isDark ? const Color(0xFF1F3D38) : const Color(0xFFE6F4F1);
}

class KycHeader extends StatelessWidget {
  const KycHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onBack,
    this.assetPath,
    this.icon,
    this.trailingNote,
    this.showBottomBorder = false,
  }) : assert(
          assetPath != null || icon != null,
          'Provide either assetPath or icon for the header decoration',
        );

  final String title;
  final String subtitle;
  final String? assetPath;
  final IconData? icon;
  final VoidCallback onBack;

  /// Optional small widget rendered below the subtitle (e.g. a trust badge).
  final Widget? trailingNote;

  /// Adds a 1px bottom border once the host screen has scrolled, so the
  /// hairline doesn't permanently compete with the card sitting beneath it.
  final bool showBottomBorder;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: showBottomBorder
                ? context.borderSubtle
                : Colors.transparent,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          KycBackChip(onTap: onBack),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: context.textSecondary,
                    height: 1.3,
                  ),
                ),
                if (trailingNote != null) ...[
                  const SizedBox(height: 8),
                  trailingNote!,
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              color: KycColors.accentSoft(context),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(6),
            alignment: Alignment.center,
            child: assetPath != null
                ? Image.asset(assetPath!, fit: BoxFit.contain)
                : Icon(icon, size: 38, color: KycColors.accent),
          ),
        ],
      ),
    );
  }
}

class KycBackChip extends StatelessWidget {
  const KycBackChip({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cardBg = context.cardColor;
    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(12),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.borderSubtle),
          ),
          child: Icon(
            Icons.arrow_back_rounded,
            size: 22,
            color: context.textPrimary,
          ),
        ),
      ),
    );
  }
}

class KycSectionHeading extends StatelessWidget {
  const KycSectionHeading(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: context.textPrimary,
        ),
      ),
    );
  }
}

class KycFieldCard extends StatelessWidget {
  const KycFieldCard({
    super.key,
    required this.icon,
    required this.label,
    required this.child,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Widget child;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: KycColors.accentSoft(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: KycColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                child,
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: card,
    );
  }
}

class KycPrimaryButton extends StatelessWidget {
  const KycPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.arrow_forward_rounded,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: context.cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.4 : 0.08),
            blurRadius: 14,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        height: 52,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: KycColors.accent,
            disabledBackgroundColor:
                KycColors.accent.withValues(alpha: 0.4),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

InputDecoration kycHintDecoration(
  BuildContext context,
  String hint, {
  Color? hintColor,
}) {
  return InputDecoration(
    isDense: true,
    contentPadding: EdgeInsets.zero,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
    filled: false,
    fillColor: Colors.transparent,
    hintText: hint,
    hintStyle: TextStyle(color: hintColor ?? context.textTertiary, fontSize: 14),
    errorStyle: const TextStyle(fontSize: 11.5, height: 1),
    counterText: '',
  );
}

TextStyle kycInputStyle(BuildContext context) => TextStyle(
      color: context.textPrimary,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    );

class KycSearchInput extends StatefulWidget {
  const KycSearchInput({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  State<KycSearchInput> createState() => _KycSearchInputState();
}

class _KycSearchInputState extends State<KycSearchInput> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChange);
    super.dispose();
  }

  void _onTextChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: context.shadowColor,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            child: const Icon(
              Icons.search_rounded,
              color: kKycAccent,
              size: 22,
            ),
          ),
          Expanded(
            child: TextField(
              controller: widget.controller,
              autofocus: widget.autofocus,
              style: kycInputStyle(context),
              textAlignVertical: TextAlignVertical.center,
              cursorColor: kKycAccent,
              decoration: InputDecoration(
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                hintText: widget.hint,
                hintStyle: TextStyle(
                  color: context.textTertiary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onChanged: widget.onChanged,
            ),
          ),
          if (widget.controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                widget.controller.clear();
                widget.onChanged?.call('');
              },
              child: Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: context.surfaceContainer,
                  borderRadius: BorderRadius.circular(99),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: context.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class KycResultTile extends StatelessWidget {
  const KycResultTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.leadingLetter,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? leadingLetter;

  @override
  Widget build(BuildContext context) {
    final letter = leadingLetter ??
        (label.isNotEmpty ? label[0].toUpperCase() : '?');
    return Material(
      color: selected ? KycColors.accentSoft(context) : context.cardColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? kKycAccent : context.borderSubtle,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: KycColors.accentSoft(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  letter,
                  style: const TextStyle(
                    color: kKycAccent,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        selected ? FontWeight.w800 : FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                size: selected ? 22 : 20,
                color: selected ? kKycAccent : context.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
