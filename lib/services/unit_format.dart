import 'settings_service.dart';

/// Formats distances, speeds, paces and elevations in the user's chosen unit system
/// (Settings → Imperial Units). All inputs are metric, as stored in the database.
class UnitFormat {
  UnitFormat._();

  static const double kmPerMile = 1.609344;
  static const double feetPerMeter = 3.28084;

  /// Whether imperial units (mi, mph, ft) are selected.
  static bool get imperial => SettingsService.instance.useImperialUnits;

  /// Distance unit label ("km" / "mi").
  static String get distanceUnit => imperial ? 'mi' : 'km';

  /// Converts kilometres to the display unit.
  static double distanceValue(double km) => imperial ? km / kmPerMile : km;

  /// e.g. "5.25 km" / "3.26 mi"; [upper] gives "KM" / "MI".
  static String distance(double km, {int decimals = 2, bool upper = false}) {
    final unit = upper ? distanceUnit.toUpperCase() : distanceUnit;
    return '${distanceValue(km).toStringAsFixed(decimals)} $unit';
  }

  /// Speed unit label ("km/h" / "mph").
  static String get speedUnit => imperial ? 'mph' : 'km/h';

  /// Converts km/h to the display unit.
  static double speedValue(double kmh) => imperial ? kmh / kmPerMile : kmh;

  /// e.g. "12.4 km/h" / "7.7 mph".
  static String speedKmh(double kmh, {int decimals = 1}) => '${speedValue(kmh).toStringAsFixed(decimals)} $speedUnit';

  /// Pace unit label ("/km" / "/mi").
  static String get paceUnit => imperial ? '/mi' : '/km';

  /// Pace as "m:ss" per display unit, or "--:--" when (nearly) stationary.
  static String paceFromMps(double mps) {
    if (mps <= 0.2) return '--:--';
    final secPerUnit = (imperial ? 1000.0 * kmPerMile : 1000.0) / mps;
    final min = secPerUnit ~/ 60;
    final sec = (secPerUnit % 60).round();
    if (min > 99) return '--:--';
    if (sec == 60) return '${min + 1}:00';
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  /// Average pace over a distance, as m'ss" per display unit (feed cards).
  static String paceFromDistance(double km, Duration duration) {
    if (km <= 0.05 || duration.inSeconds <= 0) return '--';
    final secPerUnit = duration.inSeconds / distanceValue(km);
    if (secPerUnit > 3600) return '>60m$paceUnit';
    final m = secPerUnit ~/ 60;
    final s = (secPerUnit % 60).round().toString().padLeft(2, '0');
    return "$m'$s\"$paceUnit";
  }

  /// Elevation, e.g. "920 m" / "3018 ft"; [sign] is prepended ("+" / "-").
  static String elevation(double meters, {String sign = ''}) =>
      imperial ? '$sign${(meters * feetPerMeter).toStringAsFixed(0)} ft' : '$sign${meters.toStringAsFixed(0)} m';

  /// Short distances (cue / accuracy), e.g. "120 m" / "394 ft".
  static String shortDistance(num meters) => imperial ? '${(meters * feetPerMeter).round()} ft' : '${meters.round()} m';
}
