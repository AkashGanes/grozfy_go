import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_shell.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.repository.fetchDetail(widget.order.name);
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _launchNavigation(ExternalDeliveryDetail detail) async {
    Uri uri;
    if (detail.latitude != null && detail.longitude != null) {
      // coords → Google Maps navigation
      uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${detail.latitude},${detail.longitude}&travelmode=driving',
      );
    } else if (detail.deliveryAddress != null) {
      // address → Google Maps search
      final encoded = Uri.encodeComponent(detail.deliveryAddress!);
      uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$encoded',
      );
    } else {
      if (mounted) showInfoSnack(context, 'No destination available');
      return;
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) showInfoSnack(context, 'Could not open Maps');
    }
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
        _MapLayer(latitude: null, longitude: null),
        // Back button
        const _BackButton(),
        // Loading panel
        DraggableScrollableSheet(
          initialChildSize: 0.28,
          minChildSize: 0.28,
          maxChildSize: 0.28,
          builder: (_, controller) => _SheetShell(
            scrollController: controller,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.oceanBlue),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Stack(
      children: [
        _MapLayer(latitude: null, longitude: null),
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
                const Icon(
                  Icons.error_outline_rounded,
                  color: Colors.redAccent,
                  size: 36,
                ),
                const SizedBox(height: 8),
                Text(
                  _error ?? 'Something went wrong',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
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
    return Stack(
      children: [
        // Full screen map
        _MapLayer(
          latitude: detail.latitude,
          longitude: detail.longitude,
        ),
        // Back button overlay
        const _BackButton(),
        // Order ID badge (top right)
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              detail.name,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: AppTheme.nightBlue,
              ),
            ),
          ),
        ),
        // Draggable bottom sheet
        DraggableScrollableSheet(
          initialChildSize: 0.38,
          minChildSize: 0.22,
          maxChildSize: 0.75,
          snap: true,
          snapSizes: const [0.22, 0.38, 0.75],
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                  const SizedBox(height: 4),
                  // Customer row
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppTheme.oceanBlue.withValues(alpha: 0.10),
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
                                fontSize: 17,
                                color: AppTheme.nightBlue,
                              ),
                            ),
                            if (detail.contactMobile != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                detail.contactMobile!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black45,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (detail.contactMobile != null)
                        _CallButton(mobile: detail.contactMobile!),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  // Delivery address
                  _AddressRow(
                    icon: Icons.location_on_rounded,
                    iconColor: Colors.redAccent,
                    label: 'Delivery',
                    address: detail.deliveryAddress ?? 'Address not available',
                  ),
                  if (detail.pickupAddress != null) ...[
                    const SizedBox(height: 14),
                    _AddressRow(
                      icon: Icons.store_rounded,
                      iconColor: AppTheme.oceanBlue,
                      label: 'Pickup',
                      address: detail.pickupAddress!,
                    ),
                  ],
                  const SizedBox(height: 24),
                  // Start button
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE8384F),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () => _launchNavigation(detail),
                    icon: const Icon(Icons.navigation_rounded, size: 20),
                    label: const Text(
                      'Start',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
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
  const _MapLayer({this.latitude, this.longitude});
  final double? latitude;
  final double? longitude;

  @override
  Widget build(BuildContext context) {
    const defaultCenter = LatLng(8.1833, 77.4119); // Nagercoil, Tamil Nadu
    final hasPin = latitude != null && longitude != null;
    final center = hasPin ? LatLng(latitude!, longitude!) : defaultCenter;

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: hasPin ? 15.0 : 13.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.delivery_partner_app',
        ),
        if (hasPin)
          MarkerLayer(
            markers: [
              Marker(
                point: center,
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
// Shared sheet shell (loading / error states)
// ---------------------------------------------------------------------------

class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.scrollController, required this.child});
  final ScrollController scrollController;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Color(0x22000000), blurRadius: 20, offset: Offset(0, -4)),
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
// Address row widget
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
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black45,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                address,
                style: const TextStyle(
                  fontSize: 14,
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
// Call button
// ---------------------------------------------------------------------------

class _CallButton extends StatelessWidget {
  const _CallButton({required this.mobile});
  final String mobile;

  Future<void> _call() async {
    final digits = mobile.replaceAll(RegExp(r'\s+'), '');
    await launchUrl(Uri.parse('tel:$digits'));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _call,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.3)),
        ),
        child: const Icon(
          Icons.phone_rounded,
          color: Color(0xFF4CAF50),
          size: 18,
        ),
      ),
    );
  }
}
