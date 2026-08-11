import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/providers.dart';
import '../../../core/widgets/app_toast.dart';
import '../model/delivery_radius_settings.dart';
import '../providers/delivery_radius_provider.dart';

/// Settings card that lets the driver pick their delivery radius.
///
/// Hides itself entirely when the feature is disabled for the driver. Fetches
/// fresh on build (via the autoDispose controller) so it never shows a stale
/// value, and saves each change to the backend with optimistic UI + rollback.
class DeliveryRadiusCard extends ConsumerStatefulWidget {
  const DeliveryRadiusCard({super.key, this.sectionLabel});

  /// Optional heading rendered directly above the card.
  ///
  /// It belongs here rather than in the caller because this widget is the only
  /// one that knows whether it will draw anything at all — when the feature is
  /// off for the driver it collapses to nothing, and a heading left stranded
  /// over empty space is worse than no heading.
  final Widget? sectionLabel;

  @override
  ConsumerState<DeliveryRadiusCard> createState() => _DeliveryRadiusCardState();
}

class _DeliveryRadiusCardState extends ConsumerState<DeliveryRadiusCard> {
  // In-progress slider value while dragging / saving; null means "defer to the
  // value in state".
  double? _draftKm;

  String _t(String key) => ref.read(appControllerProvider).t(key);

  @override
  Widget build(BuildContext context) {
    final Widget? content = _buildContent(context);
    if (content == null) return const SizedBox.shrink();
    if (widget.sectionLabel == null) return content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [widget.sectionLabel!, content],
    );
  }

  /// Null when the feature is off for this driver — see [sectionLabel].
  Widget? _buildContent(BuildContext context) {
    final state = ref.watch(deliveryRadiusControllerProvider);

    // Still loading the very first response — show a compact placeholder rather
    // than nothing, so the driver knows the section is coming.
    if (state.settings == null && state.isLoading) {
      return _LoadingCard(title: _t('delivery_radius'));
    }

    // Fetch failed with nothing to show — offer a retry.
    if (state.settings == null && state.loadError != null) {
      return _ErrorCard(
        title: _t('delivery_radius'),
        message: _errorText(state.loadError!),
        retryLabel: _t('retry'),
        onRetry: () =>
            ref.read(deliveryRadiusControllerProvider.notifier).fetch(),
      );
    }

    final settings = state.settings;
    // Feature disabled (or nothing loaded) → render nothing.
    if (settings == null || !settings.enabled || !settings.hasValidBounds) {
      return null;
    }

    return _buildCard(context, settings, state.isSaving);
  }

  Widget _buildCard(
    BuildContext context,
    DeliveryRadiusSettings settings,
    bool isSaving,
  ) {
    final theme = Theme.of(context);
    final double min = settings.minimumRadiusKm;
    final double max = settings.maximumRadiusKm;
    final double sliderValue = (_draftKm ?? settings.effectiveRadiusKm).clamp(
      min,
      max,
    );
    final int divisions = (max - min).round().clamp(1, 1000);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.my_location_rounded,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t('delivery_radius'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _t('delivery_radius_subtitle'),
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _valueChip(theme, sliderValue, isSaving),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    min: min,
                    max: max,
                    divisions: divisions,
                    value: sliderValue,
                    label: _formatKm(sliderValue),
                    // Block interaction while a save is in flight so we never
                    // fire a duplicate request.
                    onChanged: isSaving
                        ? null
                        : (v) => setState(() => _draftKm = v),
                    onChangeEnd: isSaving ? null : _onRadiusChosen,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatKm(min), style: _boundStyle(theme)),
                  Text(_formatKm(max), style: _boundStyle(theme)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _valueChip(ThemeData theme, double value, bool isSaving) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSaving) ...[
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            _formatKm(value),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onRadiusChosen(double value) async {
    // Keep the dragged value pinned while the request runs.
    setState(() => _draftKm = value);
    final outcome = await ref
        .read(deliveryRadiusControllerProvider.notifier)
        .save(value);

    if (!mounted) return;
    // Defer back to state: the confirmed value on success, or the restored
    // previous value on failure.
    setState(() => _draftKm = null);

    if (outcome.ignored) return;
    if (outcome.success) {
      AppToast.show(context, _t('delivery_radius_updated'));
    } else if (outcome.failure != null) {
      AppToast.show(context, _errorText(outcome.failure!));
    }
  }

  String _errorText(RadiusFailure failure) {
    switch (failure.kind) {
      case RadiusErrorKind.network:
        return _t('error_network');
      case RadiusErrorKind.timeout:
        return _t('error_timeout');
      case RadiusErrorKind.unauthorized:
        return _t('error_unauthorized');
      case RadiusErrorKind.invalidResponse:
        return _t('error_invalid_response');
      case RadiusErrorKind.validation:
        return failure.message.isNotEmpty
            ? failure.message
            : _t('error_generic');
      case RadiusErrorKind.unknown:
        return _t('error_generic');
    }
  }

  TextStyle _boundStyle(ThemeData theme) => TextStyle(
    fontSize: 11,
    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
  );

  /// Formats a radius like "2 km" / "10 km", dropping a trailing ".0".
  String _formatKm(double value) {
    final rounded = value.roundToDouble();
    final text = value == rounded
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$text km';
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Row(
          children: [
            Icon(
              Icons.my_location_rounded,
              color: theme.colorScheme.primary,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.title,
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String title;
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.my_location_rounded,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(retryLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
