import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 外观：跟随系统 / 浅色 / 深色，持久化到本机。
/// 深色为 OLED 纯黑（#000000），避免大面积灰雾。
class ThemeController extends ChangeNotifier {
  ThemeController();

  static const _prefsKey = 'theme_mode';
  static const _seed = Color(0xFF1B5E20);
  static const _seedDark = Color(0xFF2E7D32);
  static const _oledBlack = Color(0xFF000000);
  static const _oledCard = Color(0xFF121212);
  static const _lightScaffold = Color(0xFFF2F3F5);

  ThemeMode _mode = ThemeMode.system;
  bool _ready = false;

  ThemeMode get mode => _mode;
  bool get ready => _ready;

  String get modeLabel {
    switch (_mode) {
      case ThemeMode.system:
        return '跟随系统';
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    _mode = _parse(raw) ?? ThemeMode.system;
    _ready = true;
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _encode(mode));
  }

  static ThemeMode? _parse(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return null;
    }
  }

  static String _encode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static ThemeData lightTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: _lightScaffold,
      appBarTheme: AppBarTheme(
        backgroundColor: _lightScaffold,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: scheme.primaryContainer,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
    );
  }

  static ThemeData darkTheme() {
    final base = ColorScheme.fromSeed(
      seedColor: _seedDark,
      brightness: Brightness.dark,
    );
    final scheme = base.copyWith(
      surface: _oledBlack,
      surfaceContainerLowest: _oledBlack,
      surfaceContainerLow: _oledCard,
      surfaceContainer: _oledCard,
      surfaceContainerHigh: const Color(0xFF1A1A1A),
      surfaceContainerHighest: const Color(0xFF1E1E1E),
      outlineVariant: const Color(0xFF2A2A2A),
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _oledBlack,
      canvasColor: _oledBlack,
      appBarTheme: const AppBarTheme(
        backgroundColor: _oledBlack,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: _oledBlack,
        elevation: 0,
      ),
      dialogTheme: const DialogThemeData(backgroundColor: _oledCard),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: _oledCard),
      cardTheme: CardThemeData(
        color: _oledCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFF2A2A2A)),
        ),
      ),
    );
  }
}
