import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/providers.dart';
import '../../core/widgets/app_shell.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(appControllerProvider).fetchLoggedInEmployeeDriverProfile();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider);
    final details = app.loggedProfileDetails;

    return AppShell(
      title: 'My Profile',
      subtitle: app.profile?.fullName ?? app.profile?.mobile,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (app.profileDetailsLoading)
            const FrostCard(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: CircularProgressIndicator(),
                ),
              ),
            )
          else if (app.profileDetailsError != null)
            FrostCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.profileDetailsError!,
                    style: const TextStyle(color: Colors.black87),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      app.fetchLoggedInEmployeeDriverProfile(
                        forceRefresh: true,
                      );
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            )
          else if (details == null || !details.hasData)
            const FrostCard(
              child: Text('No profile data found for this login account.'),
            )
          else ...[
            FrostCard(
              child: _buildSection(
                title: 'Login Driver Details',
                data: details.driver,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                app.fetchLoggedInEmployeeDriverProfile(forceRefresh: true);
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh Profile'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required Map<String, dynamic>? data,
  }) {
    if (data == null || data.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          const Text('No linked record found.'),
        ],
      );
    }

    final entries =
        data.entries.where((entry) => !_isBlank(entry.value)).toList()
          ..sort((a, b) => a.key.compareTo(b.key));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        if (entries.isEmpty)
          const Text('No non-empty fields.')
        else
          ...entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(
                      _prettyKey(entry.key),
                      style: const TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _valueWidget(entry.key, entry.value)),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _valueWidget(String key, dynamic value) {
    if (key == 'driving_license_category' && value is List) {
      final List<String> categories = value
          .map(_extractDrivingCategory)
          .whereType<String>()
          .where((item) => item.trim().isNotEmpty)
          .toList();
      if (categories.isEmpty) {
        return const Text('No category data');
      }
      return Wrap(
        spacing: 8,
        runSpacing: 6,
        children: categories
            .map(
              (item) => Chip(
                label: Text(item),
                visualDensity: VisualDensity.compact,
              ),
            )
            .toList(),
      );
    }

    if (value is Map<String, dynamic> || value is List) {
      final String pretty = const JsonEncoder.withIndent('  ').convert(value);
      return ExpansionTile(
        tilePadding: EdgeInsets.zero,
        dense: true,
        title: const Text('View details'),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(
              pretty,
              style: const TextStyle(fontSize: 12, height: 1.3),
            ),
          ),
        ],
      );
    }

    return Text(value.toString());
  }

  String? _extractDrivingCategory(dynamic item) {
    if (item == null) {
      return null;
    }
    if (item is String) {
      return item;
    }
    if (item is Map<String, dynamic>) {
      final String cls = (item['class']?.toString() ?? '').trim();
      final String description = (item['description']?.toString() ?? '').trim();
      final String issuingDate = (item['issuing_date']?.toString() ?? '').trim();
      final String expiryDate = (item['expiry_date']?.toString() ?? '').trim();

      if (cls.isNotEmpty || description.isNotEmpty) {
        final StringBuffer label = StringBuffer();
        if (cls.isNotEmpty) {
          label.write(cls);
        }
        if (description.isNotEmpty) {
          if (label.isNotEmpty) {
            label.write(' - ');
          }
          label.write(description);
        }
        if (issuingDate.isNotEmpty || expiryDate.isNotEmpty) {
          label.write(' (');
          if (issuingDate.isNotEmpty) {
            label.write('Issue: $issuingDate');
          }
          if (issuingDate.isNotEmpty && expiryDate.isNotEmpty) {
            label.write(', ');
          }
          if (expiryDate.isNotEmpty) {
            label.write('Expiry: $expiryDate');
          }
          label.write(')');
        }
        return label.toString();
      }

      const List<String> fallbackKeys = <String>[
        'driving_license_category',
        'license_category',
        'category',
        'vehicle_class',
      ];
      for (final String key in fallbackKeys) {
        final String value = (item[key]?.toString() ?? '').trim();
        if (value.isNotEmpty) {
          return value;
        }
      }
    }
    return null;
  }

  bool _isBlank(dynamic value) {
    if (value == null) {
      return true;
    }
    if (value is String) {
      return value.trim().isEmpty;
    }
    if (value is Iterable) {
      return value.isEmpty;
    }
    if (value is Map) {
      return value.isEmpty;
    }
    return false;
  }

  String _prettyKey(String input) {
    final String normalized = input.replaceAll('_', ' ').trim();
    if (normalized.isEmpty) {
      return input;
    }
    return normalized[0].toUpperCase() + normalized.substring(1);
  }
}
