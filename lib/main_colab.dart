import 'app.dart';

/// Collaborative P2P Group Tracking Flavor Entry Point.
/// Adds the LAN/hotspot UDP mesh and QR-key handshake on top of the offline tracker.
void main() => runTurnBackApp(title: 'TurnBack (Colab)', isOfflineOnly: false);
