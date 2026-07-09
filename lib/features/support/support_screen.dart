import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/api_constants.dart';
import '../../core/services/secure_token_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/context_colors.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/app_toast.dart';

class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({super.key});

  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _feedbackController = TextEditingController();
  bool _submitting = false;
  XFile? _pickedImage;

  static const int _maxFileSizeBytes = 5 * 1024 * 1024; // 5 MB

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  // ── Auth headers ─────────────────────────────────────────────────────────

  Future<Map<String, String>> _authHeaders({bool withContentType = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final String? token = await SecureTokenStorage.read(
      SecureTokenStorage.accessToken,
    );
    final String tokenType =
        (await SecureTokenStorage.read(SecureTokenStorage.tokenType) ?? 'token')
            .trim();
    final String language =
        prefs.getString('language_code')?.trim().isNotEmpty == true
        ? prefs.getString('language_code')!.trim()
        : 'en';
    final Map<String, String> headers = {
      'Accept': 'application/json',
      'Accept-Language': language,
      if (withContentType) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': '$tokenType $token',
    };
    return headers;
  }

  // ── Image picking ─────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final original = await picker.pickImage(source: source);
    if (original == null || !mounted) return;

    final fileSize = await File(original.path).length();
    if (fileSize > _maxFileSizeBytes) {
      if (mounted) {
        AppToast.show(
          context,
          'Image exceeds 5 MB. Please choose a smaller image.',
        );
      }
      return;
    }

    final compressed = await FlutterImageCompress.compressWithFile(
      original.path,
      quality: 80,
    );
    if (compressed == null || !mounted) return;

    final tempDir = await getTemporaryDirectory();
    final tempFile = File(
      '${tempDir.path}/feedback_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await tempFile.writeAsBytes(compressed);

    if (mounted) setState(() => _pickedImage = XFile(tempFile.path));
  }

  void _showImageSourceSheet() {
    final theme = Theme.of(context);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: ctx.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 20),
            _sourceOption(
              ctx: ctx,
              icon: Icons.camera_alt_rounded,
              label: 'Take Photo',
              color: AppTheme.oceanBlue,
              onTap: () {
                Navigator.of(ctx).pop();
                _pickImage(ImageSource.camera);
              },
            ),
            const SizedBox(height: 10),
            _sourceOption(
              ctx: ctx,
              icon: Icons.photo_library_rounded,
              label: 'Choose from Gallery',
              color: AppTheme.mint,
              onTap: () {
                Navigator.of(ctx).pop();
                _pickImage(ImageSource.gallery);
              },
            ),
            if (_pickedImage != null) ...[
              const SizedBox(height: 10),
              _sourceOption(
                ctx: ctx,
                icon: Icons.delete_outline_rounded,
                label: 'Remove Image',
                color: ctx.danger,
                onTap: () {
                  Navigator.of(ctx).pop();
                  setState(() => _pickedImage = null);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sourceOption({
    required BuildContext ctx,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(ctx);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final driverName =
          prefs.getString('driver_name')?.trim() ?? 'Unknown Driver';

      // Step 1 — create the Issue
      final createResp = await http
          .post(
            Uri.parse(ApiConstants.issueList),
            headers: await _authHeaders(),
            body: jsonEncode({
              'subject': 'Driver Feedback — $driverName',
              'description': _feedbackController.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (!mounted) return;

      if (createResp.statusCode != 200 && createResp.statusCode != 201) {
        AppToast.show(context, 'Failed to submit feedback. Please try again.');
        return;
      }

      // Step 2 — upload image if one was selected
      if (_pickedImage != null) {
        final issueName = _parseIssueName(createResp.body);
        if (issueName != null) {
          await _uploadImage(_pickedImage!.path, issueName);
        }
      }

      if (!mounted) return;
      _feedbackController.clear();
      setState(() => _pickedImage = null);
      AppToast.show(context, 'Feedback submitted successfully.');
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, 'Network error. Please check your connection.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _parseIssueName(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      return decoded['data']?['name']?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _uploadImage(String filePath, String issueName) async {
    try {
      final uri = Uri.parse(
        '${ApiConstants.erpBaseUrl}/api/method/upload_file',
      );
      final headers = await _authHeaders(withContentType: false);
      final req = http.MultipartRequest('POST', uri)
        ..headers.addAll(headers)
        ..fields['doctype'] = 'Issue'
        ..fields['docname'] = issueName
        ..fields['is_private'] = '0'
        ..files.add(
          await http.MultipartFile.fromPath(
            'file',
            filePath,
            filename: 'feedback_$issueName.jpg',
          ),
        );
      await http.Response.fromStream(
        await req.send().timeout(const Duration(seconds: 60)),
      );
    } catch (_) {
      // Image upload failure is non-fatal — the Issue was already created.
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    return AppShell(
      title: 'Support',
      scrollable: false,
      padding: EdgeInsets.zero,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Hero header ───────────────────────────────────────────────
              _HeroHeader(isDark: isDark, primary: primary)
                  .animate()
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: -0.12, end: 0, duration: 400.ms),

              const SizedBox(height: 20),

              // ── Feedback card ─────────────────────────────────────────────
              FrostCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section label
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.edit_note_rounded,
                            color: primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Your Feedback',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Feedback text field
                    TextFormField(
                      controller: _feedbackController,
                      minLines: 5,
                      maxLines: 9,
                      textInputAction: TextInputAction.newline,
                      style: theme.textTheme.bodyMedium,
                      decoration: const InputDecoration(
                        hintText:
                            'Describe your feedback or issue in detail...',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your feedback before submitting.';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // Divider
                    Divider(
                      color: theme.colorScheme.outline.withValues(alpha: 0.2),
                      height: 1,
                    ),

                    const SizedBox(height: 16),

                    // Attachment section label
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.mint.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.attach_file_rounded,
                            color: AppTheme.mint,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Attachment',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Optional',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Image picker / preview
                    _pickedImage == null
                        ? _EmptyImagePicker(
                            onTap: _showImageSourceSheet,
                            isDark: isDark,
                          )
                        : _ImagePreview(
                            file: File(_pickedImage!.path),
                            onTap: _showImageSourceSheet,
                          ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(duration: 400.ms, delay: 100.ms)
                  .slideY(
                    begin: 0.1,
                    end: 0,
                    duration: 400.ms,
                    delay: 100.ms,
                  ),

              const SizedBox(height: 20),

              // ── Submit button ─────────────────────────────────────────────
              FilledButton(
                onPressed: _submitting ? null : _submit,
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
                child: _submitting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.send_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Submit Feedback'),
                        ],
                      ),
              )
                  .animate()
                  .fadeIn(duration: 400.ms, delay: 200.ms)
                  .slideY(
                    begin: 0.1,
                    end: 0,
                    duration: 400.ms,
                    delay: 200.ms,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.isDark, required this.primary});

  final bool isDark;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, primary.withValues(alpha: 0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'We\'re here to help',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Share your feedback or report an issue. Our team will review it shortly.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                    height: 1.4,
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

class _EmptyImagePicker extends StatelessWidget {
  const _EmptyImagePicker({required this.onTap, required this.isDark});

  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 110,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              size: 32,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap to attach an image',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Camera or gallery · Max 5 MB',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.file, required this.onTap});

  final File file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.file(
            file,
            width: double.infinity,
            height: 180,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_rounded, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text(
                    'Change',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
