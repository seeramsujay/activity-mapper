import 'package:flutter/material.dart';

enum AppThemeMode {
  light,
  softNight,
  highContrast,
  system,
}

enum AccentColorChoice {
  emberOrange(Color(0xFFFF5722), 'Ember Orange'),
  electricBlue(Color(0xFF2563EB), 'Electric Blue'),
  emeraldGreen(Color(0xFF10B981), 'Emerald Green'),
  nightViolet(Color(0xFF8B5CF6), 'Night Violet'),
  cyberpunkYellow(Color(0xFFF59E0B), 'Solar Gold'),
  monochrome(Color(0xFF9CA3AF), 'Monochrome');

  final Color color;
  final String displayName;
  const AccentColorChoice(this.color, this.displayName);
}

class SettingsService extends ChangeNotifier {
  static final SettingsService instance = SettingsService._internal();
  SettingsService._internal();

  AppThemeMode _themeMode = AppThemeMode.softNight;
  AccentColorChoice _accentColor = AccentColorChoice.emberOrange;
  int _gpsSamplingRateMs = 1000;
  bool _hapticsEnabled = true;
  bool _audioAlarmsEnabled = true;
  bool _useImperialUnits = false;
  String _mapTileSource = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  AppThemeMode get themeMode => _themeMode;
  AccentColorChoice get accentColor => _accentColor;
  int get gpsSamplingRateMs => _gpsSamplingRateMs;
  bool get hapticsEnabled => _hapticsEnabled;
  bool get audioAlarmsEnabled => _audioAlarmsEnabled;
  bool get useImperialUnits => _useImperialUnits;
  String get mapTileSource => _mapTileSource;

  void setThemeMode(AppThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  void setAccentColor(AccentColorChoice choice) {
    _accentColor = choice;
    notifyListeners();
  }

  void setGpsSamplingRate(int ms) {
    _gpsSamplingRateMs = ms;
    notifyListeners();
  }

  void setHapticsEnabled(bool enabled) {
    _hapticsEnabled = enabled;
    notifyListeners();
  }

  void setAudioAlarmsEnabled(bool enabled) {
    _audioAlarmsEnabled = enabled;
    notifyListeners();
  }

  void setUseImperialUnits(bool imperial) {
    _useImperialUnits = imperial;
    notifyListeners();
  }

  void setMapTileSource(String url) {
    _mapTileSource = url;
    notifyListeners();
  }

  ThemeData getThemeData(BuildContext context) {
    final Brightness systemBrightness = MediaQuery.maybeOf(context)?.platformBrightness ?? Brightness.dark;
    final bool isDark;

    switch (_themeMode) {
      case AppThemeMode.light:
        isDark = false;
        break;
      case AppThemeMode.softNight:
      case AppThemeMode.highContrast:
        isDark = true;
        break;
      case AppThemeMode.system:
        isDark = systemBrightness == Brightness.dark;
        break;
    }

    final accent = _accentColor.color;

    if (!isDark) {
      // Light Mode - Crisp, clean, high readability in sun
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF9FAFB),
        colorScheme: ColorScheme.light(
          primary: const Color(0xFF111827),
          secondary: accent,
          surface: Colors.white,
          onSurface: const Color(0xFF111827),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE5E7EB), width: 1.5),
          ),
          color: Colors.white,
        ),
      );
    } else if (_themeMode == AppThemeMode.highContrast) {
      // High Contrast OLED - True pure black (#000000) with ultra-bright neon accents
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.dark(
          primary: Colors.white,
          secondary: accent,
          surface: const Color(0xFF0A0A0A),
          onSurface: Colors.white,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF333333), width: 1.5),
          ),
          color: const Color(0xFF0A0A0A),
        ),
      );
    } else {
      // Soft Night Mode - Warm, low-strain muted slate/charcoal tones (#0E1318)
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0E1318),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFFE2E8F0),
          secondary: accent,
          surface: const Color(0xFF161C24),
          onSurface: const Color(0xFFE2E8F0),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF242F3E), width: 1.2),
          ),
          color: const Color(0xFF161C24),
        ),
      );
    }
  }
}
