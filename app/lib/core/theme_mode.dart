// Owned by AppWand. The app's light/dark setting.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart' show defaultThemeMode, themeSwitch;

/// The theme mode in use: what the person picked with ThemeModeSetting (kept on
/// the device) when the app has the switch, otherwise AppWand's default.
/// Worked out in build, so a new default from AppWand shows on hot reload.
ThemeMode watchThemeMode(WidgetRef ref) {
  if (!themeSwitch) return defaultThemeMode;
  return ref.watch(themeChoiceProvider) ?? defaultThemeMode;
}

/// The person's own choice; null until they pick one.
final themeChoiceProvider = NotifierProvider<ThemeModeController, ThemeMode?>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode?> {
  static const String _key = 'theme_mode';
  static ThemeMode? _saved;

  /// Reads the saved choice; main() awaits it before runApp.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_key);
    _saved = ThemeMode.values.where((m) => m.name == name).firstOrNull;
  }

  @override
  ThemeMode? build() => _saved;

  Future<void> set(ThemeMode mode) async {
    state = mode;
    _saved = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}
