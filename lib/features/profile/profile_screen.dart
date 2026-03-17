import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/api_constants.dart';
import '../../core/state/providers.dart';
import '../../core/widgets/app_shell.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _mobileCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  bool _savingBasicInfo = false;
  bool _basicInfoInitialized = false;
  bool _expandBasicDetails = true;
  bool _expandLicenseDetails = false;
  bool _expandDrivingCategory = false;
  bool _expandAdditionalDetails = false;
  bool _expandAttachments = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(appControllerProvider).fetchLoggedInEmployeeDriverProfile();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider);
    _initBasicInfoFromState(app);

    final Map<String, dynamic>? driver = app.loggedProfileDetails?.driver;
    final String displayName =
        app.profile?.fullName ?? _field(driver, 'full_name') ?? 'Driver';
    final bool hasDriver = driver != null && driver.isNotEmpty;

    final Widget detailsSection;
    final String detailsStateKey;
    if (app.profileDetailsLoading) {
      detailsStateKey = 'loading';
      detailsSection = _buildLoadingState();
    } else if (app.profileDetailsError != null) {
      detailsStateKey = 'error';
      detailsSection = _buildErrorState(app.profileDetailsError!, app);
    } else if (!hasDriver) {
      detailsStateKey = 'empty';
      detailsSection = const FrostCard(
        child: Text('No driver details found for this login account.'),
      );
    } else {
      detailsStateKey = 'data';
      detailsSection = _buildDriverDetails(driver, app);
    }

    return AppShell(
      title: 'My Profile',
      subtitle: 'Driver account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _animatedEntry(
            child: _profileHeader(
              name: displayName,
              imagePath: app.profileImagePath,
              busy: _savingBasicInfo || app.profileImageSyncing,
            ),
            delayMs: 0,
          ),
          const SizedBox(height: 12),
          _animatedEntry(
            child: _basicInformationSection(app),
            delayMs: 120,
          ),
          const SizedBox(height: 12),
          _animatedEntry(
            delayMs: 220,
            child: AnimatedSwitcher(
              duration: 320.ms,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final Animation<Offset> offset = Tween<Offset>(
                  begin: const Offset(0.0, 0.08),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: offset, child: child),
                );
              },
              child: KeyedSubtree(
                key: ValueKey<String>(detailsStateKey),
                child: detailsSection,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _animatedEntry({
    required Widget child,
    required int delayMs,
  }) {
    return child
        .animate(delay: Duration(milliseconds: delayMs))
        .fadeIn(duration: 420.ms, curve: Curves.easeOutCubic)
        .slideY(begin: 0.06, end: 0, duration: 420.ms, curve: Curves.easeOutCubic);
  }

  Widget _buildLoadingState() {
    return FrostCard(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator()
                  .animate(onPlay: (controller) => controller.repeat())
                  .fadeIn(duration: 280.ms)
                  .scale(
                    begin: const Offset(0.92, 0.92),
                    end: const Offset(1.0, 1.0),
                    duration: 500.ms,
                    curve: Curves.easeOut,
                  ),
              const SizedBox(height: 10),
              const Text(
                'Loading driver details...',
                style: TextStyle(color: Colors.black54),
              )
                  .animate(delay: 80.ms)
                  .fadeIn(duration: 320.ms)
                  .slideY(begin: 0.2, end: 0, duration: 320.ms),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(String error, dynamic app) {
    return FrostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(error, style: const TextStyle(color: Colors.black87)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              app.fetchLoggedInEmployeeDriverProfile(forceRefresh: true);
            },
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverDetails(Map<String, dynamic> driver, dynamic app) {
    final Map<String, String> additionalFields = _additionalDriverFields(driver);
    final List<_DriverAttachment> attachments = _extractDriverAttachments(driver);
    final Map<String, String> primaryImageHeaders = _primaryAttachmentHeaders(app);
    final Map<String, String> fallbackImageHeaders = <String, String>{
      'Authorization': 'token ${ApiConstants.apiKey}:${ApiConstants.apiSecret}',
      'Accept': 'image/*',
    };

    return FrostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _detailSection(
            title: 'Basic Details',
            subtitle: 'Identity and contact snapshot',
            leadingIcon: Icons.badge_outlined,
            expanded: _expandBasicDetails,
            onToggle: () {
              setState(() => _expandBasicDetails = !_expandBasicDetails);
            },
            child: Column(
              children: [
                _kv('Full Name', _field(driver, 'full_name') ?? '-'),
                _kv('Employee', _field(driver, 'employee') ?? '-'),
                _kv('Cell Number', _field(driver, 'cell_number') ?? '-'),
                _kv('Status', _field(driver, 'status') ?? '-'),
                _kv('Address', _field(driver, 'address') ?? '-'),
                _kv(
                  'Aadhar',
                  _firstAvailableField(driver, const <String>[
                        'custom_aadhar',
                        'custom_aadhaar',
                        'custom_aadhar_number',
                        'custom_aadhaar_number',
                        'aadhar',
                        'aadhaar',
                        'aadhar_number',
                        'aadhaar_number',
                      ]) ??
                      '-',
                ),
              ],
            ),
          ).animate(delay: 40.ms).fadeIn(duration: 300.ms).slideY(begin: 0.08, end: 0),
          const SizedBox(height: 10),
          _detailSection(
            title: 'License Details',
            subtitle: 'Driving license and document info',
            leadingIcon: Icons.assignment_ind_outlined,
            expanded: _expandLicenseDetails,
            onToggle: () {
              setState(() => _expandLicenseDetails = !_expandLicenseDetails);
            },
            child: Column(
              children: [
                _kv('License Number', _field(driver, 'license_number') ?? '-'),
                _kv('Issue Date', _field(driver, 'issuing_date') ?? '-'),
                _kv('Expiry Date', _field(driver, 'expiry_date') ?? '-'),
              ],
            ),
          ).animate(delay: 120.ms).fadeIn(duration: 300.ms).slideY(begin: 0.08, end: 0),
          const SizedBox(height: 10),
          _detailSection(
            title: 'Driving License Category',
            subtitle: 'Allowed vehicle classes',
            leadingIcon: Icons.category_outlined,
            expanded: _expandDrivingCategory,
            onToggle: () {
              setState(() => _expandDrivingCategory = !_expandDrivingCategory);
            },
            child: _licenseCategorySection(driver['driving_license_category']),
          ).animate(delay: 180.ms).fadeIn(duration: 300.ms).slideY(begin: 0.08, end: 0),
          const SizedBox(height: 10),
          _detailSection(
            title: 'Additional Driver Details',
            subtitle: 'Extra fields from your Driver doctype',
            leadingIcon: Icons.description_outlined,
            expanded: _expandAdditionalDetails,
            onToggle: () {
              setState(() => _expandAdditionalDetails = !_expandAdditionalDetails);
            },
            child: _additionalDetailsSection(additionalFields),
          ).animate(delay: 220.ms).fadeIn(duration: 300.ms).slideY(begin: 0.08, end: 0),
          const SizedBox(height: 10),
          _detailSection(
            title: 'Driver Attachments',
            subtitle: 'Read-only images from your URL data',
            leadingIcon: Icons.attachment_rounded,
            expanded: _expandAttachments,
            onToggle: () {
              setState(() => _expandAttachments = !_expandAttachments);
            },
            child: _attachmentSection(
              attachments,
              primaryHeaders: primaryImageHeaders,
              fallbackHeaders: fallbackImageHeaders,
            ),
          ).animate(delay: 260.ms).fadeIn(duration: 300.ms).slideY(begin: 0.08, end: 0),
        ],
      ),
    );
  }

  Widget _additionalDetailsSection(Map<String, String> fields) {
    if (fields.isEmpty) {
      return const Text('No additional details');
    }
    return Column(
      children: fields.entries
          .map((entry) => _kv(_labelFromKey(entry.key), entry.value))
          .toList(),
    );
  }

  Widget _attachmentSection(
    List<_DriverAttachment> attachments, {
    required Map<String, String> primaryHeaders,
    required Map<String, String> fallbackHeaders,
  }) {
    if (attachments.isEmpty) {
      return const Text('No attachments found');
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: attachments.map((item) {
        return InkWell(
          onTap: () => _showAttachmentPreview(item),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 124,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: _attachmentImage(
                      url: item.url,
                      fit: BoxFit.cover,
                      primaryHeaders: primaryHeaders,
                      fallbackHeaders: fallbackHeaders,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _labelFromKey(item.fieldKey),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  void _showAttachmentPreview(_DriverAttachment item) {
    final app = ref.read(appControllerProvider);
    final Map<String, String> primaryHeaders = _primaryAttachmentHeaders(app);
    final Map<String, String> fallbackHeaders = <String, String>{
      'Authorization': 'token ${ApiConstants.apiKey}:${ApiConstants.apiSecret}',
      'Accept': 'image/*',
    };

    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _labelFromKey(item.fieldKey),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: _attachmentImage(
                    url: item.url,
                    fit: BoxFit.contain,
                    primaryHeaders: primaryHeaders,
                    fallbackHeaders: fallbackHeaders,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void _initBasicInfoFromState(dynamic app) {
    if (_basicInfoInitialized) {
      return;
    }
    _nameCtrl.text = app.profile?.fullName ?? '';
    _mobileCtrl.text = app.profile?.mobile ?? '';
    _emailCtrl.text = app.profile?.email ?? '';
    _basicInfoInitialized = true;
  }

  Widget _profileHeader({
    required String name,
    required String? imagePath,
    required bool busy,
  }) {
    return FrostCard(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF5FF),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            const SizedBox(height: 4),
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: Colors.white,
                  backgroundImage: imagePath != null
                      ? FileImage(File(imagePath))
                      : null,
                  child: imagePath == null
                      ? const Icon(Icons.person_rounded, size: 42)
                      : null,
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: busy ? null : _pickImage,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.edit_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1AB36A),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.check, size: 12, color: Colors.white),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Verified Account',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _basicInformationSection(dynamic app) {
    return FrostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Basic Information',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text(
            'Edit name, phone number, email and profile picture',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Name',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _mobileCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _savingBasicInfo ? null : _saveBasicInfo,
            icon: const Icon(Icons.save_outlined),
            label: Text(
              _savingBasicInfo ? 'Saving...' : 'Save Basic Information',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1024,
    );
    if (file == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    final String? error = await ref
        .read(appControllerProvider)
        .updateProfileImageAndSync(pickedPath: file.path);
    if (!mounted) {
      return;
    }
    if (error != null) {
      showInfoSnack(context, error);
    } else {
      showInfoSnack(context, 'Profile image updated');
    }
  }

  Future<void> _saveBasicInfo() async {
    setState(() => _savingBasicInfo = true);

    await ref
        .read(appControllerProvider)
        .updateProfile(
          fullName: _nameCtrl.text.trim(),
          mobile: _mobileCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
        );

    if (!mounted) {
      return;
    }

    setState(() => _savingBasicInfo = false);
    showInfoSnack(context, 'Basic information updated');
  }

  Widget _detailSection({
    required String title,
    required String subtitle,
    required IconData leadingIcon,
    required bool expanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: expanded ? Colors.white : Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: expanded
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.25)
              : Colors.black.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(leadingIcon, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onToggle,
                  icon: AnimatedRotation(
                    turns: expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOutCubic,
                    child: const Icon(Icons.chevron_right_rounded),
                  ),
                  tooltip: expanded ? 'Collapse' : 'Expand',
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeInOutCubic,
            child: ClipRect(
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeInOutCubic,
                alignment: Alignment.topCenter,
                heightFactor: expanded ? 1 : 0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: expanded ? 1 : 0,
                  child: expanded
                      ? Column(
                          children: [
                            const SizedBox(height: 12),
                            child,
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _licenseCategorySection(dynamic raw) {
    final List<Map<String, dynamic>> categories = _toCategoryList(raw);
    if (categories.isEmpty) {
      return const Text('No category data');
    }

    return Column(
      children: categories.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _categoryTitle(item),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                _kv('Issue Date', _field(item, 'issuing_date') ?? '-'),
                _kv('Expiry Date', _field(item, 'expiry_date') ?? '-'),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  List<Map<String, dynamic>> _toCategoryList(dynamic raw) {
    if (raw is! List) {
      return const [];
    }
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  String _categoryTitle(Map<String, dynamic> item) {
    final String cls = _field(item, 'class') ?? '';
    final String description = _field(item, 'description') ?? '';
    if (cls.isNotEmpty && description.isNotEmpty) {
      return '$cls - $description';
    }
    if (cls.isNotEmpty) {
      return cls;
    }
    if (description.isNotEmpty) {
      return description;
    }
    return 'Category';
  }

  Map<String, String> _additionalDriverFields(Map<String, dynamic> driver) {
    final Set<String> excludedKeys = <String>{
      'name',
      'full_name',
      'employee',
      'cell_number',
      'status',
      'address',
      'custom_aadhar',
      'custom_aadhaar',
      'custom_aadhar_number',
      'custom_aadhaar_number',
      'aadhar',
      'aadhaar',
      'aadhar_number',
      'aadhaar_number',
      'license_number',
      'issuing_date',
      'expiry_date',
      'driving_license_category',
      'doctype',
      'owner',
      'creation',
      'modified',
      'modified_by',
      'docstatus',
      'idx',
      '_user_tags',
      '_comments',
      '_assign',
      '_liked_by',
    };

    final Map<String, String> result = <String, String>{};
    for (final entry in driver.entries) {
      final String key = entry.key;
      if (excludedKeys.contains(key)) {
        continue;
      }

      final dynamic value = entry.value;
      if (value == null || value is List || value is Map) {
        continue;
      }
      final String text = value.toString().trim();
      if (text.isEmpty || _looksLikeAttachmentValue(text)) {
        continue;
      }
      result[key] = text;
    }
    return result;
  }

  List<_DriverAttachment> _extractDriverAttachments(Map<String, dynamic> driver) {
    final List<_DriverAttachment> attachments = <_DriverAttachment>[];
    final Set<String> seen = <String>{};

    for (final entry in driver.entries) {
      final List<String> urls = _extractAttachmentUrls(entry.value);
      for (int i = 0; i < urls.length; i++) {
        final String raw = urls[i];
        final String url = _normalizeAttachmentUrl(raw);
        if (seen.add(url)) {
          final String fieldKey = urls.length == 1
              ? entry.key
              : '${entry.key}_${i + 1}';
          attachments.add(_DriverAttachment(fieldKey: fieldKey, url: url));
        }
      }
    }
    return attachments;
  }

  List<String> _extractAttachmentUrls(dynamic value) {
    if (value == null) {
      return const <String>[];
    }
    if (value is String) {
      final String raw = value.trim();
      if ((raw.startsWith('{') && raw.endsWith('}')) ||
          (raw.startsWith('[') && raw.endsWith(']'))) {
        try {
          final dynamic decoded = jsonDecode(raw);
          return _extractAttachmentUrls(decoded);
        } catch (_) {
          // fall through and treat it as plain text
        }
      }
      return _looksLikeAttachmentValue(raw) ? <String>[raw] : const <String>[];
    }
    if (value is List) {
      final List<String> urls = <String>[];
      for (final dynamic item in value) {
        urls.addAll(_extractAttachmentUrls(item));
      }
      return urls;
    }
    if (value is Map) {
      final List<String> urls = <String>[];
      for (final String candidateKey in const <String>[
        'file_url',
        'url',
        'path',
        'file',
      ]) {
        urls.addAll(_extractAttachmentUrls(value[candidateKey]));
      }
      return urls;
    }
    return const <String>[];
  }

  Widget _attachmentImage({
    required String url,
    required BoxFit fit,
    required Map<String, String> primaryHeaders,
    required Map<String, String> fallbackHeaders,
  }) {
    return Image.network(
      url,
      fit: fit,
      headers: primaryHeaders,
      errorBuilder: (context, error, stackTrace) {
        return Image.network(
          url,
          fit: fit,
          headers: fallbackHeaders,
          errorBuilder: (context, error, stackTrace) {
            return const ColoredBox(
              color: Color(0xFFF4F6F9),
              child: Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: Colors.black45,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Map<String, String> _primaryAttachmentHeaders(dynamic app) {
    final String? token = app.sessionToken?.toString().trim();
    if (token != null && token.isNotEmpty) {
      return <String, String>{
        'Authorization': 'Bearer $token',
        'Accept': 'image/*',
      };
    }
    return <String, String>{
      'Authorization': 'token ${ApiConstants.apiKey}:${ApiConstants.apiSecret}',
      'Accept': 'image/*',
    };
  }

  bool _looksLikeAttachmentValue(String value) {
    final String lowered = value.toLowerCase();
    if (lowered.isEmpty) {
      return false;
    }
    return lowered.endsWith('.jpg') ||
        lowered.endsWith('.jpeg') ||
        lowered.endsWith('.png') ||
        lowered.endsWith('.webp') ||
        lowered.endsWith('.gif') ||
        lowered.contains('/files/') ||
        lowered.startsWith('/files/') ||
        lowered.startsWith('http://') ||
        lowered.startsWith('https://');
  }

  String _normalizeAttachmentUrl(String value) {
    final String sanitized = value.trim().replaceAll(' ', '%20');
    if (sanitized.startsWith('http://') || sanitized.startsWith('https://')) {
      return sanitized;
    }
    final String base = ApiConstants.erpBaseUrl.endsWith('/')
        ? ApiConstants.erpBaseUrl.substring(0, ApiConstants.erpBaseUrl.length - 1)
        : ApiConstants.erpBaseUrl;
    return sanitized.startsWith('/')
        ? '$base$sanitized'
        : '$base/$sanitized';
  }

  String _labelFromKey(String key) {
    final String spaced = key
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (Match match) => '${match.group(1)} ${match.group(2)}',
        )
        .replaceAll('_', ' ')
        .trim();
    if (spaced.isEmpty) {
      return 'Field';
    }
    return spaced
        .split(RegExp(r'\s+'))
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  String? _field(Map<String, dynamic>? map, String key) {
    if (map == null) {
      return null;
    }
    final dynamic value = map[key];
    if (value == null) {
      return null;
    }
    final String text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  String? _firstAvailableField(Map<String, dynamic>? map, List<String> keys) {
    for (final String key in keys) {
      final String? value = _field(map, key);
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              key,
              style: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _DriverAttachment {
  const _DriverAttachment({required this.fieldKey, required this.url});

  final String fieldKey;
  final String url;
}
