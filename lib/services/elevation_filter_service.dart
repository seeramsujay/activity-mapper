import 'dart:math';

/// Kalman & Savitzky-Golay digital filter algorithms for GPS altitude/elevation smoothing.
///
/// Cleans raw, noisy GPS barometric/satellite altitude readings and eliminates false elevation
/// spikes and noise without distorting genuine hill/mountain gradients.
class ElevationFilterService {
  static final ElevationFilterService instance = ElevationFilterService._init();

  ElevationFilterService._init();

  /// 1D Kalman filter state representation.
  double _q = 0.05; // Process noise covariance
  double _r = 4.0;  // Measurement noise covariance (GPS altitude typically has ~3-5m variance)
  double _x = 0.0;  // Value estimate
  double _p = 1.0;  // Estimation error covariance
  double _k = 0.0;  // Kalman gain
  bool _isInitialized = false;

  void reset() {
    _isInitialized = false;
    _p = 1.0;
    _x = 0.0;
  }

  /// Processes a single altitude measurement with real-time Kalman filtering.
  double filterSample(double measurement, {double accuracy = 4.0}) {
    _r = max(1.0, pow(accuracy / 2.0, 2).toDouble());

    if (!_isInitialized) {
      _x = measurement;
      _isInitialized = true;
      return _x;
    }

    // Prediction update
    _p = _p + _q;

    // Measurement update
    _k = _p / (_p + _r);
    _x = _x + _k * (measurement - _x);
    _p = (1.0 - _k) * _p;

    return _x;
  }

  /// Batch Savitzky-Golay 5-point quadratic polynomial filter for track elevation arrays.
  ///
  /// Coefficients for 5-point quadratic convolution: [-3, 12, 17, 12, -3] / 35.
  List<double> savitzkyGolaySmooth(List<double> values) {
    if (values.length < 5) return List<double>.from(values);

    final int n = values.length;
    final List<double> smoothed = List<double>.filled(n, 0.0);

    // Endpoints (linear fallback)
    smoothed[0] = values[0];
    smoothed[1] = (values[0] + values[1] + values[2]) / 3.0;
    smoothed[n - 2] = (values[n - 3] + values[n - 2] + values[n - 1]) / 3.0;
    smoothed[n - 1] = values[n - 1];

    // Inner points convolution
    for (int i = 2; i < n - 2; i++) {
      final double val = (-3.0 * values[i - 2] +
                          12.0 * values[i - 1] +
                          17.0 * values[i] +
                          12.0 * values[i + 1] -
                           3.0 * values[i + 2]) / 35.0;
      smoothed[i] = val;
    }

    return smoothed;
  }

  /// Batch pipeline combining forward-backward Kalman filtering with Savitzky-Golay smoothing.
  List<double> filterFullElevationProfile(List<double> altitudes) {
    if (altitudes.length < 3) return List<double>.from(altitudes);

    // 1. Forward Kalman pass
    reset();
    final List<double> forwardPass = [];
    for (final alt in altitudes) {
      forwardPass.add(filterSample(alt));
    }

    // 2. Backward Kalman pass (Rauch-Tung-Striebel inspired reverse smoothing)
    reset();
    final List<double> reverseInput = forwardPass.reversed.toList();
    final List<double> backwardPass = [];
    for (final alt in reverseInput) {
      backwardPass.add(filterSample(alt));
    }
    final List<double> dualKalman = backwardPass.reversed.toList();

    // 3. Savitzky-Golay polynomial smoothing
    return savitzkyGolaySmooth(dualKalman);
  }
}
