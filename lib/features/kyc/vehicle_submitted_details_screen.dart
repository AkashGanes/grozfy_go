import 'package:flutter/material.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/widgets/app_shell.dart';

class VehicleSubmittedDetailsScreen extends StatelessWidget {
  const VehicleSubmittedDetailsScreen({super.key, required this.vehicleData});

  final Map<String, dynamic> vehicleData;

  static const List<String> _summaryPriorityKeys = <String>[
    'name',
    'license_plate',
    'make',
    'model',
    'last_odometer',
    'fuel_type',
    'uom',
    'employee',
  ];

  static const Set<String> _hiddenSummaryKeys = <String>{
    'doctype',
    'owner',
    'creation',
    'modified',
    'modified_by',
    'docstatus',
    'idx',
    'amended_from',
    '_user_tags',
    '_comments',
    '_assign',
    '_liked_by',
  };

  List<MapEntry<String, String>> _summaryRows() {
    final List<MapEntry<String, String>> rows = <MapEntry<String, String>>[];
    for (final entry in vehicleData.entries) {
      if (_hiddenSummaryKeys.contains(entry.key)) {
        continue;
      }
      if (entry.value is Map || entry.value is List) {
        continue;
      }
      final String value = (entry.value ?? '').toString().trim();
      if (value.isEmpty) {
        continue;
      }
      rows.add(MapEntry<String, String>(entry.key, value));
    }

    int keyRank(String key) {
      final int index = _summaryPriorityKeys.indexOf(key);
      return index >= 0 ? index : 1000;
    }

    rows.sort((a, b) {
      final int rankA = keyRank(a.key);
      final int rankB = keyRank(b.key);
      if (rankA != rankB) {
        return rankA.compareTo(rankB);
      }
      return a.key.compareTo(b.key);
    });
    return rows;
  }

  String _fieldLabel(String key) {
    final List<String> words = key
        .split('_')
        .where((part) => part.trim().isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .toList();
    return words.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final String? vehicleName = vehicleData['name']?.toString();
    final List<MapEntry<String, String>> summary = _summaryRows();

    return AppShell(
      title: vehicleName?.trim().isNotEmpty == true
          ? vehicleName!.trim()
          : 'Vehicle Details',
      subtitle: 'Fetched live from API after save',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FrostCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (summary.isEmpty)
                  const Text('No displayable fields returned from API')
                else
                  ...summary.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              _fieldLabel(entry.key),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              entry.value,
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: const Text('Back to Edit'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pushNamed(AppRoutes.bankSetup);
                        },
                        child: const Text('Continue to Bank'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
