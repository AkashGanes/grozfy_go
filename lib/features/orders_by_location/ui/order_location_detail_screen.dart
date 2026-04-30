import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/services/connectivity_service.dart';
import '../../../core/services/offline_trip_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/call_utils.dart';
import '../model/external_delivery.dart';
import '../model/external_delivery_detail.dart';
import '../repository/external_delivery_repository.dart';

class OrderLocationDetailScreen extends StatefulWidget {
  const OrderLocationDetailScreen({
    super.key,
    required this.order,
    required this.repository,
  });

  final ExternalDelivery order;
  final ExternalDeliveryRepository repository;

  @override
  State<OrderLocationDetailScreen> createState() =>
      _OrderLocationDetailScreenState();
}

class _OrderLocationDetailScreenState
    extends State<OrderLocationDetailScreen> {
  ExternalDeliveryDetail? _detail;
  bool _loading = true;
  String? _error;
  bool _updating = false;

  final MapController _mapController = MapController();
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // Offline first: serve cached order if we have it.
    if (!ConnectivityService().isConnected) {
      final cached = OfflineTripManager().getCachedOrder(widget.order.name);
      setState(() {
        _detail = cached;
        _loading = false;
        _error = cached == null
            ? 'No internet and no cached copy of this order. '
                'Open it once online to enable offline access.'
            : null;
      });
      return;
    }
    // Online: hit the repository directly so any error surfaces here.
    try {
      final detail = await widget.repository.fetchDetail(widget.order.name);
      ConnectivityService().reportNetworkSuccess();
      // Persist to the cache so subsequent offline opens succeed.
      await OfflineTripManager().cacheOrderDetail(detail);
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (_isNetworkError(e)) {
        ConnectivityService().reportNetworkFailure();
        final cached =
            OfflineTripManager().getCachedOrder(widget.order.name);
        if (cached != null) {
          setState(() {
            _detail = cached;
            _loading = false;
          });
          return;
        }
      }
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _updating = true);
    try {
      // Always go through the offline-aware path. It queues + flushes
      // immediately when online, queues + updates the local cache when
      // offline. Either way the user sees the new status right away.
      await OfflineTripManager().updateOrderStatusOffline(
        orderName: widget.order.name,
        newStatus: newStatus,
      );
      if (!mounted) return;
      final isConnected = ConnectivityService().isConnected;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isConnected
                ? 'Status updated to $newStatus'
                : 'Saved offline. Will sync when reconnected.',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  bool _isNetworkError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('socketexception') ||
        s.contains('network is unreachable') ||
        s.contains('failed host lookup') ||
        s.contains('connection failed') ||
        s.contains('connection refused') ||
        s.contains('connection closed') ||
        s.contains('timed out') ||
        s.contains('clientexception');
  }

  void _startTracking(ExternalDeliveryDetail detail) {
    setState(() => _started = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (detail.latitude != null && detail.longitude != null) {
        _mapController.fitCamera(
          CameraFit.coordinates(
            coordinates: [
              const LatLng(8.1833, 77.4119), // partner location
              LatLng(detail.latitude!, detail.longitude!),
            ],
            padding: const EdgeInsets.fromLTRB(48, 80, 48, 220),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? _buildLoading()
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildLoading() {
    return Stack(
      children: [
        _MapLayer(mapController: _mapController, started: false),
        const _BackButton(),
        DraggableScrollableSheet(
          initialChildSize: 0.28,
          minChildSize: 0.28,
          maxChildSize: 0.28,
          builder: (_, controller) => _SheetShell(
            scrollController: controller,
            child: const _LoadingSkeleton(),
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Stack(
      children: [
        _MapLayer(mapController: _mapController, started: false),
        const _BackButton(),
        DraggableScrollableSheet(
          initialChildSize: 0.35,
          minChildSize: 0.28,
          maxChildSize: 0.5,
          builder: (_, controller) => _SheetShell(
            scrollController: controller,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: Colors.redAccent, size: 36),
                const SizedBox(height: 8),
                Text(
                  _error ?? 'Something went wrong',
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    final detail = _detail!;
    final statusColor = detail.status.statusColor;

    return Stack(
      children: [
        // Full screen map
        _MapLayer(
          mapController: _mapController,
          started: _started,
          latitude: detail.latitude,
          longitude: detail.longitude,
        ),

        // Back button
        const _BackButton(),

        // Draggable bottom sheet
        DraggableScrollableSheet(
          initialChildSize: 0.45,
          minChildSize: 0.22,
          maxChildSize: 0.92,
          snap: true,
          snapSizes: const [0.22, 0.45, 0.92],
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 20,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.fromLTRB(
                  20,
                  0,
                  20,
                  MediaQuery.of(context).padding.bottom + 16,
                ),
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // ── Order ID + Store + Status ──────────────────
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              detail.name,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.nightBlue,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.store_rounded,
                                    size: 13, color: Colors.black38),
                                const SizedBox(width: 4),
                                Text(
                                  detail.storeName,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: statusColor.withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          detail.status,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 14),

                  // ── Customer ───────────────────────────────────
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color:
                              AppTheme.oceanBlue.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person_outline_rounded,
                          color: AppTheme.oceanBlue,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              detail.customerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: AppTheme.nightBlue,
                              ),
                            ),
                            if (detail.contactMobile != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                detail.contactMobile!,
                                style: const TextStyle(
                                    fontSize: 13, color: Colors.black45),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (detail.contactMobile != null)
                        CallButton(phoneNumber: detail.contactMobile!),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── Delivery address ───────────────────────────
                  _AddressRow(
                    icon: Icons.location_on_rounded,
                    iconColor: Colors.redAccent,
                    label: 'Delivery',
                    address: detail.deliveryAddress ?? 'Address not available',
                  ),
                  if (detail.pickupAddress != null) ...[
                    const SizedBox(height: 12),
                    _AddressRow(
                      icon: Icons.store_rounded,
                      iconColor: AppTheme.oceanBlue,
                      label: 'Pickup',
                      address: detail.pickupAddress!,
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 14),

                  // ── Items ──────────────────────────────────────
                  if (detail.items.isNotEmpty) ...[
                    const _SheetSectionLabel(
                        icon: Icons.shopping_bag_rounded, label: 'Items'),
                    const SizedBox(height: 10),
                    ...detail.items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              margin:
                                  const EdgeInsets.only(right: 10, top: 1),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.oceanBlue,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                item.itemName,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppTheme.nightBlue,
                                ),
                              ),
                            ),
                            Text(
                              'x${item.qty % 1 == 0 ? item.qty.toInt() : item.qty}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.nightBlue,
                              ),
                            ),
                            if (item.amount != null) ...[
                              const SizedBox(width: 14),
                              Text(
                                '₹${item.amount!.toStringAsFixed(0)}',
                                style: const TextStyle(
                                    fontSize: 13, color: Colors.black45),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Divider(height: 1),
                    const SizedBox(height: 14),
                  ],

                  // ── Action buttons ─────────────────────────────
                  if (_updating)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: CircularProgressIndicator(
                            color: AppTheme.oceanBlue),
                      ),
                    )
                  else ...[
                    const _SheetSectionLabel(
                        icon: Icons.touch_app_rounded, label: 'Actions'),
                    const SizedBox(height: 12),
                    _ActionButtons(
                      status: detail.status,
                      started: _started,
                      onStart: () => _startTracking(detail),
                      onAccept: () => _updateStatus('Accepted'),
                      onStartDelivery: () =>
                          _updateStatus('Out for Delivery'),
                      onDelivered: () => _updateStatus('Delivered'),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Full-screen map layer
// ---------------------------------------------------------------------------

class _MapLayer extends StatelessWidget {
  const _MapLayer({
    required this.mapController,
    required this.started,
    this.latitude,
    this.longitude,
  });

  final MapController mapController;
  final bool started;
  final double? latitude;
  final double? longitude;

  static const _partnerLocation = LatLng(8.1833, 77.4119);

  @override
  Widget build(BuildContext context) {
    final hasDestination = latitude != null && longitude != null;
    final destination =
        hasDestination ? LatLng(latitude!, longitude!) : null;
    final initialCenter = hasDestination ? destination! : _partnerLocation;

    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: hasDestination ? 15.0 : 13.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.lyncspace.grozfygo',
        ),
        MarkerLayer(
          markers: [
            // Delivery partner marker (shown when started)
            if (started)
              Marker(
                point: _partnerLocation,
                width: 52,
                height: 52,
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
                    size: 26,
                  ),
                ),
              ),
            // Destination marker
            if (hasDestination)
              Marker(
                point: destination!,
                width: 48,
                height: 48,
                child: const Icon(
                  Icons.location_pin,
                  color: Colors.redAccent,
                  size: 42,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Back button overlay
// ---------------------------------------------------------------------------

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.arrow_back_rounded,
            color: AppTheme.nightBlue,
            size: 20,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sheet shell (loading / error states)
// ---------------------------------------------------------------------------

class _SheetShell extends StatelessWidget {
  const _SheetShell(
      {required this.scrollController, required this.child});
  final ScrollController scrollController;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
              color: Color(0x22000000),
              blurRadius: 20,
              offset: Offset(0, -4)),
        ],
      ),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sheet section label
// ---------------------------------------------------------------------------

class _SheetSectionLabel extends StatelessWidget {
  const _SheetSectionLabel({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppTheme.oceanBlue),
        const SizedBox(width: 5),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTheme.oceanBlue,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Address row
// ---------------------------------------------------------------------------

class _AddressRow extends StatelessWidget {
  const _AddressRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.address,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.black45,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                address,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.nightBlue,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}



// ---------------------------------------------------------------------------
// Action buttons
// ---------------------------------------------------------------------------

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.status,
    required this.started,
    required this.onStart,
    required this.onAccept,
    required this.onStartDelivery,
    required this.onDelivered,
  });

  final String status;
  final bool started;
  final VoidCallback onStart;
  final VoidCallback onAccept;
  final VoidCallback onStartDelivery;
  final VoidCallback onDelivered;

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();

    if (s == 'delivered' || s == 'cancelled') {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Start button — shows partner + destination on the map (no external app)
        _Btn(
          label: started ? 'Tracking Active' : 'Start',
          icon: started
              ? Icons.my_location_rounded
              : Icons.play_arrow_rounded,
          color: started
              ? const Color(0xFF4CAF50)
              : const Color(0xFFE8384F),
          onTap: onStart,
        ),
        const SizedBox(height: 10),
        if (s == 'pending' || s == '')
          _Btn(
            label: 'Accept Order',
            icon: Icons.check_circle_rounded,
            color: AppTheme.oceanBlue,
            onTap: onAccept,
          ),
        if (s == 'accepted')
          _Btn(
            label: 'Start Delivery',
            icon: Icons.local_shipping_rounded,
            color: const Color(0xFF4CAF50),
            onTap: onStartDelivery,
          ),
        if (s == 'out for delivery')
          _Btn(
            label: 'Delivered',
            icon: Icons.done_all_rounded,
            color: const Color(0xFF4CAF50),
            onTap: onDelivered,
          ),
      ],
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 0,
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(
        label,
        style:
            const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            height: 18,
            decoration: BoxDecoration(
              color: AppTheme.oceanBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
          )
              .animate(onPlay: (controller) => controller.repeat())
              .shimmer(
                duration: 1000.ms,
                color: AppTheme.oceanBlue.withValues(alpha: 0.06),
              ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.oceanBlue.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
              )
                  .animate(onPlay: (controller) => controller.repeat())
                  .shimmer(
                    duration: 1000.ms,
                    color: AppTheme.oceanBlue.withValues(alpha: 0.06),
                  ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 14,
                      decoration: BoxDecoration(
                        color: AppTheme.oceanBlue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    )
                        .animate(onPlay: (controller) => controller.repeat())
                        .shimmer(
                          duration: 1000.ms,
                          color: AppTheme.oceanBlue.withValues(alpha: 0.06),
                        ),
                    const SizedBox(height: 8),
                    Container(
                      width: 150,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppTheme.oceanBlue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    )
                        .animate(onPlay: (controller) => controller.repeat())
                        .shimmer(
                          duration: 1000.ms,
                          color: AppTheme.oceanBlue.withValues(alpha: 0.04),
                        ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
