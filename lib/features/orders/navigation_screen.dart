import 'package:flutter/material.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/context_colors.dart';
import '../../core/utils/maps_launcher.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/app_toast.dart';
import '../orders_by_location/repository/external_delivery_repository.dart';
import '../orders_by_location/ui/cod_collection_sheet.dart';
import '../orders_by_location/ui/delivery_otp_sheet.dart';
import '../orders_by_location/ui/delivery_proof_sheet.dart';
import '../orders_by_location/ui/failed_delivery_bottom_sheet.dart';
import 'delivery_tracking_screen.dart';

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  bool _syncing = false;
  bool _codCashConfirmed = false;
  ({String mode, String? upiRef})? _codResult;

  OrderProgressStatus _nextStatus(OrderProgressStatus s) {
    if (s == OrderStatus.accepted) return OrderStatus.reachedPickup;
    if (s == OrderStatus.reachedPickup) return OrderStatus.pickedUp;
    if (s == OrderStatus.pickedUp) return OrderStatus.outForDelivery;
    if (s == OrderStatus.outForDelivery) return OrderStatus.delivered;
    return s;
  }

  String _actionLabel(OrderProgressStatus s) {
    if (s == OrderStatus.accepted) return 'Mark Reached Pickup';
    if (s == OrderStatus.reachedPickup) return 'Mark Picked Up';
    if (s == OrderStatus.pickedUp) return 'Start Out for Delivery';
    return '';
  }

  Future<void> _advanceStatus(BuildContext context, DeliveryOrder order) async {
    final app = AppScope.of(context);
    final next = _nextStatus(order.orderStatus);
    if (next == order.orderStatus || _syncing) return;
    setState(() => _syncing = true);

    if (next == OrderStatus.delivered) {
      final photoPath = await showDeliveryProofSheet(context);
      if (!mounted) { setState(() => _syncing = false); return; }
      if (photoPath != null) {
        await ExternalDeliveryRepository().uploadProofPhoto(
          orderName: order.orderId, filePath: photoPath,
        );
        if (!mounted) { setState(() => _syncing = false); return; }
      }
      if (_codCashConfirmed && _codResult != null) {
        if (_codResult!.mode != 'Not Collected') {
          try {
            await ExternalDeliveryRepository().markDeliveredWithCod(
              order.orderId,
              codCollectionMode: _codResult!.mode,
              codUpiReference: _codResult!.upiRef,
            );
          } catch (e) {
            if (!context.mounted) return;
            AppToast.show(
              context,
              'Cash collected but not recorded on the server: '
              '${e.toString().replaceFirst('Exception: ', '')}',
            );
          }
          if (!mounted) return;
        }
      } else {
        bool isCod = false;
        double codAmount = 0;
        try {
          final detail = await ExternalDeliveryRepository().fetchDetail(
            order.orderId, resolveAddress: false,
          );
          isCod = detail.isCod;
          codAmount = detail.codAmountToCollect ?? 0;
        } catch (_) {}
        if (!mounted) { setState(() => _syncing = false); return; }
        if (isCod && codAmount > 0) {
          final codResult = await showCodCollectionSheet(context, amountToCollect: codAmount);
          if (!mounted) { setState(() => _syncing = false); return; }
          if (codResult == null) { setState(() => _syncing = false); return; }
          if (codResult.mode != 'Not Collected') {
            try {
              await ExternalDeliveryRepository().markDeliveredWithCod(
                order.orderId,
                codCollectionMode: codResult.mode,
                codUpiReference: codResult.upiRef,
              );
            } catch (e) {
              if (!context.mounted) return;
              AppToast.show(
                context,
                'Cash collected but not recorded on the server: '
                '${e.toString().replaceFirst('Exception: ', '')}',
              );
            }
            if (!mounted) return;
          }
        }
      }

      // Customer-facing OTP gate — required before the order can be
      // committed as Delivered.
      if (!mounted) { setState(() => _syncing = false); return; }
      final bool? otpVerified = await showDeliveryOtpSheet(
        context,
        repository: ExternalDeliveryRepository(),
        externalDelivery: order.orderId,
      );
      if (!mounted) return;
      if (otpVerified != true) {
        setState(() => _syncing = false);
        return;
      }
    }

    final error = await app.updateOrderStatus(next);
    if (next == OrderStatus.delivered || next == OrderStatus.cancelled) {
      app.stopOrderTimer();
    }
    if (!context.mounted) return;
    setState(() => _syncing = false);
    if (error != null) { AppToast.show(context, error); return; }
    if (next == OrderStatus.delivered) {
      AppToast.show(context, 'Order delivered and earnings updated');
      Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.dashboard, (r) => false);
    } else {
      Navigator.of(context).pushNamed(AppRoutes.orderStatus);
    }
  }

  Future<void> _handleCodCashCollection(BuildContext context, DeliveryOrder order) async {
    if (_syncing) return;
    setState(() => _syncing = true);
    double codAmount = 0;
    try {
      final detail = await ExternalDeliveryRepository().fetchDetail(
        order.orderId, resolveAddress: false,
      );
      codAmount = detail.codAmountToCollect ?? 0;
    } catch (_) {}
    if (!mounted) { setState(() => _syncing = false); return; }
    final result = await showCodCollectionSheet(context, amountToCollect: codAmount);
    if (!mounted) { setState(() => _syncing = false); return; }
    if (result == null) { setState(() => _syncing = false); return; }
    setState(() { _syncing = false; _codCashConfirmed = true; _codResult = result; });
  }

  Future<void> _onMarkFailed(BuildContext context, DeliveryOrder order) async {
    if (_syncing) return;
    final isCod = order.paymentMode.toUpperCase() == 'COD';
    final result = await showFailedDeliverySheet(context, isCod: isCod);
    if (result == null || !mounted) return;
    setState(() => _syncing = true);
    final reason = result.notes.isNotEmpty ? result.notes : result.reason;
    final tripId = AppScope.of(context).tripIdForOrder(order.orderId);
    try {
      if (tripId != null && tripId.isNotEmpty) {
        await ExternalDeliveryRepository().processFailedDeliveryReturnByIds(
          tripId: tripId,
          deliveryId: order.orderId,
          reason: reason,
          reasonCode: result.reasonCode,
          photoPath: result.photoPath,
        );
      } else {
        await ExternalDeliveryRepository().markOrderFailed(
          orderName: order.orderId,
          reason: reason,
          reasonCode: result.reasonCode,
          photoPath: result.photoPath,
        );
      }
    } catch (_) {}
    if (!mounted) { setState(() => _syncing = false); return; }
    final app = AppScope.of(context);
    final error = await app.updateOrderStatus(OrderStatus.failed);
    app.stopOrderTimer();
    if (!context.mounted) return;
    setState(() => _syncing = false);
    if (error != null) { AppToast.show(context, error); return; }
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.dashboard, (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final order = app.activeOrder;

    if (order == null) {
      return AppShell(
        title: app.t('navigation'),
        subtitle: app.t('no_active_route'),
        child: ElevatedButton(
          onPressed: () =>
              Navigator.of(context).pushReplacementNamed(AppRoutes.dashboard),
          child: Text(app.t('back_to_dashboard')),
        ),
      );
    }

    return AppShell(
      title: app.t('navigation'),
      subtitle: app.t('route_summary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FrostCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.route_rounded, color: Colors.deepOrange),
                    const SizedBox(width: 8),
                    Text(
                      app.t('delivery_route'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _StepTile(
                  icon: Icons.store_rounded,
                  iconColor: Colors.blue,
                  title: app.t('pickup_store'),
                  subtitle: order.pickup,
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Icon(
                    Icons.arrow_downward_rounded,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(height: 12),
                _StepTile(
                  icon: Icons.location_on_rounded,
                  iconColor: Colors.red,
                  title: app.t('delivery_drop'),
                  subtitle: order.drop.isNotEmpty
                      ? order.drop
                      : order.deliveryAddress,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _StatChip(
                        icon: Icons.straighten_rounded,
                        label: 'Distance',
                        value: '${order.distanceKm.toStringAsFixed(1)} km',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatChip(
                        icon: Icons.sell_rounded,
                        label: 'Earnings',
                        value:
                            'Rs. ${order.estimatedEarnings.toStringAsFixed(0)}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _InfoLine(
                  icon: Icons.pin_drop_rounded,
                  label: 'Coordinates',
                  value:
                      '${order.latitude.toStringAsFixed(5)}, ${order.longitude.toStringAsFixed(5)}',
                ),
                const SizedBox(height: 8),
                _InfoLine(
                  icon: Icons.receipt_long_rounded,
                  label: 'Order',
                  value: order.orderId,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => launchGoogleMapsNavigation(
              context,
              lat: order.latitude,
              lng: order.longitude,
            ),
            icon: const Icon(Icons.navigation_rounded),
            label: Text(app.t('open_google_maps')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DeliveryTrackingScreen(
                    deliveryName: order.orderId,
                    customerName: order.customerName,
                    storeName: order.storeName,
                    contactNumber: order.customerPhone.isNotEmpty
                        ? order.customerPhone
                        : order.contactNumber,
                    dropAddress: order.deliveryAddress,
                    dropLat: order.latitude,
                    dropLng: order.longitude,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.map_rounded),
            label: Text(app.t('use_inapp_nav')),
          ),
          const SizedBox(height: 12),
          if (order.orderStatus == OrderStatus.outForDelivery)
            order.paymentMode.toUpperCase() == 'COD' && !_codCashConfirmed
                ? ElevatedButton.icon(
                    onPressed: _syncing
                        ? null
                        : () => _handleCodCashCollection(context, order),
                    icon: _syncing
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Icon(Icons.account_balance_wallet_rounded),
                    label: const Text('Confirm COD Cash'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 52),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _syncing ? null : () => _advanceStatus(context, order),
                          icon: _syncing
                              ? const SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                )
                              : const Icon(Icons.check_circle_outline),
                          label: const Text('Mark Delivered'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _syncing ? null : () => _onMarkFailed(context, order),
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('Mark Failed'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.danger,
                            side: BorderSide(color: context.danger),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  )
          else if (_actionLabel(order.orderStatus).isNotEmpty)
            ElevatedButton(
              onPressed: _syncing ? null : () => _advanceStatus(context, order),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _syncing
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : Text(_actionLabel(order.orderStatus)),
            ),
        ],
      ),
    );
  }

}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.6),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.deepOrange),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: scheme.onSurface.withValues(alpha: 0.4)),
        const SizedBox(width: 8),
        SizedBox(
          width: 86,
          child: Text(
            label,
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
