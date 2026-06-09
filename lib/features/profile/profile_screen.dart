import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_cropper/image_cropper.dart';

import '../../core/constants/api_constants.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/providers.dart';
import '../../core/theme/app_theme.dart';
// import '../../core/utils/profile_image_validator.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/authed_network_image.dart';

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
  bool _expandBasicDetails = false;
  bool _expandLicenseDetails = false;
  bool _expandDrivingCategory = false;
  bool _expandAdditionalDetails = false;

  String t(String key) => ref.read(appControllerProvider).t(key);

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
        app.profile?.fullName ?? _field(driver, 'full_name') ?? t('driver');
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
      detailsSection = FrostCard(child: Text(t('no_driver_details_found')));
    } else {
      detailsStateKey = 'data';
      detailsSection = _buildDriverDetails(driver, app);
    }

    return AppShell(
      title: t('my_profile'),
      subtitle: t('driver_account'),
      scrollable: false,
      noBottomPadding: true,
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
                  serverImageUrl: app.serverProfileImageUrl,
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

  Widget _animatedEntry({required Widget child, required int delayMs}) {
    return child
        .animate(delay: Duration(milliseconds: delayMs))
        .fadeIn(duration: 420.ms, curve: Curves.easeOutCubic)
        .slideY(
          begin: 0.06,
          end: 0,
          duration: 420.ms,
          curve: Curves.easeOutCubic,
        );
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
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              app.fetchLoggedInEmployeeDriverProfile(forceRefresh: true);
            },
            icon: const Icon(Icons.refresh_rounded),
            label: Text(t('retry')),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverDetails(Map<String, dynamic> driver, dynamic app) {
    final Map<String, String> additionalFields = _additionalDriverFields(
      driver,
    );

    return FrostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _detailSection(
                title: t('basic_details'),
                subtitle: t('identity_and_contact_snapshot'),
                leadingIcon: Icons.badge_outlined,
                expanded: _expandBasicDetails,
                onToggle: () {
                  setState(() => _expandBasicDetails = !_expandBasicDetails);
                },
                child: Column(
                  children: [
                    _kv(t('full_name'), _field(driver, 'full_name') ?? '-'),
                    _kv(t('employee'), _field(driver, 'employee') ?? '-'),
                    _kv(t('cell_number'), _field(driver, 'cell_number') ?? '-'),
                    _kv(t('status'), _field(driver, 'status') ?? '-'),
                    _kv(t('address'), _field(driver, 'address') ?? '-'),
                  ],
                ),
              )
              .animate(delay: 40.ms)
              .fadeIn(duration: 300.ms)
              .slideY(begin: 0.08, end: 0),
          const SizedBox(height: 10),
          _detailSection(
                title: t('license_details'),
                subtitle: t('driving_license_and_document_info'),
                leadingIcon: Icons.assignment_ind_outlined,
                expanded: _expandLicenseDetails,
                onToggle: () {
                  setState(
                    () => _expandLicenseDetails = !_expandLicenseDetails,
                  );
                },
                child: Column(
                  children: [
                    _kv(
                      t('license_number'),
                      _field(driver, 'license_number') ?? '-',
                    ),
                    _kv(t('issue_date'), _field(driver, 'issuing_date') ?? '-'),
                    _kv(t('expiry_date'), _field(driver, 'expiry_date') ?? '-'),
                  ],
                ),
              )
              .animate(delay: 120.ms)
              .fadeIn(duration: 300.ms)
              .slideY(begin: 0.08, end: 0),
          const SizedBox(height: 10),
          _detailSection(
                title: t('driving_license_category'),
                subtitle: t('allowed_vehicle_classes'),
                leadingIcon: Icons.category_outlined,
                expanded: _expandDrivingCategory,
                onToggle: () {
                  setState(
                    () => _expandDrivingCategory = !_expandDrivingCategory,
                  );
                },
                child: _licenseCategorySection(
                  driver['driving_license_category'],
                ),
              )
              .animate(delay: 180.ms)
              .fadeIn(duration: 300.ms)
              .slideY(begin: 0.08, end: 0),
          const SizedBox(height: 10),
          _detailSection(
                title: t('additional_driver_details'),
                subtitle: t('extra_fields_from_your_driver_doctype'),
                leadingIcon: Icons.description_outlined,
                expanded: _expandAdditionalDetails,
                onToggle: () {
                  setState(
                    () => _expandAdditionalDetails = !_expandAdditionalDetails,
                  );
                },
                child: _additionalDetailsSection(additionalFields),
              )
              .animate(delay: 220.ms)
              .fadeIn(duration: 300.ms)
              .slideY(begin: 0.08, end: 0),
          const SizedBox(height: 10),
          _buildDocumentsNavCard(app)
              .animate(delay: 260.ms)
              .fadeIn(duration: 300.ms)
              .slideY(begin: 0.08, end: 0),
        ],
      ),
    );
  }

  Widget _buildDocumentsNavCard(dynamic app) {
    final int uploadedCount = [
      app.existingLicenseUrl,
      app.existingAadharUrl,
      app.existingPanUrl,
    ].where((u) => (u ?? '').toString().isNotEmpty).length;

    final Color accent = const Color(0xFF2DBA9F);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pushNamed(AppRoutes.kycDocuments),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark
                ? scheme.surfaceContainerHighest
                : scheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.folder_special_outlined,
                  color: accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('kyc_documents'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      '$uploadedCount/3 documents uploaded — tap to manage',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: scheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _additionalDetailsSection(Map<String, String> fields) {
    if (fields.isEmpty) {
      return Text(t('no_additional_details'));
    }
    return Column(
      children: fields.entries
          .map((entry) => _kv(_labelFromKey(entry.key), entry.value))
          .toList(),
    );
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
    required String? serverImageUrl,
    required bool busy,
  }) {
    Widget avatarContent;

    if (imagePath != null && File(imagePath).existsSync()) {
      avatarContent = Image.file(
        File(imagePath),
        fit: BoxFit.cover,
        width: 88,
        height: 88,
        errorBuilder: (context, e, s) =>
            const Icon(Icons.person_rounded, size: 42),
      );
    } else if (serverImageUrl != null) {
      // Use auth-aware fetch — Frappe may redirect even public files through
      // the session middleware, so a bare NetworkImage often gets a login page.
      final app = ref.read(appControllerProvider);
      final String fullUrl = serverImageUrl.startsWith('http')
          ? serverImageUrl
          : '${ApiConstants.erpBaseUrl}$serverImageUrl';
      avatarContent = AuthedNetworkImage(
        url: fullUrl,
        authHeaders: app.buildAuthHeaders(),
        size: 88,
      );
    } else {
      avatarContent = const Icon(Icons.person_rounded, size: 42);
    }

    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return FrostCard(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: isDark
              ? scheme.primary.withValues(alpha: 0.12)
              : const Color(0xFFEAF5FF),
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
                  backgroundColor: isDark
                      ? scheme.surfaceContainerHighest
                      : Colors.white,
                  child: ClipOval(
                    child: SizedBox(
                      width: 88,
                      height: 88,
                      child: avatarContent,
                    ),
                  ),
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
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: scheme.surface, width: 2),
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
                Text(
                  t('verified_account'),
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
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
          Text(
            t('basic_information'),
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            t('edit_name_phone_number_email_and_profile_picture'),
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: t('name'),
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _mobileCtrl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: t('phone_number'),
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: t('email'),
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _savingBasicInfo ? null : _saveBasicInfo,
            icon: const Icon(Icons.save_outlined),
            label: Text(
              _savingBasicInfo ? t('saving') : t('save_basic_information'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    // Pick at full quality so we validate the original dimensions.
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    if (!mounted) return;

    CroppedFile? croppedFile;
    try {
      croppedFile = await ImageCropper().cropImage(
        sourcePath: file.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: t('crop_image'),
            toolbarColor: Theme.of(context).colorScheme.primary,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
          ),
          IOSUiSettings(title: t('crop_image')),
        ],
      );
    } on PlatformException catch (e) {
      if (mounted) showInfoSnack(context, 'Crop failed: ${e.message}');
      return;
    }
    if (croppedFile == null) return;
    if (!mounted) return;

    // Validate original dimensions and aspect ratio before any processing.
    // final String? dimensionError = await ProfileImageValidator.validate(
    //   croppedFile.path,
    // );
    // if (dimensionError != null) {
    //   if (mounted) showInfoSnack(context, dimensionError);
    //   return;
    // }

    // Compress before handing off to the upload flow.
    final Uint8List? compressed = await FlutterImageCompress.compressWithFile(
      croppedFile.path,
      minWidth: 1024,
      minHeight: 1024,
      quality: 80,
    );
    if (compressed == null) {
      if (mounted) {
        showInfoSnack(context, 'Failed to process image. Please try again.');
      }
      return;
    }
    final Directory tempDir = await getTemporaryDirectory();
    final File tempFile = File(
      '${tempDir.path}/profile_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await tempFile.writeAsBytes(compressed);

    if (!mounted) return;

    showInfoSnack(context, t('uploading_profile_image'));
    final String? error = await ref
        .read(appControllerProvider)
        .updateProfileImageAndSync(pickedPath: tempFile.path);
    if (!mounted) return;
    if (error != null) {
      showInfoSnack(context, error);
    } else {
      showInfoSnack(context, t('profile_image_updated'));
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
                title: Text(t('update_profile_image')),
                onTap: () => Navigator.of(context).pop('update'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(t('remove_profile_image')),
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

    showInfoSnack(context, t('removing_profile_image'));
    final String? error = await ref
        .read(appControllerProvider)
        .removeProfileImageAndSync();
    if (!mounted) {
      return;
    }
    if (error != null) {
      showInfoSnack(context, error);
    } else {
      showInfoSnack(context, t('profile_image_removed'));
    }
  }

  Future<void> _saveBasicInfo() async {
    setState(() => _savingBasicInfo = true);

    final String? error = await ref
        .read(appControllerProvider)
        .updateProfileAndSync(
          fullName: _nameCtrl.text.trim(),
          mobile: _mobileCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
        );

    if (!mounted) {
      return;
    }

    setState(() => _savingBasicInfo = false);
    if (error != null) {
      showInfoSnack(context, error);
    } else {
      showInfoSnack(context, t('basic_information_updated'));
    }
  }

  Widget _detailSection({
    required String title,
    required String subtitle,
    required IconData leadingIcon,
    required bool expanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: expanded
            ? scheme.surface
            : scheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: expanded
              ? scheme.primary.withValues(alpha: 0.25)
              : scheme.onSurface.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.03),
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
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.6),
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
                  tooltip: expanded ? t('collapse') : t('expand'),
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
                      ? Column(children: [const SizedBox(height: 12), child])
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
      return Text(t('no_category_data'));
    }

    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      children: categories.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: scheme.onSurface.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _categoryTitle(item),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                _kv(t('issue_date'), _field(item, 'issuing_date') ?? '-'),
                _kv(t('expiry_date'), _field(item, 'expiry_date') ?? '-'),
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
    return t('category');
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
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value, overflow: TextOverflow.ellipsis, maxLines: 2),
          ),
        ],
      ),
    );
  }
}
