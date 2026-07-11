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
class RallyNavigationEngine {
  /// The collection of reference coordinates.
  final List<Map<String, dynamic>> referencePoints;

  /// The generated list of milestones and turns.
  List<RallyCue> cues = [];

  /// Total distance of the reference route in kilometers.
  double totalReferenceDistanceKm = 0.0;

  /// Instantiates a new navigation engine and generates the list of roadbook cues.
  RallyNavigationEngine({required this.referencePoints}) {
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

  /// Processes the reference coordinates array to identify turns and construct cues.
  void _generateRallyCues() {
    if (referencePoints.length < 3) return;

    double accumulatedDist = 0.0;
    cues.clear();

    // 1. Identify starting point
    cues.add(RallyCue(
      distanceKm: 0.0,
      lat: referencePoints.first['lat'] as double,
      lng: referencePoints.first['lng'] as double,
      type: TurnType.straight,
      description: "START ROUTE",
    ));

    // 2. Identify turns by checking change in bearings
    for (int i = 1; i < referencePoints.length - 1; i++) {
      final prev = referencePoints[i - 1];
      final curr = referencePoints[i];
      final next = referencePoints[i + 1];

      final dist = _distanceBetween(
        prev['lat'] as double,
        prev['lng'] as double,
        curr['lat'] as double,
        curr['lng'] as double,
      );
      accumulatedDist += dist;

      final b1 = _calculateBearing(
        prev['lat'] as double,
        prev['lng'] as double,
        curr['lat'] as double,
        curr['lng'] as double,
      );
      final b2 = _calculateBearing(
        curr['lat'] as double,
        curr['lng'] as double,
        next['lat'] as double,
        next['lng'] as double,
      );

      double diff = b2 - b1;
      if (diff > 180) diff -= 360;
      if (diff < -180) diff += 360;

      // Turn threshold triggers
      if (diff.abs() >= 35.0) {
        TurnType type;
        String desc;
        if (diff > 0) {
          type = diff >= 70.0 ? TurnType.sharpRight : TurnType.right;
          desc = diff >= 70.0 ? "SHARP RIGHT" : "RIGHT TURN";
        } else {
          type = diff <= -70.0 ? TurnType.sharpLeft : TurnType.left;
          desc = diff <= -70.0 ? "SHARP LEFT" : "LEFT TURN";
        }

        cues.add(RallyCue(
          distanceKm: accumulatedDist,
          lat: curr['lat'] as double,
          lng: curr['lng'] as double,
          type: type,
          description: desc,
        ));
      }
    }

    // Add final endpoint
    final last = referencePoints.last;
    accumulatedDist += _distanceBetween(
      referencePoints[referencePoints.length - 2]['lat'] as double,
      referencePoints[referencePoints.length - 2]['lng'] as double,
      last['lat'] as double,
      last['lng'] as double,
    );
    totalReferenceDistanceKm = accumulatedDist;

    cues.add(RallyCue(
      distanceKm: totalReferenceDistanceKm,
      lat: last['lat'] as double,
      lng: last['lng'] as double,
      type: TurnType.arrival,
      description: "GOAL DESTINATION",
    ));
  }

  /// Evaluates user position against the reference path and updates navigation instruction states.
  RallyNavigationState updateNavigation(double userLat, double userLng) {
    if (referencePoints.isEmpty) {
      return RallyNavigationState(
        isOffRoute: false,
        distanceToNextCueMeters: 0,
        nextCue: null,
      );
    }

    // 1. Find closest coordinate point on the reference line
    double minDistance = double.maxFinite;
    int closestIdx = 0;

    for (int i = 0; i < referencePoints.length; i++) {
      final p = referencePoints[i];
      final dist = _distanceBetween(userLat, userLng, p['lat'] as double, p['lng'] as double);
      if (dist < minDistance) {
        minDistance = dist;
        closestIdx = i;
      }
    }

    // 2. Off-Route safety alarm (User drifted by more than 50 meters)
    final bool isOff = minDistance > 0.05; // 0.05 km = 50 meters

    // 3. Estimate user's accumulated distance along reference path
    double userAccumulatedDistKm = 0.0;
    for (int i = 1; i <= closestIdx; i++) {
      userAccumulatedDistKm += _distanceBetween(
        referencePoints[i - 1]['lat'] as double,
        referencePoints[i - 1]['lng'] as double,
        referencePoints[i]['lat'] as double,
        referencePoints[i]['lng'] as double,
      );
    }

    // 4. Locate the next upcoming rally cue
    RallyCue? nextCue;
    for (final cue in cues) {
      if (cue.distanceKm > userAccumulatedDistKm) {
        nextCue = cue;
        break;
      }
    }

    // If no upcoming cues, default to final destination node
    nextCue ??= cues.isNotEmpty ? cues.last : null;

    int distToCueMeters = 0;
    if (nextCue != null) {
      // Calculate direct distance or path distance to cue
      final distKm = nextCue.distanceKm - userAccumulatedDistKm;
      distToCueMeters = max(0, (distKm * 1000).toInt());
    }

    return RallyNavigationState(
      isOffRoute: isOff,
      distanceToNextCueMeters: distToCueMeters,
      nextCue: nextCue,
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

  /// Creates a new [RallyNavigationState] instance.
  RallyNavigationState({
    required this.isOffRoute,
    required this.distanceToNextCueMeters,
    required this.nextCue,
  });
}

