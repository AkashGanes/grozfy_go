import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/widgets/app_toast.dart';
import 'widgets/order_timer_widget.dart';

class OrderDetailsScreen extends StatefulWidget {
  const OrderDetailsScreen({super.key, this.order});

  final DeliveryOrder? order;

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  DeliveryOrder? _currentOrder;
  bool _busy = false;
  bool _customerExpanded = true;
  bool _storeExpanded = true;
  bool _itemsExpanded = true;

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _currentOrder ??= AppScope.of(context).activeOrder;
  }

  bool _isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
  Color _pageBg(BuildContext c) =>
      _isDark(c) ? const Color(0xFF12141C) : const Color(0xFFF7F9FC);
  Color _cardBg(BuildContext c) =>
      _isDark(c) ? const Color(0xFF1B1E2A) : Colors.white;
  Color _cardBorder(BuildContext c) =>
      _isDark(c) ? const Color(0xFF2A2F3D) : const Color(0xFFE7EBF0);
  Color _textPrimary(BuildContext c) =>
      _isDark(c) ? const Color(0xFFF2F4F7) : const Color(0xFF101828);
  Color _textSecondary(BuildContext c) =>
      _isDark(c) ? const Color(0xFFA4ABB8) : const Color(0xFF667085);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final DeliveryOrder? order = _currentOrder ?? app.activeOrder;

    if (order == null) {
      return Scaffold(
        backgroundColor: _pageBg(context),
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
        order.orderStatus == OrderStatus.outForDelivery ||
        order.orderStatus == OrderStatus.delivered;

    return Scaffold(
      backgroundColor: _pageBg(context),
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              title: 'Order ${order.orderId}',
              subtitle: isPending
                  ? 'Review and accept this order'
                  : 'Active order details',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _SectionCard(
                    expanded: _customerExpanded,
                    onToggle: () => setState(
                        () => _customerExpanded = !_customerExpanded),
                    headerBg: _isDark(context)
                        ? const Color(0xFF1A2C4F)
                        : const Color(0xFFE5EEFB),
                    headerIcon: Icons.person_rounded,
                    headerIconColor: const Color(0xFF2D6CDF),
                    title: 'Customer Details',
                    cardBg: _cardBg(context),
                    cardBorder: _cardBorder(context),
                    textPrimary: _textPrimary(context),
                    body: Column(
                      children: [
                        _InfoRow(
                          label: 'Name',
                          value: order.customerName,
                          textPrimary: _textPrimary(context),
                          textSecondary: _textSecondary(context),
                        ),
                        _InfoRow(
                          label: 'Phone',
                          value: order.customerPhone,
                          textPrimary: _textPrimary(context),
                          textSecondary: _textSecondary(context),
                          action: order.customerPhone.isNotEmpty
                              ? _IconAction(
                                  icon: Icons.phone_rounded,
                                  color: const Color(0xFF2D6CDF),
                                  onTap: () => _launchUri(
                                      'tel:${order.customerPhone}'),
                                )
                              : null,
                        ),
                        _InfoRow(
                          label: 'Address',
                          value: order.deliveryAddress,
                          textPrimary: _textPrimary(context),
                          textSecondary: _textSecondary(context),
                        ),
                        _InfoRow(
                          label: 'Order ID',
                          value: order.orderId,
                          textPrimary: _textPrimary(context),
                          textSecondary: _textSecondary(context),
                        ),
                        _InfoRow(
                          label: 'Status',
                          value: order.orderStatus.label,
                          textPrimary: _textPrimary(context),
                          textSecondary: _textSecondary(context),
                          customValue: _StatusPill(
                              label: order.orderStatus.label),
                        ),
                        if (order.orderStatus == OrderStatus.failed) ...[
                          const SizedBox(height: 10),
                          _FailureCard(
                            reasonCode: order.failureReasonCode,
                            notes: order.deliveryNotes,
                          ),
                        ],
                        if (order.deliveryInstructions.isNotEmpty)
                          _InfoRow(
                            label: 'Instructions',
                            value: order.deliveryInstructions,
                            textPrimary: _textPrimary(context),
                            textSecondary: _textSecondary(context),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    expanded: _storeExpanded,
                    onToggle: () =>
                        setState(() => _storeExpanded = !_storeExpanded),
                    headerBg: _isDark(context)
                        ? const Color(0xFF14352A)
                        : const Color(0xFFE7F7EE),
                    headerIcon: Icons.store_rounded,
                    headerIconColor: const Color(0xFF1AB36A),
                    title: 'Store Details',
                    cardBg: _cardBg(context),
                    cardBorder: _cardBorder(context),
                    textPrimary: _textPrimary(context),
                    body: Column(
                      children: [
                        _InfoRow(
                          label: 'Store Name',
                          value: order.storeName,
                          textPrimary: _textPrimary(context),
                          textSecondary: _textSecondary(context),
                        ),
                        _InfoRow(
                          label: 'Store ID',
                          value: order.storeId,
                          textPrimary: _textPrimary(context),
                          textSecondary: _textSecondary(context),
                          action: order.storeId.isNotEmpty
                              ? _IconAction(
                                  icon: Icons.public_rounded,
                                  color: const Color(0xFF2D6CDF),
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
                          textPrimary: _textPrimary(context),
                          textSecondary: _textSecondary(context),
                          action: order.storeContact.isNotEmpty
                              ? _IconAction(
                                  icon: Icons.phone_rounded,
                                  color: const Color(0xFF2D6CDF),
                                  onTap: () => _launchUri(
                                      'tel:${order.storeContact}'),
                                )
                              : null,
                        ),
                        _InfoRow(
                          label: 'Address',
                          value: order.storeAddress,
                          textPrimary: _textPrimary(context),
                          textSecondary: _textSecondary(context),
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
                          textPrimary: _textPrimary(context),
                          textSecondary: _textSecondary(context),
                        ),
                        _InfoRow(
                          label: 'Earnings',
                          value:
                              'Rs. ${order.estimatedEarnings.toStringAsFixed(0)}',
                          textPrimary: _textPrimary(context),
                          textSecondary: _textSecondary(context),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    expanded: _itemsExpanded,
                    onToggle: () =>
                        setState(() => _itemsExpanded = !_itemsExpanded),
                    headerBg: _isDark(context)
                        ? const Color(0xFF2D2148)
                        : const Color(0xFFEFE9FE),
                    headerIcon: Icons.inventory_2_rounded,
                    headerIconColor: const Color(0xFF7C3AED),
                    title: 'Order Items',
                    cardBg: _cardBg(context),
                    cardBorder: _cardBorder(context),
                    textPrimary: _textPrimary(context),
                    body: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (order.orderItems.isNotEmpty) ...[
                          ...order.orderItems.map(
                            (item) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${item.name} x${item.quantity}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: _textPrimary(context),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    'Rs. ${(item.price * item.quantity).toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: _textPrimary(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Divider(height: 1, color: _cardBorder(context)),
                          const SizedBox(height: 10),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total Amount',
                              style: TextStyle(
                                fontSize: 14,
                                color: _textSecondary(context),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Rs. ${order.totalAmount.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: _textPrimary(context),
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
                                color: _textSecondary(context),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              order.paymentMode.isEmpty
                                  ? '—'
                                  : order.paymentMode,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _textPrimary(context),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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
              busy: _busy,
              customerPhone: order.customerPhone,
              storePhone: order.storeContact,
              onAccept: () => _acceptPendingOrder(context, order),
              onReject: () => _rejectPendingOrder(context, order),
              onCallCustomer: () => _launchUri('tel:${order.customerPhone}'),
              onCallStore: () => _launchUri('tel:${order.storeContact}'),
              onNavigate: () =>
                  Navigator.of(context).pushNamed(AppRoutes.navigation),
              onTrack: () =>
                  Navigator.of(context).pushNamed(AppRoutes.orderTracking),
              cardBg: _cardBg(context),
              isDark: _isDark(context),
            ),
          ],
        ),
      ),
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
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textPrimary =
        isDark ? const Color(0xFFF2F4F7) : const Color(0xFF101828);
    final Color textSecondary =
        isDark ? const Color(0xFFA4ABB8) : const Color(0xFF667085);

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
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardBg = isDark ? const Color(0xFF1B1E2A) : Colors.white;
    final Color cardBorder =
        isDark ? const Color(0xFF2A2F3D) : const Color(0xFFE7EBF0);
    final Color iconColor =
        isDark ? const Color(0xFFF2F4F7) : const Color(0xFF101828);

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

  Color _bg(String s) {
    final lower = s.toLowerCase();
    if (lower.contains('deliver')) return const Color(0xFFE7F7EE);
    if (lower.contains('cancel') || lower.contains('reject')) {
      return const Color(0xFFFEF3F2);
    }
    if (lower.contains('pick') || lower.contains('out')) {
      return const Color(0xFFE5EEFB);
    }
    return const Color(0xFFFEF3E2);
  }

  Color _fg(String s) {
    final lower = s.toLowerCase();
    if (lower.contains('deliver')) return const Color(0xFF118A52);
    if (lower.contains('cancel') || lower.contains('reject')) {
      return const Color(0xFFB42318);
    }
    if (lower.contains('pick') || lower.contains('out')) {
      return const Color(0xFF1F4FB6);
    }
    return const Color(0xFFB87707);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _bg(label),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: _fg(label),
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
            color: Colors.black.withValues(alpha: 0.04),
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
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: headerBg,
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(16),
                  bottom: expanded
                      ? Radius.zero
                      : const Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(headerIcon, color: headerIconColor, size: 20),
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
                    color: textPrimary,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: body,
            ),
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
    this.action,
    this.customValue,
  });

  final String label;
  final String value;
  final Color textPrimary;
  final Color textSecondary;
  final Widget? action;
  final Widget? customValue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: customValue != null
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: customValue,
                  )
                : Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
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
    required this.busy,
    required this.customerPhone,
    required this.storePhone,
    required this.onAccept,
    required this.onReject,
    required this.onCallCustomer,
    required this.onCallStore,
    required this.onNavigate,
    required this.onTrack,
    required this.cardBg,
    required this.isDark,
  });

  final bool isPending;
  final bool showNavigate;
  final bool showTrackOrder;
  final bool busy;
  final String customerPhone;
  final String storePhone;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onCallCustomer;
  final VoidCallback onCallStore;
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
                        foregroundColor: const Color(0xFF2D6CDF),
                        side: BorderSide(
                          color: const Color(0xFF2D6CDF)
                              .withValues(alpha: 0.4),
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
                        foregroundColor: const Color(0xFF1AB36A),
                        side: BorderSide(
                          color: const Color(0xFF1AB36A)
                              .withValues(alpha: 0.4),
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
                        foregroundColor: const Color(0xFFB42318),
                        side: const BorderSide(
                          color: Color(0xFFFDA29B),
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
          ],
        ],
      ),
    );
  }
}

class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.reasonCode, required this.notes});
  final String? reasonCode;
  final String? notes;

  static const Map<String, String> _labels = {
    'customer_unavailable': 'Customer Unavailable',
    'address_inaccessible': 'Address Inaccessible',
    'wrong_address': 'Wrong Address',
    'customer_refused_at_door': 'Customer Refused at Door',
    'damaged_in_transit': 'Damaged in Transit',
    'lost_in_transit': 'Lost in Transit',
    'suspected_fraud': 'Suspected Fraud',
  };

  @override
  Widget build(BuildContext context) {
    final code = reasonCode ?? '';
    final noteText = notes ?? '';
    final reasonLabel = _labels[code] ?? (code.isNotEmpty ? code : '');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFC62828).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFC62828).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.cancel_rounded, color: Color(0xFFC62828), size: 15),
                    SizedBox(width: 5),
                    Text(
                      'Failure Details',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFC62828),
                      ),
                    ),
                  ],
                ),
                if (reasonLabel.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    reasonLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF7B1010),
                    ),
                  ),
                ],
                if (noteText.isNotEmpty && noteText != reasonLabel) ...[
                  const SizedBox(height: 3),
                  Text(
                    noteText,
                    style: TextStyle(
                      fontSize: 12,
                      color: const Color(0xFFC62828).withValues(alpha: 0.7),
                    ),
                  ),
                ],
                if (reasonLabel.isEmpty && noteText.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'No failure details recorded.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF7B1010)),
                    ),
                  ),
              ],
      ),
    );
  }
}
