import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/api_constants.dart';
import '../../core/state/providers.dart';
import '../../core/theme/app_theme.dart';
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
    _syncBasicInfoFromState(app);

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
      scrollable: false,
      child: RefreshIndicator(
        onRefresh: _refreshProfile,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
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
        ),
      ),
    );
  }

  Future<void> _refreshProfile() async {
    final app = ref.read(appControllerProvider);
    await app.fetchLoggedInEmployeeDriverProfile(forceRefresh: true);
    if (!mounted) {
      return;
    }
    setState(() {
      _syncBasicInfoFromState(app, force: true);
    });
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppTheme.oceanBlue.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                )
                    .animate(onPlay: (controller) => controller.repeat())
                    .shimmer(
                      duration: 1200.ms,
                      color: AppTheme.oceanBlue.withValues(alpha: 0.08),
                    ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 150,
                        height: 18,
                        decoration: BoxDecoration(
                          color: AppTheme.oceanBlue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      )
                          .animate(onPlay: (controller) => controller.repeat())
                          .shimmer(
                            duration: 1200.ms,
                            color: AppTheme.oceanBlue.withValues(alpha: 0.08),
                          ),
                      const SizedBox(height: 8),
                      Container(
                        width: 100,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppTheme.oceanBlue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      )
                          .animate(onPlay: (controller) => controller.repeat())
                          .shimmer(
                            duration: 1200.ms,
                            color: AppTheme.oceanBlue.withValues(alpha: 0.04),
                          ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              height: 14,
              decoration: BoxDecoration(
                color: AppTheme.oceanBlue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(6),
              ),
            )
                .animate(onPlay: (controller) => controller.repeat())
                .shimmer(
                  duration: 1200.ms,
                  color: AppTheme.oceanBlue.withValues(alpha: 0.06),
                ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              height: 14,
              decoration: BoxDecoration(
                color: AppTheme.oceanBlue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(6),
              ),
            )
                .animate(onPlay: (controller) => controller.repeat())
                .shimmer(
                  duration: 1200.ms,
                  color: AppTheme.oceanBlue.withValues(alpha: 0.06),
                ),
          ],
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
            title: 'KYC Documents',
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
          onTap: () => _showAttachmentActions(item),
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
                    child: item.isImage
                        ? _attachmentImage(
                            url: item.url,
                            fit: BoxFit.cover,
                            primaryHeaders: primaryHeaders,
                            fallbackHeaders: fallbackHeaders,
                          )
                        : Container(
                            color: const Color(0xFFF4F6F9),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.insert_drive_file_outlined,
                              color: Colors.black54,
                              size: 30,
                            ),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    item.displayName,
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

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) {
          return Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text(_labelFromKey(item.fieldKey)),
            ),
            body: Center(
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
          );
        },
      ),
    );
  }

  Future<void> _openAttachment(_DriverAttachment item) async {
    if (item.isImage) {
      _showAttachmentPreview(item);
      return;
    }

    await _openDocumentAttachment(item);
  }

  Future<void> _showAttachmentActions(_DriverAttachment item) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.isImage)
                ListTile(
                  leading: const Icon(Icons.visibility_outlined),
                  title: const Text('Preview'),
                  onTap: () => Navigator.of(context).pop('preview'),
                )
              else
                ListTile(
                  leading: const Icon(Icons.open_in_new_rounded),
                  title: const Text('Open'),
                  onTap: () => Navigator.of(context).pop('open'),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }

    if (action == 'preview') {
      _showAttachmentPreview(item);
      return;
    }
    if (action == 'open') {
      await _openAttachment(item);
      return;
    }
  }

  Future<void> _openDocumentAttachment(_DriverAttachment item) async {
    final app = ref.read(appControllerProvider);
    final Map<String, String> primaryHeaders = _primaryAttachmentHeaders(app);
    final Map<String, String> fallbackHeaders = <String, String>{
      'Authorization': 'token ${ApiConstants.apiKey}:${ApiConstants.apiSecret}',
      'Accept': '*/*',
    };

    try {
      final Uint8List bytes = await _fetchAttachmentBytes(
        item.url,
        primaryHeaders: primaryHeaders,
        fallbackHeaders: fallbackHeaders,
      );
      final Directory dir = await _attachmentDownloadDir();
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final String name = _downloadFileName(item.url);
      final String path =
          '${dir.path}/${DateTime.now().millisecondsSinceEpoch}_$name';
      final File file = File(path);
      await file.writeAsBytes(bytes, flush: true);

      final bool launched = await launchUrl(
        Uri.file(file.path),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) {
        return;
      }
      if (launched) {
        showInfoSnack(context, 'Opened document');
        return;
      }
    } catch (_) {
      // Fallback below
    }

    final Uri? uri = Uri.tryParse(item.url);
    if (uri == null) {
      if (mounted) {
        showInfoSnack(context, 'Invalid attachment URL');
      }
      return;
    }
    final bool launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      showInfoSnack(context, 'Unable to open document');
    }
  }

  Future<Directory> _attachmentDownloadDir() async {
    final Directory? downloads = await getDownloadsDirectory();
    if (downloads != null) {
      return Directory('${downloads.path}/attachments');
    }
    final Directory docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/attachments');
  }

  Future<Uint8List> _fetchAttachmentBytes(
    String url, {
    required Map<String, String> primaryHeaders,
    required Map<String, String> fallbackHeaders,
  }) async {
    final Uri uri = Uri.parse(url);
    final http.Response first = await http
        .get(uri, headers: primaryHeaders)
        .timeout(const Duration(seconds: 20));
    if (_isDownloadableResponse(first)) {
      return first.bodyBytes;
    }
    final http.Response second = await http
        .get(uri, headers: fallbackHeaders)
        .timeout(const Duration(seconds: 20));
    if (_isDownloadableResponse(second)) {
      return second.bodyBytes;
    }
    throw Exception('Download failed (HTTP ${second.statusCode})');
  }

  bool _isDownloadableResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return false;
    }
    if (response.bodyBytes.isEmpty) {
      return false;
    }
    final String contentType =
        response.headers['content-type']?.toLowerCase() ?? '';
    final String bodyText = String.fromCharCodes(
      response.bodyBytes.take(300),
    ).toLowerCase();
    if (contentType.contains('text/html') &&
        (bodyText.contains('<html') || bodyText.contains('login'))) {
      return false;
    }
    return true;
  }

  String _downloadFileName(String url) {
    final Uri? parsed = Uri.tryParse(url);
    if (parsed == null || parsed.pathSegments.isEmpty) {
      return 'attachment.bin';
    }
    final String raw = parsed.pathSegments.last.trim();
    final String decoded = raw.isEmpty ? 'attachment.bin' : Uri.decodeComponent(raw);
    final String sanitized = decoded.replaceAll(RegExp(r'[^\w.\- ]'), '_');
    return sanitized.isEmpty ? 'attachment.bin' : sanitized;
  }

  void _syncBasicInfoFromState(dynamic app, {bool force = false}) {
    if (_basicInfoInitialized && !force) {
      return;
    }
    final Map<String, dynamic>? driver = app.loggedProfileDetails?.driver;
    _nameCtrl.text = app.profile?.fullName ?? _field(driver, 'full_name') ?? '';
    _mobileCtrl.text =
        app.profile?.mobile ?? _field(driver, 'cell_number') ?? '';
    _emailCtrl.text =
        app.profile?.email ??
        _field(driver, 'user_id') ??
        _field(driver, 'email') ??
        '';
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
                      onTap: busy ? null : _showProfileImageActions,
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
    final bool shouldUpload = await _confirmProfileImageUpload(file.path);
    if (!mounted || !shouldUpload) {
      return;
    }

    showInfoSnack(context, 'Uploading profile image...');
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

  Future<void> _showProfileImageActions() async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Update Profile Image'),
                onTap: () => Navigator.of(context).pop('update'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Remove Profile Image'),
                onTap: () => Navigator.of(context).pop('remove'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }

    if (action == 'update') {
      await _pickImage();
      return;
    }

    await ref.read(appControllerProvider).setProfileImagePath(null);
    if (!mounted) {
      return;
    }
    showInfoSnack(context, 'Profile image removed');
  }

  Future<bool> _confirmProfileImageUpload(String imagePath) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Upload Profile Image'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(imagePath),
                  width: 170,
                  height: 170,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 12),
              const Text('Do you want to upload this image?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Upload'),
            ),
          ],
        );
      },
    );
    return confirmed == true;
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
      if (value == null) {
        continue;
      }
      final String text = _displayDriverValue(value).trim();
      if (text.isEmpty || _looksLikeAttachmentValue(text, fieldKey: key)) {
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
      _collectAttachments(
        value: entry.value,
        fieldKey: entry.key,
        seen: seen,
        out: attachments,
      );
    }
    return attachments;
  }

  void _collectAttachments({
    required dynamic value,
    required String fieldKey,
    required Set<String> seen,
    required List<_DriverAttachment> out,
  }) {
    if (value == null) {
      return;
    }
    if (value is String) {
      final String raw = value.trim();
      if ((raw.startsWith('{') && raw.endsWith('}')) ||
          (raw.startsWith('[') && raw.endsWith(']'))) {
        try {
          final dynamic decoded = jsonDecode(raw);
          _collectAttachments(
            value: decoded,
            fieldKey: fieldKey,
            seen: seen,
            out: out,
          );
          return;
        } catch (_) {
          // fall through and treat it as plain text
        }
      }
      if (_looksLikeAttachmentValue(raw, fieldKey: fieldKey)) {
        final String url = _normalizeAttachmentUrl(raw);
        if (seen.add(url)) {
          out.add(
            _DriverAttachment(
              fieldKey: fieldKey,
              url: url,
              isImage: _isImageAttachment(url),
            ),
          );
        }
      }
      return;
    }
    if (value is List) {
      for (int i = 0; i < value.length; i++) {
        _collectAttachments(
          value: value[i],
          fieldKey: '${fieldKey}_${i + 1}',
          seen: seen,
          out: out,
        );
      }
      return;
    }
    if (value is Map) {
      for (final MapEntry<dynamic, dynamic> entry in value.entries) {
        final String nestedKey = entry.key.toString().trim();
        _collectAttachments(
          value: entry.value,
          fieldKey: nestedKey.isEmpty ? fieldKey : nestedKey,
          seen: seen,
          out: out,
        );
      }
      return;
    }
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

  bool _looksLikeAttachmentValue(String value, {required String fieldKey}) {
    final String lowered = value.toLowerCase();
    if (lowered.isEmpty) {
      return false;
    }
    final bool hasFilePath =
        lowered.contains('/files/') ||
        lowered.startsWith('/files/') ||
        lowered.startsWith('http://') ||
        lowered.startsWith('https://');
    final bool hasAttachmentExtension = RegExp(
      r'\.(jpg|jpeg|png|webp|gif|bmp|pdf|doc|docx|xls|xlsx|csv|txt)(\?|$)',
      caseSensitive: false,
    ).hasMatch(lowered);
    final String key = fieldKey.toLowerCase();
    final bool keyHintsAttachment =
        key.contains('attach') ||
        key.contains('attachment') ||
        key.contains('file') ||
        key.contains('image') ||
        key.contains('photo') ||
        key.contains('document');
    final bool keyHintWithPathLikeValue =
        keyHintsAttachment && (lowered.contains('/') || lowered.contains('.'));
    return hasFilePath || hasAttachmentExtension || keyHintWithPathLikeValue;
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

  bool _isImageAttachment(String url) {
    final String lowered = url.toLowerCase();
    return lowered.contains('.jpg') ||
        lowered.contains('.jpeg') ||
        lowered.contains('.png') ||
        lowered.contains('.webp') ||
        lowered.contains('.gif') ||
        lowered.contains('.bmp');
  }

  String _labelFromKey(String key) {
    final String spaced = key
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (Match match) => '${match.group(1)} ${match.group(2)}',
        )
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\bcustom\b', caseSensitive: false), ' ')
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

  String _displayDriverValue(dynamic value) {
    if (value == null) {
      return '';
    }
    if (value is String) {
      return value.trim();
    }
    if (value is num || value is bool) {
      return '$value';
    }
    if (value is List || value is Map) {
      try {
        return const JsonEncoder.withIndent('  ').convert(value);
      } catch (_) {
        return value.toString();
      }
    }
    return value.toString();
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
  const _DriverAttachment({
    required this.fieldKey,
    required this.url,
    required this.isImage,
  });

  final String fieldKey;
  final String url;
  final bool isImage;

  String get displayName {
    final String label = fieldKey
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\bcustom\b', caseSensitive: false), ' ')
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
    if (label.isNotEmpty) {
      return label;
    }
    final Uri? parsed = Uri.tryParse(url);
    if (parsed != null && parsed.pathSegments.isNotEmpty) {
      return parsed.pathSegments.last;
    }
    return 'Attachment';
  }
}
