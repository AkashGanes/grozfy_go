import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

class ProfileImageValidator {
  static const int minDimension = 300;
  static const int maxDimension = 5000;
  static const double minAspectRatio = 0.75; // ~3:4 portrait tolerance
  static const double maxAspectRatio = 1.33; // ~4:3 landscape tolerance

  /// Returns a user-facing error string, or null if the image passes all checks.
  static Future<String?> validate(String filePath) async {
    final File file = File(filePath);
    if (!file.existsSync()) {
      return 'Selected image is unavailable. Please pick another image.';
    }

    final Size? size = await readDimensions(file);
    if (size == null) {
      return 'Unable to read this image. The file may be corrupted.';
    }

    final int w = size.width.toInt();
    final int h = size.height.toInt();

    if (w < minDimension || h < minDimension) {
      return 'Image is too small ($w×$h px). '
          'Minimum required size is $minDimension×$minDimension px.';
    }
    if (w > maxDimension || h > maxDimension) {
      return 'Image is too large ($w×$h px). '
          'Maximum allowed size is $maxDimension×$maxDimension px.';
    }

    final double ratio = size.width / size.height;
    if (ratio < minAspectRatio || ratio > maxAspectRatio) {
      return 'Image shape is not suitable for a profile photo. '
          'Please use a roughly square image (between 3:4 and 4:3 aspect ratio).';
    }

    return null;
  }

  /// Decodes only the image header to read pixel dimensions without loading the
  /// full bitmap into Flutter's rendering layer.
  static Future<Size?> readDimensions(File file) async {
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(
        await file.readAsBytes(),
      );
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ui.Image image = frame.image;
      final Size size = Size(image.width.toDouble(), image.height.toDouble());
      image.dispose();
      codec.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }
}
