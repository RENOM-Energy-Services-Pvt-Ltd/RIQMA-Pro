import 'package:flutter/material.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode {
    if (_themeMode == ThemeMode.system) {
      // You might want to access the platform dispatcher here if needed,
      // but for simple toggle logic, checking against ThemeMode.dark is often enough
      // or relying on the UI to switch.
      // However, for the switch state, we usually want explicit control.
      // Let's default to light for the switch if system, or handle it in the UI.
      return _themeMode == ThemeMode.dark;
    }
    return _themeMode == ThemeMode.dark;
  }

  void toggleTheme(bool isDark) {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }
}
