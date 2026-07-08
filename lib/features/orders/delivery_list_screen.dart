import 'package:flutter/material.dart';
import '../../core/state/app_scope.dart';
import '../../core/utils/formatters.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../orders_by_location/model/external_delivery.dart';
import '../orders_by_location/model/external_delivery_detail.dart';
import '../orders_by_location/repository/external_delivery_repository.dart';
import '../orders_by_location/ui/delivery_proof_sheet.dart';

class DeliveryListScreen extends StatefulWidget {
  const DeliveryListScreen({super.key});

  @override
  State<DeliveryListScreen> createState() => _DeliveryListScreenState();
}

class _DeliveryListScreenState extends State<DeliveryListScreen> {
  final ExternalDeliveryRepository _repository = ExternalDeliveryRepository();

  List<ExternalDelivery> _deliveries = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _fetchDeliveries();
  }

  Future<void> _fetchDeliveries() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final deliveries = await _repository.fetchAllByStatus('Pending');
      if (mounted) {
        setState(() {
          _deliveries = deliveries;
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load: $e';
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _refreshDeliveries() async {
    setState(() => _isRefreshing = true);
    await _fetchDeliveries();
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'picked up':
      case 'pickedup':
        return Colors.purple;
      case 'out for delivery':
      case 'outfordelivery':
        return Colors.teal;
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  void _showDeliveryDetails(ExternalDelivery delivery) {
    showAppBottomSheet(
      context: context,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _DeliveryDetailsSheet(
          summary: delivery,
          scrollController: scrollController,
          onAccept: (name) => _repository.createTripForOrderName(name),
          onNavigateToDelivery: (detail) {
            if (detail.latitude == null || detail.longitude == null) {
              AppToast.show(context, 'No GPS coordinates for delivery location');
              return;
            }
            Navigator.of(context).pushNamed(
              '/delivery-tracking',
              arguments: {
                'name': detail.name,
                'customerName': detail.customerName,
                'storeName': detail.storeName,
                'contactNumber': detail.contactMobile ?? '',
                'dropAddress': detail.deliveryAddress ?? '',
                'pickupLat': null,
                'pickupLng': null,
                'dropLat': detail.latitude,
                'dropLng': detail.longitude,
              },
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Available Deliveries',
      subtitle: '${_deliveries.length} orders',
      scrollable: false,
      padding: EdgeInsets.zero,
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    if (_isLoading && !_isRefreshing) {
      return const SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 20, 16, 20),
        child: SkeletonLoader(itemCount: 5, spacing: 12),
      );
    }

    if (_errorMessage != null && _deliveries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: FrostCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 48,
                  color: AppTheme.mango.withValues(alpha: 0.8),
                ),
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _fetchDeliveries,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_deliveries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: FrostCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 52,
                  color: AppTheme.oceanBlue.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 12),
                Text(
                  'No deliveries available',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Pull down to refresh',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshDeliveries,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        itemCount: _deliveries.length,
        itemBuilder: (context, index) {
          final delivery = _deliveries[index];
          return _DeliveryCard(
            delivery: delivery,
            statusColor: _getStatusColor(delivery.status),
            onTap: () => _showDeliveryDetails(delivery),
          );
        },
      ),
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  final ExternalDelivery delivery;
  final Color statusColor;
  final VoidCallback onTap;

  const _DeliveryCard({
    required this.delivery,
    required this.statusColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: FrostCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(right: 14, top: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      delivery.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.store_outlined,
                          size: 13,
                          color: scheme.onSurface.withValues(alpha: 0.5),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            delivery.storeName,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurface.withValues(alpha: 0.6),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 13,
                          color: scheme.onSurface.withValues(alpha: 0.5),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            delivery.customerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                        if (delivery.modified.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Icon(
                            Icons.schedule,
                            size: 13,
                            color: scheme.onSurface.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            AppDateFormat.dateFromString(delivery.modified),
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  delivery.status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeliveryDetailsSheet extends StatefulWidget {
  final ExternalDelivery summary;
  final ScrollController scrollController;
  final Future<String> Function(String name) onAccept;
  final void Function(ExternalDeliveryDetail detail) onNavigateToDelivery;

  const _DeliveryDetailsSheet({
    required this.summary,
    required this.scrollController,
    required this.onAccept,
    required this.onNavigateToDelivery,
  });

  @override
  State<_DeliveryDetailsSheet> createState() => _DeliveryDetailsSheetState();
}

class _DeliveryDetailsSheetState extends State<_DeliveryDetailsSheet> {
  ExternalDeliveryDetail? _detail;
  bool _loadingFull = true;
  bool _uploadingProof = false;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  Future<void> _fetchDetail() async {
    try {
      final detail = await ExternalDeliveryRepository().fetchDetail(
        widget.summary.name,
      );
      if (mounted) {
        setState(() {
          _detail = detail;
          _loadingFull = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingFull = false);
    }
  }

  Future<void> _uploadProofPhotoLate(BuildContext context) async {
    final photoPath = await showDeliveryProofSheet(context);
    if (!mounted || photoPath == null) return;
    setState(() => _uploadingProof = true);
    try {
      await ExternalDeliveryRepository().uploadProofPhoto(
        orderName: widget.summary.name,
        filePath: photoPath,
      );
      await _fetchDetail();
    } finally {
      if (mounted) setState(() => _uploadingProof = false);
    }
  }

  Future<void> _clearProofPhoto() async {
    final photo = _detail?.proofPhoto;
    if (photo == null || photo.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear proof photo?'),
        content: const Text(
          'This will blank the proof_photo field on External Delivery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _uploadingProof = true);
    try {
      await ExternalDeliveryRepository().clearProofPhoto(
        orderName: widget.summary.name,
      );
      await _fetchDetail();
      if (mounted) AppToast.show(context, 'Proof photo cleared');
    } catch (e) {
      if (mounted) AppToast.show(context, e.toString());
    } finally {
      if (mounted) setState(() => _uploadingProof = false);
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'picked up':
      case 'pickedup':
        return Colors.purple;
      case 'out for delivery':
      case 'outfordelivery':
        return Colors.teal;
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Future<void> _acceptDelivery(BuildContext context) async {
    // Offline drivers can't take on work — this accept path creates a trip
    // directly via the repository, bypassing AppController.acceptOrder, so it
    // needs its own guard.
    if (!AppScope.of(context).isOnline) {
      AppToast.show(context, 'You are Offline. Go Online to accept orders.');
      return;
    }
    final navigator = Navigator.of(context);
    AppToast.show(context, 'Creating trip...');
    try {
      final tripName = await widget.onAccept(widget.summary.name);
      if (!context.mounted) return;
      navigator.pop();
      navigator.pushNamed(AppRoutes.externalDeliveryTripDetails, arguments: tripName);
    } catch (e) {
      if (!context.mounted) return;
      AppToast.show(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _detail?.status ?? widget.summary.status;
    final statusColor = _getStatusColor(status);
    final proofPhoto = _detail?.proofPhoto;
    final hasDropLocation =
        _detail?.latitude != null && _detail?.longitude != null;

    return AppBottomSheet(
      scrollController: widget.scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.summary.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_loadingFull)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),

          const SizedBox(height: 24),

          _buildSection('Store Details', [
            _buildInfoRow(
              Icons.store,
              'Store Name',
              _detail?.storeName ?? widget.summary.storeName,
            ),
            if ((_detail?.storeUrl ?? '').isNotEmpty)
              _buildInfoRow(Icons.link, 'URL', _detail!.storeUrl),
          ]),

          const SizedBox(height: 16),

          _buildSection('Customer Details', [
            _buildInfoRow(
              Icons.person,
              'Customer',
              _detail?.customerName ?? widget.summary.customerName,
            ),
            if (_detail?.contactMobile != null)
              _buildInfoRow(Icons.phone, 'Phone', _detail!.contactMobile!),
          ]),

          const SizedBox(height: 16),

          _buildSection('Pickup Location', [
            _buildInfoRow(
              Icons.trip_origin,
              'Address',
              _detail?.pickupAddress ?? 'Not available',
            ),
          ]),

          const SizedBox(height: 16),

          _buildSection('Drop Location', [
            _buildInfoRow(
              Icons.location_on,
              'Address',
              _detail?.deliveryAddress ?? widget.summary.deliveryAddress ?? 'Not available',
            ),
            if (hasDropLocation)
              _buildInfoRow(
                Icons.gps_fixed,
                'Coordinates',
                '${_detail!.latitude!.toStringAsFixed(6)}, ${_detail!.longitude!.toStringAsFixed(6)}',
              ),
          ]),

          if (proofPhoto != null && proofPhoto.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Proof of Delivery',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            buildProofPhotoWidget(context, proofPhoto),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: _clearProofPhoto,
                icon: const Icon(Icons.clear_rounded),
                label: const Text('Clear Proof Photo'),
              ),
            ),
          ] else if (status.toLowerCase() == 'delivered') ...[
            const SizedBox(height: 16),
            Text(
              'Proof of Delivery',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: _uploadingProof
                  ? const Center(child: CircularProgressIndicator())
                  : OutlinedButton.icon(
                      onPressed: () => _uploadProofPhotoLate(context),
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: const Text('Add Proof Photo'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
            ),
          ],

          const SizedBox(height: 32),

          if (status.toLowerCase() == 'pending')
            AppSheetPrimaryButton(
              label: 'Create Trip',
              icon: Icons.add_road,
              color: Colors.green,
              onPressed: () => _acceptDelivery(context),
            ),

          if (hasDropLocation && _detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: AppSheetPrimaryButton(
                label: 'Navigate to Delivery',
                icon: Icons.navigation,
                color: Colors.blue,
                onPressed: () {
                  Navigator.pop(context);
                  widget.onNavigateToDelivery(_detail!);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final nonEmptyChildren = children.where((w) => w is! SizedBox).toList();
    if (nonEmptyChildren.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: scheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.onSurface.withValues(alpha: 0.6)),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
