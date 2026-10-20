import 'dart:math';

/// Types of turns and route navigation checkpoints.
enum TurnType {
  /// Travel straight.
  straight,

  /// Turn left.
  left,

  /// Turn sharp left (more than 70 degrees).
  sharpLeft,

  /// Turn right.
  right,

  /// Turn sharp right (more than 70 degrees).
  sharpRight,

  /// Perform a U-turn.
  uTurn,

  /// User has drifted off-route.
  offRoute,

  /// Target goal arrived.
  arrival
}

/// Represents a single navigation milestone cue generated along the route.
class RallyCue {
  /// The accumulated distance along the reference route in kilometers.
  final double distanceKm;

  /// The latitude coordinate of the cue.
  final double lat;

  /// The longitude coordinate of the cue.
  final double lng;

  /// The type of checkpoint or turn instruction.
  final TurnType type;

  /// Human-readable instruction label (e.g. "SHARP LEFT").
  final String description;

  /// Creates a new [RallyCue] instance.
  RallyCue({
    required this.distanceKm,
    required this.lat,
    required this.lng,
    required this.type,
    required this.description,
  });
}

/// Navigation engine that processes past activities to guide the user.
///
/// Compiles a "roadbook" of turns by analyzing bearing differences, and evaluates
/// user cross-track errors to trigger off-route warnings.
///
/// The reference track is first resampled to [resampleSpacingMeters] so GPS jitter and duplicate
/// fixes cannot produce bogus turn cues. Matching the user to the route is forward-biased around
/// the last matched position: on an out-and-back route the outbound and return legs overlap, and a
/// global nearest-point search would jump straight to the return leg.
class RallyNavigationEngine {
  /// The collection of reference coordinates.
  final List<Map<String, dynamic>> referencePoints;

  /// Minimum spacing between resampled route vertices.
  static const double resampleSpacingMeters = 25.0;

  /// Cross-track distance beyond which the user is considered off-route.
  static const double offRouteMeters = 50.0;

  /// The generated list of milestones and turns.
  List<RallyCue> cues = [];

  /// Total distance of the reference route in kilometers.
  double totalReferenceDistanceKm = 0.0;

  // Resampled route: coordinates and cumulative distance (km) at each vertex.
  final List<double> _lat = [];
  final List<double> _lng = [];
  final List<double> _cumKm = [];
  int _matchedIdx = 0;

  /// Instantiates a new navigation engine and generates the list of roadbook cues.
  RallyNavigationEngine({required this.referencePoints}) {
    _resample();
    _generateRallyCues();
  }

  double _toRadians(double degree) => degree * pi / 180.0;
  double _toDegrees(double radian) => radian * 180.0 / pi;

  /// Calculates the Haversine distance between two sets of coordinates.
  double _distanceBetween(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - cos((lat2 - lat1) * p) / 2 +
          cos(lat1 * p) * cos(lat2 * p) *
          (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // km
  }

  /// Computes the initial bearing angle from point 1 to point 2.
  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final rLat1 = _toRadians(lat1);
    final rLat2 = _toRadians(lat2);
    final dLon = _toRadians(lon2 - lon1);

    final y = sin(dLon) * cos(rLat2);
    final x = cos(rLat1) * sin(rLat2) - sin(rLat1) * cos(rLat2) * cos(dLon);
    final brng = atan2(y, x);
    return (_toDegrees(brng) + 360) % 360;
  }

  /// Drops vertices closer than [resampleSpacingMeters] to the previous kept vertex.
  void _resample() {
    for (final p in referencePoints) {
      final lat = (p['lat'] as num).toDouble();
      final lng = (p['lng'] as num).toDouble();
      if (_lat.isEmpty) {
        _lat.add(lat);
        _lng.add(lng);
        _cumKm.add(0.0);
        continue;
      }
      final d = _distanceBetween(_lat.last, _lng.last, lat, lng);
      if (d * 1000 < resampleSpacingMeters) continue;
      _lat.add(lat);
      _lng.add(lng);
      _cumKm.add(_cumKm.last + d);
    }
    // Always keep the true end of the route.
    if (referencePoints.length > 1) {
      final last = referencePoints.last;
      final lat = (last['lat'] as num).toDouble();
      final lng = (last['lng'] as num).toDouble();
      if (_lat.last != lat || _lng.last != lng) {
        _cumKm.add(_cumKm.last + _distanceBetween(_lat.last, _lng.last, lat, lng));
        _lat.add(lat);
        _lng.add(lng);
      }
    }
    totalReferenceDistanceKm = _cumKm.isEmpty ? 0.0 : _cumKm.last;
  }

  /// Processes the resampled route to identify turns and construct cues.
  void _generateRallyCues() {
    cues.clear();
    if (_lat.length < 2) return;

    // 1. Identify starting point
    cues.add(RallyCue(
      distanceKm: 0.0,
      lat: _lat.first,
      lng: _lng.first,
      type: TurnType.straight,
      description: "START ROUTE",
    ));

    // 2. Identify turns by checking change in bearings
    for (int i = 1; i < _lat.length - 1; i++) {
      final b1 = _calculateBearing(_lat[i - 1], _lng[i - 1], _lat[i], _lng[i]);
      final b2 = _calculateBearing(_lat[i], _lng[i], _lat[i + 1], _lng[i + 1]);

      double diff = b2 - b1;
      if (diff > 180) diff -= 360;
      if (diff < -180) diff += 360;

      // Turn threshold triggers
      if (diff.abs() >= 35.0) {
        TurnType type;
        String desc;
        if (diff.abs() >= 150.0) {
          type = TurnType.uTurn;
          desc = "U-TURN";
        } else if (diff > 0) {
          type = diff >= 70.0 ? TurnType.sharpRight : TurnType.right;
          desc = diff >= 70.0 ? "SHARP RIGHT" : "RIGHT TURN";
        } else {
          type = diff <= -70.0 ? TurnType.sharpLeft : TurnType.left;
          desc = diff <= -70.0 ? "SHARP LEFT" : "LEFT TURN";
        }

        cues.add(RallyCue(
          distanceKm: _cumKm[i],
          lat: _lat[i],
          lng: _lng[i],
          type: type,
          description: desc,
        ));
      }
    }

    cues.add(RallyCue(
      distanceKm: totalReferenceDistanceKm,
      lat: _lat.last,
      lng: _lng.last,
      type: TurnType.arrival,
      description: "GOAL DESTINATION",
    ));
  }

  /// Distance (m) from the user to segment [i]..[i+1], and the fraction along it (0..1).
  ({double meters, double t}) _segmentDistance(int i, double userLat, double userLng) {
    // Local equirectangular projection around the user (metres); accurate at these scales.
    const mPerDegLat = 111320.0;
    final mPerDegLng = 111320.0 * cos(_toRadians(userLat));
    final ax = (_lng[i] - userLng) * mPerDegLng, ay = (_lat[i] - userLat) * mPerDegLat;
    final bx = (_lng[i + 1] - userLng) * mPerDegLng, by = (_lat[i + 1] - userLat) * mPerDegLat;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    final t = len2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
    final px = ax + t * dx, py = ay + t * dy;
    return (meters: sqrt(px * px + py * py), t: t);
  }

  /// Best matching segment in [from, to): returns (index, distance m, t).
  ({int idx, double meters, double t}) _bestSegment(int from, int to, double userLat, double userLng) {
    int bestIdx = from;
    double bestM = double.maxFinite;
    double bestT = 0.0;
    for (int i = from; i < to; i++) {
      final seg = _segmentDistance(i, userLat, userLng);
      if (seg.meters < bestM) {
        bestM = seg.meters;
        bestIdx = i;
        bestT = seg.t;
      }
    }
    return (idx: bestIdx, meters: bestM, t: bestT);
  }

  /// Evaluates user position against the reference path and updates navigation instruction states.
  RallyNavigationState updateNavigation(double userLat, double userLng) {
    if (_lat.isEmpty) {
      return RallyNavigationState(
        isOffRoute: false,
        distanceToNextCueMeters: 0,
        nextCue: null,
      );
    }
    if (_lat.length == 1) {
      final d = _distanceBetween(userLat, userLng, _lat.first, _lng.first) * 1000;
      return RallyNavigationState(
        isOffRoute: d > offRouteMeters,
        distanceToNextCueMeters: d.round(),
        nextCue: cues.isNotEmpty ? cues.last : null,
        offRouteMeters: d,
      );
    }

    final segCount = _lat.length - 1;

    // 1. Forward-biased window around the last match (~0.25 km back, ~2 km ahead).
    final from = max(0, _matchedIdx - 10);
    final to = min(segCount, _matchedIdx + 80);
    var match = _bestSegment(from, to, userLat, userLng);

    // 2. Lost (e.g. GPS gap or shortcut): global search, preferring progress ahead of us.
    if (match.meters > offRouteMeters) {
      final global = _bestSegment(0, segCount, userLat, userLng);
      final ahead = _matchedIdx < segCount ? _bestSegment(_matchedIdx, segCount, userLat, userLng) : global;
      match = ahead.meters <= offRouteMeters ? ahead : global;
    }
    _matchedIdx = match.idx;

    // 3. Progress along the route and next cue.
    final progressKm = _cumKm[match.idx] + (_cumKm[match.idx + 1] - _cumKm[match.idx]) * match.t;

    RallyCue? nextCue;
    for (final cue in cues) {
      if (cue.distanceKm > progressKm + 0.001) {
        nextCue = cue;
        break;
      }
    }
    // If no upcoming cues, default to final destination node
    nextCue ??= cues.isNotEmpty ? cues.last : null;

    final distToCueMeters = nextCue == null ? 0 : max(0, ((nextCue.distanceKm - progressKm) * 1000).round());

    return RallyNavigationState(
      isOffRoute: match.meters > offRouteMeters,
      distanceToNextCueMeters: distToCueMeters,
      nextCue: nextCue,
      offRouteMeters: match.meters,
      progressKm: progressKm,
    );
  }
}

/// Represents the real-time evaluation of user alignment against the guide route.
class RallyNavigationState {
  /// Set to true if the user's distance from the reference line exceeds 50 meters.
  final bool isOffRoute;

  /// Estimated distance to the upcoming checkpoint in meters.
  final int distanceToNextCueMeters;

  /// The next upcoming cue.
  final RallyCue? nextCue;

  /// Cross-track distance from the reference route in meters.
  final double offRouteMeters;

  /// Distance travelled along the reference route in km.
  final double progressKm;

  /// Creates a new [RallyNavigationState] instance.
  RallyNavigationState({
    required this.isOffRoute,
    required this.distanceToNextCueMeters,
    required this.nextCue,
    this.offRouteMeters = 0.0,
    this.progressKm = 0.0,
  });
}

