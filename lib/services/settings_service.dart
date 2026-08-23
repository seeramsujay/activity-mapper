import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

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

  Future<File> _getSettingsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/settings.json');
  }

  /// Loads persisted settings from disk on app launch.
  Future<void> loadSettings() async {
    try {
      final file = await _getSettingsFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        if (map.containsKey('themeMode')) {
          _themeMode = AppThemeMode.values.firstWhere(
            (e) => e.name == map['themeMode'],
            orElse: () => AppThemeMode.softNight,
          );
        }
        if (map.containsKey('accentColor')) {
          _accentColor = AccentColorChoice.values.firstWhere(
            (e) => e.name == map['accentColor'],
            orElse: () => AccentColorChoice.emberOrange,
          );
        }
        if (map.containsKey('recordProfile')) {
          _recordProfile = RecordProfile.values.firstWhere(
            (e) => e.name == map['recordProfile'],
            orElse: () => RecordProfile.general,
          );
        }
        if (map.containsKey('coordFormat')) {
          _coordFormat = CoordFormat.values.firstWhere(
            (e) => e.name == map['coordFormat'],
            orElse: () => CoordFormat.decimal,
          );
        }
        if (map.containsKey('chartXAxis')) {
          _chartXAxis = ChartXAxis.values.firstWhere(
            (e) => e.name == map['chartXAxis'],
            orElse: () => ChartXAxis.distance,
          );
        }
        _gpsSamplingRateMs = map['gpsSamplingRateMs'] ?? _gpsSamplingRateMs;
        _minDistanceFilter = (map['minDistanceFilter'] as num?)?.toDouble() ?? _minDistanceFilter;
        _maxAccuracyFilter = (map['maxAccuracyFilter'] as num?)?.toDouble() ?? _maxAccuracyFilter;
        _extraFiltering = map['extraFiltering'] ?? _extraFiltering;
        _autoMarkStops = map['autoMarkStops'] ?? _autoMarkStops;
        _confirmStopRecording = map['confirmStopRecording'] ?? _confirmStopRecording;
        _hapticsEnabled = map['hapticsEnabled'] ?? _hapticsEnabled;
        _audioAlarmsEnabled = map['audioAlarmsEnabled'] ?? _audioAlarmsEnabled;
        _useImperialUnits = map['useImperialUnits'] ?? _useImperialUnits;
        _mapTileSource = map['mapTileSource'] ?? _mapTileSource;
        _showHudMediaController = map['showHudMediaController'] ?? _showHudMediaController;
        _autoPauseCyclingMusic = map['autoPauseCyclingMusic'] ?? _autoPauseCyclingMusic;
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error loading settings: $e");
    }
  }

  Future<void> _saveSettings() async {
    try {
      final file = await _getSettingsFile();
      final map = {
        'themeMode': _themeMode.name,
        'accentColor': _accentColor.name,
        'recordProfile': _recordProfile.name,
        'coordFormat': _coordFormat.name,
        'chartXAxis': _chartXAxis.name,
        'gpsSamplingRateMs': _gpsSamplingRateMs,
        'minDistanceFilter': _minDistanceFilter,
        'maxAccuracyFilter': _maxAccuracyFilter,
        'extraFiltering': _extraFiltering,
        'autoMarkStops': _autoMarkStops,
        'confirmStopRecording': _confirmStopRecording,
        'hapticsEnabled': _hapticsEnabled,
        'audioAlarmsEnabled': _audioAlarmsEnabled,
        'useImperialUnits': _useImperialUnits,
        'mapTileSource': _mapTileSource,
        'showHudMediaController': _showHudMediaController,
        'autoPauseCyclingMusic': _autoPauseCyclingMusic,
      };
      await file.writeAsString(jsonEncode(map), flush: true);
    } catch (e) {
      debugPrint("Error saving settings: $e");
    }
  }

  bool isLightMode(BuildContext context) {
    if (_themeMode == AppThemeMode.light || _themeMode == AppThemeMode.highContrastDaylight) {
      return true;
    }
    if (_themeMode == AppThemeMode.system) {
      final Brightness systemBrightness = MediaQuery.maybeOf(context)?.platformBrightness ?? Brightness.dark;
      return systemBrightness == Brightness.light;
    }
    return false;
  }

  void setShowHudMediaController(bool enabled) {
    _showHudMediaController = enabled;
    _saveSettings();
    notifyListeners();
  }

  void setAutoPauseCyclingMusic(bool enabled) {
    _autoPauseCyclingMusic = enabled;
    _saveSettings();
    notifyListeners();
  }

  void setThemeMode(AppThemeMode mode) {
    _themeMode = mode;
    _saveSettings();
    notifyListeners();
  }

  void setAccentColor(AccentColorChoice choice) {
    _accentColor = choice;
    _saveSettings();
    notifyListeners();
  }

  void setRecordProfile(RecordProfile profile) {
    _recordProfile = profile;
    _gpsSamplingRateMs = profile.intervalMs;
    _minDistanceFilter = profile.minDistanceMeters;
    _maxAccuracyFilter = profile.maxAccuracyMeters;
    _saveSettings();
    notifyListeners();
  }

  void setCoordFormat(CoordFormat format) {
    _coordFormat = format;
    _saveSettings();
    notifyListeners();
  }

  void setChartXAxis(ChartXAxis axis) {
    _chartXAxis = axis;
    _saveSettings();
    notifyListeners();
  }

  void setGpsSamplingRate(int ms) {
    _gpsSamplingRateMs = ms;
    _saveSettings();
    notifyListeners();
  }

  void setMinDistanceFilter(double meters) {
    _minDistanceFilter = meters;
    _saveSettings();
    notifyListeners();
  }

  void setMaxAccuracyFilter(double meters) {
    _maxAccuracyFilter = meters;
    _saveSettings();
    notifyListeners();
  }

  void setExtraFiltering(bool enabled) {
    _extraFiltering = enabled;
    _saveSettings();
    notifyListeners();
  }

  void setAutoMarkStops(bool enabled) {
    _autoMarkStops = enabled;
    _saveSettings();
    notifyListeners();
  }

  void setConfirmStopRecording(bool enabled) {
    _confirmStopRecording = enabled;
    _saveSettings();
    notifyListeners();
  }

  void setHapticsEnabled(bool enabled) {
    _hapticsEnabled = enabled;
    _saveSettings();
    notifyListeners();
  }

  void setAudioAlarmsEnabled(bool enabled) {
    _audioAlarmsEnabled = enabled;
    _saveSettings();
    notifyListeners();
  }

  void setUseImperialUnits(bool imperial) {
    _useImperialUnits = imperial;
    _saveSettings();
    notifyListeners();
  }

  void setMapTileSource(String url) {
    _mapTileSource = url;
    _saveSettings();
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

