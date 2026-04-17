import 'package:flutter/material.dart';
import '../../core/models/app_models.dart';
import '../../core/services/api_service.dart';
import '../../core/widgets/app_shell.dart';

class DeliveryListScreen extends StatefulWidget {
  const DeliveryListScreen({super.key});

  @override
  State<DeliveryListScreen> createState() => _DeliveryListScreenState();
}

class _DeliveryListScreenState extends State<DeliveryListScreen> {
  final ApiService _apiService = ApiService();

  List<ExternalDeliveryOrder> _deliveries = [];
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
      debugPrint('[DeliveryList] Fetching deliveries...');
      final deliveries = await _apiService.getExternalDeliveries();
      debugPrint('[DeliveryList] Got ${deliveries.length} deliveries');
      if (mounted) {
        setState(() {
          _deliveries = deliveries;
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    } catch (e) {
      debugPrint('[DeliveryList] Error: $e');
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
    setState(() {
      _isRefreshing = true;
    });
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

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Icons.schedule;
      case 'accepted':
        return Icons.check_circle_outline;
      case 'picked up':
      case 'pickedup':
        return Icons.inventory_2;
      case 'out for delivery':
      case 'outfordelivery':
        return Icons.local_shipping;
      case 'delivered':
        return Icons.done_all;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }

  void _showDeliveryDetails(ExternalDeliveryOrder delivery) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _DeliveryDetailsSheet(
          delivery: delivery,
          scrollController: scrollController,
          onStatusUpdate: (name, status) async {
            return await _apiService.updateDeliveryStatus(name, status);
          },
          onNavigateToDelivery: () {
            if (!delivery.hasDropLocation) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('No GPS coordinates for delivery location'),
                ),
              );
              return;
            }

            final dropLat = delivery.dropLat!;
            final dropLng = delivery.dropLng!;

            Navigator.of(context).pushNamed(
              '/delivery-tracking',
              arguments: {
                'name': delivery.name,
                'customerName': delivery.customerName,
                'storeName': delivery.storeName,
                'contactNumber': delivery.contactNumber ?? '',
                'dropAddress': delivery.dropAddress ?? '',
                'pickupLat': delivery.pickupLat,
                'pickupLng': delivery.pickupLng,
                'dropLat': dropLat,
                'dropLng': dropLng,
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
      child: Column(children: [Expanded(child: _buildContent())]),
    );
  }

  Widget _buildContent() {
    if (_isLoading && !_isRefreshing) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _deliveries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _fetchDeliveries,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_deliveries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No deliveries available',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Pull down to refresh',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshDeliveries,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _deliveries.length,
        itemBuilder: (context, index) {
          final delivery = _deliveries[index];
          return _DeliveryCard(
            delivery: delivery,
            statusColor: _getStatusColor(delivery.status),
            statusIcon: _getStatusIcon(delivery.status),
            onTap: () => _showDeliveryDetails(delivery),
          );
        },
      ),
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  final ExternalDeliveryOrder delivery;
  final Color statusColor;
  final IconData statusIcon;
  final VoidCallback onTap;

  const _DeliveryCard({
    required this.delivery,
    required this.statusColor,
    required this.statusIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(statusIcon, color: statusColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          delivery.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          delivery.storeName,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
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
                      delivery.status,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.person, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      delivery.customerName,
                      style: TextStyle(color: Colors.grey[700]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.location_on,
                    size: 16,
                    color: delivery.hasDropLocation
                        ? Colors.green
                        : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      delivery.dropAddress ?? 'No drop address',
                      style: TextStyle(
                        color: delivery.hasDropLocation
                            ? Colors.grey[700]
                            : Colors.grey,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (delivery.hasDropLocation)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.navigation, size: 12, color: Colors.green),
                          SizedBox(width: 2),
                          Text(
                            'GPS',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeliveryDetailsSheet extends StatelessWidget {
  final ExternalDeliveryOrder delivery;
  final ScrollController scrollController;
  final Future<bool> Function(String name, String status) onStatusUpdate;
  final VoidCallback onNavigateToDelivery;

  const _DeliveryDetailsSheet({
    required this.delivery,
    required this.scrollController,
    required this.onStatusUpdate,
    required this.onNavigateToDelivery,
  });

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

  void _navigateToDelivery(BuildContext context) {
    Navigator.pop(context);
    onNavigateToDelivery();
  }

  Future<void> _acceptDelivery(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    scaffoldMessenger.showSnackBar(
      SnackBar(content: Text('Accepting delivery ${delivery.name}...')),
    );

    final success = await onStatusUpdate(delivery.name, 'Accepted');

    if (!context.mounted) return;

    if (success) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Delivery ${delivery.name} accepted!')),
      );
      navigator.pop();
    } else {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Failed to accept delivery. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(delivery.status);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        controller: scrollController,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          delivery.name,
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
                            delivery.status,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () {}, icon: const Icon(Icons.share)),
                ],
              ),

              const SizedBox(height: 24),

              _buildSection('Store Details', [
                _buildInfoRow(Icons.store, 'Store Name', delivery.storeName),
                if (delivery.storeUrl.isNotEmpty)
                  _buildInfoRow(Icons.link, 'URL', delivery.storeUrl),
              ]),

              const SizedBox(height: 16),

              _buildSection('Customer Details', [
                _buildInfoRow(Icons.person, 'Customer', delivery.customerName),
                if (delivery.contactNumber != null)
                  _buildInfoRow(Icons.phone, 'Phone', delivery.contactNumber!),
              ]),

              const SizedBox(height: 16),

              _buildSection('Pickup Location', [
                _buildInfoRow(
                  Icons.trip_origin,
                  'Address',
                  delivery.pickupAddress ?? 'Not available',
                ),
                if (delivery.hasPickupLocation)
                  _buildInfoRow(
                    Icons.gps_fixed,
                    'Coordinates',
                    '${delivery.pickupLat!.toStringAsFixed(6)}, ${delivery.pickupLng!.toStringAsFixed(6)}',
                  ),
              ]),

              const SizedBox(height: 16),

              _buildSection('Drop Location', [
                _buildInfoRow(
                  Icons.location_on,
                  'Address',
                  delivery.dropAddress ?? 'Not available',
                ),
                if (delivery.hasDropLocation)
                  _buildInfoRow(
                    Icons.gps_fixed,
                    'Coordinates',
                    '${delivery.dropLat!.toStringAsFixed(6)}, ${delivery.dropLng!.toStringAsFixed(6)}',
                  ),
              ]),

              const SizedBox(height: 16),

              if (delivery.creation != null || delivery.modified != null)
                _buildSection('Timeline', [
                  if (delivery.creation != null)
                    _buildInfoRow(
                      Icons.access_time,
                      'Created',
                      _formatDate(delivery.creation!),
                    ),
                  if (delivery.modified != null)
                    _buildInfoRow(
                      Icons.update,
                      'Last Updated',
                      _formatDate(delivery.modified!),
                    ),
                ]),

              const SizedBox(height: 32),

              if (delivery.status.toLowerCase() == 'pending')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _acceptDelivery(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Accept Delivery',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

              if (delivery.hasDropLocation)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _navigateToDelivery(context),
                      icon: const Icon(Icons.navigation),
                      label: const Text('Navigate to Delivery'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    final nonEmptyChildren = children.where((w) => w is! SizedBox).toList();
    if (nonEmptyChildren.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: Colors.grey[50],
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
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

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';

    return '${date.day}/${date.month}/${date.year}';
  }
}
