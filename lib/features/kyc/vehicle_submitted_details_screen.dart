import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/context_colors.dart';

class VehicleSubmittedDetailsScreen extends StatelessWidget {
  const VehicleSubmittedDetailsScreen({
    super.key,
    required this.vehicleData,
  });

  final Map<String, dynamic> vehicleData;

  String _val(String key) => (vehicleData[key] ?? '').toString().trim();
  bool _has(String key) => _val(key).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    final licensePlate = _val('license_plate');
    final make = _val('make');
    final model = _val('model');
    final fuelType = _val('fuel_type');
    final odometer = _val('last_odometer');
    final color = _val('color');

    final hasInsurance = _has('insurance_company') ||
        _has('policy_no') ||
        _has('start_date') ||
        _has('end_date');

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────────────
            _VehicleBanner(
              primary: primary,
              isDark: isDark,
              licensePlate: licensePlate,
              make: make,
              model: model,
              onBack: () => Navigator.of(context).maybePop(),
            ).animate().fadeIn(duration: 350.ms),

            // ── Scrollable body ──────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                children: [
                  // Quick stats strip
                  if (fuelType.isNotEmpty ||
                      odometer.isNotEmpty ||
                      color.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _QuickStatsRow(
                      chips: [
                        if (fuelType.isNotEmpty)
                          _StatChip(
                            icon: Icons.local_gas_station_rounded,
                            label: 'Fuel',
                            value: fuelType,
                            color: AppTheme.oceanBlue,
                          ),
                        if (odometer.isNotEmpty)
                          _StatChip(
                            icon: Icons.speed_rounded,
                            label: 'Odometer',
                            value: '$odometer km',
                            color: AppTheme.mint,
                          ),
                        if (color.isNotEmpty)
                          _StatChip(
                            icon: Icons.palette_rounded,
                            label: 'Color',
                            value: color,
                            color: AppTheme.mango,
                          ),
                      ],
                    ).animate().fadeIn(duration: 400.ms, delay: 80.ms).slideY(
                          begin: 0.1,
                          end: 0,
                          duration: 400.ms,
                          delay: 80.ms,
                        ),
                  ],

                  const SizedBox(height: 16),

                  // ── Vehicle section ───────────────────────────────────
                  _InfoSection(
                    title: 'Vehicle Details',
                    icon: Icons.directions_car_rounded,
                    color: AppTheme.oceanBlue,
                    tiles: [
                      if (_has('wheels') || _has('doors'))
                        _TileRow(children: [
                          if (_has('wheels'))
                            _InfoTile(
                              icon: Icons.tire_repair_rounded,
                              label: 'Wheels',
                              value: _val('wheels'),
                              color: AppTheme.oceanBlue,
                            ),
                          if (_has('doors'))
                            _InfoTile(
                              icon: Icons.sensor_door_rounded,
                              label: 'Doors',
                              value: _val('doors'),
                              color: AppTheme.oceanBlue,
                            ),
                        ]),
                      if (_has('chassis_no'))
                        _InfoTile(
                          icon: Icons.pin_rounded,
                          label: 'Chassis Number',
                          value: _val('chassis_no'),
                          color: AppTheme.oceanBlue,
                          full: true,
                        ),
                      if (_has('vehicle_value'))
                        _InfoTile(
                          icon: Icons.currency_rupee_rounded,
                          label: 'Vehicle Value',
                          value: _val('vehicle_value'),
                          color: AppTheme.oceanBlue,
                          full: true,
                        ),
                      if (_has('acquisition_date'))
                        _InfoTile(
                          icon: Icons.calendar_month_rounded,
                          label: 'Acquired On',
                          value: _val('acquisition_date'),
                          color: AppTheme.oceanBlue,
                          full: true,
                        ),
                      if (_has('location'))
                        _InfoTile(
                          icon: Icons.location_on_rounded,
                          label: 'Location',
                          value: _val('location'),
                          color: AppTheme.oceanBlue,
                          full: true,
                        ),
                      if (_has('employee'))
                        _InfoTile(
                          icon: Icons.badge_rounded,
                          label: 'Employee',
                          value: _val('employee'),
                          color: AppTheme.oceanBlue,
                          full: true,
                        ),
                    ],
                  )
                      .animate()
                      .fadeIn(duration: 400.ms, delay: 160.ms)
                      .slideY(
                        begin: 0.1,
                        end: 0,
                        duration: 400.ms,
                        delay: 160.ms,
                      ),

                  // ── Insurance section ─────────────────────────────────
                  if (hasInsurance) ...[
                    const SizedBox(height: 12),
                    _InfoSection(
                      title: 'Insurance',
                      icon: Icons.shield_rounded,
                      color: AppTheme.mint,
                      tiles: [
                        if (_has('insurance_company'))
                          _InfoTile(
                            icon: Icons.apartment_rounded,
                            label: 'Insurance Company',
                            value: _val('insurance_company'),
                            color: AppTheme.mint,
                            full: true,
                          ),
                        if (_has('policy_no'))
                          _InfoTile(
                            icon: Icons.policy_rounded,
                            label: 'Policy Number',
                            value: _val('policy_no'),
                            color: AppTheme.mint,
                            full: true,
                          ),
                        if (_has('start_date') || _has('end_date'))
                          _TileRow(children: [
                            if (_has('start_date'))
                              _InfoTile(
                                icon: Icons.event_available_rounded,
                                label: 'Start Date',
                                value: _val('start_date'),
                                color: AppTheme.mint,
                              ),
                            if (_has('end_date'))
                              _InfoTile(
                                icon: Icons.event_busy_rounded,
                                label: 'End Date',
                                value: _val('end_date'),
                                color: AppTheme.mint,
                              ),
                          ]),
                        if (_has('carbon_check_date'))
                          _InfoTile(
                            icon: Icons.eco_rounded,
                            label: 'Carbon Check Date',
                            value: _val('carbon_check_date'),
                            color: AppTheme.mint,
                            full: true,
                          ),
                      ],
                    )
                        .animate()
                        .fadeIn(duration: 400.ms, delay: 240.ms)
                        .slideY(
                          begin: 0.1,
                          end: 0,
                          duration: 400.ms,
                          delay: 240.ms,
                        ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),

      // ── Pinned edit button ─────────────────────────────────────────────
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: () => Navigator.of(context).pushReplacementNamed(
              AppRoutes.vehicleDetails,
              arguments: <String, dynamic>{'force_edit': true},
            ),
            icon: const Icon(Icons.edit_rounded, size: 18),
            label: const Text('Edit Vehicle'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ).animate().fadeIn(duration: 400.ms, delay: 320.ms).slideY(
                begin: 0.2,
                end: 0,
                duration: 400.ms,
                delay: 320.ms,
              ),
        ),
      ),
    );
  }
}

// ── Banner ────────────────────────────────────────────────────────────────────

class _VehicleBanner extends StatelessWidget {
  const _VehicleBanner({
    required this.primary,
    required this.isDark,
    required this.licensePlate,
    required this.make,
    required this.model,
    required this.onBack,
  });

  final Color primary;
  final bool isDark;
  final String licensePlate;
  final String make;
  final String model;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary,
            primary.withValues(alpha: 0.80),
            AppTheme.mint.withValues(alpha: 0.70),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back button row
          Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                style: IconButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  padding: const EdgeInsets.all(8),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.verified_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'Registered',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Car icon + identity
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                child: const Icon(
                  Icons.directions_car_filled_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (make.isNotEmpty)
                      Text(
                        make,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.80),
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.4,
                        ),
                      ),
                    if (model.isNotEmpty)
                      Text(
                        model,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (licensePlate.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          licensePlate.toUpperCase(),
                          style: TextStyle(
                            color: primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            letterSpacing: 3,
                          ),
                        ),
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

// ── Quick stats row ───────────────────────────────────────────────────────────

class _QuickStatsRow extends StatelessWidget {
  const _QuickStatsRow({required this.chips});
  final List<_StatChip> chips;

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) return const SizedBox.shrink();
    return Row(
      children: chips
          .map(
            (chip) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: chip != chips.last ? 8 : 0,
                ),
                child: chip,
              ),
            ),
          )
          .toList(),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.borderSubtle,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: context.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: context.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Info section ──────────────────────────────────────────────────────────────

class _InfoSection extends StatelessWidget {
  const _InfoSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.tiles,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final nonEmpty = tiles.where((w) {
      if (w is _InfoTile) return true;
      if (w is _TileRow) return true;
      return false;
    }).toList();
    if (nonEmpty.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.borderSubtle),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: context.borderSubtle,
          ),
          // Tile grid
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: tiles
                  .asMap()
                  .entries
                  .map(
                    (entry) => Padding(
                      padding: EdgeInsets.only(
                        bottom: entry.key < tiles.length - 1 ? 8 : 0,
                      ),
                      child: entry.value,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info tile ─────────────────────────────────────────────────────────────────

class _TileRow extends StatelessWidget {
  const _TileRow({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: children
          .asMap()
          .entries
          .map(
            (e) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: e.key < children.length - 1 ? 8 : 0,
                ),
                child: e.value,
              ),
            ),
          )
          .toList(),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.full = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? color.withValues(alpha: 0.06)
            : color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.15 : 0.10),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: context.textSecondary,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                  maxLines: full ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
