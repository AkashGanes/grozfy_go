import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/state/providers.dart';
import '../../core/widgets/app_shell.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _mobileCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  bool _savingBasicInfo = false;
  bool _basicInfoInitialized = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(appControllerProvider)
          .fetchLoggedInEmployeeDriverProfile(forceRefresh: true);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
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

    return AppShell(
      title: 'My Profile',
      subtitle: 'Driver account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _profileHeader(name: displayName, imagePath: app.profileImagePath),
          const SizedBox(height: 12),
          _basicInformationSection(app),
          const SizedBox(height: 12),
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
          else if (driver == null || driver.isEmpty)
            const FrostCard(
              child: Text('No driver details found for this login account.'),
            )
          else
            FrostCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    onTap: (_) => setState(() {}),
                    tabs: const [
                      Tab(text: 'Basic Details'),
                      Tab(text: 'License Details'),
                      Tab(text: 'Driving License Category'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _tabContent(driver),
                ],
              ),
            ),
        ],
      ),
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

  Widget _profileHeader({required String name, required String? imagePath}) {
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
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1AB36A),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 14,
                      color: Colors.white,
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
            const Text(
              'Verified Account',
              style: TextStyle(color: Colors.black54),
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
          OutlinedButton.icon(
            onPressed: _savingBasicInfo ? null : _pickImage,
            icon: const Icon(Icons.image_outlined),
            label: const Text('Update Profile Picture'),
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
    await ref.read(appControllerProvider).setProfileImagePath(file.path);
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

  Widget _tabContent(Map<String, dynamic> driver) {
    switch (_tabController.index) {
      case 0:
        return Column(
          children: [
            _kv('Full Name', _field(driver, 'full_name') ?? '-'),
            _kv('Employee', _field(driver, 'employee') ?? '-'),
            _kv('Cell Number', _field(driver, 'cell_number') ?? '-'),
            _kv('Status', _field(driver, 'status') ?? '-'),
            _kv('Address', _field(driver, 'address') ?? '-'),
          ],
        );
      case 1:
        return Column(
          children: [
            _kv('License Number', _field(driver, 'license_number') ?? '-'),
            _kv('Issue Date', _field(driver, 'issuing_date') ?? '-'),
            _kv('Expiry Date', _field(driver, 'expiry_date') ?? '-'),
            _kv('Aadhar', _field(driver, 'custom_aadhar') ?? '-'),
          ],
        );
      case 2:
        return _licenseCategorySection(driver['driving_license_category']);
      default:
        return const SizedBox.shrink();
    }
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
