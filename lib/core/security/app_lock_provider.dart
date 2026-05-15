import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_auth_service.dart';

final localAuthServiceProvider = Provider<LocalAuthService>(
  (ref) => LocalAuthService(),
);

class _AppLockEnabledNotifier extends StateNotifier<bool> {
  _AppLockEnabledNotifier() : super(false);

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('app_lock_enabled') ?? false;
  }

  Future<void> toggle(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_lock_enabled', enabled);
  }
}

final appLockEnabledProvider =
    StateNotifierProvider<_AppLockEnabledNotifier, bool>(
  (ref) => _AppLockEnabledNotifier(),
);

class _AppLockedNotifier extends StateNotifier<bool> {
  _AppLockedNotifier() : super(false);

  void lock() => state = true;
  void unlock() => state = false;
}

final appLockedProvider = StateNotifierProvider<_AppLockedNotifier, bool>(
  (ref) => _AppLockedNotifier(),
);
