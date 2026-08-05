import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../core/database/partner_timing_log_dao.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/offline_trip_manager.dart';
import '../../../core/services/trip_route_service.dart';
import '../../../core/state/providers.dart';
import '../../../core/utils/geo_distance.dart' show isValidLatLng;
import '../model/external_delivery.dart';
import '../model/stop_progress_status.dart';
import '../repository/external_delivery_repository.dart';
import '../../pickup_jobs/model/pickup_job.dart';
import '../../pickup_jobs/repository/pickup_job_repository.dart';
import '../services/trip_sequencing_service.dart';

/// Sentinel used by [TripControllerState.copyWith] to distinguish "leave this
/// nullable field unchanged" from "explicitly set it to null".
class _Unset {
  const _Unset();
}

const Object _unset = _Unset();

/// Single source of truth for one External Delivery trip's sequencing,
/// in-flight-action guards, and completion/navigation state. Extracted from
/// `external_delivery_trip_details_screen.dart` so the business logic is
/// reusable/testable independent of any widget. Deliberately does not hold
/// the [ExternalDeliveryTrip] itself or a loading/error state — the screen
/// keeps its existing `FutureBuilder`-driven trip fetch (including offline
/// caching and pickup-detail prefetch) untouched and passes the freshly
/// loaded trip into this controller's methods, exactly as it already passes
/// `trip` into the pre-refactor private methods.
class TripControllerState {
  const TripControllerState({
    this.stopCoords = const {},
    this.suggestedOrder = const [],
    this.displayOrder = const [],
    this.manualOrderActive = false,
    this.updatingStops = const {},
    this.tripCompleting = false,
    this.etaSecondsCache = const {},
    this.justCompletedTrip,
  });

  /// Resolved coordinates for pending stops, keyed `ed:&lt;externalDelivery&gt;`
  /// or `pj:&lt;pickupJob&gt;`. Best-effort — a stop with no entry is excluded
  /// from nearest-neighbor sorting and stays appended at the end in server
  /// order.
  final Map<String, (double, double)> stopCoords;

  /// Pure nearest-neighbor algorithm output — recalculated on every
  /// [TripController.resolveSequencing] call, never on a live GPS tick.
  final List<String> suggestedOrder;

  /// What's actually rendered/drag-reorderable. Mirrors [suggestedOrder]
  /// until the driver manually reorders, after which only completed/vanished
  /// stops are dropped and new ones appended — "manual order sticks".
  final List<String> displayOrder;
  final bool manualOrderActive;

  /// In-flight guard, keyed by stop key — a stop present here has an action
  /// (Delivered/Failed/pickup status change) currently being submitted.
  final Set<String> updatingStops;

  /// True while a trip-completion commit is in flight, guarding against a
  /// second concurrent auto-complete attempt racing the first.
  final bool tripCompleting;

  /// Best-effort ETA (seconds) per stop-key, fetched lazily via OSRM. The
  /// in-flight-fetch dedupe set is a plain (non-observable) field on
  /// [TripController] itself, not here — see [TripController.etaLabelFor].
  final Map<String, double?> etaSecondsCache;

  /// Set when [TripController.maybeAutoCompleteTrip] just completed a trip;
  /// the widget listens for this to show the "Trip completed" dialog and
  /// calls [TripController.acknowledgeTripCompleted] once handled.
  final ExternalDeliveryTrip? justCompletedTrip;

  TripControllerState copyWith({
    Map<String, (double, double)>? stopCoords,
    List<String>? suggestedOrder,
    List<String>? displayOrder,
    bool? manualOrderActive,
    Set<String>? updatingStops,
    bool? tripCompleting,
    Map<String, double?>? etaSecondsCache,
    Object? justCompletedTrip = _unset,
  }) {
    return TripControllerState(
      stopCoords: stopCoords ?? this.stopCoords,
      suggestedOrder: suggestedOrder ?? this.suggestedOrder,
      displayOrder: displayOrder ?? this.displayOrder,
      manualOrderActive: manualOrderActive ?? this.manualOrderActive,
      updatingStops: updatingStops ?? this.updatingStops,
      tripCompleting: tripCompleting ?? this.tripCompleting,
      etaSecondsCache: etaSecondsCache ?? this.etaSecondsCache,
      justCompletedTrip: identical(justCompletedTrip, _unset)
          ? this.justCompletedTrip
          : justCompletedTrip as ExternalDeliveryTrip?,
    );
  }
}

final tripControllerProvider =
    StateNotifierProvider.family<TripController, TripControllerState, String>(
  (ref, tripName) => TripController(ref, tripName),
);

class TripController extends StateNotifier<TripControllerState> {
  TripController(this._ref, this._tripName) : super(const TripControllerState());

  final Ref _ref;
  final String _tripName;

  /// Public accessor for the current state — `state` itself is `@protected`
  /// on `StateNotifier` and unreachable from outside this class (e.g. from
  /// the widget that watches this provider).
  TripControllerState get value => state;

  // ── Stop identity / lookup helpers ──────────────────────────────────────

  (double, double)? coordsFor(dynamic stop) {
    if (stop is ExternalDeliveryTripStop) {
      return state.stopCoords['ed:${stop.externalDelivery}'];
    } else if (stop is PickupTripStop) {
      return state.stopCoords['pj:${stop.pickupJob}'];
    }
    return null;
  }

  String stopKey(dynamic stop) {
    if (stop is ExternalDeliveryTripStop) {
      final String rowName = (stop.rawFields['name'] ?? '').toString().trim();
      if (rowName.isNotEmpty) return rowName;
      return '${stop.externalDelivery}-${stop.stop}';
    } else if (stop is PickupTripStop) {
      final String rowName = (stop.rawFields['name'] ?? '').toString().trim();
      if (rowName.isNotEmpty) return rowName;
      return '${stop.pickupJob}-${stop.stop}';
    }
    return '';
  }

  /// Nearest-first (or manually reordered) pending stops, rebuilt from
  /// [TripControllerState.displayOrder] on every call so it always reflects
  /// the latest state.
  List<dynamic> pendingOrderedStops(ExternalDeliveryTrip trip) {
    final List<dynamic> allStops = [...trip.stops, ...trip.pickupStops];
    final Map<String, dynamic> stopByKey = {
      for (final dynamic s in allStops) stopKey(s): s,
    };
    return [
      for (final String key in state.displayOrder)
        if (stopByKey.containsKey(key)) stopByKey[key]!,
    ];
  }

  /// The single "active stop" source of truth — replaces ad hoc
  /// `pendingOrdered.first` comparisons scattered across the UI.
  dynamic activeStop(ExternalDeliveryTrip trip) {
    final List<dynamic> pending = pendingOrderedStops(trip);
    return pending.isEmpty ? null : pending.first;
  }

  /// Explicit lifecycle status for [stop] within [trip].
  StopProgressStatus progressOf(dynamic stop, ExternalDeliveryTrip trip) {
    final dynamic active = activeStop(trip);
    final bool isActive = active != null && stopKey(active) == stopKey(stop);
    return deriveStopProgress(stop, isActive: isActive);
  }

  bool isUpdating(String key) => state.updatingStops.contains(key);

  // ── Sequencing ───────────────────────────────────────────────────────────

  /// Resolves coordinates for pending stops and recomputes
  /// [TripControllerState.suggestedOrder]/[TripControllerState.displayOrder],
  /// always from the driver's current live GPS location. Best-effort: a
  /// network failure here never breaks the trip screen — unresolved stops
  /// simply stay in server order at the end of the list.
  Future<void> resolveSequencing(ExternalDeliveryTrip trip) async {
    final List<ExternalDeliveryTripStop> pendingDeliveryStops =
        trip.stops.where((s) => !isTerminalStop(s)).toList();
    final List<PickupTripStop> pendingPickupStops =
        trip.pickupStops.where((s) => !isTerminalStop(s)).toList();

    final Map<String, (double, double)> nextCoords = Map.of(state.stopCoords);

    final List<String> missingDeliveryNames = pendingDeliveryStops
        .map((s) => s.externalDelivery)
        .where((n) => n.isNotEmpty)
        .toSet()
        .where((n) => !nextCoords.containsKey('ed:$n'))
        .toList();
    if (missingDeliveryNames.isNotEmpty) {
      try {
        final Map<String, ExternalDelivery> resolved =
            await ExternalDeliveryRepository()
                .fetchDeliveriesByNames(missingDeliveryNames);
        for (final MapEntry<String, ExternalDelivery> entry
            in resolved.entries) {
          final double? lat = entry.value.latitude;
          final double? lng = entry.value.longitude;
          if (lat != null && lng != null && isValidLatLng(lat, lng)) {
            nextCoords['ed:${entry.key}'] = (lat, lng);
          }
        }
      } catch (_) {
        // Best-effort — those stops just stay unsorted at the end.
      }
    }

    final List<String> missingPickupNames = pendingPickupStops
        .map((s) => s.pickupJob)
        .where((n) => n.isNotEmpty)
        .toSet()
        .where((n) => !nextCoords.containsKey('pj:$n'))
        .toList();
    if (missingPickupNames.isNotEmpty) {
      final PickupJobRepository repo = PickupJobRepository();
      final List<PickupJob?> results = await Future.wait(
        missingPickupNames.map((String n) async {
          try {
            return await repo.fetchJob(n);
          } catch (_) {
            return null;
          }
        }),
      );
      for (final PickupJob job in results.whereType<PickupJob>()) {
        final double? lat = job.pickupLatitude;
        final double? lng = job.pickupLongitude;
        if (lat != null && lng != null && isValidLatLng(lat, lng)) {
          nextCoords['pj:${job.name}'] = (lat, lng);
        }
      }
    }

    final List<String> pendingKeys = <String>[
      for (final ExternalDeliveryTripStop s in pendingDeliveryStops) stopKey(s),
      for (final PickupTripStop s in pendingPickupStops) stopKey(s),
    ];
    final Map<String, String> coordKeyOf = <String, String>{
      for (final ExternalDeliveryTripStop s in pendingDeliveryStops)
        stopKey(s): 'ed:${s.externalDelivery}',
      for (final PickupTripStop s in pendingPickupStops)
        stopKey(s): 'pj:${s.pickupJob}',
    };

    final double? fromLat = _ref.read(appControllerProvider).currentLatitude;
    final double? fromLng = _ref.read(appControllerProvider).currentLongitude;

    final List<String> suggested = TripSequencingService.suggestOrder(
      fromLat: fromLat,
      fromLng: fromLng,
      pendingKeys: pendingKeys,
      coordsOf: (String key) => nextCoords[coordKeyOf[key]],
    );

    final List<String> merged = TripSequencingService.mergeManualOrder(
      currentDisplayOrder: state.displayOrder,
      pendingKeys: pendingKeys,
      manualOrderActive: state.manualOrderActive,
      suggestedOrder: suggested,
    );

    state = state.copyWith(
      stopCoords: nextCoords,
      suggestedOrder: suggested,
      displayOrder: merged,
    );
  }

  /// Direct port of the drag-to-reorder splice — sets manual mode active.
  void reorder(int oldIndex, int newIndex) {
    final List<String> updated = List<String>.from(state.displayOrder);
    final String moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    state = state.copyWith(displayOrder: updated, manualOrderActive: true);
  }

  /// Moves [stop] to the back of the display order — "Skip for now". Purely
  /// client-side; does not touch server status or re-run sequencing.
  void skipForNow(dynamic stop) {
    final String key = stopKey(stop);
    final List<String> updated = List<String>.from(state.displayOrder)
      ..remove(key)
      ..add(key);
    state = state.copyWith(displayOrder: updated, manualOrderActive: true);
  }

  /// "Reset to suggested" — drops the manual override and snaps back to the
  /// pure nearest-neighbor order.
  void resetToSuggested() {
    state = state.copyWith(
      manualOrderActive: false,
      displayOrder: List<String>.from(state.suggestedOrder),
    );
  }

  // ── In-flight (duplicate-submission) guard ──────────────────────────────

  void beginAction(String key) {
    if (key.isEmpty) return;
    state = state.copyWith(updatingStops: {...state.updatingStops, key});
  }

  void endAction(String key) {
    if (!state.updatingStops.contains(key)) return;
    final Set<String> updated = Set<String>.from(state.updatingStops)
      ..remove(key);
    state = state.copyWith(updatingStops: updated);
  }

  // ── Delivery radius gate (read-only against AppController) ─────────────

  (bool ok, String? blockMessage) checkDeliveryRadius(dynamic stop) {
    final (double, double)? coords = coordsFor(stop);
    final app = _ref.read(appControllerProvider);
    final bool within = app.isWithinDeliveryRadiusAt(coords?.$1, coords?.$2);
    if (within || coords == null) return (true, null);
    final double? distanceKm = app.distanceFromPartnerKm(coords.$1, coords.$2);
    final double? radiusKm = app.deliveryRadiusKm;
    final String distanceLabel =
        distanceKm != null ? formatDistance(distanceKm * 1000) : 'too far';
    final String radiusLabel = radiusKm != null
        ? '${radiusKm.toStringAsFixed(radiusKm.truncateToDouble() == radiusKm ? 0 : 1)} km'
        : 'the delivery radius';
    return (
      false,
      "You're $distanceLabel — get within $radiusLabel to mark this delivered.",
    );
  }

  // ── ETA (OSRM, cached) ───────────────────────────────────────────────────

  /// Plain instance field, NOT part of [TripControllerState] — this only
  /// dedupes concurrent OSRM fetches and must never trigger a provider
  /// state update synchronously. [etaLabelFor] is called from build methods
  /// (the "Nearest stop" banner computes it on every rebuild), and Riverpod
  /// forbids modifying a provider's state while the widget tree is
  /// building — only the eventual (always-async) `.then()` callback below is
  /// allowed to call `state = ...`.
  final Set<String> _etaFetchInFlight = {};

  String? etaLabelFor(
    String stopKeyValue,
    double driverLat,
    double driverLng,
    double destLat,
    double destLng,
  ) {
    if (state.etaSecondsCache.containsKey(stopKeyValue)) {
      final double? seconds = state.etaSecondsCache[stopKeyValue];
      return seconds == null ? null : formatEta(seconds);
    }
    if (_etaFetchInFlight.add(stopKeyValue)) {
      TripRouteService.fetchRouteWithEta([
        LatLng(driverLat, driverLng),
        LatLng(destLat, destLng),
      ]).then((result) {
        _etaFetchInFlight.remove(stopKeyValue);
        if (!mounted) return;
        final Map<String, double?> updatedCache =
            Map<String, double?>.from(state.etaSecondsCache);
        updatedCache[stopKeyValue] = result?.durationSeconds;
        state = state.copyWith(etaSecondsCache: updatedCache);
      });
    }
    return null;
  }

  static String formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m away';
    return '${(meters / 1000).toStringAsFixed(1)} km away';
  }

  static String formatEta(double seconds) {
    final int minutes = (seconds / 60).round();
    if (minutes < 1) return '<1 min';
    if (minutes < 60) return '~$minutes min';
    return '~${minutes ~/ 60}h ${minutes % 60}m';
  }

  // ── Mutation commits (network/offline calls only, no BuildContext) ─────

  /// Marks [stop] Delivered. Callers must already have gathered
  /// proof-of-delivery/COD inputs via UI sheets before calling this — those
  /// steps stay in the widget since they require a BuildContext.
  Future<void> markDeliveredCommit(
    ExternalDeliveryTripStop stop, {
    required bool isCod,
  }) async {
    final String stopDocType = (stop.rawFields['doctype'] ?? '').toString().trim();
    final String stopName = (stop.rawFields['name'] ?? '').toString().trim();
    final String parentTripName =
        (stop.rawFields['parent'] ?? '').toString().trim();

    // Online: the async-queue flush (conflict check + PUT) can exceed the
    // 800ms reload window, causing the reload to still see the stop as
    // pending — it then reappears as "next" (wrong address in the
    // navigate/next-stop UI) until a later reload catches up. Use the
    // direct awaited path whenever we have connectivity, regardless of
    // COD — this used to be COD-only, but the race applies equally to a
    // plain delivery.
    if (ConnectivityService().isConnected) {
      await ExternalDeliveryRepository()
          .updateTripStopStatus(stop: stop, newStatus: 'Delivered');
    } else {
      await OfflineTripManager().updateStopStatusOffline(
        stopDocType: stopDocType,
        stopName: stopName,
        parentTripName: parentTripName,
        orderName: stop.externalDelivery.trim(),
        newStatus: 'Delivered',
      );
    }
    _ref.read(appControllerProvider).recordTimingEvent(
          eventType: TimingEventType.stopDelivered,
          tripRef: parentTripName.isEmpty ? null : parentTripName,
          stopRef: stopName.isEmpty ? null : stopName,
        );
  }

  Future<void> markFailedOfflineCommit(ExternalDeliveryTripStop stop) async {
    final String stopDocType = (stop.rawFields['doctype'] ?? '').toString().trim();
    final String stopName = (stop.rawFields['name'] ?? '').toString().trim();
    final String parentTripName =
        (stop.rawFields['parent'] ?? '').toString().trim();
    await OfflineTripManager().updateStopStatusOffline(
      stopDocType: stopDocType,
      stopName: stopName,
      parentTripName: parentTripName,
      orderName: stop.externalDelivery.trim(),
      newStatus: 'Failed',
    );
    _ref.read(appControllerProvider).recordTimingEvent(
          eventType: TimingEventType.stopFailed,
          tripRef: parentTripName.isEmpty ? null : parentTripName,
          stopRef: stopName.isEmpty ? null : stopName,
        );
  }

  Future<ReturnProcessResult> markFailedOnlineCommit(
    ExternalDeliveryTripStop stop, {
    required String orderName,
    required String fullReason,
    required String reasonCode,
    required String? photoPath,
  }) async {
    final ReturnProcessResult processResult =
        await ExternalDeliveryRepository().processFailedDeliveryReturn(
      stop: stop,
      orderName: orderName,
      reason: fullReason,
      reasonCode: reasonCode,
      photoPath: photoPath,
      shouldCreateReturnTrip: false,
    );
    final String parent = (stop.rawFields['parent'] ?? '').toString().trim();
    final String name = (stop.rawFields['name'] ?? '').toString().trim();
    _ref.read(appControllerProvider).recordTimingEvent(
          eventType: TimingEventType.stopFailed,
          tripRef: parent.isEmpty ? null : parent,
          stopRef: name.isEmpty ? null : name,
        );
    return processResult;
  }

  /// Pending/blank → En Route. Mirrors the single pickup-job screen's
  /// "Mark En Route" action (`PickupJobDetailScreen._handleMarkEnRoute`) —
  /// writes `External Delivery Trip Pickup Stop.status='En Route'`; the
  /// parent `Pickup Job` doc's status flip to `Scheduled` is a server-side
  /// side effect, not a second client write.
  Future<void> startPickupEnRouteCommit(PickupTripStop ps) async {
    await PickupJobRepository().markPickupEnRoute(
      pickupJobName: ps.pickupJob,
      tripName: _tripName,
    );
  }

  /// En Route → Picked Up. Mirrors `PickupJobDetailScreen._handleMarkPickedUp`.
  /// Caller has already run the customer OTP gate, which transitions the
  /// Pickup Job to Picked Up server-side — this call is now just for the
  /// proof photo, so a failure here is swallowed rather than surfaced as a
  /// blocking error.
  Future<void> markPickupPickedUpCommit(
    PickupTripStop ps, {
    String? proofPhotoPath,
  }) async {
    try {
      await PickupJobRepository().markPickedUp(
        ps.pickupJob,
        proofPhotoPath: proofPhotoPath,
      );
    } catch (_) {
    }
  }

  /// Picked Up → Received at Store. Mirrors
  /// `PickupJobDetailScreen._handleDropAtStore` — completes the Pickup Job
  /// doc first, then flips the trip-stop row status.
  Future<void> markPickupReceivedAtStoreCommit(PickupTripStop ps) async {
    await PickupJobRepository().confirmCompleted(ps.pickupJob);
    await PickupJobRepository().updatePickupTripStopCompleted(
      tripName: _tripName,
      pickupJobName: ps.pickupJob,
    );
  }

  /// Mirrors `PickupJobDetailScreen._handleMarkFailed` — writes both the
  /// `Pickup Job` doc (status/reason/notes/photo) and, best-effort, the
  /// trip-stop row, via the richer `markPickupFailed` (unlike the old
  /// single-field `setStopStatusRaw` this replaces).
  Future<void> markPickupFailedCommit(
    PickupTripStop ps, {
    required String reasonCode,
    String notes = '',
    String? photoPath,
  }) async {
    await PickupJobRepository().markPickupFailed(
      ps.pickupJob,
      reasonCode: reasonCode,
      notes: notes,
      proofPhotoPath: photoPath,
      tripName: _tripName,
    );
  }

  /// Port of `_updateStopStatus`'s generic (non-Delivered/Failed) path.
  /// Returns the message the widget should show in its SnackBar.
  Future<String> updateGenericStopStatusCommit(
    ExternalDeliveryTripStop stop,
    String newStatus,
  ) async {
    final String stopDocType = (stop.rawFields['doctype'] ?? '').toString().trim();
    final String stopName = (stop.rawFields['name'] ?? '').toString().trim();
    final String parentTripName =
        (stop.rawFields['parent'] ?? '').toString().trim();
    await OfflineTripManager().updateStopStatusOffline(
      stopDocType: stopDocType,
      stopName: stopName,
      parentTripName: parentTripName,
      orderName: stop.externalDelivery.trim(),
      newStatus: newStatus,
    );
    final bool isConnected = ConnectivityService().isConnected;
    return isConnected
        ? 'Stop status updated to $newStatus'
        : 'Saved offline. Will sync when reconnected.';
  }

  // ── Trip completion ──────────────────────────────────────────────────────

  /// Auto-completes [trip] once every stop has reached a terminal status.
  /// Idempotent and safe to retry — re-setting the same status/count/
  /// timestamp on an already-Completed trip is harmless, so a failure here
  /// (e.g. network loss right at the last stop) just gets retried the next
  /// time the caller finds zero pending stops again. [tripCompleting] adds a
  /// client-side re-entrancy guard on top of that existing server-side
  /// idempotency, closing a narrow race window where two stop-completion
  /// events could otherwise both attempt completion concurrently. Returns
  /// true only when this call actually performed the completion (so the
  /// widget knows whether to show the dialog via [TripControllerState
  /// .justCompletedTrip], which this method sets on success).
  Future<bool> maybeAutoCompleteTrip(ExternalDeliveryTrip trip) async {
    if (trip.status.trim().toLowerCase() == 'completed') return false;
    if (state.tripCompleting) return false;
    state = state.copyWith(tripCompleting: true);
    try {
      await ExternalDeliveryRepository().completeTrip(trip);
      _ref.read(appControllerProvider).recordTimingEvent(
            eventType: TimingEventType.tripCompleted,
            tripRef: trip.name.isEmpty ? null : trip.name,
          );
      debugPrint('[Nav] trip auto-completed => ${trip.name}');
      state = state.copyWith(justCompletedTrip: trip);
      return true;
    } catch (e) {
      debugPrint('[Nav] trip auto-complete failed => $e');
      return false;
    } finally {
      if (mounted) state = state.copyWith(tripCompleting: false);
    }
  }

  void acknowledgeTripCompleted() {
    state = state.copyWith(justCompletedTrip: null);
  }
}
