import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../model/delivery_radius_settings.dart';
import '../repository/delivery_radius_repository.dart';

/// The category of a delivery-radius failure. The UI maps each kind to a
/// localized message, except [validation] which carries the backend's own text.
enum RadiusErrorKind {
  network,
  timeout,
  unauthorized,
  invalidResponse,
  validation,
  unknown,
}

/// A classified failure: a [kind] the UI can localize plus the raw backend
/// [message] (used verbatim for validation errors).
class RadiusFailure {
  const RadiusFailure(this.kind, [this.message = '']);

  final RadiusErrorKind kind;
  final String message;
}

/// Outcome of a save attempt, so the widget can show the right toast.
class RadiusSaveOutcome {
  const RadiusSaveOutcome._({
    required this.success,
    required this.ignored,
    this.failure,
  });

  const RadiusSaveOutcome.success() : this._(success: true, ignored: false);

  /// A no-op (duplicate request in flight, or nothing loaded) — show nothing.
  const RadiusSaveOutcome.ignored() : this._(success: false, ignored: true);

  const RadiusSaveOutcome.failed(RadiusFailure failure)
    : this._(success: false, ignored: false, failure: failure);

  final bool success;
  final bool ignored;
  final RadiusFailure? failure;
}

/// Immutable view of the delivery-radius feature the widget renders from.
class DeliveryRadiusState {
  const DeliveryRadiusState({
    this.isLoading = true,
    this.loadError,
    this.settings,
    this.isSaving = false,
  });

  /// Initial fetch in progress and nothing to show yet.
  final bool isLoading;

  /// Initial fetch failed (and we have no settings to fall back on).
  final RadiusFailure? loadError;

  /// The loaded configuration; null until the first successful fetch.
  final DeliveryRadiusSettings? settings;

  /// An update request is in flight — used to block duplicate saves and show a
  /// saving indicator.
  final bool isSaving;

  DeliveryRadiusState copyWith({
    bool? isLoading,
    DeliveryRadiusSettings? settings,
    bool? isSaving,
    RadiusFailure? loadError,
    bool clearLoadError = false,
  }) {
    return DeliveryRadiusState(
      isLoading: isLoading ?? this.isLoading,
      settings: settings ?? this.settings,
      isSaving: isSaving ?? this.isSaving,
      loadError: clearLoadError ? null : (loadError ?? this.loadError),
    );
  }
}

class DeliveryRadiusController extends StateNotifier<DeliveryRadiusState> {
  DeliveryRadiusController(this._repository)
    : super(const DeliveryRadiusState()) {
    fetch();
  }

  final DeliveryRadiusRepository _repository;

  /// Loads the latest configuration from the backend. Always hits the server so
  /// values are never stale after a logout/login.
  Future<void> fetch() async {
    state = state.copyWith(isLoading: true, clearLoadError: true);
    try {
      final settings = await _repository.getSettings();
      state = DeliveryRadiusState(isLoading: false, settings: settings);
    } catch (error) {
      state = state.copyWith(isLoading: false, loadError: _classify(error));
    }
  }

  /// Persists [km]. Optimistically updates the UI, blocks duplicate concurrent
  /// requests, and restores the previous value on failure.
  Future<RadiusSaveOutcome> save(double km) async {
    final current = state.settings;
    if (current == null || state.isSaving) {
      return const RadiusSaveOutcome.ignored();
    }

    final double? previous = current.selectedRadiusKm;
    // Optimistic: reflect the new value immediately while the request runs.
    state = state.copyWith(settings: current.withSelected(km), isSaving: true);

    try {
      final confirmed = await _repository.updateRadius(km);
      state = state.copyWith(
        settings: current.withSelected(confirmed),
        isSaving: false,
      );
      return const RadiusSaveOutcome.success();
    } catch (error) {
      // Restore the value that was showing before this attempt.
      state = state.copyWith(
        settings: current.withSelected(previous),
        isSaving: false,
      );
      return RadiusSaveOutcome.failed(_classify(error));
    }
  }

  /// Maps a thrown error onto a [RadiusFailure] the UI can present.
  RadiusFailure _classify(Object error) {
    if (error is TimeoutException) {
      return const RadiusFailure(RadiusErrorKind.timeout);
    }
    if (error is SocketException || error is http.ClientException) {
      return const RadiusFailure(RadiusErrorKind.network);
    }
    final message = _stripException(error);
    if (message.startsWith('401') || message.startsWith('403')) {
      return RadiusFailure(RadiusErrorKind.unauthorized, message);
    }
    if (message.contains('Invalid response') ||
        message.contains('Unexpected response')) {
      return RadiusFailure(RadiusErrorKind.invalidResponse, message);
    }
    if (message.isNotEmpty) {
      return RadiusFailure(RadiusErrorKind.validation, message);
    }
    return const RadiusFailure(RadiusErrorKind.unknown);
  }

  String _stripException(Object error) {
    final text = error.toString();
    return text.startsWith('Exception: ')
        ? text.substring('Exception: '.length).trim()
        : text.trim();
  }
}

final deliveryRadiusRepositoryProvider = Provider<DeliveryRadiusRepository>(
  (ref) => DeliveryRadiusRepository(),
);

/// autoDispose so the Settings screen refetches on every open — guaranteeing a
/// fresh value after logout/login and never showing a stale selection.
final deliveryRadiusControllerProvider =
    StateNotifierProvider.autoDispose<
      DeliveryRadiusController,
      DeliveryRadiusState
    >((ref) => DeliveryRadiusController(ref.read(deliveryRadiusRepositoryProvider)));
