enum SessionStatus { active, paused, completed }

class Session {
  final int? id;
  final Duration targetDuration;
  final double safetyBufferPct;
  final DateTime startTime;
  final DateTime? endTime;
  final SessionStatus status;

  Session({
    this.id,
    required this.targetDuration,
    required this.safetyBufferPct,
    required this.startTime,
    this.endTime,
    required this.status,
  });

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
