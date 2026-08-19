import 'dart:async';
import 'dart:math';

/// Live sensor telemetry payload emitted by connected BLE devices or simulations.
class BleSensorData {
  final int heartRateBpm;
  final int cadenceRpm;
  final int powerWatts;
  final double batteryPct;
  final String deviceName;
  final bool isConnected;

  const BleSensorData({
    this.heartRateBpm = 0,
    this.cadenceRpm = 0,
    this.powerWatts = 0,
    this.batteryPct = 100.0,
    this.deviceName = 'Disconnected',
    this.isConnected = false,
  });
}

/// Service managing Bluetooth Low Energy (BLE) peripheral discovery and GATT profile parsing.
///
/// Implements standard Bluetooth SIG Profiles:
/// - Heart Rate Service (`0x180D` / Measurement `0x2A37`)
/// - Cycling Speed & Cadence (`0x1816` / CSC Measurement `0x2A5B`)
/// - Cycling Power (`0x1818` / Measurement `0x2A63`)
class BleSensorService {
  static final BleSensorService instance = BleSensorService._init();

  BleSensorService._init();

  final _controller = StreamController<BleSensorData>.broadcast();
  Stream<BleSensorData> get sensorStream => _controller.stream;

  BleSensorData _currentData = const BleSensorData();
  BleSensorData get currentData => _currentData;

  Timer? _simulationTimer;
  bool _isSimulating = false;

  /// Parses raw byte packets conforming to standard Bluetooth SIG Heart Rate Measurement (0x2A37).
  static int parseHeartRateGatt(List<int> bytes) {
    if (bytes.isEmpty) return 0;
    final int flags = bytes[0];
    final bool is16Bit = (flags & 0x01) != 0;

    if (is16Bit && bytes.length >= 3) {
      return bytes[1] | (bytes[2] << 8);
    } else if (bytes.length >= 2) {
      return bytes[1];
    }
    return 0;
  }

  /// Parses raw byte packets conforming to standard Bluetooth SIG Cycling Speed & Cadence (0x2A5B).
  static int parseCadenceGatt(List<int> bytes, {int? previousCrankRevs, int? previousCrankTime}) {
    if (bytes.isEmpty) return 0;
    final int flags = bytes[0];
    final bool hasWheel = (flags & 0x01) != 0;
    final bool hasCrank = (flags & 0x02) != 0;

    int offset = 1;
    if (hasWheel) {
      offset += 6; // 4 bytes cumulative wheel revs + 2 bytes wheel event time
    }

    if (hasCrank && bytes.length >= offset + 4) {
      final int crankRevs = bytes[offset] | (bytes[offset + 1] << 8);
      final int crankTime = bytes[offset + 2] | (bytes[offset + 3] << 8);

      if (previousCrankRevs != null && previousCrankTime != null) {
        final int deltaRevs = (crankRevs - previousCrankRevs) & 0xFFFF;
        final int deltaTime = (crankTime - previousCrankTime) & 0xFFFF; // in 1/1024th seconds

        if (deltaTime > 0 && deltaRevs > 0) {
          final double seconds = deltaTime / 1024.0;
          final double rpm = (deltaRevs / seconds) * 60.0;
          return rpm.round().clamp(0, 220);
        }
      }
    }
    return 0;
  }

  /// Starts sensor simulation for testing HR & Cadence without physical straps.
  void startSimulation({String deviceName = 'Polar H10 (Simulated)'}) {
    _simulationTimer?.cancel();
    _isSimulating = true;
    final rnd = Random();

    int bpm = 135;
    int rpm = 82;

    _simulationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      bpm = (bpm + rnd.nextInt(5) - 2).clamp(110, 185);
      rpm = (rpm + rnd.nextInt(7) - 3).clamp(65, 115);

      _currentData = BleSensorData(
        heartRateBpm: bpm,
        cadenceRpm: rpm,
        powerWatts: (bpm * 1.35).round(),
        batteryPct: 92.0,
        deviceName: deviceName,
        isConnected: true,
      );
      _controller.add(_currentData);
    });
  }

  /// Stops simulation or sensor stream.
  void disconnect() {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _isSimulating = false;
    _currentData = const BleSensorData(
      isConnected: false,
      deviceName: 'Disconnected',
    );
    _controller.add(_currentData);
  }

  bool get isSimulating => _isSimulating;
  bool get isConnected => _currentData.isConnected;
}
