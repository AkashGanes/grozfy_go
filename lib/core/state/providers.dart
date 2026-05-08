import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_controller.dart';
import '../theme/theme_controller.dart';

final ChangeNotifierProvider<AppController> appControllerProvider =
    ChangeNotifierProvider<AppController>((Ref ref) {
      return AppController();
    });

final ChangeNotifierProvider<ThemeController> themeControllerProvider =
    ChangeNotifierProvider<ThemeController>((Ref ref) {
      final controller = ThemeController();
      controller.load();
      return controller;
    });
