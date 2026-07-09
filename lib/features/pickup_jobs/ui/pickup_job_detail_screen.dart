import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/database/partner_timing_log_dao.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/state/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/context_colors.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/app_toast.dart';
import '../model/pickup_job.dart';
import '../repository/pickup_job_repository.dart';
import 'failed_pickup_bottom_sheet.dart';

class PickupJobDetailScreen extends ConsumerStatefulWidget {
  const PickupJobDetailScreen({super.key, required this.pickupJobName});

  final String pickupJobName;

  @override
  ConsumerState<PickupJobDetailScreen> createState() =>
      _PickupJobDetailScreenState();
}

class _PickupJobDetailScreenState
    extends ConsumerState<PickupJobDetailScreen> {
  late Future<_JobDetail> _future;
  bool _isSubmitting = false;
  bool _tripAcceptedFired = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_tripAcceptedFired) {
        _tripAcceptedFired = true;
        ref.read(appControllerProvider).recordTimingEvent(
          eventType: TimingEventType.tripAccepted,
          tripRef: widget.pickupJobName,
        );
      }
    });
  }

  Future<_JobDetail> _load() async {
    final repo = PickupJobRepository();
    final job = await repo.fetchJob(widget.pickupJobName);

    // Resolve trip name: prefer field on doc, fall back to saved pref
    final savedTrip = await repo.loadActiveTrip();
    final tripHint = (job.deliveryTrip?.isNotEmpty == true)
        ? job.deliveryTrip
        : savedTrip;

    final (stop, stopErr) = await repo.fetchPickupTripStop(
      pickupJobName: job.name,
      hintTripName: tripHint,
    );
    return _JobDetail(job, stop, stopErr);
  }

  // ── Mark Picked Up (B.3) ──────────────────────────────────────────────────

  Future<void> _handleMarkPickedUp(PickupJob job) async {
    // Optional photo capture
    final photoPath = await _showPickupProofSheet();
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.inventory_2_outlined, color: AppTheme.oceanBlue),
            const SizedBox(width: 8),
            Text(
              'Confirm Pickup',
              style: TextStyle(
                  color: ctx.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16),
            ),
          ],
        ),
        content: Text(
          'Confirm you have collected the items from ${job.customerName.isNotEmpty ? job.customerName : "the customer"}?',
          style:
              TextStyle(color: ctx.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.oceanBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm Picked Up'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    if (!ConnectivityService().isConnected) {
      showInfoSnack(context, 'You are offline — connect and try again.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await PickupJobRepository()
          .markPickedUp(job.name, proofPhotoPath: photoPath);
      if (!mounted) return;
      showInfoSnack(context, 'Picked up — head to the store.');
      setState(() { _future = _load(); });
    } catch (e) {
      if (!mounted) return;
      showInfoSnack(
          context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Drop at Store (B.4) ───────────────────────────────────────────────────

  Future<void> _handleDropAtStore(PickupJob job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.store_rounded, color: AppTheme.oceanBlue),
            const SizedBox(width: 8),
            Text(
              'Drop at Store',
              style: TextStyle(
                  color: ctx.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16),
            ),
          ],
        ),
        content: Text(
          'Confirm you have dropped the items for ${job.customerName.isNotEmpty ? job.customerName : "this customer"} at the store dock?',
          style: TextStyle(color: ctx.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.oceanBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm Drop'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    if (!ConnectivityService().isConnected) {
      showInfoSnack(context, 'You are offline — connect and try again.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await PickupJobRepository().confirmCompleted(job.name);
      await PickupJobRepository().clearActiveJob();
      ref.read(appControllerProvider).recordTimingEvent(
        eventType: TimingEventType.tripCompleted,
        tripRef: job.name,
      );
      // Update the trip stop status in ERPNext.
      if (job.deliveryTrip != null && job.deliveryTrip!.isNotEmpty) {
        try {
          await PickupJobRepository().updatePickupTripStopCompleted(
            tripName: job.deliveryTrip!,
            pickupJobName: job.name,
          );
        } catch (e) {
          debugPrint('[PickupJob] trip stop update failed: $e');
          if (mounted) {
            showInfoSnack(context,
                'Stop update: ${e.toString().replaceFirst('Exception: ', '')}');
          }
        }
      } else {
        debugPrint('[PickupJob] deliveryTrip is empty — skipping stop update');
      }
      if (!mounted) return;
      _showCompletionDialog();
      setState(() { _future = _load(); });
    } catch (e) {
      if (!mounted) return;
      showInfoSnack(
          context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Mark as Failed ────────────────────────────────────────────────────────

  Future<void> _handleMarkFailed(PickupJob job) async {
    final result = await showFailedPickupSheet(context);
    if (result == null || !mounted) return;
    if (!ConnectivityService().isConnected) {
      showInfoSnack(context, 'You are offline — connect and try again.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await PickupJobRepository().markPickupFailed(
        job.name,
        reasonCode: result.reasonCode,
        notes: result.notes,
        proofPhotoPath: result.photoPath,
        tripName: job.deliveryTrip,
      );
      await PickupJobRepository().clearActiveJob();
      if (!mounted) return;
      showInfoSnack(context, 'Pickup marked as failed.');
      setState(() { _future = _load(); });
    } catch (e) {
      if (!mounted) return;
      showInfoSnack(
          context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Mark En Route ─────────────────────────────────────────────────────────

  Future<void> _handleMarkEnRoute(PickupJob job) async {
    if (job.deliveryTrip == null || job.deliveryTrip!.isEmpty) {
      showInfoSnack(context, 'No delivery trip assigned to this job.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.directions_car_rounded, color: AppTheme.oceanBlue),
            const SizedBox(width: 8),
            Text(
              'Mark En Route',
              style: TextStyle(
                  color: ctx.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16),
            ),
          ],
        ),
        content: Text(
          'Confirm you are heading to pick up from ${job.customerName.isNotEmpty ? job.customerName : "the customer"}?',
          style: TextStyle(color: ctx.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.oceanBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm En Route'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    if (!ConnectivityService().isConnected) {
      showInfoSnack(context, 'You are offline — connect and try again.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await PickupJobRepository().markPickupEnRoute(
        pickupJobName: job.name,
        tripName: job.deliveryTrip!,
      );
      if (!mounted) return;
      showInfoSnack(context, 'En route — job status updated to Scheduled.');
      setState(() { _future = _load(); });
    } catch (e) {
      if (!mounted) return;
      showInfoSnack(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showCompletionDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: ctx.success),
            const SizedBox(width: 8),
            Text(
              'Pickup Complete',
              style: TextStyle(
                  color: ctx.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16),
            ),
          ],
        ),
        content: Text(
          'Items received at the store.\n\nThe customer\'s refund will be issued within 5–7 business days.',
          style: TextStyle(color: ctx.textSecondary),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ctx.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  // ── Photo capture ─────────────────────────────────────────────────────────

  Future<String?> _showPickupProofSheet() {
    return showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PickupProofSheet(),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Pickup Job',
      subtitle: widget.pickupJobName,
      scrollable: false,
      child: FutureBuilder<_JobDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.oceanBlue),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: FrostCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          size: 40, color: AppTheme.mango),
                      const SizedBox(height: 10),
                      Text(
                        snapshot.error
                            .toString()
                            .replaceFirst('Exception: ', ''),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.textSecondary),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton(
                        onPressed: () =>
                            setState(() => _future = _load()),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final detail = snapshot.data!;
          final job = detail.job;
          final extraFields = _computeExtraFields(job);
          final tabCount = 3 + (extraFields.isNotEmpty ? 1 : 0);

          return DefaultTabController(
            length: tabCount,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 8),
                  child: _statusProgressBar(job)
                      .animate()
                      .fadeIn(duration: 220.ms),
                ),
                TabBar(
                  indicatorColor: AppTheme.oceanBlue,
                  indicatorWeight: 2,
                  labelColor: AppTheme.oceanBlue,
                  unselectedLabelColor: context.textSecondary,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                  unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 13),
                  dividerColor: Colors.transparent,
                  tabs: [
                    const Tab(text: 'Details'),
                    const Tab(text: 'Trip'),
                    const Tab(text: 'Items'),
                    if (extraFields.isNotEmpty) const Tab(text: 'Info'),
                  ],
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: TabBarView(
                    children: [
                      _detailsTab(job),
                      _tripTab(detail.tripStop, detail.tripStopError),
                      _itemsTab(job),
                      if (extraFields.isNotEmpty) _infoTab(extraFields),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _actionArea(job)
                      .animate()
                      .fadeIn(delay: 200.ms, duration: 220.ms),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Dynamic cards from raw API data ──────────────────────────────────────

  /// Fields shown in dedicated cards — excluded from the raw dump.
  static const _handledKeys = {
    'name', 'doctype', 'status', 'docstatus', 'idx',
    'customer_name', 'customer_mobile', 'customer_email',
    'pickup_address', 'pickup_latitude', 'pickup_longitude',
    'drop_address', 'drop_latitude', 'drop_longitude',
    'items',
    'owner', 'creation', 'modified', 'modified_by',
    '__islocal', '__unsaved', '_liked_by', '__run_link_triggers',
    '__last_sync_on', '__onload',
  };

  /// All keys consumed explicitly in _tripStopCard — not shown in raw loop.
  static const _stopConsumedKeys = {
    'name', 'doctype', 'parent', 'parenttype', 'parentfield',
    'idx', 'docstatus', 'pickup_job',
    'stop', 'customer_name', 'customer_mobile', 'pickup_address',
    'status', 'failure_reason_code',
    'owner', 'creation', 'modified', 'modified_by',
    // injected trip fields
    '_trip_name', '_trip_status', '_trip_date',
    '_trip_driver', '_trip_total_stops', '_trip_completed_stops',
  };

  Map<String, dynamic> _computeExtraFields(PickupJob job) {
    final extra = <String, dynamic>{};
    for (final entry in job.rawData.entries) {
      final k = entry.key;
      final v = entry.value;
      if (_handledKeys.contains(k)) continue;
      if (v == null) continue;
      if (v is String && v.trim().isEmpty) continue;
      if (v is List || v is Map) continue;
      extra[k] = v;
    }
    return extra;
  }

  // ── Tab content ───────────────────────────────────────────────────────────

  Widget _detailsTab(PickupJob job) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
      child: Column(
        children: [
          if (job.customerName.isNotEmpty || job.customerMobile.isNotEmpty) ...[
            _customerCard(job).animate().fadeIn(duration: 220.ms),
            const SizedBox(height: 12),
          ],
          _addressCard(job)
              .animate()
              .fadeIn(delay: 40.ms, duration: 220.ms),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _tripTab(Map<String, dynamic>? tripStop, String? tripStopError) {
    if (tripStop != null) {
      return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
        child: Column(children: [
          _tripStopCard(tripStop).animate().fadeIn(duration: 220.ms),
          const SizedBox(height: 8),
        ]),
      );
    }
    if (tripStopError != null) {
      return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
        child: _tripStopErrorCard(tripStopError)
            .animate()
            .fadeIn(duration: 220.ms),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_shipping_outlined,
              size: 44, color: context.iconMuted),
          const SizedBox(height: 10),
          Text('No delivery trip assigned',
              style: TextStyle(color: context.textTertiary, fontSize: 13)),
        ],
      ).animate().fadeIn(duration: 220.ms),
    );
  }

  Widget _itemsTab(PickupJob job) {
    if (job.items.isEmpty && job.proofPhoto == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 44, color: context.iconMuted),
            const SizedBox(height: 10),
            Text('No items',
                style: TextStyle(color: context.textTertiary, fontSize: 13)),
          ],
        ).animate().fadeIn(duration: 220.ms),
      );
    }
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
      child: Column(
        children: [
          if (job.items.isNotEmpty)
            _itemsCard(job).animate().fadeIn(duration: 220.ms),
          if (job.proofPhoto != null) ...[
            if (job.items.isNotEmpty) const SizedBox(height: 12),
            _proofPhotoCard(job.proofPhoto!)
                .animate()
                .fadeIn(delay: 40.ms, duration: 220.ms),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _infoTab(Map<String, dynamic> extraFields) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
      child: Column(children: [
        _rawFieldsCard('Job Info', extraFields)
            .animate()
            .fadeIn(duration: 220.ms),
        const SizedBox(height: 8),
      ]),
    );
  }

  // ── Trip Stop cards ───────────────────────────────────────────────────────

  Widget _tripStopErrorCard(String error) {
    return FrostCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 16, color: AppTheme.mango),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Delivery Trip Stop',
                    style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(error,
                    style: TextStyle(
                        color: context.textSecondary, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tripStopCard(Map<String, dynamic> stop) {
    final stopNo = stop['stop']?.toString() ?? '';
    final stopStatus = (stop['status'] ?? '').toString();
    final customerName = (stop['customer_name'] ?? '').toString();
    final customerMobile = (stop['customer_mobile'] ?? '').toString();
    final pickupAddress = (stop['pickup_address'] ?? '').toString();
    final failureReason = (stop['failure_reason_code'] ?? '').toString().trim();

    final tripName = (stop['_trip_name'] ?? '').toString();
    final tripDate = (stop['_trip_date'] ?? '').toString();
    final tripDriver = (stop['_trip_driver'] ?? '').toString();

    Color stopColor;
    switch (stopStatus.trim().toLowerCase()) {
      case 'received at store':
        stopColor = context.success;
      case 'picked up':
        stopColor = AppTheme.oceanBlue;
      case 'failed':
        stopColor = context.danger;
      default:
        stopColor = AppTheme.mango;
    }

    // Any extra unknown fields the server might add in future
    final extra = <MapEntry<String, dynamic>>[];
    for (final entry in stop.entries) {
      if (_stopConsumedKeys.contains(entry.key)) continue;
      final v = entry.value;
      if (v == null) continue;
      if (v is String && v.trim().isEmpty) continue;
      if (v is List || v is Map) continue;
      extra.add(entry);
    }

    return FrostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Row(
            children: [
              _sectionTitle(
                  stopNo.isNotEmpty ? 'Pickup Stop #$stopNo' : 'Pickup Stop'),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: stopColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: stopColor.withValues(alpha: 0.30)),
                ),
                child: Text(
                  stopStatus.isEmpty ? 'Pending' : stopStatus,
                  style: TextStyle(
                    color: stopColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Stop details ──
          if (customerName.isNotEmpty)
            _infoRow(Icons.person_outline_rounded, customerName),
          if (customerMobile.isNotEmpty) ...[
            if (customerName.isNotEmpty) const SizedBox(height: 8),
            _callRow(customerMobile),
          ],
          if (pickupAddress.isNotEmpty) ...[
            const SizedBox(height: 8),
            _infoRow(Icons.my_location_outlined, pickupAddress,
                label: 'Pickup Address'),
          ],
          if (failureReason.isNotEmpty) ...[
            const SizedBox(height: 8),
            _infoRow(Icons.error_outline_rounded, failureReason,
                label: 'Failure Reason'),
          ],
          for (final e in extra) ...[
            const SizedBox(height: 8),
            _rawFieldRow(e.key, e.value),
          ],

          // ── Trip info divider ──
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),

          _sectionTitle('Delivery Trip'),
          const SizedBox(height: 10),

          _infoRow(Icons.local_shipping_outlined, tripName,
              label: 'Trip'),
          if (tripDate.isNotEmpty) ...[
            const SizedBox(height: 8),
            _infoRow(Icons.calendar_today_outlined, tripDate,
                label: 'Trip Date'),
          ],
          if (tripDriver.isNotEmpty) ...[
            const SizedBox(height: 8),
            _infoRow(Icons.badge_outlined, tripDriver, label: 'Driver'),
          ],
        ],
      ),
    );
  }

  Widget _rawFieldsCard(String title, Map<String, dynamic> fields) {
    final entries = fields.entries.toList();
    return FrostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(title),
          const SizedBox(height: 10),
          for (int i = 0; i < entries.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _rawFieldRow(entries[i].key, entries[i].value),
          ],
        ],
      ),
    );
  }

  Widget _rawFieldRow(String key, dynamic value) {
    final label = _humanLabel(key);
    final raw = value.toString().trim();
    final isUrl = raw.startsWith('http://') || raw.startsWith('https://');
    final isDate = RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(raw);

    Widget valueWidget;
    if (isUrl) {
      valueWidget = GestureDetector(
        onTap: () async {
          final uri = Uri.tryParse(raw);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: Text(
          raw,
          style: const TextStyle(
            color: AppTheme.oceanBlue,
            fontSize: 13,
            decoration: TextDecoration.underline,
          ),
        ),
      );
    } else {
      valueWidget = Text(
        isDate ? _formatCreation(raw) : raw,
        style: TextStyle(color: context.textPrimary, fontSize: 13),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: TextStyle(
              color: context.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(child: valueWidget),
      ],
    );
  }

  /// Converts snake_case field names to human-readable labels.
  String _humanLabel(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  // ── Compact horizontal progress bar ──────────────────────────────────────

  Widget _statusProgressBar(PickupJob job) {
    final statusNorm = job.status.trim().toLowerCase();
    final failed = statusNorm == 'failed';

    // Lifecycle: Added to Trip → Scheduled (En Route on stop) → Picked Up → Received at Store
    final enRoute = !failed &&
        (statusNorm == 'scheduled' ||
            statusNorm == 'picked up' ||
            statusNorm == 'received at store');
    final pickedUp = !failed &&
        (statusNorm == 'picked up' || statusNorm == 'received at store');
    final completed = statusNorm == 'received at store';

    Color statusColor;
    String statusLabel;
    if (failed) {
      statusColor = context.danger;
      statusLabel = 'Failed';
    } else if (completed) {
      statusColor = context.success;
      statusLabel = 'Received at Store';
    } else if (pickedUp) {
      statusColor = AppTheme.oceanBlue;
      statusLabel = 'Picked Up';
    } else if (enRoute) {
      statusColor = AppTheme.oceanBlue;
      statusLabel = 'Scheduled';
    } else {
      statusColor = AppTheme.mango;
      statusLabel = 'Added to Trip';
    }

    return FrostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Status',
                style: TextStyle(
                  color: context.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: statusColor.withValues(alpha: 0.30)),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _stepDot(done: true, label: 'Accepted'),
              _stepLine(done: enRoute),
              _stepDot(done: enRoute, label: 'En Route'),
              _stepLine(done: pickedUp),
              _stepDot(done: pickedUp, label: 'Picked Up'),
              _stepLine(done: completed),
              _stepDot(done: completed, label: 'At Store'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepDot({required bool done, required String label}) {
    final color = done ? AppTheme.oceanBlue : context.textTertiary;
    return Expanded(
      flex: 2,
      child: Column(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? AppTheme.oceanBlue : Colors.transparent,
              border: done
                  ? null
                  : Border.all(color: context.borderStrong, width: 1.5),
            ),
            child: done
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : null,
          ),
          const SizedBox(height: 5),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: done ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepLine({required bool done}) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 18),
        color: done
            ? AppTheme.oceanBlue.withValues(alpha: 0.4)
            : context.borderSubtle,
      ),
    );
  }

  // ── Customer card ─────────────────────────────────────────────────────────

  Widget _customerCard(PickupJob job) {
    return FrostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Customer'),
          const SizedBox(height: 10),
          _infoRow(Icons.person_outline_rounded, job.customerName.isNotEmpty
              ? job.customerName
              : '—'),
          if (job.customerMobile.isNotEmpty) ...[
            const SizedBox(height: 8),
            _callRow(job.customerMobile),
          ],
        ],
      ),
    );
  }

  // ── Address card ──────────────────────────────────────────────────────────

  Widget _addressCard(PickupJob job) {
    return FrostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Addresses'),
          const SizedBox(height: 10),
          _addressRow(
            icon: Icons.my_location_outlined,
            label: 'Pickup from',
            address: job.pickupAddress,
            lat: job.pickupLatitude,
            lng: job.pickupLongitude,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1),
          ),
          _addressRow(
            icon: Icons.store_outlined,
            label: 'Drop at store',
            address: job.dropAddress,
            lat: job.dropLatitude,
            lng: job.dropLongitude,
          ),
        ],
      ),
    );
  }

  Widget _addressRow({
    required IconData icon,
    required String label,
    required String address,
    double? lat,
    double? lng,
  }) {
    final hasCoords = lat != null && lng != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 15, color: AppTheme.oceanBlue),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: context.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                address.isNotEmpty ? address : '—',
                style: TextStyle(
                    color: context.textPrimary, fontSize: 13),
              ),
              if (hasCoords) ...[
                const SizedBox(height: 3),
                Text(
                  '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                  style: TextStyle(
                      color: context.textTertiary, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
        if (hasCoords)
          GestureDetector(
            onTap: () async {
              final url = Uri.parse(
                  'https://maps.google.com/?q=$lat,$lng');
              if (await canLaunchUrl(url)) await launchUrl(url);
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.oceanBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppTheme.oceanBlue.withValues(alpha: 0.25)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.map_outlined,
                      size: 12, color: AppTheme.oceanBlue),
                  SizedBox(width: 3),
                  Text('Map',
                      style: TextStyle(
                          color: AppTheme.oceanBlue,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ── Items card ────────────────────────────────────────────────────────────

  Widget _itemsCard(PickupJob job) {
    return FrostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _sectionTitle('Items'),
              const Spacer(),
              Text(
                '${job.items.length} item${job.items.length == 1 ? '' : 's'}',
                style: const TextStyle(
                    color: AppTheme.oceanBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < job.items.length; i++) ...[
            if (i > 0) const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Divider(height: 1),
            ),
            _itemRow(job.items[i]),
          ],
        ],
      ),
    );
  }

  Widget _itemRow(PickupJobItem item) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppTheme.oceanBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.inventory_2_outlined,
              size: 14, color: AppTheme.oceanBlue),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.itemName,
                style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
              ),
              if (item.description != null && item.description!.isNotEmpty)
                Text(item.description!,
                    style: TextStyle(
                        color: context.textSecondary, fontSize: 11)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Qty: ${item.qty % 1 == 0 ? item.qty.toInt() : item.qty}',
              style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
            if (item.amount != null)
              Text(
                '₹${item.amount!.toStringAsFixed(2)}',
                style: TextStyle(color: context.textSecondary, fontSize: 11),
              ),
          ],
        ),
      ],
    );
  }

  String _formatCreation(String raw) {
    try {
      final dt = DateTime.parse(raw);
      final months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '${dt.day} ${months[dt.month]} ${dt.year}  $h:$m';
    } catch (_) {
      return raw;
    }
  }

  // ── Proof photo card ──────────────────────────────────────────────────────

  Widget _proofPhotoCard(String photoUrl) {
    final baseUrl = photoUrl.startsWith('http')
        ? photoUrl
        : '${ApiConstants.erpBaseUrl}$photoUrl';
    return FrostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Proof of Pickup'),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              baseUrl,
              width: double.infinity,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : const SizedBox(
                      height: 120,
                      child: Center(
                        child: CircularProgressIndicator(
                            color: AppTheme.oceanBlue, strokeWidth: 2),
                      ),
                    ),
              errorBuilder: (_, e, s) => Container(
                height: 80,
                decoration: BoxDecoration(
                  color: context.fillSubtle,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text('Image unavailable',
                      style: TextStyle(
                          color: context.textTertiary, fontSize: 12)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        color: context.textTertiary,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _actionArea(PickupJob job) {
    final statusNorm = job.status.trim().toLowerCase();

    if (_isSubmitting) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: CircularProgressIndicator(color: AppTheme.oceanBlue),
        ),
      );
    }

    // Added to Trip → Mark En Route (propagates to Scheduled on server)
    if (statusNorm == 'added to trip') {
      return Column(
        children: [
          _primaryActionButton(
            label: 'Mark En Route',
            icon: Icons.directions_car_rounded,
            onTap: () => _handleMarkEnRoute(job),
          ),
          const SizedBox(height: 10),
          _failedActionButton(onTap: () => _handleMarkFailed(job)),
        ],
      );
    }

    // Scheduled (En Route marked on stop) → Mark Picked Up + Mark as Failed  (Story B.3)
    if (statusNorm == 'scheduled') {
      return Column(
        children: [
          _primaryActionButton(
            label: 'Mark Picked Up',
            icon: Icons.inventory_2_outlined,
            onTap: () => _handleMarkPickedUp(job),
          ),
          const SizedBox(height: 10),
          _failedActionButton(onTap: () => _handleMarkFailed(job)),
        ],
      );
    }

    // Picked Up → Drop at Store + Mark as Failed  (Story B.4)
    if (statusNorm == 'picked up') {
      return Column(
        children: [
          _primaryActionButton(
            label: 'Drop at Store',
            icon: Icons.store_rounded,
            onTap: () => _handleDropAtStore(job),
          ),
          const SizedBox(height: 10),
          _failedActionButton(onTap: () => _handleMarkFailed(job)),
        ],
      );
    }

    // Received at Store — terminal success
    if (statusNorm == 'received at store') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.successContainer,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: context.success.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded,
                size: 18, color: context.success),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Pickup complete. Refund issued within 5–7 business days.',
                style: TextStyle(
                    color: context.success,
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    // Failed — terminal failure
    if (statusNorm == 'failed') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.dangerContainer,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.danger.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(Icons.cancel_outlined, size: 18, color: context.danger),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Pickup marked as failed.',
                style: TextStyle(
                    color: context.danger,
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _failedActionButton({required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: context.danger,
          side: BorderSide(color: context.danger.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        icon: const Icon(Icons.cancel_outlined, size: 18),
        label: const Text(
          'Mark as Failed',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        onPressed: onTap,
      ),
    );
  }

  Widget _primaryActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.oceanBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 15)),
        onPressed: onTap,
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, {String? label}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 15, color: context.iconMuted),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: label != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                          color: context.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 1),
                    Text(text,
                        style: TextStyle(
                            color: context.textPrimary, fontSize: 13)),
                  ],
                )
              : Text(text,
                  style: TextStyle(
                      color: context.textPrimary, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _callRow(String phone) {
    return Row(
      children: [
        Icon(Icons.phone_outlined, size: 15, color: context.iconMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(phone,
              style: TextStyle(
                  color: context.textPrimary, fontSize: 13)),
        ),
        GestureDetector(
          onTap: () async {
            final uri = Uri(scheme: 'tel', path: phone);
            if (await canLaunchUrl(uri)) await launchUrl(uri);
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: context.successContainer,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: context.success.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.call_rounded,
                    size: 13, color: context.success),
                const SizedBox(width: 4),
                Text('Call',
                    style: TextStyle(
                        color: context.success,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ],
    );
  }

}

class _JobDetail {
  const _JobDetail(this.job, this.tripStop, this.tripStopError);
  final PickupJob job;
  final Map<String, dynamic>? tripStop;
  final String? tripStopError;
}

// ── Pickup proof sheet ────────────────────────────────────────────────────────

class _PickupProofSheet extends StatefulWidget {
  const _PickupProofSheet();

  @override
  State<_PickupProofSheet> createState() => _PickupProofSheetState();
}

class _PickupProofSheetState extends State<_PickupProofSheet> {
  XFile? _pickedFile;
  static const int _maxFileSizeBytes = 5 * 1024 * 1024;

  Future<void> _pickPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final original = await picker.pickImage(source: source);
    if (original == null || !mounted) return;
    final size = await File(original.path).length();
    if (size > _maxFileSizeBytes) {
      if (mounted) {
        AppToast.show(context,
            'Selected image exceeds 5 MB limit. Choose a smaller image.');
      }
      return;
    }
    final compressed =
        await FlutterImageCompress.compressWithFile(original.path, quality: 80);
    if (compressed == null || !mounted) return;
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/pickup_proof_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await file.writeAsBytes(compressed);
    if (mounted) setState(() => _pickedFile = XFile(file.path));
  }

  void _showSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: AppTheme.oceanBlue),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppTheme.oceanBlue),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickPhoto(ImageSource.gallery);
              },
            ),
            if (_pickedFile != null)
              ListTile(
                leading:
                    Icon(Icons.delete_outline, color: context.danger),
                title: Text('Remove Photo',
                    style: TextStyle(color: context.danger)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  setState(() => _pickedFile = null);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + inset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: context.fillMuted,
                    borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.oceanBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      color: AppTheme.oceanBlue, size: 20),
                ),
                const SizedBox(width: 10),
                Text(
                  'Proof of Pickup',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Optionally capture a photo of the items before collecting.',
              style: TextStyle(fontSize: 13, color: context.textSecondary),
            ),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: _showSourceSheet,
              child: _pickedFile == null
                  ? Container(
                      width: double.infinity,
                      height: 160,
                      decoration: BoxDecoration(
                        color: context.fillSubtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: context.borderMuted),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo_outlined,
                              color: context.iconMuted, size: 36),
                          const SizedBox(height: 8),
                          Text('Tap to capture photo',
                              style: TextStyle(
                                  color: context.textTertiary, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text('Camera or gallery',
                              style: TextStyle(
                                  color: context.textDisabled, fontSize: 11)),
                        ],
                      ),
                    )
                  : Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(_pickedFile!.path),
                            width: double.infinity,
                            height: 200,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: _showSourceSheet,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('Change',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(
                          color: context.borderStrong),
                    ),
                    child: Text('Skip',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: context.textSecondary)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.oceanBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.done_all_rounded, size: 18),
                    label: const Text('Confirm Picked Up',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    onPressed: () =>
                        Navigator.of(context).pop(_pickedFile?.path),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
