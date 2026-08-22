import 'package:flutter/material.dart';
import 'services/db_service.dart';
import 'services/settings_service.dart';
import 'screens/setup_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';

/// Collaborative P2P Group Tracking & Cloud Sync Flavor Entry Point.
/// Features wide-area E2EE UDP mesh, QR-key handshake, Strava direct upload, and Relive 3D bridge.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  Map<String, dynamic>? activeSession;
  try {
    final dbHelper = DbService.instance;
    await dbHelper.database;
    activeSession = await dbHelper.getActiveSession();
  } catch (e, stack) {
    debugPrint("Startup Colab DB initialization error: $e\n$stack");
  }
  
  runApp(const TurnBackColabApp());
}

/// The root Widget of the TurnBack Colab application.
class TurnBackColabApp extends StatelessWidget {
  const TurnBackColabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SettingsService.instance,
      builder: (context, _) {
        final currentTheme = SettingsService.instance.getThemeData(context);
        return MaterialApp(
          title: 'TurnBack (Colab)',
          debugShowCheckedModeBanner: false,
          theme: currentTheme,
          darkTheme: currentTheme,
          themeMode: ThemeMode.dark,
          home: const SetupScreen(isOfflineOnly: false),
          routes: {
            '/setup': (context) => const SetupScreen(isOfflineOnly: false),
            '/history': (context) => const HistoryScreen(),
            '/settings': (context) => const SettingsScreen(),
          },
        );
      },
    );
  }
}
