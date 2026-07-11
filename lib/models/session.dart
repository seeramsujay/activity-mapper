/// The lifecycle status of a tracking session.
enum SessionStatus {
  /// The session is currently actively logging coordinate points.
  active,

  /// The session is paused; coordinates are not being appended.
  paused,

  /// The session is finalized and saved.
  completed
}

/// Represents an activity tracking run (session) configured by the user.
///
/// Holds the duration targets, buffers, active state, start/end timestamps,
/// and current status of the workout.
class Session {
  /// Unique auto-increment identifier in the database.
  final int? id;

  /// The total time allocated for the entire workout.
  final Duration targetDuration;

  /// The safety buffer percentage used to calculate the turnaround outbound limit.
  final double safetyBufferPct;

  /// The time the session was started.
  final DateTime startTime;

  /// The time the session was finished.
  final DateTime? endTime;

  /// The current tracking status of this session.
  final SessionStatus status;

  /// Creates a new [Session] instance.
  Session({
    this.id,
    required this.targetDuration,
    required this.safetyBufferPct,
    required this.startTime,
    this.endTime,
    required this.status,
  });

  /// Converts this [Session] instance into an SQLite database-friendly map.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'target_duration': targetDuration.inSeconds,
      'safety_buffer': safetyBufferPct,
      'start_time': startTime.millisecondsSinceEpoch,
      'end_time': endTime?.millisecondsSinceEpoch,
      'status': status.name,
    };
  }

  /// Reconstructs a [Session] from an SQLite query database row map.
  factory Session.fromMap(Map<String, dynamic> map) {
    return Session(
      id: map['id'] as int?,
      targetDuration: Duration(seconds: map['target_duration'] as int),
      safetyBufferPct: map['safety_buffer'] as double,
      startTime: DateTime.fromMillisecondsSinceEpoch(map['start_time'] as int),
      endTime: map['end_time'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['end_time'] as int)
          : null,
      status: SessionStatus.values.byName(map['status'] as String),
    );
  }
}

