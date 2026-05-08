import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'section_card.dart';

class CurrentLocationCard extends StatelessWidget {
  const CurrentLocationCard({
    super.key,
    required this.title,
    required this.changeLabel,
    required this.address,
    required this.subAddress,
    required this.latitude,
    required this.longitude,
    required this.onChangeTap,
    this.hasLocation = true,
  });

  final String title;
  final String changeLabel;
  final String address;
  final String subAddress;
  final double? latitude;
  final double? longitude;
  final VoidCallback onChangeTap;
  final bool hasLocation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final LatLng center = (latitude != null && longitude != null)
        ? LatLng(latitude!, longitude!)
        : const LatLng(28.6139, 77.2090);

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              _ChangeChip(label: changeLabel, onTap: onChangeTap),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                SizedBox(
                  height: 130,
                  width: double.infinity,
                  child: hasLocation
                      ? FlutterMap(
                          options: MapOptions(
                            initialCenter: center,
                            initialZoom: 15.5,
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.none,
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: isDark
                                  ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                                  : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              subdomains: isDark
                                  ? const ['a', 'b', 'c', 'd']
                                  : const [],
                              userAgentPackageName:
                                  'com.lyncspace.grozfygo',
                            ),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: center,
                                  width: 44,
                                  height: 44,
                                  child: Icon(
                                    Icons.location_pin,
                                    size: 36,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      : Container(
                          color: const Color(0xFFEEF2F7),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.map_outlined,
                            size: 40,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
                          ),
                        ),
                ),
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(onTap: onChangeTap),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.location_on_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 14,
                      ),
                    ),
                    if (subAddress.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subAddress,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
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

class _ChangeChip extends StatelessWidget {
  const _ChangeChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.gps_fixed_rounded,
                size: 14,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
