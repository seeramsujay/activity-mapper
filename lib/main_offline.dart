import 'app.dart';

/// Pure 100% Offline Flavor Entry Point.
/// Zero network telemetry, zero cloud dependencies, 100% local SQLite WAL execution.
void main() => runTurnBackApp(title: 'TurnBack (Offline)', isOfflineOnly: true);
