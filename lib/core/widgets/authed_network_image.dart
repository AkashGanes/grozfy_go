import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class AuthedNetworkImage extends StatefulWidget {
  const AuthedNetworkImage({
    super.key,
    required this.url,
    required this.authHeaders,
    required this.size,
    this.fallback,
  });

  final String url;
  final Map<String, String> authHeaders;
  final double size;
  final Widget? fallback;

  static final Map<String, Uint8List> _cache = {};
  static void clearCache() => _cache.clear();

  @override
  State<AuthedNetworkImage> createState() => _AuthedNetworkImageState();
}

class _AuthedNetworkImageState extends State<AuthedNetworkImage> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final cached = AuthedNetworkImage._cache[widget.url];
    if (cached != null) {
      _bytes = cached;
    } else {
      _load();
    }
  }

  @override
  void didUpdateWidget(AuthedNetworkImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      final cached = AuthedNetworkImage._cache[widget.url];
      if (cached != null) {
        setState(() {
          _bytes = cached;
          _failed = false;
        });
      } else {
        setState(() {
          _bytes = null;
          _failed = false;
        });
        _load();
      }
    }
  }

  Future<void> _load() async {
    try {
      final response = await http
          .get(Uri.parse(widget.url), headers: widget.authHeaders)
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        AuthedNetworkImage._cache[widget.url] = response.bodyBytes;
        setState(() => _bytes = response.bodyBytes);
      } else {
        setState(() => _failed = true);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return Image.memory(
        _bytes!,
        fit: BoxFit.cover,
        width: widget.size,
        height: widget.size,
        errorBuilder: (context, e, s) =>
            widget.fallback ?? const Icon(Icons.person_rounded, size: 42),
      );
    }
    if (_failed) {
      return widget.fallback ?? const Icon(Icons.person_rounded, size: 42);
    }
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}
