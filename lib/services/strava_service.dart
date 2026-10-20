import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Represents the processing state of an activity upload to Strava.
enum StravaUploadState {
  idle,
  authorizing,
  uploading,
  processing,
  completed,
  error,
}

/// Result payload returned from a Strava activity upload attempt.
class StravaUploadResult {
  final bool success;
  final String? uploadId;
  final int? activityId;
  final String? externalId;
  final String? statusMessage;
  final String? error;

  const StravaUploadResult({
    required this.success,
    this.uploadId,
    this.activityId,
    this.externalId,
    this.statusMessage,
    this.error,
  });

  String get stravaActivityUrl =>
      activityId != null ? 'https://www.strava.com/activities/$activityId' : '';
}

/// Service handling direct 1-tap OAuth2 uploading of workouts to the Strava Activity API.
///
/// Implements standard Strava API v3 file upload specification with support for GPX and TCX files.
class StravaService extends ChangeNotifier {
  static final StravaService instance = StravaService._internal();
  StravaService._internal();

  static const String stravaApiBase = 'https://www.strava.com/api/v3';
  static const String stravaUploadUrl = '$stravaApiBase/uploads';

  String? _accessToken;
  String? _athleteName;
  StravaUploadState _state = StravaUploadState.idle;
  String _statusText = '';

  bool get isAuthenticated => _accessToken != null && _accessToken!.isNotEmpty;
  String? get athleteName => _athleteName;
  StravaUploadState get state => _state;
  String get statusText => _statusText;

  /// Sets or updates the active Strava OAuth2 access token.
  void setAccessToken(String token, {String? athleteName}) {
    _accessToken = token;
    _athleteName = athleteName ?? 'Strava Athlete';
    notifyListeners();
  }

  /// Clears stored Strava credentials.
  void logout() {
    _accessToken = null;
    _athleteName = null;
    _state = StravaUploadState.idle;
    _statusText = '';
    notifyListeners();
  }

  /// Uploads a GPX or TCX file to Strava Activity API v3.
  Future<StravaUploadResult> uploadActivity({
    required String fileContent,
    required String fileName,
    required String activityName,
    required String activityType, // 'run', 'ride', 'walk', 'hike'
    String? description,
    bool isCommute = false,
    bool isTrainer = false,
  }) async {
    _state = StravaUploadState.uploading;
    _statusText = 'Preparing Strava upload package...';
    notifyListeners();

    final dataFormat = fileName.toLowerCase().endsWith('.tcx') ? 'tcx' : 'gpx';
    final stravaSport = _mapActivityTypeToStrava(activityType);

    try {
      if (!isAuthenticated) {
        // There is no in-app OAuth flow (it needs a client secret held on a server), so without
        // a token we must not pretend the upload happened.
        _state = StravaUploadState.error;
        _statusText = 'Not connected to Strava';
        notifyListeners();
        return const StravaUploadResult(
          success: false,
          error: 'Not connected to Strava. Export the activity as TCX or GPX and upload it at '
              'strava.com/upload instead.',
        );
      }

      // Real live multipart HTTP upload when token is provided
      _statusText = 'Transmitting telemetry to Strava API v3...';
      notifyListeners();

      final client = HttpClient();
      try {
        final request = await client.postUrl(Uri.parse(stravaUploadUrl));
      
        final boundary = '----TurnBackBoundary${DateTime.now().millisecondsSinceEpoch}';
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_accessToken');
        request.headers.set(HttpHeaders.contentTypeHeader, 'multipart/form-data; boundary=$boundary');

        final bodyBuffer = StringBuffer();
      
        // Activity Name
        bodyBuffer.write('--$boundary\r\n');
        bodyBuffer.write('Content-Disposition: form-data; name="name"\r\n');
        bodyBuffer.write('\r\n');
        bodyBuffer.write('$activityName\r\n');

        // Activity Type
        bodyBuffer.write('--$boundary\r\n');
        bodyBuffer.write('Content-Disposition: form-data; name="activity_type"\r\n');
        bodyBuffer.write('\r\n');
        bodyBuffer.write('$stravaSport\r\n');

        // Data format
        bodyBuffer.write('--$boundary\r\n');
        bodyBuffer.write('Content-Disposition: form-data; name="data_type"\r\n');
        bodyBuffer.write('\r\n');
        bodyBuffer.write('$dataFormat\r\n');

        // Description
        if (description != null && description.isNotEmpty) {
          bodyBuffer.write('--$boundary\r\n');
          bodyBuffer.write('Content-Disposition: form-data; name="description"\r\n');
          bodyBuffer.write('\r\n');
          bodyBuffer.write('$description\r\n');
        }

        // Commute & Trainer flags
        bodyBuffer.write('--$boundary\r\n');
        bodyBuffer.write('Content-Disposition: form-data; name="commute"\r\n');
        bodyBuffer.write('\r\n');
        bodyBuffer.write('${isCommute ? '1' : '0'}\r\n');

        bodyBuffer.write('--$boundary\r\n');
        bodyBuffer.write('Content-Disposition: form-data; name="trainer"\r\n');
        bodyBuffer.write('\r\n');
        bodyBuffer.write('${isTrainer ? '1' : '0'}\r\n');

        // File Payload
        bodyBuffer.write('--$boundary\r\n');
        bodyBuffer.write('Content-Disposition: form-data; name="file"; filename="$fileName"\r\n');
        bodyBuffer.write('Content-Type: application/octet-stream\r\n');
        bodyBuffer.write('\r\n');
        bodyBuffer.write(fileContent);
        bodyBuffer.write('\r\n');
        bodyBuffer.write('--$boundary--\r\n');

        request.add(utf8.encode(bodyBuffer.toString()));
        final response = await request.close();
        final responseBody = await response.transform(utf8.decoder).join();

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final json = jsonDecode(responseBody) as Map<String, dynamic>;
          final uploadId = json['id_str']?.toString() ?? json['id']?.toString();
          final actId = json['activity_id'] as int?;

          // Strava processes uploads asynchronously; activity_id is usually null at this point.
          _state = StravaUploadState.completed;
          _statusText = actId != null ? 'Uploaded to Strava successfully!' : 'Upload received; Strava is processing it.';
          notifyListeners();

          return StravaUploadResult(
            success: true,
            uploadId: uploadId,
            activityId: actId,
            externalId: fileName,
            statusMessage: json['status'] as String? ?? 'Your activity is processing on Strava.',
          );
        } else {
          _state = StravaUploadState.error;
          _statusText = 'Strava Upload Failed (HTTP ${response.statusCode})';
          notifyListeners();
          return StravaUploadResult(
            success: false,
            error: 'Strava Error: $responseBody',
          );
        }
      } finally {
        client.close();
      }
    } catch (e) {
      _state = StravaUploadState.error;
      _statusText = 'Upload failed: $e';
      notifyListeners();
      return StravaUploadResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  String _mapActivityTypeToStrava(String activityType) {
    switch (activityType.toLowerCase()) {
      case 'cycling':
      case 'ride':
      case 'bike':
        return 'Ride';
      case 'walk':
        return 'Walk';
      case 'hike':
      case 'trek':
        return 'Hike';
      case 'run':
      case 'fitness':
      default:
        return 'Run';
    }
  }
}
