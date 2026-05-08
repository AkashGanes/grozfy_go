import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

class ThemeController extends ChangeNotifier {
  static const String _prefThemeMode = 'theme_mode';
  static const String _prefBackgroundColor = 'background_color';
  static const String _prefAccentColor = 'accent_color';

  ThemeMode _themeMode = ThemeMode.system;
  int _backgroundColorValue = 0xFFF0F4FA;
  int _accentColorValue = 0xFF1C4E80;

  ThemeMode get themeMode => _themeMode;
  Color get backgroundColor => Color(_backgroundColorValue);
  Color get accentColor => Color(_accentColorValue);

  ThemeData get lightTheme => AppTheme.getLightTheme(
    scaffoldBackgroundColor: backgroundColor,
    primaryColor: accentColor,
  );

  ThemeData get darkTheme => AppTheme.getDarkTheme(primaryColor: accentColor);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final int idx = prefs.getInt(_prefThemeMode) ?? ThemeMode.system.index;
    _themeMode = ThemeMode.values[idx.clamp(0, ThemeMode.values.length - 1)];
    _backgroundColorValue = prefs.getInt(_prefBackgroundColor) ?? 0xFFF0F4FA;
    _accentColorValue = prefs.getInt(_prefAccentColor) ?? 0xFF1C4E80;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefThemeMode, mode.index);
    notifyListeners();
  }

  Future<void> setBackgroundColor(Color color) async {
    _backgroundColorValue = color.toARGB32();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefBackgroundColor, _backgroundColorValue);
    notifyListeners();
  }

  Future<void> setAccentColor(Color color) async {
    _accentColorValue = color.toARGB32();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefAccentColor, _accentColorValue);
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    _themeMode = ThemeMode.system;
    _backgroundColorValue = 0xFFF0F4FA;
    _accentColorValue = 0xFF1C4E80;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefThemeMode, ThemeMode.system.index);
    await prefs.setInt(_prefBackgroundColor, _backgroundColorValue);
    await prefs.setInt(_prefAccentColor, _accentColorValue);
    notifyListeners();
  }
}
