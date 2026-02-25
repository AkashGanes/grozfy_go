import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_controller.dart';

final ChangeNotifierProvider<AppController> appControllerProvider =
    ChangeNotifierProvider<AppController>((Ref ref) {
      return AppController();
    });
