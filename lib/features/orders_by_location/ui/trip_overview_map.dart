import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/context_colors.dart';

/// Where a stop currently stands in the trip, used to style its map pin.
enum StopMapStatus { active, pending, completed }

/// A single stop pin for the trip overview map.
class OverviewMapStop {
  const OverviewMapStop({
    required this.id,
    required this.sequenceNumber,
    required this.lat,
    required this.lng,
    required this.status,
  });

  final String id;
  final int sequenceNumber;
  final double lat;
  final double lng;
  final StopMapStatus status;
}

/// Read-only overview map (Map A) showing every stop as a status-colored pin
/// in current sequence order, the driver's live position, and the trip route
/// (a real road-following polyline when [routePoints] is supplied, else a
/// cosmetic straight-line fallback) — purely visual, no turn-by-turn guidance.
/// Distinct from [TripStopMapScreen] (Map B), which handles single-destination
/// navigation for one stop at a time.
class TripOverviewMap extends StatefulWidget {
  const TripOverviewMap({
    super.key,
    required this.stops,
    this.driverLat,
    this.driverLng,
    this.routePoints,
    this.height = 220,
  });

  final List<OverviewMapStop> stops;
  final double? driverLat;
  final double? driverLng;

  /// Real road-following route points (driver → pending stops, in trip
  /// sequence), fetched externally. When null, a straight-line connector
  /// between the driver and pending stops is drawn instead.
  final List<LatLng>? routePoints;

  /// Fixed preview height when embedded inline. Pass null to fill all
  /// available space instead (e.g. inside a Positioned.fill on a full-screen
  /// map view) — the parent must then provide bounded constraints.
  final double? height;

  @override
  State<TripOverviewMap> createState() => _TripOverviewMapState();
}

class _TripOverviewMapState extends State<TripOverviewMap> {
  final MapController _mapController = MapController();
  bool _isMapReady = false;

  @override
  void didUpdateWidget(covariant TripOverviewMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isMapReady &&
        (oldWidget.stops.length != widget.stops.length ||
            oldWidget.driverLat != widget.driverLat ||
            oldWidget.driverLng != widget.driverLng)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  List<LatLng> get _allPoints => [
        for (final OverviewMapStop s in widget.stops) LatLng(s.lat, s.lng),
        if (widget.driverLat != null && widget.driverLng != null)
          LatLng(widget.driverLat!, widget.driverLng!),
      ];

  List<OverviewMapStop> get _pendingStops => widget.stops
      .where((OverviewMapStop s) => s.status != StopMapStatus.completed)
      .toList();

  void _fitBounds() {
    final List<LatLng> points = _allPoints;
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, 14.0);
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(40),
      ),
    );
  }

  Color _pinColor(BuildContext context, StopMapStatus status) {
    switch (status) {
      case StopMapStatus.active:
        return context.success;
      case StopMapStatus.pending:
        return Colors.white;
      case StopMapStatus.completed:
        return context.textDisabled;
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<LatLng> points = _allPoints;
    final LatLng initialCenter =
        points.isNotEmpty ? points.first : const LatLng(20.5937, 78.9629);

    final List<LatLng> routeLine = widget.routePoints != null &&
            widget.routePoints!.length > 1
        ? widget.routePoints!
        : <LatLng>[
            if (widget.driverLat != null && widget.driverLng != null)
              LatLng(widget.driverLat!, widget.driverLng!),
            for (final OverviewMapStop s in _pendingStops) LatLng(s.lat, s.lng),
          ];

    final Widget mapStack = Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: 13.0,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
            ),
            onMapReady: () {
              _isMapReady = true;
              _fitBounds();
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.lyncspace.grozfygo',
            ),
            if (routeLine.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: routeLine,
                    strokeWidth: 4,
                    color: AppTheme.oceanBlue.withValues(alpha: 0.75),
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                for (final OverviewMapStop s in widget.stops)
                  Marker(
                    point: LatLng(s.lat, s.lng),
                    width: 34,
                    height: 34,
                    child: _StopPin(
                      color: _pinColor(context, s.status),
                      status: s.status,
                      number: s.sequenceNumber,
                    ),
                  ),
                if (widget.driverLat != null && widget.driverLng != null)
                  Marker(
                    point: LatLng(widget.driverLat!, widget.driverLng!),
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.oceanBlue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.oceanBlue.withValues(alpha: 0.4),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.delivery_dining_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        if (points.isEmpty)
          Container(
            color: context.surfaceMuted,
            alignment: Alignment.center,
            child: Text(
              'Map unavailable for these stops',
              style: TextStyle(color: context.textSecondary, fontSize: 12),
            ),
          ),
        if (points.isNotEmpty)
          Positioned(
            left: 12,
            bottom: 16,
            child: _MapLegend(pinColor: (status) => _pinColor(context, status)),
          ),
        if (widget.height == null)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.small(
              heroTag: null,
              onPressed: _fitBounds,
              child: const Icon(Icons.my_location_rounded),
            ),
          ),
      ],
    );

    if (widget.height == null) {
      return mapStack;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(height: widget.height, child: mapStack),
    );
  }
}

class _StopPin extends StatelessWidget {
  const _StopPin({
    required this.color,
    required this.status,
    required this.number,
  });

  final Color color;
  final StopMapStatus status;
  final int number;

  @override
  Widget build(BuildContext context) {
    final bool isActive = status == StopMapStatus.active;
    final bool isRemaining = status == StopMapStatus.pending;
    final Color contentColor = isRemaining ? Colors.grey.shade700 : Colors.white;
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: isRemaining ? Colors.grey.shade400 : Colors.white,
          width: isActive ? 2.5 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: (isRemaining ? Colors.black : color)
                .withValues(alpha: isRemaining ? 0.15 : 0.35),
            blurRadius: isActive ? 10 : 8,
            spreadRadius: isActive ? 2 : 1,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: status == StopMapStatus.completed
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
          : Text(
              '$number',
              style: TextStyle(
                color: contentColor,
                fontWeight: FontWeight.w700,
                fontSize: isActive ? 14 : 13,
              ),
            ),
    );
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend({required this.pinColor});

  final Color Function(StopMapStatus status) pinColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.cardColor.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _legendRow(context, AppTheme.oceanBlue, 'You'),
          const SizedBox(height: 4),
          _legendRow(context, pinColor(StopMapStatus.active), 'Next stop'),
          const SizedBox(height: 4),
          _legendRow(context, pinColor(StopMapStatus.pending), 'Remaining'),
          const SizedBox(height: 4),
          _legendRow(context, pinColor(StopMapStatus.completed), 'Completed'),
        ],
      ),
    );
  }

  Widget _legendRow(BuildContext context, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey.shade400, width: 0.75),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: context.textSecondary),
        ),
      ],
    );
  }
}
