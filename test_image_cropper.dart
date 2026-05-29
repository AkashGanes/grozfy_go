import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';

void main() async {
  final croppedFile = await ImageCropper().cropImage(
    sourcePath: 'path',
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: 'Cropper',
        toolbarColor: Colors.deepOrange,
        toolbarWidgetColor: Colors.white,
        initAspectRatio: CropAspectRatioPreset.original,
        lockAspectRatio: false,
      ),
      IOSUiSettings(
        title: 'Cropper',
      ),
    ],
  );
}
