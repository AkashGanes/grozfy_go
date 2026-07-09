import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/context_colors.dart';
import '../../core/widgets/app_toast.dart';
import '../orders_by_location/model/external_delivery_detail.dart';
import '../orders_by_location/repository/external_delivery_repository.dart';
import 'widgets/order_timer_widget.dart';

class OrderDetailsScreen extends StatefulWidget {
  const OrderDetailsScreen({super.key, this.order});

  final DeliveryOrder? order;

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  DeliveryOrder? _currentOrder;
  ExternalDeliveryDetail? _detail;
  bool _busy = false;
  bool _loadingDetail = false;
  bool _customerExpanded = true;
  bool _storeExpanded = true;
  bool _itemsExpanded = true;

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchDetail());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _currentOrder ??= AppScope.of(context).activeOrder;
  }

  Future<void> _fetchDetail() async {
    final orderId = _currentOrder?.orderId ??
        (mounted ? AppScope.of(context).activeOrder?.orderId : null);
    if (orderId == null || orderId.isEmpty) return;
    setState(() => _loadingDetail = true);
    try {
      final detail = await ExternalDeliveryRepository().fetchDetail(
        orderId,
        resolveAddress: false,
      );
      if (mounted) setState(() { _detail = detail; _loadingDetail = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  static const Map<String, String> _reasonLabels = {
    'customer_unavailable': 'Customer Unavailable',
    'address_inaccessible': 'Address Inaccessible',
    'wrong_address': 'Wrong Address',
    'customer_refused_at_door': 'Customer Refused at Door',
    'damaged_in_transit': 'Damaged in Transit',
    'lost_in_transit': 'Lost in Transit',
    'suspected_fraud': 'Suspected Fraud',
  };

  String _reasonLabelFor(String code) =>
      _reasonLabels[code] ?? (code.isNotEmpty ? code : '');

  ({Color accent, IconData icon, String title}) _closedStatusConfig(
      BuildContext context, OrderStatus status) {
    switch (status) {
      case OrderStatus.delivered:
        return (
          accent: context.success,
          icon: Icons.check_circle_rounded,
          title: 'Order Delivered',
        );
      case OrderStatus.cancelled:
        return (
          accent: context.danger,
          icon: Icons.cancel_rounded,
          title: 'Order Cancelled',
        );
      case OrderStatus.returned:
        return (
          accent: const Color(0xFF6A1B9A),
          icon: Icons.assignment_return_rounded,
          title: 'Order Returned',
        );
      case OrderStatus.failed:
      default:
        return (
          accent: context.danger,
          icon: Icons.report_problem_rounded,
          title: 'Delivery Failed',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final DeliveryOrder? order = _currentOrder ?? app.activeOrder;

    if (order == null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  title: 'Order Details',
                  subtitle: 'No active order found',
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.of(context)
                      .pushReplacementNamed(AppRoutes.dashboard),
                  child: const Text('Back to Dashboard'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final bool isPending = order.orderStatus == OrderStatus.pending;
    final bool showNavigate =
        !isPending &&
        (order.orderStatus == OrderStatus.accepted ||
            order.orderStatus == OrderStatus.reachedPickup);
    final bool showTrackOrder =
        order.orderStatus == OrderStatus.pickedUp ||
        order.orderStatus == OrderStatus.outForDelivery;
    final bool isClosedStatus = order.orderStatus == OrderStatus.delivered ||
        order.orderStatus == OrderStatus.cancelled ||
        order.orderStatus == OrderStatus.returned ||
        order.orderStatus == OrderStatus.failed;
    // The detail fetch (_detail) hits the live per-order endpoint and is the
    // source of truth; the nav-arg `order` may carry stale/blank reason data
    // copied from a list summary, so prefer _detail whenever it has a value.
    final String effectiveReasonCode =
        (_detail?.failureReasonCode.isNotEmpty ?? false)
            ? _detail!.failureReasonCode
            : order.failureReasonCode;
    final String effectiveNotes = (_detail?.deliveryNotes.isNotEmpty ?? false)
        ? _detail!.deliveryNotes
        : order.deliveryNotes;
    final DateTime? effectiveCompletedAt =
        DateTime.tryParse(_detail?.modified ?? '') ?? order.completedAt;
    final String reasonLabel = _reasonLabelFor(effectiveReasonCode);
    final bool hasNote =
        effectiveNotes.isNotEmpty && effectiveNotes != reasonLabel;
    final closedConfig = _closedStatusConfig(context, order.orderStatus);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              title: 'Order ${order.orderId}',
              subtitle: isPending
                  ? 'Review and accept this order'
                  : isClosedStatus
                      ? 'Order details'
                      : 'Active order details',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  if (isClosedStatus) ...[
                    _StatusBanner(
                      accent: closedConfig.accent,
                      icon: closedConfig.icon,
                      title: closedConfig.title,
                      completedAt: effectiveCompletedAt,
                    ),
                    if (reasonLabel.isNotEmpty || hasNote) ...[
                      const SizedBox(height: 6),
                      _ReasonNotesPanel(
                        reasonLabel: reasonLabel,
                        notes: effectiveNotes,
                        hasNote: hasNote,
                        accent: closedConfig.accent,
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],
                  _SectionCard(
                    expanded: _customerExpanded,
                    onToggle: () => setState(
                        () => _customerExpanded = !_customerExpanded),
                    headerBg: context.infoContainer,
                    headerIcon: Icons.person_rounded,
                    headerIconColor: context.info,
                    title: 'Customer Details',
                    cardBg: context.cardColor,
                    cardBorder: context.borderSubtle,
                    textPrimary: context.textPrimary,
                    body: Column(
                      children: _withRowDividers([
                        _InfoRow(
                          label: 'Name',
                          value: order.customerName,
                          textPrimary: context.textPrimary,
                          textSecondary: context.textSecondary,
                          icon: Icons.person_outline_rounded,
                          iconColor: context.info,
                        ),
                        _InfoRow(
                          label: 'Phone',
                          value: order.customerPhone,
                          textPrimary: context.textPrimary,
                          textSecondary: context.textSecondary,
                          icon: Icons.call_outlined,
                          iconColor: context.info,
                          action: order.customerPhone.isNotEmpty
                              ? _IconAction(
                                  icon: Icons.phone_rounded,
                                  color: context.info,
                                  onTap: () => _launchUri(
                                      'tel:${order.customerPhone}'),
                                )
                              : null,
                        ),
                        _InfoRow(
                          label: 'Address',
                          value: order.deliveryAddress,
                          textPrimary: context.textPrimary,
                          textSecondary: context.textSecondary,
                          icon: Icons.location_on_outlined,
                          iconColor: context.info,
                        ),
                        _InfoRow(
                          label: 'Order ID',
                          value: order.orderId,
                          textPrimary: context.textPrimary,
                          textSecondary: context.textSecondary,
                          icon: Icons.confirmation_number_outlined,
                          iconColor: context.info,
                        ),
                        _InfoRow(
                          label: 'Status',
                          value: order.orderStatus.label,
                          textPrimary: context.textPrimary,
                          textSecondary: context.textSecondary,
                          icon: Icons.flag_outlined,
                          iconColor: context.info,
                          customValue: _StatusPill(
                              label: order.orderStatus.label),
                        ),
                        if (order.deliveryInstructions.isNotEmpty)
                          _InfoRow(
                            label: 'Instructions',
                            value: order.deliveryInstructions,
                            textPrimary: context.textPrimary,
                            textSecondary: context.textSecondary,
                            icon: Icons.notes_rounded,
                            iconColor: context.info,
                          ),
                      ], context.borderSubtle),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    expanded: _storeExpanded,
                    onToggle: () =>
                        setState(() => _storeExpanded = !_storeExpanded),
                    headerBg: context.successContainer,
                    headerIcon: Icons.store_rounded,
                    headerIconColor: context.success,
                    title: 'Store Details',
                    cardBg: context.cardColor,
                    cardBorder: context.borderSubtle,
                    textPrimary: context.textPrimary,
                    body: Column(
                      children: _withRowDividers([
                        _InfoRow(
                          label: 'Store Name',
                          value: order.storeName,
                          textPrimary: context.textPrimary,
                          textSecondary: context.textSecondary,
                          icon: Icons.storefront_outlined,
                          iconColor: context.success,
                        ),
                        _InfoRow(
                          label: 'Store ID',
                          value: order.storeId,
                          textPrimary: context.textPrimary,
                          textSecondary: context.textSecondary,
                          icon: Icons.tag_rounded,
                          iconColor: context.success,
                          action: order.storeId.isNotEmpty
                              ? _IconAction(
                                  icon: Icons.public_rounded,
                                  color: context.info,
                                  onTap: () {
                                    final uri = order.storeId.startsWith('http')
                                        ? order.storeId
                                        : 'https://${order.storeId}';
                                    _launchUri(uri);
                                  },
                                )
                              : null,
                        ),
                        _InfoRow(
                          label: 'Contact',
                          value: order.storeContact,
                          textPrimary: context.textPrimary,
                          textSecondary: context.textSecondary,
                          icon: Icons.call_outlined,
                          iconColor: context.success,
                          action: order.storeContact.isNotEmpty
                              ? _IconAction(
                                  icon: Icons.phone_rounded,
                                  color: context.info,
                                  onTap: () => _launchUri(
                                      'tel:${order.storeContact}'),
                                )
                              : null,
                        ),
                        _InfoRow(
                          label: 'Address',
                          value: order.storeAddress,
                          textPrimary: context.textPrimary,
                          textSecondary: context.textSecondary,
                          icon: Icons.location_on_outlined,
                          iconColor: context.success,
                          action: (order.latitude != 0 && order.longitude != 0)
                              ? _IconAction(
                                  icon: Icons.location_on_rounded,
                                  color: const Color(0xFFE8384F),
                                  onTap: () => _launchUri(
                                    'https://www.google.com/maps/search/?api=1&query=${order.latitude},${order.longitude}',
                                  ),
                                )
                              : null,
                        ),
                        _InfoRow(
                          label: 'Distance',
                          value: '${order.distanceKm.toStringAsFixed(2)} km',
                          textPrimary: context.textPrimary,
                          textSecondary: context.textSecondary,
                          icon: Icons.route_outlined,
                          iconColor: context.success,
                        ),
                        _InfoRow(
                          label: 'Earnings',
                          value:
                              'Rs. ${order.estimatedEarnings.toStringAsFixed(0)}',
                          textPrimary: context.textPrimary,
                          textSecondary: context.textSecondary,
                          icon: Icons.payments_outlined,
                          iconColor: context.success,
                        ),
                      ], context.borderSubtle),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    expanded: _itemsExpanded,
                    onToggle: () =>
                        setState(() => _itemsExpanded = !_itemsExpanded),
                    headerBg: context.isDark
                        ? const Color(0xFF2D2148)
                        : const Color(0xFFEFE9FE),
                    headerIcon: Icons.inventory_2_rounded,
                    headerIconColor: const Color(0xFF7C3AED),
                    title: 'Order Items',
                    cardBg: context.cardColor,
                    cardBorder: context.borderSubtle,
                    textPrimary: context.textPrimary,
                    body: _loadingDetail && _detail == null
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          )
                        : _buildItemsBody(context, order),
                  ),
                  if (app.isOrderTimerRunning) ...[
                    const SizedBox(height: 12),
                    const Center(child: OrderTimerWidget()),
                  ],
                ],
              ),
            ),
            _BottomActions(
              isPending: isPending,
              showNavigate: showNavigate,
              showTrackOrder: showTrackOrder,
              isClosedStatus: isClosedStatus,
              busy: _busy,
              customerPhone: order.customerPhone,
              storePhone: order.storeContact,
              onAccept: () => _acceptPendingOrder(context, order),
              onReject: () => _rejectPendingOrder(context, order),
              onCallCustomer: () => _launchUri('tel:${order.customerPhone}'),
              onCallStore: () => _launchUri('tel:${order.storeContact}'),
              onBackToOrders: () => Navigator.of(context).maybePop(),
              onNavigate: () =>
                  Navigator.of(context).pushNamed(AppRoutes.navigation),
              onTrack: () =>
                  Navigator.of(context).pushNamed(AppRoutes.orderTracking),
              cardBg: context.cardColor,
              isDark: context.isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsBody(BuildContext context, DeliveryOrder order) {
    final detail = _detail;
    final paymentMethod = detail?.paymentMethod ?? detail?.paymentMode ?? order.paymentMode;
    final isCod = paymentMethod.toUpperCase() == 'COD';
    final codAmount = detail?.codAmountToCollect;
    final items = detail?.items ?? [];
    final hasItems = items.isNotEmpty;
    // Compute total from items if available; fall back to codAmountToCollect
    final double itemsTotal = items.fold(
      0,
      (sum, i) => sum + ((i.amount ?? (i.rate != null ? i.rate! * i.qty : 0))),
    );
    final double displayTotal = itemsTotal > 0
        ? itemsTotal
        : (codAmount != null && codAmount > 0 ? codAmount : order.totalAmount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasItems) ...[
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item.itemName} x${item.qty.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 14,
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                  if ((item.amount ?? item.rate) != null)
                    Text(
                      'Rs. ${(item.amount ?? (item.rate! * item.qty)).toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Divider(height: 1, color: context.borderSubtle),
          const SizedBox(height: 10),
        ] else if (!_loadingDetail) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'No items found',
              style: TextStyle(fontSize: 13, color: context.textSecondary),
            ),
          ),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isCod && codAmount != null && codAmount > 0
                  ? 'COD Amount'
                  : 'Total Amount',
              style: TextStyle(
                fontSize: 14,
                color: context.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              displayTotal > 0
                  ? 'Rs. ${displayTotal.toStringAsFixed(0)}'
                  : '—',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isCod && displayTotal > 0
                    ? context.warning
                    : context.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Payment Mode',
              style: TextStyle(
                fontSize: 14,
                color: context.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (isCod)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: context.warningContainer,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: context.warning),
                ),
                child: Text(
                  'COD',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: context.warning,
                  ),
                ),
              )
            else
              Text(
                paymentMethod.isEmpty ? '—' : paymentMethod,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _launchUri(String uri) async {
    final parsed = Uri.parse(uri);
    if (await canLaunchUrl(parsed)) {
      await launchUrl(parsed, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _acceptPendingOrder(
    BuildContext context,
    DeliveryOrder order,
  ) async {
    final app = AppScope.of(context);
    setState(() => _busy = true);
    final error = await app.acceptOrder(order.orderId);
    if (!context.mounted) {
      return;
    }
    setState(() => _busy = false);
    if (error != null) {
      AppToast.show(context, error);
      return;
    }
    setState(() {
      _currentOrder = order.copyWith(
        orderStatus: OrderStatus.accepted,
        assignmentStatus: OrderAssignmentStatus.assigned,
      );
    });

    if (!context.mounted) return;
    AppToast.show(context, 'Order accepted successfully!');
    Navigator.of(context).pushNamed(AppRoutes.navigation);
  }

  Future<void> _rejectPendingOrder(
    BuildContext context,
    DeliveryOrder order,
  ) async {
    final app = AppScope.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    final error = await app.rejectOrder(order.orderId);
    if (!context.mounted) {
      return;
    }
    setState(() => _busy = false);
    if (error != null) {
      AppToast.show(context, error);
      return;
    }
    AppToast.show(context, 'Order rejected');
    navigator.pushNamedAndRemoveUntil(AppRoutes.orderListing, (route) => false);
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final Color textPrimary = context.textPrimary;
    final Color textSecondary = context.textSecondary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _BackChip(onTap: onBack),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BackChip extends StatelessWidget {
  const _BackChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color cardBg = context.cardColor;
    final Color cardBorder = context.borderSubtle;
    final Color iconColor = context.iconPrimary;

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cardBorder),
          ),
          child: Icon(Icons.arrow_back_rounded, size: 22, color: iconColor),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});
  final String label;

  Color _bg(BuildContext context, String s) {
    final lower = s.toLowerCase();
    if (lower.contains('deliver')) return context.successContainer;
    if (lower.contains('cancel') || lower.contains('reject') || lower.contains('fail')) {
      return context.dangerContainer;
    }
    if (lower.contains('return')) {
      return context.isDark ? const Color(0xFF2D2148) : const Color(0xFFF4EBFB);
    }
    if (lower.contains('pick') || lower.contains('out')) {
      return context.infoContainer;
    }
    return context.warningContainer;
  }

  Color _fg(BuildContext context, String s) {
    final lower = s.toLowerCase();
    if (lower.contains('deliver')) return context.success;
    if (lower.contains('cancel') || lower.contains('reject') || lower.contains('fail')) {
      return context.danger;
    }
    if (lower.contains('return')) {
      return context.isDark ? const Color(0xFFB197E0) : const Color(0xFF6A1B9A);
    }
    if (lower.contains('pick') || lower.contains('out')) {
      return context.info;
    }
    return context.warning;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _bg(context, label),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: _fg(context, label),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.expanded,
    required this.onToggle,
    required this.headerBg,
    required this.headerIcon,
    required this.headerIconColor,
    required this.title,
    required this.body,
    required this.cardBg,
    required this.cardBorder,
    required this.textPrimary,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final Color headerBg;
  final IconData headerIcon;
  final Color headerIconColor;
  final String title;
  final Widget body;
  final Color cardBg;
  final Color cardBorder;
  final Color textPrimary;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: context.shadowColor,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: EdgeInsets.fromLTRB(14, 14, 14, expanded ? 10 : 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: headerBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(headerIcon, color: headerIconColor, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: textPrimary,
                      ),
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: textPrimary.withValues(alpha: 0.45),
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            Divider(height: 1, color: cardBorder),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: body,
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.textPrimary,
    required this.textSecondary,
    this.icon,
    this.iconColor,
    this.action,
    this.customValue,
  });

  final String label;
  final String value;
  final Color textPrimary;
  final Color textSecondary;
  final IconData? icon;
  final Color? iconColor;
  final Widget? action;
  final Widget? customValue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: (iconColor ?? textSecondary).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 15, color: iconColor ?? textSecondary),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                customValue ??
                    Text(
                      value.isEmpty ? '—' : value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w400,
                        color: textSecondary,
                      ),
                    ),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 8),
            action!,
          ],
        ],
      ),
    );
  }
}

List<Widget> _withRowDividers(List<Widget> rows, Color color) {
  final result = <Widget>[];
  for (var i = 0; i < rows.length; i++) {
    result.add(rows[i]);
    if (i != rows.length - 1) {
      result.add(Divider(height: 1, thickness: 1, color: color));
    }
  }
  return result;
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Icon(icon, color: color, size: 16),
        ),
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.isPending,
    required this.showNavigate,
    required this.showTrackOrder,
    required this.isClosedStatus,
    required this.busy,
    required this.customerPhone,
    required this.storePhone,
    required this.onAccept,
    required this.onReject,
    required this.onCallCustomer,
    required this.onCallStore,
    required this.onBackToOrders,
    required this.onNavigate,
    required this.onTrack,
    required this.cardBg,
    required this.isDark,
  });

  final bool isPending;
  final bool showNavigate;
  final bool showTrackOrder;
  final bool isClosedStatus;
  final bool busy;
  final String customerPhone;
  final String storePhone;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onCallCustomer;
  final VoidCallback onCallStore;
  final VoidCallback onBackToOrders;
  final VoidCallback onNavigate;
  final VoidCallback onTrack;
  final Color cardBg;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bool hasCustomer = customerPhone.trim().isNotEmpty;
    final bool hasStore = storePhone.trim().isNotEmpty;
    final bool showQuickRow = hasCustomer || hasStore;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: cardBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.06),
            blurRadius: 14,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showQuickRow) ...[
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: hasCustomer ? onCallCustomer : null,
                      icon: const Icon(Icons.person_rounded, size: 18),
                      label: const Text('Customer'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.info,
                        side: BorderSide(
                          color: context.info.withValues(alpha: 0.4),
                          width: 1.4,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: hasStore ? onCallStore : null,
                      icon: const Icon(Icons.store_rounded, size: 18),
                      label: const Text('Store'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.success,
                        side: BorderSide(
                          color: context.success.withValues(alpha: 0.4),
                          width: 1.4,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (isPending) ...[
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : onReject,
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('Reject Order'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.danger,
                        side: BorderSide(
                          color: context.danger.withValues(alpha: 0.4),
                          width: 1.4,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: busy ? null : onAccept,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1F5FE8),
                        disabledBackgroundColor:
                            const Color(0xFF1F5FE8).withValues(alpha: 0.7),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      child: busy
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(
                                            Colors.white),
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text('Accepting...'),
                              ],
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle_rounded, size: 20),
                                SizedBox(width: 8),
                                Text('Accept Order'),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            if (showNavigate)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: onNavigate,
                  icon: const Icon(Icons.navigation_rounded, size: 20),
                  label: const Text('Navigate'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F5FE8),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            if (showTrackOrder) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: onTrack,
                  icon: const Icon(Icons.track_changes_rounded, size: 20),
                  label: const Text('Track Order'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1F5FE8),
                    side: const BorderSide(
                      color: Color(0xFF1F5FE8),
                      width: 1.4,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
            if (!showNavigate && !showTrackOrder) ...[
              if (isClosedStatus) ...[
                Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 15,
                      color: context.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'This order is closed and no further action is needed.',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: context.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: onBackToOrders,
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Back to Orders'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F5FE8),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.accent,
    required this.icon,
    required this.title,
    required this.completedAt,
  });

  final Color accent;
  final IconData icon;
  final String title;
  final DateTime? completedAt;

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatTimestamp(DateTime dt) {
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${_months[dt.month - 1]} ${dt.year} • $hour12:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final Color textSecondary = context.textSecondary;
    final Color textPrimary = context.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: accent, size: 52),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: textPrimary,
            ),
          ),
          if (completedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              _formatTimestamp(completedAt!),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReasonNotesPanel extends StatelessWidget {
  const _ReasonNotesPanel({
    required this.reasonLabel,
    required this.notes,
    required this.hasNote,
    required this.accent,
  });

  final String reasonLabel;
  final String notes;
  final bool hasNote;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final Color textPrimary = context.textPrimary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: context.isDark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.3), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (reasonLabel.isNotEmpty)
            _row(Icons.info_rounded, 'Reason', reasonLabel, textPrimary),
          if (hasNote) ...[
            if (reasonLabel.isNotEmpty) const SizedBox(height: 12),
            _row(Icons.sticky_note_2_rounded, 'Notes', notes, textPrimary),
          ],
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value, Color textPrimary) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 15, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w400,
                  color: textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

