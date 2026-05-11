import 'package:flutter/material.dart';

const Color kKycAccent = Color(0xFF2DBA9F);
const Color kKycAccentSoft = Color(0xFFE6F4F1);
const Color kKycCardBorder = Color(0xFFE7EBF0);
const Color kKycTextPrimary = Color(0xFF101828);
const Color kKycTextHint = Color(0xFF98A2B3);
const Color kKycTextSecondary = Color(0xFF667085);
const Color kKycBg = Color(0xFFF7F9FC);

/// Theme-adaptive color tokens for the KYC / form-card design system.
/// Use these instead of the constants above when you want correct
/// rendering in dark mode.
class KycColors {
  static const Color accent = Color(0xFF2DBA9F);

  static bool _isDark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;

  static Color accentSoft(BuildContext c) =>
      _isDark(c) ? const Color(0xFF1F3D38) : const Color(0xFFE6F4F1);

  static Color pageBg(BuildContext c) =>
      _isDark(c) ? const Color(0xFF12141C) : const Color(0xFFF7F9FC);

  static Color cardBg(BuildContext c) =>
      _isDark(c) ? const Color(0xFF1B1E2A) : Colors.white;

  static Color cardBorder(BuildContext c) =>
      _isDark(c) ? const Color(0xFF2A2F3D) : const Color(0xFFE7EBF0);

  static Color textPrimary(BuildContext c) =>
      _isDark(c) ? const Color(0xFFF2F4F7) : const Color(0xFF101828);

  static Color textSecondary(BuildContext c) =>
      _isDark(c) ? const Color(0xFFA4ABB8) : const Color(0xFF667085);

  static Color textHint(BuildContext c) =>
      _isDark(c) ? const Color(0xFF747B8B) : const Color(0xFF98A2B3);

  static Color searchFill(BuildContext c) =>
      _isDark(c) ? const Color(0xFF252A38) : const Color(0xFFF2F4F7);

  static Color sheetGrabber(BuildContext c) =>
      _isDark(c) ? const Color(0xFF3D4255) : const Color(0xFFD0D5DD);
}

class KycHeader extends StatelessWidget {
  const KycHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onBack,
    this.assetPath,
    this.icon,
  }) : assert(
          assetPath != null || icon != null,
          'Provide either assetPath or icon for the header decoration',
        );

  final String title;
  final String subtitle;
  final String? assetPath;
  final IconData? icon;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: KycColors.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: KycColors.textSecondary(context),
                    height: 1.3,
                  ),
                ),
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
    final cardBg = KycColors.cardBg(context);
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
            border: Border.all(color: KycColors.cardBorder(context)),
          ),
          child: Icon(
            Icons.arrow_back_rounded,
            size: 22,
            color: KycColors.textPrimary(context),
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
          color: KycColors.textPrimary(context),
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
        color: KycColors.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KycColors.cardBorder(context)),
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
                    color: KycColors.textPrimary(context),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: KycColors.cardBg(context),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
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

InputDecoration kycHintDecoration(String hint, {Color? hintColor}) {
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
    hintStyle: TextStyle(color: hintColor ?? kKycTextHint, fontSize: 14),
    errorStyle: const TextStyle(fontSize: 11.5, height: 1),
    counterText: '',
  );
}

TextStyle kycInputStyle(BuildContext context) => TextStyle(
      color: KycColors.textPrimary(context),
      fontSize: 14,
      fontWeight: FontWeight.w500,
    );

const TextStyle kKycInputTextStyle = TextStyle(
  color: kKycTextPrimary,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: KycColors.searchFill(context),
        borderRadius: BorderRadius.circular(14),
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
                  color: KycColors.textHint(context),
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
                  color: isDark
                      ? const Color(0xFF3D4255)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(99),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: KycColors.textSecondary(context),
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
      color: selected ? KycColors.accentSoft(context) : KycColors.cardBg(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? kKycAccent : KycColors.cardBorder(context),
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
                    color: KycColors.textPrimary(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                size: selected ? 22 : 20,
                color: selected ? kKycAccent : KycColors.textHint(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
