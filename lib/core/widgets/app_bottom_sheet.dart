import 'package:flutter/material.dart';

import '../theme/context_colors.dart';

/// Shared design tokens + scaffolding for every bottom sheet in the app.
///
/// Use [showAppBottomSheet] to open a modal sheet with standard transition,
/// barrier and shape, and wrap the sheet body in an [AppBottomSheet] so the
/// background, corner radius, drag handle, header and padding are identical
/// everywhere. Primary/secondary actions inside a sheet should use
/// [AppSheetPrimaryButton] / [AppSheetSecondaryButton].

/// Canonical top corner radius for all sheets.
const double kSheetCornerRadius = 24;

/// Canonical content padding (keyboard + safe-area insets are added on top).
const EdgeInsets kSheetContentPadding = EdgeInsets.fromLTRB(20, 8, 20, 20);

/// Canonical full-width action button height + corner radius.
const double kSheetButtonHeight = 52;
const double kSheetButtonRadius = 16;

/// Opens a modal bottom sheet with the standardized modal parameters
/// (scroll-controlled, transparent background so [AppBottomSheet] draws its own
/// rounded surface, consistent barrier). The [builder] should return an
/// [AppBottomSheet].
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    builder: builder,
  );
}

/// Standard bottom-sheet scaffold: rounded surface, drag handle, optional
/// header (leading icon + title + subtitle) and consistent padding.
///
/// Four layout modes:
///  * default — sizes to its content ([mainAxisSize.min]); capped at
///    [maxHeightFactor] of the screen.
///  * `scrollable: true` — content scrolls inside the capped height (use for
///    forms / long content).
///  * `heightFactor` set — the sheet takes a fixed fraction of the available
///    height (above the keyboard) and [child] fills it. Use for search pickers
///    that pin a field on top and scroll results via an inner [Expanded].
///  * `scrollController` provided — draggable mode for use inside a
///    [DraggableScrollableSheet]; the sheet fills the available height and the
///    content scrolls via the supplied controller.
class AppBottomSheet extends StatelessWidget {
  const AppBottomSheet({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.leadingIcon,
    this.leadingIconColor,
    this.trailing,
    this.scrollable = false,
    this.scrollController,
    this.heightFactor,
    this.padding = kSheetContentPadding,
    this.maxHeightFactor = 0.9,
    this.showHandle = true,
  });

  /// The body of the sheet (below the handle + optional header).
  final Widget child;

  /// Optional header title. When null, no built-in header is rendered.
  final String? title;
  final String? subtitle;
  final IconData? leadingIcon;
  final Color? leadingIconColor;

  /// Optional trailing widget in the header row (e.g. a close button).
  final Widget? trailing;

  /// Wrap [child] in a [SingleChildScrollView] (ignored in draggable mode).
  final bool scrollable;

  /// When supplied, the sheet runs in draggable mode and this controller drives
  /// the scrollable content (see [DraggableScrollableSheet]).
  final ScrollController? scrollController;

  /// When set, the sheet takes this fraction of the available height (above the
  /// keyboard) and [child] fills it. Ignored in draggable mode.
  final double? heightFactor;

  final EdgeInsets padding;
  final double maxHeightFactor;
  final bool showHandle;

  bool get _draggable => scrollController != null;
  bool get _fixedHeight => !_draggable && heightFactor != null;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboardInset = mq.viewInsets.bottom;
    final safeBottom = mq.padding.bottom;
    // In fixed-height mode the keyboard is handled by shrinking the sheet, so
    // only the safe-area inset is added to the content padding.
    final contentPadding = padding.copyWith(
      bottom: padding.bottom + safeBottom + (_fixedHeight ? 0 : keyboardInset),
    );

    final List<Widget> columnChildren = [
      if (showHandle) _buildHandle(context),
      if (title != null) _buildHeader(context),
    ];

    if (_draggable) {
      columnChildren.add(
        Expanded(
          child: SingleChildScrollView(
            controller: scrollController,
            padding: contentPadding,
            child: child,
          ),
        ),
      );
    } else if (_fixedHeight) {
      columnChildren.add(
        Expanded(child: Padding(padding: contentPadding, child: child)),
      );
    } else if (scrollable) {
      columnChildren.add(
        Flexible(
          child: SingleChildScrollView(
            padding: contentPadding,
            child: child,
          ),
        ),
      );
    } else {
      columnChildren.add(Padding(padding: contentPadding, child: child));
    }

    final column = Column(
      mainAxisSize:
          (_draggable || _fixedHeight) ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: columnChildren,
    );

    return Container(
      height: _fixedHeight
          ? (mq.size.height - keyboardInset) * heightFactor!
          : null,
      constraints: (_draggable || _fixedHeight)
          ? null
          : BoxConstraints(maxHeight: mq.size.height * maxHeightFactor),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(kSheetCornerRadius),
        ),
      ),
      child: column,
    );
  }

  Widget _buildHandle(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(top: 12, bottom: 12),
        decoration: BoxDecoration(
          color: context.borderSubtle,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final iconColor = leadingIconColor ?? context.scheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leadingIcon != null) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(leadingIcon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title!,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Full-width primary action for use inside a bottom sheet.
/// Pass [color] to override the background for semantic actions
/// (e.g. success/danger) while keeping consistent dimensions.
class AppSheetPrimaryButton extends StatelessWidget {
  const AppSheetPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = ElevatedButton.styleFrom(
      backgroundColor: color ?? context.scheme.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      minimumSize: const Size.fromHeight(kSheetButtonHeight),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kSheetButtonRadius),
      ),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    );
    final labelText = Text(label);
    return icon != null
        ? ElevatedButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 18),
            label: labelText,
          )
        : ElevatedButton(onPressed: onPressed, style: style, child: labelText);
  }
}

/// Full-width secondary (outlined) action for use inside a bottom sheet.
class AppSheetSecondaryButton extends StatelessWidget {
  const AppSheetSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      foregroundColor: context.textSecondary,
      minimumSize: const Size.fromHeight(kSheetButtonHeight),
      side: BorderSide(color: context.borderStrong),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kSheetButtonRadius),
      ),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    );
    final labelText = Text(label);
    return icon != null
        ? OutlinedButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 18),
            label: labelText,
          )
        : OutlinedButton(onPressed: onPressed, style: style, child: labelText);
  }
}
