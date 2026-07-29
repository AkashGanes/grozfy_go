import '../model/external_delivery.dart';

/// Explicit lifecycle state for a single trip stop (delivery or pickup).
///
/// [active] is always *derived* from a stop's position in the current
/// display order, never stored as an independent mutable flag — so it is
/// structurally impossible for two stops to be active at once.
enum StopProgressStatus {
  pending,
  active,
  delivered,
  failed,
  returned,
  cancelled,
  receivedAtStore,
}

const Set<String> terminalStopStatuses = <String>{
  'delivered',
  'returned',
  'failed',
  'cancelled',
  'received at store',
};

/// Mirrors the terminal-status check historically inlined in the trip
/// details screen (`_isTerminalStop`).
bool isTerminalStop(dynamic stop) {
  final String status = stop is ExternalDeliveryTripStop
      ? stop.status
      : (stop as PickupTripStop).status;
  return terminalStopStatuses.contains(status.trim().toLowerCase());
}

/// Derives the explicit [StopProgressStatus] for [stop]. [isActive] should be
/// true only for the stop currently first in the pending display order.
StopProgressStatus deriveStopProgress(dynamic stop, {required bool isActive}) {
  final String status = stop is ExternalDeliveryTripStop
      ? stop.status
      : (stop as PickupTripStop).status;
  final String normalized = status.trim().toLowerCase();

  switch (normalized) {
    case 'delivered':
      return StopProgressStatus.delivered;
    case 'failed':
      return StopProgressStatus.failed;
    case 'returned':
      return StopProgressStatus.returned;
    case 'cancelled':
      return StopProgressStatus.cancelled;
    case 'received at store':
      return StopProgressStatus.receivedAtStore;
    default:
      return isActive ? StopProgressStatus.active : StopProgressStatus.pending;
  }
}
