import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';

class ThemeSettings {
  final ThemeMode themeMode;
  final String fontFamily;
  final double fontSizeFactor;
  final Color seedColor;

  const ThemeSettings({
    this.themeMode = ThemeMode.system,
    this.fontFamily = 'Roboto',
    this.fontSizeFactor = 1.0,
    this.seedColor = Colors.indigo,
  });

  ThemeSettings copyWith({
    ThemeMode? themeMode,
    String? fontFamily,
    double? fontSizeFactor,
    Color? seedColor,
  }) {
    return ThemeSettings(
      themeMode: themeMode ?? this.themeMode,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSizeFactor: fontSizeFactor ?? this.fontSizeFactor,
      seedColor: seedColor ?? this.seedColor,
    );
  }

  ThemeData get lightTheme => AppTheme.light(
        fontFamily: fontFamily,
        fontSizeFactor: fontSizeFactor,
        seedColor: seedColor,
      );

  ThemeData get darkTheme => AppTheme.dark(
        fontFamily: fontFamily,
        fontSizeFactor: fontSizeFactor,
        seedColor: seedColor,
      );
}

class ThemeNotifier extends StateNotifier<ThemeSettings> {
  ThemeNotifier() : super(const ThemeSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIndex = prefs.getInt('themeMode') ?? 0;
    final font = prefs.getString('fontFamily') ?? 'Roboto';
    final size = prefs.getDouble('fontSizeFactor') ?? 1.0;
    // ignore: deprecated_member_use
    final colorValue = prefs.getInt('seedColor') ?? Colors.indigo.value;

    state = ThemeSettings(
      themeMode: ThemeMode.values[modeIndex],
      fontFamily: font,
      fontSizeFactor: size,
      seedColor: Color(colorValue),
    );
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', state.themeMode.index);
    await prefs.setString('fontFamily', state.fontFamily);
    await prefs.setDouble('fontSizeFactor', state.fontSizeFactor);
    // ignore: deprecated_member_use
    await prefs.setInt('seedColor', state.seedColor.value);
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _save();
  }

  void setFontFamily(String font) {
    state = state.copyWith(fontFamily: font);
    _save();
  }

  void setFontSizeFactor(double factor) {
    state = state.copyWith(fontSizeFactor: factor);
    _save();
  }

  void setSeedColor(Color color) {
    state = state.copyWith(seedColor: color);
    _save();
  }
}

final themeProvider =
    StateNotifierProvider<ThemeNotifier, ThemeSettings>((ref) {
  return ThemeNotifier();
});
