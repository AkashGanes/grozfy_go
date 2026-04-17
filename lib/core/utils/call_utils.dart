import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> makePhoneCall(
  BuildContext context,
  String phoneNumber, {
  String? label,
}) async {
  if (phoneNumber.isEmpty) {
    _showSnackBar(context, 'Phone number not available', isError: true);
    return;
  }

  final digits = phoneNumber.replaceAll(RegExp(r'\s+'), '');
  final uri = Uri.parse('tel:$digits');

  final status = await Permission.phone.request();

  if (status.isGranted) {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showSnackBar(context, 'Unable to open phone app', isError: true);
    }
  } else if (status.isDenied) {
    _showSnackBar(
      context,
      'Phone permission denied. Please enable in settings.',
      isError: true,
    );
    await openAppSettings();
  } else if (status.isPermanentlyDenied) {
    _showSnackBar(
      context,
      'Phone permission permanently denied. Please enable in settings.',
      isError: true,
    );
    await openAppSettings();
  }
}

void _showSnackBar(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red : null,
      duration: const Duration(seconds: 3),
    ),
  );
}

class CallButton extends StatelessWidget {
  const CallButton({
    super.key,
    required this.phoneNumber,
    this.label,
    this.size = 40,
    this.iconSize = 18,
  });

  final String phoneNumber;
  final String? label;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => makePhoneCall(context, phoneNumber, label: label),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFF4CAF50).withAlpha(77),
          ),
        ),
        child: Icon(
          Icons.phone_rounded,
          color: const Color(0xFF4CAF50),
          size: iconSize,
        ),
      ),
    );
  }
}

class CallButtonRow extends StatelessWidget {
  const CallButtonRow({
    super.key,
    required this.calls,
    this.buttonHeight = 48,
    this.spacing = 12,
  });

  final List<CallEntry> calls;
  final double buttonHeight;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < calls.length; i++) ...[
          Expanded(
            child: ElevatedButton.icon(
              onPressed: calls[i].phoneNumber.isEmpty
                  ? null
                  : () => makePhoneCall(
                        context,
                        calls[i].phoneNumber,
                        label: calls[i].label,
                      ),
              icon: Icon(
                calls[i].icon ?? Icons.call,
                size: 18,
              ),
              label: Text(
                calls[i].label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: buttonHeight / 2.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          if (i < calls.length - 1) SizedBox(width: spacing),
        ],
      ],
    );
  }
}

class CallEntry {
  const CallEntry({
    required this.phoneNumber,
    required this.label,
    this.icon,
  });

  final String phoneNumber;
  final String label;
  final IconData? icon;
}
