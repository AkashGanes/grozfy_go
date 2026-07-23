import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grozfy_go/features/delivery_radius/model/delivery_radius_settings.dart';
import 'package:grozfy_go/features/delivery_radius/providers/delivery_radius_provider.dart';
import 'package:grozfy_go/features/delivery_radius/repository/delivery_radius_repository.dart';
import 'package:http/http.dart' as http;

/// A scriptable stand-in for the real repository so controller behaviour
/// (optimistic UI, rollback, duplicate-save guard, error classification) can be
/// exercised without any network. Subclasses the concrete repository and
/// overrides only the two public methods the controller touches.
class _FakeRepository extends DeliveryRadiusRepository {
  _FakeRepository({required this.settings});

  DeliveryRadiusSettings settings;

  Object? getError;
  Object? updateError;

  /// Completer used to hold [updateRadius] open so a second save can be
  /// attempted while the first is still in flight.
  Completer<double>? updateGate;

  int getCalls = 0;
  int updateCalls = 0;
  final List<double> updatedValues = [];

  @override
  Future<DeliveryRadiusSettings> getSettings() async {
    getCalls++;
    if (getError != null) throw getError!;
    return settings;
  }

  @override
  Future<double> updateRadius(double selectedRadiusKm) async {
    updateCalls++;
    updatedValues.add(selectedRadiusKm);
    if (updateError != null) throw updateError!;
    if (updateGate != null) return updateGate!.future;
    return selectedRadiusKm;
  }
}

DeliveryRadiusSettings _baseSettings({double? selected}) =>
    DeliveryRadiusSettings(
      enabled: true,
      minimumRadiusKm: 2,
      defaultRadiusKm: 5,
      maximumRadiusKm: 10,
      selectedRadiusKm: selected,
    );

/// Waits for the controller's constructor-triggered fetch to settle.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('DeliveryRadiusController.fetch', () {
    test('loads settings on construction and clears loading', () async {
      final repo = _FakeRepository(settings: _baseSettings(selected: 7));
      final controller = DeliveryRadiusController(repo);
      addTearDown(controller.dispose);

      await _settle();

      expect(repo.getCalls, 1);
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.settings?.selectedRadiusKm, 7);
      expect(controller.state.loadError, isNull);
    });

    test('classifies a socket failure as a network error', () async {
      final repo = _FakeRepository(settings: _baseSettings())
        ..getError = const SocketException('no route');
      final controller = DeliveryRadiusController(repo);
      addTearDown(controller.dispose);

      await _settle();

      expect(controller.state.settings, isNull);
      expect(controller.state.loadError?.kind, RadiusErrorKind.network);
    });

    test('classifies a timeout as a timeout error', () async {
      final repo = _FakeRepository(settings: _baseSettings())
        ..getError = TimeoutException('slow');
      final controller = DeliveryRadiusController(repo);
      addTearDown(controller.dispose);

      await _settle();

      expect(controller.state.loadError?.kind, RadiusErrorKind.timeout);
    });

    test('classifies a 401 message as unauthorized', () async {
      final repo = _FakeRepository(settings: _baseSettings())
        ..getError = Exception('401: Invalid API credentials.');
      final controller = DeliveryRadiusController(repo);
      addTearDown(controller.dispose);

      await _settle();

      expect(controller.state.loadError?.kind, RadiusErrorKind.unauthorized);
    });
  });

  group('DeliveryRadiusController.save', () {
    test('optimistically applies then confirms the backend value', () async {
      final repo = _FakeRepository(settings: _baseSettings(selected: 5));
      final controller = DeliveryRadiusController(repo);
      addTearDown(controller.dispose);
      await _settle();

      final outcome = await controller.save(8);

      expect(outcome.success, isTrue);
      expect(repo.updatedValues, [8]);
      expect(controller.state.settings?.selectedRadiusKm, 8);
      expect(controller.state.isSaving, isFalse);
    });

    test('reflects a server-clamped value echoed back by the repository',
        () async {
      final repo = _FakeRepository(settings: _baseSettings(selected: 5));
      final controller = DeliveryRadiusController(repo);
      addTearDown(controller.dispose);
      await _settle();

      // Backend clamps the request down to the max and echoes 10.
      repo.updateGate = Completer<double>()..complete(10);
      final outcome = await controller.save(999);

      expect(outcome.success, isTrue);
      expect(controller.state.settings?.selectedRadiusKm, 10);
    });

    test('rolls back to the previous selection when the save fails', () async {
      final repo = _FakeRepository(settings: _baseSettings(selected: 4))
        ..updateError = Exception('Radius exceeds allowed maximum');
      final controller = DeliveryRadiusController(repo);
      addTearDown(controller.dispose);
      await _settle();

      final outcome = await controller.save(9);

      expect(outcome.success, isFalse);
      expect(outcome.failure?.kind, RadiusErrorKind.validation);
      expect(outcome.failure?.message, 'Radius exceeds allowed maximum');
      // Selection restored to what it was before the attempt.
      expect(controller.state.settings?.selectedRadiusKm, 4);
      expect(controller.state.isSaving, isFalse);
    });

    test('ignores a save when nothing has loaded yet', () async {
      final repo = _FakeRepository(settings: _baseSettings())
        ..getError = const SocketException('down');
      final controller = DeliveryRadiusController(repo);
      addTearDown(controller.dispose);
      await _settle();

      final outcome = await controller.save(6);

      expect(outcome.ignored, isTrue);
      expect(repo.updateCalls, 0);
    });

    test('blocks a duplicate save while one is already in flight', () async {
      final repo = _FakeRepository(settings: _baseSettings(selected: 5));
      final controller = DeliveryRadiusController(repo);
      addTearDown(controller.dispose);
      await _settle();

      // Hold the first save open.
      final gate = Completer<double>();
      repo.updateGate = gate;
      final first = controller.save(7);
      expect(controller.state.isSaving, isTrue);

      // Second save arrives while the first is still pending → ignored.
      final second = await controller.save(8);
      expect(second.ignored, isTrue);
      expect(repo.updateCalls, 1);

      gate.complete(7);
      final firstOutcome = await first;
      expect(firstOutcome.success, isTrue);
      expect(controller.state.settings?.selectedRadiusKm, 7);
    });

    test('classifies an http ClientException as a network error', () async {
      final repo = _FakeRepository(settings: _baseSettings(selected: 5))
        ..updateError = http.ClientException('connection reset');
      final controller = DeliveryRadiusController(repo);
      addTearDown(controller.dispose);
      await _settle();

      final outcome = await controller.save(8);

      expect(outcome.failure?.kind, RadiusErrorKind.network);
      // Rolled back to the loaded selection.
      expect(controller.state.settings?.selectedRadiusKm, 5);
    });
  });
}
