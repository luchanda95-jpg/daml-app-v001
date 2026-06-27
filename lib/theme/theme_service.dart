import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Key used to store the theme preference in SharedPreferences.
const String themePreferenceKey = 'theme_preference';

class ThemeService extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  
  // Set to true once the theme preference has been loaded from storage.
  bool _isInitialized = false;

  ThemeService() {
    // Immediately start loading theme preference in the constructor
    loadThemePreference(); 
  }

  ThemeMode get themeMode => _themeMode;
  bool get isInitialized => _isInitialized;

  /// Loads the theme mode from SharedPreferences.
  /// Made public so that consumers (like SplashDecider) can explicitly await initialization.
  Future<void> loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final String? themeString = prefs.getString(themePreferenceKey);

    if (themeString != null) {
      _themeMode = _getThemeModeFromString(themeString);
    } else {
      // Default theme is system (device setting)
      _themeMode = ThemeMode.system;
    }
    _isInitialized = true;
    notifyListeners();
  }

  /// Sets a new theme mode and saves it.
  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;

    _themeMode = mode;
    _saveThemePreference(mode);
    notifyListeners();
  }

  /// Toggles between light, dark, and system modes (e.g., for a toggle button).
  void toggleTheme() {
    ThemeMode newMode;
    switch (_themeMode) {
      case ThemeMode.system:
        newMode = ThemeMode.light;
        break;
      case ThemeMode.light:
        newMode = ThemeMode.dark;
        break;
      case ThemeMode.dark:
        newMode = ThemeMode.system;
        break;
    }
    setThemeMode(newMode);
  }

  // --- Utility Methods (kept private as they are internal) ---

  Future<void> _saveThemePreference(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(themePreferenceKey, mode.name);
  }

  ThemeMode _getThemeModeFromString(String themeString) {
    return ThemeMode.values.firstWhere(
      (e) => e.name == themeString,
      orElse: () => ThemeMode.system, // Default to system if string is invalid
    );
  }
}
