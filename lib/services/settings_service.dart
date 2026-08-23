import 'package:flutter/material.dart';

enum AppThemeMode {
  softNight,
  highContrastOled,
  highContrastDaylight,
  light,
  system,
}

enum CoordFormat {
  decimal,
  dms,
}

enum ChartXAxis {
  distance,
  duration,
}

enum RecordProfile {
  general('General', 1000, 10.0, 50.0),
  running('Running / Fitness', 1000, 5.0, 30.0),
  cycling('Cycling / Fast', 1000, 15.0, 50.0),
  hiking('Hiking / Trek', 5000, 20.0, 75.0),
  batterySave('Ultra Battery Save', 15000, 30.0, 100.0);

  final String label;
  final int intervalMs;
  final double minDistanceMeters;
  final double maxAccuracyMeters;
  const RecordProfile(this.label, this.intervalMs, this.minDistanceMeters, this.maxAccuracyMeters);
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
  RecordProfile _recordProfile = RecordProfile.general;
  CoordFormat _coordFormat = CoordFormat.decimal;
  ChartXAxis _chartXAxis = ChartXAxis.distance;

  int _gpsSamplingRateMs = 1000;
  double _minDistanceFilter = 10.0;
  double _maxAccuracyFilter = 50.0;
  bool _extraFiltering = true;
  bool _autoMarkStops = true;
  bool _confirmStopRecording = true;
  bool _hapticsEnabled = true;
  bool _audioAlarmsEnabled = true;
  bool _useImperialUnits = false;
  String _mapTileSource = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  bool _showHudMediaController = true;
  bool _autoPauseCyclingMusic = true;

  AppThemeMode get themeMode => _themeMode;
  AccentColorChoice get accentColor => _accentColor;
  RecordProfile get recordProfile => _recordProfile;
  CoordFormat get coordFormat => _coordFormat;
  ChartXAxis get chartXAxis => _chartXAxis;

  int get gpsSamplingRateMs => _gpsSamplingRateMs;
  double get minDistanceFilter => _minDistanceFilter;
  double get maxAccuracyFilter => _maxAccuracyFilter;
  bool get extraFiltering => _extraFiltering;
  bool get autoMarkStops => _autoMarkStops;
  bool get confirmStopRecording => _confirmStopRecording;
  bool get hapticsEnabled => _hapticsEnabled;
  bool get audioAlarmsEnabled => _audioAlarmsEnabled;
  bool get useImperialUnits => _useImperialUnits;
  String get mapTileSource => _mapTileSource;
  bool get showHudMediaController => _showHudMediaController;
  bool get autoPauseCyclingMusic => _autoPauseCyclingMusic;

  void setShowHudMediaController(bool enabled) {
    _showHudMediaController = enabled;
    notifyListeners();
  }

  void setAutoPauseCyclingMusic(bool enabled) {
    _autoPauseCyclingMusic = enabled;
    notifyListeners();
  }

  void setThemeMode(AppThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  void setAccentColor(AccentColorChoice choice) {
    _accentColor = choice;
    notifyListeners();
  }

  void setRecordProfile(RecordProfile profile) {
    _recordProfile = profile;
    _gpsSamplingRateMs = profile.intervalMs;
    _minDistanceFilter = profile.minDistanceMeters;
    _maxAccuracyFilter = profile.maxAccuracyMeters;
    notifyListeners();
  }

  void setCoordFormat(CoordFormat format) {
    _coordFormat = format;
    notifyListeners();
  }

  void setChartXAxis(ChartXAxis axis) {
    _chartXAxis = axis;
    notifyListeners();
  }

  void setGpsSamplingRate(int ms) {
    _gpsSamplingRateMs = ms;
    notifyListeners();
  }

  void setMinDistanceFilter(double meters) {
    _minDistanceFilter = meters;
    notifyListeners();
  }

  void setMaxAccuracyFilter(double meters) {
    _maxAccuracyFilter = meters;
    notifyListeners();
  }

  void setExtraFiltering(bool enabled) {
    _extraFiltering = enabled;
    notifyListeners();
  }

  void setAutoMarkStops(bool enabled) {
    _autoMarkStops = enabled;
    notifyListeners();
  }

  void setConfirmStopRecording(bool enabled) {
    _confirmStopRecording = enabled;
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

  String formatCoordinates(double lat, double lng) {
    if (_coordFormat == CoordFormat.dms) {
      String toDms(double val, String posDir, String negDir) {
        final dir = val >= 0 ? posDir : negDir;
        final absVal = val.abs();
        final deg = absVal.floor();
        final minVal = (absVal - deg) * 60;
        final min = minVal.floor();
        final sec = ((minVal - min) * 60).toStringAsFixed(1);
        return '$deg°$min\'$sec"$dir';
      }
      return '${toDms(lat, 'N', 'S')}, ${toDms(lng, 'E', 'W')}';
    } else {
      final latDir = lat >= 0 ? 'N' : 'S';
      final lngDir = lng >= 0 ? 'E' : 'W';
      return '${lat.abs().toStringAsFixed(5)}° $latDir, ${lng.abs().toStringAsFixed(5)}° $lngDir';
    }
  }

  ThemeData getThemeData(BuildContext context) {
    final Brightness systemBrightness = MediaQuery.maybeOf(context)?.platformBrightness ?? Brightness.dark;
    final accent = _accentColor.color;

    if (_themeMode == AppThemeMode.highContrastDaylight) {
      // High Contrast Daylight - Maximum solar contrast with pitch black text on pure white & bold borders
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.light(
          primary: Colors.black,
          secondary: accent,
          surface: const Color(0xFFF0F2F5),
          onSurface: Colors.black,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.black, width: 2.0),
          ),
          color: Colors.white,
        ),
      );
    } else if (_themeMode == AppThemeMode.light) {
      // Light Mode - Balanced modern daylight
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
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
    } else if (_themeMode == AppThemeMode.highContrastOled) {
      // High Contrast OLED - True pure black (#000000) with ultra-bright neon accents
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.dark(
          primary: Colors.white,
          secondary: accent,
          surface: const Color(0xFF0C0C0C),
          onSurface: Colors.white,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF383838), width: 1.8),
          ),
          color: const Color(0xFF0C0C0C),
        ),
      );
    } else if (_themeMode == AppThemeMode.system && systemBrightness == Brightness.light) {
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
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
    } else {
      // Soft Night Mode (Default) - Warm, low-strain muted slate/charcoal tones (#0E1318)
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

