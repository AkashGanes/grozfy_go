import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_auth_service.dart';

final localAuthServiceProvider = Provider<LocalAuthService>(
  (ref) => LocalAuthService(),
);

// ── App lock enabled ─────────────────────────────────────────────────────────

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

// ── Runtime locked state ─────────────────────────────────────────────────────

class _AppLockedNotifier extends StateNotifier<bool> {
  _AppLockedNotifier() : super(false);

  void lock() => state = true;
  void unlock() => state = false;
}

final appLockedProvider = StateNotifierProvider<_AppLockedNotifier, bool>(
  (ref) => _AppLockedNotifier(),
);

// ── Auto-lock duration ───────────────────────────────────────────────────────
// Index into autoLockOptions. 0 = lock immediately on every background.

const autoLockOptions = <String>[
  'Immediately',
  '30 sec',
  '1 min',
  '5 min',
  '15 min',
];

const autoLockDurations = <Duration?>[
  null,                        // immediately
  Duration(seconds: 30),
  Duration(minutes: 1),
  Duration(minutes: 5),
  Duration(minutes: 15),
];

class _AutoLockIndexNotifier extends StateNotifier<int> {
  _AutoLockIndexNotifier() : super(0);

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getInt('auto_lock_index') ?? 0;
  }

  Future<void> setIndex(int index) async {
    state = index;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('auto_lock_index', index);
  }
}

final autoLockIndexProvider =
    StateNotifierProvider<_AutoLockIndexNotifier, int>(
  (ref) => _AutoLockIndexNotifier(),
);

/// Returns the Duration threshold (null = lock immediately every time).
Duration? autoLockThreshold(int index) => autoLockDurations[index];

// ── Biometric-only toggle ────────────────────────────────────────────────────
// When true, only biometric auth is accepted (no PIN fallback).

class _BiometricOnlyNotifier extends StateNotifier<bool> {
  _BiometricOnlyNotifier() : super(false);

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('biometric_only') ?? false;
  }

  Future<void> toggle(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometric_only', value);
  }
}

final biometricOnlyProvider =
    StateNotifierProvider<_BiometricOnlyNotifier, bool>(
  (ref) => _BiometricOnlyNotifier(),
);
